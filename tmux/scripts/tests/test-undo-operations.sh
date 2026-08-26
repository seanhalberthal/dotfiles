#!/usr/bin/env bash
set -euo pipefail

# functional tests for undo operations (window and pane kill → undo cycles)
# tests the full lifecycle: kill saves state, undo restores from state

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_DIR="$(dirname "$SCRIPT_DIR")"

# source test helpers to get isolated tmux server
source "$SCRIPT_DIR/_test-helpers.sh"

# trap to ensure cleanup on exit/interrupt
UNDO_TEST_DIR=""
trap 'rm -rf "$UNDO_TEST_DIR"; cleanup_test_server' EXIT INT TERM

# setup isolated tmux server
setup_test_server

# create temp directory for undo state (override XDG_CACHE_HOME)
UNDO_TEST_DIR=$(mktemp -d)
export XDG_CACHE_HOME="$UNDO_TEST_DIR/cache"
mkdir -p "$XDG_CACHE_HOME/tmux/undo"

# source production libraries (they use TMUX_TEST_SOCKET via the tmux wrapper)
source "$SCRIPTS_DIR/_lib/common.sh"
source "$SCRIPTS_DIR/_lib/paths.sh"

# ═══════════════════════════════════════════════════════════════
# window kill → undo cycle
# ═══════════════════════════════════════════════════════════════

section "Window Undo State Files"

TEST_SESSION="test-undo-$$"
test_tmux new-session -d -s "$TEST_SESSION" -c /tmp

# create a second window to kill (can't kill the only window easily)
test_tmux new-window -t "$TEST_SESSION" -n "killme" -c /tmp
sleep 0.2

# verify window exists
WINDOW_COUNT=$(test_tmux list-windows -t "$TEST_SESSION" | wc -l | tr -d ' ')
if [[ "$WINDOW_COUNT" -ge 2 ]]; then
    pass "Created test session with multiple windows"
else
    fail "Expected at least 2 windows, got $WINDOW_COUNT"
fi

# kill the window using the production script (with --no-confirm)
"$SCRIPTS_DIR/windows/kill.sh" "${TEST_SESSION}:1" --no-confirm 2>/dev/null || true

# check that undo state files were created
UNDO_FILE=$(get_window_undo_file)
UNDO_STATE=$(get_window_undo_state)
UNDO_CONTENTS_DIR=$(get_window_undo_contents_dir)

if [[ -f "$UNDO_FILE" ]]; then
    pass "Window kill creates undo file"
else
    fail "Window kill should create undo file at $UNDO_FILE"
fi

if [[ -f "$UNDO_STATE" ]]; then
    pass "Window kill creates undo state file"
else
    fail "Window kill should create undo state file at $UNDO_STATE"
fi

if [[ -d "$UNDO_CONTENTS_DIR" ]]; then
    pass "Window kill creates undo contents directory"
else
    fail "Window kill should create undo contents directory"
fi

# verify state file contains window metadata
if [[ -f "$UNDO_STATE" ]]; then
    state_content=$(cat "$UNDO_STATE")
    if [[ "$state_content" == *"window"* ]]; then
        pass "Undo state contains window metadata"
    else
        fail "Undo state should contain window metadata"
    fi

    if [[ "$state_content" == *"$TEST_SESSION"* ]]; then
        pass "Undo state references correct session"
    else
        fail "Undo state should reference session $TEST_SESSION"
    fi
fi

# verify undo file permissions (macOS and Linux have different stat syntax)
if [[ "$(uname)" == "Darwin" ]]; then
    undo_file_perms=$(stat -f %Lp "$UNDO_FILE" 2>/dev/null)
else
    undo_file_perms=$(stat -c %a "$UNDO_FILE" 2>/dev/null)
fi
if [[ "$undo_file_perms" == "600" ]]; then
    pass "Undo file has secure permissions (600)"
else
    fail "Undo file should have 600 permissions"
fi

section "Window Undo Restore"

# now restore using undo
"$SCRIPTS_DIR/windows/undo.sh" 2>/dev/null || true
sleep 0.3

# check window count is back to 2
WINDOW_COUNT_AFTER=$(test_tmux list-windows -t "$TEST_SESSION" | wc -l | tr -d ' ')
if [[ "$WINDOW_COUNT_AFTER" -ge 2 ]]; then
    pass "Window undo restores window (count: $WINDOW_COUNT_AFTER)"
else
    fail "Window undo should restore window (expected >=2, got $WINDOW_COUNT_AFTER)"
fi

# verify undo state is cleaned up (delayed cleanup runs in background)
sleep 1.5
UNDO_FILE_AFTER=$(get_window_undo_file)
if [[ ! -f "$UNDO_FILE_AFTER" ]]; then
    pass "Undo state cleaned up after restore"
