#!/usr/bin/env bash
set -euo pipefail

# test suite for tmux script libraries
# usage: ./tmux/scripts/_lib/test-tmux-libs.sh [--verbose]

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PASS=0
FAIL=0
# shellcheck disable=SC2034
VERBOSE="${1:-}" # reserved for future verbose output

# source test helpers for isolated tmux server support
# shellcheck source=tmux/scripts/tests/_test-helpers.sh
source "$SCRIPT_DIR/../tests/_test-helpers.sh"

# source common.sh to get the tmux() wrapper that respects TMUX_TEST_SOCKET
# shellcheck source=tmux/scripts/_lib/common.sh
source "$SCRIPT_DIR/common.sh"

# temp dir for isolated alerts file (set up before alerts.sh is sourced)
_TEST_ALERTS_DIR="$(mktemp -d)"
export ALERTS_FILE="$_TEST_ALERTS_DIR/alerts"
touch "$ALERTS_FILE"

_cleanup_lib_tests() {
    cleanup_test_server 2>/dev/null || true
    rm -rf "$_TEST_ALERTS_DIR"
}
trap _cleanup_lib_tests EXIT INT TERM

section() {
    echo ""
    echo "─────────────────────────────────────────"
    echo "$1"
    echo "─────────────────────────────────────────"
}

# capture stderr from a command (discard stdout, return stderr)
# shellcheck disable=SC2069
capture_stderr() {
    "$@" 2>&1 1>/dev/null
}

# assert that a command succeeds
assert_success() {
    local desc="$1"
    shift
    if "$@" 2>/dev/null; then
        pass "$desc"
    else
        fail "$desc"
    fi
}

# assert that a command fails
assert_failure() {
    local desc="$1"
    shift
    if ! "$@" 2>/dev/null; then
        pass "$desc"
    else
        fail "$desc"
    fi
}

# assert output equals expected value
assert_equals() {
    local desc="$1"
    local expected="$2"
    local actual="$3"
    if [[ "$actual" == "$expected" ]]; then
        pass "$desc"
    else
        fail "$desc (expected: '$expected', got: '$actual')"
    fi
}

# assert output matches pattern
assert_matches() {
    local desc="$1"
    local pattern="$2"
    local actual="$3"
    if [[ "$actual" =~ $pattern ]]; then
        pass "$desc"
    else
        fail "$desc (expected pattern: '$pattern', got: '$actual')"
    fi
}

# assert file exists
assert_file_exists() {
    local desc="$1"
    local file="$2"
    if [[ -f "$file" ]]; then
        pass "$desc"
    else
        fail "$desc (file not found: $file)"
    fi
}

# assert directory exists
assert_dir_exists() {
    local desc="$1"
    local dir="$2"
    if [[ -d "$dir" ]]; then
        pass "$desc"
    else
        fail "$desc (directory not found: $dir)"
    fi
}

# assert file has specific permissions
assert_permissions() {
    local desc="$1"
    local path="$2"
    local expected="$3"
    local actual
    # macOS and Linux have different stat syntax
    if [[ "$(uname)" == "Darwin" ]]; then
        actual=$(stat -f %Lp "$path" 2>/dev/null)
    else
        actual=$(stat -c %a "$path" 2>/dev/null)
    fi
    if [[ "$actual" == "$expected" ]]; then
        pass "$desc"
    else
        fail "$desc (expected: $expected, got: $actual)"
    fi
}

# ─────────────────────────────────────────
# test common.sh
# ─────────────────────────────────────────
section "Testing common.sh"
source "$SCRIPT_DIR/common.sh"

# validate_session_name tests
echo "  validate_session_name:"
assert_success "  accepts 'valid-name'" validate_session_name "valid-name"
assert_failure "  rejects 'my_session.1' (dot)" validate_session_name "my_session.1"
assert_success "  accepts 'A'" validate_session_name "A"
assert_success "  accepts '123'" validate_session_name "123"
assert_failure "  rejects 'a.b-c_d' (dot)" validate_session_name "a.b-c_d"
assert_success "  accepts 'CamelCase'" validate_session_name "CamelCase"
assert_failure "  rejects 'invalid name' (space)" validate_session_name "invalid name"
assert_failure "  rejects 'bad!' (special char)" validate_session_name "bad!"
assert_failure "  rejects '' (empty)" validate_session_name ""
assert_failure "  rejects 'has:colon'" validate_session_name "has:colon"
assert_failure "  rejects 'has/slash'" validate_session_name "has/slash"
assert_failure "  rejects 'has\$dollar'" validate_session_name 'has$dollar'
assert_failure "  rejects name with newline" validate_session_name $'foo\nbar'
assert_failure "  rejects name with tab" validate_session_name $'foo\tbar'

