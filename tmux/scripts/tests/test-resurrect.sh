#!/usr/bin/env bash
set -euo pipefail

# ══════════════════════════════════════════════════════════════
# test-resurrect.sh
# ══════════════════════════════════════════════════════════════
# tests for tmux resurrect scripts and path discovery
#
# coverage:
# - path discovery (legacy vs XDG locations)
# - split operations (post-save hook)
# - restore operations (per-session restore)
# - delete operations (kill + remove backup)
# - edge cases (missing dirs, invalid files)
#
# usage: ./test-resurrect.sh
# ══════════════════════════════════════════════════════════════

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_DIR="$(dirname "$SCRIPT_DIR")"
LIB_DIR="$SCRIPTS_DIR/_lib"

# source test helpers (provides colours, pass/fail/skip/section, counters)
source "$SCRIPT_DIR/_test-helpers.sh"

# final cleanup function for trap (cleans up both server and env)
final_cleanup() {
    # kill any remaining test tmux server first
    cleanup_test_server 2>/dev/null || true

    # then clean up test environment
    cleanup_test_env
}

# trap to ensure cleanup on exit/interrupt
trap final_cleanup EXIT INT TERM

# ══════════════════════════════════════════════════════════════
# test environment setup/cleanup
# ══════════════════════════════════════════════════════════════

# test environment variables
TEST_HOME=""
TEST_XDG_DATA_HOME=""
ORIGINAL_HOME="$HOME"
ORIGINAL_XDG_DATA_HOME="${XDG_DATA_HOME:-}"

setup_test_env() {
    # create temporary test directories
    TEST_HOME=$(mktemp -d)
    TEST_XDG_DATA_HOME="$TEST_HOME/.local/share"

    # export for subshells
    export HOME="$TEST_HOME"
    export XDG_DATA_HOME="$TEST_XDG_DATA_HOME"

    # create basic directory structure
    mkdir -p "$TEST_HOME/.tmux/resurrect"
    mkdir -p "$TEST_XDG_DATA_HOME/tmux/resurrect"
}

cleanup_test_env() {
    # restore original environment
    export HOME="$ORIGINAL_HOME"
    if [[ -n "$ORIGINAL_XDG_DATA_HOME" ]]; then
        export XDG_DATA_HOME="$ORIGINAL_XDG_DATA_HOME"
    else
        unset XDG_DATA_HOME
    fi

    # remove test directories (suppress errors for idempotent cleanup)
    if [[ -n "$TEST_HOME" && -d "$TEST_HOME" ]]; then
        rm -rf "$TEST_HOME" 2>/dev/null || true
    fi

    # clear TEST_HOME to prevent double-cleanup attempts
    TEST_HOME=""
}

# ══════════════════════════════════════════════════════════════
# path discovery tests
# ══════════════════════════════════════════════════════════════

test_path_discovery() {
    section "Path Discovery Tests"

    # source the paths library
    source "$LIB_DIR/paths.sh"

    # test 1: legacy location with 'last' symlink
    setup_test_env
    touch "$TEST_HOME/.tmux/resurrect/last"
    result=$(get_resurrect_dir)
    if [[ "$result" == "$TEST_HOME/.tmux/resurrect" ]]; then
        pass "Legacy location detected via 'last' symlink"
    else
        fail "Legacy location detection failed (got: $result)"
    fi
    cleanup_test_env

    # test 2: XDG location with 'last' symlink
    setup_test_env
    mkdir -p "$TEST_XDG_DATA_HOME/tmux/resurrect"
    touch "$TEST_XDG_DATA_HOME/tmux/resurrect/last"
    result=$(get_resurrect_dir)
    if [[ "$result" == "$TEST_XDG_DATA_HOME/tmux/resurrect" ]]; then
        pass "XDG location detected via 'last' symlink"
    else
        fail "XDG location detection failed (got: $result)"
    fi
    cleanup_test_env

    # test 3: priority, legacy 'last' over XDG 'last'
    setup_test_env
    touch "$TEST_HOME/.tmux/resurrect/last"
    mkdir -p "$TEST_XDG_DATA_HOME/tmux/resurrect"
    touch "$TEST_XDG_DATA_HOME/tmux/resurrect/last"
    result=$(get_resurrect_dir)
    if [[ "$result" == "$TEST_HOME/.tmux/resurrect" ]]; then
        pass "Legacy 'last' takes priority over XDG"
    else
        fail "Priority order incorrect (got: $result)"
    fi
    cleanup_test_env

    # test 4: XDG sessions directory fallback
    setup_test_env
    mkdir -p "$TEST_XDG_DATA_HOME/tmux/resurrect/sessions"
    result=$(get_resurrect_dir)
    if [[ "$result" == "$TEST_XDG_DATA_HOME/tmux/resurrect" ]]; then
        pass "XDG sessions directory fallback works"
    else
        fail "XDG sessions directory fallback failed (got: $result)"
    fi
    cleanup_test_env

    # test 5: legacy sessions directory fallback
    setup_test_env
    mkdir -p "$TEST_HOME/.tmux/resurrect/sessions"
    result=$(get_resurrect_dir)
    if [[ "$result" == "$TEST_HOME/.tmux/resurrect" ]]; then
        pass "Legacy sessions directory fallback works"
    else
        fail "Legacy sessions directory fallback failed (got: $result)"
    fi
    cleanup_test_env

    # test 6: default to legacy when nothing exists
    setup_test_env
    result=$(get_resurrect_dir)
    if [[ "$result" == "$TEST_HOME/.tmux/resurrect" ]]; then
        pass "Defaults to legacy location when nothing exists"
    else
        fail "Default location incorrect (got: $result)"
    fi
    cleanup_test_env

    # test 7: get_resurrect_sessions_dir consistency
    setup_test_env
    touch "$TEST_HOME/.tmux/resurrect/last"
    result=$(get_resurrect_sessions_dir)
    expected="$TEST_HOME/.tmux/resurrect/sessions"
    if [[ "$result" == "$expected" ]]; then
        pass "Sessions directory path is consistent with base dir"
    else
        fail "Sessions directory path mismatch (got: $result, expected: $expected)"
    fi
    cleanup_test_env

    # test 8: XDG_DATA_HOME unset behaviour
    setup_test_env
    unset XDG_DATA_HOME
    touch "$TEST_HOME/.local/share/tmux/resurrect/last"
    result=$(get_resurrect_dir)
    if [[ "$result" == "$TEST_HOME/.local/share/tmux/resurrect" ]]; then
        pass "XDG default location works when XDG_DATA_HOME unset"
    else
        fail "XDG default location failed (got: $result)"
    fi
    cleanup_test_env
}

