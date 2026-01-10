#!/usr/bin/env bash
set -euo pipefail

# Test suite for installation script libraries
# Usage: ./test.sh [--verbose]

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PASS=0
FAIL=0
# shellcheck disable=SC2034
VERBOSE="${1:-}"  # Reserved for future verbose output

# Colours (using $'...' for proper escape interpretation)
GREEN=$'\033[0;32m'
RED=$'\033[0;31m'
YELLOW=$'\033[0;33m'
NC=$'\033[0m'

# Test output helpers
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

# Assert that a command succeeds
assert_success() {
    local desc="$1"
    shift
    if "$@" 2>/dev/null; then
        pass "$desc"
    else
        fail "$desc"
    fi
}

# Assert that a command fails
assert_failure() {
    local desc="$1"
    shift
    if ! "$@" 2>/dev/null; then
        pass "$desc"
    else
        fail "$desc"
    fi
}

# Assert output equals expected value
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

# ===========================================================================
# Tests
# ===========================================================================

section "Library Sourcing"

# Source the library
if source "$SCRIPT_DIR/common.sh" 2>/dev/null; then
    pass "common.sh sources without error"
else
    fail "common.sh failed to source"
    exit 1
fi

section "Colour Definitions"

assert_equals "RED is defined" $'\033[0;31m' "$RED"
assert_equals "GREEN is defined" $'\033[0;32m' "$GREEN"
assert_equals "YELLOW is defined" $'\033[0;33m' "$YELLOW"
assert_equals "CYAN is defined" $'\033[0;36m' "$CYAN"
assert_equals "NC is defined" $'\033[0m' "$NC"

section "Output Functions"

# Test that output functions exist and are callable
assert_success "error function exists" type error
assert_success "warn function exists" type warn
assert_success "info function exists" type info
assert_success "success function exists" type success
assert_success "print_header function exists" type print_header
assert_success "print_section function exists" type print_section
assert_success "print_step function exists" type print_step

section "Utility Functions"

# command_exists
assert_success "command_exists returns true for bash" command_exists bash
assert_failure "command_exists returns false for nonexistent" command_exists nonexistent_command_12345

# is_macos (platform-dependent)
if [[ "$(uname)" == "Darwin" ]]; then
    assert_success "is_macos returns true on macOS" is_macos
else
    assert_failure "is_macos returns false on non-macOS" is_macos
fi

# get_homebrew_prefix
prefix=$(get_homebrew_prefix)
if [[ "$(uname -m)" == "arm64" ]]; then
    assert_equals "get_homebrew_prefix on Apple Silicon" "/opt/homebrew" "$prefix"
else
    assert_equals "get_homebrew_prefix on Intel/Linux" "/usr/local" "$prefix"
fi

section "Check Command Function"

# Test check_command with a known command
if check_command "bash" "bash" "" >/dev/null 2>&1; then
    pass "check_command returns 0 for existing command"
else
    fail "check_command should return 0 for bash"
fi

# Test check_command with nonexistent command
if ! check_command "nonexistent" "nonexistent_12345" "" 2>/dev/null; then
    pass "check_command returns 1 for missing command"
else
    fail "check_command should return 1 for nonexistent"
fi

section "ShellCheck Validation"

if command -v shellcheck &>/dev/null; then
    if shellcheck -x "$SCRIPT_DIR/common.sh" 2>/dev/null; then
        pass "common.sh passes shellcheck"
    else
        fail "common.sh has shellcheck warnings"
    fi
else
    skip "shellcheck not installed"
fi

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
