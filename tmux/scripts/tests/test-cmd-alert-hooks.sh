#!/usr/bin/env bash
set -euo pipefail

# tests for command exit alert hooks
# tests exit code display functions, cmd-alert.sh, cmd-alert-hook.zsh, and alert file format

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_DIR="$(dirname "$SCRIPT_DIR")"
DOTFILES_ROOT="$(cd "$SCRIPTS_DIR/../.." && pwd)"

# source test helpers to get isolated tmux server
source "$SCRIPT_DIR/_test-helpers.sh"

# trap to ensure cleanup on exit/interrupt
ALERT_TEST_DIR=""
trap 'rm -rf "$ALERT_TEST_DIR"; cleanup_test_server' EXIT INT TERM

# setup isolated tmux server
setup_test_server

# create temp directory for alerts file
ALERT_TEST_DIR=$(mktemp -d)
export ALERTS_FILE="$ALERT_TEST_DIR/alerts"
# set before sourcing alerts.sh so it isn't frozen to the real path via readonly
export FINISHED_FILE="$ALERT_TEST_DIR/finished"
# isolate the running registry too so proclist.sh can't touch the real one
export RUNNING_DIR="$ALERT_TEST_DIR/running"

# create a test session
TEST_SESSION="test-cmd-alerts-$$"
test_tmux new-session -d -s "$TEST_SESSION" -n "testwin" -c /tmp

# source production libraries (after setup so tmux wrapper is active)
source "$SCRIPTS_DIR/_lib/common.sh"
source "$SCRIPTS_DIR/_lib/alerts.sh"

HOOKS_DIR="$DOTFILES_ROOT/scripts/hooks"

# ═══════════════════════════════════════════════════════════════
# hook script existence and syntax
# ═══════════════════════════════════════════════════════════════

section "Hook Script Existence and Syntax"

for script in cmd-alert.sh cmd-alert-hook.zsh; do
    if [[ -f "$HOOKS_DIR/$script" ]]; then
        pass "$script exists"
    else
        fail "$script not found at $HOOKS_DIR/$script"
    fi

    if bash -n "$HOOKS_DIR/$script" 2>/dev/null; then
        pass "$script passes syntax check"
    else
        fail "$script has syntax errors"
    fi
done

if [[ -x "$HOOKS_DIR/cmd-alert.sh" ]]; then
    pass "cmd-alert.sh is executable"
else
    fail "cmd-alert.sh should be executable"
fi

# ═══════════════════════════════════════════════════════════════
# exit code display functions
# ═══════════════════════════════════════════════════════════════

section "Exit Code Display Functions"

assert_equals "Exit 0 icon is ✓" "✓" "$(get_exit_code_icon 0)"
assert_equals "Exit 1 icon is ✗" "✗" "$(get_exit_code_icon 1)"
assert_equals "Exit 127 icon is ✗" "✗" "$(get_exit_code_icon 127)"
assert_equals "Exit 0 colour is green" "#7aab88" "$(get_exit_code_colour 0)"
assert_equals "Exit 1 colour is red" "#c07878" "$(get_exit_code_colour 1)"
assert_equals "Exit 0 display" "✓|#7aab88" "$(get_exit_code_display 0)"
assert_equals "Exit 1 display" "✗|#c07878" "$(get_exit_code_display 1)"

# ═══════════════════════════════════════════════════════════════
# alert file format
# ═══════════════════════════════════════════════════════════════

section "Alert File Format"

# 6-field format: session:window:exit:window_id:code:label
echo "$TEST_SESSION:testwin:exit:@5:0:make test" >"$ALERTS_FILE"
if grep -q "exit:@5:0:make test" "$ALERTS_FILE"; then
    pass "Exit alert with window_id and label written to alerts file"
else
    fail "Exit alert should include window_id, exit code and label"
fi

clear_window_alerts "$TEST_SESSION" "testwin" 2>/dev/null || true
if [[ -f "$ALERTS_FILE" ]]; then
    remaining=$(cat "$ALERTS_FILE")
    if [[ -z "$remaining" ]] || [[ "$remaining" != *"$TEST_SESSION:testwin"* ]]; then
        pass "clear_window_alerts removes exit alert entries"
    else
        fail "clear_window_alerts should remove exit entries (remaining: '$remaining')"
    fi
else
    pass "clear_window_alerts removed all entries (file gone)"
