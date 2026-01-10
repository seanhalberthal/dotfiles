#!/usr/bin/env bash
set -euo pipefail

# Kill current window with undo capability
# Saves all pane states before killing for later restoration

SCRIPT_DIR="${BASH_SOURCE%/*}"
source "$SCRIPT_DIR/_lib/common.sh"
source "$SCRIPT_DIR/_lib/paths.sh"
source "$SCRIPT_DIR/_lib/session.sh"

require_tmux

# Get current state
CURRENT_SESSION=$(get_current_session)
CURRENT_WINDOW=$(get_current_window)
WINDOW_LAYOUT=$(get_window_layout)

# Get undo file paths
UNDO_FILE=$(get_window_undo_file)
UNDO_STATE=$(get_window_undo_state)
UNDO_CONTENTS_DIR=$(get_window_undo_contents_dir)

# Clear previous undo data and recreate directory
cleanup_undo_files "window"

# Tab delimiter for state file
d=$'\t'

# Save window target
echo "${CURRENT_SESSION}:${CURRENT_WINDOW}" > "$UNDO_FILE"
chmod 600 "$UNDO_FILE"

# Get window info
WINDOW_NAME=$(tmux display-message -p '#{window_name}')
WINDOW_ACTIVE=$(tmux display-message -p '#{window_active}')
WINDOW_FLAGS=$(tmux display-message -p '#{window_flags}')
AUTO_RENAME=$(tmux show-window-option -v automatic-rename 2>/dev/null || echo "on")

# Write window line
echo "window${d}${CURRENT_SESSION}${d}${CURRENT_WINDOW}${d}:${WINDOW_NAME}${d}${WINDOW_ACTIVE}${d}${WINDOW_FLAGS}${d}${WINDOW_LAYOUT}${d}${AUTO_RENAME}" > "$UNDO_STATE"
chmod 600 "$UNDO_STATE"

# Get pane info for each pane
while IFS='|' read -r pane_index pane_title pane_dir pane_active pane_cmd; do
    # Escape spaces in path
    escaped_dir="${pane_dir// /\\ }"

    # Write pane line
    echo "pane${d}${CURRENT_SESSION}${d}${CURRENT_WINDOW}${d}${WINDOW_ACTIVE}${d}${WINDOW_FLAGS}${d}${pane_index}${d}${pane_title}${d}:${escaped_dir}${d}${pane_active}${d}${pane_cmd}${d}:" >> "$UNDO_STATE"

    # Capture pane contents
    tmux capture-pane -t "${CURRENT_SESSION}:${CURRENT_WINDOW}.${pane_index}" -p -S -32768 \
        > "$UNDO_CONTENTS_DIR/pane-${pane_index}.txt" 2>/dev/null || true
    chmod 600 "$UNDO_CONTENTS_DIR/pane-${pane_index}.txt"
done < <(tmux list-panes -F '#{pane_index}|#{pane_title}|#{pane_current_path}|#{pane_active}|#{pane_current_command}')

# If this is the last window, switch session first
if is_last_window; then
    switch_to_other_session "$CURRENT_SESSION" || true
fi

# Kill the window
tmux kill-window -t "${CURRENT_SESSION}:${CURRENT_WINDOW}"
