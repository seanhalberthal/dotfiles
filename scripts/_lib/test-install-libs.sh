#!/usr/bin/env bash
set -euo pipefail
# shellcheck source=/dev/null
source "$(dirname "${BASH_SOURCE[0]}")/brewfile.sh"
# shellcheck source=/dev/null
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

# test suite for installation script libraries
# usage: ./scripts/_lib/test-install-libs.sh [--verbose]

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC2034
VERBOSE="${1:-}" # reserved for future verbose output

# source shared test helpers (colours, pass/fail/skip/section, assertions)
source "$SCRIPT_DIR/../tests/_test-helpers.sh"

# ===========================================================================
# Tests
# ===========================================================================

section "Library Sourcing"

# common.sh is already sourced at the top of this script, so we just verify it exists
if [[ -f "$SCRIPT_DIR/common.sh" ]]; then
    pass "common.sh exists"
else
    fail "common.sh not found"
    exit 1
fi

section "Colour Definitions"

# test that colour variables are defined (values may vary by terminal)
if [[ -n "$RED" && "$RED" != "$GREEN" ]]; then
    pass "RED is defined and different from GREEN"
else
    fail "RED is not properly defined"
fi

if [[ -n "$GREEN" && "$GREEN" != "$RED" ]]; then
    pass "GREEN is defined and different from RED"
else
    fail "GREEN is not properly defined"
fi

if [[ -n "$YELLOW" && "$YELLOW" != "$RED" && "$YELLOW" != "$GREEN" ]]; then
    pass "YELLOW is defined and different from others"
else
    fail "YELLOW is not properly defined"
fi

if [[ -n "$CYAN" && "$CYAN" != "$RED" && "$CYAN" != "$GREEN" && "$CYAN" != "$YELLOW" ]]; then
    pass "CYAN is defined and different from others"
else
    fail "CYAN is not properly defined"
fi

if [[ -n "$NC" && "$NC" != "$RED" && "$NC" != "$GREEN" && "$NC" != "$YELLOW" && "$NC" != "$CYAN" ]]; then
    pass "NC is defined and different from colors"
else
    fail "NC is not properly defined"
fi

section "Output Functions"

# test that output functions exist and are callable
for fn in error warn info success print_header print_section print_step; do
    if declare -F "$fn" >/dev/null 2>&1; then
        pass "$fn function exists"
    else
        fail "$fn function not found"
    fi
done

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

# is_linux (platform-dependent)
if [[ "$(uname)" == "Linux" ]]; then
    assert_success "is_linux returns true on Linux" is_linux
else
    assert_failure "is_linux returns false on non-Linux" is_linux
fi

# get_homebrew_prefix
prefix=$(get_homebrew_prefix)
if [[ "$(uname)" == "Darwin" ]]; then
    if [[ "$(uname -m)" == "arm64" ]]; then
        assert_equals "get_homebrew_prefix on Apple Silicon" "/opt/homebrew" "$prefix"
    else
        assert_equals "get_homebrew_prefix on Intel Mac" "/usr/local" "$prefix"
    fi
else
    assert_equals "get_homebrew_prefix on Linux" "/home/linuxbrew/.linuxbrew" "$prefix"
fi

section "Check Command Function"

# test check_command with a known command
if check_command "bash" "bash" "" >/dev/null 2>&1; then
    pass "check_command returns 0 for existing command"
else
    fail "check_command should return 0 for bash"
fi

# test check_command with nonexistent command
if ! check_command "nonexistent" "nonexistent_12345" "" >/dev/null 2>&1; then
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
# Install Preset Tests
# ===========================================================================

DOTFILES_DIR="$(dirname "$(dirname "$SCRIPT_DIR")")"

section "Brewfile Preset Markers"

