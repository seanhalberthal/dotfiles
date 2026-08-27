#!/usr/bin/env bash
set -euo pipefail

# unit/integration tests for kill-session logic
# mocks UI interactions to verify behaviour without user input

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEST_SCRIPTS_DIR="$(dirname "$SCRIPT_DIR")"
LIB_DIR="$TEST_SCRIPTS_DIR/_lib"

# source test helpers to get isolated tmux server
source "$SCRIPT_DIR/_test-helpers.sh"

# trap to ensure cleanup on exit/interrupt
KILL_TEST_DIR=""
trap 'rm -rf "$KILL_TEST_DIR"; cleanup_test_server' EXIT INT TERM

# mocks
# ---------------------------------------------------------
# create a mock UI library
MOCK_UI_LIB="/tmp/mock_ui_lib_$$.sh"
echo 'show_visual_confirm() { return 0; }' >"$MOCK_UI_LIB"
echo 'show_centered_confirm() { return 0; }' >>"$MOCK_UI_LIB"
echo 'show_centered_message() { :; }' >>"$MOCK_UI_LIB"

# setup
# ---------------------------------------------------------
# setup isolated tmux server for testing
setup_test_server

# create temp directory for test isolation
KILL_TEST_DIR=$(mktemp -d)
export XDG_CACHE_HOME="$KILL_TEST_DIR/cache"
mkdir -p "$XDG_CACHE_HOME/tmux/undo"

# override alerts file to avoid polluting real config
export ALERTS_FILE="$KILL_TEST_DIR/alerts"

# source production libraries for alert helpers
source "$LIB_DIR/common.sh"
source "$LIB_DIR/paths.sh"
source "$LIB_DIR/alerts.sh"

TEST_SESSION_1="test_kill_1_$$"
TEST_SESSION_2="test_kill_2_$$"

# create two test sessions
test_tmux new-session -d -s "$TEST_SESSION_1" -c /tmp
test_tmux new-session -d -s "$TEST_SESSION_2" -c /tmp

echo "Created test sessions: $TEST_SESSION_1, $TEST_SESSION_2"

# ═══════════════════════════════════════════════════════════════
# Basic Kill Tests
# ═══════════════════════════════════════════════════════════════

section "Basic Session Kill"

# test 1: kill inactive session (should just kill it)
"$TEST_SCRIPTS_DIR/sessions/kill.sh" "$TEST_SESSION_2" --no-confirm >/dev/null

if ! test_tmux has-session -t "$TEST_SESSION_2" 2>/dev/null; then
    pass "Inactive session killed successfully"
else
    fail "Inactive session still exists"
fi

# test 2: kill remaining session with --no-confirm
# note: testing the "active session + switch" path requires an actual attached
# client, which isn't possible in an isolated test server; instead we verify
# killing the remaining session directly
TEST_SESSION_3="test_kill_3_$$"
test_tmux new-session -d -s "$TEST_SESSION_3" -c /tmp

"$TEST_SCRIPTS_DIR/sessions/kill.sh" "$TEST_SESSION_1" --no-confirm >/dev/null 2>&1 || true

if ! test_tmux has-session -t "$TEST_SESSION_1" 2>/dev/null; then
    pass "Remaining session killed successfully"
else
    fail "Remaining session still exists"
fi

# ═══════════════════════════════════════════════════════════════
# Alert Cleanup After Session Kill
# ═══════════════════════════════════════════════════════════════

section "Alert Cleanup After Kill"

# setup: create sessions with alerts
TEST_SESSION_A="test_alert_a_$$"
TEST_SESSION_B="test_alert_b_$$"
test_tmux new-session -d -s "$TEST_SESSION_A" -n "main" -c /tmp
test_tmux new-session -d -s "$TEST_SESSION_B" -n "work" -c /tmp