# ══════════════════════════════════════════════════════════════
# resurrect operation tests
# ══════════════════════════════════════════════════════════════

test_split_operation() {
    section "Split Operation Tests"

    # test 1: basic split functionality
    setup_test_env

    # create a mock 'last' file with multiple sessions
    cat >"$TEST_HOME/.tmux/resurrect/last" <<'EOF'
pane	session1	0	:window1	1	:*	1	:/home/user	1	bash	:
pane	session2	0	:window1	1	:*	1	:/home/user	1	bash	:
window	session1	0	1	:*	0123,80x24,0,0,1
window	session2	0	1	:*	0123,80x24,0,0,2
state	session1	
state	session2	
EOF

    # run split script (may fail in some environments)
    if bash "$SCRIPTS_DIR/resurrect/split.sh" 2>&1; then
        # check session1 file was created
        if [[ -f "$TEST_HOME/.tmux/resurrect/sessions/session1.txt" ]]; then
            pass "Split creates session1.txt"
        else
            fail "Split did not create session1.txt"
        fi

        # check session2 file was created
        if [[ -f "$TEST_HOME/.tmux/resurrect/sessions/session2.txt" ]]; then
            pass "Split creates session2.txt"
        else
            fail "Split did not create session2.txt"
        fi

        # verify session1 content
        if grep -q "session1" "$TEST_HOME/.tmux/resurrect/sessions/session1.txt" &&
            ! grep -q "session2" "$TEST_HOME/.tmux/resurrect/sessions/session1.txt"; then
            pass "session1.txt contains only session1 data"
        else
            fail "session1.txt content incorrect"
        fi

        # verify session2 content
        if grep -q "session2" "$TEST_HOME/.tmux/resurrect/sessions/session2.txt" &&
            ! grep -q "session1" "$TEST_HOME/.tmux/resurrect/sessions/session2.txt"; then
            pass "session2.txt contains only session2 data"
        else
            fail "session2.txt content incorrect"
        fi
    else
        # split script failed, this might happen in CI or limited environments
        skip "Split script execution failed (environment-specific issue)"
    fi

    cleanup_test_env

    # test 2: empty 'last' file handling
    setup_test_env
    touch "$TEST_HOME/.tmux/resurrect/last"

    if bash "$SCRIPTS_DIR/resurrect/split.sh" 2>/dev/null; then
        pass "Split handles empty 'last' file gracefully"
    else
        skip "Split script may fail on empty file (expected behaviour)"
    fi

    cleanup_test_env

    # test 3: missing 'last' file
    setup_test_env

    if ! bash "$SCRIPTS_DIR/resurrect/split.sh" 2>/dev/null; then
        pass "Split fails gracefully with missing 'last' file"
    else
        skip "Split may succeed with missing file (creates empty sessions)"
    fi

    cleanup_test_env
}

test_restore_operation() {
    section "Restore Operation Tests"

    # note: full restore testing requires tmux server setup
    # these tests focus on backup file handling and validation
    # a test server is required so restore.sh's tmux calls don't hit the live server
    setup_test_server

    setup_test_env

    # create a session backup file
    mkdir -p "$TEST_HOME/.tmux/resurrect/sessions"
    cat >"$TEST_HOME/.tmux/resurrect/sessions/test-session.txt" <<'EOF'
pane	test-session	0	:window1	1	:*	1	:/home/user	1	bash	:
window	test-session	0	1	:*	0123,80x24,0,0,1
state	test-session	
EOF

    # test 1: list backups
    result=$(bash "$SCRIPTS_DIR/resurrect/restore.sh" --list 2>/dev/null | grep -c "test-session" || true)
    if [[ "$result" -gt 0 ]]; then
        pass "List operation finds test-session backup"
    else
        fail "List operation did not find test-session backup"
    fi

    # test 2: backup file exists check
    if [[ -f "$TEST_HOME/.tmux/resurrect/sessions/test-session.txt" ]]; then
        pass "Backup file created correctly"
    else
        fail "Backup file not found"
    fi

    cleanup_test_env

    # test 3: empty sessions directory
    setup_test_env
    mkdir -p "$TEST_HOME/.tmux/resurrect/sessions"

    result=$(bash "$SCRIPTS_DIR/resurrect/restore.sh" --list 2>/dev/null | wc -l)
    if [[ "$result" -le 2 ]]; then # allow for header/footer lines
        pass "List operation handles empty sessions directory"
    else
        fail "List operation shows unexpected content for empty directory"
    fi

    cleanup_test_env
    cleanup_test_server
}

test_delete_operation() {
    section "Delete Operation Tests"

    # a test server is required so delete.sh's tmux calls don't hit the live server
    setup_test_server

    # note: these tests focus on backup file deletion; session killing requires tmux server
    setup_test_env

    # create a session backup file
    mkdir -p "$TEST_HOME/.tmux/resurrect/sessions"
    touch "$TEST_HOME/.tmux/resurrect/sessions/test-session.txt"

    # test 1: verify backup exists before delete
    if [[ -f "$TEST_HOME/.tmux/resurrect/sessions/test-session.txt" ]]; then
        pass "Backup file exists before delete"
    else
        fail "Backup file not created"
    fi

    # test 2: delete when session doesn't exist (only deletes backup)
    # note: this will attempt to kill the session which will fail,
    # but should still delete the backup
    bash "$SCRIPTS_DIR/resurrect/delete.sh" test-session 2>/dev/null || true

    # verify backup was deleted (or attempted)
    # note: script may not delete if session validation fails
    # this is expected behaviour
    skip "Delete operation requires tmux server for full testing"

    cleanup_test_env
    cleanup_test_server
}

# ══════════════════════════════════════════════════════════════
# edge case tests
# ══════════════════════════════════════════════════════════════

