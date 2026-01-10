#!/usr/bin/env bash
# URL picker - extracts URLs from tmux pane and opens selected one

PANE_ID="$1"

# Capture pane content and extract URLs
urls=$(tmux capture-pane -t "$PANE_ID" -Jp -S -5000 | grep -oE 'https?://[^][ \"<>]+' | tail -r | awk '!seen[$0]++')

if [[ -z "$urls" ]]; then
    # Get terminal dimensions
    term_height=$(tput lines)
    term_width=$(tput cols)

    # Box dimensions (5 lines for box + 2 for spacing + 1 for prompt = 8 total)
    box_height=8
    box_width=31

    # Calculate vertical padding
    v_pad=$(( (term_height - box_height) / 2 ))
    [[ $v_pad -lt 0 ]] && v_pad=0

    # Calculate horizontal padding
    h_pad=$(( (term_width - box_width) / 2 ))
    [[ $h_pad -lt 0 ]] && h_pad=0
    pad=$(printf '%*s' "$h_pad" '')

    # Clear screen and print centered dialog
    clear
    for ((i=0; i<v_pad; i++)); do printf '\n'; done

    printf '%s\033[38;5;141m╭─────────────────────────────╮\033[0m\n' "$pad"
    printf '%s\033[38;5;141m│\033[0m                             \033[38;5;141m│\033[0m\n' "$pad"
    printf '%s\033[38;5;141m│\033[0m   \033[38;5;245mNo URLs found in pane\033[0m     \033[38;5;141m│\033[0m\n' "$pad"
    printf '%s\033[38;5;141m│\033[0m                             \033[38;5;141m│\033[0m\n' "$pad"
    printf '%s\033[38;5;141m╰─────────────────────────────╯\033[0m\n' "$pad"
    printf '\n'
    printf '%s\033[38;5;245mPress any key to close...\033[0m' "$pad"
    read -n1 -s
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
