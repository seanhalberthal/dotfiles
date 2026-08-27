#!/usr/bin/env bash
# shared test helpers for scripts/tests/ and scripts/_lib/ test suites
# provides pass/fail/skip/section output and assertion helpers

# determine dotfiles root from this file's location
_SCRIPTS_TEST_HELPERS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOTFILES_ROOT="$(cd "$_SCRIPTS_TEST_HELPERS_DIR/../.." && pwd)"

# source colour definitions
# shellcheck source=scripts/_lib/colours.sh
source "$DOTFILES_ROOT/scripts/_lib/colours.sh"

# test counters
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
    printf "${YELLOW}○${NC} %s (skipped)\n" "$1"
}

section() {
    echo ""
    echo "─────────────────────────────────────────"
    echo "$1"
    echo "─────────────────────────────────────────"
}

assert_success() {
    local desc="$1"
    shift
    if "$@" 2>/dev/null; then
        pass "$desc"
    else
        fail "$desc"
    fi
}

assert_failure() {
    local desc="$1"
    shift
    if ! "$@" 2>/dev/null; then
        pass "$desc"
    else
        fail "$desc"
    fi
}

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

# create a sandboxed test environment with isolated HOME
# usage: setup_sandbox
# sets: TEST_DIR, TEST_HOME, ORIGINAL_HOME
setup_sandbox() {
    TEST_DIR=$(mktemp -d)
    TEST_HOME="$TEST_DIR/home"
    mkdir -p "$TEST_HOME"
    ORIGINAL_HOME="$HOME"
    export HOME="$TEST_HOME"
}

# clean up sandboxed test environment
# usage: cleanup_sandbox
cleanup_sandbox() {
    export HOME="$ORIGINAL_HOME"
    # setup_dotfiles_sandbox / setup_cli_sandbox override DOTFILES_DIR; restore
    # the prior value (or unset if there was none) so subsequent unsandboxed
    # CLI runs find the real install
    if [[ -n "${_ORIGINAL_DOTFILES_DIR+x}" ]]; then
        if [[ -z "$_ORIGINAL_DOTFILES_DIR" ]]; then
            unset DOTFILES_DIR
        else
            export DOTFILES_DIR="$_ORIGINAL_DOTFILES_DIR"
        fi
        unset _ORIGINAL_DOTFILES_DIR
    fi
    rm -rf "$TEST_DIR"
}

# create a minimal dotfiles structure in the sandbox for testing
# usage: setup_dotfiles_sandbox
# sets: TEST_DOTFILES_DIR (a copy/mock of the repo structure)
setup_dotfiles_sandbox() {
    setup_sandbox
    TEST_DOTFILES_DIR="$TEST_DIR/dotfiles"
    mkdir -p "$TEST_DOTFILES_DIR"
    # snapshot DOTFILES_DIR (if any) so cleanup_sandbox can restore it
    _ORIGINAL_DOTFILES_DIR="${DOTFILES_DIR:-}"
    export DOTFILES_DIR="$TEST_DOTFILES_DIR"
}

# build a fuller dotfiles tree for behavioural CLI tests. symlinks the real
# scripts/themes/launchers (so the CLI under test is the actual file) but
# uses fake content for everything the CLI reads (CHANGELOG, zsh source,
# zshrc), so tests don't depend on the live developer state.
#
# usage:
#   setup_cli_sandbox
#   "$TEST_DOTFILES_DIR/scripts/dotfiles" version
#   cleanup_sandbox
setup_cli_sandbox() {
    setup_dotfiles_sandbox

    ln -s "$DOTFILES_ROOT/scripts" "$TEST_DOTFILES_DIR/scripts"
    ln -s "$DOTFILES_ROOT/themes" "$TEST_DOTFILES_DIR/themes"
    ln -s "$DOTFILES_ROOT/launchers" "$TEST_DOTFILES_DIR/launchers"
    # zsh/ holds the cheatsheet source; tests typically replace it with
    # a synthesised file, so create the directory but leave it empty
    mkdir -p "$TEST_DOTFILES_DIR/zsh"

    cat >"$TEST_DOTFILES_DIR/CHANGELOG.md" <<'EOF'
# Changelog

## [Unreleased]

### Added
- Fake unreleased entry for testing.

## [9.9.9] - 2099-01-01

### Added
- Fake released entry for testing.
EOF

    touch "$TEST_HOME/.zshrc"
}

# run the dotfiles CLI in the sandbox.
# usage: dotfiles_run version
#        dotfiles_run update --preview
# captures both stdout and stderr; returns the CLI's exit code
dotfiles_run() {
    "$TEST_DOTFILES_DIR/scripts/dotfiles" "$@" 2>&1
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
