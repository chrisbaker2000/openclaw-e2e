# lib/output.sh — Test output helpers (pass/fail/skip/section)
# Sourced by openclaw-test.sh — do not run directly.

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

PASS_COUNT=0
FAIL_COUNT=0
SKIP_COUNT=0
FAILURES=()
CURRENT_SECTION=""

pass() {
    echo -e "  ${GREEN}✓${NC} $1"
    PASS_COUNT=$((PASS_COUNT + 1))
}

fail() {
    echo -e "  ${RED}✗${NC} $1"
    FAIL_COUNT=$((FAIL_COUNT + 1))
    FAILURES+=("[$CURRENT_SECTION] $1")
}

skip() {
    echo -e "  ${DIM}○${NC} $1 ${DIM}(skipped)${NC}"
    SKIP_COUNT=$((SKIP_COUNT + 1))
}

section() {
    CURRENT_SECTION="$1"
    echo -e "\n${BOLD}━━━ $1 ━━━${NC}"
}

should_run() {
    if [ -z "$SECTION_FILTER" ]; then
        return 0
    fi
    # Support comma-separated section names
    echo ",$SECTION_FILTER," | grep -q ",$1,"
}

print_summary() {
    echo ""
    echo -e "${BOLD}════════════════════════════════════════${NC}"
    if [ $FAIL_COUNT -eq 0 ]; then
        echo -e "  ${GREEN}${PASS_COUNT} passed${NC}, ${SKIP_COUNT} skipped"
    else
        echo -e "  ${GREEN}${PASS_COUNT} passed${NC}, ${RED}${FAIL_COUNT} failed${NC}, ${SKIP_COUNT} skipped"
        echo ""
        echo -e "  ${RED}FAILURES:${NC}"
        for f in "${FAILURES[@]}"; do
            echo -e "    ${RED}✗${NC} $f"
        done
    fi
    echo -e "${BOLD}════════════════════════════════════════${NC}"
    echo ""
}
