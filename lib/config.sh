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
OPENCLAW_DOCKER_BIN="${OPENCLAW_DOCKER_BIN:-docker}"
OPENCLAW_CONTAINER="${OPENCLAW_CONTAINER:-openclaw-gateway}"

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
OPENCLAW_AZURE_ANTHROPIC_KEY="${OPENCLAW_AZURE_ANTHROPIC_KEY:-}"
OPENCLAW_AZURE_ANTHROPIC_URL="${OPENCLAW_AZURE_ANTHROPIC_URL:-}"
OPENCLAW_MAC_CONFIG_DIR="${OPENCLAW_MAC_CONFIG_DIR:-$HOME/.openclaw}"

# ─── Latency thresholds (ms) ──────────────────────────────────────
OPENCLAW_MAX_MEMORY_SEARCH_MS="${OPENCLAW_MAX_MEMORY_SEARCH_MS:-3000}"
OPENCLAW_MAX_GATEWAY_HTTP_MS="${OPENCLAW_MAX_GATEWAY_HTTP_MS:-2000}"
OPENCLAW_MAX_HEALTH_MS="${OPENCLAW_MAX_HEALTH_MS:-1000}"
OPENCLAW_MAX_SKILLS_MS="${OPENCLAW_MAX_SKILLS_MS:-3000}"

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
                echo "          runtime, environment, latency, custom-provider"
                echo "          + any tests/local/*.sh modules"
                echo ""
                echo "Configuration: create a .env file (see .env.example)"
                exit 0
                ;;
            *) shift ;;
        esac
    done
}

# ─── Docs schema path ─────────────────────────────────────────────
DOCS_SCHEMA="$SCRIPT_DIR/docs-schema.json"
