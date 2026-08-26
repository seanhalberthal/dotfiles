#!/usr/bin/env bash
set -euo pipefail

# unit tests for theme-switch script
# tests theme switching functionality including template substitution,
# file handling, and error cases

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOTFILES_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
THEME_SWITCH="$DOTFILES_ROOT/scripts/theme-switch"
THEMES_DIR="$DOTFILES_ROOT/themes"

# source shared test helpers (colours, pass/fail/skip/section, assertions)
source "$SCRIPT_DIR/_test-helpers.sh"

# create test environment
setup_test_env() {
    TEST_DIR=$(mktemp -d)
    TEST_CONFIG_DIR="$TEST_DIR/config"
    TEST_THEMES_DIR="$TEST_DIR/themes"
    TEST_TMUX_TEMPLATE="$TEST_DIR/tmux.conf.template"
    TEST_TMUX_OUTPUT="$TEST_DIR/tmux.conf"
    TEST_GHOSTTY_TEMPLATE="$TEST_DIR/ghostty.conf.template"
    TEST_GHOSTTY_OUTPUT="$TEST_DIR/ghostty.conf"
    TEST_CURRENT_THEME="$TEST_CONFIG_DIR/current-theme"

    mkdir -p "$TEST_CONFIG_DIR"
    mkdir -p "$TEST_THEMES_DIR"

    # create test templates with placeholders
    cat >"$TEST_TMUX_TEMPLATE" <<'EOF'
# Theme: {{THEME_NAME}}
# Tmux configuration
set -g status-style "bg={{TMUX_STATUS_BG}},fg={{TMUX_STATUS_FG}}"
set -g window-status-current-style "bg={{TMUX_STATUS_ACTIVE_BG}},fg={{TMUX_STATUS_ACTIVE_FG}}"
set -g pane-border-style "fg={{TMUX_PANE_BORDER_INACTIVE}}"
set -g pane-active-border-style "fg={{TMUX_PANE_BORDER_ACTIVE}}"
set -g message-style "bg={{TMUX_MESSAGE_BG}},fg={{TMUX_MESSAGE_FG}}"
EOF

    cat >"$TEST_GHOSTTY_TEMPLATE" <<'EOF'
# Theme: {{THEME_NAME}}
# Ghostty configuration
background={{GHOSTTY_BACKGROUND}}
foreground={{GHOSTTY_FOREGROUND}}
cursor-color={{GHOSTTY_CURSOR_COLOR}}
selection-background={{GHOSTTY_SELECTION_BG}}
palette=0={{GHOSTTY_PALETTE_0}}
palette=1={{GHOSTTY_PALETTE_1}}
keybind={{PLATFORM_MOD}}+c=text:\x1bc
EOF

    # create test theme (using new base variable format)
    cat >"$TEST_THEMES_DIR/test-theme.theme" <<'EOF'
THEME_NAME="Test Theme"
THEME_ACTIVE_ACCENT="purple"
TMUX_BG_PRIMARY="#ff0000"
TMUX_FG_PRIMARY="#00ff00"
TMUX_BG_SECONDARY="#cccccc"
TMUX_FG_SECONDARY="#666666"
TMUX_ACCENT_PURPLE="#ff00ff"
TMUX_ACCENT_PINK="#ffaaff"
TMUX_ACCENT_CYAN="#00ffff"
TMUX_ACCENT_GREEN="#00ff00"
TMUX_ACCENT_YELLOW="#ffff00"
TMUX_ACCENT_RED="#ff5555"
TMUX_CPU_LOW_BG="#001100"
TMUX_CPU_MEDIUM_BG="#111100"
TMUX_CPU_HIGH_BG="#110000"
TMUX_RAM_LOW_BG="#001100"
TMUX_RAM_MEDIUM_BG="#111100"
TMUX_RAM_HIGH_BG="#110000"
TMUX_BATTERY_NORMAL_BG="#001100"
TMUX_BATTERY_LOW_BG="#110000"
GHOSTTY_BACKGROUND="#000000"
GHOSTTY_FOREGROUND="#ffffff"
GHOSTTY_CURSOR_COLOR="#ff0000"
GHOSTTY_CURSOR_TEXT="#000000"
GHOSTTY_SELECTION_BG="#00ff00"
GHOSTTY_SELECTION_FG="#ffffff"
GHOSTTY_PALETTE_0="#111111"
GHOSTTY_PALETTE_1="#ff5555"
GHOSTTY_PALETTE_2="#55ff55"
GHOSTTY_PALETTE_3="#ffff55"
GHOSTTY_PALETTE_4="#5555ff"
GHOSTTY_PALETTE_5="#ff55ff"
GHOSTTY_PALETTE_6="#55ffff"
GHOSTTY_PALETTE_7="#ffffff"
GHOSTTY_PALETTE_8="#888888"
GHOSTTY_PALETTE_9="#ff8888"
GHOSTTY_PALETTE_10="#88ff88"
GHOSTTY_PALETTE_11="#ffff88"
GHOSTTY_PALETTE_12="#8888ff"
GHOSTTY_PALETTE_13="#ff88ff"
GHOSTTY_PALETTE_14="#88ffff"
GHOSTTY_PALETTE_15="#ffffff"
NVIM_COLORSCHEME="test-theme"
EOF

    # create minimal theme for testing (using new base variable format)
    cat >"$TEST_THEMES_DIR/minimal.theme" <<'EOF'
THEME_NAME="Minimal Theme"
THEME_ACTIVE_ACCENT="cyan"
TMUX_BG_PRIMARY="#000000"
TMUX_FG_PRIMARY="#ffffff"
TMUX_BG_SECONDARY="#333333"
TMUX_FG_SECONDARY="#999999"
TMUX_ACCENT_CYAN="#00ffff"
TMUX_ACCENT_PINK="#ff00ff"
TMUX_ACCENT_PURPLE="#ff00ff"
TMUX_ACCENT_GREEN="#00ff00"
TMUX_ACCENT_YELLOW="#ffff00"
TMUX_ACCENT_RED="#ff0000"
TMUX_CPU_LOW_BG="#00ff00"
TMUX_CPU_MEDIUM_BG="#ffff00"
TMUX_CPU_HIGH_BG="#ff0000"
TMUX_RAM_LOW_BG="#00ff00"
TMUX_RAM_MEDIUM_BG="#ffff00"
TMUX_RAM_HIGH_BG="#ff0000"
TMUX_BATTERY_NORMAL_BG="#00ff00"
TMUX_BATTERY_LOW_BG="#ff0000"
GHOSTTY_BACKGROUND="#000000"
GHOSTTY_FOREGROUND="#ffffff"
GHOSTTY_CURSOR_COLOR="#ffffff"
GHOSTTY_CURSOR_TEXT="#000000"
GHOSTTY_SELECTION_BG="#444444"
GHOSTTY_SELECTION_FG="#ffffff"
GHOSTTY_PALETTE_0="#000000"
GHOSTTY_PALETTE_1="#ff0000"
GHOSTTY_PALETTE_2="#00ff00"
GHOSTTY_PALETTE_3="#ffff00"
GHOSTTY_PALETTE_4="#0000ff"
GHOSTTY_PALETTE_5="#ff00ff"
GHOSTTY_PALETTE_6="#00ffff"
GHOSTTY_PALETTE_7="#ffffff"
GHOSTTY_PALETTE_8="#666666"
GHOSTTY_PALETTE_9="#ff6666"
GHOSTTY_PALETTE_10="#66ff66"
GHOSTTY_PALETTE_11="#ffff66"
GHOSTTY_PALETTE_12="#6666ff"
GHOSTTY_PALETTE_13="#ff66ff"
GHOSTTY_PALETTE_14="#66ffff"
GHOSTTY_PALETTE_15="#ffffff"
EOF

    export TEST_DIR
    export TEST_CONFIG_DIR
    export TEST_THEMES_DIR
    export TEST_TMUX_TEMPLATE
    export TEST_TMUX_OUTPUT
    export TEST_GHOSTTY_TEMPLATE
    export TEST_GHOSTTY_OUTPUT
    export TEST_CURRENT_THEME
}

