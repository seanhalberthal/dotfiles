#!/usr/bin/env bash
# shellcheck disable=SC2030,SC2031
set -euo pipefail

# tests for Linux compatibility of installation and configuration scripts
# verifies that platform-specific code paths work correctly

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOTFILES_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# source shared test helpers (colours, pass/fail/skip/section, assertions)
source "$SCRIPT_DIR/_test-helpers.sh"

# source common.sh for platform helpers
# shellcheck source=scripts/_lib/common.sh
source "$DOTFILES_ROOT/scripts/_lib/common.sh"

# temp file cleanup on exit
_TEST_TMPFILES=()
_TEST_TMPDIRS=()
trap 'rm -f "${_TEST_TMPFILES[@]}"; [[ ${#_TEST_TMPDIRS[@]} -gt 0 ]] && rm -rf "${_TEST_TMPDIRS[@]}"' EXIT

# ===========================================================================
# Tests
# ===========================================================================

section "sed_inplace Helper"

# test that sed_inplace function exists
if declare -f sed_inplace &>/dev/null; then
    pass "sed_inplace function is defined"
else
    fail "sed_inplace function should be defined in common.sh"
fi

# test sed_inplace works for simple substitution
test_file=$(mktemp)
_TEST_TMPFILES+=("$test_file")
echo "hello world" >"$test_file"
sed_inplace "s/hello/goodbye/" "$test_file"
result=$(cat "$test_file")
if [[ "$result" == "goodbye world" ]]; then
    pass "sed_inplace performs simple substitution"
else
    fail "sed_inplace substitution failed (got: '$result')"
fi

# test sed_inplace works for in-place replacement (no leftover backup files)
test_file2=$(mktemp)
_TEST_TMPFILES+=("$test_file2")
echo "foo bar" >"$test_file2"
sed_inplace "s/foo/baz/" "$test_file2"
# check no backup files exist (BSD sed creates file-e or file.bak patterns)
backup_files=$(find "$(dirname "$test_file2")" -name "$(basename "$test_file2")*" ! -name "$(basename "$test_file2")" 2>/dev/null || true)
if [[ -z "$backup_files" ]]; then
    pass "sed_inplace does not leave backup files"
else
    fail "sed_inplace left backup files behind: $backup_files"
fi

# test sed_inplace with append command (used by update_zshrc_export)
test_file3=$(mktemp)
_TEST_TMPFILES+=("$test_file3")
cat >"$test_file3" <<'EOF'
line1
line2
line3
EOF
sed_inplace "2a\\
inserted" "$test_file3"
if grep -q "inserted" "$test_file3"; then
    pass "sed_inplace append command works"
else
    fail "sed_inplace append command failed"
fi

# temp files cleaned up by EXIT trap

section "update_zshrc_export (Portable sed)"

# test that update_zshrc_export works on current platform
# the function reads $HOME/.zshrc, so we use a sandbox with fake HOME
setup_sandbox
cat >"$HOME/.zshrc" <<'EOF'
# YOUR PERSONAL CONFIGURATION
# Add your settings below

export EXISTING_VAR="old_value"
EOF

# test updating existing variable
update_zshrc_export "EXISTING_VAR" "new_value"
if grep -q 'export EXISTING_VAR="new_value"' "$HOME/.zshrc"; then
    pass "update_zshrc_export updates existing variable"
else
    fail "update_zshrc_export should update existing variable"
fi

# test adding new variable
update_zshrc_export "NEW_VAR" "test_value"
if grep -q 'export NEW_VAR="test_value"' "$HOME/.zshrc"; then
    pass "update_zshrc_export adds new variable"
else
    fail "update_zshrc_export should add new variable"
fi

cleanup_sandbox

section "Ghostty Config Template"

# verify template uses {{PLATFORM_CONFIG}} placeholder
if grep -q '{{PLATFORM_CONFIG}}' "$DOTFILES_ROOT/ghostty/config.template"; then
    pass "ghostty template uses PLATFORM_CONFIG placeholder"
