#!/usr/bin/env bash
# ══════════════════════════════════════════════════════════════
# resurrect-restore-session.sh
# ══════════════════════════════════════════════════════════════
# Restores a single tmux session from its individual backup file.
#
# This script works with per-session backup files created by
# resurrect-split-sessions.sh (the post-save hook). Unlike the
# built-in resurrect restore which restores ALL sessions at once,
# this allows restoring individual sessions independently.
#
# Usage:
#   resurrect-restore-session.sh <session-name>           # Restore session
#   resurrect-restore-session.sh <session-name> --replace # Kill existing first
#   resurrect-restore-session.sh <session-name> --delete  # Delete backup
#   resurrect-restore-session.sh --list                   # List backups
#
# Session files are stored in: ~/.tmux/resurrect/sessions/
# ══════════════════════════════════════════════════════════════

set -euo pipefail

# Find where resurrect actually saves (check for 'last' symlink or sessions dir)
if [[ -d "${HOME}/.tmux/resurrect/sessions" ]]; then
    RESURRECT_DIR="${HOME}/.tmux/resurrect"
elif [[ -d "${XDG_DATA_HOME:-$HOME/.local/share}/tmux/resurrect/sessions" ]]; then
    RESURRECT_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/tmux/resurrect"
else
    # Default to ~/.tmux/resurrect (where resurrect saves by default)
    RESURRECT_DIR="${HOME}/.tmux/resurrect"
fi
SESSIONS_DIR="${RESURRECT_DIR}/sessions"

# Colours for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No colour

usage() {
    echo -e "${CYAN}Usage:${NC} $0 <session-name> [--replace|--delete]"
    echo ""
    echo "Options:"
    echo "  --replace    Kill existing session with same name before restoring"
    echo "  --delete     Delete the saved session backup"
    echo "  --list       List available sessions"
    echo ""
    list_sessions
    exit 1
}