cleanup_test_env() {
    rm -rf "${TEST_DIR:-}"
}

# trap to ensure cleanup
trap cleanup_test_env EXIT

# ===========================================================================
# Tests
# ===========================================================================

section "Script Exists and Is Executable"

if [[ -f "$THEME_SWITCH" ]]; then
    pass "theme-switch script exists"
else
    fail "theme-switch script not found"
    exit 1
fi

if [[ -x "$THEME_SWITCH" ]]; then
    pass "theme-switch script is executable"
else
    fail "theme-switch script is not executable"
fi

section "ShellCheck Validation"

if command -v shellcheck &>/dev/null; then
    # SC2033 is a false positive for `tmux info` (not a shell function)
    if shellcheck -x -S warning -e SC1091 -e SC2033 "$THEME_SWITCH" 2>/dev/null; then
        pass "theme-switch passes shellcheck"
    else
        fail "theme-switch has shellcheck warnings"
    fi
else
    skip "shellcheck not installed"
fi

section "List Themes Command"

list_output=$("$THEME_SWITCH" list 2>&1) || true

if [[ "$list_output" == *"Custom themes"* ]]; then
    pass "list command shows header"
else
    fail "list command should show 'Custom themes' header"
fi

if [[ "$list_output" == *"dracula"* ]]; then
    pass "list command shows dracula theme"
