#!/usr/bin/env bash
# ══════════════════════════════════════════════════════════════
# split-resurrect.sh
# ══════════════════════════════════════════════════════════════
# post-save hook for tmux-resurrect.
#
# by default, tmux-resurrect saves ALL sessions to a single combined
# file. this hook runs after each save and splits that file into
# individual per-session files, enabling independent session restore.
#
# called automatically via: @resurrect-hook-post-save-all
#
# input:  ~/.tmux/resurrect/last (symlink to latest save)
# output: ~/.tmux/resurrect/sessions/<session-name>.txt
#
# also cleans up session files for sessions that no longer exist
# ══════════════════════════════════════════════════════════════

set -euo pipefail

# source path utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../_lib/paths.sh"

# get the resurrect directories using shared functions
RESURRECT_DIR=$(get_resurrect_dir)
SESSIONS_DIR=$(get_resurrect_sessions_dir)
LAST_FILE="${RESURRECT_DIR}/last"

# ensure sessions directory exists
mkdir -p "${SESSIONS_DIR}"

# get file modification time (cross-platform)
get_file_mtime() {
    local file="$1"
    if [[ "$(uname)" == "Darwin" ]]; then
        stat -f %m "$file" 2>/dev/null || echo 0
    else
        stat -c %Y "$file" 2>/dev/null || echo 0
    fi
}

# get the actual save file (resolve symlink)
if [[ ! -L "${LAST_FILE}" ]] && [[ ! -f "${LAST_FILE}" ]]; then
    exit 0 # no save file yet, nothing to do
fi

if [[ -L "${LAST_FILE}" ]]; then
    # use realpath if available, otherwise use readlink (macOS compatible)
    if command -v realpath >/dev/null 2>&1; then
        SAVE_FILE=$(realpath "${LAST_FILE}" 2>/dev/null) || exit 0
    else
        # macOS readlink doesn't support -f, so manually resolve
        SAVE_FILE=$(readlink "${LAST_FILE}" 2>/dev/null) || exit 0
        # if relative path, make it absolute
        if [[ "${SAVE_FILE}" != /* ]]; then
            SAVE_FILE="${RESURRECT_DIR}/${SAVE_FILE}"
        fi
    fi
else
    SAVE_FILE="${LAST_FILE}"
fi

if [[ ! -f "${SAVE_FILE}" ]]; then
    exit 0
fi

# ─────────────────────────────────────────
# extract session names
# ─────────────────────────────────────────
# resurrect save format: tab-separated values with session name in field 2
SESSIONS=$(awk -F'\t' '/^(pane|window)/ { print $2 }' "${SAVE_FILE}" | sort -u)

if [[ -z "${SESSIONS}" ]]; then
    exit 0
fi

# ─────────────────────────────────────────
# split into per-session files
# ─────────────────────────────────────────
# track sessions saved this run (bash 3.2 compatible, no associative arrays)
CURRENT_SESSIONS_LIST=""

for session in ${SESSIONS}; do
    SESSION_FILE="${SESSIONS_DIR}/${session}.txt"
    CURRENT_SESSIONS_LIST="$CURRENT_SESSIONS_LIST $session "

    # extract all lines belonging to this session (pane, window, grouped_session)
    awk -F'\t' -v sess="${session}" '
        /^pane/ && $2 == sess { print }
        /^window/ && $2 == sess { print }
        /^grouped_session/ && $2 == sess { print }
    ' "${SAVE_FILE}" >"${SESSION_FILE}"
done

# ─────────────────────────────────────────
# cleanup: remove orphaned session files
# ─────────────────────────────────────────
# delete backup files for sessions that no longer exist,
# but skip files that are newer than the save file we just processed
# (these may have been restored by undo and shouldn't be deleted)
SAVE_FILE_TIME=$(get_file_mtime "${SAVE_FILE}")

for existing_file in "${SESSIONS_DIR}"/*.txt; do
    [[ -e "${existing_file}" ]] || continue
    session_name=$(basename "${existing_file}" .txt)
    # check if session is in current sessions list (bash 3.2 compatible)
    if [[ " $CURRENT_SESSIONS_LIST " != *" $session_name "* ]]; then
        # skip files newer than the save file (likely restored by undo)
        local_file_time=$(get_file_mtime "${existing_file}")
        if [[ $local_file_time -gt $SAVE_FILE_TIME ]]; then
            continue
        fi
        rm -f "${existing_file}"
    fi
done

# ─────────────────────────────────────────
# cleanup: remove old resurrect save files
# ─────────────────────────────────────────
# keep only the 20 most recent saves to prevent unbounded growth
cleanup_old_backups() {
    local dir="$1"
    local keep="$2"
    local count=0

    while IFS= read -r file; do
        count=$((count + 1))
        if [[ $count -gt $keep ]]; then
            rm -f "$file"
        fi
    done < <(ls -1t "$dir"/tmux_resurrect_*.txt 2>/dev/null)
}

cleanup_old_backups "$RESURRECT_DIR" 20