BREWFILE="$DOTFILES_DIR/Brewfile"
if [[ -f "$BREWFILE" ]]; then
    brewfile_content=$(cat "$BREWFILE")

    if [[ "$brewfile_content" == *"@preset: minimal"* ]]; then
        pass "Brewfile has @preset: minimal marker"
    else
        fail "Brewfile missing @preset: minimal marker"
    fi

    if [[ "$brewfile_content" == *"@preset: core"* ]]; then
        pass "Brewfile has @preset: core marker"
    else
        fail "Brewfile missing @preset: core marker"
    fi

    if [[ "$brewfile_content" == *"@preset: full"* ]]; then
        pass "Brewfile has @preset: full marker"
    else
        fail "Brewfile missing @preset: full marker"
    fi

    if [[ "$brewfile_content" == *'brew "zsh"'* ]]; then
        pass "Brewfile has zsh"
    else
        fail "Brewfile missing zsh"
    fi

    if [[ "$brewfile_content" == *'cask "karabiner-elements"'* ]]; then
        pass "Brewfile has karabiner in full section"
    else
        fail "Brewfile missing karabiner"
    fi

    if [[ "$brewfile_content" == *'cask "music-presence"'* ]]; then
        pass "Brewfile has music-presence in full section"
    else
        fail "Brewfile missing music-presence"
    fi
else
    fail "Brewfile not found at $BREWFILE"
fi

section "Brewfile Filtering"

# create test Brewfile
TEST_BREWFILE=$(mktemp)
trap 'rm -f "$TEST_BREWFILE"' EXIT
cat >"$TEST_BREWFILE" <<'EOF'
tap "homebrew/bundle"
# @preset: minimal
brew "zsh"
brew "tmux"
# @preset: core
brew "neovim"
cask "ghostty"
# @preset: full
cask "hammerspoon"
EOF

# test minimal filtering
minimal_output=$(filter_brewfile "minimal" "$TEST_BREWFILE")
if [[ "$minimal_output" == *'brew "zsh"'* ]]; then
    pass "minimal preset includes zsh"
else
    fail "minimal preset should include zsh"
fi
if [[ "$minimal_output" != *'brew "neovim"'* ]]; then
    pass "minimal preset excludes neovim"
else
    fail "minimal preset should exclude neovim"
fi

# test core filtering
core_output=$(filter_brewfile "core" "$TEST_BREWFILE")
if [[ "$core_output" == *'brew "neovim"'* ]]; then
    pass "core preset includes neovim"
else
    fail "core preset should include neovim"
fi
if [[ "$core_output" != *'cask "hammerspoon"'* ]]; then
    pass "core preset excludes hammerspoon"
else
    fail "core preset should exclude hammerspoon"
fi

# test full filtering
full_output=$(filter_brewfile "full" "$TEST_BREWFILE")
if [[ "$(uname)" == "Darwin" ]]; then
    # on macOS, cask lines should be included
    if [[ "$full_output" == *'cask "hammerspoon"'* ]]; then
        pass "full preset includes hammerspoon"
    else
        fail "full preset should include hammerspoon"
    fi
else
    # on Linux, cask lines are filtered out (macOS-only packages)
    if [[ "$full_output" != *'cask "hammerspoon"'* ]]; then
        pass "full preset excludes hammerspoon cask on Linux"
    else
        fail "full preset should exclude hammerspoon cask on Linux"
    fi
fi

# TEST_BREWFILE cleanup is handled by trap

section "should_install Helper"

# define the helper for testing
should_install() {
    local required_preset="$1"
    local current_preset="$2"
    case "$required_preset" in
        minimal) return 0 ;;
        core) [[ "$current_preset" == "core" || "$current_preset" == "full" ]] ;;
        full) [[ "$current_preset" == "full" ]] ;;
    esac
}

# test minimal preset
if should_install "minimal" "minimal"; then
    pass "minimal: should_install 'minimal' returns true"
else
    fail "minimal: should_install 'minimal' should return true"
fi
if ! should_install "core" "minimal"; then
    pass "minimal: should_install 'core' returns false"
else
    fail "minimal: should_install 'core' should return false"
fi

# test core preset
if should_install "core" "core"; then
    pass "core: should_install 'core' returns true"
else
    fail "core: should_install 'core' should return true"
fi
if ! should_install "full" "core"; then
    pass "core: should_install 'full' returns false"
