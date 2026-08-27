#!/usr/bin/env bash
set -euo pipefail

# unit tests for tmux theme picker
# tests the fzf-compatible theme picker output

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
THEME_PICKER="$SCRIPT_DIR/../themes/pick.sh"
DOTFILES_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
THEMES_DIR="$DOTFILES_ROOT/themes"

source "$SCRIPT_DIR/_test-helpers.sh"

# ===========================================================================
# Tests
# ===========================================================================

section "Script Exists and Is Executable"

if [[ -f "$THEME_PICKER" ]]; then
    pass "pick-theme.sh exists"
else
    fail "pick-theme.sh not found"
    exit 1
fi

if [[ -x "$THEME_PICKER" ]]; then
    pass "pick-theme.sh is executable"
else
    fail "pick-theme.sh is not executable"
fi

section "ShellCheck Validation"

if command -v shellcheck &>/dev/null; then
    # SC2155 is for declare/assign pattern which is common and harmless here
    if shellcheck -x -S warning -e SC1091 -e SC2155 "$THEME_PICKER" 2>/dev/null; then
        pass "pick-theme.sh passes shellcheck"
    else
        fail "pick-theme.sh has shellcheck warnings"
    fi
else
    skip "shellcheck not installed"
fi

section "Output Format - Header"

output=$("$THEME_PICKER" 2>&1) || true

if [[ "$output" == *"Theme Switcher"* ]]; then
    pass "output includes 'Theme Switcher' header"
else
    fail "output should include 'Theme Switcher' header"
fi

# check for box drawing characters or similar header formatting
if [[ "$output" == *"╭"* ]] || [[ "$output" == *"─"* ]] || [[ "$output" =~ ^[[:space:]]*═+ ]]; then
    pass "output has formatted header box"
else
    fail "output should have formatted header box"
fi

if [[ "$output" == *"tmux"* ]] && [[ "$output" == *"ghostty"* ]]; then
    pass "output mentions tmux and ghostty"
else
    fail "output should mention tmux and ghostty"
fi

section "Output Format - Theme List"

