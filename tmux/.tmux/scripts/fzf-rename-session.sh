#!/bin/bash
# Rename a session from the fzf session switcher
# Usage: fzf-rename-session.sh <session-name>

session="$1"

# Use fzf as a styled input field with escape support
newname=$(printf '' | fzf \
    --print-query \
    --query="$session" \
    --prompt='Rename session: ' \
    --height=100% \
    --layout=reverse \
    --border=rounded \
    --border-label=' ⏎ rename · esc cancel ' \
    --border-label-pos=bottom \
    --no-info \
    --pointer=' ' \
    --bind 'enter:print-query' \
    --bind 'esc:abort' \
    2>/dev/null | head -1)

if [[ -n "$newname" && "$newname" != "$session" ]]; then
    tmux rename-session -t "$session" "$newname"
fi