else
    fail "core: should_install 'full' should return false"
fi

# test full preset
if should_install "full" "full"; then
    pass "full: should_install 'full' returns true"
else
    fail "full: should_install 'full' should return true"
fi

section "Install Script Help"

INSTALL_SCRIPT="$DOTFILES_DIR/install.sh"
if [[ -f "$INSTALL_SCRIPT" ]]; then
    help_output=$("$INSTALL_SCRIPT" --help 2>&1 || true)

    if [[ "$help_output" == *"--minimal"* ]]; then
        pass "Help shows --minimal flag"
    else
        fail "Help missing --minimal flag"
    fi
    if [[ "$help_output" == *"--core"* ]]; then
        pass "Help shows --core flag"
    else
        fail "Help missing --core flag"
    fi
    if [[ "$help_output" == *"--full"* ]]; then
        pass "Help shows --full flag"
    else
        fail "Help missing --full flag"
    fi

    if [[ "$help_output" == *"--update"* ]]; then
        pass "Help shows --update flag"
    else
        fail "Help missing --update flag"
    fi

    if [[ "$help_output" == *"--yes"* ]]; then
        pass "Help shows --yes flag"
    else
        fail "Help missing --yes flag"
    fi

    if [[ "$help_output" == *"--skip-steps"* ]]; then
        pass "Help shows --skip-steps flag"
    else
        fail "Help missing --skip-steps flag"
    fi
else
    fail "install.sh not found"
fi

section "is_step_skipped Helper"

# define is_step_skipped for isolated testing
is_step_skipped() {
    local step_name="$1"
    [[ ",$SKIP_STEPS," == *",$step_name,"* ]]
}

SKIP_STEPS=""
if ! is_step_skipped "homebrew"; then
    pass "empty skip list: homebrew not skipped"
else
    fail "empty skip list should not skip homebrew"
fi

SKIP_STEPS="homebrew"
if is_step_skipped "homebrew"; then
    pass "single item: homebrew skipped"
else
    fail "single item should skip homebrew"
fi

SKIP_STEPS="homebrew,packages,symlinks"
if is_step_skipped "homebrew"; then
    pass "multi-item: homebrew skipped"
else
    fail "multi-item should skip homebrew"
fi
if is_step_skipped "packages"; then
    pass "multi-item: packages skipped"
else
    fail "multi-item should skip packages"
fi
if is_step_skipped "symlinks"; then
    pass "multi-item: symlinks skipped"
else
    fail "multi-item should skip symlinks"
fi
if ! is_step_skipped "keyd"; then
    pass "multi-item: keyd not skipped"
else
    fail "multi-item should not skip keyd"
fi

# partial name must not match
SKIP_STEPS="homebrew"
if ! is_step_skipped "home"; then
    pass "partial name 'home' does not match 'homebrew'"
else
    fail "partial name 'home' should not match 'homebrew'"
fi

SKIP_STEPS="" # reset

section "Tab Completion - Update Sub-flags"

FRAMEWORK_FILE="$DOTFILES_DIR/zsh/dotfiles.zsh"
COMPLETION_FILE="$DOTFILES_DIR/zsh/functions/_dotfiles"
if [[ -f "$FRAMEWORK_FILE" ]]; then
    framework_content=$(cat "$FRAMEWORK_FILE")
    # completion may be inline or in autoload file
    comp_content="$framework_content"
    if [[ -f "$COMPLETION_FILE" ]]; then
        comp_content+=$(cat "$COMPLETION_FILE")
    fi

    if [[ "$comp_content" == *"'--force:"* ]]; then
        pass "completion includes --force option"
    else
        fail "completion should include --force option"
    fi

    if [[ "$comp_content" == *"'--preview:"* ]]; then
        pass "completion includes --preview option"
    else
        fail "completion should include --preview option"
    fi
else
    skip "dotfiles.zsh not found"
fi

section "Sub-script Preset Awareness"