else
    fail "ghostty template should use {{PLATFORM_CONFIG}} placeholder"
fi

# verify template does NOT contain hardcoded macOS-only options
if ! grep -q 'macos-icon' "$DOTFILES_ROOT/ghostty/config.template"; then
    pass "ghostty template has no hardcoded macos-icon"
else
    fail "ghostty template should not contain hardcoded macos-icon (use PLATFORM_CONFIG)"
fi

if ! grep -q 'macos-option-as-alt' "$DOTFILES_ROOT/ghostty/config.template"; then
    pass "ghostty template has no hardcoded macos-option-as-alt"
else
    fail "ghostty template should not contain hardcoded macos-option-as-alt"
fi

# verify template does NOT contain hardcoded opt+ keybindings
if ! grep -q 'keybind = opt+' "$DOTFILES_ROOT/ghostty/config.template"; then
    pass "ghostty template has no hardcoded opt+ keybindings"
else
    fail "ghostty template should not contain hardcoded opt+ keybindings"
fi

section "Tmux Config Template Clipboard"

# verify tmux template uses {{CLIPBOARD_CMD}} placeholder
if grep -q '{{CLIPBOARD_CMD}}' "$DOTFILES_ROOT/tmux/tmux.conf.template"; then
    pass "tmux template uses CLIPBOARD_CMD placeholder"
else
    fail "tmux template should use {{CLIPBOARD_CMD}} placeholder"
fi

# verify tmux template does NOT contain hardcoded pbcopy
if ! grep -q '"pbcopy"' "$DOTFILES_ROOT/tmux/tmux.conf.template"; then
    pass "tmux template has no hardcoded pbcopy"
else
    fail "tmux template should not contain hardcoded pbcopy"
fi

section "Theme-Switch Platform Handling"

THEME_SWITCH="$DOTFILES_ROOT/scripts/theme-switch"

# verify theme-switch handles PLATFORM_CONFIG
if grep -q 'PLATFORM_CONFIG' "$THEME_SWITCH"; then
    pass "theme-switch handles PLATFORM_CONFIG substitution"
else
    fail "theme-switch should handle PLATFORM_CONFIG substitution"
fi

# verify theme-switch has both macOS and Linux modifier keys
if grep -q 'mod="opt"' "$THEME_SWITCH" && grep -q 'mod="alt"' "$THEME_SWITCH"; then
    pass "theme-switch has both macOS (opt) and Linux (alt) modifier keys"
else
    fail "theme-switch should have both opt and alt modifier key variants"
fi

# verify theme-switch includes macOS-only options in macOS block only
if grep -q 'macos-icon' "$THEME_SWITCH"; then
    pass "theme-switch includes macos-icon in platform config"
else
    fail "theme-switch should include macos-icon in macOS platform block"
fi

# verify theme-switch handles CLIPBOARD_CMD
if grep -q 'CLIPBOARD_CMD' "$THEME_SWITCH"; then
    pass "theme-switch handles CLIPBOARD_CMD substitution"
else
    fail "theme-switch should handle CLIPBOARD_CMD substitution"
fi

# verify theme-switch resolves the clipboard command via the shared lib rather
# than carrying its own detection, so it cannot drift from the tmux scripts
if grep -q '_lib/clipboard.sh' "$THEME_SWITCH" && grep -q 'clipboard_copy_cmd' "$THEME_SWITCH"; then
    pass "theme-switch resolves clipboard via the shared lib"
else
    fail "theme-switch should source _lib/clipboard.sh and call clipboard_copy_cmd"
fi

# the detection itself must live in one place only
if ! grep -qE '^\s*(elif )?(command_exists|command -v) (wl-copy|xclip|xsel)' "$THEME_SWITCH"; then
    pass "theme-switch has no duplicate clipboard detection"
else
    fail "theme-switch should not re-implement clipboard detection"
fi

section "Generate-Theme Ghostty Path Fallbacks"

GENERATE_THEME="$DOTFILES_ROOT/scripts/generate-theme"

