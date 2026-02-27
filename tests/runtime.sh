# tests/runtime.sh — Container Runtime
# Validates Node.js version, container stability, user, and resource limits.

test_runtime() {
    should_run "runtime" || return 0
    has_container_access || return 0
    if [ "$OPENCLAW_NATIVE" = "true" ]; then
        section "Process Runtime (7 tests)"
    else
        section "Container Runtime (7 tests)"
    fi

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

    # 3. Config accessible (volume mounts in Docker, filesystem in native)
    local vol_ok
    vol_ok=$(container_exec "test -f $_PROC_CONFIG_DIR/openclaw.json && echo yes")
    if [ "$vol_ok" = "yes" ]; then
        if [ "$OPENCLAW_NATIVE" = "true" ]; then
            pass "Config accessible: $_PROC_CONFIG_DIR/openclaw.json"
        else
            pass "Volume mounts: config file accessible"
        fi
    else
        if [ "$OPENCLAW_NATIVE" = "true" ]; then
            fail "Config not found: $_PROC_CONFIG_DIR/openclaw.json"
        else
            fail "Volume mounts: config not accessible inside container"
        fi
    fi

    # 4. Runtime user (Docker expects 'node'/uid 1000; not applicable in native mode)
    if [ "$OPENCLAW_NATIVE" = "true" ]; then
        skip "Runtime user: not applicable in native mode (no container user constraint)"
    else
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

    # 6. Container uptime (< 60s may indicate crash-loop)
    if [ -n "$GATEWAY_INSPECT" ]; then
        local uptime_secs
        uptime_secs=$(echo "$GATEWAY_INSPECT" | python3 -c "
import json, sys
from datetime import datetime, timezone
d = json.load(sys.stdin)
started = d[0].get('State', {}).get('StartedAt', '')
if not started:
    print('')
    sys.exit(0)
# Parse Docker ISO timestamp
try:
    started_dt = datetime.fromisoformat(started.replace('Z', '+00:00'))
    now = datetime.now(timezone.utc)
    diff = (now - started_dt).total_seconds()
    print(int(max(diff, 0)))
except:
    print('')
" 2>/dev/null | tr -d '\r\n')
        if [ -n "$uptime_secs" ] && [ "$uptime_secs" -ge 0 ] 2>/dev/null; then
            if [ "$uptime_secs" -ge 60 ]; then
                local uptime_human
                if [ "$uptime_secs" -ge 86400 ]; then
                    uptime_human="$((uptime_secs / 86400))d $((uptime_secs % 86400 / 3600))h"
                elif [ "$uptime_secs" -ge 3600 ]; then
                    uptime_human="$((uptime_secs / 3600))h $((uptime_secs % 3600 / 60))m"
                else
                    uptime_human="$((uptime_secs / 60))m ${uptime_secs}s"
                fi
                pass "Container uptime: $uptime_human"
            else
                fail "Container uptime: ${uptime_secs}s (< 60s — possible crash-loop)"
            fi
        else
            skip "Container uptime: could not parse StartedAt"
        fi
    else
        skip "Container uptime: inspect data not available"
    fi

    # 7. Memory limit check (report, warn if below 1 GiB)
    if [ -n "$GATEWAY_INSPECT" ]; then
        local mem_limit_bytes
        mem_limit_bytes=$(echo "$GATEWAY_INSPECT" | python3 -c "
import json, sys
d = json.load(sys.stdin)
mem = d[0].get('HostConfig', {}).get('Memory', 0)
print(mem)
" 2>/dev/null | tr -d '\r\n')
        if [ "${mem_limit_bytes:-0}" = "0" ]; then
            pass "Memory limit: unlimited (no cap set)"
        elif [ "$mem_limit_bytes" -ge 1073741824 ] 2>/dev/null; then
            local mem_mb=$((mem_limit_bytes / 1048576))
            pass "Memory limit: ${mem_mb}MB"
        elif [ "$mem_limit_bytes" -gt 0 ] 2>/dev/null; then
            local mem_mb=$((mem_limit_bytes / 1048576))
            fail "Memory limit: ${mem_mb}MB (< 1 GiB — docs recommend at least 1g)"
        else
            skip "Memory limit: could not read from inspect"
        fi
    else
        skip "Memory limit: inspect data not available"
    fi
}
