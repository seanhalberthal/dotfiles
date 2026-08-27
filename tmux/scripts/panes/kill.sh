#!/usr/bin/env bash
set -euo pipefail

# kill current pane with undo capability
# saves pane state before killing for later restoration

# parse arguments
PANE_TARGET=""
FORCE_KILL=false

for arg in "$@"; do
    case "$arg" in
        --force)
            FORCE_KILL=true
            ;;
        *)
            PANE_TARGET="$arg"
            ;;
    esac
done

SCRIPT_DIR="${BASH_SOURCE%/*}"
source "$SCRIPT_DIR/../_lib/common.sh"
source "$SCRIPT_DIR/../_lib/paths.sh"
source "$SCRIPT_DIR/../_lib/session.sh"
source "$SCRIPT_DIR/../_lib/ui.sh"
source "$SCRIPT_DIR/../_lib/alerts.sh"
source "$SCRIPT_DIR/../_lib/process.sh"

require_tmux

# load all pane/window metadata in one tmux round-trip
if [[ -n "$PANE_TARGET" ]]; then
    pane_info=$(tmux display-message -t "$PANE_TARGET" -p \
        '#{session_name}|#{window_index}|#{pane_index}|#{pane_current_path}|#{window_layout}|#{window_name}|#{window_id}|#{window_panes}|#{session_windows}' \
        2>/dev/null) || exit 1
else
    pane_info=$(tmux display-message -p \
        '#{session_name}|#{window_index}|#{pane_index}|#{pane_current_path}|#{window_layout}|#{window_name}|#{window_id}|#{window_panes}|#{session_windows}' \
        2>/dev/null) || exit 1
fi

IFS='|' read -r CURRENT_SESSION CURRENT_WINDOW CURRENT_PANE PANE_DIR WINDOW_LAYOUT WINDOW_NAME WINDOW_ID PANE_COUNT WINDOW_COUNT <<<"$pane_info"
PANE_TARGET="${CURRENT_SESSION}:${CURRENT_WINDOW}.${CURRENT_PANE}"

IS_LAST_PANE="no"
[[ "$PANE_COUNT" -eq 1 ]] && IS_LAST_PANE="yes"
IS_LAST_WINDOW="no"
[[ "$WINDOW_COUNT" -eq 1 ]] && IS_LAST_WINDOW="yes"

# show confirmation unless --force flag is set
if ! $FORCE_KILL; then
    # build context-aware message
    if [[ "$IS_LAST_PANE" == "yes" && "$IS_LAST_WINDOW" == "yes" ]]; then
        OTHER_SESSION=$(find_other_session "$CURRENT_SESSION")
        if [[ -n "$OTHER_SESSION" ]]; then
            MESSAGE="Last pane in '${CURRENT_SESSION}'\nSwitch to '${OTHER_SESSION}' and kill?"
        else
            MESSAGE="Last pane in '${CURRENT_SESSION}'\nThis will end the session. Kill?"
        fi
    else
        MESSAGE="Kill this pane?"
    fi

    if ! show_visual_confirm "Kill Pane" "$MESSAGE"; then
        exit 0
    fi
fi

# user confirmed, save undo state
UNDO_FILE=$(get_pane_undo_file)
UNDO_STATE=$(get_pane_undo_state)
UNDO_CONTENT=$(get_pane_undo_content)

# clear previous undo data
cleanup_undo_files "pane"

# save current state for undo
echo "$PANE_TARGET" >"$UNDO_FILE"
chmod 600 "$UNDO_FILE"

# save pane metadata
{
    echo "dir=$PANE_DIR"
    echo "layout=$WINDOW_LAYOUT"
} >"$UNDO_STATE"
chmod 600 "$UNDO_STATE"

# capture pane contents
tmux capture-pane -t "$PANE_TARGET" -p -S -32768 >"$UNDO_CONTENT" 2>/dev/null || true
chmod 600 "$UNDO_CONTENT"

# gracefully terminate running processes before killing the pane
terminate_pane_processes "$PANE_TARGET"

# determine if we need to check for session switching
# we need the ACTUAL current client session (where the user is), not the target session
ACTUAL_CLIENT_SESSION=$(tmux display-message -p '#{client_session}' 2>/dev/null || echo "")

# if last pane in last window and we're in that session, handle session switching
if [[ "$IS_LAST_PANE" == "yes" && "$IS_LAST_WINDOW" == "yes" && "$ACTUAL_CLIENT_SESSION" == "$CURRENT_SESSION" ]]; then
    OTHER_SESSION=$(find_other_session "$CURRENT_SESSION")
    if [[ -n "$OTHER_SESSION" ]]; then
        tmux switch-client -t "$OTHER_SESSION" \; kill-pane -t "$PANE_TARGET" 2>/dev/null || exit 1
    else
        tmux kill-pane -t "$PANE_TARGET" 2>/dev/null || exit 1
    fi
    # session is destroyed, clear all session alerts synchronously
    # (backgrounding risks SIGHUP killing the process when popup exits)
    clear_session_alerts "$CURRENT_SESSION"
elif [[ "$IS_LAST_PANE" == "yes" && "$IS_LAST_WINDOW" == "yes" ]]; then
    # last pane of the last window in a session we're not attached to: killing it
    # destroys the whole session, so clear at session scope (no client switch)
    tmux kill-pane -t "$PANE_TARGET" 2>/dev/null || exit 1
    clear_session_alerts "$CURRENT_SESSION"
elif [[ "$IS_LAST_PANE" == "yes" ]]; then
    # last pane but not last window, killing destroys the window
    tmux kill-pane -t "$PANE_TARGET" 2>/dev/null || exit 1
    # window is destroyed, clear its alerts
    clear_window_alerts "$CURRENT_SESSION" "$WINDOW_NAME" "$WINDOW_ID"
else
    # not the last pane, panes don't have individual alerts
    tmux kill-pane -t "$PANE_TARGET" 2>/dev/null || exit 1
fi
