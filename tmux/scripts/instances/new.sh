#!/usr/bin/env bash
set -euo pipefail

# create a new window in the current session and launch a process
#
# usage: new.sh <process_name>
#   process_name: claude, codex, opencode, copilot, or nvim

SCRIPT_DIR="${BASH_SOURCE%/*}"
source "$SCRIPT_DIR/../_lib/common.sh"

require_tmux

if [[ $# -lt 1 ]]; then
    show_error "Usage: new.sh <process_name>"
    exit 1
fi

PROCESS="$1"

# validate process name
case "$PROCESS" in
    claude|codex|opencode|copilot|nvim) ;;
    *)
        show_error "Unknown process: $PROCESS"
        exit 1
        ;;
esac

# session id, not name: 'new-window -t <name>' resolves a window with that name
# ahead of the session, pinning the new window to an occupied index and failing
# with "index in use". the trailing ':' keeps the target session-scoped
SESSION=$(tmux display-message -p '#{session_id}')
DIR=$(tmux display-message -p '#{pane_current_path}')

# capture the window id so later commands stay unambiguous when several windows
# share a name, and survive renumber-windows shifting indices underneath us
if ! TARGET=$(tmux new-window -P -F '#{window_id}' -t "${SESSION}:" -n "$PROCESS" -c "$DIR" 2>&1); then
    show_error "Could not create $PROCESS window: $TARGET"
    exit 1
fi

# claude windows track the session title via the OSC title branch of
# automatic-rename-format; others stay static. new-window -n disables
# automatic-rename for the window, so claude must re-enable it explicitly
if [[ "$PROCESS" == "claude" ]]; then
    tmux set-window-option -t "$TARGET" automatic-rename on
else
    tmux set-window-option -t "$TARGET" automatic-rename off
fi
tmux send-keys -t "$TARGET" "$PROCESS" Enter

# switch client to the new window
tmux switch-client -t "$TARGET"
