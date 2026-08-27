#!/usr/bin/env bash
set -euo pipefail

# unit tests for theme generation during installation
# tests that create-symlinks.sh properly generates themed configs

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOTFILES_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
CREATE_SYMLINKS="$DOTFILES_ROOT/scripts/install/create-symlinks.sh"
THEME_SWITCH="$DOTFILES_ROOT/scripts/theme-switch"

# source shared test helpers (colours, pass/fail/skip/section, assertions)
source "$SCRIPT_DIR/_test-helpers.sh"

# ===========================================================================
# tests
# ===========================================================================

section "Script Prerequisite Checks"

if [[ -f "$CREATE_SYMLINKS" ]]; then
    pass "create-symlinks.sh exists"
else
    fail "create-symlinks.sh not found"
    exit 1
fi

if [[ -x "$CREATE_SYMLINKS" ]]; then
    pass "create-symlinks.sh is executable"
else
    fail "create-symlinks.sh is not executable"
fi

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

section "Create Symlinks Integration"

create_symlinks_content=$(cat "$CREATE_SYMLINKS")

if [[ "$create_symlinks_content" == *"themed configurations"* ]]; then
    pass "create-symlinks mentions themed configurations"
else
    fail "create-symlinks should mention themed configurations"
fi

if [[ "$create_symlinks_content" == *"theme-switch"* ]]; then
    pass "create-symlinks calls theme-switch script"
else
    fail "create-symlinks should call theme-switch script"
fi

if [[ "$create_symlinks_content" == *"Generating themed configurations"* ]]; then
    pass "create-symlinks has themed config generation step"
else
    fail "create-symlinks should have themed config generation step"
fi

section "Default Theme Fallback"

if [[ "$create_symlinks_content" == *"dracula"* ]]; then
    pass "create-symlinks defaults to dracula theme"
else
    fail "create-symlinks should default to dracula theme"
fi

if [[ "$create_symlinks_content" == *"current-theme"* ]]; then
    pass "create-symlinks checks for saved theme preference"
else
    fail "create-symlinks should check for saved theme preference"
fi

section "Error Handling"

# the theme-switch invocations themselves must be quiet, so anchor to those
# lines rather than searching the whole file for a redirect used elsewhere
theme_switch_calls=$(printf '%s\n' "$create_symlinks_content" |
    grep -E '^[[:space:]]*"\$DOTFILES_DIR/scripts/theme-switch"' || true)
if [[ -n "$theme_switch_calls" ]] &&
    ! printf '%s\n' "$theme_switch_calls" | grep -qvE -- '--quiet|>/dev/null|2>/dev/null'; then
    pass "create-symlinks suppresses theme-switch output"
else
    fail "create-symlinks should suppress theme-switch output"
fi

# check for fallback on theme application failure
if echo "$create_symlinks_content" | grep -A5 "theme-switch" | grep -q "warn"; then
    pass "create-symlinks warns on theme application failure"
else
    fail "create-symlinks should warn on theme application failure"
fi

if echo "$create_symlinks_content" | grep -A10 "theme-switch" | grep -q "dracula"; then
    pass "create-symlinks falls back to dracula on failure"
else
    fail "create-symlinks should fall back to dracula on failure"
fi

section "Template Files Existence"

tmux_template="$DOTFILES_ROOT/tmux/tmux.conf.template"
ghostty_template="$DOTFILES_ROOT/ghostty/config.template"

if [[ -f "$tmux_template" ]]; then
    pass "tmux template file exists"
else
    fail "tmux template file should exist at $tmux_template"
fi

if [[ -f "$ghostty_template" ]]; then
    pass "ghostty template file exists"
else
    fail "ghostty template file should exist at $ghostty_template"
fi

section "Template File Structure"

if [[ -f "$tmux_template" ]]; then
    tmux_template_content=$(cat "$tmux_template")

    if [[ "$tmux_template_content" == *"{{TMUX_STATUS_BG}}"* ]]; then
        pass "tmux template contains TMUX_STATUS_BG placeholder"
    else
        fail "tmux template should contain TMUX_STATUS_BG placeholder"
    fi

    if [[ "$tmux_template_content" == *"{{TMUX_PANE_BORDER_ACTIVE}}"* ]]; then
        pass "tmux template contains TMUX_PANE_BORDER_ACTIVE placeholder"
    else
        fail "tmux template should contain TMUX_PANE_BORDER_ACTIVE placeholder"
    fi

    # count placeholders, tmux template has many theme variables
    placeholder_count=$(grep -oE "{{[A-Z_]+}}" "$tmux_template" | wc -l | tr -d ' ')
    if [[ $placeholder_count -gt 5 ]]; then
        pass "tmux template has multiple placeholders ($placeholder_count found)"
    else
        fail "tmux template should have multiple placeholders (only $placeholder_count found)"
    fi
else
    skip "tmux template file checks (file missing)"
fi

if [[ -f "$ghostty_template" ]]; then
    ghostty_template_content=$(cat "$ghostty_template")

    if [[ "$ghostty_template_content" == *"{{THEME_NAME}}"* ]]; then
        pass "ghostty template contains THEME_NAME placeholder"
    else
        fail "ghostty template should contain THEME_NAME placeholder"
    fi

    if [[ "$ghostty_template_content" == *"{{GHOSTTY_BACKGROUND}}"* ]]; then
        pass "ghostty template contains GHOSTTY_BACKGROUND placeholder"
    else
        fail "ghostty template should contain GHOSTTY_BACKGROUND placeholder"
    fi

    # count placeholders, ghostty has fewer theme variables than tmux
    placeholder_count=$(grep -oE "{{[A-Z_]+}}" "$ghostty_template" | wc -l | tr -d ' ')
    if [[ $placeholder_count -gt 3 ]]; then
        pass "ghostty template has multiple placeholders ($placeholder_count found)"
    else
        fail "ghostty template should have multiple placeholders (only $placeholder_count found)"
    fi
