#!/usr/bin/env bash
set -euo pipefail

# unit tests for tmux theme reload functionality
# tests that theme switching properly reloads tmux configuration
# requires tmux to be installed (tests are skipped if not available)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/_test-helpers.sh"

DOTFILES_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
THEME_SWITCH="$DOTFILES_ROOT/scripts/theme-switch"
THEMES_DIR="$DOTFILES_ROOT/themes"
TMUX_TEMPLATE="$DOTFILES_ROOT/tmux/tmux.conf.template"
# use XDG path where theme-switch actually writes the config
TMUX_OUTPUT="${XDG_CONFIG_HOME:-$HOME/.config}/tmux/tmux.conf"

# ===========================================================================
# pre-flight checks
# ===========================================================================

section "Pre-flight Checks"

# check if tmux is available
if ! command -v tmux &>/dev/null; then
    skip "tmux is not installed - skipping all reload tests"
    print_summary
    exit 0
fi

pass "tmux is installed"

if [[ -f "$THEME_SWITCH" ]]; then
    pass "theme-switch script exists"
else
    fail "theme-switch script not found"
    exit 1
fi

if [[ -f "$TMUX_TEMPLATE" ]]; then
    pass "tmux template exists"
else
    skip "tmux template not found - some tests may fail"
fi

# ===========================================================================
# test server setup
# ===========================================================================

section "Test Server Setup"

setup_test_server

if $TEST_TMUX_CMD list-sessions &>/dev/null; then
    pass "test tmux server started successfully"
else
    fail "failed to start test tmux server"
    cleanup_test_server
    exit 1
fi

# ensure cleanup on exit
trap cleanup_test_server EXIT

# create a test session for theme testing
$TEST_TMUX_CMD new-session -d -s theme-test 2>/dev/null || true

if $TEST_TMUX_CMD has-session -t theme-test 2>/dev/null; then
    pass "created theme-test session"
else
    fail "failed to create theme-test session"
fi

# ===========================================================================
# theme switch script structure
# ===========================================================================

section "Theme Switch Script Structure"

script_content=$(cat "$THEME_SWITCH")

# check for tmux reload logic
if [[ "$script_content" == *"tmux source-file"* ]]; then
    pass "theme-switch includes tmux reload command"
else
    fail "theme-switch should include tmux source-file for reload"
fi

# check for tmux availability check
if [[ "$script_content" == *"command -v tmux"* ]] || [[ "$script_content" == *"which tmux"* ]]; then
    pass "theme-switch checks if tmux is available"
else
    skip "tmux availability check not found"
fi

# check for running tmux detection
if [[ "$script_content" == *'tmux info'* ]] || [[ "$script_content" == *'tmux list-sessions'* ]]; then
    pass "theme-switch detects running tmux"
else
    skip "running tmux detection not found"
fi

# ===========================================================================
# config generation tests
# ===========================================================================

section "Config Generation Tests"

# save original config if it exists
original_config=""
if [[ -f "$TMUX_OUTPUT" ]]; then
    original_config=$(cat "$TMUX_OUTPUT")
fi

# apply a theme to generate config
theme_output=$("$THEME_SWITCH" dracula --no-reload 2>&1) && theme_result=0 || theme_result=$?
if [[ $theme_result -eq 0 ]]; then
    pass "theme-switch applied dracula theme"
else
    fail "theme-switch should apply dracula theme (exit code: $theme_result)"
    echo "  Error output: $theme_output" | head -3
fi

# verify config was generated
if [[ -f "$TMUX_OUTPUT" ]]; then
    pass "tmux config file was generated"

    # check that config doesn't contain placeholders
    if ! grep -q "{{.*}}" "$TMUX_OUTPUT"; then
        pass "generated config has no unrendered placeholders"
    else
        fail "generated config should not contain placeholders"
    fi

    # check that config contains themed colours (hex codes from theme)
    if grep -qE '#[0-9a-fA-F]{6}' "$TMUX_OUTPUT"; then
        pass "generated config contains theme colours"
    else
        fail "generated config should contain theme colours"
    fi
