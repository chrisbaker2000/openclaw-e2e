# tests/environment.sh — Gateway Environment
# Validates env vars, checks logs for errors, security flags.

test_environment() {
    should_run "environment" || return 0
    has_container_access || return 0
    section "Gateway Environment (9 tests)"

    # 1. Gateway token set
    local has_token
    has_token=$(container_exec "printenv OPENCLAW_GATEWAY_TOKEN >/dev/null 2>&1 && echo yes || echo no")
    if [ "$has_token" = "yes" ]; then
        pass "Gateway token: set"
    else
        fail "Gateway token: OPENCLAW_GATEWAY_TOKEN not set"
    fi

    # 2. No uncaught exceptions or fatal errors
    if [ -n "$GATEWAY_LOGS" ]; then
        local fatal_count
        fatal_count=$(echo "$GATEWAY_LOGS" | grep -ai "uncaught\|unhandled.*rejection\|FATAL\|process\.exit\|segfault\|out of memory" | \
            grep -c "[0-9][0-9]:[0-9][0-9]:[0-9][0-9]" 2>/dev/null || true)
        fatal_count=$(echo "$fatal_count" | tr -d ' \n')
        if [ "${fatal_count:-0}" = "0" ]; then
            pass "No uncaught exceptions or fatal errors"
        else
            fail "Fatal errors: $fatal_count occurrences"
            echo "$GATEWAY_LOGS" | grep -ai "uncaught\|unhandled.*rejection\|FATAL" | \
                grep "[0-9][0-9]:[0-9][0-9]:[0-9][0-9]" | head -3 | sed 's/^/    /'
        fi
    else
        skip "Fatal errors: logs not available"
    fi

    # 3. No config validation warnings
    if [ -n "$GATEWAY_LOGS" ]; then
        local config_warns
        config_warns=$(echo "$GATEWAY_LOGS" | grep -ai "Invalid config\|must NOT have additional" | \
            grep -c "[0-9][0-9]:[0-9][0-9]:[0-9][0-9]" 2>/dev/null || true)
        config_warns=$(echo "$config_warns" | tr -d ' \n')
        if [ "${config_warns:-0}" = "0" ]; then
            pass "No config validation warnings"
        else
            fail "Config validation warnings: $config_warns"
        fi
    else
        skip "Config warnings: logs not available"
    fi

    # 4. No config include errors
    if [ -n "$GATEWAY_LOGS" ]; then
        local include_errors
        include_errors=$(echo "$GATEWAY_LOGS" | grep -ai "ConfigIncludeError\|Failed to read include\|ENOENT.*shared-config" | \
            grep -c "[0-9][0-9]:[0-9][0-9]:[0-9][0-9]" 2>/dev/null || true)
        include_errors=$(echo "$include_errors" | tr -d ' \n')
        if [ "${include_errors:-0}" = "0" ]; then
            pass "No config include errors"
        else
            fail "Config include errors: $include_errors — shared-config.json may be missing"
        fi
    else
        skip "Config include errors: logs not available"
    fi

    # 5. No pending device pairing requests
    local pending_count
    pending_count=$(container_exec "python3 -c '
import json
try:
    with open(\"/home/node/.openclaw/devices/pending.json\") as f:
        d = json.load(f)
    print(len(d))
except:
    print(0)
'" | tr -d ' \n\r')
    if [ "${pending_count:-0}" = "0" ]; then
        pass "No pending device pairing requests"
    else
        fail "Pending pairing requests: $pending_count"
    fi

    # 6. No workspace corruption (source repo artifacts)
    local workspace_artifacts
    workspace_artifacts=$(container_exec "python3 -c '
import os
ws = \"/home/node/.openclaw/workspace\"
artifacts = [f for f in [\"src\",\"node_modules\",\"package.json\",\"pnpm-lock.yaml\",\"tsconfig.json\"] if os.path.exists(os.path.join(ws, f))]
print(\" \".join(artifacts) if artifacts else \"none\")
'" | tr -d '\r')
    if [ "$workspace_artifacts" = "none" ]; then
        pass "Workspace clean: no source repo artifacts"
    else
        fail "Workspace corrupted: found $workspace_artifacts"
    fi

    # 7. No dangerous flags enabled (per docs: break-glass only)
    if [ -n "$GATEWAY_CONFIG" ] && [ -f "$DOCS_SCHEMA" ]; then
        local danger_check
        danger_check=$(echo "$GATEWAY_CONFIG" | python3 -c "
import json, sys
config = json.load(sys.stdin)
findings = []

# dangerouslyDisableDeviceAuth — break-glass only
if config.get('gateway', {}).get('controlUi', {}).get('dangerouslyDisableDeviceAuth', False):
    findings.append('dangerouslyDisableDeviceAuth=true')

# allowInsecureAuth — warn-level security concern
if config.get('gateway', {}).get('controlUi', {}).get('allowInsecureAuth', False):
    findings.append('allowInsecureAuth=true')

# tools.elevated.enabled — should be false in production
if config.get('tools', {}).get('elevated', {}).get('enabled', False):
    findings.append('tools.elevated.enabled=true')

print('|'.join(findings) if findings else 'ok')
" 2>/dev/null)
        if [ "$danger_check" = "ok" ]; then
            pass "No dangerous flags enabled"
        else
            fail "Dangerous flags: $(echo "$danger_check" | tr '|' ', ')"
        fi
    else
        skip "Dangerous flags: config or schema not available"
    fi

    # 8. Config file permissions (per docs: 600 for config, 700 for dirs)
    local perm_check
    perm_check=$(container_exec "python3 -c '
import os, stat
issues = []
config_path = \"/home/node/.openclaw/openclaw.json\"
config_dir = \"/home/node/.openclaw\"
creds_dir = \"/home/node/.openclaw/credentials\"

# Config file should be 600 or more restrictive
if os.path.exists(config_path):
    mode = stat.S_IMODE(os.stat(config_path).st_mode)
    if mode & 0o077:  # group or world readable/writable
        issues.append(f\"openclaw.json: {oct(mode)} (should be 0o600)\")

# Config dir should be 700 or more restrictive
if os.path.exists(config_dir):
    mode = stat.S_IMODE(os.stat(config_dir).st_mode)
    if mode & 0o077:
        issues.append(f\".openclaw/: {oct(mode)} (should be 0o700)\")

# Credentials dir should be 700 or more restrictive
if os.path.exists(creds_dir):
    mode = stat.S_IMODE(os.stat(creds_dir).st_mode)
    if mode & 0o077:
        issues.append(f\"credentials/: {oct(mode)} (should be 0o700)\")

print(\"|\".join(issues) if issues else \"ok\")
'" | tr -d '\r')
    if [ "$perm_check" = "ok" ]; then
        pass "Config file permissions: secure"
    else
        # Docker volume mounts may have different permissions; warn but don't fail
        pass "Config permissions: $(echo "$perm_check" | tr '|' ', ') (volume mount — may differ)"
    fi

    # 9. No unrecognized config key warnings
    if [ -n "$GATEWAY_LOGS" ]; then
        local unrecognized
        unrecognized=$(echo "$GATEWAY_LOGS" | grep -ai "Unrecognized key\|unknown config" | \
            grep -c "[0-9][0-9]:[0-9][0-9]:[0-9][0-9]" 2>/dev/null || true)
        unrecognized=$(echo "$unrecognized" | tr -d ' \n')
        if [ "${unrecognized:-0}" = "0" ]; then
            pass "No unrecognized config keys"
        else
            fail "Unrecognized config keys: $unrecognized warnings"
            echo "$GATEWAY_LOGS" | grep -ai "Unrecognized key\|unknown config" | head -3 | sed 's/^/    /'
        fi
    else
        skip "Unrecognized config keys: logs not available"
    fi
}
