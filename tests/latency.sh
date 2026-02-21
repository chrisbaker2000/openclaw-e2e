# tests/latency.sh — Performance Benchmarks
# Measures warm response times for critical components.

test_latency() {
    should_run "latency" || return 0
    section "Latency Benchmarks (3 tests)"

    local has_memory=false
    [ -n "$OPENCLAW_MEMORY_SERVER_URL" ] && has_memory=true

    # Determine the best gateway URL for latency testing
    # If direct URL is unreachable but we have SSH, test from the Docker host
    local gw_latency_url="$OPENCLAW_GATEWAY_URL"
    local gw_latency_via=""
    if [ -n "$gw_latency_url" ]; then
        local probe
        probe=$(curl -s -o /dev/null -w '%{http_code}' --connect-timeout 3 "$gw_latency_url" 2>/dev/null)
        if [ "$probe" = "000" ] && has_container_access; then
            # Not directly reachable — we'll test via Docker host
            gw_latency_url="http://localhost:18789"
            gw_latency_via=" (via Docker host)"
        fi
    fi

    # Warmup: ping endpoints to ensure connections are hot
    if [ -n "$gw_latency_via" ] && has_container_access; then
        host_exec "curl -sf -o /dev/null 'http://localhost:18789'" 2>/dev/null || true
    elif [ -n "$OPENCLAW_GATEWAY_URL" ]; then
        curl -sf -o /dev/null --connect-timeout 3 "$OPENCLAW_GATEWAY_URL" 2>/dev/null || true
    fi
    if [ "$has_memory" = "true" ]; then
        python3 -c "
import urllib.request, json
try:
    urllib.request.urlopen('$OPENCLAW_MEMORY_SERVER_URL/v1/health', timeout=10).read()
except: pass
try:
    data = json.dumps({'text': 'warmup', 'namespace': {'eq': '$OPENCLAW_MEMORY_NAMESPACE'}, 'limit': 1}).encode()
    req = urllib.request.Request('$OPENCLAW_MEMORY_SERVER_URL/v1/long-term-memory/search', data=data, headers={'Content-Type': 'application/json'})
    urllib.request.urlopen(req, timeout=10).read()
except: pass
" 2>/dev/null
    fi

    # 1. Gateway HTTP latency
    # Measures round-trip time to gateway. Accepts any HTTP response (including 400/401).
    if [ -n "$OPENCLAW_GATEWAY_URL" ]; then
        local gw_http_ms
        if [ -n "$gw_latency_via" ] && has_container_access; then
            # Test from Docker host via SSH (measures container responsiveness, not network)
            gw_http_ms=$(host_exec "python3 -c \"
import urllib.request, urllib.error, time
start = time.monotonic()
try:
    resp = urllib.request.urlopen('$gw_latency_url', timeout=10)
except urllib.error.HTTPError:
    pass  # 400/401/etc still means we got a response
elapsed = (time.monotonic() - start) * 1000
print(int(elapsed))
\"" 2>/dev/null | tr -d '\r\n')
        else
            gw_http_ms=$(python3 -c "
import urllib.request, urllib.error, time
start = time.monotonic()
try:
    resp = urllib.request.urlopen('$gw_latency_url', timeout=10)
except urllib.error.HTTPError:
    pass  # 400/401/etc still means we got a response
elapsed = (time.monotonic() - start) * 1000
print(int(elapsed))
" 2>/dev/null)
        fi
        if [ "${gw_http_ms:-9999}" -le "$OPENCLAW_MAX_GATEWAY_HTTP_MS" ] 2>/dev/null; then
            pass "Gateway HTTP: ${gw_http_ms}ms${gw_latency_via} (max ${OPENCLAW_MAX_GATEWAY_HTTP_MS}ms)"
        else
            fail "Gateway HTTP: ${gw_http_ms:-timeout}ms${gw_latency_via} (max ${OPENCLAW_MAX_GATEWAY_HTTP_MS}ms)"
        fi
    else
        skip "Gateway HTTP: URL not set"
    fi

    # 2. Memory server health latency
    if [ "$has_memory" = "true" ]; then
        local mem_health_ms
        mem_health_ms=$(python3 -c "
import urllib.request, time
start = time.monotonic()
resp = urllib.request.urlopen('$OPENCLAW_MEMORY_SERVER_URL/v1/health', timeout=10)
elapsed = (time.monotonic() - start) * 1000
print(int(elapsed))
" 2>/dev/null)
        if [ "${mem_health_ms:-9999}" -le "$OPENCLAW_MAX_HEALTH_MS" ] 2>/dev/null; then
            pass "Memory health: ${mem_health_ms}ms (max ${OPENCLAW_MAX_HEALTH_MS}ms)"
        else
            fail "Memory health: ${mem_health_ms:-timeout}ms (max ${OPENCLAW_MAX_HEALTH_MS}ms)"
        fi
    else
        skip "Memory health: server URL not set"
    fi

    # 3. Memory search latency
    if [ "$has_memory" = "true" ]; then
        local mem_search_ms
        mem_search_ms=$(python3 -c "
import urllib.request, json, time
url = '$OPENCLAW_MEMORY_SERVER_URL/v1/long-term-memory/search'
data = json.dumps({'text': 'standing instructions preferences', 'namespace': {'eq': '$OPENCLAW_MEMORY_NAMESPACE'}, 'limit': 5}).encode()
req = urllib.request.Request(url, data=data, headers={'Content-Type': 'application/json'})
start = time.monotonic()
resp = urllib.request.urlopen(req, timeout=15)
elapsed = (time.monotonic() - start) * 1000
print(int(elapsed))
" 2>/dev/null)
        if [ "${mem_search_ms:-9999}" -le "$OPENCLAW_MAX_MEMORY_SEARCH_MS" ] 2>/dev/null; then
            pass "Memory search: ${mem_search_ms}ms (max ${OPENCLAW_MAX_MEMORY_SEARCH_MS}ms)"
        else
            fail "Memory search: ${mem_search_ms:-timeout}ms (max ${OPENCLAW_MAX_MEMORY_SEARCH_MS}ms)"
        fi
    else
        skip "Memory search: server URL not set"
    fi
}
