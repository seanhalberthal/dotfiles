#!/usr/bin/env bash
set -euo pipefail

# extract and open URLs from tmux pane scrollback

SCRIPT_DIR="${BASH_SOURCE%/*}"
source "$SCRIPT_DIR/../_lib/common.sh"
source "$SCRIPT_DIR/../_lib/ui.sh"

# load current theme colours for fzf
load_fzf_theme

PANE_ID="${1:-}"
CLIPBOARD_CMD=$(clipboard_copy_cmd)

# extract URLs from text, cleaning trailing punctuation and balancing parens
# handles: trailing ,.:;!?' and unbalanced closing parens/brackets
extract_urls() {
    grep -oE "https?://[^][[:space:]\"'<>{}|\\\^]+" | awk '{
        # Strip trailing punctuation that is almost never part of a URL
        while (match($0, /[,.:;!?]+$/)) $0 = substr($0, 1, RSTART - 1)
        # Strip trailing ) only if no matching ( in URL (unbalanced)
        if (match($0, /\)+$/) && index($0, "(") == 0) $0 = substr($0, 1, RSTART - 1)
        # Strip trailing ] only if no matching [ in URL (unbalanced)
        if (match($0, /\]+$/) && index($0, "[") == 0) $0 = substr($0, 1, RSTART - 1)
    } NF { if (seen[$0] == 0) { seen[$0] = 1; print } }'
}

# capture pane content and extract URLs
if [[ -n "$PANE_ID" ]]; then
    urls=$(tmux capture-pane -t "$PANE_ID" -Jp -S -50000 2>/dev/null | extract_urls | reverse_lines) || true
else
    urls=$(tmux capture-pane -Jp -S -50000 2>/dev/null | extract_urls | reverse_lines) || true
fi

if [[ -z "$urls" ]]; then
    show_notification "No URLs found in scrollback" 1
    exit 0
fi

selected=$(
    echo "$urls" | fzf \
        --reverse \
        --exact \
        --no-sort \
        --disabled \
        --cycle \
        --prompt ': ' \
        --border=rounded \
        --border-label=' j/k · g/G · f/b · d/u · o/spc/⏎ open · y yank · / search · q/esc quit ' \
        --border-label-pos=bottom \
        --bind 'j:down,k:up,g:first,G:last,q:abort,space:accept,o:accept' \
        --bind 'f:page-down,b:page-up' \
        --bind 'enter:accept' \
        --bind 'd:half-page-down,u:half-page-up' \
        --bind 'change:transform:[[ $FZF_PROMPT == ": " ]] && echo "clear-query"' \
        --bind '/:enable-search+change-prompt(> )+unbind(j,k,g,G,f,b,d,u,q,space,y,o)' \
        --bind 'esc:transform:[[ $FZF_PROMPT == "> " ]] && echo "disable-search+clear-query+change-prompt(: )+rebind(j,k,g,G,f,b,d,u,q,space,y,o)" || echo "abort"' \
        --bind 'ctrl-k:up,ctrl-l:clear-query' \
        --bind "y:execute-silent(echo -n {} | $CLIPBOARD_CMD)+abort"
) || true

if [[ -n "$selected" ]]; then
    open_url "$selected"
fi