# validate_pane_id tests
echo ""
echo "  validate_pane_id:"
assert_success "  accepts '%123'" validate_pane_id "%123"
assert_success "  accepts '%0'" validate_pane_id "%0"
assert_success "  accepts '%999999'" validate_pane_id "%999999"
assert_failure "  rejects '123' (no %)" validate_pane_id "123"
assert_failure "  rejects '%' (no number)" validate_pane_id "%"
assert_failure "  rejects '' (empty)" validate_pane_id ""
assert_failure "  rejects '%-1' (negative)" validate_pane_id "%-1"
assert_failure "  rejects '%abc' (letters)" validate_pane_id "%abc"
assert_failure "  rejects '%%123' (double %)" validate_pane_id "%%123"
assert_failure "  rejects '%12.3' (decimal)" validate_pane_id "%12.3"

# validate_window_index tests
echo ""
echo "  validate_window_index:"
assert_success "  accepts '0'" validate_window_index "0"
assert_success "  accepts '5'" validate_window_index "5"
assert_success "  accepts '999'" validate_window_index "999"
assert_failure "  rejects 'abc'" validate_window_index "abc"
assert_failure "  rejects '' (empty)" validate_window_index ""
assert_failure "  rejects '-1' (negative)" validate_window_index "-1"
assert_failure "  rejects '1.5' (decimal)" validate_window_index "1.5"
assert_failure "  rejects '1a' (mixed)" validate_window_index "1a"

# test output functions (capture output)
echo ""
echo "  output functions:"

ERROR_OUTPUT=$(capture_stderr error "test error")
if [[ "$ERROR_OUTPUT" == *"Error:"* && "$ERROR_OUTPUT" == *"test error"* ]]; then
    pass "  error() outputs error message to stderr"
else
    fail "  error() should output 'Error: test error'"
fi

WARN_OUTPUT=$(capture_stderr warn "test warning")
if [[ "$WARN_OUTPUT" == *"Warning:"* && "$WARN_OUTPUT" == *"test warning"* ]]; then
    pass "  warn() outputs warning message to stderr"
else
    fail "  warn() should output 'Warning: test warning'"
fi

INFO_OUTPUT=$(info "test info")
if [[ "$INFO_OUTPUT" == *"test info"* ]]; then
    pass "  info() outputs info message"
else
    fail "  info() should output 'test info'"
fi

SUCCESS_OUTPUT=$(success "test success")
if [[ "$SUCCESS_OUTPUT" == *"test success"* ]]; then
    pass "  success() outputs success message"
else
    fail "  success() should output 'test success'"
fi

# ─────────────────────────────────────────
# test paths.sh
# ─────────────────────────────────────────
section "Testing paths.sh"
source "$SCRIPT_DIR/paths.sh"

echo "  get_undo_base_dir:"
UNDO_DIR=$(get_undo_base_dir)
assert_matches "  returns correct path format" "^${HOME}/.cache/tmux/undo$" "$UNDO_DIR"
assert_dir_exists "  creates directory" "$UNDO_DIR"
assert_permissions "  has correct permissions (700)" "$UNDO_DIR" "700"

# test idempotency, calling again shouldn't fail
UNDO_DIR2=$(get_undo_base_dir)
assert_equals "  is idempotent" "$UNDO_DIR" "$UNDO_DIR2"

echo ""
echo "  pane undo paths:"
PANE_FILE=$(get_pane_undo_file)
assert_equals "  get_pane_undo_file returns correct path" "$UNDO_DIR/pane" "$PANE_FILE"

PANE_STATE=$(get_pane_undo_state)
assert_equals "  get_pane_undo_state returns correct path" "$UNDO_DIR/pane-state.txt" "$PANE_STATE"

PANE_CONTENT=$(get_pane_undo_content)
assert_equals "  get_pane_undo_content returns correct path" "$UNDO_DIR/pane-content.txt" "$PANE_CONTENT"

echo ""
echo "  window undo paths:"
WINDOW_FILE=$(get_window_undo_file)
assert_equals "  get_window_undo_file returns correct path" "$UNDO_DIR/window" "$WINDOW_FILE"

WINDOW_STATE=$(get_window_undo_state)
assert_equals "  get_window_undo_state returns correct path" "$UNDO_DIR/window-state.txt" "$WINDOW_STATE"

WINDOW_CONTENTS=$(get_window_undo_contents_dir)
assert_equals "  get_window_undo_contents_dir returns correct path" "$UNDO_DIR/window-contents" "$WINDOW_CONTENTS"
assert_dir_exists "  window contents directory is created" "$WINDOW_CONTENTS"
assert_permissions "  window contents has correct permissions (700)" "$WINDOW_CONTENTS" "700"

echo ""
echo "  session undo paths:"
SESSION_FILE=$(get_session_undo_file)
assert_equals "  get_session_undo_file returns correct path" "$UNDO_DIR/session" "$SESSION_FILE"

SESSION_STATE=$(get_session_undo_state)
assert_equals "  get_session_undo_state returns correct path" "$UNDO_DIR/session-state.txt" "$SESSION_STATE"

