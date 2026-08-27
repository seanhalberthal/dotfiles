#!/usr/bin/env bash
# test suite for sessions/rename.sh
# tests the session renaming functionality including edge cases with alerts

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_test-helpers.sh"
source "$SCRIPT_DIR/../_lib/common.sh"

# isolate the alerts file to a temp directory so tests never touch the real one
# ALERTS_FILE must be set before sourcing alerts.sh; it guards with
# [[ -z "${ALERTS_FILE:-}" ]] before declaring it readonly
TEST_ALERTS_DIR="$(mktemp -d)"
export ALERTS_FILE="$TEST_ALERTS_DIR/alerts"
touch "$ALERTS_FILE"

# source alerts.sh after ALERTS_FILE is set so it picks up our isolated path
source "$SCRIPT_DIR/../_lib/alerts.sh"

# shellcheck disable=SC2329  # Called indirectly via trap
_cleanup_rename_tests() {
    cleanup_test_server
    rm -rf "$TEST_ALERTS_DIR"
}

# trap to ensure cleanup on exit/interrupt
trap _cleanup_rename_tests EXIT INT TERM

echo ""
echo "${CYAN}═══════════════════════════════════════════${NC}"
echo "${CYAN}  Rename Session Tests${NC}"
echo "${CYAN}═══════════════════════════════════════════${NC}"
echo ""

# ═══════════════════════════════════════════════════════════════════════════
# test: Clear alerts for session with no alert options set
# ═══════════════════════════════════════════════════════════════════════════
section "Clear alerts - no options set"

setup_test_server "rename-no-alerts"

# create a test session with no alerts
tmux new-session -d -s test-rename-1 -n window1

# create alerts file with entry for this session
echo "test-rename-1:window1:claude" >"$ALERTS_FILE"

# clear session alerts (should not fail even with no @*_alert options)
if clear_session_alerts "test-rename-1"; then
    pass "Clear alerts succeeded with no options set"
else
    fail "Clear alerts failed with no options set"
fi

cleanup_test_server

# ═══════════════════════════════════════════════════════════════════════════
# test: Clear alerts for session with alert options set
# ═══════════════════════════════════════════════════════════════════════════
section "Clear alerts - options set"

setup_test_server "rename-with-alerts"

# create a test session
tmux new-session -d -s test-rename-2 -n window1

# set alert options on the window
tmux set-option -wt test-rename-2:window1 "@claude_alert" 1

# create alerts file entry
echo "test-rename-2:window1:claude" >"$ALERTS_FILE"

# clear session alerts
if clear_session_alerts "test-rename-2"; then
    pass "Clear alerts succeeded with options set"
else
    fail "Clear alerts failed with options set"
fi

# verify option was cleared
if tmux show-options -wt test-rename-2:window1 "@claude_alert" 2>/dev/null; then
    fail "Alert option was not cleared"
else
    pass "Alert option was cleared"
fi

cleanup_test_server

# ═══════════════════════════════════════════════════════════════════════════
# test: Sanitise session names
# ═══════════════════════════════════════════════════════════════════════════
section "Sanitise session names"

# test space conversion
result=$(sanitise_session_name "my session")
assert_equals "Spaces converted to dashes" "my-session" "$result"

# test special character removal
result=$(sanitise_session_name "my@session!")
assert_equals "Special chars converted to dashes" "my-session" "$result"

# test trailing dash removal
result=$(sanitise_session_name "test   ")
assert_equals "Trailing dashes removed" "test" "$result"

# test valid name unchanged
result=$(sanitise_session_name "valid-name_123")
assert_equals "Valid name unchanged" "valid-name_123" "$result"

# test dot replacement (tmux uses '.' as pane separator)
result=$(sanitise_session_name "music.nvim")
assert_equals "Dots converted to dashes" "music-nvim" "$result"

# ═══════════════════════════════════════════════════════════════════════════
# test: Validate session names
# ═══════════════════════════════════════════════════════════════════════════
section "Validate session names"

