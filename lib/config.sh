# lib/config.sh — Load .env, set defaults, detect features
# Sourced by openclaw-test.sh — do not run directly.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Load .env if it exists
if [ -f "$SCRIPT_DIR/.env" ]; then
    set -a
    # shellcheck disable=SC1091
    source "$SCRIPT_DIR/.env"
    set +a
fi

# ─── Required ──────────────────────────────────────────────────────
OPENCLAW_GATEWAY_URL="${OPENCLAW_GATEWAY_URL:-}"

# ─── Container access ─────────────────────────────────────────────
OPENCLAW_SSH_HOST="${OPENCLAW_SSH_HOST:-}"
OPENCLAW_DOCKER_BIN="${OPENCLAW_DOCKER_BIN:-}"
OPENCLAW_CONTAINER="${OPENCLAW_CONTAINER:-openclaw-gateway}"

# ─── Native mode (no Docker — gateway runs directly on host) ─────
OPENCLAW_NATIVE="${OPENCLAW_NATIVE:-false}"
OPENCLAW_INSTALL_DIR="${OPENCLAW_INSTALL_DIR:-}"

# ─── Memory server ────────────────────────────────────────────────
OPENCLAW_MEMORY_SERVER_URL="${OPENCLAW_MEMORY_SERVER_URL:-}"
OPENCLAW_MEMORY_NAMESPACE="${OPENCLAW_MEMORY_NAMESPACE:-default}"

# ─── Feature flags ────────────────────────────────────────────────
OPENCLAW_SLACK_ENABLED="${OPENCLAW_SLACK_ENABLED:-false}"
OPENCLAW_DISCORD_ENABLED="${OPENCLAW_DISCORD_ENABLED:-false}"

# ─── Expected values ──────────────────────────────────────────────
OPENCLAW_EXPECTED_VERSION="${OPENCLAW_EXPECTED_VERSION:-}"
OPENCLAW_PRIMARY_PROVIDER="${OPENCLAW_PRIMARY_PROVIDER:-}"
OPENCLAW_MIN_FALLBACK_MODELS="${OPENCLAW_MIN_FALLBACK_MODELS:-0}"
OPENCLAW_MIN_SKILLS="${OPENCLAW_MIN_SKILLS:-0}"

# ─── Custom provider endpoint testing ─────────────────────────────
OPENCLAW_CUSTOM_PROVIDER_NAME="${OPENCLAW_CUSTOM_PROVIDER_NAME:-}"
OPENCLAW_CUSTOM_PROVIDER_URL="${OPENCLAW_CUSTOM_PROVIDER_URL:-}"
OPENCLAW_CUSTOM_PROVIDER_KEY="${OPENCLAW_CUSTOM_PROVIDER_KEY:-}"
OPENCLAW_CUSTOM_PROVIDER_MODELS="${OPENCLAW_CUSTOM_PROVIDER_MODELS:-}"

# ─── Local deployment extras (used by tests/local/*.sh) ──────────
OPENCLAW_DEPLOY_DIR="${OPENCLAW_DEPLOY_DIR:-}"
OPENCLAW_ANTHROPIC_KEY="${OPENCLAW_ANTHROPIC_KEY:-}"
OPENCLAW_ANTHROPIC_URL="${OPENCLAW_ANTHROPIC_URL:-https://api.anthropic.com/v1/messages}"
OPENCLAW_MAC_CONFIG_DIR="${OPENCLAW_MAC_CONFIG_DIR:-$HOME/.openclaw}"

# ─── Latency thresholds (ms) ──────────────────────────────────────
OPENCLAW_MAX_MEMORY_SEARCH_MS="${OPENCLAW_MAX_MEMORY_SEARCH_MS:-3000}"
OPENCLAW_MAX_GATEWAY_HTTP_MS="${OPENCLAW_MAX_GATEWAY_HTTP_MS:-2000}"
OPENCLAW_MAX_HEALTH_MS="${OPENCLAW_MAX_HEALTH_MS:-1000}"
OPENCLAW_MAX_SKILLS_MS="${OPENCLAW_MAX_SKILLS_MS:-3000}"

# ─── Context optimization thresholds ─────────────────────────────
OPENCLAW_MAX_WORKSPACE_MD_FILES="${OPENCLAW_MAX_WORKSPACE_MD_FILES:-10}"
OPENCLAW_MAX_WORKSPACE_MD_BYTES="${OPENCLAW_MAX_WORKSPACE_MD_BYTES:-8000}"
OPENCLAW_MAX_BOOTSTRAP_TOKENS="${OPENCLAW_MAX_BOOTSTRAP_TOKENS:-2000}"
OPENCLAW_FRAMEWORK_MD_FILES="${OPENCLAW_FRAMEWORK_MD_FILES:-AGENTS.md,CLAUDE.md,SOUL.md,TOOLS.md,IDENTITY.md,USER.md,HEARTBEAT.md,MEMORY.md}"

# ─── CLI args (override .env) ─────────────────────────────────────
SECTION_FILTER=""

parse_args() {
    while [ $# -gt 0 ]; do
        case "$1" in
            --expected-version) OPENCLAW_EXPECTED_VERSION="${2:-}"; shift 2 ;;
            --expected-version=*) OPENCLAW_EXPECTED_VERSION="${1#*=}"; shift ;;
            --section) SECTION_FILTER="${2:-}"; shift 2 ;;
            --section=*) SECTION_FILTER="${1#*=}"; shift ;;
            --gateway-url) OPENCLAW_GATEWAY_URL="${2:-}"; shift 2 ;;
            --gateway-url=*) OPENCLAW_GATEWAY_URL="${1#*=}"; shift ;;
            --help|-h)
                echo "Usage: openclaw-test.sh [OPTIONS]"
                echo ""
                echo "Options:"
                echo "  --section NAME         Run only named section(s), comma-separated"
                echo "  --expected-version V   Verify gateway matches this version"
                echo "  --gateway-url URL      Override gateway URL"
                echo "  --help                 Show this help"
                echo ""
                echo "Sections: core, config, cron, plugins, memory, channels,"
                echo "          runtime, environment, context, latency,"
                echo "          custom-provider + any tests/local/*.sh modules"
                echo ""
                echo "Configuration: create a .env file (see .env.example)"
                exit 0
                ;;
            *) shift ;;
        esac
    done
}

# ─── Computed paths ───────────────────────────────────────────────
# Config directory inside the runtime environment (container or native host).
# Tests use this instead of hardcoding /home/node/.openclaw.
if [ "$OPENCLAW_NATIVE" = "true" ]; then
    _PROC_CONFIG_DIR="$OPENCLAW_MAC_CONFIG_DIR"
else
    _PROC_CONFIG_DIR="/home/node/.openclaw"
fi

# ─── Docs schema path ─────────────────────────────────────────────
DOCS_SCHEMA="$SCRIPT_DIR/docs-schema.json"