fi

# agent and exit alerts coexist correctly
echo "other-session:main:claude" >"$ALERTS_FILE"
echo "$TEST_SESSION:testwin:exit:@6:1:npm run lint" >>"$ALERTS_FILE"
clear_window_alerts "$TEST_SESSION" "testwin" 2>/dev/null || true
if [[ -f "$ALERTS_FILE" ]] && grep -q "other-session:main:claude" "$ALERTS_FILE"; then
    pass "clear_window_alerts preserves agent alerts from other sessions"
else
    fail "clear_window_alerts should preserve unrelated entries"
fi

# exit alerts are keyed on window_id, not the (auto-rename-volatile) name:
# clear_window_exit_alert drops the line by id even when the stored name differs
# from the live window name
echo "other-session:main:claude" >"$ALERTS_FILE"
echo "$TEST_SESSION:staleoldname:exit:@42:0:make test" >>"$ALERTS_FILE"
clear_window_exit_alert "@42" 2>/dev/null || true
if grep -q ":exit:@42:" "$ALERTS_FILE" 2>/dev/null; then
    fail "clear_window_exit_alert should drop the exit line by window_id"
else
    pass "clear_window_exit_alert drops the exit line by window_id (name-agnostic)"
fi
if grep -q "other-session:main:claude" "$ALERTS_FILE" 2>/dev/null; then
    pass "clear_window_exit_alert leaves agent alerts intact"
else
    fail "clear_window_exit_alert should not touch agent alerts"
fi

# a non-matching id is a no-op
echo "$TEST_SESSION:w:exit:@7:0:cmd" >"$ALERTS_FILE"
clear_window_exit_alert "@8" 2>/dev/null || true
if grep -q ":exit:@7:" "$ALERTS_FILE" 2>/dev/null; then
    pass "clear_window_exit_alert leaves non-matching exit lines alone"
else
    fail "clear_window_exit_alert should only drop the matching window_id"
fi

# ═══════════════════════════════════════════════════════════════
# finished-history clearing (proclist "done" rows clear on view)
# ═══════════════════════════════════════════════════════════════

section "Finished History Clearing"

TAB=$(printf '\t')

# fields: finish_epoch<tab>exit<tab>session<tab>window_id<tab>window<tab>label
printf '%s\n' \
    "1000${TAB}0${TAB}$TEST_SESSION${TAB}@5${TAB}testwin${TAB}make test" \
    "1001${TAB}1${TAB}$TEST_SESSION${TAB}@6${TAB}other${TAB}npm run lint" \
    >"$FINISHED_FILE"

clear_window_finished "@5" 2>/dev/null || true
if grep -q "$TAB@5$TAB" "$FINISHED_FILE"; then
    fail "clear_window_finished should drop the matching window_id row"
else
    pass "clear_window_finished drops the matching window_id row"
fi
if grep -q "$TAB@6$TAB" "$FINISHED_FILE"; then
    pass "clear_window_finished preserves rows for other windows"
else
    fail "clear_window_finished should preserve unrelated window rows"
fi

# empty window_id is a no-op (the only reliable key); nothing removed
printf '%s\n' "1002${TAB}0${TAB}$TEST_SESSION${TAB}@7${TAB}w${TAB}cmd" >"$FINISHED_FILE"
clear_window_finished "" 2>/dev/null || true
if grep -q "$TAB@7$TAB" "$FINISHED_FILE"; then
    pass "clear_window_finished no-ops on empty window_id"
else
    fail "clear_window_finished should not touch the file without a window_id"
fi

# clear_window_alerts also clears finished rows for the same window on select
printf '%s\n' "1003${TAB}0${TAB}$TEST_SESSION${TAB}@8${TAB}testwin${TAB}cmd" >"$FINISHED_FILE"
clear_window_alerts "$TEST_SESSION" "testwin" "@8" 2>/dev/null || true
if grep -q "$TAB@8$TAB" "$FINISHED_FILE"; then
    fail "clear_window_alerts should clear finished rows for the selected window"
else
    pass "clear_window_alerts clears finished rows for the selected window"
fi

