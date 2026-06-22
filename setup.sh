#!/bin/bash
# OpenClaw E2E Test Suite — Interactive Setup
#
# Generates a .env file by auto-detecting your deployment or asking questions.
#
# Usage:
#   ./setup.sh          # Interactive mode
#   ./setup.sh --auto   # Auto-detect only, no prompts

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="$SCRIPT_DIR/.env"
AUTO_MODE=false

[[ "${1:-}" == "--auto" ]] && AUTO_MODE=true

# Colors
GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; RED='\033[0;31m'; NC='\033[0m'; BOLD='\033[1m'

echo ""
echo -e "${BOLD}OpenClaw E2E Test Suite — Setup${NC}"
echo ""

if [ -f "$ENV_FILE" ]; then
    echo -e "${YELLOW}Warning: .env already exists. This will overwrite it.${NC}"
    if ! $AUTO_MODE; then
        read -rp "Continue? [y/N] " confirm
        [[ "$confirm" != [yY] ]] && echo "Aborted." && exit 0
    fi
fi

# ─── Discover gateway ────────────────────────────────────────────────
GATEWAY_URL=""
SSH_HOST=""
DOCKER_BIN=""
CONTAINER="openclaw-gateway"
NATIVE_MODE=""
MEMORY_URL=""
MEMORY_NS="default"
SLACK_ENABLED=""
DISCORD_ENABLED=""

echo -e "${CYAN}Checking localhost:18789...${NC}"
if curl -sf --max-time 3 "http://localhost:18789" >/dev/null 2>&1; then
    GATEWAY_URL="http://localhost:18789"
    echo -e "${GREEN}  Found local gateway at $GATEWAY_URL${NC}"
else
    echo -e "  No local gateway detected."
    if ! $AUTO_MODE; then
        read -rp "Gateway URL (e.g., http://192.168.1.100:18789): " GATEWAY_URL
    fi
fi

if [ -z "$GATEWAY_URL" ]; then
    echo -e "${RED}No gateway URL configured. Cannot continue.${NC}"
    exit 1
fi

# ─── Detect native install ──────────────────────────────────────────
echo ""
echo -e "${CYAN}Checking for native OpenClaw install...${NC}"

if command -v openclaw &>/dev/null; then
    OC_VERSION=$(openclaw --version 2>/dev/null | head -1)
    # Validate it's actually OpenClaw (version output should be numeric-ish)
    if [ -n "$OC_VERSION" ] && [ -d "${OPENCLAW_MAC_CONFIG_DIR:-$HOME/.openclaw}" ]; then
        echo -e "${GREEN}  Found native OpenClaw: $OC_VERSION${NC}"
        # Check if a Docker container also exists
        if command -v docker &>/dev/null && docker inspect "$CONTAINER" &>/dev/null 2>&1; then
            echo -e "${YELLOW}  NOTE: Docker container '$CONTAINER' also found.${NC}"
            if ! $AUTO_MODE; then
                read -rp "  Use native mode? [Y/n] " use_native
                [[ "$use_native" == [nN] ]] || NATIVE_MODE="true"
            else
                # Auto mode: prefer native when CLI is installed
                NATIVE_MODE="true"
            fi
        else
            NATIVE_MODE="true"
        fi
    fi
fi

