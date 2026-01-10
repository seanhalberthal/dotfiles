#!/bin/bash
# Create a new session from the fzf session switcher
# Usage: session-new.sh

# Use fzf as a styled input field with escape support
newname=$(printf '' | fzf \
    --print-query \
    --query='' \
    --prompt='New session: ' \
    --height=100% \
    --layout=reverse \
    --border=rounded \
    --border-label=' ⏎ create · esc cancel ' \
    --border-label-pos=bottom \
    --no-info \
    --pointer=' ' \
    --bind 'enter:print-query' \
    --bind 'esc:abort' \
    2>/dev/null | head -1)

if [[ -n "$newname" ]]; then
    # Check if session already exists
    if tmux has-session -t "$newname" 2>/dev/null; then
        # Session exists, switch to it
        tmux switch-client -t "$newname"
    else
        # Create new session at home directory and switch to it
        tmux new-session -d -s "$newname" -c ~
        tmux switch-client -t "$newname"
    fi
fi