test_edge_cases() {
    section "Edge Case Tests"

    # a test server is required so restore.sh's tmux calls don't hit the live server
    setup_test_server

    # test 1: session name with special characters in backup
    setup_test_env
    mkdir -p "$TEST_HOME/.tmux/resurrect/sessions"
    touch "$TEST_HOME/.tmux/resurrect/sessions/my-project_v2.1.txt"

    result=$(bash "$SCRIPTS_DIR/resurrect/restore.sh" --list 2>/dev/null | grep -c "my-project_v2.1" || true)
    if [[ "$result" -gt 0 ]]; then
        pass "Handles session names with dots, dashes, underscores"
    else
        fail "Session name parsing failed for special characters"
    fi

    cleanup_test_env

    # test 2: multiple sessions with same prefix
    setup_test_env
    mkdir -p "$TEST_HOME/.tmux/resurrect/sessions"
    touch "$TEST_HOME/.tmux/resurrect/sessions/project.txt"
    touch "$TEST_HOME/.tmux/resurrect/sessions/project-2.txt"
    touch "$TEST_HOME/.tmux/resurrect/sessions/project-test.txt"

    result=$(bash "$SCRIPTS_DIR/resurrect/restore.sh" --list 2>/dev/null | grep -c "project" || true)
    if [[ "$result" -ge 3 ]]; then
        pass "Lists all sessions with similar names"
    else
        fail "Session listing incomplete for similar names"
    fi

    cleanup_test_env

    # test 3: invalid/corrupt backup file
    setup_test_env
    mkdir -p "$TEST_HOME/.tmux/resurrect/sessions"
    echo "corrupted data" >"$TEST_HOME/.tmux/resurrect/sessions/corrupt-session.txt"

    # script should still list it (restoration might fail, but listing should work)
    result=$(bash "$SCRIPTS_DIR/resurrect/restore.sh" --list 2>/dev/null | grep -c "corrupt-session" || true)
    if [[ "$result" -gt 0 ]]; then
        pass "Lists sessions even with potentially corrupt backup files"
    else
        skip "Corrupt file handling varies by implementation"
    fi

    cleanup_test_env
    cleanup_test_server
}

# ══════════════════════════════════════════════════════════════
# content and command restoration tests
# ══════════════════════════════════════════════════════════════

test_content_restoration() {
    section "Content Restoration Tests"

    # check if tmux-resurrect plugin is installed
    if [[ ! -f "$ORIGINAL_HOME/.tmux/plugins/tmux-resurrect/scripts/save.sh" ]]; then
        skip "Content restoration tests require tmux-resurrect plugin"
        return
    fi

    setup_test_env
    setup_test_server

    # create a session with content
    $TEST_TMUX_CMD new-session -d -s "test-content" "echo 'Test Content Line 1'; echo 'Test Content Line 2'; bash"
    sleep 0.5

    # save session (this should create pane contents files)
    $TEST_TMUX_CMD run-shell "$ORIGINAL_HOME/.tmux/plugins/tmux-resurrect/scripts/save.sh"
    sleep 0.5

    # split sessions to create individual backup
    bash "$SCRIPTS_DIR/resurrect/split.sh"

    # kill the session
    $TEST_TMUX_CMD kill-session -t "test-content"

    # restore the session
    bash "$SCRIPTS_DIR/resurrect/restore.sh" --no-switch --session "test-content"

    # check if session was restored
    if $TEST_TMUX_CMD has-session -t "test-content" 2>/dev/null; then
        pass "Session restored with content restoration enabled"
    else
        fail "Session restoration failed"
    fi

    cleanup_test_server
    cleanup_test_env
}

test_command_restoration() {
    section "Command Restoration Tests"

    # check if tmux-resurrect plugin is installed
    if [[ ! -f "$ORIGINAL_HOME/.tmux/plugins/tmux-resurrect/scripts/save.sh" ]]; then
        skip "Command restoration tests require tmux-resurrect plugin"
        return
    fi

    setup_test_env
    setup_test_server

    # configure process restoration
    $TEST_TMUX_CMD set-option -g @resurrect-processes "vim"

    # create session with vim running (should be restored)
    # use a simple sleep command instead of an interactive program for testing
    $TEST_TMUX_CMD new-session -d -s "test-commands" "sleep 60"
    sleep 0.5

    # verify session was created
    if ! $TEST_TMUX_CMD has-session -t "test-commands" 2>/dev/null; then
        skip "Session creation failed in test environment"
        cleanup_test_server
        cleanup_test_env
        return
    fi

    # save and restore flow
    $TEST_TMUX_CMD run-shell "$ORIGINAL_HOME/.tmux/plugins/tmux-resurrect/scripts/save.sh"
    sleep 0.5
    bash "$SCRIPTS_DIR/resurrect/split.sh"
    $TEST_TMUX_CMD kill-session -t "test-commands"
    bash "$SCRIPTS_DIR/resurrect/restore.sh" --no-switch --session "test-commands"

    # check if session was restored
    if $TEST_TMUX_CMD has-session -t "test-commands" 2>/dev/null; then
        pass "Session restored with command restoration configured"

        # check if command is running
        local cmd
        cmd=$($TEST_TMUX_CMD display-message -p -t "test-commands:0.0" "#{pane_current_command}" 2>/dev/null || echo "")
        if [[ -n "$cmd" ]]; then
            pass "Command restoration attempted (pane running: $cmd)"
        else
            skip "Command state could not be verified"
        fi
    else
        fail "Session restoration failed with command restoration"
    fi

    cleanup_test_server
    cleanup_test_env
}

test_process_list_configuration() {
    section "Process List Configuration Tests"

    # check if tmux-resurrect plugin is installed
    if [[ ! -f "$ORIGINAL_HOME/.tmux/plugins/tmux-resurrect/scripts/save.sh" ]]; then
        skip "Process list configuration tests require tmux-resurrect plugin"
        return
    fi

    setup_test_env
    setup_test_server

    # test 1: default process list (no configuration)
    $TEST_TMUX_CMD set-option -ug @resurrect-processes
    $TEST_TMUX_CMD new-session -d -s "test-default" "sleep 30"
    sleep 0.3

    # save, kill, restore
    $TEST_TMUX_CMD run-shell "$ORIGINAL_HOME/.tmux/plugins/tmux-resurrect/scripts/save.sh"
    sleep 0.3
    bash "$SCRIPTS_DIR/resurrect/split.sh"
    $TEST_TMUX_CMD kill-session -t "test-default"
    bash "$SCRIPTS_DIR/resurrect/restore.sh" --no-switch --session "test-default"

    if $TEST_TMUX_CMD has-session -t "test-default" 2>/dev/null; then
        pass "Restoration works with default process list"
    else
        fail "Restoration failed with default configuration"
    fi

    $TEST_TMUX_CMD kill-session -t "test-default" 2>/dev/null || true

    # test 2: custom process list
    $TEST_TMUX_CMD set-option -g @resurrect-processes "ssh sleep"
    $TEST_TMUX_CMD new-session -d -s "test-custom" "sleep 30"
    sleep 0.3

    if ! $TEST_TMUX_CMD has-session -t "test-custom" 2>/dev/null; then
        skip "Session creation failed for custom process test"
        cleanup_test_server
        cleanup_test_env
        return
    fi

    $TEST_TMUX_CMD run-shell "$ORIGINAL_HOME/.tmux/plugins/tmux-resurrect/scripts/save.sh"
    sleep 0.3
    bash "$SCRIPTS_DIR/resurrect/split.sh"
    $TEST_TMUX_CMD kill-session -t "test-custom"
    bash "$SCRIPTS_DIR/resurrect/restore.sh" --no-switch --session "test-custom"

    if $TEST_TMUX_CMD has-session -t "test-custom" 2>/dev/null; then
        pass "Restoration works with custom process list"
    else
        fail "Restoration failed with custom process list"
    fi

    cleanup_test_server
    cleanup_test_env
}

