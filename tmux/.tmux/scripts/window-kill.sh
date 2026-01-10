#!/usr/bin/env bash
# ══════════════════════════════════════════════════════════════
# window-kill.sh
# ══════════════════════════════════════════════════════════════
# Kills a tmux window but preserves its state for undo.
# Called from fzf window switcher when user presses Ctrl+x.
#
# Saves window state in resurrect-compatible format for restoration.
#
# Usage: window-kill.sh <session:window>
# ══════════════════════════════════════════════════════════════

set -euo pipefail

WINDOW_TARGET="${1:-}"
[[ -z "$WINDOW_TARGET" ]] && exit 1

# Parse session:window format
SESSION_NAME="${WINDOW_TARGET%%:*}"
WINDOW_INDEX="${WINDOW_TARGET#*:}"

# Verify window exists
tmux has-session -t "$SESSION_NAME" 2>/dev/null || exit 1
tmux list-windows -t "$SESSION_NAME" -F '#{window_index}' | grep -q "^${WINDOW_INDEX}$" || exit 1

UNDO_FILE="/tmp/tmux-undo-window"
UNDO_STATE="/tmp/tmux-undo-window-state.txt"
UNDO_CONTENTS_DIR="/tmp/tmux-undo-window-contents"

# Clear previous undo data
rm -f "$UNDO_FILE" "$UNDO_STATE"
rm -rf "$UNDO_CONTENTS_DIR"
mkdir -p "$UNDO_CONTENTS_DIR"

# Save window target for undo
echo "$WINDOW_TARGET" > "$UNDO_FILE"

# Tab delimiter (resurrect format)
d=$'\t'

# Get window info
WINDOW_NAME=$(tmux display-message -t "$WINDOW_TARGET" -p '#{window_name}')
WINDOW_ACTIVE=$(tmux display-message -t "$WINDOW_TARGET" -p '#{window_active}')
WINDOW_FLAGS=$(tmux display-message -t "$WINDOW_TARGET" -p '#{window_flags}')
WINDOW_LAYOUT=$(tmux display-message -t "$WINDOW_TARGET" -p '#{window_layout}')
AUTO_RENAME=$(tmux show-window-option -t "$WINDOW_TARGET" -v automatic-rename 2>/dev/null || echo "on")

# Write window line
echo "window${d}${SESSION_NAME}${d}${WINDOW_INDEX}${d}:${WINDOW_NAME}${d}${WINDOW_ACTIVE}${d}${WINDOW_FLAGS}${d}${WINDOW_LAYOUT}${d}${AUTO_RENAME}" > "$UNDO_STATE"

# Get pane info for each pane (use process substitution to avoid subshell)
while IFS='|' read -r pane_index pane_title pane_dir pane_active pane_cmd; do
    # Escape spaces in path
    escaped_dir="${pane_dir// /\\ }"

    # Write pane line
    echo "pane${d}${SESSION_NAME}${d}${WINDOW_INDEX}${d}${WINDOW_ACTIVE}${d}${WINDOW_FLAGS}${d}${pane_index}${d}${pane_title}${d}:${escaped_dir}${d}${pane_active}${d}${pane_cmd}${d}:" >> "$UNDO_STATE"

    # Capture full pane history (scrollback + visible)
    tmux capture-pane -t "${WINDOW_TARGET}.${pane_index}" -p -S - > "${UNDO_CONTENTS_DIR}/pane-${pane_index}.txt" 2>/dev/null || true
done < <(tmux list-panes -t "$WINDOW_TARGET" -F '#{pane_index}|#{pane_title}|#{pane_current_path}|#{pane_active}|#{pane_current_command}')

# If this is the last window in the current session, switch to another session first
CURRENT_SESSION=$(tmux display-message -p '#S')
WINDOW_COUNT=$(tmux list-windows -t "$SESSION_NAME" | wc -l | tr -d ' ')

if [[ "$SESSION_NAME" == "$CURRENT_SESSION" && "$WINDOW_COUNT" -eq 1 ]]; then
    # Find another session to switch to
    OTHER_SESSION=$(tmux list-sessions -F '#{session_activity} #{session_name}' | \
        sort -rn | cut -d' ' -f2- | grep -v "^${SESSION_NAME}$" | head -n1)

    if [[ -n "$OTHER_SESSION" ]]; then
        tmux switch-client -t "$OTHER_SESSION"
    fi
fi

# Kill the window
tmux kill-window -t "$WINDOW_TARGET" 2>/dev/null || true
