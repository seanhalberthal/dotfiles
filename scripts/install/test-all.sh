#!/usr/bin/env bash
set -euo pipefail

# Master test runner for dotfiles
# Usage: ./scripts/test-all.sh [--integration]

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOTFILES_DIR="$(dirname "$(dirname "$SCRIPT_DIR")")"

RUN_INTEGRATION="${1:-}"
TOTAL_FAIL=0

# Colours (using $'...' for proper escape interpretation)
GREEN=$'\033[0;32m'
RED=$'\033[0;31m'
YELLOW=$'\033[0;33m'
CYAN=$'\033[0;36m'
NC=$'\033[0m'

run_test_suite() {
    local name="$1"
    local script="$2"

    echo ""
    echo "${CYAN}═══════════════════════════════════════════${NC}"
    echo "${CYAN} Running: $name${NC}"
    echo "${CYAN}═══════════════════════════════════════════${NC}"

    if [[ -f "$script" ]]; then
        if "$script"; then
            echo "${GREEN}✓ $name passed${NC}"
        else
            echo "${RED}✗ $name failed${NC}"
            TOTAL_FAIL=$((TOTAL_FAIL + 1))
        fi
    else
        echo "${YELLOW}○ $name skipped (not found: $script)${NC}"
    fi
}

echo ""
echo "╔═══════════════════════════════════════════╗"
echo "║         Dotfiles Test Suite               ║"
echo "╚═══════════════════════════════════════════╝"

# ShellCheck validation
echo ""
echo "${CYAN}═══════════════════════════════════════════${NC}"
echo "${CYAN} Running: ShellCheck${NC}"
echo "${CYAN}═══════════════════════════════════════════${NC}"

if command -v shellcheck &>/dev/null; then
    SHELLCHECK_FAILED=0

    # Check installation scripts (severity warning or above, exclude SC1091 source following)
    for script in "$SCRIPT_DIR"/*.sh; do
        if ! shellcheck -x -S warning -e SC1091 "$script" 2>/dev/null; then
            echo "${RED}✗ ShellCheck failed: $script${NC}"
            SHELLCHECK_FAILED=1
        fi
    done

    # Check tmux scripts
    for script in "$DOTFILES_DIR/tmux/.tmux/scripts"/*.sh; do
        if ! shellcheck -x -S warning -e SC1091 "$script" 2>/dev/null; then
            echo "${RED}✗ ShellCheck failed: $script${NC}"
            SHELLCHECK_FAILED=1
        fi
    done

    if [[ $SHELLCHECK_FAILED -eq 0 ]]; then
        echo "${GREEN}✓ All scripts pass ShellCheck${NC}"
    else
        TOTAL_FAIL=$((TOTAL_FAIL + 1))
    fi
else
    echo "${YELLOW}○ ShellCheck not installed${NC}"
fi

# Unit tests
run_test_suite "Tmux Library Tests" "$DOTFILES_DIR/tmux/.tmux/scripts/_lib/test.sh"

if [[ -f "$SCRIPT_DIR/../_lib/test.sh" ]]; then
    run_test_suite "Installation Library Tests" "$SCRIPT_DIR/../_lib/test.sh"
fi

# Integration tests (require tmux)
if [[ "$RUN_INTEGRATION" == "--integration" ]]; then
    if [[ -n "${TMUX:-}" ]]; then
        run_test_suite "Kill/Undo Integration" "$DOTFILES_DIR/tmux/.tmux/scripts/tests/test-kill-undo.sh"
        run_test_suite "Session Management Integration" "$DOTFILES_DIR/tmux/.tmux/scripts/tests/test-session-management.sh"
    else
        echo ""
        echo "${YELLOW}○ Integration tests skipped (not in tmux)${NC}"
        echo "  Run inside tmux to execute integration tests"
    fi
fi

# Summary
echo ""
echo "╔═══════════════════════════════════════════╗"
echo "║              Test Summary                 ║"
echo "╚═══════════════════════════════════════════╝"

if [[ $TOTAL_FAIL -eq 0 ]]; then
    echo "${GREEN}All test suites passed!${NC}"
    exit 0
else
    echo "${RED}$TOTAL_FAIL test suite(s) failed${NC}"
    exit 1
fi