# seed alerts file with entries for both sessions
mkdir -p "$(dirname "$ALERTS_FILE")"
{
    echo "${TEST_SESSION_A}:main:claude"
    echo "${TEST_SESSION_A}:main:exit:@1:1:error"
    echo "${TEST_SESSION_B}:work:claude"
} >"$ALERTS_FILE"

# kill session A; alerts for A should be cleared, B should remain
"$TEST_SCRIPTS_DIR/sessions/kill.sh" "$TEST_SESSION_A" --no-confirm >/dev/null 2>&1 || true

# verify session A's alerts are gone (synchronous, no race condition)
if [[ -f "$ALERTS_FILE" ]] && grep -q "^${TEST_SESSION_A}:" "$ALERTS_FILE" 2>/dev/null; then
    fail "Session kill should clear all alerts for killed session"
else
    pass "Session kill clears alerts for killed session"
fi

# verify session B's alerts are preserved
if [[ -f "$ALERTS_FILE" ]] && grep -q "^${TEST_SESSION_B}:work:claude$" "$ALERTS_FILE" 2>/dev/null; then
    pass "Session kill preserves alerts for other sessions"
else
    fail "Session kill should not affect other sessions' alerts"
fi

# verify both agent AND exit alerts were cleared (not just agent ones)
if [[ -f "$ALERTS_FILE" ]] && grep -q "^${TEST_SESSION_A}:.*:exit:" "$ALERTS_FILE" 2>/dev/null; then
    fail "Session kill should clear exit alerts too"
else
    pass "Session kill clears exit alerts for killed session"
fi

# ═══════════════════════════════════════════════════════════════
# alert cleanup with empty/missing alerts file
# ═══════════════════════════════════════════════════════════════

section "Edge Cases"

# test: kill with no alerts file
rm -f "$ALERTS_FILE"
TEST_SESSION_D="test_alert_d_$$"
test_tmux new-session -d -s "$TEST_SESSION_D" -n "main" -c /tmp

"$TEST_SCRIPTS_DIR/sessions/kill.sh" "$TEST_SESSION_D" --no-confirm >/dev/null 2>&1 || true

if ! test_tmux has-session -t "$TEST_SESSION_D" 2>/dev/null; then
    pass "Kill works when alerts file does not exist"
else
    fail "Kill should succeed even without alerts file"
fi

# test: kill with empty alerts file
TEST_SESSION_E="test_alert_e_$$"
TEST_SESSION_F="test_alert_f_$$"
test_tmux new-session -d -s "$TEST_SESSION_E" -c /tmp
test_tmux new-session -d -s "$TEST_SESSION_F" -c /tmp

: >"$ALERTS_FILE"

"$TEST_SCRIPTS_DIR/sessions/kill.sh" "$TEST_SESSION_E" --no-confirm >/dev/null 2>&1 || true

if ! test_tmux has-session -t "$TEST_SESSION_E" 2>/dev/null; then
    pass "Kill works with empty alerts file"
else
    fail "Kill should succeed with empty alerts file"
fi

# cleanup
rm -f "$MOCK_UI_LIB"
test_tmux kill-session -t "$TEST_SESSION_1" 2>/dev/null || true
test_tmux kill-session -t "$TEST_SESSION_2" 2>/dev/null || true
test_tmux kill-session -t "${TEST_SESSION_3:-}" 2>/dev/null || true
test_tmux kill-session -t "${TEST_SESSION_A:-}" 2>/dev/null || true
test_tmux kill-session -t "${TEST_SESSION_B:-}" 2>/dev/null || true
test_tmux kill-session -t "${TEST_SESSION_D:-}" 2>/dev/null || true
test_tmux kill-session -t "${TEST_SESSION_E:-}" 2>/dev/null || true
test_tmux kill-session -t "${TEST_SESSION_F:-}" 2>/dev/null || true

# cleanup isolated tmux server
cleanup_test_server

print_summary
[[ $FAIL -gt 0 ]] && exit 1
exit 0
