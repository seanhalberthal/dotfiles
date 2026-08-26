#!/usr/bin/env bash
set -euo pipefail

# unit tests for theme-delete script

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOTFILES_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
THEME_DELETE="$DOTFILES_ROOT/scripts/theme-delete"
GENERATE_THEME="$DOTFILES_ROOT/scripts/generate-theme"
THEMES_GENERATED="$DOTFILES_ROOT/themes/generated"
NVIM_GENERATED="$DOTFILES_ROOT/nvim/colors/generated"

# source shared test helpers (colours, pass/fail/skip/section, assertions)
source "$SCRIPT_DIR/_test-helpers.sh"

section "Script Exists and Is Executable"

if [[ -f "$THEME_DELETE" ]]; then
    pass "theme-delete script exists"
else
    fail "theme-delete script should exist"
fi

if [[ -x "$THEME_DELETE" ]]; then
    pass "theme-delete script is executable"
else
    fail "theme-delete script should be executable"
fi

section "ShellCheck Validation"

if command -v shellcheck >/dev/null 2>&1; then
    if shellcheck -x "$THEME_DELETE" 2>/dev/null; then
        pass "theme-delete passes shellcheck"
    else
        fail "theme-delete should pass shellcheck"
    fi
else
    printf "  (shellcheck not installed, skipping)\n"
fi

section "Help Output"

help_output=$("$THEME_DELETE" help 2>&1) || true
if [[ "$help_output" == *"theme-delete"* ]]; then
    pass "help shows script name"
else
    fail "help should show script name"
fi

if [[ "$help_output" == *"all"* ]]; then
    pass "help mentions all subcommand"
else
    fail "help should mention all subcommand"
fi

if [[ "$help_output" == *"list"* ]]; then
    pass "help mentions list subcommand"
else
    fail "help should mention list subcommand"
fi

section "Refuses to Delete Custom Themes"

# all hand-crafted themes should be refused
for theme_file in "$DOTFILES_ROOT/themes/"*.theme; do
    [[ -f "$theme_file" ]] || continue
    theme_name=$(basename "$theme_file" .theme)
    output=$("$THEME_DELETE" "$theme_name" 2>&1) && exit_code=0 || exit_code=$?
    if [[ "$exit_code" -ne 0 ]] && [[ "$output" == *"custom theme"* ]]; then
        pass "refuses to delete custom theme: $theme_name"
    else
        fail "should refuse to delete custom theme: $theme_name"
    fi
done

section "Handles Non-Existent Theme"

output=$("$THEME_DELETE" "nonexistent-theme-xyz" 2>&1) && exit_code=0 || exit_code=$?
if [[ "$exit_code" -ne 0 ]] && [[ "$output" == *"No generated theme found"* ]]; then
    pass "reports error for non-existent theme"
else
    fail "should report error for non-existent theme"
fi

section "Delete Generated Theme"

# generate a test theme, then delete it
if [[ -d "/Applications/Ghostty.app/Contents/Resources/ghostty/themes" ]]; then
    "$GENERATE_THEME" zenburn --quiet >/dev/null 2>&1

    if [[ -f "$THEMES_GENERATED/zenburn.theme" ]]; then
        pass "generated zenburn theme for test"
    else
        fail "should generate zenburn theme"
    fi

    output=$("$THEME_DELETE" zenburn 2>&1) || true
    if [[ ! -f "$THEMES_GENERATED/zenburn.theme" ]] && [[ ! -f "$NVIM_GENERATED/zenburn.lua" ]]; then
        pass "deleted generated theme files"
    else
        fail "should delete generated theme files"
    fi
else
    printf "  (Ghostty not installed, skipping generation tests)\n"
fi

section "Auto-Switch When Deleting Current Theme"

if [[ -d "/Applications/Ghostty.app/Contents/Resources/ghostty/themes" ]]; then
    # set up isolated config so we don't affect real current-theme
    TEST_XDG=$(mktemp -d)
    mkdir -p "$TEST_XDG/dotfiles"

    # generate a theme to delete
    "$GENERATE_THEME" zenburn --quiet >/dev/null 2>&1

    # pretend zenburn is the current theme
    echo "zenburn" >"$TEST_XDG/dotfiles/current-theme"

    output=$(XDG_CONFIG_HOME="$TEST_XDG" "$THEME_DELETE" zenburn 2>&1) || true

    # should have switched away from zenburn
    if [[ -f "$TEST_XDG/dotfiles/current-theme" ]]; then
        new_theme=$(cat "$TEST_XDG/dotfiles/current-theme")
        if [[ "$new_theme" != "zenburn" ]] && [[ -n "$new_theme" ]]; then
            pass "auto-switched from deleted theme to '$new_theme'"
        else
            fail "should auto-switch away from deleted theme (got: '$new_theme')"
        fi
    else
        fail "current-theme file should exist after auto-switch"
    fi

    if [[ "$output" == *"switching to"* ]]; then
        pass "output mentions switching to fallback theme"
    else
        fail "output should mention switching to fallback theme"
    fi

    rm -rf "$TEST_XDG"
