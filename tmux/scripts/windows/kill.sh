#!/usr/bin/env bash
set -euo pipefail

# kill a window with undo capability
# saves all pane states before killing for later restoration
#
# usage: kill.sh [session:window] [--no-confirm|--force]
#   if no argument provided, kills the current window
#   --force: skip last window confirmation (confirmation already happened in tmux keybinding)

SCRIPT_DIR="${BASH_SOURCE%/*}"
source "$SCRIPT_DIR/../_lib/common.sh"
source "$SCRIPT_DIR/../_lib/ui.sh"
source "$SCRIPT_DIR/../_lib/paths.sh"
source "$SCRIPT_DIR/../_lib/session.sh"
source "$SCRIPT_DIR/../_lib/alerts.sh"
source "$SCRIPT_DIR/../_lib/process.sh"

require_tmux

# load current theme colours for fzf
load_fzf_theme

# parse optional flags
WINDOW_TARGET=""
NO_CONFIRM=""

for arg in "$@"; do
    case "$arg" in
        --force | --no-confirm)
            NO_CONFIRM="--no-confirm"
            ;;
        *)
            WINDOW_TARGET="$arg"
            ;;
    esac
done

if [[ -n "$WINDOW_TARGET" ]]; then
    # validate and parse session:window format
    TARGET_SESSION="${WINDOW_TARGET%%:*}"
    TARGET_WINDOW="${WINDOW_TARGET#*:}"

    # verify session exists
    tmux has-session -t "$TARGET_SESSION" 2>/dev/null || {
        error "Session '$TARGET_SESSION' does not exist"
        exit 1
    }

    # verify window exists
    tmux list-windows -t "$TARGET_SESSION" -F '#{window_index}' | grep -q "^${TARGET_WINDOW}$" || {
        error "Window '$TARGET_WINDOW' does not exist in session '$TARGET_SESSION'"
        exit 1
    }

    WINDOW_LAYOUT=$(tmux display-message -t "$WINDOW_TARGET" -p '#{window_layout}')
else
    # use current window
    TARGET_SESSION=$(get_current_session)
    TARGET_WINDOW=$(get_current_window)
    WINDOW_TARGET="${TARGET_SESSION}:${TARGET_WINDOW}"
    WINDOW_LAYOUT=$(get_window_layout)
fi

CURRENT_SESSION=$(get_current_session)

# get window name and ID for confirmation and alert cleanup
WINDOW_NAME=$(tmux display-message -t "$WINDOW_TARGET" -p '#{window_name}')
WINDOW_ID=$(tmux display-message -t "$WINDOW_TARGET" -p '#{window_id}')

# get window count to check if this is the last window
WINDOW_COUNT=$(get_window_count "$TARGET_SESSION")

# show confirmation dialog (unless --no-confirm is specified)
if [[ "$NO_CONFIRM" != "--no-confirm" ]]; then
    TITLE="Kill Window"

    # build context-aware message
    if [[ "$TARGET_SESSION" == "$CURRENT_SESSION" && "$WINDOW_COUNT" -eq 1 ]]; then
        OTHER_SESSION=$(find_other_session "$TARGET_SESSION")
        if [[ -n "$OTHER_SESSION" ]]; then
            MESSAGE="Last window '${WINDOW_NAME}' in '${TARGET_SESSION}'\nSwitch to '${OTHER_SESSION}' and kill?"
        else
            MESSAGE="Last window '${WINDOW_NAME}' in '${TARGET_SESSION}'\nThis will end the session. Kill?"
        fi
    else
        MESSAGE="Kill window '${WINDOW_NAME}'?"
    fi

    if ! show_visual_confirm "$TITLE" "$MESSAGE"; then
        exit 0 # exit cleanly on cancellation
    fi
fi

# user confirmed; now save undo state
UNDO_FILE=$(get_window_undo_file)
UNDO_STATE=$(get_window_undo_state)
UNDO_CONTENTS_DIR=$(get_window_undo_contents_dir)

# clear previous undo data and recreate directory
cleanup_undo_files "window"

# tab delimiter for state file
d=$'\t'

# save window target
echo "$WINDOW_TARGET" >"$UNDO_FILE"
chmod 600 "$UNDO_FILE"

# get window info
WINDOW_ACTIVE=$(tmux display-message -t "$WINDOW_TARGET" -p '#{window_active}')
WINDOW_FLAGS=$(tmux display-message -t "$WINDOW_TARGET" -p '#{window_flags}')
AUTO_RENAME=$(tmux show-window-option -t "$WINDOW_TARGET" -v automatic-rename 2>/dev/null || echo "on")

# write window line
echo "window${d}${TARGET_SESSION}${d}${TARGET_WINDOW}${d}:${WINDOW_NAME}${d}${WINDOW_ACTIVE}${d}${WINDOW_FLAGS}${d}${WINDOW_LAYOUT}${d}${AUTO_RENAME}" >"$UNDO_STATE"
chmod 600 "$UNDO_STATE"

# get pane info for each pane
while IFS='|' read -r pane_index pane_title pane_dir pane_active pane_cmd; do
    # escape spaces in path
    escaped_dir="${pane_dir// /\\ }"

    # write pane line
    echo "pane${d}${TARGET_SESSION}${d}${TARGET_WINDOW}${d}${WINDOW_ACTIVE}${d}${WINDOW_FLAGS}${d}${pane_index}${d}${pane_title}${d}:${escaped_dir}${d}${pane_active}${d}${pane_cmd}${d}:" >>"$UNDO_STATE"

    # capture pane contents
    tmux capture-pane -t "${WINDOW_TARGET}.${pane_index}" -p -S -32768 \
        >"$UNDO_CONTENTS_DIR/pane-${pane_index}.txt" 2>/dev/null || true
    chmod 600 "$UNDO_CONTENTS_DIR/pane-${pane_index}.txt"
done < <(tmux list-panes -t "$WINDOW_TARGET" -F '#{pane_index}|#{pane_title}|#{pane_current_path}|#{pane_active}|#{pane_current_command}')

# gracefully terminate running processes before killing the window
terminate_window_processes "$WINDOW_TARGET"

# if killing the last window in current session, switch to another session first
# this prevents tmux from auto-exiting since killing the last window would kill the session
if [[ "$TARGET_SESSION" == "$CURRENT_SESSION" && "$WINDOW_COUNT" -eq 1 ]]; then
    OTHER_SESSION=$(find_other_session "$TARGET_SESSION")
    if [[ -n "$OTHER_SESSION" ]]; then
        tmux switch-client -t "$OTHER_SESSION" \; kill-window -t "$WINDOW_TARGET"
    else
        # no other session; killing this window will end the session
        tmux kill-window -t "$WINDOW_TARGET"
    fi
else
    # not the last window, or not in current session; kill normally
    tmux kill-window -t "$WINDOW_TARGET"
fi

# clear alerts (window is already killed, so only file cleanup matters)
# run synchronously to avoid race conditions with concurrent kills.
# if this was the session's only window, killing it ended the session, so clear
# the whole session (also drops finished rows for windows that closed earlier)
if [[ "$WINDOW_COUNT" -eq 1 ]]; then
    clear_session_alerts "$TARGET_SESSION"
else
    clear_window_alerts "$TARGET_SESSION" "$WINDOW_NAME" "$WINDOW_ID"
fi
