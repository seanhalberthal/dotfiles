#!/usr/bin/env bash
# Common utilities for tmux scripts
# Source this file: source "${BASH_SOURCE%/*}/_lib/common.sh"

# Strict mode - scripts should set this themselves for clarity
# set -euo pipefail

# Colours for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[0;33m'
readonly BLUE='\033[0;34m'
readonly CYAN='\033[0;36m'
readonly NC='\033[0m' # No Colour

# Print error message to stderr
error() {
    printf "${RED}Error:${NC} %s\n" "$1" >&2
}

# Print warning message to stderr
warn() {
    printf "${YELLOW}Warning:${NC} %s\n" "$1" >&2
}

# Print info message
info() {
    printf "${CYAN}%s${NC}\n" "$1"
}

# Print success message
success() {
    printf "${GREEN}%s${NC}\n" "$1"
}

# Check if tmux is running
require_tmux() {
    if ! command -v tmux &>/dev/null; then
        error "tmux is not installed"
        exit 1
    fi

    if [[ -z "${TMUX:-}" ]]; then
        error "Not running inside tmux"
        exit 1
    fi
}

# Validate session name (alphanumeric, underscore, hyphen, dot)
validate_session_name() {
    local name="$1"

    if [[ -z "$name" ]]; then
        error "Session name cannot be empty"
        return 1
    fi

    # Session names should be alphanumeric with _ - . allowed
    if [[ ! "$name" =~ ^[a-zA-Z0-9._-]+$ ]]; then
        error "Invalid session name: '$name'. Use only letters, numbers, dots, underscores, hyphens."
        return 1
    fi

    return 0
}

# Validate pane ID format (e.g., %123)
validate_pane_id() {
    local pane_id="$1"

    if [[ -z "$pane_id" ]]; then
        error "Pane ID cannot be empty"
        return 1
    fi

    if [[ ! "$pane_id" =~ ^%[0-9]+$ ]]; then
        error "Invalid pane ID format: '$pane_id'"
        return 1
    fi

    return 0
}

# Validate window index format
validate_window_index() {
    local index="$1"

    if [[ -z "$index" ]]; then
        error "Window index cannot be empty"
        return 1
    fi

    if [[ ! "$index" =~ ^[0-9]+$ ]]; then
        error "Invalid window index: '$index'"
        return 1
    fi

    return 0
}

# Check if a session exists
session_exists() {
    local session="$1"
    tmux has-session -t "$session" 2>/dev/null
}

# Get the number of windows in a session
get_window_count() {
    local session="$1"
    tmux list-windows -t "$session" 2>/dev/null | wc -l | tr -d ' '
}

# Get the number of panes in current window
get_pane_count() {
    tmux display-message -p '#{window_panes}'
}

# Check if this is the last session
is_last_session() {
    local count
    count=$(tmux list-sessions 2>/dev/null | wc -l | tr -d ' ')
    [[ "$count" -eq 1 ]]
}

# Check if this is the last window in session
is_last_window() {
    local count
    count=$(get_window_count "$(tmux display-message -p '#{session_name}')")
    [[ "$count" -eq 1 ]]
}

# Check if this is the last pane in window
is_last_pane() {
    local count
    count=$(get_pane_count)
    [[ "$count" -eq 1 ]]
}
