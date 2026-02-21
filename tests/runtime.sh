# tests/runtime.sh — Container Runtime
# Validates Node.js version and container stability.

test_runtime() {
    should_run "runtime" || return 0
    has_container_access || return 0
    section "Container Runtime (3 tests)"

    # 1. Node.js version >= 22
    local node_ver
    node_ver=$(container_exec "node --version")
    if [ -n "$node_ver" ]; then
        local major
        major=$(echo "$node_ver" | sed 's/v//' | cut -d. -f1)
        if [ "$major" -ge 22 ] 2>/dev/null; then
            pass "Node.js: $node_ver (>= 22)"
        else
            fail "Node.js: $node_ver (expected >= 22)"
        fi
    else
        fail "Node.js: not found in container"
    fi

    # 2. Container stable (restart count)
    if [ -n "$GATEWAY_INSPECT" ]; then
        local restart_count
        restart_count=$(echo "$GATEWAY_INSPECT" | python3 -c "
import json, sys
d = json.load(sys.stdin)
print(d[0].get('RestartCount', -1))
" 2>/dev/null)
        if [ "${restart_count:-}" = "0" ]; then
            pass "Container stable: 0 restarts"
        elif [ -n "$restart_count" ] && [ "$restart_count" -le 2 ] 2>/dev/null; then
            pass "Container stable: $restart_count restarts (≤ 2)"
        elif [ -n "$restart_count" ]; then
            fail "Container unstable: $restart_count restarts"
        else
            skip "Container stability: could not read restart count"
        fi
    else
        skip "Container stability: inspect data not available"
    fi

    # 3. Volume mounts accessible
    local vol_ok
    vol_ok=$(container_exec "test -f /home/node/.openclaw/openclaw.json && echo yes")
    if [ "$vol_ok" = "yes" ]; then
        pass "Volume mounts: config file accessible"
    else
        fail "Volume mounts: config not accessible inside container"
    fi
}
