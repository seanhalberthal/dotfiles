#!/usr/bin/env bash
# ══════════════════════════════════════════════════════════════
# undo-dispatch.sh
# ══════════════════════════════════════════════════════════════
# Restores the last killed pane, window, or session - whichever
# was most recent.
#
# Usage: undo-dispatch.sh
# ══════════════════════════════════════════════════════════════

set -euo pipefail

PANE_UNDO="/tmp/tmux-undo-pane"
WINDOW_UNDO="/tmp/tmux-undo-window"
SESSION_UNDO="/tmp/tmux-undo-session"

# Get modification times (0 if file doesn't exist)
get_mtime() {
    [[ -f "$1" ]] || { echo 0; return; }
    stat -f %m "$1" 2>/dev/null || stat -c %Y "$1" 2>/dev/null || echo 0
}

PANE_TIME=$(get_mtime "$PANE_UNDO")
WINDOW_TIME=$(get_mtime "$WINDOW_UNDO")
SESSION_TIME=$(get_mtime "$SESSION_UNDO")

# If none exist, nothing to undo
if [[ "$PANE_TIME" -eq 0 && "$WINDOW_TIME" -eq 0 && "$SESSION_TIME" -eq 0 ]]; then
    exit 0
fi

# Find the most recent and execute its undo script
if [[ "$PANE_TIME" -ge "$WINDOW_TIME" && "$PANE_TIME" -ge "$SESSION_TIME" && "$PANE_TIME" -gt 0 ]]; then
    exec ~/.tmux/scripts/undo-pane.sh
elif [[ "$WINDOW_TIME" -ge "$PANE_TIME" && "$WINDOW_TIME" -ge "$SESSION_TIME" && "$WINDOW_TIME" -gt 0 ]]; then
    exec ~/.tmux/scripts/undo-window.sh
elif [[ "$SESSION_TIME" -gt 0 ]]; then
    exec ~/.tmux/scripts/undo-session.sh
fi
