#!/usr/bin/env bash
set -euo pipefail

# Restore the last killed session from its preserved backup

SCRIPT_DIR="${BASH_SOURCE%/*}"
source "$SCRIPT_DIR/_lib/common.sh"
source "$SCRIPT_DIR/_lib/paths.sh"
source "$SCRIPT_DIR/_lib/ui.sh"

# Get undo file paths
UNDO_FILE=$(get_session_undo_file)
UNDO_BACKUP=$(get_session_undo_backup)
SESSIONS_DIR="${HOME}/.tmux/resurrect/sessions"

# Check if there's something to undo
if [[ ! -f "$UNDO_FILE" ]]; then
    show_centered_message "No session to restore" \
        "" \
        "No recently killed session found."
    sleep 2
    exit 0
fi

SESSION_NAME=$(cat "$UNDO_FILE")

# Check if backup exists
if [[ ! -f "$UNDO_BACKUP" ]]; then
    cleanup_undo_files "session"
    show_centered_message "Backup not found" \
        "" \
        "Backup for '$SESSION_NAME' not found."
    sleep 2
    exit 0
fi

# Ensure sessions directory exists
mkdir -p "$SESSIONS_DIR"

# Restore the backup to proper location
cp "$UNDO_BACKUP" "${SESSIONS_DIR}/${SESSION_NAME}.txt"
chmod 600 "${SESSIONS_DIR}/${SESSION_NAME}.txt"

# Restore the session using existing script
if "${HOME}/.tmux/scripts/resurrect-restore.sh" "$SESSION_NAME" 2>&1; then
    show_centered_message "Session restored" \
        "" \
        "Restored: $SESSION_NAME"
    sleep 1
else
    show_centered_message "Restore failed" \
        "" \
        "Failed to restore: $SESSION_NAME"
    sleep 2
fi

# Cleanup undo data
cleanup_undo_files "session"
