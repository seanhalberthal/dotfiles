#!/usr/bin/env bash
set -euo pipefail

# Duplicate current window with same layout, directories, and scrollback content
# Creates a new window that mirrors the current one's pane structure

SCRIPT_DIR="${BASH_SOURCE%/*}"
source "$SCRIPT_DIR/_lib/common.sh"
source "$SCRIPT_DIR/_lib/session.sh"

require_tmux

# Get current window info
CURRENT_SESSION=$(get_current_session)
CURRENT_WINDOW=$(get_current_window)
WINDOW_NAME=$(get_window_name)
WINDOW_LAYOUT=$(get_window_layout)
PANE_COUNT=$(get_pane_count)

# Create temp directory for pane data
TEMP_DIR=$(mktemp -d)
trap 'rm -rf "$TEMP_DIR"' EXIT

# Capture all pane info from current window
declare -a PANE_DIRS
declare -a PANE_IDS

# Get pane directories and IDs
while IFS=$'\t' read -r pane_index pane_dir pane_id; do
    PANE_DIRS+=("$pane_dir")
    PANE_IDS+=("$pane_id")
    # Capture scrollback content for each pane
    tmux capture-pane -p -S -32768 -t "$pane_id" > "$TEMP_DIR/pane_${pane_index}.txt" 2>/dev/null || true
done < <(tmux list-panes -t "${CURRENT_SESSION}:${CURRENT_WINDOW}" -F '#{pane_index}	#{pane_current_path}	#{pane_id}')

# Use first pane's directory for new window
FIRST_DIR="${PANE_DIRS[0]:-$HOME}"
[[ -d "$FIRST_DIR" ]] || FIRST_DIR="$HOME"

# Create new window with same name
tmux new-window -t "$CURRENT_SESSION" -n "$WINDOW_NAME" -c "$FIRST_DIR"
NEW_WINDOW=$(tmux display-message -p '#{window_index}')

# Create additional panes (we need PANE_COUNT - 1 splits)
for ((i = 1; i < PANE_COUNT; i++)); do
    dir="${PANE_DIRS[$i]:-$HOME}"
    [[ -d "$dir" ]] || dir="$HOME"
    tmux split-window -t "${CURRENT_SESSION}:${NEW_WINDOW}" -c "$dir"
done

# Apply the original layout
if [[ -n "$WINDOW_LAYOUT" ]]; then
    tmux select-layout -t "${CURRENT_SESSION}:${NEW_WINDOW}" "$WINDOW_LAYOUT" 2>/dev/null || true
fi

# Small delay for shells to be ready
sleep 0.1

# Display captured content in each pane
# Get the new pane IDs
mapfile -t NEW_PANE_IDS < <(tmux list-panes -t "${CURRENT_SESSION}:${NEW_WINDOW}" -F '#{pane_id}')

for ((i = 0; i < ${#NEW_PANE_IDS[@]}; i++)); do
    new_pane_id="${NEW_PANE_IDS[$i]}"
    content_file="$TEMP_DIR/pane_$((i + 1)).txt"
    dir="${PANE_DIRS[$i]:-$HOME}"
    [[ -d "$dir" ]] || dir="$HOME"

    # Escape paths to prevent command injection from special characters
    safe_file=$(printf '%q' "$content_file")
    safe_dir=$(printf '%q' "$dir")

    if [[ -f "$content_file" && -s "$content_file" ]]; then
        # Display content using cat, then cd to original directory
        tmux send-keys -t "$new_pane_id" "cat $safe_file; cd $safe_dir" Enter
    else
        # Just cd to the right directory
        tmux send-keys -t "$new_pane_id" "cd $safe_dir" Enter
    fi
done

# Keep temp files around briefly for cat to complete, then cleanup happens via trap
sleep 0.5