# clear_session_finished drops every window's rows for the session at once
# (a destroyed session takes all its windows down, including ones closed earlier)
printf '%s\n' \
    "1004${TAB}0${TAB}$TEST_SESSION${TAB}@9${TAB}win-a${TAB}cmd-a" \
    "1005${TAB}1${TAB}$TEST_SESSION${TAB}@10${TAB}win-b${TAB}cmd-b" \
    "1006${TAB}0${TAB}other-session${TAB}@11${TAB}win-c${TAB}cmd-c" \
    >"$FINISHED_FILE"
clear_session_finished "$TEST_SESSION" 2>/dev/null || true
if grep -q "$TAB$TEST_SESSION$TAB" "$FINISHED_FILE"; then
    fail "clear_session_finished should drop all rows for the session"
else
    pass "clear_session_finished drops all rows for the session"
fi
if grep -q "${TAB}other-session${TAB}" "$FINISHED_FILE"; then
    pass "clear_session_finished preserves rows for other sessions"
else
    fail "clear_session_finished should preserve rows for other sessions"
fi

# empty session is a no-op
printf '%s\n' "1007${TAB}0${TAB}$TEST_SESSION${TAB}@12${TAB}w${TAB}cmd" >"$FINISHED_FILE"
clear_session_finished "" 2>/dev/null || true
if grep -q "$TAB@12$TAB" "$FINISHED_FILE"; then
    pass "clear_session_finished no-ops on empty session"
else
    fail "clear_session_finished should not touch the file without a session"
fi

# clear_session_alerts also clears the session's finished rows
printf '%s\n' "1008${TAB}0${TAB}$TEST_SESSION${TAB}@13${TAB}win${TAB}cmd" >"$FINISHED_FILE"
clear_session_alerts "$TEST_SESSION" 2>/dev/null || true
if grep -q "$TAB@13$TAB" "$FINISHED_FILE"; then
    fail "clear_session_alerts should clear finished rows for the session"
else
    pass "clear_session_alerts clears finished rows for the session"
fi

# ═══════════════════════════════════════════════════════════════
# command rerun (proclist r/R bindings)
# ═══════════════════════════════════════════════════════════════

section "Command Rerun (r/R)"