else
    skip "auto-switch on delete (Ghostty not installed)"
fi

section "No Auto-Switch When Deleting Non-Current Theme"

if [[ -d "/Applications/Ghostty.app/Contents/Resources/ghostty/themes" ]]; then
    TEST_XDG=$(mktemp -d)
    mkdir -p "$TEST_XDG/dotfiles"

    # generate a theme to delete
    "$GENERATE_THEME" zenburn --quiet >/dev/null 2>&1

    # set current theme to dracula (a custom theme, not the one being deleted)
    echo "dracula" >"$TEST_XDG/dotfiles/current-theme"

    XDG_CONFIG_HOME="$TEST_XDG" "$THEME_DELETE" zenburn >/dev/null 2>&1 || true

    new_theme=$(cat "$TEST_XDG/dotfiles/current-theme")
    if [[ "$new_theme" == "dracula" ]]; then
        pass "current theme unchanged when deleting a different theme"
    else
        fail "current theme should stay 'dracula' (got: '$new_theme')"
    fi

    rm -rf "$TEST_XDG"
else
    skip "no auto-switch for non-current (Ghostty not installed)"
fi

section "Auto-Switch on Delete All With Generated Current Theme"

if [[ -d "/Applications/Ghostty.app/Contents/Resources/ghostty/themes" ]]; then
    TEST_XDG=$(mktemp -d)
    mkdir -p "$TEST_XDG/dotfiles"

    # generate a theme so there's something to delete
    "$GENERATE_THEME" zenburn --quiet >/dev/null 2>&1

    # pretend zenburn is the current theme
    echo "zenburn" >"$TEST_XDG/dotfiles/current-theme"

    output=$(XDG_CONFIG_HOME="$TEST_XDG" "$THEME_DELETE" all --yes 2>&1) || true

    new_theme=$(cat "$TEST_XDG/dotfiles/current-theme")
    if [[ "$new_theme" == "dracula" ]]; then
        pass "delete all switches generated current theme to default"
    else
        fail "delete all should switch to 'dracula' (got: '$new_theme')"
    fi

    rm -rf "$TEST_XDG"
else
    skip "auto-switch on delete all (Ghostty not installed)"
fi

section "No Auto-Switch on Delete All With Custom Current Theme"

if [[ -d "/Applications/Ghostty.app/Contents/Resources/ghostty/themes" ]]; then
    TEST_XDG=$(mktemp -d)
    mkdir -p "$TEST_XDG/dotfiles"

    # generate a theme so delete all has work to do
    "$GENERATE_THEME" zenburn --quiet >/dev/null 2>&1

    # current theme is a custom theme, should not be affected
    echo "catppuccin-mocha" >"$TEST_XDG/dotfiles/current-theme"

    XDG_CONFIG_HOME="$TEST_XDG" "$THEME_DELETE" all --yes >/dev/null 2>&1 || true

    new_theme=$(cat "$TEST_XDG/dotfiles/current-theme")
    if [[ "$new_theme" == "catppuccin-mocha" ]]; then
        pass "delete all leaves custom current theme unchanged"
    else
        fail "delete all should leave 'catppuccin-mocha' unchanged (got: '$new_theme')"
    fi

    rm -rf "$TEST_XDG"
else
    skip "no auto-switch on delete all with custom theme (Ghostty not installed)"
fi

section "List Generated Themes"

# list should produce valid output (themed listing or empty message)
output=$("$THEME_DELETE" list 2>&1) || true
if [[ "$output" == *"No generated themes"* ]]; then
    pass "list shows empty state when no generated themes"
elif [[ "$output" == *"Generated themes"* ]]; then
    pass "list shows generated themes listing"
else
    fail "list should show generated themes or empty message"
fi

print_summary
[[ "$FAIL" -eq 0 ]] || exit 1