else
    skip "ghostty template file checks (file missing)"
fi

section "Generated Config Files Should Not Contain Placeholders"

# check the actual generated files (if they exist)
tmux_output="${XDG_CONFIG_HOME:-$HOME/.config}/tmux/tmux.conf"
ghostty_output_macos="$HOME/Library/Application Support/com.mitchellh.ghostty/config"
ghostty_output_linux="$HOME/.config/ghostty/config"

if [[ -f "$tmux_output" ]]; then
    if ! grep -q "{{.*}}" "$tmux_output"; then
        pass "generated tmux config has no unrendered placeholders"
    else
        fail "generated tmux config should not contain placeholders"
    fi
else
    skip "generated tmux config check (file not generated yet)"
fi

if [[ -f "$ghostty_output_macos" ]]; then
    if ! grep -q "{{.*}}" "$ghostty_output_macos"; then
        pass "generated ghostty config has no unrendered placeholders (macOS)"
    else
        fail "generated ghostty config should not contain placeholders (macOS)"
    fi
elif [[ -f "$ghostty_output_linux" ]]; then
    if ! grep -q "{{.*}}" "$ghostty_output_linux"; then
        pass "generated ghostty config has no unrendered placeholders (Linux)"
    else
        fail "generated ghostty config should not contain placeholders (Linux)"
    fi
else
    skip "generated ghostty config check (file not generated yet)"
fi

section "Theme Preference Persistence"

config_dir="${XDG_CONFIG_HOME:-$HOME/.config}/dotfiles"
current_theme_file="$config_dir/current-theme"

if [[ -f "$current_theme_file" ]]; then
    saved_theme=$(cat "$current_theme_file")
    pass "theme preference file exists (current: $saved_theme)"

    # verify it's a valid theme (hand-crafted or generated)
    themes_dir="$DOTFILES_ROOT/themes"
    theme_file="$themes_dir/$saved_theme.theme"
    generated_theme_file="$themes_dir/generated/$saved_theme.theme"

    if [[ -f "$theme_file" ]]; then
        pass "saved theme ($saved_theme) is valid (custom)"
    elif [[ -f "$generated_theme_file" ]]; then
        pass "saved theme ($saved_theme) is valid (generated)"
    else
        skip "saved theme ($saved_theme) not on disk (may need regeneration)"
    fi
else
    skip "theme preference file check (not set yet)"
fi

section "Theme Files Complete Variable Set"

# test that all theme files define base variables (not generated ones)
# generated variables (TMUX_STATUS_BG, TMUX_PANE_BORDER_ACTIVE, etc.) are created by apply_theme_defaults()
themes_dir="$DOTFILES_ROOT/themes"
base_required_vars=(
    "THEME_NAME"
    "TMUX_BG_PRIMARY"
    "TMUX_FG_PRIMARY"
    "GHOSTTY_BACKGROUND"
    "GHOSTTY_FOREGROUND"
)

for theme_file in "$themes_dir"/*.theme; do
    if [[ -f "$theme_file" ]]; then
        theme_name=$(basename "$theme_file" .theme)

        # check that all base variables are defined in the theme file
        all_defined=true
        for var in "${base_required_vars[@]}"; do
            if ! grep -q "^$var=" "$theme_file"; then
                all_defined=false
                break
            fi
        done

        if $all_defined; then
            # also verify that apply_theme_defaults generates derived variables
            (
                # shellcheck disable=SC1090
                source "$theme_file"
                # shellcheck disable=SC1091
                source "$themes_dir/theme-defaults.sh"
                apply_theme_defaults

                # check generated variables exist
                [[ -n "${TMUX_STATUS_BG:-}" ]] &&
                    [[ -n "${TMUX_STATUS_FG:-}" ]] &&
                    [[ -n "${TMUX_PANE_BORDER_ACTIVE:-}" ]]
            ) && pass "$theme_name defines all required variables" || fail "$theme_name should define all required variables"
        else
            fail "$theme_name should define all required variables"
        fi
    fi
done

section "Installation Integration - Live Test"

echo ""
echo "NOTE: The following tests would require running the actual installer,"
echo "which could modify the system. These are structural checks only."
echo ""

# check that installer script calls create-symlinks
install_script="$DOTFILES_ROOT/install.sh"
if [[ -f "$install_script" ]]; then
    install_content=$(cat "$install_script")

    if [[ "$install_content" == *"create-symlinks.sh"* ]]; then
        pass "install.sh calls create-symlinks.sh"
    else
        fail "install.sh should call create-symlinks.sh"
    fi
else
    skip "install.sh check (file not found)"
fi

section "Documentation"

# check that README or installation docs mention themes
readme="$DOTFILES_ROOT/README.md"
claude_md="$DOTFILES_ROOT/CLAUDE.md"

doc_mentions_themes=false

if [[ -f "$readme" ]]; then
    if grep -qi "theme" "$readme"; then
        pass "README.md mentions themes"
        doc_mentions_themes=true
    fi
fi

if [[ -f "$claude_md" ]]; then
    if grep -qi "theme" "$claude_md"; then
        pass "CLAUDE.md mentions themes"
        doc_mentions_themes=true
    fi
fi

if ! $doc_mentions_themes; then
    skip "theme documentation check (not documented yet)"
fi

# ===========================================================================
# summary
# ===========================================================================

print_summary

if [[ $FAIL -gt 0 ]]; then
    exit 1
fi
