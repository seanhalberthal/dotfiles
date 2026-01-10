#!/usr/bin/env bash
set -euo pipefail

# Integration tests for session management operations
# Requires: Running inside tmux session
# Usage: ./test-session-management.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_DIR="$(dirname "$SCRIPT_DIR")"
LIB_DIR="$SCRIPTS_DIR/_lib"

PASS=0
FAIL=0

# Colours (using $'...' for proper escape interpretation)
GREEN=$'\033[0;32m'
RED=$'\033[0;31m'
YELLOW=$'\033[0;33m'
NC=$'\033[0m'

pass() {
    PASS=$((PASS + 1))
    printf "${GREEN}✓${NC} %s\n" "$1"
}

fail() {
    FAIL=$((FAIL + 1))
    printf "${RED}✗${NC} %s\n" "$1"
}

skip() {
    printf "${YELLOW}○${NC} %s (skipped)\n" "$1"
}

section() {
    echo ""
    echo "─────────────────────────────────────────"
    echo "$1"
    echo "─────────────────────────────────────────"
}

# Check if running inside tmux
if [[ -z "${TMUX:-}" ]]; then
    echo "Error: Must run inside tmux session"
    echo "Start tmux and run: $0"
    exit 1
fi

# Source libraries
source "$LIB_DIR/common.sh"
source "$LIB_DIR/session.sh"

section "Session Library Tests"

# Test get_current_session
current=$(get_current_session)
if [[ -n "$current" ]]; then
    pass "get_current_session returns value: $current"
else
    fail "get_current_session returned empty"
fi

# Test session_exists
if session_exists "$current"; then
    pass "session_exists returns true for current session"
else
    fail "session_exists should return true for current session"
fi

if ! session_exists "nonexistent-session-12345"; then
    pass "session_exists returns false for nonexistent session"
else
    fail "session_exists should return false for nonexistent"
fi

section "Validation Tests"

# Test validate_session_name
assert_valid_name() {
    local name="$1"
    if validate_session_name "$name" 2>/dev/null; then
        pass "validate_session_name accepts: '$name'"
    else
        fail "validate_session_name should accept: '$name'"
    fi
}

assert_invalid_name() {
    local name="$1"
    if ! validate_session_name "$name" 2>/dev/null; then
        pass "validate_session_name rejects: '$name'"
    else
        fail "validate_session_name should reject: '$name'"
    fi
}

# Valid session names
assert_valid_name "myproject"
assert_valid_name "my-project"
assert_valid_name "my_project"
assert_valid_name "my.project"
assert_valid_name "project123"
assert_valid_name "123"

# Invalid session names
assert_invalid_name ""
assert_invalid_name "my project"
assert_invalid_name "my:project"
assert_invalid_name "my/project"
assert_invalid_name "my\$project"

section "Session Switching Tests"

# Create a temporary test session
TEST_SESSION="test-session-$$"
# shellcheck disable=SC2034
ORIGINAL_SESSION=$(get_current_session)  # Kept for potential future cleanup

tmux new-session -d -s "$TEST_SESSION" -c /tmp
pass "Created test session: $TEST_SESSION"

# Test find_other_session
other=$(find_other_session "$TEST_SESSION")
if [[ -n "$other" ]]; then
    pass "find_other_session found: $other"
else
    fail "find_other_session should find another session"
fi

# Cleanup
tmux kill-session -t "$TEST_SESSION" 2>/dev/null || true
pass "Cleaned up test session"

# ===========================================================================
# Summary
# ===========================================================================

echo ""
echo "==========================================="
echo "Test Results: ${GREEN}${PASS} passed${NC}, ${RED}${FAIL} failed${NC}"
echo "==========================================="

if [[ $FAIL -gt 0 ]]; then
    exit 1
fi
