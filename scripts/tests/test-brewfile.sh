#!/usr/bin/env bash
set -euo pipefail

# test suite for Brewfile filtering utilities

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# note: test scripts use full cd+pwd for absolute paths;
# production scripts use the simpler ${BASH_SOURCE%/*} pattern
source "$SCRIPT_DIR/../_lib/brewfile.sh"
source "$SCRIPT_DIR/../_lib/common.sh"

# source shared test helpers (colours, pass/fail/skip/section, assertions)
source "$SCRIPT_DIR/_test-helpers.sh"

section "Brewfile Library Tests"

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
brew "full-only-formula"
cask "hammerspoon"
EOF

section "filter_brewfile Function"

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
if [[ "$full_output" == *'brew "full-only-formula"'* ]]; then
    pass "full preset includes full-tier formula"
else
    fail "full preset should include full-tier formula"
fi

# casks are stripped on Linux regardless of preset tier (see brewfile.sh),
# so hammerspoon's presence in "full" output is platform-dependent
if is_macos; then
    if [[ "$full_output" == *'cask "hammerspoon"'* ]]; then
        pass "full preset includes hammerspoon (macOS)"
    else
        fail "full preset should include hammerspoon on macOS"
    fi
else
    if [[ "$full_output" != *'cask "hammerspoon"'* ]]; then
        pass "full preset excludes hammerspoon (casks stripped on Linux)"
    else
        fail "full preset should exclude hammerspoon on Linux (casks are macOS-only)"
    fi
fi

# test invalid preset handling
if ! filter_brewfile "invalid" "$TEST_BREWFILE" 2>/dev/null; then
    pass "Invalid preset returns error"
else
    fail "Invalid preset should return error"
fi

section "macOS-only Formula Filtering"

# create test Brewfile with macOS-only markers
MACOS_BREWFILE=$(mktemp)
cat >"$MACOS_BREWFILE" <<'EOF'
tap "homebrew/bundle"
# @preset: core
brew "fnm"                    # macOS-only (Linux uses curl installer)
brew "neovim"
brew "swift-format"           # macOS-only
brew "oven-sh/bun/bun"
EOF

if is_macos; then
    # on macOS: macOS-only formulas should be retained
    macos_output=$(filter_brewfile "core" "$MACOS_BREWFILE")
    if [[ "$macos_output" == *'brew "fnm"'* ]]; then
        pass "macOS-only formula retained on Darwin (fnm)"
    else
        fail "macOS-only formula should be included on Darwin"
    fi
    if [[ "$macos_output" == *'brew "swift-format"'* ]]; then
        pass "macOS-only formula retained on Darwin (swift-format)"
    else
        fail "macOS-only formula should be included on Darwin"
    fi
else
    # on Linux: macOS-only formulas should be stripped
    linux_output=$(filter_brewfile "core" "$MACOS_BREWFILE")
    if [[ "$linux_output" != *'brew "fnm"'* ]]; then
        pass "macOS-only formula stripped on Linux (fnm)"
    else
        fail "macOS-only formula should be excluded on Linux"
    fi
    if [[ "$linux_output" != *'brew "swift-format"'* ]]; then
        pass "macOS-only formula stripped on Linux (swift-format)"
    else
        fail "macOS-only formula should be excluded on Linux"
    fi
fi

# on both platforms: non-macOS-only formulas should be retained
both_output=$(filter_brewfile "core" "$MACOS_BREWFILE")
if [[ "$both_output" == *'brew "neovim"'* ]]; then
    pass "Non-macOS-only formula retained"
else
    fail "Non-macOS-only formula should not be stripped"
fi
if [[ "$both_output" == *'brew "oven-sh/bun/bun"'* ]]; then
    pass "Formula without macOS-only comment retained"
else
    fail "Formula without macOS-only comment should not be stripped"
fi

rm -f "$MACOS_BREWFILE"

section "create_filtered_brewfile Function"

# test that create_filtered_brewfile creates a file that persists
# regression test for the EXIT trap bug where the trap fired
# in the command substitution subshell, deleting the file immediately
FILTERED=$(create_filtered_brewfile "full" "$TEST_BREWFILE")
if [[ -f "$FILTERED" ]]; then
    pass "Temp file persists after command substitution"
else
    fail "Temp file should persist after command substitution (regression: EXIT trap bug)"
fi

# verify the filtered file contains expected content
if [[ -f "$FILTERED" ]]; then
    filtered_content=$(cat "$FILTERED")
    if [[ "$filtered_content" == *'brew "full-only-formula"'* ]]; then
        pass "Filtered file contains correct content"
    else
        fail "Filtered file should contain full preset content"
    fi

    # clean up the temp file
    rm -f "$FILTERED"
fi

# test that create_filtered_brewfile returns error for invalid preset
if ! FILTERED=$(create_filtered_brewfile "invalid" "$TEST_BREWFILE" 2>/dev/null); then
    pass "create_filtered_brewfile returns error for invalid preset"
else
    fail "create_filtered_brewfile should return error for invalid preset"
    rm -f "$FILTERED"
fi

print_summary

if [[ $FAIL -gt 0 ]]; then
    exit 1
fi