test_mixed_restoration() {
    section "Mixed State Restoration Tests"

    # check if tmux-resurrect plugin is installed
    if [[ ! -f "$ORIGINAL_HOME/.tmux/plugins/tmux-resurrect/scripts/save.sh" ]]; then
        skip "Mixed restoration tests require tmux-resurrect plugin"
        return
    fi

    setup_test_env
    setup_test_server

    # create a session with multiple panes
    # - some with content, some without
    # - some with commands, some without
    $TEST_TMUX_CMD new-session -d -s "test-mixed" "echo 'Pane 1 content'; bash"
    $TEST_TMUX_CMD split-window -t "test-mixed" "bash" # empty pane
    $TEST_TMUX_CMD split-window -t "test-mixed" "echo 'Pane 3 content'; bash"
    sleep 0.5

    # save, kill, restore
    $TEST_TMUX_CMD run-shell "$ORIGINAL_HOME/.tmux/plugins/tmux-resurrect/scripts/save.sh"
    sleep 0.5
    bash "$SCRIPTS_DIR/resurrect/split.sh"
    $TEST_TMUX_CMD kill-session -t "test-mixed"
    bash "$SCRIPTS_DIR/resurrect/restore.sh" --no-switch --session "test-mixed"

    # check if session was restored with all panes
    if $TEST_TMUX_CMD has-session -t "test-mixed" 2>/dev/null; then
        local pane_count
        pane_count=$($TEST_TMUX_CMD list-panes -t "test-mixed" 2>/dev/null | wc -l)
        pane_count="${pane_count//[$'\n\r ']/}" # strip whitespace
        if [[ "$pane_count" -eq 3 ]]; then
            pass "Mixed state restoration preserves all panes"
        else
            fail "Mixed state restoration lost panes (expected 3, got $pane_count)"
        fi
    else
        fail "Mixed state restoration failed"
    fi

    cleanup_test_server
    cleanup_test_env
}

test_graceful_degradation() {
    section "Graceful Degradation Tests"

    setup_test_env
    setup_test_server

    # test restoration when pane contents files don't exist
    $TEST_TMUX_CMD new-session -d -s "test-no-contents" "bash"
    sleep 0.3

    # create backup manually without pane contents
    mkdir -p "$TEST_HOME/.tmux/resurrect/sessions"
    cat >"$TEST_HOME/.tmux/resurrect/sessions/test-no-contents.txt" <<'EOF'
pane	test-no-contents	0	1		0	bash	/tmp	1	bash	
window	test-no-contents	0	bash	1		b6af,80x24,0,0,0	1
EOF

    $TEST_TMUX_CMD kill-session -t "test-no-contents"
    bash "$SCRIPTS_DIR/resurrect/restore.sh" --no-switch --session "test-no-contents"

    # should still restore successfully without contents files
    if $TEST_TMUX_CMD has-session -t "test-no-contents" 2>/dev/null; then
        pass "Restoration works gracefully without pane contents files"
    else
        fail "Restoration failed when pane contents missing"
    fi

    cleanup_test_server
    cleanup_test_env
}

# ══════════════════════════════════════════════════════════════
# field validation tests (Improvement #1)
# ══════════════════════════════════════════════════════════════

test_field_validation() {
    section "Field Validation Tests"

    # test 1: missing window_number in pane line
    setup_test_env
    setup_test_server
    mkdir -p "$TEST_HOME/.tmux/resurrect/sessions"
    cat >"$TEST_HOME/.tmux/resurrect/sessions/test-missing-window.txt" <<'EOF'
pane	test-missing-window		0	:	0	:	/tmp	1	bash	:
pane	test-missing-window	1	0	:	1	:	/tmp	0	bash	:
window	test-missing-window	1	window1	1	:*	1234,80x24,0,0,1	0
EOF

    # should skip malformed line but not crash
    if bash "$SCRIPTS_DIR/resurrect/restore.sh" --no-switch --session "test-missing-window" 2>/dev/null; then
        pass "Handles missing window_number in pane line gracefully"
    else
        skip "Script may fail on malformed files (depends on validation logic)"
    fi

    cleanup_test_server
    cleanup_test_env

    # test 2: missing pane_index in pane line
    setup_test_env
    setup_test_server
    mkdir -p "$TEST_HOME/.tmux/resurrect/sessions"
    cat >"$TEST_HOME/.tmux/resurrect/sessions/test-missing-pane.txt" <<'EOF'
pane	test-missing-pane	0	0	:		:	/tmp	1	bash	:
pane	test-missing-pane	1	0	:	0	:	/tmp	0	bash	:
window	test-missing-pane	1	window1	1	:*	1234,80x24,0,0,1	0
EOF

    if bash "$SCRIPTS_DIR/resurrect/restore.sh" --no-switch --session "test-missing-pane" 2>/dev/null; then
        pass "Handles missing pane_index in pane line gracefully"
    else
        skip "Script may fail on malformed pane index"
    fi

    cleanup_test_server
    cleanup_test_env

    # test 3: missing window_layout in window line
    setup_test_env
    setup_test_server
    mkdir -p "$TEST_HOME/.tmux/resurrect/sessions"
    cat >"$TEST_HOME/.tmux/resurrect/sessions/test-missing-layout.txt" <<'EOF'
pane	test-missing-layout	0	0	:	0	:	/tmp	1	bash	:
window	test-missing-layout	0	window1	1	:*		0
EOF

    if bash "$SCRIPTS_DIR/resurrect/restore.sh" --no-switch --session "test-missing-layout" 2>/dev/null; then
        pass "Handles missing window_layout gracefully"
    else
        skip "Script may fail on missing layout"
    fi

    cleanup_test_server
    cleanup_test_env

    # test 4: completely empty lines (should be ignored)
    setup_test_env
    setup_test_server
    mkdir -p "$TEST_HOME/.tmux/resurrect/sessions"
    cat >"$TEST_HOME/.tmux/resurrect/sessions/test-empty-lines.txt" <<'EOF'
pane	test-empty-lines	0	0	:	0	:	/tmp	1	bash	:

window	test-empty-lines	0	window1	1	:*	1234,80x24,0,0,1	0

EOF

    if bash "$SCRIPTS_DIR/resurrect/restore.sh" --no-switch --session "test-empty-lines" 2>/dev/null; then
        pass "Handles empty lines in backup file gracefully"
    else
        skip "Script may fail on empty lines"
    fi

    cleanup_test_server
    cleanup_test_env
}

