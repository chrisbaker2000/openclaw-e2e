# tests/context.sh — Context Optimization
# Validates that the workspace stays lean to minimize per-turn token overhead.
# Every .md file in the workspace root is injected into every agent turn.

test_context() {
    should_run "context" || return 0
    has_container_access || return 0
    section "Context Optimization (8 tests)"

    local WS="/home/node/.openclaw/workspace"

    # 1. Workspace root .md file count
    # Exclude LAST_CHAT_*.md (ephemeral per-user handoff files created by session-memory-bridge)
    local md_count
    md_count=$(container_exec "ls $WS/*.md 2>/dev/null | grep -v LAST_CHAT_ | wc -l" | tr -d ' \n\r')
    if [ "${md_count:-0}" -le "$OPENCLAW_MAX_WORKSPACE_MD_FILES" ] 2>/dev/null; then
        pass "Workspace .md count: $md_count (max $OPENCLAW_MAX_WORKSPACE_MD_FILES)"
    else
        fail "Workspace .md count: $md_count (max $OPENCLAW_MAX_WORKSPACE_MD_FILES) — stale docs bloating context"
    fi

    # 2. Total workspace root .md size
    local total_bytes
    total_bytes=$(container_exec "python3 -c '
import os
d = \"$WS\"
total = sum(
    os.path.getsize(os.path.join(d, f))
    for f in os.listdir(d)
    if f.endswith(\".md\") and not f.startswith(\"LAST_CHAT_\") and os.path.isfile(os.path.join(d, f))
)
print(total)
'" | tr -d ' \n\r')
    if [ "${total_bytes:-999999}" -le "$OPENCLAW_MAX_WORKSPACE_MD_BYTES" ] 2>/dev/null; then
        pass "Workspace .md total: ${total_bytes} bytes (max $OPENCLAW_MAX_WORKSPACE_MD_BYTES)"
    else
        fail "Workspace .md total: ${total_bytes:-unknown} bytes (max $OPENCLAW_MAX_WORKSPACE_MD_BYTES) — trim large docs"
    fi

    # 3. No README.md in workspace root (upstream project README can waste ~27K tokens)
    local has_readme
    has_readme=$(container_exec "test -f $WS/README.md && echo yes || echo no" | tr -d ' \n\r')
    if [ "$has_readme" = "no" ]; then
        pass "No README.md in workspace root"
    else
        fail "README.md in workspace root — may waste thousands of tokens per turn"
    fi

    # 4. No BOOTSTRAP.md (only needed during first-run onboarding)
    local has_bootstrap
    has_bootstrap=$(container_exec "test -f $WS/BOOTSTRAP.md && echo yes || echo no" | tr -d ' \n\r')
    if [ "$has_bootstrap" = "no" ]; then
        pass "No BOOTSTRAP.md (post-setup, not needed)"
    else
        fail "BOOTSTRAP.md in workspace root — delete it after initial setup"
    fi

    # 5. Detect non-framework stale .md files
    local framework_files
    framework_files="$OPENCLAW_FRAMEWORK_MD_FILES"
    local stale_docs
    stale_docs=$(container_exec "python3 -c '
import os
ws = \"$WS\"
framework = set(\"$framework_files\".split(\",\"))
extra = [
    f for f in os.listdir(ws)
    if f.endswith(\".md\")
    and os.path.isfile(os.path.join(ws, f))
    and not f.startswith(\"LAST_CHAT_\")
    and f not in framework
]
print(\" \".join(sorted(extra)))
'" | tr -d '\r\n')
    if [ -z "$stale_docs" ]; then
        pass "No non-framework .md files in workspace root"
    else
        fail "Stale docs in workspace: $stale_docs — move to a subdirectory"
    fi

    # 6. Bootstrap token estimation (bytes / 4 ≈ tokens)
    local bootstrap_tokens
    bootstrap_tokens=$(container_exec "python3 -c '
import os
ws = \"$WS\"
framework = \"$framework_files\".split(\",\")
total = 0
for f in framework:
    fp = os.path.join(ws, f)
    if os.path.islink(fp):
        fp = os.path.join(ws, os.readlink(fp))
    if os.path.exists(fp):
        total += os.path.getsize(fp)
print(total // 4)
'" | tr -d ' \n\r')
    if [ "${bootstrap_tokens:-9999}" -le "$OPENCLAW_MAX_BOOTSTRAP_TOKENS" ] 2>/dev/null; then
        pass "Bootstrap tokens: ~${bootstrap_tokens} (max $OPENCLAW_MAX_BOOTSTRAP_TOKENS)"
    else
        fail "Bootstrap tokens: ~${bootstrap_tokens:-unknown} (max $OPENCLAW_MAX_BOOTSTRAP_TOKENS) — workspace docs too large"
    fi

    # 7. humanDelay is 0/0 on gateway (no artificial typing delay = lower latency)
    if [ -n "$GATEWAY_CONFIG" ]; then
        local delay_check
        delay_check=$(echo "$GATEWAY_CONFIG" | python3 -c "
import json, sys
d = json.load(sys.stdin)
hd = d.get('agents',{}).get('defaults',{}).get('humanDelay',{})
minMs = hd.get('minMs', 0)
maxMs = hd.get('maxMs', 0)
if minMs == 0 and maxMs == 0:
    print('OK')
else:
    print('SLOW|min=%d max=%d' % (minMs, maxMs))
" 2>/dev/null | tr -d ' \n\r')
        if [ "$delay_check" = "OK" ]; then
            pass "humanDelay: 0ms/0ms (no artificial latency)"
        else
            fail "humanDelay: $delay_check — should be 0/0 on gateway for minimum latency"
        fi
    else
        skip "humanDelay: gateway config not available"
    fi

    # 8. Context headroom (budget minus actual usage)
    if [ -n "$total_bytes" ] && [ "$total_bytes" -gt 0 ] 2>/dev/null; then
        local headroom=$(( OPENCLAW_MAX_WORKSPACE_MD_BYTES - total_bytes ))
        if [ "$headroom" -ge 50 ] 2>/dev/null; then
            pass "Context headroom: ${headroom} bytes free (${total_bytes}/${OPENCLAW_MAX_WORKSPACE_MD_BYTES} used)"
        else
            fail "Context headroom: only ${headroom} bytes free — dangerously close to budget"
        fi
    else
        skip "Context headroom: could not measure workspace size"
    fi
}
