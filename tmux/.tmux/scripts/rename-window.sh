#!/usr/bin/env bash
set -euo pipefail

# Rename window with spacebar converted to dash
# Uses fzf's print-query to get user input with custom key handling

SCRIPT_DIR="${BASH_SOURCE%/*}"
source "$SCRIPT_DIR/_lib/common.sh"
source "$SCRIPT_DIR/_lib/session.sh"

require_tmux

CURRENT_NAME=$(get_window_name)

# Use fzf as an input prompt - space inserts dash, enter confirms
# The --print-query outputs the query even with no matches
NEW_NAME=$(echo "" | fzf --reverse --no-info \
    --prompt "Rename: " \
    --query "$CURRENT_NAME" \
    --print-query \
    --bind 'enter:print-query' \
    --bind 'space:transform-query:echo {q}-' \
    --bind 'esc:abort' \
    --height 3 \
    --no-separator \
    --color 'bg+:-1' \
    2>/dev/null | head -1) || true

# If user provided a name, rename the window
if [[ -n "$NEW_NAME" ]]; then
    tmux rename-window "$NEW_NAME"
fi