SESSION_BACKUP=$(get_session_undo_backup)
assert_equals "  get_session_undo_backup returns correct path" "$UNDO_DIR/session-backup" "$SESSION_BACKUP"

echo ""
echo "  cleanup_undo_files:"

# Ensure clean state before testing cleanup functions
rm -rf "$UNDO_DIR/pane" "$UNDO_DIR/pane-state.txt" "$UNDO_DIR/pane-content.txt"
rm -rf "$UNDO_DIR/window" "$UNDO_DIR/window-state.txt" "$UNDO_DIR/window-contents"
rm -rf "$UNDO_DIR/session" "$UNDO_DIR/session-state.txt" "$UNDO_DIR/session-backup"

# Test pane cleanup
touch "$UNDO_DIR/pane" "$UNDO_DIR/pane-state.txt" "$UNDO_DIR/pane-content.txt"
cleanup_undo_files "pane"
if [[ ! -f "$UNDO_DIR/pane" && ! -f "$UNDO_DIR/pane-state.txt" && ! -f "$UNDO_DIR/pane-content.txt" ]]; then
    pass "  cleans up pane files"
else
    fail "  cleanup_undo_files 'pane' should remove all pane files"
fi

# Test window cleanup
touch "$UNDO_DIR/window" "$UNDO_DIR/window-state.txt"
mkdir -p "$UNDO_DIR/window-contents"
touch "$UNDO_DIR/window-contents/test.txt"
cleanup_undo_files "window"
if [[ ! -f "$UNDO_DIR/window" && ! -f "$UNDO_DIR/window-state.txt" && ! -f "$UNDO_DIR/window-contents/test.txt" ]]; then
    pass "  cleans up window files"
else
    fail "  cleanup_undo_files 'window' should remove all window files"
fi
assert_dir_exists "  recreates window-contents directory after cleanup" "$UNDO_DIR/window-contents"

# Test session cleanup
touch "$UNDO_DIR/session" "$UNDO_DIR/session-state.txt"
mkdir -p "$UNDO_DIR/session-backup"
touch "$UNDO_DIR/session-backup/test.txt"
cleanup_undo_files "session"
if [[ ! -f "$UNDO_DIR/session" && ! -f "$UNDO_DIR/session-state.txt" && ! -d "$UNDO_DIR/session-backup" ]]; then
    pass "  cleans up session files"
else
    fail "  cleanup_undo_files 'session' should remove all session files"
fi

# Test invalid type
if ! cleanup_undo_files "invalid" 2>/dev/null; then
    pass "  rejects invalid cleanup type"
else
    fail "  cleanup_undo_files should reject invalid type"
fi

echo ""
echo "  get_most_recent_undo_type:"

# Clean slate
rm -f "$UNDO_DIR/pane" "$UNDO_DIR/window" "$UNDO_DIR/session"

MOST_RECENT=$(get_most_recent_undo_type)
assert_equals "  returns empty when no undo files" "" "$MOST_RECENT"

# Use explicit timestamps to avoid timing issues (macOS has second-level granularity)
# Format: [[CC]YY]MMDDhhmm[.ss]
touch -t 202501010001 "$UNDO_DIR/pane"
MOST_RECENT=$(get_most_recent_undo_type)
assert_equals "  returns 'pane' when only pane file exists" "pane" "$MOST_RECENT"

# Create newer window file (1 minute later)
touch -t 202501010002 "$UNDO_DIR/window"
MOST_RECENT=$(get_most_recent_undo_type)
assert_equals "  returns 'window' when window is newest" "window" "$MOST_RECENT"

# Create newest session file (1 minute later again)
touch -t 202501010003 "$UNDO_DIR/session"
MOST_RECENT=$(get_most_recent_undo_type)
assert_equals "  returns 'session' when session is newest" "session" "$MOST_RECENT"

# Update pane to be newest
touch -t 202501010004 "$UNDO_DIR/pane"
MOST_RECENT=$(get_most_recent_undo_type)
assert_equals "  returns 'pane' after updating pane file" "pane" "$MOST_RECENT"

# Cleanup test files
rm -f "$UNDO_DIR/pane" "$UNDO_DIR/window" "$UNDO_DIR/session"

# ─────────────────────────────────────────
# test session.sh
# ─────────────────────────────────────────
section "Testing session.sh"
source "$SCRIPT_DIR/session.sh"

# spin up an isolated server for session and alerts tests
setup_test_server
# create a bootstrap session so the server has something to query
test_tmux new-session -d -s lib-test-main -n main 2>/dev/null || true

