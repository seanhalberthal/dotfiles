#!/usr/bin/env bash
set -euo pipefail

# Extract and open URLs from tmux pane scrollback

SCRIPT_DIR="${BASH_SOURCE%/*}"
source "$SCRIPT_DIR/_lib/common.sh"
source "$SCRIPT_DIR/_lib/ui.sh"

PANE_ID="${1:-}"

# Capture pane content and extract URLs
if [[ -n "$PANE_ID" ]]; then
    urls=$(tmux capture-pane -t "$PANE_ID" -Jp -S -5000 2>/dev/null | grep -oE 'https?://[^][ \"<>]+' | tail -r | awk '!seen[$0]++') || true
else
    urls=$(tmux capture-pane -Jp -S -5000 2>/dev/null | grep -oE 'https?://[^][ \"<>]+' | tail -r | awk '!seen[$0]++') || true
fi

if [[ -z "$urls" ]]; then
    show_centered_message "No URLs found" \
        "" \
        "No URLs were found in the current pane scrollback."
    wait_for_key "Press any key to close..."
    exit 0
fi

selected=$(echo "$urls" | fzf \
    --reverse \
    --no-sort \
    --disabled \
    --cycle \
    --prompt ': ' \
    --border=rounded \
    --border-label=' j/k · g/G · f/b · d/u · spc/⏎ open · y yank · / srch · q/esc quit ' \
    --border-label-pos=bottom \
    --bind 'j:down,k:up,g:first,G:last,q:abort,space:accept' \
    --bind 'f:page-down,b:page-up' \
    --bind 'enter:accept' \
    --bind 'd:half-page-down,u:half-page-up' \
    --bind 'change:transform:[[ $FZF_PROMPT == ": " ]] && echo "clear-query"' \
    --bind '/:enable-search+change-prompt(> )+unbind(j,k,g,G,f,b,d,u,q,space,y)' \
    --bind 'esc:transform:[[ $FZF_PROMPT == "> " ]] && echo "disable-search+clear-query+change-prompt(: )+rebind(j,k,g,G,f,b,d,u,q,space,y)" || echo "abort"' \
    --bind 'ctrl-k:kill-line,ctrl-w:unix-line-discard' \
    --bind "y:execute-silent(echo -n {} | pbcopy)+abort" \
) || true

if [[ -n "$selected" ]]; then
    open "$selected"
fi
