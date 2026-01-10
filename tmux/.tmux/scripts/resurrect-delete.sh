#!/usr/bin/env bash
# ══════════════════════════════════════════════════════════════
# resurrect-kill-session.sh
# ══════════════════════════════════════════════════════════════
# Kills a tmux session and removes its backup file.
#
# Usage:
#   resurrect-kill-session.sh <session-name>   # Kill session
#
# Session files are stored in: ~/.tmux/resurrect/sessions/
# ══════════════════════════════════════════════════════════════

set -euo pipefail

# Find where resurrect actually saves
if [[ -d "${HOME}/.tmux/resurrect/sessions" ]]; then
    RESURRECT_DIR="${HOME}/.tmux/resurrect"
elif [[ -d "${XDG_DATA_HOME:-$HOME/.local/share}/tmux/resurrect/sessions" ]]; then
    RESURRECT_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/tmux/resurrect"
else
    RESURRECT_DIR="${HOME}/.tmux/resurrect"
fi
SESSIONS_DIR="${RESURRECT_DIR}/sessions"

# Colours for output
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No colour

usage() {
    echo -e "${CYAN}Usage:${NC} $0 <session-name>"
    echo ""
    echo "Kills the specified tmux session and removes its backup file."
    exit 1
}

if [[ -z "${1:-}" ]]; then
    usage
fi

SESSION_NAME="$1"
SESSION_FILE="${SESSIONS_DIR}/${SESSION_NAME}.txt"

# Kill the session if it's running
if tmux has-session -t "${SESSION_NAME}" 2>/dev/null; then
    tmux kill-session -t "${SESSION_NAME}"
    echo -e "${GREEN}Killed session: ${SESSION_NAME}${NC}"
else
    echo -e "${YELLOW}Session not running: ${SESSION_NAME}${NC}"
fi

# Remove the backup file
if [[ -f "${SESSION_FILE}" ]]; then
    rm -f "${SESSION_FILE}"
    echo -e "${GREEN}Deleted session backup: ${SESSION_NAME}${NC}"
else
    echo -e "${YELLOW}No backup found for: ${SESSION_NAME}${NC}"
fi
