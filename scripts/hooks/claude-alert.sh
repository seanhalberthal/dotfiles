#!/bin/bash
# Claude Code hook script: Set tmux alert when Claude needs attention
# Used by: Stop, PostToolUse (AskUserQuestion), PermissionRequest hooks

ALERTS_DIR="$HOME/.claude"
ALERTS_FILE="$ALERTS_DIR/alerts"

# Ensure ~/.claude directory exists with secure permissions
if [[ ! -d "$ALERTS_DIR" ]]; then
    mkdir -p "$ALERTS_DIR"
    chmod 700 "$ALERTS_DIR"
fi

# Get current tmux window identifier
WIN=$(tmux display-message -t "$TMUX_PANE" -p '#S:#W')

# Set the @claude_alert window option to indicate attention needed
tmux set-option -wt "$TMUX_PANE" @claude_alert 1 2>/dev/null

# Add window to alerts file if not already present
grep -qxF "$WIN" "$ALERTS_FILE" 2>/dev/null || echo "$WIN" >> "$ALERTS_FILE"

# Ring the terminal bell
printf '\a' > /dev/tty
