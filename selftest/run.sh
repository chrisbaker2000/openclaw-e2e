#!/bin/bash
# selftest/run.sh — offline tests for the harness itself (no gateway needed).
# Locks: env-over-.env precedence, thinking-level schema, manifest-candidate
# filtering, and the HTTP timeout on every curl in tests/.
set -uo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PASS=0
FAIL=0
FIX=$(mktemp -d)
trap 'rm -rf "$FIX"' EXIT

ok()  { PASS=$((PASS + 1)); echo "  PASS: $1"; }
bad() { FAIL=$((FAIL + 1)); echo "  FAIL: $1"; }

echo "1. .env precedence"
mkdir -p "$FIX/repo/lib"
cp "$REPO_DIR/lib/config.sh" "$FIX/repo/lib/"
printf 'OPENCLAW_GATEWAY_URL="http://from-dotenv:1"\nOPENCLAW_SSH_HOST="dotenv-host"\n' > "$FIX/repo/.env"
got=$(env -i PATH="$PATH" HOME="$HOME" OPENCLAW_GATEWAY_URL="http://from-env:2" \
  /bin/bash -c "source '$FIX/repo/lib/config.sh'; echo \"\$OPENCLAW_GATEWAY_URL|\$OPENCLAW_SSH_HOST\"")
# Regression: .env was sourced last and clobbered values passed in the environment.
[[ "$got" == "http://from-env:2|dotenv-host" ]] && ok "env var overrides .env; unset vars still come from .env" \
  || bad "precedence wrong: '$got'"
got=$(env -i PATH="$PATH" HOME="$HOME" /bin/bash -c "source '$FIX/repo/lib/config.sh'; echo \"\$OPENCLAW_GATEWAY_URL|\$OPENCLAW_HTTP_TIMEOUT\"")
[[ "$got" == "http://from-dotenv:1|30" ]] && ok ".env applies when env is unset; HTTP timeout defaults to 30" \
  || bad ".env-only load wrong: '$got'"

echo "2. Thinking levels match OpenClaw 2026.9 (ALL_THINKING_LEVELS)"
for section in agents cron; do
  if python3 -c "
import json, sys
levels = json.load(open(sys.argv[1]))[sys.argv[2]]['thinking_levels']
want = ['off', 'minimal', 'low', 'medium', 'high', 'xhigh', 'adaptive', 'max', 'ultra']
sys.exit(0 if levels == want else 1)" "$REPO_DIR/docs-schema.json" "$section"; then
    ok "$section.thinking_levels includes adaptive/max/ultra"
  else
    bad "$section.thinking_levels out of date"
  fi
done

echo "3. Plugin manifest check ignores non-plugin dirs"
ext="$FIX/oc/extensions"
mkdir -p "$ext/good" "$ext/node_modules/dep" "$ext/framework/lib" "$ext/broken"
echo '{"id": "good", "configSchema": {"type": "object"}}' > "$ext/good/openclaw.plugin.json"
echo '{"name": "broken"}' > "$ext/broken/package.json"
out=$(env -i PATH="$PATH" HOME="$HOME" OPENCLAW_NATIVE=true OPENCLAW_MAC_CONFIG_DIR="$FIX/oc" \
  OPENCLAW_GATEWAY_URL= /bin/bash -c "
    cd '$REPO_DIR'
    source lib/output.sh; source lib/config.sh; source lib/transport.sh; source tests/plugins.sh
    GATEWAY_LOGS=''
    test_plugins" 2>&1)
manifest_line=$(echo "$out" | grep -E 'manifest' | head -1)
# Regression: node_modules/ and framework/ (no manifest, no package.json) were reported as broken plugins.
if [[ "$manifest_line" == *"broken: missing manifest"* && "$manifest_line" != *node_modules* && "$manifest_line" != *framework* ]]; then
  ok "only the real plugin candidate without a manifest is flagged"
else
  bad "manifest check output: '$manifest_line'"
fi

echo "5. Native version probe ignores OPENCLAW_CONTAINER"
mkdir -p "$FIX/bin"
cat > "$FIX/bin/openclaw" <<'STUB'
#!/bin/bash
# Mimics the real CLI: an exported OPENCLAW_CONTAINER redirects it into a container.
if [ -n "${OPENCLAW_CONTAINER:-}" ]; then echo "No running container matched" >&2; exit 1; fi
echo "OpenClaw 2026.9.8 (fc23bc8)"
STUB
chmod +x "$FIX/bin/openclaw"
out=$(env -i PATH="$FIX/bin:$PATH" HOME="$HOME" OPENCLAW_NATIVE=true OPENCLAW_CONTAINER=openclaw-gateway \
  OPENCLAW_MAC_CONFIG_DIR="$FIX/oc" OPENCLAW_GATEWAY_URL= /bin/bash -c "
    cd '$REPO_DIR'
    source lib/output.sh; source lib/config.sh; source lib/transport.sh; source tests/core.sh
    GATEWAY_INSPECT=''; GATEWAY_STATS=''
    test_core" 2>&1)
# Regression: the exported container name broke `openclaw --version` in native mode.
[[ "$out" == *"Version: 2026.9.8"* ]] && ok "native mode reads the CLI version with OPENCLAW_CONTAINER exported" \
  || bad "native version probe: $(echo "$out" | grep -i version)"

echo "6. Channel liveness keeps the token out of curl argv"
cat > "$FIX/bin/curl" <<'STUB'
#!/bin/bash
printf '%s\n' "$@" > "$CURL_ARGV"
cat > "$CURL_STDIN"
echo '{"ok": true}'
STUB
chmod +x "$FIX/bin/curl"
res=$(echo '{"channels": {"slack": {"botToken": "xoxb-SELFTEST-SENTINEL"}}}' | \
  CURL_ARGV="$FIX/argv" CURL_STDIN="$FIX/stdin" PATH="$FIX/bin:$PATH" python3 "$REPO_DIR/lib/channel-liveness.py" slack)
# Regression: the bot token was passed as `-H "Authorization: Bearer <token>"` (visible in ps).
if [[ "$res" == "ok" ]] && ! grep -q SENTINEL "$FIX/argv" && grep -q 'Authorization: Bearer xoxb-SELFTEST-SENTINEL' "$FIX/stdin"; then
  ok "token sent via stdin header (-H @-), absent from argv"
else
  bad "liveness token handling: res='$res' argv=$(tr '\n' ' ' < "$FIX/argv" 2>/dev/null)"
fi

echo "4. Every curl in tests/ is time-bounded"
unbounded=$(grep -n 'curl ' "$REPO_DIR"/tests/*.sh | grep -v -- '--max-time' || true)
[[ -z "$unbounded" ]] && ok "all curl calls carry --max-time" || bad "unbounded curl calls:"$'\n'"$unbounded"

echo ""
echo "Results: ${PASS}/$((PASS + FAIL)) passed, ${FAIL} failed"
[[ $FAIL -eq 0 ]]