# verify generate-theme searches multiple Linux paths
if grep -q '/usr/share/ghostty/themes' "$GENERATE_THEME" &&
    grep -q '/usr/local/share/ghostty/themes' "$GENERATE_THEME" &&
    grep -q '.local/share/ghostty/themes' "$GENERATE_THEME"; then
    pass "generate-theme searches multiple Linux Ghostty theme paths"
else
    fail "generate-theme should search multiple Linux paths for Ghostty themes"
fi

# verify generate-theme has a fallback when no path is found
if grep -q 'find_ghostty_themes' "$GENERATE_THEME"; then
    pass "generate-theme uses find_ghostty_themes function"
else
    fail "generate-theme should use find_ghostty_themes for path discovery"
fi

section "Install Script Linux Compatibility"

# verify install-packages.sh has distro-specific Ghostty handling
INSTALL_PACKAGES="$DOTFILES_ROOT/scripts/install/install-packages.sh"
if grep -q 'pacman' "$INSTALL_PACKAGES" &&
    grep -q 'apt-get' "$INSTALL_PACKAGES" &&
    grep -q 'dnf' "$INSTALL_PACKAGES"; then
    pass "install-packages.sh handles multiple Linux distros for Ghostty"
else
    fail "install-packages.sh should handle pacman, apt-get, and dnf for Ghostty"
fi

# verify no remaining sed -i '' calls outside of sed_inplace (exclude common.sh and this test file)
# scans both scripts/ (installer) and tmux/scripts/ (tmux tooling has its own
# sed_inplace in tmux/scripts/_lib/common.sh)
other_sed_files=$(grep -rl "sed -i ''" "$DOTFILES_ROOT/scripts/" "$DOTFILES_ROOT/tmux/scripts/" 2>/dev/null |
    grep -v '_lib/common.sh' | grep -v 'test-linux-compat.sh' || true)
if [[ -z "$other_sed_files" ]]; then
    pass "no sed -i '' calls outside of sed_inplace helper"
else
    fail "found sed -i '' calls outside of sed_inplace: $other_sed_files"
fi

section "Clipboard Detection (Functional)"