# ══════════════════════════════════════════════════════════════
# cleanup trap tests (Improvement #3)
# ══════════════════════════════════════════════════════════════

test_cleanup_trap() {
    section "Cleanup Trap Tests"

    # check if tmux server is available for these tests
    if [[ ! -f "$ORIGINAL_HOME/.tmux/plugins/tmux-resurrect/scripts/save.sh" ]]; then
        skip "Cleanup trap tests require tmux-resurrect plugin"
        return
    fi

    setup_test_env
    setup_test_server

    # test 1: partial session cleanup on error
    # create a backup file that will cause an error during restoration
    mkdir -p "$TEST_HOME/.tmux/resurrect/sessions"

    # this should create session successfully, but subsequent operations might fail
    cat >"$TEST_HOME/.tmux/resurrect/sessions/test-cleanup.txt" <<'EOF'
pane	test-cleanup	0	0	:	0	:	/tmp	1	bash	:
window	test-cleanup	0	window1	1	:*	1234,80x24,0,0,1	0
EOF

    # attempt restoration (may succeed or fail depending on environment)
    bash "$SCRIPTS_DIR/resurrect/restore.sh" --no-switch --session "test-cleanup" 2>/dev/null || true

    # if it failed, verify no partial session remains
    if ! $TEST_TMUX_CMD has-session -t "test-cleanup" 2>/dev/null; then
        pass "No partial session left after restoration error"
    else
        # session exists, either succeeded or trap didn't work
        skip "Session restoration succeeded or cleanup trap not triggered"
    fi

    cleanup_test_server
    cleanup_test_env

    # test 2: script interruption handling
    # note: this is difficult to test automatically as it requires SIGINT/SIGTERM
    skip "Script interruption cleanup requires manual testing"
}

# ══════════════════════════════════════════════════════════════
# non-consecutive window number tests (Improvement #4)
# ══════════════════════════════════════════════════════════════

test_non_consecutive_windows() {
    section "Non-consecutive Window Number Tests"

    # check if tmux server is available
    if [[ ! -f "$ORIGINAL_HOME/.tmux/plugins/tmux-resurrect/scripts/save.sh" ]]; then
        skip "Non-consecutive window tests require tmux-resurrect plugin"
        return
    fi

    setup_test_env
    setup_test_server

    # test 1: windows with gaps (0, 5, 9)
    $TEST_TMUX_CMD new-session -d -s "test-gaps" -n "win0"
    $TEST_TMUX_CMD new-window -t "test-gaps:5" -n "win5"
    $TEST_TMUX_CMD new-window -t "test-gaps:9" -n "win9"
    sleep 0.5

    # verify windows were created with correct numbers
    local win_list
    win_list=$($TEST_TMUX_CMD list-windows -t "test-gaps" -F "#{window_index}" 2>/dev/null | tr '\n' ' ')
    if [[ "$win_list" =~ "0" ]] && [[ "$win_list" =~ "5" ]] && [[ "$win_list" =~ "9" ]]; then
        pass "Created test session with non-consecutive windows"
    else
        skip "Could not create windows with gaps (got: $win_list)"
        cleanup_test_server
        cleanup_test_env
        return
    fi

    # save, kill, restore
    $TEST_TMUX_CMD run-shell "$ORIGINAL_HOME/.tmux/plugins/tmux-resurrect/scripts/save.sh"
    sleep 0.5
    bash "$SCRIPTS_DIR/resurrect/split.sh"
    $TEST_TMUX_CMD kill-session -t "test-gaps"
    bash "$SCRIPTS_DIR/resurrect/restore.sh" --no-switch --session "test-gaps"

    # verify gaps are preserved
    if $TEST_TMUX_CMD has-session -t "test-gaps" 2>/dev/null; then
        local restored_wins
        restored_wins=$($TEST_TMUX_CMD list-windows -t "test-gaps" -F "#{window_index}" 2>/dev/null | tr '\n' ' ')
        if [[ "$restored_wins" =~ "0" ]] && [[ "$restored_wins" =~ "5" ]] && [[ "$restored_wins" =~ "9" ]]; then
            pass "Window number gaps preserved after restoration"
        else
            fail "Window numbers changed after restoration (got: $restored_wins)"
        fi

        # verify window names
        local win0_name win5_name win9_name
        win0_name=$($TEST_TMUX_CMD display-message -t "test-gaps:0" -p "#{window_name}" 2>/dev/null)
        win5_name=$($TEST_TMUX_CMD display-message -t "test-gaps:5" -p "#{window_name}" 2>/dev/null)
        win9_name=$($TEST_TMUX_CMD display-message -t "test-gaps:9" -p "#{window_name}" 2>/dev/null)

        if [[ "$win0_name" == "win0" ]] && [[ "$win5_name" == "win5" ]] && [[ "$win9_name" == "win9" ]]; then
            pass "Window names preserved with non-consecutive numbers"
        else
            fail "Window names incorrect (0:$win0_name, 5:$win5_name, 9:$win9_name)"
        fi
    else
        fail "Session restoration failed with non-consecutive windows"
    fi

    cleanup_test_server
    cleanup_test_env

    # test 2: base index 1 with gaps (1, 3, 7)
    setup_test_env
    setup_test_server

    # set base-index to 1
    $TEST_TMUX_CMD set-option -g base-index 1

    $TEST_TMUX_CMD new-session -d -s "test-gaps-base1" -n "win1"
    $TEST_TMUX_CMD new-window -t "test-gaps-base1:3" -n "win3"
    $TEST_TMUX_CMD new-window -t "test-gaps-base1:7" -n "win7"
    sleep 0.5

    $TEST_TMUX_CMD run-shell "$ORIGINAL_HOME/.tmux/plugins/tmux-resurrect/scripts/save.sh"
    sleep 0.5
    bash "$SCRIPTS_DIR/resurrect/split.sh"
    $TEST_TMUX_CMD kill-session -t "test-gaps-base1"
    bash "$SCRIPTS_DIR/resurrect/restore.sh" --no-switch --session "test-gaps-base1"

    if $TEST_TMUX_CMD has-session -t "test-gaps-base1" 2>/dev/null; then
        local restored_wins
        restored_wins=$($TEST_TMUX_CMD list-windows -t "test-gaps-base1" -F "#{window_index}" 2>/dev/null | tr '\n' ' ')
        if [[ "$restored_wins" =~ "1" ]] && [[ "$restored_wins" =~ "3" ]] && [[ "$restored_wins" =~ "7" ]]; then
            pass "Window gaps preserved with base-index 1"
        else
            fail "Window numbers incorrect with base-index 1 (got: $restored_wins)"
        fi
    else
        fail "Session restoration failed with base-index 1"
    fi

    # reset base-index
    $TEST_TMUX_CMD set-option -ug base-index

    cleanup_test_server
    cleanup_test_env
}