# ─── Discover container access ────────────────────────────────────────
if [ "$NATIVE_MODE" != "true" ]; then
    echo ""
    echo -e "${CYAN}Checking container access...${NC}"

    # Try local Docker first
    if command -v docker &>/dev/null; then
        if docker inspect "$CONTAINER" &>/dev/null 2>&1; then
            DOCKER_BIN="docker"
            echo -e "${GREEN}  Found local Docker container '$CONTAINER'${NC}"
        fi
    fi

    # If no local container, ask about SSH
    if [ -z "$DOCKER_BIN" ] && ! $AUTO_MODE; then
        echo "  No local container found."
        read -rp "SSH host for remote Docker (leave empty for API-only): " SSH_HOST
        if [ -n "$SSH_HOST" ]; then
            echo -e "${CYAN}  Testing SSH connection to $SSH_HOST...${NC}"
            if ssh -o ConnectTimeout=5 -o BatchMode=yes "$SSH_HOST" "echo ok" &>/dev/null; then
                echo -e "${GREEN}  SSH connected.${NC}"
                # Try to find Docker binary
                for try_bin in docker /usr/bin/docker /usr/local/bin/docker; do
                    if ssh "$SSH_HOST" "command -v $try_bin || test -x $try_bin" &>/dev/null 2>&1; then
                        DOCKER_BIN="$try_bin"
                        echo -e "${GREEN}  Found Docker at $DOCKER_BIN${NC}"
                        break
                    fi
                done
                # Check QNAP Container Station path
                if [ -z "$DOCKER_BIN" ]; then
                    QNAP_DOCKER="/share/CACHEDEV1_DATA/.qpkg/container-station/bin/docker"
                    if ssh "$SSH_HOST" "test -x $QNAP_DOCKER" &>/dev/null 2>&1; then
                        DOCKER_BIN="$QNAP_DOCKER"
                        echo -e "${GREEN}  Found QNAP Docker at $DOCKER_BIN${NC}"
                    fi
                fi
                if [ -z "$DOCKER_BIN" ]; then
                    read -rp "  Docker binary path on remote host: " DOCKER_BIN
                fi
            else
                echo -e "${RED}  SSH connection failed. Continuing in API-only mode.${NC}"
                SSH_HOST=""
            fi
        fi
    fi
else
    echo -e "${GREEN}  Using native mode (no Docker needed)${NC}"
fi

# ─── Discover memory server ──────────────────────────────────────────
echo ""
echo -e "${CYAN}Checking for memory server...${NC}"

# Try to read gateway config — from disk (native) or container (Docker)
GW_CONFIG=""
if [ "$NATIVE_MODE" = "true" ]; then
    CONFIG_DIR="${OPENCLAW_MAC_CONFIG_DIR:-$HOME/.openclaw}"
    GW_CONFIG=$(cat "$CONFIG_DIR/openclaw.json" 2>/dev/null || true)
elif [ -n "$DOCKER_BIN" ]; then
    CONFIG_CMD="cat /home/node/.openclaw/openclaw.json 2>/dev/null"
    if [ -n "$SSH_HOST" ]; then
        GW_CONFIG=$(ssh "$SSH_HOST" "$DOCKER_BIN exec $CONTAINER sh -c '$CONFIG_CMD'" 2>/dev/null || true)
    else
        GW_CONFIG=$($DOCKER_BIN exec "$CONTAINER" sh -c "$CONFIG_CMD" 2>/dev/null || true)
    fi
fi

