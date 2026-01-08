#!/usr/bin/env bash
# ══════════════════════════════════════════════════════════════
# fzf-kill-session.sh
# ══════════════════════════════════════════════════════════════
# Kills a tmux session but preserves its backup for undo.
# Called from fzf session switcher when user presses Ctrl+x.
#
# Usage: fzf-kill-session.sh <session-name>
# ══════════════════════════════════════════════════════════════

set -euo pipefail

SESSION_NAME="${1:-}"
[[ -z "$SESSION_NAME" ]] && exit 1

UNDO_FILE="/tmp/tmux-undo-session"
BACKUP_SRC="${HOME}/.tmux/resurrect/sessions/${SESSION_NAME}.txt"
BACKUP_UNDO="/tmp/tmux-undo-${SESSION_NAME}.txt"

# Clear previous undo data
rm -f /tmp/tmux-undo-*.txt 2>/dev/null || true

# Save session name for undo
echo "$SESSION_NAME" > "$UNDO_FILE"

# Preserve backup before kill triggers cleanup
[[ -f "$BACKUP_SRC" ]] && cp "$BACKUP_SRC" "$BACKUP_UNDO"

# Kill the session
tmux kill-session -t "$SESSION_NAME" 2>/dev/null || true
