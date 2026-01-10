#!/usr/bin/env bash
set -euo pipefail

# Test suite for tmux script libraries
# Usage: ./test.sh

SCRIPT_DIR="${BASH_SOURCE%/*}"
PASS=0
FAIL=0

# Colours
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

pass() {
    PASS=$((PASS + 1))
    printf "${GREEN}✓${NC} %s\n" "$1"
}

fail() {
    FAIL=$((FAIL + 1))
    printf "${RED}✗${NC} %s\n" "$1"
}

# ─────────────────────────────────────────
# Test common.sh
# ─────────────────────────────────────────
echo "Testing common.sh..."
source "$SCRIPT_DIR/common.sh"

# validate_session_name tests
if validate_session_name "valid-name" 2>/dev/null; then
    pass "validate_session_name accepts 'valid-name'"
else
    fail "validate_session_name should accept 'valid-name'"
fi

if validate_session_name "my_session.1" 2>/dev/null; then
    pass "validate_session_name accepts 'my_session.1'"
else
    fail "validate_session_name should accept 'my_session.1'"
fi

if ! validate_session_name "invalid name" 2>/dev/null; then
    pass "validate_session_name rejects 'invalid name' (space)"
else
    fail "validate_session_name should reject 'invalid name'"
fi

if ! validate_session_name "bad!" 2>/dev/null; then
    pass "validate_session_name rejects 'bad!' (special char)"
else
    fail "validate_session_name should reject 'bad!'"
fi

if ! validate_session_name "" 2>/dev/null; then
    pass "validate_session_name rejects empty string"
else
    fail "validate_session_name should reject empty string"
fi

# validate_pane_id tests
if validate_pane_id "%123" 2>/dev/null; then
    pass "validate_pane_id accepts '%123'"
else
    fail "validate_pane_id should accept '%123'"
fi

if ! validate_pane_id "123" 2>/dev/null; then
    pass "validate_pane_id rejects '123' (no %)"
else
    fail "validate_pane_id should reject '123'"
fi

# validate_window_index tests
if validate_window_index "5" 2>/dev/null; then
    pass "validate_window_index accepts '5'"
else
    fail "validate_window_index should accept '5'"
fi

if ! validate_window_index "abc" 2>/dev/null; then
    pass "validate_window_index rejects 'abc'"
else
    fail "validate_window_index should reject 'abc'"
fi

# ─────────────────────────────────────────
# Test paths.sh
# ─────────────────────────────────────────
echo ""
echo "Testing paths.sh..."
source "$SCRIPT_DIR/paths.sh"

UNDO_DIR=$(get_undo_base_dir)
if [[ "$UNDO_DIR" == "/tmp/tmux-undo-"* ]]; then
    pass "get_undo_base_dir returns correct path format"
else
    fail "get_undo_base_dir returned unexpected path: $UNDO_DIR"
fi

if [[ -d "$UNDO_DIR" ]]; then
    pass "get_undo_base_dir creates directory"
else
    fail "get_undo_base_dir should create directory"
fi

PERMS=$(stat -f %Lp "$UNDO_DIR" 2>/dev/null || stat -c %a "$UNDO_DIR" 2>/dev/null)
if [[ "$PERMS" == "700" ]]; then
    pass "undo directory has correct permissions (700)"
else
    fail "undo directory should have 700 permissions, got $PERMS"
fi

PANE_FILE=$(get_pane_undo_file)
if [[ "$PANE_FILE" == "$UNDO_DIR/pane" ]]; then
    pass "get_pane_undo_file returns correct path"
else
    fail "get_pane_undo_file returned unexpected path: $PANE_FILE"
fi

# ─────────────────────────────────────────
# Test session.sh
# ─────────────────────────────────────────
echo ""
echo "Testing session.sh..."
source "$SCRIPT_DIR/session.sh"

# These require tmux, so only test if inside tmux
if [[ -n "${TMUX:-}" ]]; then
    SESSION=$(get_current_session)
    if [[ -n "$SESSION" ]]; then
        pass "get_current_session returns session name: $SESSION"
    else
        fail "get_current_session returned empty"
    fi

    WINDOW=$(get_current_window)
    if [[ "$WINDOW" =~ ^[0-9]+$ ]]; then
        pass "get_current_window returns window index: $WINDOW"
    else
        fail "get_current_window returned non-numeric: $WINDOW"
    fi
else
    echo "  (skipping tmux-dependent tests - not in tmux)"
fi

# ─────────────────────────────────────────
# Syntax check all scripts
# ─────────────────────────────────────────
echo ""
echo "Syntax checking scripts..."
SCRIPTS_DIR="$SCRIPT_DIR/.."

for script in "$SCRIPTS_DIR"/*.sh; do
    if bash -n "$script" 2>/dev/null; then
        pass "$(basename "$script") syntax OK"
    else
        fail "$(basename "$script") has syntax errors"
    fi
done

# ─────────────────────────────────────────
# Summary
# ─────────────────────────────────────────
echo ""
echo "─────────────────────────────────────────"
TOTAL=$((PASS + FAIL))
printf "Results: ${GREEN}%d passed${NC}, ${RED}%d failed${NC} (total: %d)\n" "$PASS" "$FAIL" "$TOTAL"

if [[ $FAIL -gt 0 ]]; then
    exit 1
fi
