# tests/core.sh — Gateway Core (health, version, resources, HTTP)
# Always runs if gateway is reachable.

test_core() {
    should_run "core" || return 0

    local test_count=0
    has_container_access && test_count=7 || test_count=1
    section "Gateway Core ($test_count tests)"

    # 1. Gateway HTTP responds
    # Any HTTP response (200, 400, 401, etc.) means the gateway is reachable.
    # Only 000 (connection refused/timeout) means it's down.
    if [ -n "$OPENCLAW_GATEWAY_URL" ]; then
        local http_code
        http_code=$(curl -s -o /dev/null -w '%{http_code}' --connect-timeout 5 "$OPENCLAW_GATEWAY_URL" 2>/dev/null)
        if [ "$http_code" != "000" ] && [ -n "$http_code" ]; then
            pass "HTTP responds: $http_code"
        elif has_container_access; then
            # Gateway not reachable directly — try from the Docker host
            http_code=$(host_exec "curl -s -o /dev/null -w '%{http_code}' --connect-timeout 5 'http://localhost:18789'" 2>/dev/null | tr -d '\r\n')
            if [ "$http_code" != "000" ] && [ -n "$http_code" ]; then
                pass "HTTP responds: $http_code (via Docker host)"
            else
                fail "HTTP responds: unreachable (direct and host both failed)"
            fi
        else
            fail "HTTP responds: unreachable (code: ${http_code:-000})"
        fi
    else
        skip "HTTP responds: OPENCLAW_GATEWAY_URL not set"
    fi

    has_container_access || return 0

    # 2. Health status
    if [ -n "$GATEWAY_INSPECT" ]; then
        local health
        health=$(echo "$GATEWAY_INSPECT" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d[0]['State']['Health']['Status'])" 2>/dev/null)
        if [ "$health" = "healthy" ]; then
            pass "Health status: healthy"
        else
            fail "Health status: ${health:-unknown} (expected healthy)"
        fi
    else
        skip "Health status: inspect data not available"
    fi

    # 3. Version
    local version
    if [ "$OPENCLAW_NATIVE" = "true" ]; then
        # Isolate the semver token (e.g. "2026.6.8" from "OpenClaw 2026.6.8 (844f405)")
        # rather than stripping all non-numeric chars, which concatenates build-hash digits.
        version=$(openclaw --version 2>/dev/null | head -1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
        if [ -z "$version" ] && [ -n "$OPENCLAW_INSTALL_DIR" ]; then
            version=$(node -p "require('$OPENCLAW_INSTALL_DIR/package.json').version" 2>/dev/null)
        fi
    else
        version=$(container_exec "node -p \"require('/app/package.json').version\"")
    fi
    if [ -n "$OPENCLAW_EXPECTED_VERSION" ]; then
        if [ "$version" = "$OPENCLAW_EXPECTED_VERSION" ]; then
            pass "Version: $version"
        else
            fail "Version: $version (expected $OPENCLAW_EXPECTED_VERSION)"
        fi
    elif [ -n "$version" ]; then
        pass "Version: $version"
    else
        fail "Version: could not read"
    fi

    # 4. CPU usage
    if [ -n "$GATEWAY_STATS" ]; then
        local cpu
        cpu=$(echo "$GATEWAY_STATS" | cut -d'|' -f1 | tr -d '%' | tr -d ' ')
        if [ -n "$cpu" ]; then
            local cpu_int=${cpu%.*}
            if [ "$cpu_int" -lt 50 ] 2>/dev/null; then
                pass "CPU: ${cpu}% (< 50%)"
            else
                fail "CPU: ${cpu}% (expected < 50% — may still be compiling skills)"
            fi
        else
            skip "CPU: could not parse stats"
        fi
    else
        skip "CPU: stats not available"
    fi

    # 5. Memory usage
    if [ -n "$GATEWAY_STATS" ]; then
        local mem_usage
        mem_usage=$(echo "$GATEWAY_STATS" | cut -d'|' -f2 | awk -F/ '{print $1}' | tr -d ' ')
        if [ -n "$mem_usage" ]; then
            pass "Memory: $mem_usage"
        else
            skip "Memory: could not parse"
        fi
    else
        skip "Memory: stats not available"
    fi

    # 6. PID count
    if [ -n "$GATEWAY_STATS" ]; then
        local pids
        pids=$(echo "$GATEWAY_STATS" | cut -d'|' -f3 | tr -d ' ')
        if [ -n "$pids" ] && [ "$pids" -ge 3 ] && [ "$pids" -le 100 ] 2>/dev/null; then
            pass "PIDs: $pids (3-100 range)"
        elif [ -n "$pids" ]; then
            fail "PIDs: $pids (expected 3-100)"
        else
            skip "PIDs: could not read"
        fi
    else
        skip "PIDs: stats not available"
    fi

    # 7. Docker healthcheck configured
    if [ -n "$GATEWAY_INSPECT" ]; then
        local has_healthcheck
        has_healthcheck=$(echo "$GATEWAY_INSPECT" | python3 -c "
import json, sys
d = json.load(sys.stdin)
hc = d[0].get('Config', {}).get('Healthcheck', {})
print('yes' if hc.get('Test') else 'no')
" 2>/dev/null)
        if [ "$has_healthcheck" = "yes" ]; then
            pass "Healthcheck: configured"
        else
            fail "Healthcheck: not configured on container"
        fi
    else
        skip "Healthcheck: inspect data not available"
    fi
}
