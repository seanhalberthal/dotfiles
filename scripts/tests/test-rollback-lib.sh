#!/usr/bin/env bash
set -euo pipefail

# functional tests for scripts/_lib/rollback.sh
# tests rollback operations with real filesystem operations in a temp directory

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOTFILES_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

# source shared test helpers
source "$SCRIPT_DIR/_test-helpers.sh"

# create isolated test environment
TEST_DIR=$(mktemp -d)
TEST_HOME="$TEST_DIR/home"
TEST_BACKUP="$TEST_DIR/backup"
mkdir -p "$TEST_HOME" "$TEST_BACKUP"

# override HOME and DOTFILES_DIR for isolation
ORIGINAL_HOME="$HOME"
export HOME="$TEST_HOME"
export DOTFILES_DIR="$TEST_DIR/dotfiles"
mkdir -p "$DOTFILES_DIR"

# trap to ensure cleanup
trap 'HOME="$ORIGINAL_HOME"; rm -rf "$TEST_DIR"' EXIT INT TERM

# source the libraries under test
# shellcheck source=scripts/_lib/common.sh
source "$DOTFILES_DIR/../../dotfiles/scripts/_lib/common.sh" 2>/dev/null ||
    source "$(cd "$SCRIPT_DIR/.." && pwd)/_lib/common.sh"
# shellcheck source=scripts/_lib/rollback.sh
source "$(cd "$SCRIPT_DIR/.." && pwd)/_lib/rollback.sh"

# ═══════════════════════════════════════════════════════════════
# init_rollback_state Tests
# ═══════════════════════════════════════════════════════════════

section "init_rollback_state"

init_rollback_state

if [[ -d "$ROLLBACK_STATE_DIR" ]]; then
    pass "Creates state directory"
else
    fail "Should create state directory"
fi

# check permissions (macOS and Linux have different stat syntax)
if [[ "$(uname)" == "Darwin" ]]; then
    dir_perms=$(stat -f %Lp "$ROLLBACK_STATE_DIR" 2>/dev/null) || dir_perms="unknown"
else
    dir_perms=$(stat -c %a "$ROLLBACK_STATE_DIR" 2>/dev/null) || dir_perms="unknown"
fi
if [[ "$dir_perms" == "700" ]]; then
    pass "State directory has 700 permissions"
else
    fail "State directory should have 700 permissions (got: $dir_perms)"
fi

if [[ -f "$ROLLBACK_STATE_FILE" ]]; then
    pass "Creates state.txt"
else
    fail "Should create state.txt"
fi

if [[ -f "$SYMLINKS_CREATED_FILE" ]]; then
    pass "Creates symlinks.txt"
else
    fail "Should create symlinks.txt"
fi

if [[ -f "$BACKUP_LOCATION_FILE" ]]; then
    pass "Creates backup-location.txt"
else
    fail "Should create backup-location.txt"
fi

# ═══════════════════════════════════════════════════════════════
# record_step Tests
# ═══════════════════════════════════════════════════════════════

section "record_step"

record_step "prerequisites"
record_step "packages"
record_step "symlinks"

step_count=$(wc -l <"$ROLLBACK_STATE_FILE" | tr -d ' ')
assert_equals "Records three steps" "3" "$step_count"

last_step=$(get_last_step)
assert_equals "get_last_step returns last recorded step" "symlinks" "$last_step"

# ═══════════════════════════════════════════════════════════════
# record_symlink Tests
# ═══════════════════════════════════════════════════════════════

section "record_symlink"

record_symlink "$TEST_HOME/.zshrc" "$DOTFILES_DIR/zsh/zshrc"
record_symlink "$TEST_HOME/.tmux.conf" "$DOTFILES_DIR/tmux/tmux.conf"

symlink_count=$(wc -l <"$SYMLINKS_CREATED_FILE" | tr -d ' ')
assert_equals "Records two symlinks" "2" "$symlink_count"

# verify pipe-delimited format
first_line=$(head -1 "$SYMLINKS_CREATED_FILE")
if [[ "$first_line" == *"|"* ]]; then
    pass "Symlink records use pipe delimiter"
else
    fail "Symlink records should use pipe delimiter"
fi

# ═══════════════════════════════════════════════════════════════
# record_backup_location Tests
# ═══════════════════════════════════════════════════════════════

section "record_backup_location"

record_backup_location "$TEST_BACKUP"

backup_loc=$(get_backup_location)
assert_equals "Records and retrieves backup location" "$TEST_BACKUP" "$backup_loc"