else
    fail "tmux config file should be generated"
fi

# ===========================================================================
# tmux reload tests
# ===========================================================================

section "Tmux Reload Tests"

# test that config can be loaded by tmux
if [[ -f "$TMUX_OUTPUT" ]]; then
    # try to source the config in the test server
    # note: may fail with TPM error in CI (acceptable; only TPM missing, not config syntax)
    reload_output=$($TEST_TMUX_CMD source-file "$TMUX_OUTPUT" 2>&1) && reload_result=0 || reload_result=$?
    if [[ $reload_result -eq 0 ]] || [[ "$reload_output" == *"tpm"* ]]; then
        pass "tmux can source the generated config (TPM errors OK)"
    else
        fail "tmux should be able to source the generated config"
    fi
else
    skip "tmux config reload test (no config file)"
fi

# ===========================================================================
# theme switching tests
# ===========================================================================

section "Theme Switching Tests"

# switch to different theme and verify
# save config before switching (for comparison)
config_backup="${TMUX_OUTPUT}.test-backup"
cp "$TMUX_OUTPUT" "$config_backup" 2>/dev/null || true

theme_output=$("$THEME_SWITCH" nord --no-reload 2>&1) && theme_result=0 || theme_result=$?
if [[ $theme_result -eq 0 ]]; then
    pass "theme-switch applied nord theme"

    # check config was modified (use cmp for portability; works on macOS and Linux)
    if ! cmp -s "$config_backup" "$TMUX_OUTPUT" 2>/dev/null; then
        pass "config updated when switching themes"
    else
        fail "config should be updated when switching themes"
    fi
    rm -f "$config_backup"

    # source the new config (TPM errors are acceptable in CI)
    reload_output=$($TEST_TMUX_CMD source-file "$TMUX_OUTPUT" 2>&1) && reload_result=0 || reload_result=$?
    if [[ $reload_result -eq 0 ]] || [[ "$reload_output" == *"tpm"* ]]; then
        pass "tmux reloaded with nord theme (TPM errors OK)"
    else
        fail "tmux should reload with nord theme"
    fi
else
    fail "theme-switch should apply nord theme (exit code: $theme_result)"
    echo "  Error output: $theme_output" | head -3
fi

# switch back to dracula
config_nord=$(md5sum "$TMUX_OUTPUT" 2>/dev/null | cut -d' ' -f1 || echo "")

theme_output=$("$THEME_SWITCH" dracula --no-reload 2>&1) && theme_result=0 || theme_result=$?
if [[ $theme_result -eq 0 ]]; then
    pass "theme-switch switched back to dracula"

    # config should change again
    config_dracula=$(md5sum "$TMUX_OUTPUT" 2>/dev/null | cut -d' ' -f1 || echo "")
    if [[ "$config_nord" != "$config_dracula" ]]; then
        pass "config changed when reverting theme"
    else
        fail "config should change when reverting theme"
    fi
else
    fail "theme-switch should switch back to dracula (exit code: $theme_result)"
    echo "  Error output: $theme_output" | head -3
fi

# ===========================================================================
# multiple session tests
# ===========================================================================

section "Multiple Session Tests"

# create additional sessions
$TEST_TMUX_CMD new-session -d -s theme-test-2 2>/dev/null || true
$TEST_TMUX_CMD new-session -d -s theme-test-3 2>/dev/null || true

session_count=$($TEST_TMUX_CMD list-sessions 2>/dev/null | wc -l | tr -d ' ')

if [[ $session_count -ge 3 ]]; then
    pass "created multiple test sessions ($session_count total)"
else
    fail "should have at least 3 sessions, got $session_count"
fi

# apply theme; all sessions should work with new config
theme_output=$("$THEME_SWITCH" tokyo-night --no-reload 2>&1) && theme_result=0 || theme_result=$?
if [[ $theme_result -eq 0 ]]; then
    pass "applied tokyo-night theme with multiple sessions"

    # source in test server (affects all sessions, TPM errors acceptable)
    reload_output=$($TEST_TMUX_CMD source-file "$TMUX_OUTPUT" 2>&1) && reload_result=0 || reload_result=$?
    if [[ $reload_result -eq 0 ]] || [[ "$reload_output" == *"tpm"* ]]; then
        pass "config reloaded across multiple sessions (TPM errors OK)"
    else
        fail "should reload config across sessions"
    fi