if [ -n "$GW_CONFIG" ]; then
    MEMORY_URL=$(echo "$GW_CONFIG" | python3 -c "
import sys, json
try:
    cfg = json.load(sys.stdin)
    # Check plugins.entries (current format) and plugins (legacy format)
    entries = cfg.get('plugins', {}).get('entries', cfg.get('plugins', {}))
    for name, pcfg in entries.items():
        if 'memory' in name.lower():
            # Try all known config paths
            url = (pcfg.get('config', {}).get('serverUrl', '') or
                   pcfg.get('settings', {}).get('apiUrl', '') or
                   pcfg.get('settings', {}).get('serverUrl', ''))
            if url: print(url); break
except Exception: pass
" 2>/dev/null || true)

    if [ -n "$MEMORY_URL" ]; then
        echo -e "${GREEN}  Found memory server: $MEMORY_URL${NC}"
        MEMORY_NS=$(echo "$GW_CONFIG" | python3 -c "
import sys, json
try:
    cfg = json.load(sys.stdin)
    entries = cfg.get('plugins', {}).get('entries', cfg.get('plugins', {}))
    for name, pcfg in entries.items():
        if 'memory' in name.lower():
            ns = (pcfg.get('config', {}).get('namespace', '') or
                  pcfg.get('settings', {}).get('namespace', 'default'))
            print(ns); break
except Exception: print('default')
" 2>/dev/null || echo "default")
    fi
fi

if [ -z "$MEMORY_URL" ] && ! $AUTO_MODE; then
    read -rp "Memory server URL (leave empty to skip): " MEMORY_URL
fi

# ─── Discover channels ───────────────────────────────────────────────
if [ -n "${GW_CONFIG:-}" ]; then
    HAS_SLACK=$(echo "$GW_CONFIG" | python3 -c "
import sys, json
try:
    cfg = json.load(sys.stdin)
    slack = cfg.get('channels', {}).get('slack', cfg.get('slack', {}))
    if slack.get('appToken') or slack.get('botToken'):
        print('true')
except Exception: pass
" 2>/dev/null || true)
    HAS_DISCORD=$(echo "$GW_CONFIG" | python3 -c "
import sys, json
try:
    cfg = json.load(sys.stdin)
    discord = cfg.get('channels', {}).get('discord', cfg.get('discord', {}))
    if discord.get('token'):
        print('true')
except Exception: pass
" 2>/dev/null || true)
    [ "$HAS_SLACK" = "true" ] && SLACK_ENABLED="true" && echo -e "${GREEN}  Detected Slack channel${NC}"
    [ "$HAS_DISCORD" = "true" ] && DISCORD_ENABLED="true" && echo -e "${GREEN}  Detected Discord channel${NC}"
fi

# ─── Write .env ───────────────────────────────────────────────────────
echo ""
echo -e "${CYAN}Writing .env...${NC}"

cat > "$ENV_FILE" << EOF
# OpenClaw E2E Test Suite Configuration
# Generated by setup.sh on $(date -u +"%Y-%m-%dT%H:%M:%SZ")

OPENCLAW_GATEWAY_URL="$GATEWAY_URL"
EOF

if [ "$NATIVE_MODE" = "true" ]; then
    cat >> "$ENV_FILE" << EOF
OPENCLAW_NATIVE=true
EOF
elif [ -n "$SSH_HOST" ]; then
    cat >> "$ENV_FILE" << EOF
OPENCLAW_SSH_HOST="$SSH_HOST"
OPENCLAW_DOCKER_BIN="$DOCKER_BIN"
OPENCLAW_CONTAINER="$CONTAINER"
EOF
elif [ -n "$DOCKER_BIN" ]; then
    cat >> "$ENV_FILE" << EOF
OPENCLAW_DOCKER_BIN="$DOCKER_BIN"
OPENCLAW_CONTAINER="$CONTAINER"
EOF
fi

if [ -n "$MEMORY_URL" ]; then
    cat >> "$ENV_FILE" << EOF
OPENCLAW_MEMORY_SERVER_URL="$MEMORY_URL"
OPENCLAW_MEMORY_NAMESPACE="$MEMORY_NS"
EOF
fi

[ "$SLACK_ENABLED" = "true" ] && echo "OPENCLAW_SLACK_ENABLED=true" >> "$ENV_FILE"
[ "$DISCORD_ENABLED" = "true" ] && echo "OPENCLAW_DISCORD_ENABLED=true" >> "$ENV_FILE"

echo -e "${GREEN}  Written to $ENV_FILE${NC}"

# ─── Smoke test ───────────────────────────────────────────────────────
echo ""
echo -e "${CYAN}Running smoke test...${NC}"
HTTP_CODE=$(curl -sf -o /dev/null -w "%{http_code}" --max-time 5 "$GATEWAY_URL" 2>/dev/null || echo "000")
if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "401" ]; then
    echo -e "${GREEN}  Gateway responded (HTTP $HTTP_CODE) — setup complete!${NC}"
else
    echo -e "${YELLOW}  Gateway returned HTTP $HTTP_CODE — check your OPENCLAW_GATEWAY_URL${NC}"
fi

echo ""
echo -e "${BOLD}Next steps:${NC}"
echo -e "  1. Review and edit .env if needed"
echo -e "  2. Run: ${CYAN}./openclaw-test.sh${NC}"
echo ""
