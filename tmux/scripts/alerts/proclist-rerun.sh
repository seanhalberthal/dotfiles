#!/usr/bin/env bash
# proclist rerun binding: replay a finished command in its origin window.
#   r (stage): type it onto the prompt, no Enter, the user reviews then runs it
#   R (run):   type it and press Enter, running it straight away
# the full command is read from the finished history by key (epoch+window_id) so
# the raw text never crosses the fzf/shell boundary.
# usage: proclist-rerun.sh <epoch> <window_id> [exec]
set -euo pipefail

SCRIPT_DIR="${BASH_SOURCE%/*}"
source "$SCRIPT_DIR/../_lib/alerts.sh"

EPOCH="${1:-}"
WID="${2:-}"
MODE="${3:-stage}" # stage (default, no run) or exec (run it)

# need a history key and tmux; no-op for running rows (their key never matches)
[[ -n "$EPOCH" && -n "$WID" && -f "$FINISHED_FILE" ]] || exit 0
command -v tmux >/dev/null 2>&1 || exit 0

# pull field 7 (full command) for this exact row; empty for pre-rerun rows
cmd=$(awk -F'\t' -v e="$EPOCH" -v w="$WID" '$1==e && $4==w {print $7; exit}' \
    "$FINISHED_FILE" 2>/dev/null || true)
[[ -n "$cmd" ]] || exit 0

# type literally into the window's active pane. -- stops option parsing so a
# command starting with '-' isn't read as a flag
tmux send-keys -t "$WID" -l -- "$cmd" 2>/dev/null || true
# run mode: press Enter to execute it; stage mode leaves it on the prompt to review
[[ "$MODE" == "exec" ]] && tmux send-keys -t "$WID" Enter 2>/dev/null || true
