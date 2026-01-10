#!/usr/bin/env bash
set -euo pipefail

# Dispatch undo command to appropriate script based on most recent deletion

SCRIPT_DIR="${BASH_SOURCE%/*}"
source "$SCRIPT_DIR/_lib/common.sh"
source "$SCRIPT_DIR/_lib/paths.sh"
source "$SCRIPT_DIR/_lib/ui.sh"

require_tmux

# Determine what was most recently deleted
undo_type=$(get_most_recent_undo_type)

case "$undo_type" in
    pane)
        exec "$SCRIPT_DIR/undo-pane.sh"
        ;;
    window)
        exec "$SCRIPT_DIR/undo-window.sh"
        ;;
    session)
        exec "$SCRIPT_DIR/session-undo.sh"
        ;;
    *)
        show_centered_message "Nothing to undo" \
            "" \
            "No recently deleted pane, window, or session found."
        sleep 2
        exit 0
        ;;
esac