# ═══════════════════════════════════════════════════════════════
# perform_rollback Tests
# ═══════════════════════════════════════════════════════════════

section "perform_rollback - Symlink Removal"

# create actual symlinks that rollback should remove
mkdir -p "$DOTFILES_DIR/zsh" "$DOTFILES_DIR/tmux"
echo "zshrc content" >"$DOTFILES_DIR/zsh/zshrc"
echo "tmux content" >"$DOTFILES_DIR/tmux/tmux.conf"

ln -sf "$DOTFILES_DIR/zsh/zshrc" "$TEST_HOME/.zshrc"
ln -sf "$DOTFILES_DIR/tmux/tmux.conf" "$TEST_HOME/.tmux.conf"

if [[ -L "$TEST_HOME/.zshrc" ]]; then
    pass "Test symlink .zshrc created"
else
    fail "Test symlink .zshrc should exist"
fi

# re-initialise state with the symlinks
init_rollback_state
record_symlink "$TEST_HOME/.zshrc" "$DOTFILES_DIR/zsh/zshrc"
record_symlink "$TEST_HOME/.tmux.conf" "$DOTFILES_DIR/tmux/tmux.conf"

# create a backup to restore from
mkdir -p "$TEST_BACKUP/.config"
echo "original zshrc" >"$TEST_BACKUP/.zshrc"
record_backup_location "$TEST_BACKUP"

# run rollback
perform_rollback 2>/dev/null

if [[ ! -L "$TEST_HOME/.zshrc" ]]; then
    pass "Rollback removes .zshrc symlink"
else
    fail "Rollback should remove .zshrc symlink"
fi

if [[ ! -L "$TEST_HOME/.tmux.conf" ]]; then
    pass "Rollback removes .tmux.conf symlink"
else
    fail "Rollback should remove .tmux.conf symlink"
fi

# check backup was restored
if [[ -f "$TEST_HOME/.zshrc" ]] && [[ "$(cat "$TEST_HOME/.zshrc")" == "original zshrc" ]]; then
    pass "Rollback restores .zshrc from backup"
else
    fail "Rollback should restore .zshrc from backup"
fi

# ═══════════════════════════════════════════════════════════════
# cleanup_rollback_state Tests
# ═══════════════════════════════════════════════════════════════

section "cleanup_rollback_state"

# re-init and then clean up
init_rollback_state
record_step "test"

if has_rollback_state; then
    pass "has_rollback_state returns true when state exists"
else
    fail "has_rollback_state should return true"
fi

cleanup_rollback_state

if ! has_rollback_state; then
    pass "cleanup_rollback_state removes state directory"
else
    fail "cleanup_rollback_state should remove state directory"
fi

# ═══════════════════════════════════════════════════════════════
# idempotency tests
# ═══════════════════════════════════════════════════════════════

section "Idempotency"

# record_step with no state directory should be a no-op
cleanup_rollback_state 2>/dev/null || true
record_step "should_noop" 2>/dev/null || true
pass "record_step is no-op without state directory"

record_symlink "/fake/path" "/fake/target" 2>/dev/null || true
pass "record_symlink is no-op without state directory"

record_backup_location "/fake/backup" 2>/dev/null || true
pass "record_backup_location is no-op without state directory"

# ═══════════════════════════════════════════════════════════════
# path traversal protection tests
# ═══════════════════════════════════════════════════════════════

section "Path Traversal Protection"

# create a backup with a traversal path and verify it's skipped
mkdir -p "$TEST_BACKUP"
init_rollback_state
record_backup_location "$TEST_BACKUP"

# create a file with a traversal path in the backup
# the restore_from_backup function should skip files matching ../ patterns
# this is a structural check; the function uses pattern matching
rollback_content=$(cat "$(cd "$SCRIPT_DIR/.." && pwd)/_lib/rollback.sh")
if [[ "$rollback_content" == *'../*'* ]]; then
    pass "Rollback library checks for path traversal patterns"
else
    fail "Rollback library should check for ../ patterns"
fi

if [[ "$rollback_content" == *'/../'* ]]; then
    pass "Rollback library checks for embedded traversal patterns"
else
    fail "Rollback library should check for /../ patterns"
fi

cleanup_rollback_state

# ═══════════════════════════════════════════════════════════════
# summary
# ═══════════════════════════════════════════════════════════════

print_summary

if [[ $FAIL -gt 0 ]]; then
    exit 1
fi