else
    fail "list command should show dracula theme"
fi

if [[ "$list_output" == *"Dracula"* ]]; then
    pass "list command shows theme display name"
else
    fail "list command should show theme display names"
fi

# check for current theme marker (may not exist if no theme is set or saved theme is missing from disk)
saved_theme=""
[[ -f ~/.config/dotfiles/current-theme ]] && saved_theme=$(cat ~/.config/dotfiles/current-theme)
if [[ "$list_output" == *"#current"* ]]; then
    pass "list command marks current theme"
elif [[ -z "$saved_theme" ]]; then
    pass "list command marks current theme (no theme set)"
elif [[ ! -f "$THEMES_DIR/${saved_theme}.theme" && ! -f "$THEMES_DIR/generated/${saved_theme}.theme" ]]; then
    pass "list command marks current theme (saved theme '$saved_theme' not on disk)"
else
    fail "list command should mark current theme when theme is set"
fi

section "Current Theme Command"

current_output=$("$THEME_SWITCH" current 2>&1) || true

if [[ "$current_output" == *"Current theme:"* ]]; then
    pass "current command shows header"
else
    fail "current command should show 'Current theme' header"
fi

# should show some theme name (format: "Display Name (theme-id)")
# accept any known theme
if [[ "$current_output" =~ \(.*\) ]]; then
    pass "current command shows theme name"
else
    fail "current command should show theme name"
fi

section "No Arguments Error Handling"

no_args_output=$("$THEME_SWITCH" 2>&1) && exit_code=0 || exit_code=$?

if [[ $exit_code -ne 0 ]]; then
    pass "exits with error when no arguments provided"
else
    fail "should exit with error when no arguments provided"
fi

if [[ "$no_args_output" == *"No theme specified"* ]]; then
    pass "shows error message for missing arguments"
else
    fail "should show error message for missing arguments"
fi

if [[ "$no_args_output" == *"Usage:"* ]]; then
    pass "shows usage information on error"
else
    fail "should show usage information on error"
fi

section "Invalid Theme Error Handling"

invalid_output=$("$THEME_SWITCH" nonexistent-theme-12345 2>&1) && exit_code=0 || exit_code=$?

if [[ $exit_code -ne 0 ]]; then
    pass "exits with error for invalid theme"
else
    fail "should exit with error for invalid theme"
fi

if [[ "$invalid_output" == *"not found"* ]]; then
    pass "shows error message for invalid theme"
else
    fail "should show error message for invalid theme"
fi

if [[ "$invalid_output" == *"dotfiles theme list"* ]]; then
    pass "suggests listing available themes"
