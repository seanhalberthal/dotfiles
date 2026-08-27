#!/usr/bin/env bash
# ══════════════════════════════════════════════════════════════
# run-tests.sh
# ══════════════════════════════════════════════════════════════
# dynamic test discovery and runner for dotfiles test suite
# discovers and runs all test-*.sh files in the repository
#
# usage:
#   ./scripts/run-tests.sh                # run all tests
#   ./scripts/run-tests.sh --verbose      # verbose output
#   ./scripts/run-tests.sh --tmux-only    # only tmux-dependent tests
#   ./scripts/run-tests.sh --no-tmux      # skip tmux-dependent tests
# ══════════════════════════════════════════════════════════════

set -euo pipefail

# colours
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# configuration
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERBOSE=false
TMUX_ONLY=false
NO_TMUX=false

# global counters
GLOBAL_TOTAL=0
GLOBAL_PASSED=0
GLOBAL_FAILED=0
GLOBAL_SKIPPED=0

# per-suite counters
SUITE_TOTAL=0
SUITE_PASSED=0
SUITE_FAILED=0
SUITE_SKIPPED=0

# parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --verbose | -v)
            VERBOSE=true
            shift
            ;;
        --tmux-only)
            TMUX_ONLY=true
            shift
            ;;
        --no-tmux)
            NO_TMUX=true
            shift
            ;;
        *)
            printf "${RED}Unknown option: %s${NC}\n" "$1"
            exit 1
            ;;
    esac
done

# check for conflicting options
if [[ "$TMUX_ONLY" = true && "$NO_TMUX" = true ]]; then
    printf "${RED}Error: Cannot use --tmux-only and --no-tmux together${NC}\n"
    exit 1
fi

# ──────────────────────────────────────────────────────────────
# helper functions
# ──────────────────────────────────────────────────────────────

# check if a test requires tmux
requires_tmux() {
    local test_file="$1"
    grep -q "_test-helpers.sh\|setup_test_server\|cleanup_test_server" "$test_file" 2>/dev/null
}

# reset suite counters
reset_suite_counters() {
    SUITE_TOTAL=0
    SUITE_PASSED=0
    SUITE_FAILED=0
    SUITE_SKIPPED=0
}

# print suite summary
print_suite_summary() {
    local suite_name="$1"
    printf "\n"
    printf "${BOLD}%s Summary:${NC} " "$suite_name"
    printf "%d total, " "$SUITE_TOTAL"
    printf "${GREEN}%d passed${NC}" "$SUITE_PASSED"

    if [[ $SUITE_FAILED -gt 0 ]]; then
        printf ", ${RED}%d failed${NC}" "$SUITE_FAILED"
    fi

    if [[ $SUITE_SKIPPED -gt 0 ]]; then
        printf ", ${YELLOW}%d skipped${NC}" "$SUITE_SKIPPED"
    fi

    printf "\n\n"
}

# increment counters for test result
increment_counters() {
    local result="$1" # "passed", "failed", or "skipped"

    SUITE_TOTAL=$((SUITE_TOTAL + 1))
    GLOBAL_TOTAL=$((GLOBAL_TOTAL + 1))

    case "$result" in
        passed)
            SUITE_PASSED=$((SUITE_PASSED + 1))
            GLOBAL_PASSED=$((GLOBAL_PASSED + 1))
            ;;
        failed)
            SUITE_FAILED=$((SUITE_FAILED + 1))
            GLOBAL_FAILED=$((GLOBAL_FAILED + 1))
            ;;
        skipped)
            SUITE_SKIPPED=$((SUITE_SKIPPED + 1))
            GLOBAL_SKIPPED=$((GLOBAL_SKIPPED + 1))
            ;;
    esac
}

# print skip message and increment counters
skip_test() {
    local test_name="$1"
    local reason="$2"

    printf "${YELLOW}⊘${NC} %-50s ${YELLOW}SKIP${NC} (%s)\n" "$test_name" "$reason"
    increment_counters "skipped"
}