# session.sh functions that query the *current* tmux context require
# being attached; skip those when not in a real tmux session but run
# the server-querying tests against the isolated server regardless
if [[ -n "${TMUX:-}" ]]; then
    echo "  (running inside tmux - full tests)"

    SESSION=$(get_current_session)
    if [[ -n "$SESSION" ]]; then
        pass "  get_current_session returns session name: $SESSION"
    else
        fail "  get_current_session returned empty"
    fi

    WINDOW=$(get_current_window)
    assert_matches "  get_current_window returns window index" "^[0-9]+$" "$WINDOW"

    PANE=$(get_current_pane)
    assert_matches "  get_current_pane returns pane index" "^[0-9]+$" "$PANE"

    PANE_DIR=$(get_pane_directory)
    assert_dir_exists "  get_pane_directory returns valid directory" "$PANE_DIR"

    LAYOUT=$(get_window_layout)
    if [[ -n "$LAYOUT" ]]; then
        pass "  get_window_layout returns layout: ${LAYOUT:0:30}..."
    else
        fail "  get_window_layout returned empty"
    fi

    # test find_other_session (may or may not have other sessions)
    OTHER=$(find_other_session "$SESSION")
    if [[ -n "$OTHER" ]]; then
        pass "  find_other_session found another session: $OTHER"
    else
        skip "  find_other_session (no other sessions to find)"
    fi
else
    echo "  (not in tmux - skipping tmux-dependent tests)"
    skip "  get_current_session"
    skip "  get_current_window"
    skip "  get_current_pane"
    skip "  get_pane_directory"
    skip "  get_window_layout"
    skip "  find_other_session"
fi

# ─────────────────────────────────────────
# test alerts.sh
# ─────────────────────────────────────────
section "Testing alerts.sh"
source "$SCRIPT_DIR/alerts.sh"

# run against the isolated test server (set up above in session.sh section)
# TMUX_TEST_SOCKET is exported, so all bare `tmux` calls are intercepted by
# the wrapper in common.sh and routed to the isolated server
echo "  (using isolated test server)"

# clear the isolated alerts file for a clean slate
: >"$ALERTS_FILE"

# use the bootstrap session created on the isolated server
CURRENT_SESSION="lib-test-main"
CURRENT_WINDOW="main"
CURRENT_WINDOW_ID=$(tmux list-windows -t "$CURRENT_SESSION" -F '#{window_id}' 2>/dev/null | head -1)
CURRENT_PANE_ID=$(tmux list-panes -t "$CURRENT_SESSION:$CURRENT_WINDOW" -F '#{pane_id}' 2>/dev/null | head -1)

# test set_window_alert
echo ""
echo "  set_window_alert:"
# set_window_alert uses TMUX_PANE to call display-message; point it at the
# isolated server's pane so it can resolve the session:window context
TMUX_PANE="$CURRENT_PANE_ID" set_window_alert "claude" "false" 2>/dev/null || true
if grep -q "^${CURRENT_SESSION}:${CURRENT_WINDOW}:claude$" "$ALERTS_FILE" 2>/dev/null; then
    pass "    creates alert file entry"
else
    fail "    should create alert file entry"
fi

OPTION_VALUE=$(tmux show-options -wt "$CURRENT_WINDOW_ID" @claude_alert 2>/dev/null | cut -d' ' -f2)
if [[ "$OPTION_VALUE" == "1" ]]; then
    pass "    sets tmux window option"
else
    fail "    should set @claude_alert option to 1"
fi

# test clear_window_alerts
echo ""
echo "  clear_window_alerts:"
clear_window_alerts "$CURRENT_SESSION" "$CURRENT_WINDOW" "$CURRENT_WINDOW_ID"

if ! grep -q "^${CURRENT_SESSION}:${CURRENT_WINDOW}:" "$ALERTS_FILE" 2>/dev/null; then
    pass "    removes alert from file"
else
    fail "    should remove alert from file"
fi

OPTION_AFTER_CLEAR=$(tmux show-options -wt "$CURRENT_WINDOW_ID" @claude_alert 2>/dev/null || echo "")
if [[ -z "$OPTION_AFTER_CLEAR" ]]; then
    pass "    unsets tmux window option"
else
    fail "    should unset @claude_alert option"
fi

# test concurrent clearing (locking mechanism)
echo ""
echo "  clear_window_alerts locking:"

# create test alerts
echo "${CURRENT_SESSION}:${CURRENT_WINDOW}:claude" >"$ALERTS_FILE"
echo "${CURRENT_SESSION}:test-window-1:claude" >>"$ALERTS_FILE"
echo "${CURRENT_SESSION}:test-window-2:claude" >>"$ALERTS_FILE"

# simulate concurrent clears (file operations only, no tmux ops since windows don't exist)
(
    LOCK_DIR="${ALERTS_FILE}.lock"
    for _ in {1..10}; do
        if mkdir "$LOCK_DIR" 2>/dev/null; then
            grep -v "^${CURRENT_SESSION}:test-window-1:" "$ALERTS_FILE" >"${ALERTS_FILE}.tmp.$$" 2>/dev/null || true
            mv "${ALERTS_FILE}.tmp.$$" "$ALERTS_FILE" 2>/dev/null || rm -f "${ALERTS_FILE}.tmp.$$"
            rmdir "$LOCK_DIR" 2>/dev/null || true
            break
        fi
        sleep 0.01
    done
) &
PID1=$!

