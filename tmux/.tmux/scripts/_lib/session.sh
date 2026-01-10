#!/usr/bin/env bash
# Session management utilities for tmux scripts
# Source this file after common.sh

# Find another session to switch to (excluding specified session)
# Returns the session name via stdout, empty if none found
# Usage: other=$(find_other_session "$current_session")
find_other_session() {
    local exclude_session="$1"

    tmux list-sessions -F '#{session_activity} #{session_name}' 2>/dev/null | \
        sort -rn | \
        cut -d' ' -f2- | \
        grep -v "^${exclude_session}$" | \
        head -n1
}

# Switch to another session if available
# Usage: switch_to_other_session "$current_session"
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

# Get current session name
get_current_session() {
    tmux display-message -p '#{session_name}'
}

# Get current window index
get_current_window() {
    tmux display-message -p '#{window_index}'
}

# Get current pane index
get_current_pane() {
    tmux display-message -p '#{pane_index}'
}

# Get current pane directory
get_pane_directory() {
    tmux display-message -p '#{pane_current_path}'
}

# Get window layout
get_window_layout() {
    tmux display-message -p '#{window_layout}'
}

# Get current window name
get_window_name() {
    tmux display-message -p '#{window_name}'
}

# Get pane count in current window
get_pane_count() {
    tmux display-message -p '#{window_panes}'
}