# exercise the real shared lib rather than an inlined copy of its logic, so the
# test cannot silently drift from the implementation it is meant to pin.
# fakes a Linux PATH containing only the named tools.
# usage: clipboard_test "<tools>" "<WAYLAND_DISPLAY>" "<DISPLAY>"
_CLIP_FAKE_BIN="$(mktemp -d)"
_TEST_TMPDIRS+=("$_CLIP_FAKE_BIN")
_clipboard_call() {
    local fn="$1" available_cmds="$2" wayland="${3:-}" x11="${4:-}"
    local bin="$_CLIP_FAKE_BIN"

    rm -f "${bin:?}"/*
    printf '#!/bin/sh\necho Linux\n' >"$bin/uname"
    local c
    for c in $available_cmds; do
        printf '#!/bin/sh\nexit 0\n' >"$bin/$c"
    done
    chmod +x "$bin"/*

    (
        # PATH is set last: rm/chmod above still need the real one
        export PATH="$bin" WAYLAND_DISPLAY="$wayland" DISPLAY="$x11"
        unset _DOTFILES_CLIPBOARD_SH_LOADED
        # shellcheck source=scripts/_lib/clipboard.sh
        source "$DOTFILES_ROOT/scripts/_lib/clipboard.sh"
        "$fn"
    )
}

clipboard_test() { _clipboard_call clipboard_copy_cmd "$@"; }
clipboard_backend_test() { _clipboard_call clipboard_backend "$@"; }

# display server decides, not mere binary presence: a wayland session with xclip
# installed (via XWayland) must still pick wl-copy
result=$(clipboard_test "wl-copy xclip xsel" "wayland-0" "")
assert_equals "prefers wl-copy on a wayland session" "wl-copy" "$result"

result=$(clipboard_test "wl-copy xclip xsel" "wayland-0" ":0")
assert_equals "prefers wl-copy when both display servers are set" "wl-copy" "$result"

result=$(clipboard_test "wl-copy xclip xsel" "" ":0")
assert_equals "prefers xclip on an X11 session" "xclip -selection clipboard" "$result"

result=$(clipboard_test "xsel" "" ":0")
assert_equals "falls back to xsel when no xclip" "xsel --clipboard --input" "$result"

# wl-copy present but no wayland session (and no X11): it would fail if chosen
result=$(clipboard_test "wl-copy xclip xsel" "" "")
assert_equals "ignores display tools when headless" "cat >/dev/null" "$result"

result=$(clipboard_test "" "" "")
assert_equals "discards when no clipboard tool is found" "cat >/dev/null" "$result"

# a running display server with no tool installed must NOT be treated as
# headless: falling through to OSC 52 there would silently push the payload out
# through the terminal (and any ssh hop) when a local clipboard was expected
result=$(clipboard_backend_test "" "wayland-0" "")
assert_equals "wayland session with no tool reports missing, not osc52" "missing" "$result"

result=$(clipboard_backend_test "" "" ":0")
assert_equals "X11 session with no tool reports missing, not osc52" "missing" "$result"

result=$(clipboard_backend_test "" "" "")
assert_equals "genuinely headless reports osc52" "osc52" "$result"

result=$(clipboard_backend_test "wl-copy" "wayland-0" "")
assert_equals "wayland session with wl-copy reports wayland" "wayland" "$result"

section "find_ghostty_themes Fallback (Functional)"

# test fallback when no directories exist
# (can't source generate-theme directly as it runs main, so replicate the function)
result=$(
    is_macos() { return 1; }
    HOME="/nonexistent"
    find_ghostty_themes() {
        if is_macos; then
            echo "/Applications/Ghostty.app/Contents/Resources/ghostty/themes"
            return
        fi
        local paths=(
            "/usr/share/ghostty/themes"
            "/usr/local/share/ghostty/themes"
            "$HOME/.local/share/ghostty/themes"
        )
        for p in "${paths[@]}"; do
            if [[ -d "$p" ]]; then
                echo "$p"
                return
            fi
        done
        echo "/usr/share/ghostty/themes"
    }
    find_ghostty_themes
)
if [[ "$result" == "/usr/share/ghostty/themes" ]]; then
    pass "find_ghostty_themes falls back to /usr/share/ghostty/themes"
else
    fail "find_ghostty_themes fallback returned: $result"
fi

section "update_zshrc_export Edge Cases"

# test with path containing slashes
setup_sandbox
cat >"$HOME/.zshrc" <<'EOF'
# YOUR PERSONAL CONFIGURATION
EOF
update_zshrc_export "DEV_ROOT" "/home/user/dev/projects"
if grep -q 'export DEV_ROOT="/home/user/dev/projects"' "$HOME/.zshrc"; then
    pass "update_zshrc_export handles paths with slashes"
else
    fail "update_zshrc_export should handle paths with slashes"
fi

# backslashes survive the sed a\ append branch, which consumes them unescaped
setup_sandbox
cat >"$HOME/.zshrc" <<'EOF'
# YOUR PERSONAL CONFIGURATION
EOF
update_zshrc_export "DEV_ROOT" '/home/user/a\b'
if grep -qF 'export DEV_ROOT="/home/user/a\b"' "$HOME/.zshrc"; then
    pass "update_zshrc_export preserves backslashes on first write"
else
    fail "update_zshrc_export dropped a backslash: $(grep '^export DEV_ROOT=' "$HOME/.zshrc")"
fi

# test with no marker in .zshrc
cleanup_sandbox
setup_sandbox
echo "# Plain zshrc with no marker" >"$HOME/.zshrc"
update_zshrc_export "TEST_VAR" "some_value"
if grep -q 'export TEST_VAR="some_value"' "$HOME/.zshrc"; then
    pass "update_zshrc_export appends when no marker found"
else
    fail "update_zshrc_export should append to end when no marker"
fi
cleanup_sandbox

# ===========================================================================
# Summary
# ===========================================================================

print_summary

if [[ $FAIL -gt 0 ]]; then
    exit 1
fi