# valid names
if validate_session_name "test" 2>/dev/null; then
    pass "Simple name valid"
else
    fail "Simple name should be valid"
fi

if validate_session_name "test-session_123" 2>/dev/null; then
    pass "Complex valid name accepted"
else
    fail "Complex valid name should be accepted"
fi

if validate_session_name "music.nvim" 2>/dev/null; then
    fail "Name with dot should be invalid (tmux pane separator)"
else
    pass "Name with dot rejected"
fi

# invalid names
if validate_session_name "" 2>/dev/null; then
    fail "Empty name should be invalid"
else
    pass "Empty name rejected"
fi

if validate_session_name "test session" 2>/dev/null; then
    fail "Name with spaces should be invalid"
else
    pass "Name with spaces rejected"
fi

if validate_session_name "test@session" 2>/dev/null; then
    fail "Name with @ should be invalid"
else
    pass "Name with @ rejected"
fi

# ═══════════════════════════════════════════════════════════════════════════
# test: Rename session workflow (no alerts)
# ═══════════════════════════════════════════════════════════════════════════
section "Rename workflow - no alerts"

setup_test_server "rename-workflow-1"

# create test session
tmux new-session -d -s old-name -n window1

# simulate rename script logic
current_session="old-name"
newname="new-name"

# validate
if ! validate_session_name "$newname" 2>/dev/null; then
    fail "Validation failed for valid name"
fi

# check if target exists
if session_exists "$newname"; then
    fail "Target session should not exist yet"
fi

# update alerts file (no-op when no alerts) then rename
update_session_name_in_alerts "$current_session" "$newname"

# rename
if tmux rename-session -t "$current_session" "$newname" 2>/dev/null; then
    pass "Session renamed successfully"
else
    fail "Session rename failed"
fi

# verify new name exists
if session_exists "$newname"; then
    pass "New session name exists"
else
    fail "New session name does not exist"
fi

# verify old name gone
if session_exists "$current_session"; then
    fail "Old session name still exists"
else
    pass "Old session name removed"
fi

cleanup_test_server

# ═══════════════════════════════════════════════════════════════════════════
# test: Rename session workflow (with alerts, alerts preserved)
# ═══════════════════════════════════════════════════════════════════════════
section "Rename workflow - alerts preserved"

setup_test_server "rename-workflow-2"

# create test session with alerts
tmux new-session -d -s alert-session -n window1

# set alert on window
tmux set-option -wt alert-session:window1 "@claude_alert" 1

# create alerts file entry
echo "alert-session:window1:claude" >"$ALERTS_FILE"

# simulate the rename script: update alerts file BEFORE renaming
current_session="alert-session"
newname="renamed-session"

update_session_name_in_alerts "$current_session" "$newname"

# verify alerts file was updated (old name gone, new name present)
if grep -q "^${current_session}:" "$ALERTS_FILE" 2>/dev/null; then
    fail "Old session name still in alerts file after update"
else
    pass "Old session name removed from alerts file"
fi

if grep -q "^${newname}:window1:claude$" "$ALERTS_FILE" 2>/dev/null; then
    pass "Alert updated to new session name"
else
    fail "Alert not updated to new session name"
fi

# now rename
if tmux rename-session -t "$current_session" "$newname" 2>/dev/null; then
    pass "Session with alerts renamed successfully"
else
    fail "Session with alerts rename failed"
fi

# verify session exists and alert entry survived
if session_exists "$newname"; then
    pass "Renamed session exists"
else
    fail "Renamed session does not exist"
fi

if grep -q "^${newname}:window1:claude$" "$ALERTS_FILE" 2>/dev/null; then
    pass "Alert persists after rename"
else
    fail "Alert lost after rename"
fi

cleanup_test_server

# ═══════════════════════════════════════════════════════════════════════════
# test: Rename to existing session name (should fail)
# ═══════════════════════════════════════════════════════════════════════════
section "Rename to existing name"

setup_test_server "rename-existing"

# create two sessions
tmux new-session -d -s session-a -n window1
tmux new-session -d -s session-b -n window1