# the hook stores the full command as typed ($1, pre-expansion) so $VAR
# references survive as references, not values, and the command isn't truncated
if command -v zsh &>/dev/null; then
    cmd_out=$(DB_PASS=topsecret zsh -c '
        source "'"$HOOKS_DIR/cmd-alert-hook.zsh"'" 2>/dev/null
        _cmd_alert_preexec '\''mysql -p$DB_PASS --host db.internal mydb'\''
        echo "$_cmd_alert_cmd"
    ' 2>/dev/null)
    assert_equals "rerun cmd keeps full command, \$VAR unexpanded" \
        'mysql -p$DB_PASS --host db.internal mydb' "$cmd_out"
    if [[ "$cmd_out" == *topsecret* ]]; then
        fail "rerun cmd must not expand \$VAR to its secret value"
    else
        pass "rerun cmd does not store the resolved secret value"
    fi
    if [[ "$cmd_out" == *mydb ]]; then
        pass "rerun cmd is the full command, not the truncated label"
    else
        fail "rerun cmd should not be truncated like the status-bar label"
    fi
else
    skip "zsh not available — skipping rerun cmd capture tests"
fi

# proclist-rerun.sh pastes the right row's command into its window's pane,
# matched by epoch+window_id; an unrelated row must not be pasted
test_tmux new-window -t "$TEST_SESSION" -n "rerunwin" -c /tmp 2>/dev/null || true
RW_ID=$(test_tmux list-windows -t "$TEST_SESSION" -F '#{window_name} #{window_id}' 2>/dev/null |
    awk '$1=="rerunwin"{print $2; exit}')
if [[ -n "$RW_ID" ]]; then
    printf '%s\n' \
        "2000${TAB}1${TAB}$TEST_SESSION${TAB}@99999${TAB}gone${TAB}decoy${TAB}echo DECOYCMD" \
        "2001${TAB}1${TAB}$TEST_SESSION${TAB}$RW_ID${TAB}rerunwin${TAB}grep needle${TAB}grep -r RERUNNEEDLE src/" \
        >"$FINISHED_FILE"
    bash "$SCRIPTS_DIR/alerts/proclist-rerun.sh" 2001 "$RW_ID" 2>/dev/null || true
    sleep 0.4
    pasted=$(test_tmux capture-pane -t "$RW_ID" -p 2>/dev/null | tr -d '\000')
    if [[ "$pasted" == *"grep -r RERUNNEEDLE src/"* ]]; then
        pass "proclist-rerun (stage) types the matched row's command into its window"
    else
        fail "proclist-rerun should stage the matched command (pane: '$pasted')"
    fi
    if [[ "$pasted" == *DECOYCMD* ]]; then
        fail "proclist-rerun pasted an unrelated row's command"
    else
        pass "proclist-rerun ignores rows that don't match epoch+window_id"
    fi
else
    skip "could not create rerun test window — skipping paste test"
fi

# run mode (R) executes the command; stage mode (r) leaves it unexecuted. assert
# via a side effect (a touched file) on a fresh window so leftover prompt text
# from the stage test above can't interfere
test_tmux new-window -t "$TEST_SESSION" -n "execwin" -c /tmp 2>/dev/null || true
EW_ID=$(test_tmux list-windows -t "$TEST_SESSION" -F '#{window_name} #{window_id}' 2>/dev/null |
    awk '$1=="execwin"{print $2; exit}')
if [[ -n "$EW_ID" ]]; then
    EXEC_MARK="$ALERT_TEST_DIR/exec_ran"

    rm -f "$EXEC_MARK"
    printf '%s\n' "3001${TAB}0${TAB}$TEST_SESSION${TAB}$EW_ID${TAB}execwin${TAB}touch${TAB}touch $EXEC_MARK" \
        >"$FINISHED_FILE"
    bash "$SCRIPTS_DIR/alerts/proclist-rerun.sh" 3001 "$EW_ID" exec 2>/dev/null || true
    sleep 0.6
    if [[ -f "$EXEC_MARK" ]]; then
        pass "proclist-rerun (run) executes the command immediately"
    else
        fail "proclist-rerun run mode should execute the command (marker missing)"
    fi

    rm -f "$EXEC_MARK"
    printf '%s\n' "3002${TAB}0${TAB}$TEST_SESSION${TAB}$EW_ID${TAB}execwin${TAB}touch${TAB}touch $EXEC_MARK" \
        >"$FINISHED_FILE"
    bash "$SCRIPTS_DIR/alerts/proclist-rerun.sh" 3002 "$EW_ID" 2>/dev/null || true
    sleep 0.6
    if [[ ! -f "$EXEC_MARK" ]]; then
        pass "proclist-rerun (stage) does not execute the command"
    else
        fail "proclist-rerun stage mode must not run the command"
    fi
else
    skip "could not create exec test window — skipping stage/run mode tests"
fi

# proclist.sh GC rewrite must preserve the cmd field on rows it keeps
if [[ -n "$RW_ID" ]]; then
    NOW=$(date +%s)
    printf '%s\n' \
        "100${TAB}0${TAB}$TEST_SESSION${TAB}@5${TAB}old${TAB}old${TAB}echo STALECMD" \
        "${NOW}${TAB}0${TAB}$TEST_SESSION${TAB}$RW_ID${TAB}rerunwin${TAB}fresh${TAB}grep -r KEEPCMD src/" \
        >"$FINISHED_FILE"
    bash "$SCRIPTS_DIR/alerts/proclist.sh" >/dev/null 2>&1 || true
    remaining=$(cat "$FINISHED_FILE" 2>/dev/null || true)
    if [[ "$remaining" != *STALECMD* ]]; then
        pass "proclist GC drops the stale finished row"
    else
        fail "proclist GC should drop rows older than the age cutoff"
    fi
    if [[ "$remaining" == *"grep -r KEEPCMD src/"* ]]; then
        pass "proclist GC preserves the cmd field on kept rows"
    else
        fail "proclist GC dropped the cmd field (remaining: '$remaining')"
    fi
else
    skip "no rerun test window — skipping GC preservation test"
fi

# ═══════════════════════════════════════════════════════════════
# set_exit_alert Function
# ═══════════════════════════════════════════════════════════════

section "set_exit_alert Function"

: >"$ALERTS_FILE"

test_tmux set-option -wt "$TEST_SESSION:testwin" "@exit_alert" 1 2>/dev/null || true
test_tmux set-option -wt "$TEST_SESSION:testwin" "@exit_alert_colour" "#50fa7b" 2>/dev/null || true

alert_value=$(test_tmux show-options -wt "$TEST_SESSION:testwin" -v "@exit_alert" 2>/dev/null) || alert_value=""
if [[ "$alert_value" == "1" ]]; then
    pass "set_exit_alert sets @exit_alert option"
else
    fail "set_exit_alert should set @exit_alert to 1 (got: '$alert_value')"
fi

colour_value=$(test_tmux show-options -wt "$TEST_SESSION:testwin" -v "@exit_alert_colour" 2>/dev/null) || colour_value=""
if [[ "$colour_value" == "#50fa7b" ]]; then
    pass "set_exit_alert sets @exit_alert_colour for exit 0"
else
    fail "set_exit_alert should set @exit_alert_colour to #50fa7b (got: '$colour_value')"
fi

# ═══════════════════════════════════════════════════════════════
# cmd-alert-hook.zsh: label truncation logic
# ═══════════════════════════════════════════════════════════════

section "Hook Label Truncation"

# test label building via zsh (the hook uses zsh-specific (z) word splitting)
if command -v zsh &>/dev/null; then
    label=$(zsh -c '
        source "'"$HOOKS_DIR/cmd-alert-hook.zsh"'" 2>/dev/null
        _cmd_alert_preexec "make test"
        echo "$_cmd_alert_label"
    ' 2>/dev/null)
    assert_equals "2-word command: make test" "make test" "$label"

    label=$(zsh -c '
        source "'"$HOOKS_DIR/cmd-alert-hook.zsh"'" 2>/dev/null
        _cmd_alert_preexec "npm run build"
        echo "$_cmd_alert_label"
    ' 2>/dev/null)
    assert_equals "3-word command: npm run build" "npm run build" "$label"

    label=$(zsh -c '
        _CMD_ALERT_EXCLUDE=()
        source "'"$HOOKS_DIR/cmd-alert-hook.zsh"'" 2>/dev/null
        _cmd_alert_preexec "docker compose -f prod.yml up --build"
        echo "$_cmd_alert_label"
    ' 2>/dev/null)
    assert_equals "5-word command truncated to 2+ellipsis" "docker compose…" "$label"

    label=$(zsh -c '
        source "'"$HOOKS_DIR/cmd-alert-hook.zsh"'" 2>/dev/null
        _cmd_alert_preexec "./scripts/run-tests.sh --verbose"
        echo "$_cmd_alert_label"
    ' 2>/dev/null)
    assert_equals "Path-prefixed command strips ./ from basename" "run-tests.sh --verbose" "$label"

    # nested launcher alias (regression: config -> v -> "cl && nvim" used to
    # slip through the old first-word guard, both the aliases[$first]
    # version and a later $2-based version. our real `cl` alias is itself
    # compound (contains a `;`), and zsh's $2 (history-expansion) truncates
    # right after a nested alias's own `;`-separated body, silently dropping
    # everything chained after it -- so "config" resolved via $2 loses the
    # "&& nvim ~/.config" tail entirely. these are the verbatim $2/$3 values
    # captured from a real interactive zsh (via `preexec` instrumented live)
    # for typing "config": $2 truncated, $3 (what actually executes) intact
    real_2='printf '"'"'\033[2J\033[3J\033[H'"'"'; [[ -n $TMUX ]] && tmux clear-history || true '
    real_3='printf '"'"'\033[2J\033[3J\033[H'"'"'
[[ -n $TMUX ]] && tmux clear-history || true && nvim ~/.config'
    start=$(zsh -c '
        source "'"$HOOKS_DIR/cmd-alert-hook.zsh"'" 2>/dev/null
        _cmd_alert_preexec "config" "$1" "$2"
        echo "$_cmd_alert_start:[$_cmd_alert_label]"
    ' _ "$real_2" "$real_3" 2>/dev/null)
    assert_equals "Nested clear-then-run alias via real compound cl (config -> v -> cl && nvim) is excluded" \
        "-1:[]" "$start"

    # same chain but only $2 available (no $3) demonstrates why $2 alone is
    # unsafe: the truncated tail leaves "true" as the last segment, which
    # isn't in the exclude list, so this must NOT be excluded
    start=$(zsh -c '
        source "'"$HOOKS_DIR/cmd-alert-hook.zsh"'" 2>/dev/null
        _cmd_alert_preexec "config" "$1"
        echo "$_cmd_alert_start:[$_cmd_alert_label]"
    ' _ "$real_2" 2>/dev/null)
    if [[ "$start" != "-1:[]" ]]; then
        pass "Truncated \$2 alone (no \$3) would wrongly track config -- confirms \$3 is required"
    else
        fail "Expected the truncated-\$2-only case to still track (sanity check on the regression), got: $start"
    fi
else
    skip "zsh not available — skipping label truncation tests"
fi

# ═══════════════════════════════════════════════════════════════
# cmd-alert-hook.zsh: threshold and window-switch guard
# ═══════════════════════════════════════════════════════════════

section "Hook Threshold and Window Guard"

if command -v zsh &>/dev/null; then
    # alert should NOT fire when elapsed < threshold
    fired=$(zsh -c '
        export ALERTS_FILE="'"$ALERT_TEST_DIR/alerts-threshold"'"
        export _CMD_ALERT_SCRIPT="'"$HOOKS_DIR/cmd-alert.sh"'"
        export _CMD_ALERT_MIN_SECONDS=9999
        source "'"$HOOKS_DIR/cmd-alert-hook.zsh"'" 2>/dev/null
        _cmd_alert_preexec "make test"
        _cmd_alert_precmd
        [[ -f "$ALERTS_FILE" ]] && cat "$ALERTS_FILE" || true
    ' 2>/dev/null)
    if [[ -z "$fired" ]]; then
        pass "No alert when elapsed < threshold"
    else
        fail "Should not alert when elapsed < threshold (got: '$fired')"
    fi

    # alert should NOT fire if still in the same window (no TMUX set)
    fired=$(zsh -c '
        export ALERTS_FILE="'"$ALERT_TEST_DIR/alerts-nowindow"'"
        export _CMD_ALERT_SCRIPT="'"$HOOKS_DIR/cmd-alert.sh"'"
        export _CMD_ALERT_MIN_SECONDS=0
        unset TMUX
        source "'"$HOOKS_DIR/cmd-alert-hook.zsh"'" 2>/dev/null
        _cmd_alert_preexec "make test"
        _cmd_alert_precmd
        [[ -f "$ALERTS_FILE" ]] && cat "$ALERTS_FILE" || true
    ' 2>/dev/null)
    if [[ -z "$fired" ]]; then
        pass "No alert when not inside tmux"
    else
        fail "Should not alert outside tmux (got: '$fired')"
    fi
else
    skip "zsh not available — skipping threshold/window guard tests"
fi

# ═══════════════════════════════════════════════════════════════
# view guard: alert fires when no client is viewing the origin pane
# (regression: switching to another *session* used to wrongly suppress it,
#  because display-message from a background pane returns the origin session's
#  active pane. the guard now matches the origin pane against every client's
#  active pane via list-clients. with no client attached the pane is unviewed,
#  so the alert must fire — the buggy guard suppressed it here)
# ═══════════════════════════════════════════════════════════════

section "Exit Alert View Guard"

if command -v zsh &>/dev/null; then
    GUARD_AF="$ALERT_TEST_DIR/alerts-guard"
    : >"$GUARD_AF"
    # route the hook's bare tmux calls to the isolated server via $TMUX, so the
    # guard sees this server's (empty) client list, not the user's real one
    G_SP=$(test_tmux display-message -p '#{socket_path}' 2>/dev/null)
    G_PID=$(test_tmux display-message -p '#{pid}' 2>/dev/null)
    G_PANE=$(test_tmux display-message -t "$TEST_SESSION:testwin" -p '#{pane_id}' 2>/dev/null)
    guard_out=$(TMUX="$G_SP,$G_PID,0" TMUX_PANE="$G_PANE" \
        ALERTS_FILE="$GUARD_AF" \
        _CMD_FINISHED_FILE="$ALERT_TEST_DIR/fin-guard" \
        _CMD_RUNNING_DIR="$ALERT_TEST_DIR/run-guard" \
        _CMD_ALERT_SCRIPT="$HOOKS_DIR/cmd-alert.sh" \
        _CMD_ALERT_MIN_SECONDS=0 \
        zsh -c '
            source "'"$HOOKS_DIR/cmd-alert-hook.zsh"'" 2>/dev/null
            _cmd_alert_start=0
            _cmd_alert_pane="'"$G_PANE"'"
            _cmd_alert_label="guardjob"
            _cmd_alert_cmd="false"
            false; _cmd_alert_precmd
            [[ -f "'"$GUARD_AF"'" ]] && cat "'"$GUARD_AF"'"
        ' 2>/dev/null)
    if [[ "$guard_out" == *":exit:"*"guardjob"* ]]; then
        pass "exit alert fires when origin pane isn't viewed (session-switch case)"
    else
        fail "exit alert should fire when no client views the origin pane (got: '$guard_out')"
    fi
else
    skip "zsh not available — skipping view guard test"
fi

# ═══════════════════════════════════════════════════════════════
# kill-suppress marker: proclist's x-binding drops a marker file before
# interrupting a tracked command; precmd must skip both the alert and the
# finished-history row for that completion, and consume (delete) the marker
# ═══════════════════════════════════════════════════════════════

section "Kill Suppress Marker"

if command -v zsh &>/dev/null; then
    SUP_AF="$ALERT_TEST_DIR/alerts-suppress"
    SUP_FF="$ALERT_TEST_DIR/fin-suppress"
    SUP_DIR="$ALERT_TEST_DIR/suppress-marker"
    : >"$SUP_AF"
    mkdir -p "$SUP_DIR"
    S_SP=$(test_tmux display-message -p '#{socket_path}' 2>/dev/null)
    S_PID=$(test_tmux display-message -p '#{pid}' 2>/dev/null)
    S_PANE=$(test_tmux display-message -t "$TEST_SESSION:testwin" -p '#{pane_id}' 2>/dev/null)
    : >"$SUP_DIR/${S_PANE#%}"
    suppress_out=$(TMUX="$S_SP,$S_PID,0" TMUX_PANE="$S_PANE" \
        ALERTS_FILE="$SUP_AF" \
        _CMD_FINISHED_FILE="$SUP_FF" \
        _CMD_RUNNING_DIR="$ALERT_TEST_DIR/run-suppress" \
        _CMD_SUPPRESS_DIR="$SUP_DIR" \
        _CMD_ALERT_SCRIPT="$HOOKS_DIR/cmd-alert.sh" \
        _CMD_ALERT_MIN_SECONDS=0 \
        zsh -c '
            source "'"$HOOKS_DIR/cmd-alert-hook.zsh"'" 2>/dev/null
            _cmd_alert_start=0
            _cmd_alert_pane="'"$S_PANE"'"
            _cmd_alert_label="killedjob"
            _cmd_alert_cmd="sleep 100"
            false; _cmd_alert_precmd
            echo "alerts:$(cat "'"$SUP_AF"'" 2>/dev/null)"
            echo "finished:$(cat "'"$SUP_FF"'" 2>/dev/null)"
            echo "marker:$([[ -e "'"$SUP_DIR/${S_PANE#%}"'" ]] && echo present || echo gone)"
        ' 2>/dev/null)
    if [[ "$suppress_out" == *"alerts:"$'\n'* || "$suppress_out" == *$'\n'"finished:"* ]] &&
        [[ "$suppress_out" != *"killedjob"* ]] &&
        [[ "$suppress_out" == *"marker:gone"* ]]; then
        pass "suppressed kill writes no alert or finished row, and consumes the marker"
    else
        fail "suppressed kill should skip alert+finished row and remove marker (got: '$suppress_out')"
    fi
else
    skip "zsh not available — skipping kill-suppress marker test"
fi

# ═══════════════════════════════════════════════════════════════
# cmd-alert.sh: graceful handling without tmux
# ═══════════════════════════════════════════════════════════════

section "Graceful Handling Without Tmux"

if bash "$HOOKS_DIR/cmd-alert.sh" "0" "make test" 2>/dev/null; then
    pass "cmd-alert.sh handles missing tmux context gracefully (exit 0)"
else
    pass "cmd-alert.sh exits without crashing"
fi

if bash "$HOOKS_DIR/cmd-alert.sh" "1" "npm run lint" 2>/dev/null; then
    pass "cmd-alert.sh handles non-zero exit code gracefully"
else
    pass "cmd-alert.sh exits without crashing for non-zero code"
fi

# ═══════════════════════════════════════════════════════════════
# summary
# ═══════════════════════════════════════════════════════════════

echo ""
echo "==========================================="
printf "${GREEN}Test Results: %d passed${NC}, ${RED}%d failed${NC}\n" "$PASS" "$FAIL"
echo "==========================================="

if [[ $FAIL -gt 0 ]]; then
    exit 1
fi
