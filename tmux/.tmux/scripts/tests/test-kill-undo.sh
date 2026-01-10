#!/usr/bin/env bash
set -euo pipefail

# Integration tests for kill/undo operations
# Requires: Running inside tmux session
# Usage: ./test-kill-undo.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_DIR="$(dirname "$SCRIPT_DIR")"
LIB_DIR="$SCRIPTS_DIR/_lib"

PASS=0
FAIL=0

# Colours (using $'...' for proper escape interpretation)
GREEN=$'\033[0;32m'
RED=$'\033[0;31m'
YELLOW=$'\033[0;33m'
NC=$'\033[0m'

pass() {
    PASS=$((PASS + 1))
    printf "${GREEN}✓${NC} %s\n" "$1"
}

fail() {
    FAIL=$((FAIL + 1))
    printf "${RED}✗${NC} %s\n" "$1"
}

skip() {
    printf "${YELLOW}○${NC} %s (skipped)\n" "$1"
}

section() {
    echo ""
    echo "─────────────────────────────────────────"
    echo "$1"
    echo "─────────────────────────────────────────"
}

# Check if running inside tmux
if [[ -z "${TMUX:-}" ]]; then
    echo "Error: Must run inside tmux session"
    echo "Start tmux and run: $0"
    exit 1
fi

# Source libraries
source "$LIB_DIR/common.sh"
source "$LIB_DIR/paths.sh"
source "$LIB_DIR/session.sh"

section "Setup Test Environment"

# Create a test session
TEST_SESSION="test-kill-undo-$$"
ORIGINAL_SESSION=$(get_current_session)

tmux new-session -d -s "$TEST_SESSION" -c /tmp
pass "Created test session: $TEST_SESSION"

# Switch to test session
tmux switch-client -t "$TEST_SESSION"
sleep 0.5

section "Pane Kill/Undo Tests"

# Create a second pane
tmux split-window -h -c /tmp
sleep 0.5
PANE_COUNT_BEFORE=$(tmux display-message -p '#{window_panes}')

if [[ "$PANE_COUNT_BEFORE" -eq 2 ]]; then
    pass "Created second pane (count: $PANE_COUNT_BEFORE)"
else
    fail "Expected 2 panes, got $PANE_COUNT_BEFORE"
fi

# Kill the pane using kill-pane.sh
"$SCRIPTS_DIR/kill-pane.sh" 2>/dev/null || true
sleep 0.5

PANE_COUNT_AFTER=$(tmux display-message -p '#{window_panes}')
if [[ "$PANE_COUNT_AFTER" -eq 1 ]]; then
    pass "kill-pane.sh reduced pane count to 1"
else
    fail "Expected 1 pane after kill, got $PANE_COUNT_AFTER"
fi

# Check undo file was created
UNDO_FILE=$(get_pane_undo_file)
if [[ -f "$UNDO_FILE" ]]; then
    pass "Pane undo file created"
else
    fail "Pane undo file not found: $UNDO_FILE"
fi

# Undo the pane kill
"$SCRIPTS_DIR/undo-pane.sh" 2>/dev/null || true
sleep 0.5

PANE_COUNT_RESTORED=$(tmux display-message -p '#{window_panes}')
if [[ "$PANE_COUNT_RESTORED" -eq 2 ]]; then
    pass "undo-pane.sh restored pane (count: $PANE_COUNT_RESTORED)"
else
    fail "Expected 2 panes after undo, got $PANE_COUNT_RESTORED"
fi

section "Window Kill/Undo Tests"

# Create a second window
tmux new-window -t "$TEST_SESSION" -n "test-window" -c /tmp
sleep 0.5

WINDOW_COUNT_BEFORE=$(tmux list-windows -t "$TEST_SESSION" | wc -l | tr -d ' ')
if [[ "$WINDOW_COUNT_BEFORE" -eq 2 ]]; then
    pass "Created second window (count: $WINDOW_COUNT_BEFORE)"
else
    fail "Expected 2 windows, got $WINDOW_COUNT_BEFORE"
fi

# Kill the window
"$SCRIPTS_DIR/kill-window.sh" 2>/dev/null || true
sleep 0.5

WINDOW_COUNT_AFTER=$(tmux list-windows -t "$TEST_SESSION" | wc -l | tr -d ' ')
if [[ "$WINDOW_COUNT_AFTER" -eq 1 ]]; then
    pass "kill-window.sh reduced window count to 1"
else
    fail "Expected 1 window after kill, got $WINDOW_COUNT_AFTER"
fi

# Check undo file was created
WINDOW_UNDO_FILE=$(get_window_undo_file)
if [[ -f "$WINDOW_UNDO_FILE" ]]; then
    pass "Window undo file created"
else
    fail "Window undo file not found: $WINDOW_UNDO_FILE"
fi

# Undo the window kill
"$SCRIPTS_DIR/undo-window.sh" 2>/dev/null || true
sleep 0.5

WINDOW_COUNT_RESTORED=$(tmux list-windows -t "$TEST_SESSION" | wc -l | tr -d ' ')
if [[ "$WINDOW_COUNT_RESTORED" -eq 2 ]]; then
    pass "undo-window.sh restored window (count: $WINDOW_COUNT_RESTORED)"
else
    fail "Expected 2 windows after undo, got $WINDOW_COUNT_RESTORED"
fi

section "Cleanup"

# Switch back to original session
tmux switch-client -t "$ORIGINAL_SESSION" 2>/dev/null || true

# Kill test session
tmux kill-session -t "$TEST_SESSION" 2>/dev/null || true
pass "Cleaned up test session"

# Clean up undo files
cleanup_undo_files "pane"
cleanup_undo_files "window"
pass "Cleaned up undo files"

# ===========================================================================
# Summary
# ===========================================================================

echo ""
echo "==========================================="
echo "Test Results: ${GREEN}${PASS} passed${NC}, ${RED}${FAIL} failed${NC}"
echo "==========================================="

if [[ $FAIL -gt 0 ]]; then
    exit 1
fi