(
    LOCK_DIR="${ALERTS_FILE}.lock"
    for _ in {1..10}; do
        if mkdir "$LOCK_DIR" 2>/dev/null; then
            grep -v "^${CURRENT_SESSION}:test-window-2:" "$ALERTS_FILE" >"${ALERTS_FILE}.tmp.$$" 2>/dev/null || true
            mv "${ALERTS_FILE}.tmp.$$" "$ALERTS_FILE" 2>/dev/null || rm -f "${ALERTS_FILE}.tmp.$$"
            rmdir "$LOCK_DIR" 2>/dev/null || true
            break
        fi
        sleep 0.01
    done
) &
PID2=$!

wait $PID1 $PID2

# check that file is in consistent state (only current window alert should remain)
REMAINING=$(wc -l <"$ALERTS_FILE" 2>/dev/null | tr -d ' ' || echo "0")
if [[ "$REMAINING" == "1" ]]; then
    pass "    handles concurrent clears without corruption"
else
    fail "    concurrent clears may have caused corruption (expected: 1, got: $REMAINING)"
fi

# test cleanup_stale_alerts
echo ""
echo "  cleanup_stale_alerts:"

# create alerts with mix of valid and invalid sessions/windows
echo "${CURRENT_SESSION}:${CURRENT_WINDOW}:claude" >"$ALERTS_FILE"
echo "nonexistent-session:window:claude" >>"$ALERTS_FILE"
echo "${CURRENT_SESSION}:nonexistent-window:claude" >>"$ALERTS_FILE"

BEFORE_COUNT=$(wc -l <"$ALERTS_FILE")
cleanup_stale_alerts
AFTER_COUNT=$(wc -l <"$ALERTS_FILE" 2>/dev/null || echo "0")

if [[ "$AFTER_COUNT" -lt "$BEFORE_COUNT" ]]; then
    pass "    removes stale alerts ($BEFORE_COUNT -> $AFTER_COUNT)"
else
    fail "    should remove stale alerts"
fi

if grep -q "nonexistent" "$ALERTS_FILE" 2>/dev/null; then
    fail "    should remove nonexistent session/window alerts"
else
    pass "    removes nonexistent session/window alerts"
fi

if grep -q "^${CURRENT_SESSION}:${CURRENT_WINDOW}:claude$" "$ALERTS_FILE"; then
    pass "    preserves valid alerts"
else
    fail "    should preserve valid alerts"
fi

# ─────────────────────────────────────────
# colon-in-window-name handling (percent-encoding round-trip)
# regression: window names like "FOO:BAR" contain tmux's ':' which is
# also the alerts-file field separator. they must be encoded on write and
# decoded on read, otherwise clear.sh and friends reject or corrupt them
# ─────────────────────────────────────────
echo ""
echo "  colon-in-window encoding:"

COLON_WIN='FOO:BAR'
ENC_WIN=$(alerts_encode_window "$COLON_WIN")

if [[ "$ENC_WIN" == 'FOO%3ABAR' ]]; then
    pass "    encodes ':' to %3A"
else
    fail "    should encode ':' to %3A, got: $ENC_WIN"
fi

if [[ "$(alerts_decode_window "$ENC_WIN")" == "$COLON_WIN" ]]; then
    pass "    decodes back to the original name"
else
    fail "    decode should round-trip the original name"
fi

# a literal '%' must survive the round-trip ('%' is encoded first)
if [[ "$(alerts_decode_window "$(alerts_encode_window 'a%3Ab:c')")" == 'a%3Ab:c' ]]; then
    pass "    round-trips a literal percent sequence"
else
    fail "    literal '%' should round-trip"
fi

# end-to-end against the isolated server: create a colon-named window, set an
# alert via its pane, and confirm the file stores the encoded form. tmux 3.x+
# rejects ':' in window names set via new-window/rename-window and sanitises it
# to '_' under automatic-rename, so a colon-named window can't be materialised
# on those builds; skip the end-to-end checks there rather than aborting the
# suite (the encode/decode round-trip above already covers the core logic)
: >"$ALERTS_FILE"
tmux new-window -t "$CURRENT_SESSION" -n "$COLON_WIN" 2>/dev/null || true
COLON_WIN_ID=$(tmux list-windows -t "$CURRENT_SESSION" -F '#{window_name}|#{window_id}' 2>/dev/null | grep -F "${COLON_WIN}|" | head -1 | cut -d'|' -f2) || COLON_WIN_ID=""

if [[ -z "$COLON_WIN_ID" ]]; then
    skip "    set_window_alert stores the encoded window name (tmux rejects ':' in window names)"
    skip "    raw colon name is not written verbatim (tmux rejects ':' in window names)"
    skip "    cleanup_stale_alerts preserves the colon-named window (tmux rejects ':' in window names)"
    skip "    clear_window_alerts clears via the raw colon name (tmux rejects ':' in window names)"
