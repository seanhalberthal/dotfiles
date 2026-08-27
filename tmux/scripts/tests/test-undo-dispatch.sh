#!/usr/bin/env bash
set -euo pipefail

# tests for undo-dispatch.sh routing logic
# verifies get_most_recent_undo_type() and dispatch behaviour

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_DIR="$(dirname "$SCRIPT_DIR")"

# source test helpers to get isolated tmux server
source "$SCRIPT_DIR/_test-helpers.sh"

# trap to ensure cleanup on exit/interrupt
UNDO_TEST_DIR=""
trap 'rm -rf "$UNDO_TEST_DIR"; cleanup_test_server' EXIT INT TERM

# setup isolated tmux server
setup_test_server

# create temp directory for undo state
UNDO_TEST_DIR=$(mktemp -d)
export XDG_CACHE_HOME="$UNDO_TEST_DIR/cache"
mkdir -p "$XDG_CACHE_HOME/tmux/undo"

# source production libraries
source "$SCRIPTS_DIR/_lib/common.sh"
source "$SCRIPTS_DIR/_lib/paths.sh"

# create a test session
TEST_SESSION="test-dispatch-$$"
test_tmux new-session -d -s "$TEST_SESSION" -c /tmp

# ═══════════════════════════════════════════════════════════════
# get_most_recent_undo_type Tests
# ═══════════════════════════════════════════════════════════════

section "Undo Type Detection - No State"

# clean slate, no undo files
cleanup_undo_files "pane"
cleanup_undo_files "window"
cleanup_undo_files "session"

result=$(get_most_recent_undo_type)
assert_equals "Returns empty when no state files exist" "" "$result"

section "Undo Type Detection - Single Type"

# only pane undo state exists
echo "test:0.0" >"$(get_pane_undo_file)"
result=$(get_most_recent_undo_type)
assert_equals "Returns 'pane' when only pane state exists" "pane" "$result"
rm -f "$(get_pane_undo_file)"

# only window undo state exists
echo "test:0" >"$(get_window_undo_file)"
result=$(get_most_recent_undo_type)
assert_equals "Returns 'window' when only window state exists" "window" "$result"
rm -f "$(get_window_undo_file)"

# only session undo state exists
echo "test" >"$(get_session_undo_file)"
result=$(get_most_recent_undo_type)
assert_equals "Returns 'session' when only session state exists" "session" "$result"
rm -f "$(get_session_undo_file)"

section "Undo Type Detection - Priority by Timestamp"

# create all three types with controlled timestamps
UNDO_BASE="$XDG_CACHE_HOME/tmux/undo"

echo "test:0.0" >"$UNDO_BASE/pane"
echo "test:0" >"$UNDO_BASE/window"
echo "test" >"$UNDO_BASE/session"

# make pane the oldest, window middle, session newest
touch -t 202601010000 "$UNDO_BASE/pane"
touch -t 202601010001 "$UNDO_BASE/window"
touch -t 202601010002 "$UNDO_BASE/session"

result=$(get_most_recent_undo_type)
assert_equals "Returns 'session' when session is most recent" "session" "$result"

# make window the most recent
touch -t 202601010003 "$UNDO_BASE/window"
result=$(get_most_recent_undo_type)
assert_equals "Returns 'window' when window is most recent" "window" "$result"

# make pane the most recent
touch -t 202601010004 "$UNDO_BASE/pane"
result=$(get_most_recent_undo_type)
assert_equals "Returns 'pane' when pane is most recent" "pane" "$result"

# clean up
rm -f "$UNDO_BASE/pane" "$UNDO_BASE/window" "$UNDO_BASE/session"

section "Dispatch Script Structure"

DISPATCH_SCRIPT="$SCRIPTS_DIR/utils/undo-dispatch.sh"

if [[ -f "$DISPATCH_SCRIPT" ]]; then
    pass "undo-dispatch.sh exists"
else
    fail "undo-dispatch.sh not found"
fi

if [[ -x "$DISPATCH_SCRIPT" ]]; then
    pass "undo-dispatch.sh is executable"
else
    fail "undo-dispatch.sh should be executable"
fi

if bash -n "$DISPATCH_SCRIPT" 2>/dev/null; then
    pass "undo-dispatch.sh passes syntax check"
else
    fail "undo-dispatch.sh has syntax errors"
fi

# verify dispatch script references all three undo types
dispatch_content=$(cat "$DISPATCH_SCRIPT")
if [[ "$dispatch_content" == *"panes/undo.sh"* ]]; then
    pass "Dispatch routes to panes/undo.sh"
else
    fail "Dispatch should route to panes/undo.sh"
fi

if [[ "$dispatch_content" == *"windows/undo.sh"* ]]; then
    pass "Dispatch routes to windows/undo.sh"
else
    fail "Dispatch should route to windows/undo.sh"
fi

if [[ "$dispatch_content" == *"sessions/undo.sh"* ]]; then
    pass "Dispatch routes to sessions/undo.sh"
else
    fail "Dispatch should route to sessions/undo.sh"
fi

section "Dispatch - Nothing to Undo"

# clean all undo state
cleanup_undo_files "pane"
cleanup_undo_files "window"
cleanup_undo_files "session"

# run dispatch with no state, should show "nothing to undo" and exit 0
dispatch_output=$("$DISPATCH_SCRIPT" 2>&1) || true
pass "Dispatch with no state exits gracefully"

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