# should list all available themes
for theme_file in "$THEMES_DIR"/*.theme; do
    if [[ -f "$theme_file" ]]; then
        theme_name=$(basename "$theme_file" .theme)

        if [[ "$output" == *"$theme_name"* ]]; then
            pass "output lists $theme_name theme"
        else
            fail "output should list $theme_name theme"
        fi
    fi
done

section "Output Format - Theme Display Names"

# should show theme names (kebab-case)
if [[ "$output" == *"dracula"* ]]; then
    pass "output shows dracula theme"
else
    fail "output should show theme names"
fi

section "Output Format - Current Theme Marker"

# should mark current theme with a bullet or similar
if [[ "$output" == *"●"* ]] || [[ "$output" == *"*"* ]] || [[ "$output" == *">"* ]]; then
    pass "output includes current theme marker"
else
    fail "output should mark current theme with ● or similar"
fi

# should also have inactive markers
if [[ "$output" == *"○"* ]] || [[ "$output" == *" "* ]]; then
    pass "output includes inactive theme markers"
else
    skip "inactive theme marker check"
fi

section "Output Format - Line Count"

# count non-empty lines
line_count=$(echo "$output" | grep -c . || true)

# should have header lines + theme lines
# at least: 3 header lines + 4 themes = 7+ lines
if [[ $line_count -ge 7 ]]; then
    pass "output has sufficient lines (${line_count} lines)"
else
    fail "output should have at least 7 lines (header + themes), got $line_count"
fi

section "Output Format - fzf Compatibility"

# fzf expects plain text with optional ANSI colours
# test that each theme line can be parsed

theme_lines=$(echo "$output" | grep -E "(dracula|nord|catppuccin|tokyo)" || true)
theme_line_count=$(echo "$theme_lines" | grep -c . || true)

if [[ $theme_line_count -ge 4 ]]; then
    pass "output has at least 4 theme lines"
else
    fail "output should have at least 4 theme lines, got $theme_line_count"
fi

# each theme line should have theme name visible
for theme_file in "$THEMES_DIR"/*.theme; do
    if [[ -f "$theme_file" ]]; then
        theme_name=$(basename "$theme_file" .theme)

        # strip ANSI codes to test plain text (use sed as bash can't handle these complex patterns)
        # shellcheck disable=SC2001
        plain_output=$(echo "$output" | sed 's/\x1b\[[0-9;]*m//g')

        if echo "$plain_output" | grep -q "$theme_name"; then
            pass "$theme_name is present in plain text (fzf compatible)"
        else
            fail "$theme_name should be in plain text output"
        fi
    fi
done

section "Script Structure"

script_content=$(cat "$THEME_PICKER")

# should have get_current_theme function
if [[ "$script_content" == *"get_current_theme()"* ]]; then
    pass "script defines get_current_theme function"
else
    fail "script should define get_current_theme function"
fi

# should have list_themes_for_fzf function
if [[ "$script_content" == *"list_themes_for_fzf()"* ]]; then
    pass "script defines list_themes_for_fzf function"
else
    fail "script should define list_themes_for_fzf function"
fi

# should use generate-theme list to get all themes
if [[ "$script_content" == *'generate-theme'* ]]; then
    pass "script uses generate-theme for theme listing"
else
    fail "script should use generate-theme for theme listing"
fi

# should use THEMES_DIR variable
if [[ "$script_content" == *'THEMES_DIR'* ]]; then
    pass "script uses THEMES_DIR variable"
else
    fail "script should use THEMES_DIR variable"
fi

# should use CURRENT_THEME_FILE variable
if [[ "$script_content" == *'CURRENT_THEME_FILE'* ]]; then
    pass "script uses CURRENT_THEME_FILE variable"
else
    fail "script should use CURRENT_THEME_FILE variable"
fi

section "Colour Codes"

# should use ANSI colour codes for visual appeal (via common.sh which sources colours.sh)
if [[ "$script_content" == *"CYAN="* ]] || [[ "$script_content" == *"colours.sh"* ]] || [[ "$script_content" == *"common.sh"* ]] || [[ "$script_content" == *"033"* ]]; then
    pass "script defines or sources colour variables"
else
    fail "script should define or source colour variables"
fi

# check that colours are actually used in output
# look for ANSI escape sequences using od to check raw bytes
if echo "$output" | head -1 | od -c | grep -q "033"; then
    pass "output contains ANSI colour codes"
else
    fail "output should contain ANSI colour codes for visual appeal"
fi

section "Current Theme Detection"

# create test config directory
# script uses $XDG_CONFIG_HOME/dotfiles/current-theme
TEST_XDG_BASE=$(mktemp -d)
TEST_CONFIG_DIR="$TEST_XDG_BASE/dotfiles"
TEST_CURRENT_THEME="$TEST_CONFIG_DIR/current-theme"
export XDG_CONFIG_HOME="$TEST_XDG_BASE"

trap 'rm -rf "$TEST_XDG_BASE"' EXIT

# test with no saved theme (should default)
test_output=$("$THEME_PICKER" 2>&1) || true

# should not error
if [[ -n "$test_output" ]]; then
    pass "script works without saved theme preference"
else
    fail "script should work without saved theme preference"
fi

# test with saved theme preference
mkdir -p "$TEST_CONFIG_DIR"
echo "nord" >"$TEST_CURRENT_THEME"

test_output=$("$THEME_PICKER" 2>&1) || true

# should mark nord as current (● symbol)
if echo "$test_output" | grep "nord" | grep -q "●"; then
    pass "script marks saved theme as current"
else
    fail "script should mark saved theme (nord) as current"
fi

section "Integration with tmux"

# check if theme-picker is bound in tmux config
tmux_config="${XDG_CONFIG_HOME:-$HOME/.config}/tmux/tmux.conf"
tmux_template="$DOTFILES_ROOT/tmux/tmux.conf.template"

theme_picker_bound=false

if [[ -f "$tmux_config" ]]; then
    if grep -q "theme-picker" "$tmux_config"; then
        pass "theme-picker is referenced in tmux config"
        theme_picker_bound=true
    fi
fi

if [[ -f "$tmux_template" ]]; then
    if grep -q "theme-picker" "$tmux_template"; then
        pass "theme-picker is referenced in tmux template"
        theme_picker_bound=true
    fi
fi

if ! $theme_picker_bound; then
    skip "theme-picker tmux binding check (not configured yet)"
fi

# check that theme picker script calls reload-ghostty.sh
# (moved from inline tmux template to picker.sh)
PICKER_SCRIPT="$SCRIPT_DIR/../themes/picker.sh"
if [[ -f "$PICKER_SCRIPT" ]]; then
    if grep -q "reload-ghostty.sh" "$PICKER_SCRIPT"; then
        pass "theme picker calls reload-ghostty.sh"
    else
        fail "theme picker should call reload-ghostty.sh"
    fi
fi

# verify reload-ghostty.sh exists and is executable
GHOSTTY_RELOAD="$SCRIPT_DIR/../themes/reload-ghostty.sh"
if [[ -f "$GHOSTTY_RELOAD" ]]; then
    pass "reload-ghostty.sh exists in tmux scripts"
else
    fail "reload-ghostty.sh should exist in tmux scripts directory"
fi

if [[ -x "$GHOSTTY_RELOAD" ]]; then
    pass "reload-ghostty.sh is executable"
else
    fail "reload-ghostty.sh should be executable"
fi

section "Theme Picker Wrapper Performance"

if [[ -f "$PICKER_SCRIPT" ]]; then
    if grep -q 'pick.sh" --pos' "$PICKER_SCRIPT"; then
        fail "theme picker wrapper should not invoke pick.sh twice for --pos"
    else
        pass "theme picker wrapper avoids redundant pick.sh --pos call"
    fi

    if grep -q 'awk .*\$selected' "$PICKER_SCRIPT"; then
        fail "theme picker wrapper should parse selected theme without awk"
    else
        pass "theme picker wrapper avoids awk for selected theme parsing"
    fi
fi

section "Error Handling"

# test with missing themes directory
THEMES_DIR_BACKUP="$THEMES_DIR"
export THEMES_DIR="/nonexistent/themes/directory"

error_output=$("$THEME_PICKER" 2>&1) && exit_code=0 || exit_code=$?

# should either error or handle gracefully
if [[ $exit_code -ne 0 ]] || [[ -z "$error_output" ]]; then
    pass "handles missing themes directory"
else
    skip "missing themes directory handling"
fi

export THEMES_DIR="$THEMES_DIR_BACKUP"

section "--pos Flag (Current Theme Position)"

# test --pos returns a number
pos_output=$("$THEME_PICKER" --pos 2>&1) || true

if [[ "$pos_output" =~ ^[0-9]+$ ]]; then
    pass "--pos returns a numeric position"
else
    fail "--pos should return a numeric position, got: $pos_output"
fi

# position should be >= 1
if [[ -n "$pos_output" ]] && [[ "$pos_output" -ge 1 ]]; then
    pass "--pos position is >= 1 (1-based index)"
else
    fail "--pos position should be >= 1"
fi

# count available themes
theme_count=0
for tf in "$THEMES_DIR"/*.theme; do
    [[ -f "$tf" ]] && theme_count=$((theme_count + 1))
done

# position should not exceed theme count
if [[ -n "$pos_output" ]] && [[ "$pos_output" -le "$theme_count" ]]; then
    pass "--pos position ($pos_output) is within theme count ($theme_count)"
else
    fail "--pos position ($pos_output) should be <= theme count ($theme_count)"
fi

# test with a known theme set via XDG
mkdir -p "$TEST_CONFIG_DIR"
echo "nord" >"$TEST_CURRENT_THEME"
pos_nord=$(XDG_CONFIG_HOME="$TEST_XDG_BASE" "$THEME_PICKER" --pos 2>&1) || true

# should be different from default if nord isn't the first theme
if [[ "$pos_nord" =~ ^[0-9]+$ ]]; then
    pass "--pos works with saved theme preference"
else
    fail "--pos should work with saved theme preference"
fi

section "Output Stability"

# run twice and compare output (should be consistent)
output1=$("$THEME_PICKER" 2>&1) || true
sleep 0.1
output2=$("$THEME_PICKER" 2>&1) || true

# strip timestamps if any (use sed for performance)
# shellcheck disable=SC2001
output1_clean=$(echo "$output1" | sed 's/[0-9]\{2\}:[0-9]\{2\}:[0-9]\{2\}//g')
# shellcheck disable=SC2001
output2_clean=$(echo "$output2" | sed 's/[0-9]\{2\}:[0-9]\{2\}:[0-9]\{2\}//g')

if [[ "$output1_clean" == "$output2_clean" ]]; then
    pass "output is stable across multiple runs"
else
    fail "output should be consistent across runs"
fi

# ===========================================================================
# Summary
# ===========================================================================

print_summary
[[ $FAIL -gt 0 ]] && exit 1
exit 0