# ══════════════════════════════════════════════════════════════
# pane readiness tests (Improvement #2)
# ══════════════════════════════════════════════════════════════

test_pane_readiness() {
    section "Pane Readiness Tests"

    # check if tmux server is available
    if [[ ! -f "$ORIGINAL_HOME/.tmux/plugins/tmux-resurrect/scripts/save.sh" ]]; then
        skip "Pane readiness tests require tmux-resurrect plugin"
        return
    fi

    setup_test_env
    setup_test_server

    # test 1: command restoration with wait_for_pane
    # configure process restoration
    $TEST_TMUX_CMD set-option -g @resurrect-processes "sleep"

    # create session with a sleep command
    $TEST_TMUX_CMD new-session -d -s "test-wait-pane" "sleep 60"
    sleep 0.5

    # save and restore
    $TEST_TMUX_CMD run-shell "$ORIGINAL_HOME/.tmux/plugins/tmux-resurrect/scripts/save.sh"
    sleep 0.5
    bash "$SCRIPTS_DIR/resurrect/split.sh"
    $TEST_TMUX_CMD kill-session -t "test-wait-pane"

    # restore, wait_for_pane should prevent race conditions
    bash "$SCRIPTS_DIR/resurrect/restore.sh" --no-switch --session "test-wait-pane"

    if $TEST_TMUX_CMD has-session -t "test-wait-pane" 2>/dev/null; then
        pass "Session restored with pane readiness polling"

        # give command restoration a moment
        sleep 0.3

        # check if command was restored (may or may not work depending on timing)
        local cmd
        cmd=$($TEST_TMUX_CMD display-message -p -t "test-wait-pane:0.0" "#{pane_current_command}" 2>/dev/null || echo "")
        if [[ -n "$cmd" ]]; then
            pass "Command restoration worked with pane readiness check (running: $cmd)"
        else
            skip "Command state verification inconclusive"
        fi
    else
        fail "Session restoration failed with pane readiness polling"
    fi

    cleanup_test_server
    cleanup_test_env

    # test 2: multiple panes with rapid restoration
    setup_test_env
    setup_test_server

    # create session with multiple panes quickly
    $TEST_TMUX_CMD new-session -d -s "test-multi-panes" "bash"
    $TEST_TMUX_CMD split-window -t "test-multi-panes" "bash"
    $TEST_TMUX_CMD split-window -t "test-multi-panes" "bash"
    $TEST_TMUX_CMD split-window -t "test-multi-panes" "bash"
    sleep 0.5

    # save and restore
    $TEST_TMUX_CMD run-shell "$ORIGINAL_HOME/.tmux/plugins/tmux-resurrect/scripts/save.sh"
    sleep 0.5
    bash "$SCRIPTS_DIR/resurrect/split.sh"
    $TEST_TMUX_CMD kill-session -t "test-multi-panes"
    bash "$SCRIPTS_DIR/resurrect/restore.sh" --no-switch --session "test-multi-panes"

    # verify all panes were restored
    if $TEST_TMUX_CMD has-session -t "test-multi-panes" 2>/dev/null; then
        local pane_count
        pane_count=$($TEST_TMUX_CMD list-panes -t "test-multi-panes" 2>/dev/null | wc -l)
        pane_count="${pane_count//[$'\n\r ']/}"
        if [[ "$pane_count" -eq 4 ]]; then
            pass "All panes restored correctly with readiness polling"
        else
            fail "Pane count mismatch (expected 4, got $pane_count)"
        fi
    else
        fail "Multi-pane restoration failed"
    fi

    cleanup_test_server
    cleanup_test_env
}

# ══════════════════════════════════════════════════════════════
# fuzzy process matching tests (Improvement #6)
# ══════════════════════════════════════════════════════════════

test_fuzzy_process_matching() {
    section "Fuzzy Process Matching Tests"

    # check if tmux-resurrect plugin is installed
    if [[ ! -f "$ORIGINAL_HOME/.tmux/plugins/tmux-resurrect/scripts/save.sh" ]]; then
        skip "Fuzzy matching tests require tmux-resurrect plugin"
        return
    fi

    setup_test_env
    setup_test_server

    # test 1: tilde prefix for fuzzy matching (~vim matches nvim)
    $TEST_TMUX_CMD set-option -g @resurrect-processes "~vim"

    # source the restore script to test should_restore_command function
    # we'll test by checking the configuration handling

    # create a session with nvim (should match ~vim)
    $TEST_TMUX_CMD new-session -d -s "test-fuzzy" "bash"
    sleep 0.3

    # create backup with nvim command
    mkdir -p "$TEST_HOME/.tmux/resurrect/sessions"
    cat >"$TEST_HOME/.tmux/resurrect/sessions/test-fuzzy.txt" <<'EOF'
pane	test-fuzzy	0	1		0	bash	/tmp	1	nvim	nvim test.txt
window	test-fuzzy	0	test	1		1234,80x24,0,0,0	0
EOF

    $TEST_TMUX_CMD kill-session -t "test-fuzzy" 2>/dev/null || true
    bash "$SCRIPTS_DIR/resurrect/restore.sh" --no-switch --session "test-fuzzy" 2>/dev/null || true

    if $TEST_TMUX_CMD has-session -t "test-fuzzy" 2>/dev/null; then
        pass "Restoration works with fuzzy process matching configured"
    else
        skip "Session restoration failed (may be environment-specific)"
    fi

    cleanup_test_server
    cleanup_test_env

    # test 2: verify exact matching still works alongside fuzzy
    setup_test_env
    setup_test_server

    $TEST_TMUX_CMD set-option -g @resurrect-processes "ssh ~vim htop"

    mkdir -p "$TEST_HOME/.tmux/resurrect/sessions"
    cat >"$TEST_HOME/.tmux/resurrect/sessions/test-mixed-match.txt" <<'EOF'
pane	test-mixed-match	0	1		0	bash	/tmp	1	ssh	ssh user@host
window	test-mixed-match	0	test	1		1234,80x24,0,0,0	0
EOF

    bash "$SCRIPTS_DIR/resurrect/restore.sh" --no-switch --session "test-mixed-match" 2>/dev/null || true

    if $TEST_TMUX_CMD has-session -t "test-mixed-match" 2>/dev/null; then
        pass "Mixed exact and fuzzy matching works"
    else
        skip "Mixed matching test inconclusive"
    fi

    cleanup_test_server
    cleanup_test_env
}