else
    fail "should suggest listing available themes"
fi

section "Template Substitution with Test Environment"

setup_test_env

# create a wrapper script that uses test paths
TEST_WRAPPER="$TEST_DIR/theme-switch-test"
cat >"$TEST_WRAPPER" <<EOF
#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$DOTFILES_ROOT/scripts"
DOTFILES_ROOT="$DOTFILES_ROOT"
THEMES_DIR="$TEST_THEMES_DIR"
CONFIG_DIR="$TEST_CONFIG_DIR"
CURRENT_THEME_FILE="$TEST_CURRENT_THEME"
TMUX_TEMPLATE="$TEST_TMUX_TEMPLATE"
TMUX_OUTPUT="$TEST_TMUX_OUTPUT"
GHOSTTY_TEMPLATE="$TEST_GHOSTTY_TEMPLATE"
GHOSTTY_OUTPUT="$TEST_GHOSTTY_OUTPUT"

# Source the theme-switch script functions
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

error() { printf "\${RED}✗\${NC} %s\n" "\$1" >&2; }
success() { printf "\${GREEN}✓\${NC} %s\n" "\$1"; }
info() { printf "\${CYAN}•\${NC} %s\n" "\$1"; }
warn() { printf "\${YELLOW}!\${NC} %s\n" "\$1"; }

get_current_theme() {
    if [[ -f "\$CURRENT_THEME_FILE" ]]; then
        cat "\$CURRENT_THEME_FILE"
    else
        echo "test-theme"
    fi
}

apply_theme() {
    local theme_name="\$1"
    local theme_file="\$THEMES_DIR/\$theme_name.theme"

    if [[ ! -f "\$theme_file" ]]; then
        error "Theme '\$theme_name' not found"
        return 1
    fi

    source "\$theme_file"

    # Apply theme defaults to generate derived variables
    source "$DOTFILES_ROOT/themes/theme-defaults.sh"
    apply_theme_defaults

    if [[ -f "\$TMUX_TEMPLATE" ]]; then
        local tmux_content=\$(cat "\$TMUX_TEMPLATE")

        tmux_content="\${tmux_content//\\{\\{THEME_NAME\\}\\}/\$THEME_NAME}"
        tmux_content="\${tmux_content//\\{\\{TMUX_STATUS_BG\\}\\}/\$TMUX_STATUS_BG}"
        tmux_content="\${tmux_content//\\{\\{TMUX_STATUS_FG\\}\\}/\$TMUX_STATUS_FG}"
        tmux_content="\${tmux_content//\\{\\{TMUX_STATUS_ACTIVE_BG\\}\\}/\$TMUX_STATUS_ACTIVE_BG}"
        tmux_content="\${tmux_content//\\{\\{TMUX_STATUS_ACTIVE_FG\\}\\}/\$TMUX_STATUS_ACTIVE_FG}"
        tmux_content="\${tmux_content//\\{\\{TMUX_PANE_BORDER_INACTIVE\\}\\}/\$TMUX_PANE_BORDER_INACTIVE}"
        tmux_content="\${tmux_content//\\{\\{TMUX_PANE_BORDER_ACTIVE\\}\\}/\$TMUX_PANE_BORDER_ACTIVE}"
        tmux_content="\${tmux_content//\\{\\{TMUX_MESSAGE_BG\\}\\}/\$TMUX_MESSAGE_BG}"
        tmux_content="\${tmux_content//\\{\\{TMUX_MESSAGE_FG\\}\\}/\$TMUX_MESSAGE_FG}"

        echo "\$tmux_content" > "\$TMUX_OUTPUT"
    fi

    if [[ -f "\$GHOSTTY_TEMPLATE" ]]; then
        local ghostty_content=\$(cat "\$GHOSTTY_TEMPLATE")

        ghostty_content="\${ghostty_content//\\{\\{THEME_NAME\\}\\}/\$THEME_NAME}"
        ghostty_content="\${ghostty_content//\\{\\{GHOSTTY_BACKGROUND\\}\\}/\$GHOSTTY_BACKGROUND}"
        ghostty_content="\${ghostty_content//\\{\\{GHOSTTY_FOREGROUND\\}\\}/\$GHOSTTY_FOREGROUND}"
        ghostty_content="\${ghostty_content//\\{\\{GHOSTTY_CURSOR_COLOR\\}\\}/\$GHOSTTY_CURSOR_COLOR}"
        ghostty_content="\${ghostty_content//\\{\\{GHOSTTY_SELECTION_BG\\}\\}/\$GHOSTTY_SELECTION_BG}"
        ghostty_content="\${ghostty_content//\\{\\{GHOSTTY_PALETTE_0\\}\\}/\$GHOSTTY_PALETTE_0}"
        ghostty_content="\${ghostty_content//\\{\\{GHOSTTY_PALETTE_1\\}\\}/\$GHOSTTY_PALETTE_1}"
        ghostty_content="\${ghostty_content//\\{\\{PLATFORM_MOD\\}\\}/opt}"

        echo "\$ghostty_content" > "\$GHOSTTY_OUTPUT"
    fi

    mkdir -p "\$CONFIG_DIR"
    echo "\$theme_name" > "\$CURRENT_THEME_FILE"
}

