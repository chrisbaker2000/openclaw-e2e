# tests/latency.sh — Performance Benchmarks
# Measures warm response times for critical components.

test_latency() {
    should_run "latency" || return 0
    section "Latency Benchmarks (5 tests)"

    local has_memory=false
    [ -n "$OPENCLAW_MEMORY_SERVER_URL" ] && has_memory=true

    # Determine the best gateway URL for latency testing
    # If direct URL is unreachable but we have SSH, test from the Docker host
    local gw_latency_url="$OPENCLAW_GATEWAY_URL"
    local gw_latency_via=""
    if [ -n "$gw_latency_url" ]; then
        local probe
        probe=$(curl -s -o /dev/null -w '%{http_code}' --connect-timeout 3 "$gw_latency_url" 2>/dev/null)
        if [ "$probe" = "000" ] && has_container_access && [ "$OPENCLAW_NATIVE" != "true" ]; then
            # Not directly reachable — we'll test via Docker host
            gw_latency_url="http://localhost:18789"
            gw_latency_via=" (via Docker host)"
        fi
    fi

    # Number of samples per benchmark (median compared to threshold).
    local samples="${OPENCLAW_LATENCY_SAMPLES:-5}"

    # Warmup: ping endpoints to ensure connections are hot.
    # Track whether the memory warmup actually succeeded so the "warm" benchmarks
    # below can skip explicitly instead of silently measuring a cold path.
    local mem_warmup_ok=false
    if [ -n "$gw_latency_via" ] && has_container_access && [ "$OPENCLAW_NATIVE" != "true" ]; then
        host_exec "curl -sf -o /dev/null 'http://localhost:18789'" 2>/dev/null || true
    elif [ -n "$OPENCLAW_GATEWAY_URL" ]; then
        curl -sf -o /dev/null --connect-timeout 3 "$OPENCLAW_GATEWAY_URL" 2>/dev/null || true
    fi
    if [ "$has_memory" = "true" ]; then
        # The warmup exits non-zero (not swallowed) if either probe fails, so a
        # cold/failed warmup is visible rather than masked by `except: pass`.
        if python3 -c "
import urllib.request, json, sys
try:
    urllib.request.urlopen('$OPENCLAW_MEMORY_SERVER_URL/v1/health', timeout=10).read()
    data = json.dumps({'text': 'warmup', 'namespace': {'eq': '$OPENCLAW_MEMORY_NAMESPACE'}, 'limit': 1}).encode()
    req = urllib.request.Request('$OPENCLAW_MEMORY_SERVER_URL/v1/long-term-memory/search', data=data, headers={'Content-Type': 'application/json'})
    urllib.request.urlopen(req, timeout=10).read()
except Exception as e:
    sys.stderr.write('memory warmup failed: %s\n' % e)
    sys.exit(1)
" 2>/dev/null; then
            mem_warmup_ok=true
        fi
    fi

    # 1. Gateway HTTP latency
    # Measures round-trip time to gateway. Accepts any HTTP response (including 400/401).
    if [ -n "$OPENCLAW_GATEWAY_URL" ]; then
        local gw_http_ms
        if [ -n "$gw_latency_via" ] && has_container_access; then
            # Test from Docker host via SSH (measures container responsiveness, not network).
            # Median of N samples so a single GC pause / blip doesn't flake the run.
            gw_http_ms=$(host_exec "python3 -c \"
import urllib.request, urllib.error, time, statistics
samples = []
for _ in range($samples):
    start = time.monotonic()
    try:
        urllib.request.urlopen('$gw_latency_url', timeout=10)
    except urllib.error.HTTPError:
        pass  # 400/401/etc still means we got a response
    samples.append((time.monotonic() - start) * 1000)
print(int(statistics.median(samples)))
\"" 2>/dev/null | tr -d '\r\n')
        else
            gw_http_ms=$(python3 -c "
import urllib.request, urllib.error, time, statistics
samples = []
for _ in range($samples):
    start = time.monotonic()
    try:
        urllib.request.urlopen('$gw_latency_url', timeout=10)
    except urllib.error.HTTPError:
        pass  # 400/401/etc still means we got a response
    samples.append((time.monotonic() - start) * 1000)
print(int(statistics.median(samples)))
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
    if [ "$has_memory" != "true" ]; then
        skip "Memory health: server URL not set"
    elif [ "$mem_warmup_ok" != "true" ]; then
        skip "Memory health: warmup did not succeed (cold path — not measuring)"
    else
        local mem_health_ms
        mem_health_ms=$(python3 -c "
import urllib.request, time, statistics
samples = []
for _ in range($samples):
    start = time.monotonic()
    urllib.request.urlopen('$OPENCLAW_MEMORY_SERVER_URL/v1/health', timeout=10)
    samples.append((time.monotonic() - start) * 1000)
print(int(statistics.median(samples)))
" 2>/dev/null)
        if [ "${mem_health_ms:-9999}" -le "$OPENCLAW_MAX_HEALTH_MS" ] 2>/dev/null; then
            pass "Memory health: ${mem_health_ms}ms (median of ${samples}, max ${OPENCLAW_MAX_HEALTH_MS}ms)"
        else
            fail "Memory health: ${mem_health_ms:-timeout}ms (median of ${samples}, max ${OPENCLAW_MAX_HEALTH_MS}ms)"
        fi
    fi

    # 3. Memory search latency
    if [ "$has_memory" != "true" ]; then
        skip "Memory search: server URL not set"
    elif [ "$mem_warmup_ok" != "true" ]; then
        skip "Memory search: warmup did not succeed (cold path — not measuring)"
    else
        local mem_search_ms
        mem_search_ms=$(python3 -c "
import urllib.request, json, time, statistics
url = '$OPENCLAW_MEMORY_SERVER_URL/v1/long-term-memory/search'
data = json.dumps({'text': 'standing instructions preferences', 'namespace': {'eq': '$OPENCLAW_MEMORY_NAMESPACE'}, 'limit': 5}).encode()
samples = []
for _ in range($samples):
    req = urllib.request.Request(url, data=data, headers={'Content-Type': 'application/json'})
    start = time.monotonic()
    urllib.request.urlopen(req, timeout=15)
    samples.append((time.monotonic() - start) * 1000)
print(int(statistics.median(samples)))
" 2>/dev/null)
        if [ "${mem_search_ms:-9999}" -le "$OPENCLAW_MAX_MEMORY_SEARCH_MS" ] 2>/dev/null; then
            pass "Memory search: ${mem_search_ms}ms (median of ${samples}, max ${OPENCLAW_MAX_MEMORY_SEARCH_MS}ms)"
        else
            fail "Memory search: ${mem_search_ms:-timeout}ms (median of ${samples}, max ${OPENCLAW_MAX_MEMORY_SEARCH_MS}ms)"
        fi
    fi

    # 4. Skills compilation time (parsed from gateway logs)
    #    Measures most recent skills.bins response time from WebSocket logs.
    #    Slow compilation blocks first response; useful to catch on underpowered hardware.
    if has_container_access && [ -n "$GATEWAY_LOGS" ]; then
        local skills_ms
        skills_ms=$(echo "$GATEWAY_LOGS" | python3 -c "
import re, sys
lines = sys.stdin.read()
# Pattern 1: 'skills.bins Nms' (WebSocket response logs)
matches = re.findall(r'skills\.bins\s+(\d+)\s*ms', lines)
if matches:
    # Report the most recent value
    print(matches[-1])
    sys.exit(0)
# Pattern 2: 'skills compiled in Nms' or 'Compiled N skills in Nms'
m = re.search(r'(?:skills?\s+compiled?|compiled?\s+\d+\s+skills?)\s+in\s+(\d+)\s*ms', lines, re.IGNORECASE)
if m:
    print(m.group(1))
    sys.exit(0)
print('')
" 2>/dev/null | tr -d '\r\n')
        if [ -n "$skills_ms" ] && [ "$skills_ms" -gt 0 ] 2>/dev/null; then
            if [ "$skills_ms" -le "$OPENCLAW_MAX_SKILLS_MS" ] 2>/dev/null; then
                pass "Skills compilation: ${skills_ms}ms (max ${OPENCLAW_MAX_SKILLS_MS}ms)"
            else
                fail "Skills compilation: ${skills_ms}ms (max ${OPENCLAW_MAX_SKILLS_MS}ms) — slow startup"
            fi
        else
            skip "Skills compilation: timing not found in logs"
        fi
    else
        skip "Skills compilation: no container access or logs"
    fi

    # 5. Gateway startup time (time from container start to "listening on" log)
    #    Parses StartedAt from inspect and finds the "listening on" log line.
    if has_container_access && [ -n "$GATEWAY_INSPECT" ] && [ -n "$GATEWAY_LOGS" ]; then
        local startup_secs
        startup_secs=$(echo "$GATEWAY_INSPECT" | python3 -c "
import json, re, sys
from datetime import datetime

d = json.load(sys.stdin)
started = d[0].get('State', {}).get('StartedAt', '')
if not started:
    sys.exit(1)
started_dt = datetime.fromisoformat(started.replace('Z', '+00:00').split('.')[0])
print(started_dt.strftime('%Y-%m-%dT%H:%M:%S'))
" 2>/dev/null | tr -d '\r\n')
        local listen_ts
        listen_ts=$(echo "$GATEWAY_LOGS" | python3 -c "
import re, sys
for line in sys.stdin:
    if 'listening on' in line.lower():
        m = re.search(r'(\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2})', line)
        if m:
            print(m.group(1))
            sys.exit(0)
print('')
" 2>/dev/null | tr -d '\r\n')
        if [ -n "$startup_secs" ] && [ -n "$listen_ts" ]; then
            local diff_s
            diff_s=$(python3 -c "
from datetime import datetime
s = datetime.fromisoformat('$startup_secs')
l = datetime.fromisoformat('$listen_ts')
d = int((l - s).total_seconds())
print(d if d > 0 else '')
" 2>/dev/null | tr -d '\r\n')
            if [ -n "$diff_s" ] && [ "$diff_s" -gt 0 ] 2>/dev/null; then
                if [ "$diff_s" -le 300 ]; then
                    pass "Gateway startup: ${diff_s}s"
                else
                    fail "Gateway startup: ${diff_s}s (> 300s — may indicate a problem)"
                fi
            else
                skip "Gateway startup: could not calculate duration"
            fi
        else
            skip "Gateway startup: could not determine from logs"
        fi
    else
        skip "Gateway startup: inspect/logs not available"
    fi
}