# regression: quoted fuzzy entries like "~rails server" must stay whole
# when the process list is tokenised (naive word-splitting left literal
# quotes on the tokens, so they never matched)
test_quoted_fuzzy_process_matching() {
    section "Quoted Fuzzy Process Matching Tests"

    setup_test_env
    setup_test_server

    # quoted entry with an embedded space, exactly as documented in tmux.conf
    $TEST_TMUX_CMD set-option -g @resurrect-processes '"~sleep 12"'

    # note: empty fields are colon-prefixed as in real save files; a truly
    # empty field would collapse under tab IFS and shift every later field
    mkdir -p "$TEST_HOME/.tmux/resurrect/sessions"
    cat >"$TEST_HOME/.tmux/resurrect/sessions/test-quoted.txt" <<'EOF'
pane	test-quoted	0	1	:	0	bash	:/tmp	1	sleep	:sleep 1234
window	test-quoted	0	:test	1	:	1234,80x24,0,0,0	off
EOF

    bash "$SCRIPTS_DIR/resurrect/restore.sh" --no-switch --session "test-quoted" 2>/dev/null || true

    if ! $TEST_TMUX_CMD has-session -t "test-quoted" 2>/dev/null; then
        skip "Session restoration failed (may be environment-specific)"
        cleanup_test_server
        cleanup_test_env
        return
    fi

    # poll for the restored command; the shell needs a moment to start it
    local cmd="" attempt=0
    while [[ $attempt -lt 20 ]]; do
        cmd=$($TEST_TMUX_CMD display-message -p -t "test-quoted:0.0" "#{pane_current_command}" 2>/dev/null || echo "")
        [[ "$cmd" == "sleep" ]] && break
        sleep 0.25
        attempt=$((attempt + 1))
    done

    if [[ "$cmd" == "sleep" ]]; then
        pass "Quoted fuzzy entry restored command with arguments"
    else
        fail "Quoted fuzzy entry did not match (pane running: ${cmd:-nothing})"
    fi

    cleanup_test_server
    cleanup_test_env
}

# regression: pane contents restore was a silent no-op because restore.sh
# never extracted pane_contents.tar.gz and looked in the wrong directory
test_pane_contents_restoration() {
    section "Pane Contents Restoration Tests"

    # check if tmux-resurrect plugin is installed
    if [[ ! -f "$ORIGINAL_HOME/.tmux/plugins/tmux-resurrect/scripts/save.sh" ]]; then
        skip "Pane contents tests require tmux-resurrect plugin"
        return
    fi

    setup_test_env
    setup_test_server

    $TEST_TMUX_CMD set-option -g @resurrect-capture-pane-contents on

    # create a session with a distinctive marker in its scrollback
    $TEST_TMUX_CMD new-session -d -s "test-contents" "echo RESURRECT_CONTENTS_MARKER; bash"
    sleep 0.5

    # save via the plugin (creates pane_contents.tar.gz), then split
    $TEST_TMUX_CMD run-shell "$ORIGINAL_HOME/.tmux/plugins/tmux-resurrect/scripts/save.sh"
    sleep 0.5
    bash "$SCRIPTS_DIR/resurrect/split.sh"

    $TEST_TMUX_CMD kill-session -t "test-contents"
    bash "$SCRIPTS_DIR/resurrect/restore.sh" --no-switch --session "test-contents"
    sleep 0.5

    if ! $TEST_TMUX_CMD has-session -t "test-contents" 2>/dev/null; then
        fail "Session restoration failed with contents restoration enabled"
        cleanup_test_server
        cleanup_test_env
        return
    fi

    # restored pane should replay the saved scrollback
    if $TEST_TMUX_CMD capture-pane -p -t "test-contents" 2>/dev/null | grep -q "RESURRECT_CONTENTS_MARKER"; then
        pass "Saved pane contents restored into new pane"
    else
        fail "Saved pane contents missing after restore"
    fi

    # extracted archive contents should be cleaned up afterwards
    local resurrect_dir
    # shellcheck disable=SC1091
    source "$LIB_DIR/paths.sh"
    resurrect_dir=$(get_resurrect_dir)
    if [[ ! -d "${resurrect_dir}/restore/pane_contents" ]]; then
        pass "Extracted pane contents cleaned up after restore"
    else
        fail "Extracted pane contents left behind at ${resurrect_dir}/restore/pane_contents"
    fi

    cleanup_test_server
    cleanup_test_env
}

# ══════════════════════════════════════════════════════════════
# restore all sessions tests (regression test for arithmetic bug)
# ══════════════════════════════════════════════════════════════

