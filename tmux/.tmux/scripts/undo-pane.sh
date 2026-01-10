#!/usr/bin/env bash
# ══════════════════════════════════════════════════════════════
# undo-pane.sh
# ══════════════════════════════════════════════════════════════
# Restores the last killed pane from its preserved state.
# Called by undo-dispatch.sh when a pane was the last thing killed.
#
# Usage: undo-pane.sh
# ══════════════════════════════════════════════════════════════

set -euo pipefail

UNDO_FILE="/tmp/tmux-undo-pane"
UNDO_STATE="/tmp/tmux-undo-pane-state.txt"
UNDO_CONTENT="/tmp/tmux-undo-pane-content.txt"

# Check if there's something to undo
[[ ! -f "$UNDO_FILE" ]] && exit 0
[[ ! -f "$UNDO_STATE" ]] && { rm -f "$UNDO_FILE"; exit 0; }

# Read saved state
source "$UNDO_STATE"

# Check if session still exists
if ! tmux has-session -t "$SESSION" 2>/dev/null; then
    rm -f "$UNDO_FILE" "$UNDO_STATE" "$UNDO_CONTENT"
    exit 0
fi

# Ensure directory exists
[[ -d "$DIR" ]] || DIR="$HOME"

# Check if window still exists
if tmux list-windows -t "$SESSION" -F '#{window_index}' | grep -q "^${WINDOW}$"; then
    # Window exists - split to create new pane
    tmux split-window -t "${SESSION}:${WINDOW}" -c "$DIR"

    # Try to restore the layout if we had multiple panes before
    if [[ "$PANE_COUNT" -gt 1 && -n "$LAYOUT" ]]; then
        tmux select-layout -t "${SESSION}:${WINDOW}" "$LAYOUT" 2>/dev/null || true
    fi
else
    # Window was destroyed (last pane case) - create new window
    tmux new-window -t "${SESSION}:${WINDOW}" -c "$DIR"
fi

# Small delay for shell readiness
sleep 0.1

# Display saved content in the new pane
if [[ -f "$UNDO_CONTENT" && -s "$UNDO_CONTENT" ]]; then
    # Get the newly created pane (it should be the active one now)
    NEW_PANE=$(tmux display-message -t "${SESSION}:${WINDOW}" -p '#{pane_index}')
    tmux send-keys -t "${SESSION}:${WINDOW}.${NEW_PANE}" "cat '${UNDO_CONTENT}'" Enter
fi

# Delayed cleanup (let cat finish first)
(sleep 1 && rm -f "$UNDO_FILE" "$UNDO_STATE" "$UNDO_CONTENT") &