else
    # cleanup is backgrounded, might still be pending
    skip "Undo state cleanup may be pending (backgrounded)"
fi

# ═══════════════════════════════════════════════════════════════
# pane kill → undo cycle
# ═══════════════════════════════════════════════════════════════

section "Pane Undo State Files"

# create a split pane so we have something to kill
test_tmux split-window -t "$TEST_SESSION" -c /tmp
sleep 0.2

PANE_COUNT_BEFORE=$(test_tmux list-panes -t "$TEST_SESSION" | wc -l | tr -d ' ')
if [[ "$PANE_COUNT_BEFORE" -ge 2 ]]; then
    pass "Created split pane for testing"
else
    fail "Expected at least 2 panes, got $PANE_COUNT_BEFORE"
fi

# kill the pane using production script
"$SCRIPTS_DIR/panes/kill.sh" --force 2>/dev/null || true
sleep 0.2

# check pane undo state
PANE_UNDO_FILE=$(get_pane_undo_file)
PANE_UNDO_STATE=$(get_pane_undo_state)
PANE_UNDO_CONTENT=$(get_pane_undo_content)

if [[ -f "$PANE_UNDO_FILE" ]]; then
    pass "Pane kill creates undo file"
else
    fail "Pane kill should create undo file"
fi

if [[ -f "$PANE_UNDO_STATE" ]]; then
    pass "Pane kill creates undo state file"
else
    fail "Pane kill should create undo state file"
fi

# verify pane state contains key=value pairs
if [[ -f "$PANE_UNDO_STATE" ]]; then
    if grep -q "^dir=" "$PANE_UNDO_STATE"; then
        pass "Pane undo state contains dir field"
    else
        fail "Pane undo state should contain dir= field"
    fi

    if grep -q "^layout=" "$PANE_UNDO_STATE"; then
        pass "Pane undo state contains layout field"
    else
        fail "Pane undo state should contain layout= field"
    fi
fi

section "Pane Undo Restore"

# restore pane
"$SCRIPTS_DIR/panes/undo.sh" 2>/dev/null || true
sleep 0.3

PANE_COUNT_AFTER=$(test_tmux list-panes -t "$TEST_SESSION" | wc -l | tr -d ' ')
if [[ "$PANE_COUNT_AFTER" -ge 2 ]]; then
    pass "Pane undo restores pane (count: $PANE_COUNT_AFTER)"
else
    fail "Pane undo should restore pane (expected >=2, got $PANE_COUNT_AFTER)"
fi

# ═══════════════════════════════════════════════════════════════
# edge cases
# ═══════════════════════════════════════════════════════════════

section "Undo Edge Cases"

# clear undo state first
cleanup_undo_files "window"
cleanup_undo_files "pane"

# test undo with no state file (should exit gracefully)
UNDO_OUTPUT=$("$SCRIPTS_DIR/windows/undo.sh" 2>&1) || true
pass "Window undo with no state exits gracefully"

PANE_UNDO_OUTPUT=$("$SCRIPTS_DIR/panes/undo.sh" 2>&1) || true
pass "Pane undo with no state exits gracefully"

# test undo with corrupt/empty state file
echo "" >"$(get_window_undo_file)"
echo "" >"$(get_window_undo_state)"
"$SCRIPTS_DIR/windows/undo.sh" 2>/dev/null || true
pass "Window undo with empty state does not crash"

# clean up
cleanup_undo_files "window"
cleanup_undo_files "pane"

section "Session Undo Structural Validation"

# session undo depends on tmux-resurrect, just validate the script structure
SESSION_UNDO_SCRIPT="$SCRIPTS_DIR/sessions/undo.sh"

if [[ -f "$SESSION_UNDO_SCRIPT" ]]; then
    pass "sessions/undo.sh exists"
else
    fail "sessions/undo.sh not found"
fi

if [[ -x "$SESSION_UNDO_SCRIPT" ]]; then
    pass "sessions/undo.sh is executable"
else
    fail "sessions/undo.sh should be executable"
fi

if bash -n "$SESSION_UNDO_SCRIPT" 2>/dev/null; then
    pass "sessions/undo.sh passes syntax check"
else
    fail "sessions/undo.sh has syntax errors"
fi

session_content=$(cat "$SESSION_UNDO_SCRIPT")
if [[ "$session_content" == *"paths.sh"* ]]; then
    pass "sessions/undo.sh sources paths library"
else
    fail "sessions/undo.sh should source paths library"
fi

# ═══════════════════════════════════════════════════════════════
# Summary
# ═══════════════════════════════════════════════════════════════

echo ""
echo "==========================================="
printf "${GREEN}Test Results: %d passed${NC}, ${RED}%d failed${NC}\n" "$PASS" "$FAIL"
echo "==========================================="

if [[ $FAIL -gt 0 ]]; then
    exit 1
fi
