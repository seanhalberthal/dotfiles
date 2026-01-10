#!/usr/bin/env bash
set -euo pipefail

# Restore the last killed pane from its preserved state

SCRIPT_DIR="${BASH_SOURCE%/*}"
source "$SCRIPT_DIR/_lib/common.sh"
source "$SCRIPT_DIR/_lib/paths.sh"

# Get undo file paths
UNDO_FILE=$(get_pane_undo_file)
UNDO_STATE=$(get_pane_undo_state)
UNDO_CONTENT=$(get_pane_undo_content)

# Check if there's something to undo
[[ ! -f "$UNDO_FILE" ]] && exit 0
[[ ! -f "$UNDO_STATE" ]] && { rm -f "$UNDO_FILE"; exit 0; }

# Parse pane target from undo file (format: session:window.pane)
PANE_TARGET=$(cat "$UNDO_FILE")
SESSION="${PANE_TARGET%%:*}"
WINDOW_PANE="${PANE_TARGET#*:}"
WINDOW="${WINDOW_PANE%%.*}"

# Read saved state
DIR=""
LAYOUT=""

while IFS='=' read -r key value; do
    case "$key" in
        dir) DIR="$value" ;;
        layout) LAYOUT="$value" ;;
    esac
done < "$UNDO_STATE"

# Check if session still exists
if ! tmux has-session -t "$SESSION" 2>/dev/null; then
    cleanup_undo_files "pane"
    exit 0
fi

# Ensure directory exists
[[ -d "$DIR" ]] || DIR="$HOME"

# Check if window still exists
if tmux list-windows -t "$SESSION" -F '#{window_index}' | grep -q "^${WINDOW}$"; then
    # Window exists - split to create new pane
    tmux split-window -t "${SESSION}:${WINDOW}" -c "$DIR"

    # Try to restore the layout
    if [[ -n "$LAYOUT" ]]; then
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
(sleep 1 && cleanup_undo_files "pane") &
