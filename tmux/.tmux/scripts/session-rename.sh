#!/usr/bin/env bash
set -euo pipefail

# Rename current tmux session via fzf prompt

SCRIPT_DIR="${BASH_SOURCE%/*}"
source "$SCRIPT_DIR/_lib/common.sh"
source "$SCRIPT_DIR/_lib/session.sh"

require_tmux

current_session="${1:-$(get_current_session)}"

# Prompt for new name with current name as default
newname=$(printf '' | fzf \
    --print-query \
    --query="$current_session" \
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
    2>/dev/null | head -1) || true

# Handle empty input (user cancelled)
if [[ -z "$newname" ]]; then
    exit 0
fi

# No change needed
if [[ "$newname" == "$current_session" ]]; then
    exit 0
fi

# Validate session name
if ! validate_session_name "$newname"; then
    error "Invalid session name"
    exit 1
fi

# Check if target name already exists
if session_exists "$newname"; then
    error "Session '$newname' already exists"
    exit 1
fi

# Rename the session
tmux rename-session -t "$current_session" "$newname"
