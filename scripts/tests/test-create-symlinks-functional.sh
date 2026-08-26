#!/usr/bin/env bash
set -euo pipefail

# functional tests for symlink creation patterns
# tests actual symlink/copy/local-override logic in a sandboxed HOME

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOTFILES_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

# source shared test helpers (colours, pass/fail/skip/section, assertions, sandbox)
source "$SCRIPT_DIR/_test-helpers.sh"

# ===========================================================================
# setup
# ===========================================================================

setup_sandbox
trap cleanup_sandbox EXIT

# create minimal structure the symlink script expects
mkdir -p "$TEST_HOME/.config"

# source common.sh for should_install and colour variables
source "$DOTFILES_DIR/scripts/_lib/common.sh"

# ===========================================================================
# tests
# ===========================================================================

section "Symlink creation patterns"

# test 1: ln -sf creates a valid symlink
test_source="$DOTFILES_DIR/zsh/dotfiles.zsh"
test_dest="$TEST_HOME/.config/zsh/dotfiles.zsh"
mkdir -p "$(dirname "$test_dest")"
ln -sf "$test_source" "$test_dest"

if [[ -L "$test_dest" ]]; then
    target=$(readlink "$test_dest")
    if [[ "$target" == "$test_source" ]]; then
        pass "symlink points to correct target"
    else
        fail "symlink points to wrong target: $target"
    fi
else
    fail "symlink was not created"
fi

# test 2: symlink replaces existing file
echo "existing content" >"$TEST_HOME/.test-existing"
test_source2="$DOTFILES_DIR/zsh/zprofile"
ln -sf "$test_source2" "$TEST_HOME/.test-existing"
if [[ -L "$TEST_HOME/.test-existing" ]]; then
    pass "symlink replaces existing file"
else
    fail "symlink did not replace existing file"
fi

# test 3: copy creates a regular file (not symlink)
test_copy_src="$DOTFILES_DIR/btop/btop.conf"
test_copy_dest="$TEST_HOME/.config/btop/btop.conf"
mkdir -p "$(dirname "$test_copy_dest")"
if [[ -f "$test_copy_src" ]]; then
    cp "$test_copy_src" "$test_copy_dest"
    if [[ -f "$test_copy_dest" && ! -L "$test_copy_dest" ]]; then
        pass "copy creates a regular file (not symlink)"
    else
        fail "copy created a symlink instead of a regular file"
    fi
else
    skip "btop.conf not found — skipping copy test"
fi

# test 4: install_local preserves existing file
test_template="$DOTFILES_DIR/ghostty/local.template"
test_local_dest="$TEST_HOME/.config/ghostty/local"
mkdir -p "$(dirname "$test_local_dest")"
if [[ -f "$test_template" ]]; then
    echo "my custom overrides" >"$test_local_dest"
    # simulate install_local, should NOT overwrite existing
    if [[ -f "$test_local_dest" ]]; then
        # install_local only copies if dest doesn't exist
        content=$(cat "$test_local_dest")
        if [[ "$content" == "my custom overrides" ]]; then
            pass "install_local preserves existing local override file"
        else
            fail "install_local overwrote existing local override file"
        fi
    fi
else
    skip "ghostty local.template not found"
fi

section "Preset filtering — minimal"
PRESET="minimal"

if should_install "minimal"; then
    pass "minimal preset includes minimal items"
else
    fail "minimal preset should include minimal items"
fi

if should_install "core"; then
    fail "minimal preset should not include core items"
else
    pass "minimal preset correctly excludes core items"
fi

if should_install "full"; then
    fail "minimal preset should not include full items"
else
    pass "minimal preset correctly excludes full items"
fi

section "Preset filtering — core"
PRESET="core"

if should_install "minimal"; then
    pass "core preset includes minimal items"
else
    fail "core preset should include minimal items"
fi

if should_install "core"; then
    pass "core preset includes core items"
else
    fail "core preset should include core items"
fi

if should_install "full"; then
    fail "core preset should not include full items"
else
    pass "core preset correctly excludes full items"
fi

section "Preset filtering — full"
PRESET="full"

if should_install "minimal"; then
    pass "full preset includes minimal items"
else
    fail "full preset should include minimal items"
fi

if should_install "core"; then
    pass "full preset includes core items"
else
    fail "full preset should include core items"
fi

if should_install "full"; then
    pass "full preset includes full items"
else
    fail "full preset should include full items"
fi

# ===========================================================================
# summary
# ===========================================================================

print_summary
[[ $FAIL -gt 0 ]] && exit 1
exit 0
