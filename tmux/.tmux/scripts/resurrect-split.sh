#!/usr/bin/env bash
# ══════════════════════════════════════════════════════════════
# resurrect-split.sh
# ══════════════════════════════════════════════════════════════
# Post-save hook for tmux-resurrect.
#
# By default, tmux-resurrect saves ALL sessions to a single combined
# file. This hook runs after each save and splits that file into
# individual per-session files, enabling independent session restore.
#
# Called automatically via: @resurrect-hook-post-save-all
#
# Input:  ~/.tmux/resurrect/last (symlink to latest save)
# Output: ~/.tmux/resurrect/sessions/<session-name>.txt
#
# Also cleans up session files for sessions that no longer exist.
# ══════════════════════════════════════════════════════════════

set -euo pipefail

# Find where resurrect actually saves (check for 'last' symlink, not just directory)
if [[ -L "${HOME}/.tmux/resurrect/last" || -f "${HOME}/.tmux/resurrect/last" ]]; then
    RESURRECT_DIR="${HOME}/.tmux/resurrect"
elif [[ -L "${XDG_DATA_HOME:-$HOME/.local/share}/tmux/resurrect/last" || -f "${XDG_DATA_HOME:-$HOME/.local/share}/tmux/resurrect/last" ]]; then
    RESURRECT_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/tmux/resurrect"
else
    # Default to ~/.tmux/resurrect (where resurrect saves by default)
    RESURRECT_DIR="${HOME}/.tmux/resurrect"
fi
SESSIONS_DIR="${RESURRECT_DIR}/sessions"
LAST_FILE="${RESURRECT_DIR}/last"

# Ensure sessions directory exists
mkdir -p "${SESSIONS_DIR}"

# Get the actual save file (resolve symlink)
if [[ ! -L "${LAST_FILE}" ]] && [[ ! -f "${LAST_FILE}" ]]; then
    exit 0  # No save file yet, nothing to do
fi

if [[ -L "${LAST_FILE}" ]]; then
    SAVE_FILE=$(readlink -f "${LAST_FILE}")
else
    SAVE_FILE="${LAST_FILE}"
fi

if [[ ! -f "${SAVE_FILE}" ]]; then
    exit 0
fi

# ─────────────────────────────────────────
# Extract session names
# ─────────────────────────────────────────
# Resurrect save format: tab-separated values with session name in field 2
SESSIONS=$(awk -F'\t' '/^(pane|window)/ { print $2 }' "${SAVE_FILE}" | sort -u)

if [[ -z "${SESSIONS}" ]]; then
    exit 0
fi

# ─────────────────────────────────────────
# Split into per-session files
# ─────────────────────────────────────────
declare -A CURRENT_SESSIONS    # Track sessions saved this run

for session in ${SESSIONS}; do
    SESSION_FILE="${SESSIONS_DIR}/${session}.txt"
    CURRENT_SESSIONS["${session}"]=1

    # Extract all lines belonging to this session (pane, window, grouped_session)
    awk -F'\t' -v sess="${session}" '
        /^pane/ && $2 == sess { print }
        /^window/ && $2 == sess { print }
        /^grouped_session/ && $2 == sess { print }
    ' "${SAVE_FILE}" > "${SESSION_FILE}"
done

# ─────────────────────────────────────────
# Cleanup: remove orphaned session files
# ─────────────────────────────────────────
# Delete backup files for sessions that no longer exist
for existing_file in "${SESSIONS_DIR}"/*.txt; do
    [[ -e "${existing_file}" ]] || continue
    session_name=$(basename "${existing_file}" .txt)
    if [[ -z "${CURRENT_SESSIONS[${session_name}]:-}" ]]; then
        rm -f "${existing_file}"
    fi
done

# ─────────────────────────────────────────
# Cleanup: remove old resurrect save files
# ─────────────────────────────────────────
# Keep only the 20 most recent saves to prevent unbounded growth
KEEP_SAVES=20
SAVE_FILES=$(ls -t "${RESURRECT_DIR}"/tmux_resurrect_*.txt 2>/dev/null | tail -n +$((KEEP_SAVES + 1)))
if [[ -n "${SAVE_FILES}" ]]; then
    echo "${SAVE_FILES}" | xargs rm -f
fi