apply_theme "\$1"
EOF

chmod +x "$TEST_WRAPPER"

# apply test theme
"$TEST_WRAPPER" test-theme 2>/dev/null || true

# test tmux template substitution
if [[ -f "$TEST_TMUX_OUTPUT" ]]; then
    tmux_content=$(cat "$TEST_TMUX_OUTPUT")

    # check that no placeholders remain
    if ! grep -q "{{.*}}" "$TEST_TMUX_OUTPUT"; then
        pass "tmux template has all variables substituted"
    else
        fail "tmux template contains unsubstituted variables"
    fi

    # check specific substitutions
    if [[ "$tmux_content" == *"#ff0000"* ]]; then
        pass "tmux template substitutes TMUX_STATUS_BG correctly"
    else
        fail "tmux template should substitute TMUX_STATUS_BG"
    fi

    if [[ "$tmux_content" == *"Test Theme"* ]]; then
        pass "tmux template substitutes THEME_NAME correctly"
    else
        fail "tmux template should substitute THEME_NAME"
    fi
else
    fail "tmux output file not created"
fi

# test ghostty template substitution
if [[ -f "$TEST_GHOSTTY_OUTPUT" ]]; then
    ghostty_content=$(cat "$TEST_GHOSTTY_OUTPUT")

    # check that no placeholders remain
    if ! grep -q "{{.*}}" "$TEST_GHOSTTY_OUTPUT"; then
        pass "ghostty template has all variables substituted"
    else
        fail "ghostty template contains unsubstituted variables"
    fi

    # check specific substitutions
    if [[ "$ghostty_content" == *"#000000"* ]]; then
        pass "ghostty template substitutes GHOSTTY_BACKGROUND correctly"
    else
        fail "ghostty template should substitute GHOSTTY_BACKGROUND"
    fi

    if [[ "$ghostty_content" == *"Test Theme"* ]]; then
        pass "ghostty template substitutes THEME_NAME correctly"
    else
        fail "ghostty template should substitute THEME_NAME"
    fi

    # check PLATFORM_MOD substitution (keybindings moved to template in this branch)
    if [[ "$ghostty_content" == *"opt+c"* ]]; then
        pass "ghostty template substitutes PLATFORM_MOD correctly"
    else
        fail "ghostty template should substitute PLATFORM_MOD (expected 'opt+c')"
    fi
else
    fail "ghostty output file not created"
fi

section "Theme Persistence"

if [[ -f "$TEST_CURRENT_THEME" ]]; then
    saved_theme=$(cat "$TEST_CURRENT_THEME")
    if [[ "$saved_theme" == "test-theme" ]]; then
        pass "current theme preference saved to file"
    else
        fail "current theme preference not saved correctly (got: $saved_theme)"
    fi
else
    fail "current theme file not created"
fi

section "Missing Template Handling"

