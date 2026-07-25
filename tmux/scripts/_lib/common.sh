#!/usr/bin/env bash
# common utilities for tmux scripts
# source this file: source "${BASH_SOURCE%/*}/_lib/common.sh"

# guard against multiple sourcing
[[ -n "${_TMUX_COMMON_SH_LOADED:-}" ]] && return 0
_TMUX_COMMON_SH_LOADED=1

# strict mode; scripts should set this themselves for clarity
# set -euo pipefail

# determine dotfiles root from this library file's location
# use readlink -f to resolve symlinks (or realpath if available)
_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
DOTFILES_ROOT="$(cd "$_LIB_DIR/../../.." && pwd)"

# source colour definitions
# shellcheck source=scripts/_lib/colours.sh
source "$DOTFILES_ROOT/scripts/_lib/colours.sh"

# convert hex colour (#RRGGBB) to ANSI truecolour foreground escape
# usage: local c; c=$(hex_fg "#ff0000"); printf "${c}text${NC}\n"
hex_fg() {
    printf '\033[38;2;%d;%d;%dm' "0x${1:1:2}" "0x${1:3:2}" "0x${1:5:2}"
}

# dim a hex colour by a percentage (0-100, where 100 = full brightness)
# usage: dimmed=$(hex_dim "#8be9fd" 65)
hex_dim() {
    local hex="$1" pct="${2:-65}"
    printf '#%02x%02x%02x' \
        "$(( 16#${hex:1:2} * pct / 100 ))" \
        "$(( 16#${hex:3:2} * pct / 100 ))" \
        "$(( 16#${hex:5:2} * pct / 100 ))"
}