else
    fail "should apply theme with multiple sessions (exit code: $theme_result)"
    echo "  Error output: $theme_output" | head -3
fi

# ===========================================================================
# error recovery tests
# ===========================================================================

section "Error Recovery Tests"

# test with invalid theme (should fail gracefully)
invalid_output=$("$THEME_SWITCH" nonexistent-theme-12345 2>&1) && exit_code=0 || exit_code=$?

if [[ $exit_code -ne 0 ]]; then
    pass "theme-switch fails on invalid theme"
else
    fail "theme-switch should fail on invalid theme"
fi

# config should still be valid after failed theme switch (TPM errors acceptable)
reload_output=$($TEST_TMUX_CMD source-file "$TMUX_OUTPUT" 2>&1) && reload_result=0 || reload_result=$?
if [[ $reload_result -eq 0 ]] || [[ "$reload_output" == *"tpm"* ]]; then
    pass "config remains valid after failed theme switch (TPM errors OK)"
else
    fail "config should remain valid after failed theme switch"
fi

# ===========================================================================
# config syntax validation
# ===========================================================================

section "Config Syntax Validation"

# test that generated config is valid tmux syntax
# we do this by having tmux parse it

if [[ -f "$TMUX_OUTPUT" ]]; then
    # tmux source-file succeeding means syntax is valid (TPM errors are acceptable)
    reload_output=$($TEST_TMUX_CMD source-file "$TMUX_OUTPUT" 2>&1) && reload_result=0 || reload_result=$?
    if [[ $reload_result -eq 0 ]] || [[ "$reload_output" == *"tpm"* ]]; then
        pass "generated config has valid tmux syntax (TPM errors OK)"
    else
        fail "generated config should have valid tmux syntax"
    fi

    # check for common syntax patterns
    config_content=$(cat "$TMUX_OUTPUT")

    if [[ "$config_content" == *"set -g"* ]]; then
        pass "config uses 'set -g' global options"
    else
        skip "set -g pattern check"
    fi

    if [[ "$config_content" == *"set-option"* ]] || [[ "$config_content" == *"set -g"* ]]; then
        pass "config uses proper tmux option syntax"
    else
        fail "config should use proper tmux option syntax"
    fi

    # check for colour definitions (use here-string to avoid broken pipe with grep -q)
    if grep -qE '#[0-9a-fA-F]{6}' <<<"$config_content"; then
        pass "config contains hex colour codes"
    else
        fail "config should contain hex colour codes"
    fi
else
    skip "config syntax validation (no config file)"
fi

# ===========================================================================
# idempotency tests
# ===========================================================================

section "Idempotency Tests"

# apply same theme twice; config should be identical
"$THEME_SWITCH" dracula --no-reload 2>/dev/null || true
config_first=$(cat "$TMUX_OUTPUT")

"$THEME_SWITCH" dracula --no-reload 2>/dev/null || true
config_second=$(cat "$TMUX_OUTPUT")

if [[ "$config_first" == "$config_second" ]]; then
    pass "theme application is idempotent"
else
    fail "applying same theme twice should produce identical config"
fi

# ===========================================================================
# cleanup
# ===========================================================================

section "Cleanup"

# kill test sessions
$TEST_TMUX_CMD kill-session -t theme-test 2>/dev/null || true
$TEST_TMUX_CMD kill-session -t theme-test-2 2>/dev/null || true
$TEST_TMUX_CMD kill-session -t theme-test-3 2>/dev/null || true

pass "cleaned up test sessions"

# restore original config if we had one
if [[ -n "$original_config" ]]; then
    echo "$original_config" >"$TMUX_OUTPUT"
    pass "restored original tmux config"
fi

# ===========================================================================
# summary
# ===========================================================================

print_summary
[[ $FAIL -gt 0 ]] && exit 1
exit 0
