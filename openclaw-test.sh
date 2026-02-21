#!/bin/bash
# OpenClaw Post-Update E2E Test Suite (Community Edition)
#
# Validates your OpenClaw gateway deployment after updates, config changes,
# or infrastructure modifications. Configurable for any deployment type.
#
# Usage:
#   ./openclaw-test.sh                        # Run all enabled tests
#   ./openclaw-test.sh --section core         # Run specific section
#   ./openclaw-test.sh --section core,config  # Multiple sections
#   ./openclaw-test.sh --expected-version V   # Pin expected version
#
# Configuration: create a .env file (see .env.example or run ./setup.sh)
#
# Sections: core, config, cron, plugins, memory, channels,
#           runtime, environment, latency, custom-provider

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ─── Load libraries ────────────────────────────────────────────────
source "$SCRIPT_DIR/lib/output.sh"
source "$SCRIPT_DIR/lib/config.sh"
source "$SCRIPT_DIR/lib/transport.sh"
source "$SCRIPT_DIR/lib/prefetch.sh"

# ─── Load test modules ────────────────────────────────────────────
source "$SCRIPT_DIR/tests/core.sh"
source "$SCRIPT_DIR/tests/config.sh"
source "$SCRIPT_DIR/tests/cron.sh"
source "$SCRIPT_DIR/tests/plugins.sh"
source "$SCRIPT_DIR/tests/memory.sh"
source "$SCRIPT_DIR/tests/channels.sh"
source "$SCRIPT_DIR/tests/runtime.sh"
source "$SCRIPT_DIR/tests/environment.sh"
source "$SCRIPT_DIR/tests/latency.sh"
source "$SCRIPT_DIR/tests/custom-provider.sh"

# ─── Parse CLI args ───────────────────────────────────────────────
parse_args "$@"

# ─── Validate minimum config ──────────────────────────────────────
if [ -z "$OPENCLAW_GATEWAY_URL" ] && ! has_container_access; then
    echo -e "${RED}ERROR: No gateway configured.${NC}"
    echo -e "Set OPENCLAW_GATEWAY_URL in .env or run ./setup.sh"
    echo -e "Run ./openclaw-test.sh --help for usage."
    exit 1
fi

# ─── Main ──────────────────────────────────────────────────────────
main() {
    echo ""
    echo -e "${BOLD}╔══════════════════════════════════════╗${NC}"
    echo -e "${BOLD}║   OpenClaw Post-Update E2E Tests     ║${NC}"
    echo -e "${BOLD}╚══════════════════════════════════════╝${NC}"

    # Show active configuration
    echo -e "${DIM}Gateway:   ${OPENCLAW_GATEWAY_URL:-not set}${NC}"
    if [ -n "$OPENCLAW_SSH_HOST" ]; then
        echo -e "${DIM}Container: $OPENCLAW_SSH_HOST → $OPENCLAW_CONTAINER${NC}"
    elif has_container_access; then
        echo -e "${DIM}Container: local → $OPENCLAW_CONTAINER${NC}"
    else
        echo -e "${DIM}Container: API-only mode (no Docker access)${NC}"
    fi
    [ -n "$OPENCLAW_MEMORY_SERVER_URL" ] && echo -e "${DIM}Memory:    $OPENCLAW_MEMORY_SERVER_URL${NC}"
    [ -n "$SECTION_FILTER" ] && echo -e "${DIM}Sections:  $SECTION_FILTER${NC}"

    # Pre-fetch gateway state
    prefetch

    # Run test modules (order matters — core first, latency last)
    test_core
    test_config
    test_cron
    test_plugins
    test_memory
    test_channels
    test_runtime
    test_environment
    test_latency
    test_custom_provider

    # Summary
    print_summary

    [ $FAIL_COUNT -eq 0 ]
}

main
