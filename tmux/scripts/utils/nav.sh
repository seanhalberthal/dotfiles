#!/usr/bin/env bash
set -euo pipefail

# browser-style back/forward navigation history for tmux
# tracks window IDs (@N) which are stable across renames
#
# usage: nav.sh {record <window_id>|back|forward}
#
# history is stored in XDG cache as a flat file of window IDs (one per line).
# a separate position file tracks where we are in the stack.
# the @nav-skip tmux option prevents hooks from recording back/forward navigation

SCRIPT_DIR="${BASH_SOURCE%/*}"
source "$SCRIPT_DIR/../_lib/common.sh"

# XDG-compliant storage (consistent with paths.sh patterns)
NAV_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/tmux/nav"
HISTORY_FILE="${NAV_DIR}/history"
POS_FILE="${NAV_DIR}/position"
LAST_FILE="${NAV_DIR}/last"
MAX_HISTORY=100

ensure_dir() {
    [[ -d "$NAV_DIR" ]] || mkdir -p "$NAV_DIR"
}

# get current window ID, uses tmux display-message when a client is attached,
# falls back to querying the active window across all sessions (works detached).
# the unscoped display-message query is only trustworthy when $TMUX confirms
# we're actually inside an attached client -- run without one (e.g. detached,
# or invoked from a plain shell), tmux still answers it but silently picks an
# arbitrary session when more than one exists on the server, rather than
# erroring, so it must not be used to detect "am I attached".
get_current_window() {
    if [[ -n "${TMUX:-}" ]]; then
        tmux display-message -p '#{window_id}' 2>/dev/null && return
    fi
    # detached (or no client): scan for the active window across all sessions
    tmux list-windows -a -F '#{window_active} #{window_id}' 2>/dev/null | awk '/^1 /{print $2; exit}'
}

# get session ID for a given target window/pane
get_session_id() {
    tmux display-message -t "$1" -p '#{session_id}' 2>/dev/null
}

get_position() {
    [[ -f "$POS_FILE" ]] && cat "$POS_FILE" || echo 0
}

set_position() {
    printf '%s' "$1" >"$POS_FILE"
}

history_count() {
    [[ -f "$HISTORY_FILE" ]] && wc -l <"$HISTORY_FILE" | tr -d ' ' || echo 0
}

# check if a window ID still exists
window_exists() {
    local result
    result=$(tmux display-message -t "$1" -p '#{window_id}' 2>/dev/null) || return 1
    [[ "$result" == "$1" ]]
}

# record a navigation event (called by tmux hooks)
# arguments: $1 = window_id (from #{window_id} in hook)
record() {
    ensure_dir
    local current="${1:-}"

    # validate window ID format (@N)
    if [[ -z "$current" || ! "$current" =~ ^@[0-9]+$ ]]; then
        exit 0
    fi

    # skip if flagged by back/forward navigation
    local skip
    skip=$(tmux show-option -gqv @nav-skip 2>/dev/null || true)
    if [[ -n "$skip" && "$skip" == "$current" ]]; then
        printf '%s' "$current" >"$LAST_FILE"
        return
    fi
    # clear any stale skip flag that doesn't match current
    [[ -n "$skip" ]] && tmux set-option -gq @nav-skip "" 2>/dev/null

    # if position > 0 (we went back then navigated), truncate forward history
    local pos count
    pos=$(get_position)
    if [[ "$pos" -gt 0 ]]; then
        count=$(history_count)
        local keep=$((count - pos))
        if [[ "$keep" -gt 0 ]]; then
            head -n "$keep" "$HISTORY_FILE" >"${HISTORY_FILE}.tmp"
            mv "${HISTORY_FILE}.tmp" "$HISTORY_FILE"
        else
            : >"$HISTORY_FILE"
        fi
        set_position 0
        # reset LAST_FILE to match truncated state (prevents stale departure push)
        local new_last
        new_last=$([[ -f "$HISTORY_FILE" ]] && tail -n1 "$HISTORY_FILE" || echo "")
        if [[ -n "$new_last" ]]; then
            printf '%s' "$new_last" >"$LAST_FILE"
        else
            rm -f "$LAST_FILE"
        fi
    fi

    # push previous window if not already the last history entry
    # this captures the "departure" window on first navigation
    if [[ -f "$LAST_FILE" ]]; then
        local prev last_entry
        prev=$(cat "$LAST_FILE")
        last_entry=$([[ -f "$HISTORY_FILE" ]] && tail -n1 "$HISTORY_FILE" || echo "")
        if [[ -n "$prev" && "$prev" != "$last_entry" && "$prev" != "$current" ]]; then
            printf '%s\n' "$prev" >>"$HISTORY_FILE"
        fi
    fi

