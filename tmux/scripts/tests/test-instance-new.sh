#!/usr/bin/env bash
set -euo pipefail

# regression tests for instances/new.sh window targeting
#
# 'new-window -t <name>' treats <name> as a target-window: when a window in the
# session carries the session's own name, tmux pins the new window to that
# window's index and fails with "index in use". the pickers run new.sh under
# fzf's execute-silent, so the failure surfaces as a no-op

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_DIR="$(dirname "$SCRIPT_DIR")"
DOTFILES_DIR="$(dirname "$(dirname "$SCRIPTS_DIR")")"

source "$SCRIPT_DIR/_test-helpers.sh"

trap 'cleanup_test_server' EXIT INT TERM

setup_test_server

NEW_SCRIPT="$SCRIPTS_DIR/instances/new.sh"

# ═══════════════════════════════════════════════════════════════
# tmux target semantics the fix relies on
# ═══════════════════════════════════════════════════════════════

section "Session-scoped new-window target"

SEM_SESSION="test-newsem-$$"
test_tmux new-session -d -s "$SEM_SESSION" -n "$SEM_SESSION" -c /tmp
test_tmux new-window -t "${SEM_SESSION}:" -n other -c /tmp

assert_failure "Bare session name collides with a window of the same name" \
    test_tmux new-window -t "$SEM_SESSION" -n bare -c /tmp

assert_success "Trailing ':' keeps the target session-scoped" \
    test_tmux new-window -t "${SEM_SESSION}:" -n scoped -c /tmp

test_tmux kill-session -t "$SEM_SESSION" 2>/dev/null || true

# ═══════════════════════════════════════════════════════════════
# new.sh against a colliding window name
# ═══════════════════════════════════════════════════════════════

section "new.sh with a window named after its session"

# new.sh resolves the current session via display-message, so leave exactly one
# session on the test server for it to find
test_tmux kill-session -t test-bootstrap 2>/dev/null || true

NEW_SESSION="test-newwin-$$"
test_tmux new-session -d -s "$NEW_SESSION" -n "$NEW_SESSION" -c /tmp
sleep 0.2

# switch-client fails on a headless server, so ignore the exit status and
# assert on the resulting windows instead
"$NEW_SCRIPT" nvim >/dev/null 2>&1 || true
sleep 0.2

NVIM_WINDOWS=$(test_tmux list-windows -t "${NEW_SESSION}:" -F '#{window_name}' | grep -c '^nvim$' || true)
assert_equals "Creates an nvim window despite the name collision" "1" "$NVIM_WINDOWS"

NVIM_RENAME=$(test_tmux list-windows -t "${NEW_SESSION}:" -F '#{window_name} #{automatic-rename}' | awk '$1 == "nvim" { print $2 }')
assert_equals "nvim window keeps automatic-rename off" "0" "$NVIM_RENAME"

# claude windows track their OSC title, so the default automatic-rename-format
# renames the window away from "claude" straight away. assert on the newest
# window instead of the name
"$NEW_SCRIPT" claude >/dev/null 2>&1 || true
sleep 0.2

NEWEST=$(test_tmux list-windows -t "${NEW_SESSION}:" -F '#{window_index}' | sort -n | tail -1)
CLAUDE_RENAME=$(test_tmux display-message -p -t "${NEW_SESSION}:${NEWEST}" '#{automatic-rename}')
assert_equals "claude window re-enables automatic-rename" "1" "$CLAUDE_RENAME"

test_tmux kill-session -t "$NEW_SESSION" 2>/dev/null || true

# ═══════════════════════════════════════════════════════════════
# drift guard: no bare-session new-window targets ship
# ═══════════════════════════════════════════════════════════════

section "Drift guard"

BARE_TARGETS=$(grep -rn 'new-window[^|]*-t "\$\(SESSION\|session\|CURRENT_SESSION\)"' \
    "$DOTFILES_DIR/tmux/scripts" "$DOTFILES_DIR/launchers" 2>/dev/null |
    grep -v '/tests/' | grep -v '/_lib/test-' || true)

if [[ -z "$BARE_TARGETS" ]]; then
    pass "No bare-session new-window targets in scripts or launchers"
else
    fail "Bare-session new-window targets found:"
    printf '%s\n' "$BARE_TARGETS"
fi

print_summary

if [[ $FAIL -gt 0 ]]; then
    exit 1
fi
