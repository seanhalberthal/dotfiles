#!/bin/bash
# Claude Code hook script: Clear tmux alert when user submits a prompt
# Used by: UserPromptSubmit hook

# Get current tmux window identifier
WIN=$(tmux display-message -t "$TMUX_PANE" -p '#S:#W')

# Unset the @claude_alert window option
tmux set-option -wt "$TMUX_PANE" -u @claude_alert 2>/dev/null

# Remove window from alerts file
sed -i '' "\|^${WIN}$|d" ~/.claude/alerts 2>/dev/null

# Refresh tmux status line
tmux refresh-client -S 2>/dev/null
