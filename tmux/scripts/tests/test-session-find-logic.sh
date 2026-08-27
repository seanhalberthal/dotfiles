#!/usr/bin/env bash
set -euo pipefail

# unit tests for session logic (mocks tmux)
# this test verifies that find_other_session handles edge cases correctly
# specifically that it doesn't crash with pipefail when grep finds nothing

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$(dirname "$SCRIPT_DIR")/_lib"

# mocks
# ---------------------------------------------------------

# mock tmux command to simulate specific session states
# shellcheck disable=SC2329  # Mock function called indirectly via export -f
tmux() {
    case "$1" in
        list-sessions)
            # return predetermined output based on TEST_CASE variable
            echo "$TMUX_LIST_OUTPUT"
            ;;
        *)
            # fall back to system tmux or error
            echo "Mock tmux received unexpected command: $*" >&2
            return 1
            ;;
    esac
}
export -f tmux

# helpers
# ---------------------------------------------------------
source "$SCRIPT_DIR/_test-helpers.sh"

# setup
# ---------------------------------------------------------
# source the library under test
source "$LIB_DIR/session.sh"

echo "Running find_other_session logic tests..."
echo "-------------------------------------------"

# test 1: single session exists (no other session)
# ---------------------------------------------------------
TMUX_LIST_OUTPUT="1736780000 active_session"

# we expect find_other_session to return empty string and NOT exit with error
output=$(find_other_session "active_session")
exit_code=$?

if [[ $exit_code -eq 0 ]]; then
    if [[ -z "$output" ]]; then
        pass "Single session: Returns empty string correctly"
    else
        fail "Single session: Expected empty output, got '$output'"
    fi
else
    fail "Single session: Function exited with code $exit_code (crashed?)"
fi

# test 2: multiple sessions exist
# ---------------------------------------------------------
# format: activity name
TMUX_LIST_OUTPUT=$'1736780000 active_session\n1736770000 older_session'

output=$(find_other_session "active_session")
exit_code=$?

if [[ $exit_code -eq 0 ]]; then
    if [[ "$output" == "older_session" ]]; then
        pass "Multiple sessions: Found correct alternative session"
    else
        fail "Multiple sessions: Expected 'older_session', got '$output'"
    fi
else
    fail "Multiple sessions: Function exited with code $exit_code"
fi

print_summary
[[ $FAIL -gt 0 ]] && exit 1
exit 0