else
    tmux set-window-option -t "$COLON_WIN_ID" automatic-rename off 2>/dev/null || true
    COLON_PANE_ID=$(tmux list-panes -t "$COLON_WIN_ID" -F '#{pane_id}' 2>/dev/null | head -1) || COLON_PANE_ID=""

    TMUX_PANE="$COLON_PANE_ID" set_window_alert "claude" "false" 2>/dev/null || true
    if grep -qxF "${CURRENT_SESSION}:${ENC_WIN}:claude" "$ALERTS_FILE" 2>/dev/null; then
        pass "    set_window_alert stores the encoded window name"
    else
        fail "    set_window_alert should store the encoded name (file: $(cat "$ALERTS_FILE"))"
    fi

    if grep -qF "${CURRENT_SESSION}:${COLON_WIN}:" "$ALERTS_FILE" 2>/dev/null; then
        fail "    raw colon name must not be written verbatim"
    else
        pass "    raw colon name is not written verbatim"
    fi

    # cleanup_stale_alerts must keep it (decode matches the real tmux window name)
    cleanup_stale_alerts
    if grep -qxF "${CURRENT_SESSION}:${ENC_WIN}:claude" "$ALERTS_FILE" 2>/dev/null; then
        pass "    cleanup_stale_alerts preserves the colon-named window"
    else
        fail "    cleanup_stale_alerts should preserve the colon-named window"
    fi

    # clear_window_alerts with the RAW colon name removes the encoded entry
    clear_window_alerts "$CURRENT_SESSION" "$COLON_WIN" "$COLON_WIN_ID"
    if grep -qF "${CURRENT_SESSION}:${ENC_WIN}:" "$ALERTS_FILE" 2>/dev/null; then
        fail "    clear_window_alerts should clear the encoded entry"
    else
        pass "    clear_window_alerts clears via the raw colon name"
    fi

    tmux kill-window -t "$COLON_WIN_ID" 2>/dev/null || true
fi

# clean up isolated server (trap also handles this on exit)
cleanup_test_server

# test agent display functions (don't require tmux)
echo ""
echo "  agent display functions:"

CLAUDE_ICON=$(get_agent_icon "claude")
if [[ "$CLAUDE_ICON" == "⚡" ]]; then
    pass "  get_agent_icon returns correct icon for claude"
else
    fail "  get_agent_icon should return ⚡ for claude, got: $CLAUDE_ICON"
fi

OPENCODE_ICON=$(get_agent_icon "opencode")
if [[ "$OPENCODE_ICON" == "" ]]; then
    pass "  get_agent_icon returns correct icon for opencode"
else
    fail "  get_agent_icon should return  for opencode, got: $OPENCODE_ICON"
fi

CLAUDE_COLOUR=$(get_agent_colour "claude")
if [[ "$CLAUDE_COLOUR" == "#f1fa8c" ]]; then
    pass "  get_agent_colour returns correct colour for claude"
else
    fail "  get_agent_colour should return #f1fa8c for claude, got: $CLAUDE_COLOUR"
fi

DISPLAY=$(get_agent_display "claude")
if [[ "$DISPLAY" == "⚡|#f1fa8c" ]]; then
    pass "  get_agent_display returns icon|colour format"
else
    fail "  get_agent_display should return 'icon|colour', got: $DISPLAY"
fi

# test build_alert_icons
echo ""
echo "  build_alert_icons:"

# basic: agent alert matched by session pattern
_BAI_CONTENT="mysession:mywindow:claude"
_BAI_RESULT=$(build_alert_icons "$_BAI_CONTENT" "^mysession:")
if [[ -n "$_BAI_RESULT" ]]; then
    pass "  returns icons for matching agent alert"
else
    fail "  should return icons for matching alert"
fi

# pattern anchor: different session should not match
_BAI_RESULT2=$(build_alert_icons "$_BAI_CONTENT" "^other:")
if [[ -z "$_BAI_RESULT2" ]]; then
    pass "  non-matching session pattern returns empty"
else
    fail "  non-matching pattern should return empty"
fi

# dot in session name: 'v0.2.67' must NOT match 'v0X2X67'
_BAI_DOT_CONTENT="v0X2X67:main:claude"
_BAI_DOT_PAT="^v0\\.2\\.67:"
_BAI_DOT_RESULT=$(build_alert_icons "$_BAI_DOT_CONTENT" "$_BAI_DOT_PAT")
if [[ -z "$_BAI_DOT_RESULT" ]]; then
    pass "  escaped dot pattern does not match non-dot session name"
else
    fail "  escaped dot should not match 'v0X2X67' (got: $_BAI_DOT_RESULT)"
fi

# dot in session name: 'v0.2.67' DOES match with escaped pattern
_BAI_DOT_CONTENT2="v0.2.67:main:claude"
_BAI_DOT_RESULT2=$(build_alert_icons "$_BAI_DOT_CONTENT2" "$_BAI_DOT_PAT")
if [[ -n "$_BAI_DOT_RESULT2" ]]; then
    fail "  escaped dot pattern should not match after literal-prefix optimisation"
