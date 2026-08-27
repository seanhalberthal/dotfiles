#!/usr/bin/env bash
# proclist x-binding dispatcher: stop a running process or dismiss a finished one.
#   run  <pane target> <pane_id>     -> interrupt the pane's foreground command
#   done <window_id>   <epoch> <wid> -> drop the entry from finished history
# called from the prefix+P fzf binding with the row's hidden fields.
set -euo pipefail

SCRIPT_DIR="${BASH_SOURCE%/*}"
source "$SCRIPT_DIR/../_lib/alerts.sh"

TYPE="${1:-}"
TARGET="${2:-}"
A="${3:-}"
B="${4:-}"

case "$TYPE" in
    run)
        # mark this pane's next completion as an intentional kill so precmd
        # (cmd-alert-hook.zsh) skips the alert + finished-history row for it;
        # written before the interrupt to avoid a race with a fast exit
        if [[ -n "$A" ]]; then
            mkdir -p "$SUPPRESS_DIR" 2>/dev/null
            : >"$SUPPRESS_DIR/${A#%}" 2>/dev/null || true
        fi
        # interrupt the pane's foreground command; the shell's precmd then
        # clears the registry. remove the file too so the list updates at once
        [[ -n "$TARGET" ]] && tmux send-keys -t "$TARGET" C-c 2>/dev/null || true
        [[ -n "$A" ]] && rm -f "$RUNNING_DIR/${A#%}" 2>/dev/null || true
        ;;
    done)
        # A=finish epoch, B=window_id: drop that one entry from the history file
        if [[ -n "$A" && -f "$FINISHED_FILE" ]]; then
            tmpf=$(mktemp "${FINISHED_FILE}.XXXXXX") || exit 0
            if awk -F'\t' -v e="$A" -v w="$B" '!($1 == e && $4 == w)' \
                "$FINISHED_FILE" >"$tmpf" 2>/dev/null; then
                mv "$tmpf" "$FINISHED_FILE" 2>/dev/null || rm -f "$tmpf"
            else
                rm -f "$tmpf"
            fi
        fi
        # clear the window's exit indicator (status-right + window-status) on the
        # same keystroke, keyed on window_id. the indicator is one-per-window,
        # decoupled from how many finished rows the window has, so gating on a
        # remaining-rows count stranded it whenever the other rows aged out via
        # GC. the id is stable under automatic-rename where the stored name is not
        [[ -n "$B" ]] && clear_window_exit_alert "$B"
        ;;
esac