# try to rename session-a to session-b (should fail)
if session_exists "session-b"; then
    pass "Target session exists (as expected)"
fi

# this should fail (we're just checking the validation)
if session_exists "session-b"; then
    pass "Validation catches existing session name"
fi

cleanup_test_server

# ═══════════════════════════════════════════════════════════════════════════
# test: Clear window alerts with no options (pipefail safe)
# ═══════════════════════════════════════════════════════════════════════════
section "Clear window alerts - pipefail safety"

setup_test_server "rename-pipefail"

# create test session
tmux new-session -d -s pipefail-test -n window1

# get window ID
win_id=$(tmux list-windows -t pipefail-test -F '#D' | head -1)

# this test ensures clear_window_alerts doesn't fail with pipefail
# when grep returns no results
(
    set -euo pipefail
    source "$SCRIPT_DIR/../_lib/alerts.sh"

    if clear_window_alerts "pipefail-test" "window1" "$win_id"; then
        echo "PASS"
    else
        echo "FAIL"
    fi
) | grep -q "PASS" && pass "Clear window alerts is pipefail-safe" || fail "Clear window alerts failed with pipefail"

cleanup_test_server

# ═══════════════════════════════════════════════════════════════════════════
# regression tests: rename must update alerts file BEFORE the tmux rename
# command, otherwise the async cleanup hook races and deletes alert entries
# see: race condition fix in sessions/rename.sh and windows/rename.sh
# ═══════════════════════════════════════════════════════════════════════════

section "Regression: session rename preserves alerts through cleanup"

setup_test_server "rename-regression-sess"

tmux new-session -d -s reg-sess -n work
echo "reg-sess:work:claude" >"$ALERTS_FILE"

# simulate the correct order: update file, then rename, then cleanup
# (cleanup.sh is what the session-renamed hook runs asynchronously)
update_session_name_in_alerts "reg-sess" "reg-new"
tmux rename-session -t "reg-sess" "reg-new" 2>/dev/null

# now simulate the async cleanup hook firing after both operations
cleanup_stale_alerts

# the alert should survive: file says "reg-new:work:claude" and session "reg-new" exists
if grep -q "^reg-new:work:claude$" "$ALERTS_FILE" 2>/dev/null; then
    pass "Alert survives session rename + cleanup"
else
    fail "Alert lost after session rename + cleanup (race regression)"
fi

cleanup_test_server

section "Regression: window rename preserves alerts through cleanup"

setup_test_server "rename-regression-win"

tmux new-session -d -s reg-wsess -n oldwin
echo "reg-wsess:oldwin:opencode" >"$ALERTS_FILE"

# correct order: update file, then rename, then cleanup
update_window_name_in_alerts "reg-wsess" "oldwin" "newwin"
tmux rename-window -t "reg-wsess:oldwin" "newwin" 2>/dev/null

# simulate the async cleanup hook
cleanup_stale_alerts

if grep -q "^reg-wsess:newwin:opencode$" "$ALERTS_FILE" 2>/dev/null; then
    pass "Alert survives window rename + cleanup"
else
    fail "Alert lost after window rename + cleanup (race regression)"
fi

cleanup_test_server

section "Regression: wrong order loses alerts (documents the bug)"

setup_test_server "rename-regression-wrong"

tmux new-session -d -s wrong-sess -n work
echo "wrong-sess:work:claude" >"$ALERTS_FILE"

# WRONG order: rename first, THEN cleanup runs before update
# this simulates what happens if update_session_name_in_alerts is called
# AFTER tmux rename-session: the async cleanup deletes the stale entry
tmux rename-session -t "wrong-sess" "wrong-new" 2>/dev/null
cleanup_stale_alerts
# now the late update finds nothing to sed-replace
update_session_name_in_alerts "wrong-sess" "wrong-new"

if grep -q "wrong" "$ALERTS_FILE" 2>/dev/null; then
    fail "Stale or mismatched entry found (unexpected)"