list_sessions() {
    if [[ ! -d "${SESSIONS_DIR}" ]] || [[ -z "$(ls -A "${SESSIONS_DIR}" 2>/dev/null)" ]]; then
        echo -e "${YELLOW}No session backups found.${NC}"
        echo "Run resurrect save (prefix + Ctrl-s) to create backups."
        return
    fi

    echo -e "${CYAN}Available session backups:${NC}"
    echo ""

    for f in "${SESSIONS_DIR}"/*.txt; do
        [[ -e "$f" ]] || continue
        session=$(basename "$f" .txt)
        windows=$(grep -c '^window' "$f" 2>/dev/null || echo 0)
        panes=$(grep -c '^pane' "$f" 2>/dev/null || echo 0)
        modified=$(stat -f "%Sm" -t "%Y-%m-%d %H:%M" "$f" 2>/dev/null || stat -c "%y" "$f" 2>/dev/null | cut -d. -f1)

        # Check if session currently exists
        if tmux has-session -t "${session}" 2>/dev/null; then
            status="${GREEN}[ACTIVE]${NC}"
        else
            status=""
        fi

        printf "  ${CYAN}%-20s${NC} %2d windows, %2d panes  (%s) %b\n" "${session}" "${windows}" "${panes}" "${modified}" "${status}"
    done
}

# Parse arguments
REPLACE=false
DELETE=false
SESSION_NAME=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --replace)
            REPLACE=true
            shift
            ;;
        --delete)
            DELETE=true
            shift
            ;;
        --list)
            list_sessions
            exit 0
            ;;
        --help|-h)
            usage
            ;;
        *)
            if [[ -z "${SESSION_NAME}" ]]; then
                SESSION_NAME="$1"
            else
                echo -e "${RED}Error: Unexpected argument: $1${NC}" >&2
                usage
            fi
            shift
            ;;
    esac
done

if [[ -z "${SESSION_NAME}" ]]; then
    usage
fi

SESSION_FILE="${SESSIONS_DIR}/${SESSION_NAME}.txt"

if [[ ! -f "${SESSION_FILE}" ]]; then
    echo -e "${RED}Error: Session file not found: ${SESSION_FILE}${NC}" >&2
    echo "Use --list to see available sessions."
    exit 1
fi

# Handle delete
if [[ "${DELETE}" == "true" ]]; then
    rm -f "${SESSION_FILE}"
    echo -e "${GREEN}Deleted session backup: ${SESSION_NAME}${NC}"
    exit 0
fi

# Check if session already exists
if tmux has-session -t "${SESSION_NAME}" 2>/dev/null; then
    if [[ "${REPLACE}" == "true" ]]; then
        echo -e "${YELLOW}Killing existing session: ${SESSION_NAME}${NC}"
        tmux kill-session -t "${SESSION_NAME}"
    else
        echo -e "${YELLOW}Session '${SESSION_NAME}' already running - switching to it${NC}"
        tmux switch-client -t "${SESSION_NAME}" 2>/dev/null || tmux attach-session -t "${SESSION_NAME}"
        exit 0
    fi
fi

# ─────────────────────────────────────────────────────────────
# Session Restoration (three-pass algorithm)
# ─────────────────────────────────────────────────────────────
# Pass 1: Create session, windows, and panes with working directories
# Pass 2: Apply window layouts and names
# Pass 3: Select the correct active pane in each window

# Delimiter for parsing (resurrect uses tab-separated values)
d=$'\t'

# Get base-index setting (windows may start at 0 or 1)
BASE_INDEX=$(tmux show -gv base-index 2>/dev/null || echo 0)

# Track state during restoration
SESSION_CREATED=false
declare -A WINDOWS_CREATED      # Track which windows have been created
declare -A WINDOW_PANE_COUNT    # Count panes per window

# ─────────────────────────────────────────
# Pass 1: Create session and panes
# ─────────────────────────────────────────
while IFS="${d}" read -r line_type sess_name window_number window_active window_flags pane_index pane_title dir pane_active pane_command pane_full_command rest; do
    [[ "${line_type}" == "pane" ]] || continue

    # Remove leading colon from dir if present
    dir="${dir#:}"
    # Expand tilde and handle escaped spaces
    dir="${dir/#\~/$HOME}"
    dir=$(echo -e "${dir}" | sed 's/\\ / /g')

    # Ensure directory exists, fallback to home
    if [[ ! -d "${dir}" ]]; then
        dir="${HOME}"
    fi

    if [[ "${SESSION_CREATED}" == "false" ]]; then
        # Create the session with first window
        tmux new-session -d -s "${SESSION_NAME}" -c "${dir}" 2>/dev/null || {
            # If we're inside tmux, need to handle differently
            TMUX="" tmux new-session -d -s "${SESSION_NAME}" -c "${dir}"
        }

        # Handle base-index - rename first window if needed
        FIRST_WIN="${BASE_INDEX}"
        if [[ "${window_number}" != "${FIRST_WIN}" ]]; then
            tmux move-window -s "${SESSION_NAME}:${FIRST_WIN}" -t "${SESSION_NAME}:${window_number}" 2>/dev/null || true
        fi

        WINDOWS_CREATED["${window_number}"]=1
        WINDOW_PANE_COUNT["${window_number}"]=1
        SESSION_CREATED=true
        continue
    fi

    # Check if window exists
    if [[ -z "${WINDOWS_CREATED[${window_number}]:-}" ]]; then
        # Create new window
        tmux new-window -d -t "${SESSION_NAME}:${window_number}" -c "${dir}"
        WINDOWS_CREATED["${window_number}"]=1
        WINDOW_PANE_COUNT["${window_number}"]=1
    else
        # Add pane to existing window (split)
        tmux split-window -t "${SESSION_NAME}:${window_number}" -c "${dir}"
        WINDOW_PANE_COUNT["${window_number}"]=$((WINDOW_PANE_COUNT["${window_number}"] + 1))
    fi

done < "${SESSION_FILE}"

# ─────────────────────────────────────────
# Pass 2: Apply window layouts and names
# ─────────────────────────────────────────
while IFS="${d}" read -r line_type sess_name window_number window_name window_active window_flags window_layout automatic_rename rest; do
    [[ "${line_type}" == "window" ]] || continue

    # Remove leading colon from window_name
    window_name="${window_name#:}"

    # Apply layout (may fail if pane count doesn't match, that's ok)
    tmux select-layout -t "${SESSION_NAME}:${window_number}" "${window_layout}" 2>/dev/null || true

    # Set window name
    if [[ -n "${window_name}" ]]; then
        tmux rename-window -t "${SESSION_NAME}:${window_number}" "${window_name}" 2>/dev/null || true
    fi

    # Handle automatic-rename option
    if [[ -n "${automatic_rename:-}" && "${automatic_rename}" != ":" ]]; then
        tmux set-option -t "${SESSION_NAME}:${window_number}" automatic-rename "${automatic_rename}" 2>/dev/null || true
    fi

done < "${SESSION_FILE}"

# ─────────────────────────────────────────
# Pass 3: Select active pane and window
# ─────────────────────────────────────────
while IFS="${d}" read -r line_type sess_name window_number window_active window_flags pane_index pane_title dir pane_active pane_command pane_full_command rest; do
    [[ "${line_type}" == "pane" ]] || continue
    [[ "${pane_active}" == "1" ]] || continue

    tmux select-pane -t "${SESSION_NAME}:${window_number}.${pane_index}" 2>/dev/null || true
done < "${SESSION_FILE}"

# Find and select active window
ACTIVE_WINDOW=$(awk -F'\t' '/^window/ && $4 == 1 { print $3; exit }' "${SESSION_FILE}")
if [[ -n "${ACTIVE_WINDOW}" ]]; then
    tmux select-window -t "${SESSION_NAME}:${ACTIVE_WINDOW}" 2>/dev/null || true
fi

echo -e "${GREEN}Restored session: ${SESSION_NAME}${NC}"
