#!/usr/bin/env bash
# session management utilities for tmux scripts
# source this file after common.sh

# guard against multiple sourcing
[[ -n "${_TMUX_SESSION_SH_LOADED:-}" ]] && return 0
_TMUX_SESSION_SH_LOADED=1

# find another session to switch to (excluding specified session)
# returns the session name via stdout, empty if none found
# usage: other=$(find_other_session "$current_session")
find_other_session() {
    local exclude_session="$1"

    tmux list-sessions -F '#{session_activity} #{session_name}' 2>/dev/null |
        sort -rn |
        cut -d' ' -f2- |
        grep -v "^${exclude_session}$" |
        head -n1 || true
}

# switch to another session if available
# usage: switch_to_other_session "$current_session"
switch_to_other_session() {
    local current_session="$1"
    local other_session

    other_session=$(find_other_session "$current_session")

    if [[ -n "$other_session" ]]; then
        tmux switch-client -t "$other_session"
        return 0
    fi

    return 1
}

# get current session name
get_current_session() {
    # only return a session name if we're actually inside tmux
    # check for TMUX variable which is set when running inside a tmux session
    if [[ -z "${TMUX:-}" ]]; then
        # not inside a tmux session, return empty
        echo ""
        return 0
    fi
    tmux display-message -p '#{session_name}' 2>/dev/null || echo ""
}

# get current window index
get_current_window() {
    tmux display-message -p '#{window_index}'
}

# get current pane index
get_current_pane() {
    tmux display-message -p '#{pane_index}'
}

# get current pane directory
get_pane_directory() {
    tmux display-message -p '#{pane_current_path}'
}

# get window layout
get_window_layout() {
    tmux display-message -p '#{window_layout}'
}

# get current window name
get_window_name() {
    tmux display-message -p '#{window_name}'
}

# get pane count in current window
get_pane_count() {
    tmux display-message -p '#{window_panes}'
}