else
    pass "Wrong order correctly loses alerts (confirms the bug pattern)"
fi

cleanup_test_server

section "Regression: exit alerts preserved through session rename"

setup_test_server "rename-regression-exit"

tmux new-session -d -s exit-sess -n build
# exit alerts are keyed on window_id (field 4); cleanup validates by id, so the
# seed carries the real id of the build window. it survives the session move
EXIT_WID=$(tmux display-message -t "exit-sess:build" -p '#{window_id}' 2>/dev/null)
echo "exit-sess:build:exit:${EXIT_WID}:1:make test" >"$ALERTS_FILE"

update_session_name_in_alerts "exit-sess" "exit-new"
tmux rename-session -t "exit-sess" "exit-new" 2>/dev/null
cleanup_stale_alerts

if grep -q "^exit-new:build:exit:${EXIT_WID}:1:make test$" "$ALERTS_FILE" 2>/dev/null; then
    pass "Exit alert survives session rename + cleanup"
else
    fail "Exit alert lost after session rename + cleanup"
fi

cleanup_test_server

section "Regression: exit alert keyed on window_id survives automatic-rename"

setup_test_server "rename-regression-autorename"

tmux new-session -d -s auto-sess -n nowname
AUTO_WID=$(tmux display-message -t "auto-sess:nowname" -p '#{window_id}' 2>/dev/null)
# the stored name ("make") is what the window was called mid-command; the live
# window has since auto-renamed to "nowname". keyed on the id, cleanup must keep
# it; a second line points at a dead id and must be GC'd
{
    echo "auto-sess:make:exit:${AUTO_WID}:0:make test"
    echo "auto-sess:gone:exit:@99999:1:dead window"
} >"$ALERTS_FILE"

cleanup_stale_alerts

if grep -q ":exit:${AUTO_WID}:0:make test$" "$ALERTS_FILE" 2>/dev/null; then
    pass "cleanup keeps exit alert with a live id despite a stale stored name"
else
    fail "cleanup wrongly GC'd a live exit alert because its stored name drifted"
fi
if grep -q ":exit:@99999:" "$ALERTS_FILE" 2>/dev/null; then
    fail "cleanup should GC an exit alert whose window_id no longer exists"
else
    pass "cleanup GCs an exit alert whose window_id no longer exists"
fi

cleanup_test_server

section "Regression: multiple alerts preserved through window rename"

setup_test_server "rename-regression-multi"

tmux new-session -d -s multi-sess -n codew
cat >"$ALERTS_FILE" <<'ALERTS'
multi-sess:codew:claude
multi-sess:codew:opencode
multi-sess:other:copilot
ALERTS
# create the "other" window so cleanup doesn't remove its entry
tmux new-window -t multi-sess -n other

update_window_name_in_alerts "multi-sess" "codew" "editor"
tmux rename-window -t "multi-sess:codew" "editor" 2>/dev/null
cleanup_stale_alerts

# both alerts for the renamed window should be updated
if grep -q "^multi-sess:editor:claude$" "$ALERTS_FILE" 2>/dev/null; then
    pass "Claude alert updated to new window name"
else
    fail "Claude alert lost after window rename"
fi

if grep -q "^multi-sess:editor:opencode$" "$ALERTS_FILE" 2>/dev/null; then
    pass "OpenCode alert updated to new window name"
else
    fail "OpenCode alert lost after window rename"
fi

# unrelated window alert should be untouched
if grep -q "^multi-sess:other:copilot$" "$ALERTS_FILE" 2>/dev/null; then
    pass "Unrelated window alert preserved"
else
    fail "Unrelated window alert was incorrectly modified"
fi

cleanup_test_server

# print summary
echo ""
echo "${CYAN}═══════════════════════════════════════════${NC}"
if [[ $FAIL -eq 0 ]]; then
    echo "${GREEN}✓ All tests passed${NC} ($PASS passed)"
    exit 0
else
    echo "${RED}✗ Some tests failed${NC} ($PASS passed, $FAIL failed)"
    exit 1
fi
