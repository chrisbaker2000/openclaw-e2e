# lib/transport.sh — SSH/Docker/local abstraction layer
# Sourced by openclaw-test.sh — do not run directly.
#
# All container access goes through these functions. They transparently
# handle three deployment modes:
#   A) SSH to remote Docker host (NAS, VPS, etc.)
#   B) Local Docker (gateway on same machine)
#   C) No container access (API-only mode — tests degrade gracefully)

# Execute a command inside the gateway container.
# Usage: container_exec "node --version"
container_exec() {
    local cmd="$1"
    if [ -n "$OPENCLAW_SSH_HOST" ]; then
        ssh -o ConnectTimeout=5 "$OPENCLAW_SSH_HOST" \
            "$OPENCLAW_DOCKER_BIN exec $OPENCLAW_CONTAINER $cmd" 2>/dev/null
    elif [ -n "$OPENCLAW_DOCKER_BIN" ]; then
        $OPENCLAW_DOCKER_BIN exec "$OPENCLAW_CONTAINER" sh -c "$cmd" 2>/dev/null
    else
        return 1
    fi
}

# Get raw docker logs from the container.
# Usage: container_logs [TAIL_LINES]
container_logs() {
    local tail_lines="${1:-300}"
    if [ -n "$OPENCLAW_SSH_HOST" ]; then
        ssh -o ConnectTimeout=5 "$OPENCLAW_SSH_HOST" \
            "$OPENCLAW_DOCKER_BIN logs --tail $tail_lines $OPENCLAW_CONTAINER" 2>&1
    elif [ -n "$OPENCLAW_DOCKER_BIN" ]; then
        $OPENCLAW_DOCKER_BIN logs --tail "$tail_lines" "$OPENCLAW_CONTAINER" 2>&1
    else
        return 1
    fi
}

# Get docker inspect JSON for the container.
container_inspect() {
    if [ -n "$OPENCLAW_SSH_HOST" ]; then
        ssh -o ConnectTimeout=5 "$OPENCLAW_SSH_HOST" \
            "$OPENCLAW_DOCKER_BIN inspect $OPENCLAW_CONTAINER" 2>/dev/null
    elif [ -n "$OPENCLAW_DOCKER_BIN" ]; then
        $OPENCLAW_DOCKER_BIN inspect "$OPENCLAW_CONTAINER" 2>/dev/null
    else
        return 1
    fi
}

# Get docker stats for the container.
container_stats() {
    if [ -n "$OPENCLAW_SSH_HOST" ]; then
        ssh -o ConnectTimeout=5 "$OPENCLAW_SSH_HOST" \
            "$OPENCLAW_DOCKER_BIN stats --no-stream --format '{{.CPUPerc}}|{{.MemUsage}}|{{.PIDs}}' $OPENCLAW_CONTAINER" 2>/dev/null
    elif [ -n "$OPENCLAW_DOCKER_BIN" ]; then
        $OPENCLAW_DOCKER_BIN stats --no-stream --format '{{.CPUPerc}}|{{.MemUsage}}|{{.PIDs}}' "$OPENCLAW_CONTAINER" 2>/dev/null
    else
        return 1
    fi
}

# Execute a command on the Docker host (not inside the container).
# Usage: host_exec "crontab -l"
host_exec() {
    local cmd="$1"
    if [ -n "$OPENCLAW_SSH_HOST" ]; then
        ssh -o ConnectTimeout=5 "$OPENCLAW_SSH_HOST" "$cmd" 2>/dev/null
    else
        eval "$cmd" 2>/dev/null
    fi
}

# Returns 0 if we have container access, 1 if API-only mode.
has_container_access() {
    [ -n "$OPENCLAW_SSH_HOST" ] || [ -n "$OPENCLAW_DOCKER_BIN" ]
}
