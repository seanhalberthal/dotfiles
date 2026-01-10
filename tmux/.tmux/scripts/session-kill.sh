#!/usr/bin/env bash
# ══════════════════════════════════════════════════════════════
# session-kill.sh
# ══════════════════════════════════════════════════════════════
# Kills a tmux session but preserves its backup for undo.
# Called from fzf session switcher when user presses Ctrl+x.
#
# Features:
#   - y/n confirmation before deleting
#   - Auto-switches to another session if killing the current one
#
# Usage: session-kill.sh <session-name>
# ══════════════════════════════════════════════════════════════

set -euo pipefail

SESSION_NAME="${1:-}"
[[ -z "$SESSION_NAME" ]] && exit 1

# Get the current session (the one the client is attached to)
CURRENT_SESSION=$(tmux display-message -p '#S')

# Get terminal dimensions
term_height=$(tput lines)
term_width=$(tput cols)

# Box dimensions (5 lines for box + 2 for spacing + 1 for prompt = 8 total)
box_height=8
box_width=39

# Calculate vertical padding
v_pad=$(( (term_height - box_height) / 2 ))
[[ $v_pad -lt 0 ]] && v_pad=0

# Calculate horizontal padding
h_pad=$(( (term_width - box_width) / 2 ))
[[ $h_pad -lt 0 ]] && h_pad=0
pad=$(printf '%*s' "$h_pad" '')

# Clear screen and print centered dialog
clear
for ((i=0; i<v_pad; i++)); do printf '\n'; done

printf '%s\033[38;5;203m╭─────────────────────────────────────╮\033[0m\n' "$pad"
printf '%s\033[38;5;203m│\033[0m                                     \033[38;5;203m│\033[0m\n' "$pad"
printf '%s\033[38;5;203m│\033[0m   \033[38;5;203mDelete session\033[0m \033[1;37m%-18s\033[0m \033[38;5;203m│\033[0m\n' "$pad" "'$SESSION_NAME'"
printf '%s\033[38;5;203m│\033[0m                                     \033[38;5;203m│\033[0m\n' "$pad"
printf '%s\033[38;5;203m╰─────────────────────────────────────╯\033[0m\n' "$pad"
printf '\n'
printf '%s\033[38;5;245mConfirm?\033[0m [\033[38;5;84my\033[0m/\033[38;5;203mN\033[0m] ' "$pad"
read -r -n1 CONFIRM
echo

if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
    exit 0
fi

UNDO_FILE="/tmp/tmux-undo-session"
BACKUP_SRC="${HOME}/.tmux/resurrect/sessions/${SESSION_NAME}.txt"
BACKUP_UNDO="/tmp/tmux-undo-${SESSION_NAME}.txt"

# Clear previous undo data
rm -f /tmp/tmux-undo-*.txt 2>/dev/null || true

# Save session name for undo
echo "$SESSION_NAME" > "$UNDO_FILE"

# Force a save to ensure we have current state
~/.tmux/plugins/tmux-resurrect/scripts/save.sh >/dev/null 2>&1 || true
~/.tmux/scripts/resurrect-split.sh >/dev/null 2>&1 || true

# Preserve backup before kill triggers cleanup
[[ -f "$BACKUP_SRC" ]] && cp "$BACKUP_SRC" "$BACKUP_UNDO"

# If killing the current session, switch to another first
if [[ "$SESSION_NAME" == "$CURRENT_SESSION" ]]; then
    # Find another session to switch to (most recently used, excluding the one we're killing)
    OTHER_SESSION=$(tmux list-sessions -F '#{session_activity} #{session_name}' | \
        sort -rn | cut -d' ' -f2- | grep -v "^${SESSION_NAME}$" | head -n1)

    if [[ -n "$OTHER_SESSION" ]]; then
        tmux switch-client -t "$OTHER_SESSION"
    fi
fi

# Kill the session
tmux kill-session -t "$SESSION_NAME" 2>/dev/null || true
