# lib/prefetch.sh — Pre-cache gateway state in one batch
# Sourced by openclaw-test.sh — do not run directly.
#
# Fetches all gateway state once at startup and stores it in global
# variables. Tests reference these cached values instead of making
# repeated SSH/API calls. This reduces runtime from ~5 min to <2 min.

# Global cache variables (populated by prefetch)
GATEWAY_LOGS=""
GATEWAY_CONFIG=""
GATEWAY_INSPECT=""
GATEWAY_STATS=""

prefetch() {
    echo -e "${DIM}Fetching gateway state...${NC}"

    if ! has_container_access; then
        echo -e "${YELLOW}No container access configured — running in API-only mode${NC}"
        echo -e "${DIM}(Only core HTTP and memory API tests will run)${NC}"
        return 0
    fi

    if [ "$OPENCLAW_NATIVE" = "true" ]; then
        echo -e "${DIM}Native mode — reading config and logs from disk${NC}"
    fi

    # Fetch recent logs, then filter to only the current startup using timestamps.
    # Docker logs interleaves stdout/stderr out of chronological order, so
    # line-number filtering doesn't work. Instead, find the timestamp of the
    # last "Initializing telemetry" line and keep only lines at or after that point.
    local raw_logs
    raw_logs=$(container_logs 300) || raw_logs=""

    GATEWAY_LOGS=$(echo "$raw_logs" | python3 -c "
import re, sys
lines = sys.stdin.read().splitlines()
startup_ts = None
for line in reversed(lines):
    if 'Initializing telemetry' in line:
        m = re.search(r'(\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2})', line)
        if m:
            startup_ts = m.group(1)
            break
if not startup_ts:
    print('\n'.join(lines))
    sys.exit(0)
ts_re = re.compile(r'(\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2})')
in_current = False
for line in lines:
    m = ts_re.search(line)
    if m:
        in_current = m.group(1) >= startup_ts
    if in_current:
        print(line)
" 2>/dev/null) || GATEWAY_LOGS="$raw_logs"

    GATEWAY_CONFIG=$(container_exec "cat $_PROC_CONFIG_DIR/openclaw.json") || GATEWAY_CONFIG=""
    GATEWAY_INSPECT=$(container_inspect) || GATEWAY_INSPECT=""
    GATEWAY_STATS=$(container_stats) || GATEWAY_STATS=""

    if [ -z "$GATEWAY_LOGS" ] && [ -z "$GATEWAY_INSPECT" ] && [ -z "$GATEWAY_CONFIG" ]; then
        echo -e "${RED}ERROR: Cannot reach gateway.${NC}"
        if [ "$OPENCLAW_NATIVE" = "true" ]; then
            echo -e "${DIM}Check OPENCLAW_MAC_CONFIG_DIR ($OPENCLAW_MAC_CONFIG_DIR) and that the gateway is running${NC}"
        else
            echo -e "${DIM}Check your .env: OPENCLAW_SSH_HOST, OPENCLAW_DOCKER_BIN, OPENCLAW_CONTAINER${NC}"
        fi
        exit 1
    fi
}