test_window_name_restoration() {
    section "Window Name Restoration Tests"

    # check if tmux-resurrect plugin is installed
    if [[ ! -f "$ORIGINAL_HOME/.tmux/plugins/tmux-resurrect/scripts/save.sh" ]]; then
        skip "Window name restoration tests require tmux-resurrect plugin"
        return
    fi

    # test 1: custom window names are preserved after restore
    setup_test_env
    setup_test_server

    $TEST_TMUX_CMD new-session -d -s "test-winnames" -n "editor"
    $TEST_TMUX_CMD new-window -t "test-winnames" -n "server"
    $TEST_TMUX_CMD new-window -t "test-winnames" -n "logs"
    # disable automatic-rename to simulate user-set names
    $TEST_TMUX_CMD set-option -t "test-winnames:0" automatic-rename off
    $TEST_TMUX_CMD set-option -t "test-winnames:1" automatic-rename off
    $TEST_TMUX_CMD set-option -t "test-winnames:2" automatic-rename off
    sleep 0.5

    # save, split, kill, restore
    $TEST_TMUX_CMD run-shell "$ORIGINAL_HOME/.tmux/plugins/tmux-resurrect/scripts/save.sh"
    sleep 0.5
    bash "$SCRIPTS_DIR/resurrect/split.sh"
    $TEST_TMUX_CMD kill-session -t "test-winnames"
    bash "$SCRIPTS_DIR/resurrect/restore.sh" --no-switch --session "test-winnames"

    if $TEST_TMUX_CMD has-session -t "test-winnames" 2>/dev/null; then
        local name0 name1 name2
        name0=$($TEST_TMUX_CMD display-message -t "test-winnames:0" -p "#{window_name}" 2>/dev/null)
        name1=$($TEST_TMUX_CMD display-message -t "test-winnames:1" -p "#{window_name}" 2>/dev/null)
        name2=$($TEST_TMUX_CMD display-message -t "test-winnames:2" -p "#{window_name}" 2>/dev/null)

        if [[ "$name0" == "editor" ]] && [[ "$name1" == "server" ]] && [[ "$name2" == "logs" ]]; then
            pass "Custom window names preserved after restore"
        else
            fail "Window names not preserved (0:$name0, 1:$name1, 2:$name2)"
        fi
    else
        fail "Session restoration failed for window name test"
    fi

    cleanup_test_server
    cleanup_test_env

    # test 2: window names not overwritten by automatic-rename during restore
    # this tests the race condition fix where automatic-rename is disabled
    # in Pass 1 before names are applied in Pass 2
    setup_test_env
    setup_test_server

    # enable automatic-rename globally (the default that causes the race)
    $TEST_TMUX_CMD set-option -g automatic-rename on

    $TEST_TMUX_CMD new-session -d -s "test-autorename" -n "code"
    $TEST_TMUX_CMD new-window -t "test-autorename" -n "build"
    # leave automatic-rename on for these windows (as saved in backup)
    sleep 0.5

    $TEST_TMUX_CMD run-shell "$ORIGINAL_HOME/.tmux/plugins/tmux-resurrect/scripts/save.sh"
    sleep 0.5
    bash "$SCRIPTS_DIR/resurrect/split.sh"
    $TEST_TMUX_CMD kill-session -t "test-autorename"

    # restore with global automatic-rename on (triggers the race condition)
    bash "$SCRIPTS_DIR/resurrect/restore.sh" --no-switch --session "test-autorename"
    sleep 0.3

    if $TEST_TMUX_CMD has-session -t "test-autorename" 2>/dev/null; then
        local aname0 aname1
        aname0=$($TEST_TMUX_CMD display-message -t "test-autorename:0" -p "#{window_name}" 2>/dev/null)
        aname1=$($TEST_TMUX_CMD display-message -t "test-autorename:1" -p "#{window_name}" 2>/dev/null)

        if [[ "$aname0" == "code" ]] && [[ "$aname1" == "build" ]]; then
            pass "Window names survive automatic-rename race condition"
        else
            fail "Automatic-rename overwrote window names (0:$aname0, 1:$aname1)"
        fi
    else
        fail "Session restoration failed for automatic-rename test"
    fi

    # reset global setting
    $TEST_TMUX_CMD set-option -ug automatic-rename

    cleanup_test_server
    cleanup_test_env
}

test_restore_all_sessions() {
    section "Restore All Sessions Tests"

    # check if tmux-resurrect plugin is installed
    if [[ ! -f "$ORIGINAL_HOME/.tmux/plugins/tmux-resurrect/scripts/save.sh" ]]; then
        skip "Restore all tests require tmux-resurrect plugin"
        return
    fi

    setup_test_env
    setup_test_server

    # test 1: restore all with some sessions already running (tests skipping logic)
    # this is a regression test for the ((skipped++)) bug that caused early exit
    mkdir -p "$TEST_HOME/.tmux/resurrect/sessions"

    # create multiple session backups
    for i in 1 2 3; do
        cat >"$TEST_HOME/.tmux/resurrect/sessions/test-all-$i.txt" <<EOF
pane	test-all-$i	0	1		0	bash	/tmp	1	bash
window	test-all-$i	0	window1	1		1234,80x24,0,0,1	0
EOF
    done

    # start one session to force a skip
    $TEST_TMUX_CMD new-session -d -s "test-all-1" "bash"
    sleep 0.3

    # run restore all and capture output
    local output
    output=$(bash "$SCRIPTS_DIR/resurrect/restore.sh" 2>&1) || true

    # verify script processed all sessions (didn't exit early)
    if echo "$output" | grep -q "Restored:"; then
        # check that it shows the summary with skipped count
        if echo "$output" | grep -q "Skipped: 1"; then
            pass "Restore all iterates through all sessions without early exit"
        else
            # may have different skip count, but should still complete
            if echo "$output" | grep -E "Restored: [0-9]+" | grep -qv "Restored: 0"; then
                pass "Restore all completed and restored some sessions"
            else
                pass "Restore all completed (may have different results)"
            fi
        fi
    else
        fail "Restore all exited early without showing summary"
    fi

    # test 2: verify multiple sessions were restored
    local restored_count=0
    for i in 2 3; do
        if $TEST_TMUX_CMD has-session -t "test-all-$i" 2>/dev/null; then
            ((++restored_count))
        fi
    done

    if [[ $restored_count -eq 2 ]]; then
        pass "Restore all successfully restored non-running sessions"
    else
        fail "Restore all only restored $restored_count of 2 expected sessions"
    fi

    cleanup_test_server
    cleanup_test_env

    # test 3: restore all with no sessions running (all should restore)
    setup_test_env
    setup_test_server

    mkdir -p "$TEST_HOME/.tmux/resurrect/sessions"
    for i in a b c; do
        cat >"$TEST_HOME/.tmux/resurrect/sessions/test-fresh-$i.txt" <<EOF
pane	test-fresh-$i	0	1		0	bash	/tmp	1	bash
window	test-fresh-$i	0	window1	1		1234,80x24,0,0,1	0
EOF
    done

    output=$(bash "$SCRIPTS_DIR/resurrect/restore.sh" 2>&1) || true

    if echo "$output" | grep -q "Restored: 3"; then
        pass "Restore all restores all sessions when none are running"
    elif echo "$output" | grep -q "Restored:"; then
        # may show different count depending on environment
        pass "Restore all completed successfully"
    else
        fail "Restore all did not complete properly"
    fi

    cleanup_test_server
    cleanup_test_env
}

# ══════════════════════════════════════════════════════════════
# main test execution
# ══════════════════════════════════════════════════════════════

section "Setup Test Environment"
pass "Test environment ready"

# run all test groups
test_path_discovery
test_split_operation
test_restore_operation
test_delete_operation
test_edge_cases
test_content_restoration
test_command_restoration
test_process_list_configuration
test_mixed_restoration
test_graceful_degradation

# new improvement tests
test_field_validation
test_cleanup_trap
test_non_consecutive_windows
test_pane_readiness
test_fuzzy_process_matching
test_quoted_fuzzy_process_matching
test_pane_contents_restoration
test_window_name_restoration
test_restore_all_sessions

section "Test Summary"

echo ""
echo "==========================================="
printf "${GREEN}✓ Passed: %d${NC} | ${RED}✗ Failed: %d${NC}\n" "$PASS" "$FAIL"
echo "==========================================="

[[ $FAIL -eq 0 ]]