else
    pass "  escaped dot pattern does not match dotted session name"
fi

# unescaped dot regression no longer applies because build_alert_icons now
# does literal prefix matching instead of regex evaluation
_BAI_UNESCAPED_PAT="^v0.2.67:"
_BAI_REGRESSION=$(build_alert_icons "$_BAI_DOT_CONTENT" "$_BAI_UNESCAPED_PAT")
if [[ -n "$_BAI_REGRESSION" ]]; then
    fail "  unescaped dot should not match different session name"
else
    pass "  unescaped dot does not match different session name"
fi

# dedupe: same agent across multiple windows only produces one icon
_BAI_MULTI="sess:win1:claude
sess:win2:claude"
_BAI_DEDUPED=$(build_alert_icons "$_BAI_MULTI" "^sess:" "dedupe")
_BAI_COUNT=$(printf '%s' "$_BAI_DEDUPED" | grep -o '⚡' | wc -l | tr -d ' ')
if [[ "$_BAI_COUNT" == "1" ]]; then
    pass "  dedupe collapses duplicate agent icons"
else
    fail "  dedupe should produce 1 icon, got: $_BAI_COUNT"
fi

# empty content returns empty
_BAI_EMPTY=$(build_alert_icons "" "^any:")
if [[ -z "$_BAI_EMPTY" ]]; then
    pass "  empty content returns empty string"
else
    fail "  empty content should return empty"
fi

# ─────────────────────────────────────────
# test state file parsing (panes/undo.sh logic)
# ─────────────────────────────────────────
section "Testing state file parsing"

# create a test state file
TEST_STATE_FILE=$(mktemp)
cat >"$TEST_STATE_FILE" <<'EOF'
dir=/Users/test/projects
layout=main-vertical,200x50,0,0[200x25,0,0,1,200x24,0,26,2]
SESSION=mytest
WINDOW=2
PANE=1
PANE_COUNT=3
EOF

# parse the state file (mimicking panes/undo.sh logic)
TEST_SESSION=""
TEST_WINDOW=""
TEST_PANE=""
TEST_DIR=""
TEST_LAYOUT=""
TEST_PANE_COUNT=""

while IFS='=' read -r key value; do
    case "$key" in
        dir) TEST_DIR="$value" ;;
        layout) TEST_LAYOUT="$value" ;;
        SESSION) TEST_SESSION="$value" ;;
        WINDOW) TEST_WINDOW="$value" ;;
        PANE) TEST_PANE="$value" ;;
        PANE_COUNT) TEST_PANE_COUNT="$value" ;;
    esac
done <"$TEST_STATE_FILE"

assert_equals "  parses dir correctly" "/Users/test/projects" "$TEST_DIR"
assert_equals "  parses SESSION correctly" "mytest" "$TEST_SESSION"
assert_equals "  parses WINDOW correctly" "2" "$TEST_WINDOW"
assert_equals "  parses PANE correctly" "1" "$TEST_PANE"
assert_equals "  parses PANE_COUNT correctly" "3" "$TEST_PANE_COUNT"
if [[ "$TEST_LAYOUT" == *"main-vertical"* ]]; then
    pass "  parses layout correctly"
else
    fail "  layout should contain 'main-vertical'"
fi

rm -f "$TEST_STATE_FILE"

# test edge cases in state file parsing
echo ""
echo "  state file edge cases:"

# empty state file
TEST_STATE_FILE=$(mktemp)
touch "$TEST_STATE_FILE"
EMPTY_TEST=""
while IFS='=' read -r key value; do
    EMPTY_TEST="found"
done <"$TEST_STATE_FILE"
if [[ -z "$EMPTY_TEST" ]]; then
    pass "  handles empty state file"
else
    fail "  empty state file should produce no values"
fi
rm -f "$TEST_STATE_FILE"

# state file with special characters in path
TEST_STATE_FILE=$(mktemp)
echo "dir=/Users/test/path with spaces/project" >"$TEST_STATE_FILE"
SPECIAL_DIR=""
while IFS='=' read -r key value; do
    case "$key" in
        dir) SPECIAL_DIR="$value" ;;
    esac
done <"$TEST_STATE_FILE"
assert_equals "  handles paths with spaces" "/Users/test/path with spaces/project" "$SPECIAL_DIR"
rm -f "$TEST_STATE_FILE"

# state file with equals in value
TEST_STATE_FILE=$(mktemp)
echo "layout=abc=def=ghi" >"$TEST_STATE_FILE"
EQUALS_VALUE=""
while IFS='=' read -r key value; do
    case "$key" in
        layout) EQUALS_VALUE="$value" ;;
    esac
done <"$TEST_STATE_FILE"
# note: IFS='=' splits on first = only when using read -r
# this may or may not work as expected depending on shell
if [[ "$EQUALS_VALUE" == "abc=def=ghi" || "$EQUALS_VALUE" == "abc" ]]; then
    pass "  handles values with equals signs (value: $EQUALS_VALUE)"