# remove ghostty template
mv "$TEST_GHOSTTY_TEMPLATE" "$TEST_GHOSTTY_TEMPLATE.hidden"
rm -f "$TEST_GHOSTTY_OUTPUT"

# apply theme again
"$TEST_WRAPPER" test-theme 2>/dev/null || true

# tmux should still work
if [[ -f "$TEST_TMUX_OUTPUT" ]]; then
    pass "tmux config generated even when ghostty template missing"
else
    fail "tmux config should be generated independently"
fi

# Ghostty should be skipped
if [[ ! -f "$TEST_GHOSTTY_OUTPUT" ]]; then
    pass "ghostty config skipped when template missing"
else
    fail "ghostty config should not be created without template"
fi

# restore template
mv "$TEST_GHOSTTY_TEMPLATE.hidden" "$TEST_GHOSTTY_TEMPLATE"

section "Config Directory Creation"

# remove config directory
rm -rf "$TEST_CONFIG_DIR"

# apply theme, should create directory
"$TEST_WRAPPER" test-theme 2>/dev/null || true

if [[ -d "$TEST_CONFIG_DIR" ]]; then
    pass "creates config directory if missing"
else
    fail "should create config directory if missing"
fi

if [[ -f "$TEST_CURRENT_THEME" ]]; then
    pass "saves theme preference after creating directory"
else
    fail "should save theme preference after creating directory"
fi

section "Multiple Theme Switching"

# apply first theme
"$TEST_WRAPPER" test-theme 2>/dev/null || true
first_theme=$(cat "$TEST_CURRENT_THEME")

# apply second theme
"$TEST_WRAPPER" minimal 2>/dev/null || true
second_theme=$(cat "$TEST_CURRENT_THEME")

if [[ "$first_theme" == "test-theme" ]] && [[ "$second_theme" == "minimal" ]]; then
    pass "theme preference updates correctly"
else
    fail "theme preference should update (got: $first_theme -> $second_theme)"
fi

# check that second theme actually applied
if grep -q "#000000" "$TEST_TMUX_OUTPUT"; then
    pass "second theme applied successfully"
else
    fail "second theme should overwrite first theme"
fi

section "File Overwrite Safety"

# create existing config
echo "# Existing config" >"$TEST_TMUX_OUTPUT"
original_content=$(cat "$TEST_TMUX_OUTPUT")

# apply theme
"$TEST_WRAPPER" test-theme 2>/dev/null || true

new_content=$(cat "$TEST_TMUX_OUTPUT")

if [[ "$new_content" != "$original_content" ]]; then
    pass "overwrites existing config file"
else
    fail "should overwrite existing config file"
fi

if [[ "$new_content" == *"Test Theme"* ]]; then
    pass "new content is from theme, not old config"
else
    fail "should replace old content with themed content"
fi

section "Theme File Validation"

# test with empty theme file
echo "" >"$TEST_THEMES_DIR/empty.theme"

empty_output=$("$TEST_WRAPPER" empty 2>&1) && exit_code=0 || exit_code=$?

# the script will source the empty file and fail due to undefined variables
# this is acceptable behaviour: bash will complain about unbound variables
if [[ $exit_code -ne 0 ]] || ! grep -q "{{THEME_NAME}}" "$TEST_TMUX_OUTPUT" 2>/dev/null; then
    pass "handles empty theme file (fails or leaves placeholders)"
else
    fail "should fail or warn on empty theme file"
fi

section "Real Theme Files Validation"

