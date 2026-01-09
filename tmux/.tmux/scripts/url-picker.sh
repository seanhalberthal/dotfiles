#!/usr/bin/env bash
# URL picker - extracts URLs from tmux pane and opens selected one

PANE_ID="$1"

# Capture pane content and extract URLs
urls=$(tmux capture-pane -t "$PANE_ID" -Jp -S -5000 | grep -oE 'https?://[^][ \"<>]+' | tail -r | awk '!seen[$0]++')

if [[ -z "$urls" ]]; then
    echo "No URLs found in pane"
    read -n1 -s -p "Press any key to close..."
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
)

if [[ -n "$selected" ]]; then
    open "$selected"
fi
