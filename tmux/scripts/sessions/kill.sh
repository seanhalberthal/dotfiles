#!/usr/bin/env bash
set -euo pipefail

# kill a tmux session with confirmation dialog and undo capability
# Usage: kill.sh <session_name> [--no-confirm]

SCRIPT_DIR="${BASH_SOURCE%/*}"
source "$SCRIPT_DIR/../_lib/common.sh"
source "$SCRIPT_DIR/../_lib/ui.sh"
source "$SCRIPT_DIR/../_lib/paths.sh"
source "$SCRIPT_DIR/../_lib/session.sh"
source "$SCRIPT_DIR/../_lib/alerts.sh"
source "$SCRIPT_DIR/../_lib/process.sh"

# capture a session's state directly from tmux and save as undo backup.
# produces the same tab-separated format as tmux-resurrect so restore.sh
# can read it without modification. fast: only queries the target session
save_undo_state() {
    local session="$1"
    local d=$'\t'
    local undo_file undo_backup
    undo_file=$(get_session_undo_file)
    undo_backup=$(get_session_undo_backup)

    # clear previous undo data
    cleanup_undo_files "session"

    # save session name for undo
    (
        umask 077
        echo "$session" >"$undo_file"
    )

    # capture pane state (matches resurrect pane format)
    # fields: pane, session, window_index, window_active, :window_flags,
    #         pane_index, pane_title, :pane_current_path, pane_active,
    #         pane_current_command, :full_command (empty, we don't restore processes)
    local pane_fmt="pane${d}#{session_name}${d}#{window_index}${d}#{window_active}"
    pane_fmt+="${d}:#{window_flags}${d}#{pane_index}${d}#{pane_title}"
    pane_fmt+="${d}:#{pane_current_path}${d}#{pane_active}${d}#{pane_current_command}${d}:"

    # capture window state (matches resurrect window format)
    # fields: window, session, window_index, :window_name, window_active,
    #         :window_flags, window_layout, automatic_rename
    local win_fmt="window${d}#{session_name}${d}#{window_index}${d}:#{window_name}"
    win_fmt+="${d}#{window_active}${d}:#{window_flags}${d}#{window_layout}"

    {
        tmux list-panes -t "$session" -s -F "$pane_fmt" 2>/dev/null || true
        # window lines need automatic-rename appended per-window
        while IFS= read -r line; do
            local win_idx
            win_idx=$(printf '%s' "$line" | cut -f3)
            local auto_rename
            auto_rename=$(tmux show-window-options -vt "${session}:${win_idx}" automatic-rename 2>/dev/null) || true
            [[ -z "$auto_rename" ]] && auto_rename=":"
            printf '%s\t%s\n' "$line" "$auto_rename"
        done < <(tmux list-windows -t "$session" -F "$win_fmt" 2>/dev/null || true)
    } >"$undo_backup"

    if [[ -s "$undo_backup" ]]; then
        chmod 600 "$undo_backup"
    else
        rm -f "$undo_backup"
    fi
    return 0
}

# when sourced for testing, export functions without running the main script
if [[ "${SOURCING_FOR_TEST:-0}" == "1" ]]; then
    # shellcheck disable=SC2317  # exit 0 is the fallback when executed (not sourced)
    return 0 2>/dev/null || exit 0
fi

require_tmux

SESSION_NAME="${1:-$(get_current_session)}"
NO_CONFIRM="${2:-}"
[[ -z "$SESSION_NAME" ]] && exit 1

# get the current session (the one the client is attached to)
CURRENT_SESSION=$(get_current_session)

# prevent killing the last session
if is_last_session; then
    tmux display-message "Cannot kill session: This is the only session. Create another session first."
    exit 1
fi

# if killing the current session, show confirmation then switch and kill
if [[ "$SESSION_NAME" == "$CURRENT_SESSION" ]]; then
    OTHER_SESSION=$(find_other_session "$SESSION_NAME")

    if [[ -n "$OTHER_SESSION" ]]; then
        if [[ "$NO_CONFIRM" != "--no-confirm" ]]; then
            # show visual confirmation
            TITLE="Kill Session"
            MESSAGE="Kill session '${SESSION_NAME}' and switch to '${OTHER_SESSION}'?"

            if ! show_visual_confirm "$TITLE" "$MESSAGE"; then
                exit 0 # exit cleanly on cancellation
            fi
        fi

        # user confirmed, save a fresh backup before killing
        save_undo_state "$SESSION_NAME"

        # gracefully terminate running processes before killing the session
        terminate_session_processes "$SESSION_NAME"

        # switch and kill
        tmux switch-client -t "$OTHER_SESSION" \; kill-session -t "$SESSION_NAME"

        # clear alerts synchronously; backgrounding risks SIGHUP killing the
        # process when the popup exits before cleanup completes
        clear_session_alerts "$SESSION_NAME"
        exit 0
    else
        error "Failed to find another session to switch to"
        exit 1
    fi
else
    # killing a different session (not current)
    if [[ "$NO_CONFIRM" != "--no-confirm" ]]; then
        # show visual confirmation for killing inactive session
        TITLE="Kill Session"
        MESSAGE="Kill inactive session '${SESSION_NAME}'?"

        if ! show_visual_confirm "$TITLE" "$MESSAGE"; then
            exit 0 # Exit cleanly on cancellation
        fi
    fi

    # User confirmed - save a fresh backup before killing
    save_undo_state "$SESSION_NAME"

    # Gracefully terminate running processes before killing the session
    terminate_session_processes "$SESSION_NAME"

    # kill the session
    tmux kill-session -t "$SESSION_NAME" 2>/dev/null || true

    # clear alerts synchronously; backgrounding risks SIGHUP killing the
    # process when the popup exits before cleanup completes
    clear_session_alerts "$SESSION_NAME"
fi
