#!/bin/bash
# Clear Claude alert for the current window
# Called by after-select-window hook and window/session switchers

SESSION="$1"
WINDOW="$2"
WINDOW_ID="$3"

ALERTS_FILE="$HOME/.claude/alerts"

# If format strings weren't expanded (display-popup doesn't expand them),
# get the values directly from tmux
if [[ "$SESSION" == '#{session_name}' ]] || [[ -z "$SESSION" ]]; then
    SESSION=$(tmux display-message -p '#S')
    WINDOW=$(tmux display-message -p '#W')
    WINDOW_ID=$(tmux display-message -p '#D')
fi

# Validate session and window names to prevent injection attacks
# Only allow alphanumeric characters, dots, underscores, and hyphens
if [[ ! "$SESSION" =~ ^[a-zA-Z0-9._-]+$ ]] || [[ ! "$WINDOW" =~ ^[a-zA-Z0-9._-]+$ ]]; then
    exit 1
fi

# Unset the window option (target specific window)
tmux set-option -wt "${SESSION}:${WINDOW}" -u @claude_alert 2>/dev/null

# Remove from alerts file (using grep for portability across macOS/Linux)
if [[ -f "$ALERTS_FILE" ]]; then
    grep -v "^${SESSION}:${WINDOW}$" "$ALERTS_FILE" > "${ALERTS_FILE}.tmp" 2>/dev/null && \
        mv "${ALERTS_FILE}.tmp" "$ALERTS_FILE" || rm -f "${ALERTS_FILE}.tmp"
fi

# Update timestamp for window sorting
~/.tmux/scripts/timestamp.sh "$WINDOW_ID"
