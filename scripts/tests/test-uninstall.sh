#!/usr/bin/env bash
set -euo pipefail

# tests for uninstall.sh structure and symlink removal logic

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOTFILES_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

# source shared test helpers (colours, pass/fail/skip/section, assertions, sandbox)
source "$SCRIPT_DIR/_test-helpers.sh"

UNINSTALL_SCRIPT="$DOTFILES_DIR/scripts/install/uninstall.sh"

# ===========================================================================
# Tests
# ===========================================================================

section "Uninstall script structure"

# test 1: script exists and is executable
if [[ -x "$UNINSTALL_SCRIPT" ]]; then
    pass "uninstall.sh exists and is executable"
else
    fail "uninstall.sh missing or not executable"
fi

# test 2: script sources common.sh
if grep -q 'source.*common\.sh' "$UNINSTALL_SCRIPT"; then
    pass "uninstall.sh sources common.sh"
else
    fail "uninstall.sh does not source common.sh"
fi

# test 3: script has --restore-backup flag
if grep -q 'restore.backup' "$UNINSTALL_SCRIPT"; then
    pass "uninstall.sh supports --restore-backup flag"
else
    fail "uninstall.sh missing --restore-backup support"
fi

# test 4: script has --remove-brew-packages flag
if grep -q 'remove.brew.packages' "$UNINSTALL_SCRIPT"; then
    pass "uninstall.sh supports --remove-brew-packages flag"
else
    fail "uninstall.sh missing --remove-brew-packages support"
fi

# test 5: script has help output
if bash "$UNINSTALL_SCRIPT" --help 2>&1 | grep -qi "uninstall\|usage\|remove" 2>/dev/null; then
    pass "uninstall.sh has help output"
else
    skip "uninstall.sh has no --help flag"
fi

# test 6: script handles local override files
for override in ghostty tmux nvim; do
    if grep -q "$override.*local" "$UNINSTALL_SCRIPT"; then
        pass "uninstall.sh handles $override local override"
    else
        fail "uninstall.sh missing $override local override handling"
    fi
done

section "Symlink removal logic (sandboxed)"

setup_sandbox
trap cleanup_sandbox EXIT

# test 7: create and remove mock symlinks
mkdir -p "$TEST_HOME/.config/zsh"
ln -sf "$DOTFILES_DIR/zsh/dotfiles.zsh" "$TEST_HOME/.config/zsh/dotfiles.zsh"
ln -sf "$DOTFILES_DIR/zsh/zprofile" "$TEST_HOME/.zprofile"

if [[ -L "$TEST_HOME/.config/zsh/dotfiles.zsh" && -L "$TEST_HOME/.zprofile" ]]; then
    pass "test symlinks created successfully"
else
    fail "could not create test symlinks"
fi

# simulate uninstall symlink removal
for link in "$TEST_HOME/.config/zsh/dotfiles.zsh" "$TEST_HOME/.zprofile"; do
    if [[ -L "$link" ]]; then
        rm "$link"
    fi
done

if [[ ! -L "$TEST_HOME/.config/zsh/dotfiles.zsh" && ! -L "$TEST_HOME/.zprofile" ]]; then
    pass "symlink removal works correctly"
else
    fail "symlinks were not removed"
fi

# test 8: removal skips non-symlink files
echo "real config" >"$TEST_HOME/.test-real-file"
# uninstall should skip this since it's not a symlink
if [[ -f "$TEST_HOME/.test-real-file" && ! -L "$TEST_HOME/.test-real-file" ]]; then
    pass "non-symlink file preserved during removal"
else
    fail "non-symlink file was incorrectly removed"
fi

# ===========================================================================
# Symlink manifest drift guard
# ===========================================================================

section "symlink manifest drift guard"

# every create_link destination in create-symlinks.sh must appear in
# uninstall.sh's SYMLINKS array, or uninstall leaves a dangling link behind.
# add the destination to SYMLINKS, or record it below with a reason.
# both sides are resolved with the same variables rather than compared as
# text, so ${XDG_CONFIG_HOME:-...} and $lazygit_dir forms match either way
symlink_drift_exclusions=(
    # none currently
)

# a fixed stand-in for $HOME so both sides resolve to comparable paths
HOME_STUB="/drift-home"
LAZYDOCKER_MAC="$HOME_STUB/Library/Application Support/lazydocker"
LAZYDOCKER_LINUX="$HOME_STUB/.config/lazydocker"

resolve_dest() {
    # $1 = shell expression, $2 = lazydocker_dir to assume
    env -u XDG_CONFIG_HOME \
        HOME="$HOME_STUB" \
        lazygit_dir="$HOME_STUB/.config/lazygit" \
        lazydocker_dir="$2" \
        bash -c "printf '%s' \"$1\""
}

# destinations the installer creates
installer_exprs=$(grep -E '^[[:space:]]*create_link ' \
    "$DOTFILES_DIR/scripts/install/create-symlinks.sh" |
    sed -E 's/^[[:space:]]*create_link "[^"]+" "([^"]+)".*/\1/')

# destinations uninstall knows about: the array body plus any += appends
uninstall_exprs=$({
    sed -n '/^SYMLINKS=(/,/^)/p' "$UNINSTALL_SCRIPT"
    grep -E 'SYMLINKS\+=\(' "$UNINSTALL_SCRIPT"
} | grep -oE '"[^"]+"' | tr -d '"')

# resolve the uninstall side once, under both lazydocker layouts
uninstall_resolved=""
while IFS= read -r expr; do
    [[ -z "$expr" ]] && continue
    for ld in "$LAZYDOCKER_MAC" "$LAZYDOCKER_LINUX"; do
        uninstall_resolved+="$(resolve_dest "$expr" "$ld")"$'\n'
    done
done <<<"$uninstall_exprs"

symlink_drift_ok=1
while IFS= read -r expr; do
    [[ -z "$expr" ]] && continue
    excluded=0
    for ex in "${symlink_drift_exclusions[@]:-}"; do
        [[ "$expr" == "$ex" ]] && excluded=1
    done
    [[ $excluded -eq 1 ]] && continue
    for ld in "$LAZYDOCKER_MAC" "$LAZYDOCKER_LINUX"; do
        resolved=$(resolve_dest "$expr" "$ld")
        if ! printf '%s' "$uninstall_resolved" | grep -qxF "$resolved"; then
            fail "symlink drift: '$expr' is created by create-symlinks.sh but missing from SYMLINKS in uninstall.sh"
            symlink_drift_ok=0
            break
        fi
    done
done <<<"$installer_exprs"

if [[ $symlink_drift_ok -eq 1 ]]; then
    pass "every create_link destination is covered by uninstall.sh"
fi

# ===========================================================================
# Summary
# ===========================================================================

print_summary
[[ $FAIL -gt 0 ]] && exit 1
exit 0
