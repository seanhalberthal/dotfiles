#!/usr/bin/env bash
# shellcheck disable=SC2016,SC2155
set -euo pipefail

# ══════════════════════════════════════════════════════════════
# Theme Picker Wrapper
# ══════════════════════════════════════════════════════════════
# interactive theme selector using fzf with vim-style navigation.
# called from tmux keybinding: prefix + t

SCRIPT_DIR="${BASH_SOURCE%/*}"

# shellcheck source=tmux/scripts/_lib/common.sh
source "$SCRIPT_DIR/../_lib/common.sh"

# load current theme colours for fzf
load_fzf_theme
require_fzf

main() {
    local theme_list theme_pos
    theme_list=$("$SCRIPT_DIR/pick.sh")
    theme_pos=1
    local line idx=0
    while IFS= read -r line; do
        if ((idx < 5)); then
            idx=$((idx + 1))
            continue
        fi
        idx=$((idx + 1))
        case "$line" in
            *'● '*)
                theme_pos=$((idx - 5))
                break
                ;;
        esac
    done <<<"$theme_list"

    local selected
    selected=$(echo "$theme_list" | fzf \
        --ansi --reverse --exact --disabled --cycle \
        --with-nth=2.. \
        --info=inline-right \
        --bind "start:clear-query+execute-silent(rm -f /tmp/.fzf-theme-pos)" \
        --bind "load:pos($theme_pos)" \
        --bind 'result:transform:[[ -f /tmp/.fzf-theme-pos ]] && { echo "clear-query+$(cat /tmp/.fzf-theme-pos)"; rm -f /tmp/.fzf-theme-pos; } || true' \
        --color="label:${TMUX_FG_PRIMARY:-#ffffff}" \
        --header-lines=5 \
        --padding=0,0,1,0 \
        --prompt ': ' \
        --border=rounded \
        --border-label=' j/k · d/u · g/G · f fav · r rand · spc/⏎ sel · / srch · q/esc ' \
        --border-label-pos=bottom \
        --bind 'j:down,k:up,g:first,G:last,d:half-page-down,u:half-page-up,q:abort,space:accept' \
        --bind 'enter:accept' \
        --bind 'change:transform:[[ $FZF_PROMPT == ": " ]] && echo "clear-query"' \
        --bind "f:execute-silent($SCRIPT_DIR/pick.sh --toggle-fav {1})+reload-sync($SCRIPT_DIR/pick.sh --reload {1})" \
        --bind "r:become($SCRIPT_DIR/pick.sh --random)" \
        --bind '/:enable-search+change-prompt(> )+unbind(j,k,g,G,d,u,q,space,f,r)' \
        --bind 'esc:transform:[[ $FZF_PROMPT == "> " ]] && echo "disable-search+clear-query+change-prompt(: )+rebind(j,k,g,G,d,u,q,space,f,r)" || echo "abort"' \
        --bind 'ctrl-k:up,ctrl-l:clear-query' \
        2>/dev/null) || return 0

    local theme="${selected%% *}"
    [[ -n "$theme" ]] || return 0

    "$DOTFILES_ROOT/scripts/theme-switch" "$theme" --no-reload --quiet &&
        tmux source-file "$HOME/.tmux.conf" &&
        "$SCRIPT_DIR/reload-ghostty.sh" &&
        "$SCRIPT_DIR/reload-fzf.sh" &&
        tmux display-message "Theme: $theme"
}

main "$@"