# print the dotfiles ASCII art logo with theme-aware gradient
# uses TMUX_ACCENT_CYAN to TMUX_ACCENT_PURPLE from the active theme
# defaults to sage to forest gradient when no theme is loaded
# call load_fzf_theme before this to ensure theme colours are available
# usage: print_dotfiles_logo
# shellcheck disable=SC1003
print_dotfiles_logo() {
    local from="${TMUX_ACCENT_CYAN:-#8baf9e}"
    local to="${TMUX_ACCENT_PURPLE:-#38604a}"

    # convert hex to RGB components
    local r1=$((16#${from:1:2})) g1=$((16#${from:3:2})) b1=$((16#${from:5:2}))
    local r2=$((16#${to:1:2})) g2=$((16#${to:3:2})) b2=$((16#${to:5:2}))

    # logo lines (matching scripts/_lib/logo.txt)
    local lines=(
        '     _       _    __ _ _'
        '  __| | ___ | |_ / _(_) | ___  ___'
        ' / _` |/ _ \| __| |_| | |/ _ \/ __|'
        '| (_| | (_) | |_|  _| | |  __/\__ \'
        ' \__,_|\___/ \__|_| |_|_|\___||___/'
    )

    printf "\n"
    local i
    for i in 0 1 2 3 4; do
        local r=$(( r1 + (r2 - r1) * i / 4 ))
        local g=$(( g1 + (g2 - g1) * i / 4 ))
        local b=$(( b1 + (b2 - b1) * i / 4 ))
        printf "\033[38;2;%d;%d;%dm%s${NC}\n" "$r" "$g" "$b" "${lines[$i]}"
    done
    printf "\n"
}

# launcher path constants
DOTFILES_LAUNCHERS="$DOTFILES_ROOT/launchers"
USER_LAUNCHERS="${XDG_CONFIG_HOME:-$HOME/.config}/dotfiles/launchers"
LAUNCHER_HISTORY="${XDG_DATA_HOME:-$HOME/.local/share}/dotfiles/launcher-history"
THEME_HISTORY="${XDG_DATA_HOME:-$HOME/.local/share}/dotfiles/theme-history"
THEME_FAVOURITES="${XDG_DATA_HOME:-$HOME/.local/share}/dotfiles/theme-favourites"

# wrapper for tmux command that respects test socket
# when TMUX_TEST_SOCKET is set, all tmux commands use that socket
# exported so subshells (e.g. pipefail-safety tests) inherit the isolation
tmux() {
    if [[ -n "${TMUX_TEST_SOCKET:-}" ]]; then
        command tmux -L "$TMUX_TEST_SOCKET" "$@"
    else
        command tmux "$@"
    fi
}
export -f tmux

# load FZF theme colours from current theme
# call this before using fzf to ensure it uses the active theme
load_fzf_theme() {
    if [[ -f "$DOTFILES_ROOT/scripts/fzf-theme.sh" ]]; then
        # shellcheck disable=SC1091
        source "$DOTFILES_ROOT/scripts/fzf-theme.sh"
    fi
}

# print error message to stderr
error() {
    printf "${RED}Error:${NC} %s\n" "$1" >&2
}

# print warning message to stderr
warn() {
    printf "${YELLOW}Warning:${NC} %s\n" "$1" >&2
}

# print info message
info() {
    printf "${CYAN}%s${NC}\n" "$1"
}

# print success message
success() {
    printf "${GREEN}%s${NC}\n" "$1"
}

# show error via tmux display-message (visible after popup closes)
# use this for errors in popup/fzf contexts instead of error()
# falls back to stderr when running outside tmux
show_error() {
    if [[ -n "${TMUX:-}" ]]; then
        tmux display-message "Error: $1"
    else
        error "$1"
    fi
}

# check if fzf is available
require_fzf() {
    if ! command -v fzf &>/dev/null; then
        error "fzf is not installed (required for this picker)"
        exit 1
    fi
}

# check if tmux is running
require_tmux() {
    if ! command -v tmux &>/dev/null; then
        error "tmux is not installed"
        exit 1
    fi

    # skip the TMUX variable check if we're in test mode
    # tests can set TMUX_TEST_MODE=1 to bypass the "inside tmux" requirement
    if [[ -z "${TMUX:-}" && "${TMUX_TEST_MODE:-0}" != "1" ]]; then
        error "Not running inside tmux"
        exit 1
    fi
}

# sanitise a launcher name for use as a filename
# - lowercase, replace invalid chars with hyphen, strip leading dots/dashes
# - truncate to 64 characters
# - suffix reserved words to avoid shadowing shell builtins
# usage: sanitised=$(sanitise_launcher_name "My Launcher!")
sanitise_launcher_name() {
    local raw="$1"
    raw=$(printf '%s' "$raw" | tr -c '[:alnum:]_.-' '-' | tr '[:upper:]' '[:lower:]')
    raw="${raw#"${raw%%[[:alnum:]_]*}"}"
    raw="${raw:0:64}"
    case "$raw" in
        test|cd|ls|rm|cp|mv|cat|echo|printf|export|source|exec|eval|exit) raw="${raw}_launcher" ;;
    esac
    printf '%s' "$raw"
}

# sanitise session name (convert spaces, dots, and invalid chars to dashes, then trim trailing dashes)
# note: dots are replaced because tmux uses '.' as a separator in target syntax (session:window.pane)
sanitise_session_name() {
    local name="$1"
    echo "$name" | tr -c '[:alnum:]_-' '-' | sed 's/-*$//'
}

# ═════════════════════════════════════════════════════════════════
# Session Validation
# ═════════════════════════════════════════════════════════════════

# validate a tmux session name
# session names must be alphanumeric with underscores and hyphens allowed
# dots are NOT allowed because tmux uses '.' as a separator in target syntax
#
# usage:
#   if ! validate_session_name "$name"; then
#       exit 1
#   fi
#
# note: this function outputs error messages via error() on failure
#       callers should NOT add additional error messages
#
# arguments:
#   $1 - session name to validate
#
# returns:
#   0 - valid session name
#   1 - invalid session name (empty or contains invalid characters)
#
validate_session_name() {
    local name="$1"

    if [[ -z "$name" ]]; then
        error "Session name cannot be empty"
        return 1
    fi

    # session names should be alphanumeric with _ - allowed (no dots; tmux uses '.' as pane separator)
    if [[ ! "$name" =~ ^[a-zA-Z0-9_-]+$ ]]; then
        error "Invalid session name: '$name'. Use only letters, numbers, underscores, hyphens."
        return 1
    fi

    return 0
}

# validate pane ID format (e.g. %123)
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

# validate window index format
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

# check if a session exists (exact match, not prefix)
session_exists() {
    local session="$1"
    tmux list-sessions -F '#{session_name}' 2>/dev/null | grep -qxF "$session"
}

# bring a session into focus: switch-client inside tmux, attach outside
focus_session() {
    if [[ -n "${TMUX:-}" ]]; then
        tmux switch-client -t "$1"
    else
        tmux attach-session -t "$1"
    fi
}

# get the number of windows in a session
get_window_count() {
    local session="$1"
    tmux list-windows -t "$session" 2>/dev/null | wc -l | tr -d ' '
}

# check if this is the last session
is_last_session() {
    local count
    count=$(tmux list-sessions 2>/dev/null | wc -l | tr -d ' ')
    [[ "$count" -eq 1 ]]
}

# check if this is the last window in session
is_last_window() {
    local count
    count=$(get_window_count "$(tmux display-message -p '#{session_name}')")
    [[ "$count" -eq 1 ]]
}

# check if this is the last pane in window
is_last_pane() {
    local count
    count=$(get_pane_count)
    [[ "$count" -eq 1 ]]
}

# check if a pane is running a specific command by inspecting child processes
# many CLI tools (Claude Code, OpenCode) run as child processes of the pane
# shell, so pane_current_command shows the runtime (e.g. Node.js version)
# rather than the tool name. this checks the process tree directly.
# excludes suspended (Ctrl+Z) processes; only matches active foreground ones
#
# usage:
#   is_pane_running <pane_pid> <command_name> [-f]
#     -f  match against full command line (default: exact process name)
#
# examples:
#   is_pane_running "$pane_pid" "claude"            # exact match
#   is_pane_running "$pane_pid" "opencode" -f       # command line match
is_pane_running() {
    local pane_pid="$1"
    local command_name="$2"
    local match_flag="-x"
    [[ "${3:-}" == "-f" ]] && match_flag="-f"

    local pid
    pid=$(pgrep -P "$pane_pid" "$match_flag" "$command_name" 2>/dev/null) || return 1
    # filter out stopped/suspended processes (state 'T')
    [[ "$(ps -o state= -p "$pid" 2>/dev/null)" != T* ]]
}

# list project directories from PROJECT_DIRS (colon-separated, like PATH)
# outputs paths with ~ prefix for display, one per line
# uses fd if available, falls back to find
list_project_dirs() {
    local project_dirs="${PROJECT_DIRS:-$HOME/src}"
    local roots
    IFS=':' read -ra roots <<< "$project_dirs"
    for root in "${roots[@]}"; do
        [[ -n "$root" ]] || continue
        root="${root/#\~/$HOME}"
        [[ -d "$root" ]] || continue
        if command -v fd &>/dev/null; then
            fd --type d --max-depth 1 . "$root" 2>/dev/null
        else
            find "$root" -maxdepth 1 -mindepth 1 -type d 2>/dev/null | sort
        fi
    done | while IFS= read -r d; do
        printf '%s\n' "${d/#$HOME/\~}"
    done
}

# ═════════════════════════════════════════════════════════════════
# Cross-Platform Helpers
# ═════════════════════════════════════════════════════════════════

# clipboard_backend / clipboard_copy_cmd / clipboard_copy come from the shared
# lib, so tmux scripts and theme-switch resolve the same backend
# shellcheck source=scripts/_lib/clipboard.sh
source "$DOTFILES_ROOT/scripts/_lib/clipboard.sh"

# open a URL or file with the system handler (works on macOS and Linux)
# on macOS, the tmux user option `@browser-app` overrides the default browser:
# when set, URLs open via `open -a <app>` instead of the LaunchServices default
# set in ~/.config/tmux/local.conf, e.g.:  set -g @browser-app 'Arc'
open_url() {
    local url="$1"
    if [[ "$(uname)" == "Darwin" ]]; then
        local browser_app=""
        if command -v tmux &>/dev/null; then
            browser_app=$(tmux show-options -gv "@browser-app" 2>/dev/null || true)
        fi
        if [[ -n "$browser_app" ]]; then
            open -a "$browser_app" "$url"
        else
            open "$url"
        fi
    elif command -v xdg-open &>/dev/null; then
        xdg-open "$url" &>/dev/null &
    elif command -v wslview &>/dev/null; then
        wslview "$url"
    else
        error "No handler found to open URLs"
        return 1
    fi
}

# reverse lines (cross-platform replacement for macOS 'tail -r')
reverse_lines() {
    if command -v tac &>/dev/null; then
        tac
    else
        awk '{lines[NR]=$0} END {for(i=NR;i>=1;i--) print lines[i]}'
    fi
}

# return the platform-appropriate modifier key label
# usage: mod_key  ->  "Opt" on macOS, "Alt" on Linux
mod_key() {
    if [[ "$(uname)" == "Darwin" ]]; then
        printf 'Opt'
    else
        printf 'Alt'
    fi
}

# portable in-place sed (macOS BSD sed vs GNU sed)
# writes to a temp file first to prevent corruption on sed errors
# usage: sed_inplace 'sed-expression' file
sed_inplace() {
    local args=("$@")
    local file="${args[-1]}"
    local sed_args=("${args[@]:0:${#args[@]}-1}")
    local tmp
    tmp=$(mktemp "${file}.XXXXXX") || return 1
    # preserve the original file's permissions across the swap (mktemp
    # defaults to 600, which would silently drop e.g. an executable bit)
    cp -p "$file" "$tmp" 2>/dev/null
    if sed "${sed_args[@]}" "$file" > "$tmp"; then
        mv "$tmp" "$file"
    else
        rm -f "$tmp"
        return 1
    fi
}
