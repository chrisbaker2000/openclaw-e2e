# tests/runtime.sh — Container Runtime
# Validates Node.js version, container stability, user, and resource limits.

test_runtime() {
    should_run "runtime" || return 0
    has_container_access || return 0
    section "Container Runtime (5 tests)"

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

    # 4. Container user is 'node' (per docs: runtime user = node, uid 1000)
    local container_user
    container_user=$(container_exec "whoami 2>/dev/null || id -un 2>/dev/null || echo unknown" | tr -d '\r\n')
    if [ "$container_user" = "node" ]; then
        pass "Container user: node"
    elif [ -n "$container_user" ]; then
        # Docker may be running as root or custom user — warn but check uid
        local container_uid
        container_uid=$(container_exec "id -u 2>/dev/null || echo unknown" | tr -d '\r\n')
        if [ "$container_uid" = "1000" ]; then
            pass "Container user: uid 1000 ($container_user)"
        else
            fail "Container user: $container_user (uid $container_uid) — expected 'node' (uid 1000)"
        fi
    else
        skip "Container user: could not determine"
    fi

    # 5. Container PID limit reasonable (per docs: default 256)
    if [ -n "$GATEWAY_INSPECT" ]; then
        local pid_limit
        pid_limit=$(echo "$GATEWAY_INSPECT" | python3 -c "
import json, sys
d = json.load(sys.stdin)
# PidsLimit may be in HostConfig
pids = d[0].get('HostConfig', {}).get('PidsLimit', 0)
print(pids if pids else 'unset')
" 2>/dev/null)
        if [ "$pid_limit" = "unset" ] || [ "$pid_limit" = "0" ] || [ "$pid_limit" = "-1" ]; then
            pass "PID limit: unlimited (no cap set)"
        elif [ "$pid_limit" -ge 100 ] 2>/dev/null; then
            pass "PID limit: $pid_limit"
        elif [ -n "$pid_limit" ]; then
            fail "PID limit: $pid_limit (too low — docs default is 256)"
        else
            skip "PID limit: could not read"
        fi
    else
        skip "PID limit: inspect data not available"
    fi
}