    # don't record duplicate of last entry
    local last_entry
    last_entry=$([[ -f "$HISTORY_FILE" ]] && tail -n1 "$HISTORY_FILE" || echo "")
    if [[ "$last_entry" != "$current" ]]; then
        printf '%s\n' "$current" >>"$HISTORY_FILE"
    fi

    printf '%s' "$current" >"$LAST_FILE"

    # trim history if over limit
    count=$(history_count)
    if [[ "$count" -gt "$MAX_HISTORY" ]]; then
        tail -n "$MAX_HISTORY" "$HISTORY_FILE" >"${HISTORY_FILE}.tmp"
        mv "${HISTORY_FILE}.tmp" "$HISTORY_FILE"
    fi
}

# navigate backward in history
back() {
    ensure_dir
    local count pos current
    count=$(history_count)
    pos=$(get_position)
    current=$(get_current_window) || exit 0
    [[ -n "$current" ]] || exit 0

    # ensure current window is in history (handles cold start / config reload)
    if [[ "$pos" -eq 0 ]]; then
        local last_entry
        last_entry=$([[ -f "$HISTORY_FILE" ]] && tail -n1 "$HISTORY_FILE" || echo "")
        if [[ "$last_entry" != "$current" ]]; then
            printf '%s\n' "$current" >>"$HISTORY_FILE"
            count=$((count + 1))
        fi
    fi

    # calculate target
    local new_pos=$((pos + 1))
    local target_line=$((count - new_pos))

    if [[ "$target_line" -lt 1 ]]; then
        tmux display-message "No more history" 2>/dev/null || true
        return
    fi

    local target
    target=$(sed -n "${target_line}p" "$HISTORY_FILE")

    # remove stale entries and retry
    if ! window_exists "$target"; then
        sed "${target_line}d" "$HISTORY_FILE" >"${HISTORY_FILE}.tmp"
        mv "${HISTORY_FILE}.tmp" "$HISTORY_FILE"
        back
        return
    fi

    # set skip flag (target-based, persists until a different window is reached)
    tmux set-option -gq @nav-skip "$target" 2>/dev/null || true
    set_position "$new_pos"

    # navigate: use switch-client for cross-session, select-window for same-session
    local target_session current_session
    target_session=$(get_session_id "$target") || {
        tmux select-window -t "$target" 2>/dev/null || true
        return
    }
    current_session=$(get_session_id "$current") || {
        tmux select-window -t "$target" 2>/dev/null || true
        return
    }

    if [[ "$target_session" != "$current_session" ]]; then
        tmux switch-client -t "$target" 2>/dev/null || tmux select-window -t "$target" 2>/dev/null || true
    else
        tmux select-window -t "$target" 2>/dev/null || true
    fi
}

# navigate forward in history
forward() {
    local pos
    pos=$(get_position)

    if [[ "$pos" -le 0 ]]; then
        tmux display-message "Already at newest" 2>/dev/null || true
        return
    fi

    local count new_pos target_line
    count=$(history_count)
    new_pos=$((pos - 1))
    target_line=$((count - new_pos))

    local target
    target=$(sed -n "${target_line}p" "$HISTORY_FILE")

    # remove stale entries and retry
    if ! window_exists "$target"; then
        sed "${target_line}d" "$HISTORY_FILE" >"${HISTORY_FILE}.tmp"
        mv "${HISTORY_FILE}.tmp" "$HISTORY_FILE"
        forward
        return
    fi

    tmux set-option -gq @nav-skip "$target" 2>/dev/null || true
    set_position "$new_pos"

    local current target_session current_session
    current=$(get_current_window) || {
        tmux select-window -t "$target" 2>/dev/null
        return
    }
    target_session=$(get_session_id "$target") || {
        tmux select-window -t "$target" 2>/dev/null || true
        return
    }
    current_session=$(get_session_id "$current") || {
        tmux select-window -t "$target" 2>/dev/null || true
        return
    }

    if [[ "$target_session" != "$current_session" ]]; then
        tmux switch-client -t "$target" 2>/dev/null || tmux select-window -t "$target" 2>/dev/null || true
    else
        tmux select-window -t "$target" 2>/dev/null || true
    fi
}

case "${1:-}" in
    record) record "${2:-}" ;;
    back) back ;;
    forward) forward ;;
    *)
        echo "Usage: nav.sh {record <window_id>|back|forward}" >&2
        exit 1
        ;;
esac
