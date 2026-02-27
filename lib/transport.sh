# lib/transport.sh — SSH/Docker/Native/API-only abstraction layer
# Sourced by openclaw-test.sh — do not run directly.
#
# All container/process access goes through these functions. They
# transparently handle four deployment modes:
#   A) SSH to remote Docker host (NAS, VPS, etc.)
#   B) Local Docker (gateway on same machine)
#   C) Native (gateway runs directly on host as a Node.js process)
#   D) No access (API-only mode — tests degrade gracefully)

# Execute a command inside the gateway runtime.
# Usage: container_exec "node --version"
#
# WARNING: In native mode, commands execute directly on the host with the
# current user's permissions (no container boundary). Do not add destructive
# commands. Python scripts can use os.environ['_PROC_CONFIG_DIR'] for paths.
container_exec() {
    local cmd="$1"
    if [ "$OPENCLAW_NATIVE" = "true" ]; then
        _PROC_CONFIG_DIR="$_PROC_CONFIG_DIR" sh -c "$cmd" 2>/dev/null
    elif [ -n "$OPENCLAW_SSH_HOST" ]; then
        ssh -o ConnectTimeout=5 "$OPENCLAW_SSH_HOST" \
            "$OPENCLAW_DOCKER_BIN exec $OPENCLAW_CONTAINER $cmd" 2>/dev/null
    elif [ -n "$OPENCLAW_DOCKER_BIN" ]; then
        $OPENCLAW_DOCKER_BIN exec "$OPENCLAW_CONTAINER" sh -c "$cmd" 2>/dev/null
    else
        return 1
    fi
}

# Get recent gateway logs.
# Usage: container_logs [TAIL_LINES]
container_logs() {
    local tail_lines="${1:-300}"
    if [ "$OPENCLAW_NATIVE" = "true" ]; then
        # Native mode: read from OpenClaw's log file on disk.
        # Per docs, logs live at /tmp/openclaw/openclaw-YYYY-MM-DD.log (JSON lines).
        local today
        today=$(date +%Y-%m-%d)
        local log_file="/tmp/openclaw/openclaw-${today}.log"
        if [ -f "$log_file" ]; then
            tail -n "$tail_lines" "$log_file" 2>/dev/null
        else
            # Fallback: macOS diagnostics log
            local diag_file="$HOME/Library/Logs/OpenClaw/diagnostics.jsonl"
            if [ -f "$diag_file" ]; then
                tail -n "$tail_lines" "$diag_file" 2>/dev/null
            else
                return 1
            fi
        fi
    elif [ -n "$OPENCLAW_SSH_HOST" ]; then
        ssh -o ConnectTimeout=5 "$OPENCLAW_SSH_HOST" \
            "$OPENCLAW_DOCKER_BIN logs --tail $tail_lines $OPENCLAW_CONTAINER" 2>&1
    elif [ -n "$OPENCLAW_DOCKER_BIN" ]; then
        $OPENCLAW_DOCKER_BIN logs --tail "$tail_lines" "$OPENCLAW_CONTAINER" 2>&1
    else
        return 1
    fi
}

# Get docker inspect JSON for the container.
# Not available in native mode (no container to inspect).
container_inspect() {
    if [ "$OPENCLAW_NATIVE" = "true" ]; then
        return 1
    elif [ -n "$OPENCLAW_SSH_HOST" ]; then
        ssh -o ConnectTimeout=5 "$OPENCLAW_SSH_HOST" \
            "$OPENCLAW_DOCKER_BIN inspect $OPENCLAW_CONTAINER" 2>/dev/null
    elif [ -n "$OPENCLAW_DOCKER_BIN" ]; then
        $OPENCLAW_DOCKER_BIN inspect "$OPENCLAW_CONTAINER" 2>/dev/null
    else
        return 1
    fi
}

# Get runtime stats (CPU, memory, PIDs).
# Not available in native mode v1 (could add ps-based stats later).
container_stats() {
    if [ "$OPENCLAW_NATIVE" = "true" ]; then
        return 1
    elif [ -n "$OPENCLAW_SSH_HOST" ]; then
        ssh -o ConnectTimeout=5 "$OPENCLAW_SSH_HOST" \
            "$OPENCLAW_DOCKER_BIN stats --no-stream --format '{{.CPUPerc}}|{{.MemUsage}}|{{.PIDs}}' $OPENCLAW_CONTAINER" 2>/dev/null
    elif [ -n "$OPENCLAW_DOCKER_BIN" ]; then
        $OPENCLAW_DOCKER_BIN stats --no-stream --format '{{.CPUPerc}}|{{.MemUsage}}|{{.PIDs}}' "$OPENCLAW_CONTAINER" 2>/dev/null
    else
        return 1
    fi
}

# Run a command on the host (not inside the container).
# In native mode, the gateway IS on the host, so this falls through to local.
# Usage: host_exec "crontab -l"
host_exec() {
    local cmd="$1"
    if [ -n "$OPENCLAW_SSH_HOST" ]; then
        ssh -o ConnectTimeout=5 "$OPENCLAW_SSH_HOST" "$cmd" 2>/dev/null
    else
        sh -c "$cmd" 2>/dev/null
    fi
}

# Returns 0 if we have container/process access, 1 if API-only mode.
has_container_access() {
    [ "$OPENCLAW_NATIVE" = "true" ] || [ -n "$OPENCLAW_SSH_HOST" ] || [ -n "$OPENCLAW_DOCKER_BIN" ]
}