check_reads_preset() {
    local script="$1"
    local name="$2"
    if [[ -f "$script" ]] && grep -q 'DOTFILES_PRESET' "$script"; then
        pass "$name reads DOTFILES_PRESET"
    elif [[ -f "$script" ]]; then
        fail "$name should read DOTFILES_PRESET"
    else
        skip "$name not found"
    fi
}

check_reads_preset "$SCRIPT_DIR/../install/install-packages.sh" "install-packages.sh"
check_reads_preset "$SCRIPT_DIR/../install/create-symlinks.sh" "create-symlinks.sh"
check_reads_preset "$SCRIPT_DIR/../install/backup-existing.sh" "backup-existing.sh"
check_reads_preset "$SCRIPT_DIR/../install/health-check.sh" "health-check.sh"
# check-prerequisites.sh is intentionally preset-agnostic: it only verifies
# the two tools the install bootstrap needs (git, brew). preset-aware checks
# happen later in install-packages.sh / health-check.sh

# ===========================================================================
# Zshrc Quick Wins Tests
# ===========================================================================

section "Zsh Framework Shell Profiler"

FRAMEWORK_FILE="$DOTFILES_DIR/zsh/dotfiles.zsh"
if [[ -f "$FRAMEWORK_FILE" ]]; then
    framework_content=$(cat "$FRAMEWORK_FILE")

    # check for zprof module loading
    if [[ "$framework_content" == *'zmodload zsh/zprof'* ]]; then
        pass "dotfiles.zsh has zprof module loading"
    else
        fail "dotfiles.zsh missing zprof module loading"
    fi

    # check for ZPROF conditional (single quotes are intentional, matching literal string)
    # shellcheck disable=SC2016
    if [[ "$framework_content" == *'[[ -n "$ZPROF" ]]'* ]]; then
        pass "dotfiles.zsh has ZPROF conditional"
    else
        fail "dotfiles.zsh missing ZPROF conditional"
    fi

    # check for zsh-profile function
    if [[ "$framework_content" == *'zsh-profile()'* ]]; then
        pass "dotfiles.zsh has zsh-profile function"
    else
        fail "dotfiles.zsh missing zsh-profile function"
    fi

    # check for zsh-profile-detailed function
    if [[ "$framework_content" == *'zsh-profile-detailed()'* ]]; then
        pass "dotfiles.zsh has zsh-profile-detailed function"
    else
        fail "dotfiles.zsh missing zsh-profile-detailed function"
    fi
else
    fail "dotfiles.zsh not found at $FRAMEWORK_FILE"
fi

section "Zsh Framework Dotfiles CLI Completion"

if [[ -f "$FRAMEWORK_FILE" ]]; then
    # check for _dotfiles autoload (moved from inline to zsh/functions/_dotfiles)
    completion_file="$DOTFILES_ROOT/zsh/functions/_dotfiles"
    if [[ "$framework_content" == *'autoload -Uz _dotfiles'* ]]; then
        pass "dotfiles.zsh autoloads _dotfiles completion"
    elif [[ "$framework_content" == *'_dotfiles()'* ]]; then
        pass "dotfiles.zsh has _dotfiles completion function (inline)"
    else
        fail "dotfiles.zsh missing _dotfiles completion (autoload or inline)"
    fi

    # check for compdef registration
    if [[ "$framework_content" == *'compdef _dotfiles dotfiles'* ]]; then
        pass "dotfiles.zsh registers dotfiles completion"
    else
        fail "dotfiles.zsh missing dotfiles completion registration"
    fi

    # check completion includes expected commands (in autoload file or inline)
    completion_content=""
    if [[ -f "$completion_file" ]]; then
        completion_content=$(<"$completion_file")
    fi
    check_content="${framework_content}${completion_content}"
    if [[ "$check_content" == *"'update:"* ]] &&
        [[ "$check_content" == *"'status:"* ]] &&
        [[ "$check_content" == *"'health:"* ]]; then
        pass "dotfiles completion includes expected commands"
    else
        fail "dotfiles completion missing expected commands"
    fi
fi

# ===========================================================================
# Summary
# ===========================================================================

print_summary

if [[ $FAIL -gt 0 ]]; then
    exit 1
fi
