#!/usr/bin/env bash
set -euo pipefail

# Kill current pane with undo capability
# Saves pane state before killing for later restoration

SCRIPT_DIR="${BASH_SOURCE%/*}"
source "$SCRIPT_DIR/_lib/common.sh"
source "$SCRIPT_DIR/_lib/paths.sh"
source "$SCRIPT_DIR/_lib/session.sh"

require_tmux

# Get current state
CURRENT_SESSION=$(get_current_session)
CURRENT_WINDOW=$(get_current_window)
CURRENT_PANE=$(get_current_pane)
PANE_DIR=$(get_pane_directory)
WINDOW_LAYOUT=$(get_window_layout)

# Get undo file paths
UNDO_FILE=$(get_pane_undo_file)
UNDO_STATE=$(get_pane_undo_state)
UNDO_CONTENT=$(get_pane_undo_content)

# Clear previous undo data
cleanup_undo_files "pane"

# Save current state for undo
echo "${CURRENT_SESSION}:${CURRENT_WINDOW}.${CURRENT_PANE}" > "$UNDO_FILE"
chmod 600 "$UNDO_FILE"

# Save pane metadata
{
    echo "dir=$PANE_DIR"
    echo "layout=$WINDOW_LAYOUT"
} > "$UNDO_STATE"
chmod 600 "$UNDO_STATE"

# Capture pane contents
tmux capture-pane -p -S -32768 > "$UNDO_CONTENT" 2>/dev/null || true
chmod 600 "$UNDO_CONTENT"

# If this is the last pane in the last window, switch session first
if is_last_pane && is_last_window; then
    switch_to_other_session "$CURRENT_SESSION" || true
fi

# Kill the pane
tmux kill-pane -t "${CURRENT_SESSION}:${CURRENT_WINDOW}.${CURRENT_PANE}"
