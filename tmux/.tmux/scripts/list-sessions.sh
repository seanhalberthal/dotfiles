#!/bin/bash
# List tmux sessions with Claude alert indicators
# Used by the session switcher (prefix + s)

ALERTS_FILE="$HOME/.claude/alerts"

tmux list-sessions -F '#{session_activity} #{session_name}' | sort -rn | cut -d' ' -f2-
