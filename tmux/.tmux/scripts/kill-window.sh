#!/usr/bin/env bash
# ══════════════════════════════════════════════════════════════
# kill-window.sh
# ══════════════════════════════════════════════════════════════
# Kills the current window, but saves its state for undo.
# If it's the last window in the session, switches to another
# session first to avoid detaching the client.
#
# Usage: kill-window.sh
# ══════════════════════════════════════════════════════════════

set -euo pipefail

# Get current state
CURRENT_SESSION=$(tmux display-message -p '#S')
CURRENT_WINDOW=$(tmux display-message -p '#{window_index}')
WINDOW_TARGET="${CURRENT_SESSION}:${CURRENT_WINDOW}"
WINDOW_COUNT=$(tmux list-windows | wc -l | tr -d ' ')

# Undo file locations
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
WINDOW_NAME=$(tmux display-message -p '#{window_name}')
WINDOW_ACTIVE=$(tmux display-message -p '#{window_active}')
WINDOW_FLAGS=$(tmux display-message -p '#{window_flags}')
WINDOW_LAYOUT=$(tmux display-message -p '#{window_layout}')
AUTO_RENAME=$(tmux show-window-option -v automatic-rename 2>/dev/null || echo "on")

# Write window line
echo "window${d}${CURRENT_SESSION}${d}${CURRENT_WINDOW}${d}:${WINDOW_NAME}${d}${WINDOW_ACTIVE}${d}${WINDOW_FLAGS}${d}${WINDOW_LAYOUT}${d}${AUTO_RENAME}" > "$UNDO_STATE"

# Get pane info for each pane (use process substitution to avoid subshell)
while IFS='|' read -r pane_index pane_title pane_dir pane_active pane_cmd; do
    # Escape spaces in path
    escaped_dir="${pane_dir// /\\ }"

    # Write pane line
    echo "pane${d}${CURRENT_SESSION}${d}${CURRENT_WINDOW}${d}${WINDOW_ACTIVE}${d}${WINDOW_FLAGS}${d}${pane_index}${d}${pane_title}${d}:${escaped_dir}${d}${pane_active}${d}${pane_cmd}${d}:" >> "$UNDO_STATE"

    # Capture full pane history (scrollback + visible)
    tmux capture-pane -t "${WINDOW_TARGET}.${pane_index}" -p -S - > "${UNDO_CONTENTS_DIR}/pane-${pane_index}.txt" 2>/dev/null || true
done < <(tmux list-panes -F '#{pane_index}|#{pane_title}|#{pane_current_path}|#{pane_active}|#{pane_current_command}')

# If this is the last window, switch to another session first
if [[ "$WINDOW_COUNT" -eq 1 ]]; then
    OTHER_SESSION=$(tmux list-sessions -F '#{session_activity} #{session_name}' | \
        sort -rn | cut -d' ' -f2- | grep -v "^${CURRENT_SESSION}$" | head -n1)

    if [[ -n "$OTHER_SESSION" ]]; then
        tmux switch-client -t "$OTHER_SESSION"
    fi
fi

# Kill the window
tmux kill-window -t "$WINDOW_TARGET" 2>/dev/null || true
