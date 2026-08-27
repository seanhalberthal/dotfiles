#!/usr/bin/env bash
# test helpers for tmux scripts
# provides isolated tmux server for testing

# determine dotfiles root and source colours
_TEST_HELPERS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOTFILES_ROOT="$(cd "$_TEST_HELPERS_DIR/../../.." && pwd)"

# source colour definitions
# shellcheck source=scripts/_lib/colours.sh
source "$DOTFILES_ROOT/scripts/_lib/colours.sh"

# test counters (can be used by test scripts)
PASS=0
FAIL=0
SKIP=0

pass() {
    PASS=$((PASS + 1))
    printf "${GREEN}✓${NC} %s\n" "$1"
}

fail() {
    FAIL=$((FAIL + 1))
    printf "${RED}✗${NC} %s\n" "$1"
}

skip() {
    SKIP=$((SKIP + 1))
    printf "${CYAN}⊘${NC} %s (skipped)\n" "$1"
}

section() {
    echo ""
    printf "${YELLOW}=== %s ===${NC}\n" "$1"
}

# assertion helpers
assert_equals() {
    local desc="$1"
    local expected="$2"
    local actual="$3"

    if [[ "$expected" == "$actual" ]]; then
        pass "$desc"
        return 0
    else
        fail "$desc (expected '$expected', got '$actual')"
        return 1
    fi
}

assert_success() {
    local desc="$1"
    shift

    if "$@" 2>/dev/null; then
        pass "$desc"
        return 0
    else
        fail "$desc (command failed)"
        return 1
    fi
}

assert_failure() {
    local desc="$1"
    shift

    if "$@" 2>/dev/null; then
        fail "$desc (command succeeded but should have failed)"
        return 1
    else
        pass "$desc"
        return 0
    fi
}

# create isolated tmux server for testing
# usage: setup_test_server
# returns: sets TEST_TMUX_SOCKET and TEST_TMUX_CMD
setup_test_server() {
    TEST_TMUX_SOCKET="tmux-test-$$"
    TEST_TMUX_CMD="tmux -L $TEST_TMUX_SOCKET -f /dev/null"

    # start a detached server with empty config (-f /dev/null)
    # this prevents loading the user's tmux.conf via XDG_CONFIG_HOME,
    # which would initialise plugins (TPM, resurrect, continuum) that
    # make tmux calls targeting the live server
    $TEST_TMUX_CMD new-session -d -s test-bootstrap 2>/dev/null || true

    # export socket name for scripts to use
    # scripts will check this variable and add -L flag if set
    export TMUX_TEST_SOCKET="$TEST_TMUX_SOCKET"

    # enable test mode to bypass require_tmux's "inside tmux" check
    export TMUX_TEST_MODE=1
    export TMUX="" # clear TMUX variable so scripts don't think they're inside tmux
}

# cleanup test server
# usage: cleanup_test_server
cleanup_test_server() {
    if [[ -n "${TEST_TMUX_CMD:-}" ]]; then
        $TEST_TMUX_CMD kill-server 2>/dev/null || true
    fi
    if [[ -n "${TEST_TMUX_SOCKET:-}" ]]; then
        rm -f "/tmp/$TEST_TMUX_SOCKET" 2>/dev/null || true
    fi

    # disable test mode and unset test socket
    unset TMUX_TEST_MODE
    unset TMUX_TEST_SOCKET
}

# wrapper to run tmux commands in test server
# usage: test_tmux <tmux-args>
test_tmux() {
    # use command to bypass the wrapper function
    command tmux -L "$TEST_TMUX_SOCKET" -f /dev/null "$@"
}

print_summary() {
    echo ""
    echo "==========================================="
    printf "Test Results: ${GREEN}%d passed${NC}, ${RED}%d failed${NC}" "$PASS" "$FAIL"
    if [[ $SKIP -gt 0 ]]; then
        printf ", ${YELLOW}%d skipped${NC}" "$SKIP"
    fi
    echo ""
    echo "==========================================="
}

# export these for use in test scripts
export -f setup_test_server
export -f cleanup_test_server
export -f test_tmux
export -f pass
export -f fail
export -f skip
export -f section
export -f print_summary