# run a single test file
run_test() {
    local test_file="$1"
    local test_name
    test_name=$(basename "$test_file")

    # check if test requires tmux
    local needs_tmux=false
    if requires_tmux "$test_file"; then
        needs_tmux=true
    fi

    # handle skip conditions
    if [[ "$needs_tmux" = true && "$NO_TMUX" = true ]]; then
        skip_test "$test_name" "tmux required"
        return 0
    fi

    if [[ "$needs_tmux" = false && "$TMUX_ONLY" = true ]]; then
        skip_test "$test_name" "not tmux test"
        return 0
    fi

    if [[ "$needs_tmux" = true ]] && ! command -v tmux &>/dev/null; then
        skip_test "$test_name" "tmux not installed"
        return 0
    fi

    # run the test
    local output
    local exit_code

    if [[ "$VERBOSE" = true ]]; then
        printf "${CYAN}▶${NC} Running: %s\n" "$test_name"
    fi

    if output=$("$test_file" 2>&1); then
        printf "${GREEN}✓${NC} %-50s ${GREEN}PASS${NC}\n" "$test_name"
        if [[ "$VERBOSE" = true && -n "$output" ]]; then
            printf "%s\n" "$output"
        fi
        increment_counters "passed"
    else
        exit_code=$?
        printf "${RED}✗${NC} %-50s ${RED}FAIL${NC} (exit code: %d)\n" "$test_name" "$exit_code"
        if [[ -n "$output" ]]; then
            printf "%s\n" "$output"
        fi
        increment_counters "failed"
    fi
}

# ──────────────────────────────────────────────────────────────
# test discovery
# ──────────────────────────────────────────────────────────────

printf "${BOLD}${CYAN}Dotfiles Test Suite${NC}\n"
printf "${CYAN}═══════════════════════════════════════════════════════════${NC}\n\n"

cd "$REPO_ROOT"

# find all test files using bash 3.2-compatible approach
# store test file paths as newline-delimited strings

# library tests (scripts/_lib/test-install-libs.sh, tmux/scripts/_lib/test-tmux-libs.sh)
LIBRARY_TESTS=$(find . -path "*/_lib/test-*-libs.sh" -type f | sort)

# tmux script tests
SCRIPT_TESTS=$(find tmux/scripts/tests -name "test-*.sh" -type f | sort)

# integration tests
INTEGRATION_TESTS=$(find scripts/tests -name "test-*.sh" -type f 2>/dev/null | sort || true)

# run a test suite (bash 3.2+ compatible, using temp file for test list)
run_suite() {
    local suite_name="$1"
    local tests="$2" # newline-delimited test file paths

    # skip if no tests
    if [[ -z "$tests" ]]; then
        return
    fi

    reset_suite_counters
    printf "${BOLD}%s${NC}\n" "$suite_name"

    # save IFS and set to newline only for iteration
    local old_IFS="$IFS"
    IFS=$'\n'

    # process each test (newline-delimited)
    for test in $tests; do
        [[ -z "$test" ]] && continue
        run_test "$test"
    done

    # restore IFS
    IFS="$old_IFS"

    print_suite_summary "$suite_name"
}

# ──────────────────────────────────────────────────────────────
# run tests
# ──────────────────────────────────────────────────────────────

run_suite "Library Tests" "$LIBRARY_TESTS"
run_suite "Script Tests" "$SCRIPT_TESTS"
run_suite "Integration Tests" "$INTEGRATION_TESTS"

# ──────────────────────────────────────────────────────────────
# overall summary
# ──────────────────────────────────────────────────────────────

printf "${CYAN}═══════════════════════════════════════════════════════════${NC}\n"
printf "${BOLD}Overall Summary${NC}\n"
printf "${CYAN}═══════════════════════════════════════════════════════════${NC}\n"
printf "Total:   %d\n" "$GLOBAL_TOTAL"
printf "${GREEN}Passed:  %d${NC}\n" "$GLOBAL_PASSED"
printf "${RED}Failed:  %d${NC}\n" "$GLOBAL_FAILED"
printf "${YELLOW}Skipped: %d${NC}\n" "$GLOBAL_SKIPPED"
printf "\n"

# exit with appropriate code
if [[ $GLOBAL_FAILED -gt 0 ]]; then
    printf "${RED}${BOLD}Tests failed!${NC}\n"
    exit 1
else
    printf "${GREEN}${BOLD}All tests passed!${NC}\n"
    exit 0
fi
