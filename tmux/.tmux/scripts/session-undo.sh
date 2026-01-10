#!/usr/bin/env bash
# ══════════════════════════════════════════════════════════════
# session-undo.sh
# ══════════════════════════════════════════════════════════════
# Restores the last killed session from its preserved backup.
# Called from fzf session switcher when user presses ⌥u.
#
# Usage: session-undo.sh
# ══════════════════════════════════════════════════════════════

set -euo pipefail

UNDO_FILE="/tmp/tmux-undo-session"
SESSIONS_DIR="${HOME}/.tmux/resurrect/sessions"

# Get terminal dimensions for centered display
term_height=$(tput lines)
term_width=$(tput cols)
box_height=6
box_width=40

v_pad=$(( (term_height - box_height) / 2 ))
[[ $v_pad -lt 0 ]] && v_pad=0
h_pad=$(( (term_width - box_width) / 2 ))
[[ $h_pad -lt 0 ]] && h_pad=0
pad=$(printf '%*s' "$h_pad" '')

show_message() {
    local color="$1"
    local message="$2"
    clear
    for ((i=0; i<v_pad; i++)); do printf '\n'; done
    printf '%s\033[38;5;%sm╭──────────────────────────────────────╮\033[0m\n' "$pad" "$color"
    printf '%s\033[38;5;%sm│\033[0m %-36s \033[38;5;%sm│\033[0m\n' "$pad" "$color" "$message" "$color"
    printf '%s\033[38;5;%sm╰──────────────────────────────────────╯\033[0m\n' "$pad" "$color"
    printf '\n'
    printf '%s\033[38;5;245mPress any key to continue...\033[0m' "$pad"
    read -n1 -s
}

# Check if there's something to undo
if [[ ! -f "$UNDO_FILE" ]]; then
    show_message "245" "No session to restore"
    exit 0
fi

SESSION_NAME=$(cat "$UNDO_FILE")
BACKUP_UNDO="/tmp/tmux-undo-${SESSION_NAME}.txt"

# Check if backup exists
if [[ ! -f "$BACKUP_UNDO" ]]; then
    rm -f "$UNDO_FILE"
    show_message "203" "Backup not found: $SESSION_NAME"
    exit 0
fi

# Ensure sessions directory exists
mkdir -p "$SESSIONS_DIR"

# Restore the backup to proper location
cp "$BACKUP_UNDO" "${SESSIONS_DIR}/${SESSION_NAME}.txt"

# Restore the session using existing script
if "${HOME}/.tmux/scripts/resurrect-restore.sh" "$SESSION_NAME" 2>&1; then
    show_message "84" "Restored: $SESSION_NAME"
else
    show_message "203" "Failed to restore: $SESSION_NAME"
fi

# Cleanup undo data
rm -f "$UNDO_FILE" "$BACKUP_UNDO"