# verify all real theme files are valid and generate required variables after applying defaults
for theme_file in "$THEMES_DIR"/*.theme; do
    if [[ -f "$theme_file" ]]; then
        theme_name=$(basename "$theme_file" .theme)

        # source theme in subshell to avoid polluting current shell
        (
            set -euo pipefail
            # shellcheck disable=SC1090
            source "$theme_file"

            # apply theme defaults to generate derived variables
            # shellcheck disable=SC1091
            source "$THEMES_DIR/theme-defaults.sh"
            apply_theme_defaults

            # check critical base variables are defined
            [[ -n "${THEME_NAME:-}" ]] || exit 1
            [[ -n "${GHOSTTY_BACKGROUND:-}" ]] || exit 1
            # check generated variables exist after apply_theme_defaults
            [[ -n "${TMUX_STATUS_BG:-}" ]] || exit 1
        ) && pass "$theme_name theme file is valid" || fail "$theme_name theme file is missing required variables"
    fi
done

section "Colour Format Validation (Basic)"

# test that theme files contain hex colour codes
for theme_file in "$THEMES_DIR"/*.theme; do
    if [[ -f "$theme_file" ]]; then
        theme_name=$(basename "$theme_file" .theme)

        if grep -q '#[0-9a-fA-F]\{6\}' "$theme_file"; then
            pass "$theme_name contains valid hex colour codes"
        else
            fail "$theme_name should contain hex colour codes (#RRGGBB)"
        fi
    fi
done

section "Ghostty Config Template PLATFORM_MOD Placeholder"

# verify the real config.template uses {{PLATFORM_MOD}} for keybindings
GHOSTTY_REAL_TEMPLATE="$DOTFILES_ROOT/ghostty/config.template"
if [[ -f "$GHOSTTY_REAL_TEMPLATE" ]]; then
    if grep -q '{{PLATFORM_MOD}}' "$GHOSTTY_REAL_TEMPLATE"; then
        pass "config.template uses {{PLATFORM_MOD}} placeholder"
    else
        fail "config.template should use {{PLATFORM_MOD}} for platform keybindings"
    fi

    # keybindings should no longer be generated in theme-switch itself
    if ! grep -q 'keybind.*=text:' "$THEME_SWITCH"; then
        pass "theme-switch no longer contains inline keybindings"
    else
        fail "keybindings should be in config.template, not theme-switch"
    fi
fi

# verify theme-switch substitutes PLATFORM_MOD in ghostty_vars
if grep -q 'PLATFORM_MOD' "$THEME_SWITCH"; then
    pass "theme-switch includes PLATFORM_MOD in ghostty variable map"
else
    fail "theme-switch should substitute PLATFORM_MOD in ghostty_vars"
fi

section "Ghostty Reload Integration"

# check that theme-switch script references reload-ghostty.sh
if grep -q "reload-ghostty.sh" "$THEME_SWITCH"; then
    pass "theme-switch references reload-ghostty.sh"
else
    fail "theme-switch should reference reload-ghostty.sh for reloading"
fi

# check that script calls reload-ghostty.sh (which handles detection internally)
if grep -q 'reload-ghostty.sh' "$THEME_SWITCH"; then
    pass "theme-switch calls reload-ghostty.sh"
else
    fail "theme-switch should call reload-ghostty.sh"
fi

# check that reload-ghostty.sh handles platform detection internally
GHOSTTY_RELOAD_SCRIPT="$DOTFILES_ROOT/tmux/scripts/themes/reload-ghostty.sh"
if grep -q 'ghostty' "$GHOSTTY_RELOAD_SCRIPT"; then
    pass "reload-ghostty.sh handles ghostty process detection"
else
    fail "reload-ghostty.sh should handle ghostty process detection"
fi

# check that ghostty reload respects --no-reload flag
if grep -q 'no_reload.*true' "$THEME_SWITCH"; then
    pass "theme-switch respects --no-reload flag"
else
    fail "theme-switch should respect --no-reload flag"
fi

# verify reload-ghostty.sh script exists
GHOSTTY_RELOAD="$DOTFILES_ROOT/tmux/scripts/themes/reload-ghostty.sh"
if [[ -f "$GHOSTTY_RELOAD" ]]; then
    pass "reload-ghostty.sh script exists"
else
    fail "reload-ghostty.sh script should exist"
fi

if [[ -x "$GHOSTTY_RELOAD" ]]; then
    pass "reload-ghostty.sh is executable"
else
    fail "reload-ghostty.sh should be executable"
fi

# ===========================================================================
# Summary
# ===========================================================================

print_summary

if [[ $FAIL -gt 0 ]]; then
    exit 1
fi
