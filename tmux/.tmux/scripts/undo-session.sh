#!/usr/bin/env bash
# ══════════════════════════════════════════════════════════════
# undo-session.sh
# ══════════════════════════════════════════════════════════════
# Restores the last killed session from its preserved backup.
# Silent version for use with global ⌥u binding.
#
# Usage: undo-session.sh
# ══════════════════════════════════════════════════════════════

set -euo pipefail

UNDO_FILE="/tmp/tmux-undo-session"
SESSIONS_DIR="${HOME}/.tmux/resurrect/sessions"

# Check if there's something to undo
[[ ! -f "$UNDO_FILE" ]] && exit 0

SESSION_NAME=$(cat "$UNDO_FILE")
BACKUP_UNDO="/tmp/tmux-undo-${SESSION_NAME}.txt"

# Check if backup exists
[[ ! -f "$BACKUP_UNDO" ]] && { rm -f "$UNDO_FILE"; exit 0; }

# Ensure sessions directory exists
mkdir -p "$SESSIONS_DIR"

# Restore the backup to proper location
cp "$BACKUP_UNDO" "${SESSIONS_DIR}/${SESSION_NAME}.txt"

# Restore the session using existing script
"${HOME}/.tmux/scripts/resurrect-restore.sh" "$SESSION_NAME" >/dev/null 2>&1 || true

# Cleanup undo data
rm -f "$UNDO_FILE" "$BACKUP_UNDO"

# Show notification
tmux display-message "Restored session: ${SESSION_NAME}"
