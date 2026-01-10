#!/usr/bin/env bash
set -euo pipefail

# Restore the last killed window from its preserved state

SCRIPT_DIR="${BASH_SOURCE%/*}"
source "$SCRIPT_DIR/_lib/common.sh"
source "$SCRIPT_DIR/_lib/paths.sh"

# Get undo file paths
UNDO_FILE=$(get_window_undo_file)
UNDO_STATE=$(get_window_undo_state)
UNDO_CONTENTS_DIR=$(get_window_undo_contents_dir)

# Check if there's something to undo
[[ ! -f "$UNDO_FILE" ]] && exit 0
[[ ! -f "$UNDO_STATE" ]] && { rm -f "$UNDO_FILE"; exit 0; }

WINDOW_TARGET=$(cat "$UNDO_FILE")
SESSION_NAME="${WINDOW_TARGET%%:*}"
WINDOW_INDEX="${WINDOW_TARGET#*:}"

# Check if session still exists
if ! tmux has-session -t "$SESSION_NAME" 2>/dev/null; then
    # Session gone - clean up and exit
    cleanup_undo_files "window"
    exit 0
fi

# Check if window index is already taken
if tmux list-windows -t "$SESSION_NAME" -F '#{window_index}' | grep -q "^${WINDOW_INDEX}$"; then
    # Window index exists - find next available
    WINDOW_INDEX=$(tmux list-windows -t "$SESSION_NAME" -F '#{window_index}' | sort -n | tail -1)
    WINDOW_INDEX=$((WINDOW_INDEX + 1))
fi

# Tab delimiter
d=$'\t'

# Read window info
WINDOW_LINE=$(grep "^window${d}" "$UNDO_STATE" | head -1)
WINDOW_NAME=$(echo "$WINDOW_LINE" | cut -d"$d" -f4 | sed 's/^://')
WINDOW_LAYOUT=$(echo "$WINDOW_LINE" | cut -d"$d" -f7)

# Get first pane's directory
FIRST_DIR=$(grep "^pane${d}" "$UNDO_STATE" | head -1 | cut -d"$d" -f8 | sed 's/^://' | sed 's/\\ / /g')
FIRST_DIR="${FIRST_DIR/#\~/$HOME}"
[[ -d "$FIRST_DIR" ]] || FIRST_DIR="$HOME"

# Create the window
tmux new-window -t "${SESSION_NAME}:${WINDOW_INDEX}" -n "$WINDOW_NAME" -c "$FIRST_DIR"

# Create additional panes if needed
grep "^pane${d}" "$UNDO_STATE" | tail -n +2 | while IFS="$d" read -r _ _ _ _ _ _pane_index _pane_title pane_dir _pane_active _pane_cmd _; do
    # Get directory
    dir="${pane_dir#:}"
    dir="${dir/#\~/$HOME}"
    dir=$(echo -e "$dir" | sed 's/\\ / /g')
    [[ -d "$dir" ]] || dir="$HOME"

    # Split to create new pane
    tmux split-window -t "${SESSION_NAME}:${WINDOW_INDEX}" -c "$dir"
done

# Apply layout
if [[ -n "$WINDOW_LAYOUT" ]]; then
    tmux select-layout -t "${SESSION_NAME}:${WINDOW_INDEX}" "$WINDOW_LAYOUT" 2>/dev/null || true
fi

# Get list of old pane indices in order
mapfile -t OLD_PANE_INDICES < <(grep "^pane${d}" "$UNDO_STATE" | cut -d"$d" -f6)

# Get pane-base-index (usually 0 or 1)
PANE_BASE=$(tmux show -gv pane-base-index 2>/dev/null || echo 0)

# Wait for shell to be ready before sending commands
sleep 0.1

# Restore pane contents to each pane
for i in "${!OLD_PANE_INDICES[@]}"; do
    OLD_PANE_INDEX="${OLD_PANE_INDICES[$i]}"
    NEW_PANE_IDX=$((PANE_BASE + i))
    CONTENT_FILE="${UNDO_CONTENTS_DIR}/pane-${OLD_PANE_INDEX}.txt"

    if [[ -f "$CONTENT_FILE" && -s "$CONTENT_FILE" ]]; then
        # Display saved content in the pane
        tmux send-keys -t "${SESSION_NAME}:${WINDOW_INDEX}.${NEW_PANE_IDX}" "cat '${CONTENT_FILE}'" Enter
    fi
done

# Find which new pane index corresponds to the originally active pane
ACTIVE_OLD_IDX=$(grep "^pane${d}" "$UNDO_STATE" | awk -F"$d" '$9 == "1" { print $6; exit }')
if [[ -n "$ACTIVE_OLD_IDX" ]]; then
    for i in "${!OLD_PANE_INDICES[@]}"; do
        if [[ "${OLD_PANE_INDICES[$i]}" == "$ACTIVE_OLD_IDX" ]]; then
            NEW_PANE_IDX=$((PANE_BASE + i))
            tmux select-pane -t "${SESSION_NAME}:${WINDOW_INDEX}.${NEW_PANE_IDX}" 2>/dev/null || true
            break
        fi
    done
fi

# Delayed cleanup (let cat finish first)
(sleep 1 && cleanup_undo_files "window") &
