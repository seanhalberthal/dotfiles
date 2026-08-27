#!/usr/bin/env bash
# undo file path definitions for tmux scripts
# source this file after common.sh

# guard against multiple sourcing
[[ -n "${_TMUX_PATHS_SH_LOADED:-}" ]] && return 0
_TMUX_PATHS_SH_LOADED=1

# undo path constants (XDG-compliant)
# stores kill/undo state in XDG cache directory

# get the undo base directory (XDG-compliant)
get_undo_base_dir() {
    local xdg_undo_dir="${XDG_CACHE_HOME:-$HOME/.cache}/tmux/undo"
    mkdir -p "$xdg_undo_dir" 2>/dev/null || true
    chmod 700 "$xdg_undo_dir" 2>/dev/null || true
    echo "$xdg_undo_dir"
}

UNDO_BASE_DIR=$(get_undo_base_dir)
readonly UNDO_BASE_DIR

# pane undo paths
get_pane_undo_file() { echo "${UNDO_BASE_DIR}/pane"; }
get_pane_undo_state() { echo "${UNDO_BASE_DIR}/pane-state.txt"; }
get_pane_undo_content() { echo "${UNDO_BASE_DIR}/pane-content.txt"; }

# window undo paths
get_window_undo_file() { echo "${UNDO_BASE_DIR}/window"; }
get_window_undo_state() { echo "${UNDO_BASE_DIR}/window-state.txt"; }

get_window_undo_contents_dir() {
    local dir="${UNDO_BASE_DIR}/window-contents"
    mkdir -p "$dir"
    chmod 700 "$dir"
    echo "$dir"
}

# session undo paths
get_session_undo_file() { echo "${UNDO_BASE_DIR}/session"; }
get_session_undo_state() { echo "${UNDO_BASE_DIR}/session-state.txt"; }

get_session_undo_backup() {
    echo "${UNDO_BASE_DIR}/session-backup"
}

# clean up undo files for a specific type
# usage: cleanup_undo_files "pane" | "window" | "session"
cleanup_undo_files() {
    local type="$1"
    local base_dir
    base_dir=$(get_undo_base_dir)

    case "$type" in
        pane)
            rm -f "$base_dir/pane" "$base_dir/pane-state.txt" "$base_dir/pane-content.txt"
            ;;
        window)
            rm -f "$base_dir/window" "$base_dir/window-state.txt"
            rm -rf "$base_dir/window-contents"
            mkdir -p "$base_dir/window-contents"
            chmod 700 "$base_dir/window-contents"
            ;;
        session)
            rm -f "$base_dir/session" "$base_dir/session-state.txt"
            rm -rf "$base_dir/session-backup"
            ;;
        *)
            error "Unknown undo type: $type"
            return 1
            ;;
    esac
}

# get the most recent undo type based on file timestamps
get_most_recent_undo_type() {
    local base_dir
    base_dir=$(get_undo_base_dir)

    local pane_time=0 window_time=0 session_time=0

    # platform-aware stat for modification time
    local stat_cmd
    if [[ "$(uname)" == "Darwin" ]]; then
        stat_cmd=(stat -f %m)
    else
        stat_cmd=(stat -c %Y)
    fi

    [[ -f "$base_dir/pane" ]] && pane_time=$("${stat_cmd[@]}" "$base_dir/pane" 2>/dev/null || echo 0)
    [[ -f "$base_dir/window" ]] && window_time=$("${stat_cmd[@]}" "$base_dir/window" 2>/dev/null || echo 0)
    [[ -f "$base_dir/session" ]] && session_time=$("${stat_cmd[@]}" "$base_dir/session" 2>/dev/null || echo 0)

    if [[ $pane_time -ge $window_time && $pane_time -ge $session_time && $pane_time -gt 0 ]]; then
        echo "pane"
    elif [[ $window_time -ge $session_time && $window_time -gt 0 ]]; then
        echo "window"
    elif [[ $session_time -gt 0 ]]; then
        echo "session"
    else
        echo ""
    fi
}

# ═════════════════════════════════════════════════════════════════
# Resurrect Path Discovery
# ═════════════════════════════════════════════════════════════════
# the functions below discover where tmux-resurrect stores session data.
# they check both XDG-compliant and legacy locations

# get the resurrect data directory
# returns the directory where tmux-resurrect stores its data
#
# usage: RESURRECT_DIR=$(get_resurrect_dir)
# output: path to resurrect directory
get_resurrect_dir() {
    # check for existing 'last' symlink (best indicator)
    if [[ -L "${HOME}/.tmux/resurrect/last" || -f "${HOME}/.tmux/resurrect/last" ]]; then
        echo "${HOME}/.tmux/resurrect"
    elif [[ -L "${XDG_DATA_HOME:-$HOME/.local/share}/tmux/resurrect/last" || -f "${XDG_DATA_HOME:-$HOME/.local/share}/tmux/resurrect/last" ]]; then
        echo "${XDG_DATA_HOME:-$HOME/.local/share}/tmux/resurrect"
    # fall back to checking for sessions directory
    elif [[ -d "${XDG_DATA_HOME:-$HOME/.local/share}/tmux/resurrect/sessions" ]]; then
        echo "${XDG_DATA_HOME:-$HOME/.local/share}/tmux/resurrect"
    elif [[ -d "${HOME}/.tmux/resurrect/sessions" ]]; then
        echo "${HOME}/.tmux/resurrect"
    # default to legacy location if neither exists
    else
        echo "${HOME}/.tmux/resurrect"
    fi
}

# get the resurrect sessions directory
# returns the directory where session state files are stored
#
# usage: SESSIONS_DIR=$(get_resurrect_sessions_dir)
# output: path to resurrect sessions directory
get_resurrect_sessions_dir() {
    local resurrect_dir
    resurrect_dir=$(get_resurrect_dir)
    echo "${resurrect_dir}/sessions"
}