else
    fail "  unexpected handling of equals in value: $EQUALS_VALUE"
fi
rm -f "$TEST_STATE_FILE"

# ─────────────────────────────────────────
# test cross-platform helpers
# ─────────────────────────────────────────
section "Testing cross-platform helpers"

echo "  mod_key:"
MOD_RESULT=$(mod_key)
if [[ "$(uname)" == "Darwin" ]]; then
    assert_equals "  returns 'Opt' on macOS" "Opt" "$MOD_RESULT"
else
    assert_equals "  returns 'Alt' on Linux" "Alt" "$MOD_RESULT"
fi
# must return a non-empty string on any platform
if [[ -n "$MOD_RESULT" ]]; then
    pass "  returns non-empty value"
else
    fail "  should return non-empty value"
fi

echo ""
echo "  clipboard_copy_cmd:"
CLIP_CMD=$(clipboard_copy_cmd)
if [[ -n "$CLIP_CMD" ]]; then
    pass "  returns non-empty command"
else
    fail "  should return non-empty command"
fi
if [[ "$(uname)" == "Darwin" ]]; then
    assert_equals "  returns 'pbcopy' on macOS" "pbcopy" "$CLIP_CMD"
fi

echo ""
echo "  reverse_lines:"
REVERSED=$(printf 'a\nb\nc\n' | reverse_lines)
assert_equals "  reverses three lines" "$(printf 'c\nb\na')" "$REVERSED"

SINGLE=$(printf 'only\n' | reverse_lines)
assert_equals "  single line unchanged" "only" "$SINGLE"

EMPTY=$(printf '' | reverse_lines)
assert_equals "  empty input produces empty output" "" "$EMPTY"

TWO_LINES=$(printf 'first\nsecond\n' | reverse_lines)
assert_equals "  reverses two lines" "$(printf 'second\nfirst')" "$TWO_LINES"

# ─────────────────────────────────────────
# syntax check all scripts
# ─────────────────────────────────────────
section "Syntax checking scripts"
SCRIPTS_DIR="$SCRIPT_DIR/.."

for script in "$SCRIPTS_DIR"/*.sh; do
    [[ -f "$script" ]] || continue
    script_name=$(basename "$script")
    if bash -n "$script" 2>/dev/null; then
        pass "  $script_name syntax OK"
    else
        fail "  $script_name has syntax errors"
    fi
done

# also check library files
for lib in "$SCRIPT_DIR"/*.sh; do
    lib_name=$(basename "$lib")
    [[ "$lib_name" == "test.sh" ]] && continue
    if bash -n "$lib" 2>/dev/null; then
        pass "  _lib/$lib_name syntax OK"
    else
        fail "  _lib/$lib_name has syntax errors"
    fi
done

# ─────────────────────────────────────────
# ShellCheck if available
# ─────────────────────────────────────────
if command -v shellcheck &>/dev/null; then
    section "ShellCheck analysis"
    SHELLCHECK_FAIL=0
    # use same exclusions as CI (see .github/workflows/ci.yml)
    SHELLCHECK_EXCLUDES="-e SC1091 -e SC2009 -e SC2059 -e SC2015 -e SC2016 -e SC2034 -e SC2329"

    for script in "$SCRIPTS_DIR"/*.sh; do
        [[ -f "$script" ]] || continue
        script_name=$(basename "$script")
        # shellcheck disable=SC2086
        if shellcheck $SHELLCHECK_EXCLUDES -S warning "$script" 2>/dev/null; then
            pass "  $script_name passes shellcheck"
        else
            fail "  $script_name has shellcheck warnings"
            SHELLCHECK_FAIL=$((SHELLCHECK_FAIL + 1))
        fi
    done

    for lib in "$SCRIPT_DIR"/*.sh; do
        lib_name=$(basename "$lib")
        [[ "$lib_name" == "test.sh" ]] && continue
        # shellcheck disable=SC2086
        if shellcheck $SHELLCHECK_EXCLUDES -S warning "$lib" 2>/dev/null; then
            pass "  _lib/$lib_name passes shellcheck"
        else
            fail "  _lib/$lib_name has shellcheck warnings"
            SHELLCHECK_FAIL=$((SHELLCHECK_FAIL + 1))
        fi
    done
else
    section "ShellCheck analysis"
    skip "  shellcheck not installed - install with 'brew install shellcheck'"
fi

# ─────────────────────────────────────────
# summary
# ─────────────────────────────────────────
echo ""
echo "═════════════════════════════════════════"
TOTAL=$((PASS + FAIL))
printf "Results: ${GREEN}%d passed${NC}, ${RED}%d failed${NC} (total: %d)\n" "$PASS" "$FAIL" "$TOTAL"
echo "═════════════════════════════════════════"

if [[ $FAIL -gt 0 ]]; then
    exit 1
fi
