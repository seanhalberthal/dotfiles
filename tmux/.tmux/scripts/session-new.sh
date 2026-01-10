#!/usr/bin/env bash
set -euo pipefail

# Create a new tmux session via fzf prompt

SCRIPT_DIR="${BASH_SOURCE%/*}"
source "$SCRIPT_DIR/_lib/common.sh"

require_tmux

# Prompt for session name
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
    2>/dev/null | head -1) || true

# Handle empty input (user cancelled)
if [[ -z "$newname" ]]; then
    exit 0
fi

# Validate session name
if ! validate_session_name "$newname"; then
    error "Invalid session name"
    exit 1
fi

# Check if session already exists
if session_exists "$newname"; then
    # Session exists, switch to it
    tmux switch-client -t "$newname"
else
    # Create new session at home directory and switch to it
    tmux new-session -d -s "$newname" -c ~
    tmux switch-client -t "$newname"
fi
