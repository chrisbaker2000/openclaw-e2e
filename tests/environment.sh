# tests/environment.sh — Gateway Environment
# Validates env vars, checks logs for errors.

test_environment() {
    should_run "environment" || return 0
    has_container_access || return 0
    section "Gateway Environment (6 tests)"

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
}
