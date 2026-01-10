#!/usr/bin/env bash
set -euo pipefail

# Kill a tmux session with confirmation dialog and undo capability

SCRIPT_DIR="${BASH_SOURCE%/*}"
source "$SCRIPT_DIR/_lib/common.sh"
source "$SCRIPT_DIR/_lib/ui.sh"
source "$SCRIPT_DIR/_lib/paths.sh"
source "$SCRIPT_DIR/_lib/session.sh"

require_tmux

SESSION_NAME="${1:-}"
[[ -z "$SESSION_NAME" ]] && exit 1

# Get the current session (the one the client is attached to)
CURRENT_SESSION=$(get_current_session)

# Prevent killing the last session
if is_last_session; then
    show_centered_message "Cannot kill session" \
        "" \
        "This is the only session." \
        "Create another session first."
    sleep 2
    exit 1
fi

# Show confirmation dialog
if ! show_centered_confirm "Kill session: $SESSION_NAME" \
    "This will close all windows and panes in this session."; then
    exit 0
fi

# Get undo paths
UNDO_FILE=$(get_session_undo_file)
BACKUP_SRC="${HOME}/.tmux/resurrect/sessions/${SESSION_NAME}.txt"
UNDO_BACKUP=$(get_session_undo_backup)

# Clear previous undo data
cleanup_undo_files "session"

# Save session name for undo
echo "$SESSION_NAME" > "$UNDO_FILE"
chmod 600 "$UNDO_FILE"

# Force a save to ensure we have current state
~/.tmux/plugins/tmux-resurrect/scripts/save.sh >/dev/null 2>&1 || true
~/.tmux/scripts/resurrect-split.sh >/dev/null 2>&1 || true

# Preserve backup before kill triggers cleanup
if [[ -f "$BACKUP_SRC" ]]; then
    cp "$BACKUP_SRC" "$UNDO_BACKUP"
    chmod 600 "$UNDO_BACKUP"
fi

# If killing the current session, switch to another first
if [[ "$SESSION_NAME" == "$CURRENT_SESSION" ]]; then
    if ! switch_to_other_session "$SESSION_NAME"; then
        error "Failed to find another session to switch to"
        exit 1
    fi
fi

# Kill the session
tmux kill-session -t "$SESSION_NAME" 2>/dev/null || true
