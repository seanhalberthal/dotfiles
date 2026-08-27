#!/usr/bin/env bash
# shellcheck disable=SC2016,SC2155
set -euo pipefail

# ══════════════════════════════════════════════════════════════
# launcher picker wrapper
# ══════════════════════════════════════════════════════════════
# runs the launcher picker in a loop so that pressing Esc in a
# submenu (new/edit/run) returns to the main picker list
# called from tmux keybinding: prefix + p

SCRIPT_DIR="${BASH_SOURCE%/*}"

# shellcheck source=tmux/scripts/_lib/common.sh
source "$SCRIPT_DIR/../_lib/common.sh"

# load current theme colours for fzf
load_fzf_theme
require_fzf

# argument parsing + auto-detection
#
# the dotfiles ASCII logo eats 7 rows of header space, which is fine on a
# spacious popup but crowds out launchers when the popup is narrow OR short.
# we query the popup pty directly via `stty size` (env vars from the parent
# shell can lie about the popup's real dimensions) and drop the logo when:
#   - width  < 80 rows: matches the session picker's `<80(bottom,40%)`
#     vertical-preview threshold, so both pickers compact at the same size
#   - height < 20 rows: leaves at least ~8 visible launcher rows after the
#     logo + border + prompt chrome (~12 rows) are accounted for
# `--no-logo` forces it off regardless
LIST_ARGS=()
HEADER_LINES=7
NO_LOGO=0

for arg in "$@"; do
    case "$arg" in
        --no-logo) NO_LOGO=1 ;;
    esac
done

if ((!NO_LOGO)); then
    popup_height=24
    popup_width=80
    read -r popup_height popup_width < <(stty size 2>/dev/null) || true
    if ((popup_width < 80)) || ((popup_height < 20)); then
        NO_LOGO=1
    fi
fi

if ((NO_LOGO)); then
    LIST_ARGS+=(--no-logo)
    HEADER_LINES=0
fi

main() {
    while true; do
        local action
        action=$("$SCRIPT_DIR/list.sh" "${LIST_ARGS[@]}" | fzf \
            --ansi --reverse --exact --disabled --cycle \
            --delimiter=$'\t' --with-nth=2 --tiebreak=begin,length \
            --color="label:${TMUX_FG_PRIMARY:-#ffffff}" \
            --header-lines="$HEADER_LINES" \
            --padding=0,0,1,0 \
            --prompt=': ' \
            --border=rounded \
            --border-label=' j/k · d/u · g/G · spc/⏎ sel · / search · n new · e edit · D dup · x del · s set · q/esc ' \
            --border-label-pos=bottom \
            --bind 'j:down,k:up,g:first,G:last,d:half-page-down,u:half-page-up,q:abort' \
            --bind 'change:transform:[[ $FZF_PROMPT == ": " ]] && echo "clear-query"' \
            --bind '/:enable-search+change-prompt(> )+unbind(j,k,g,G,d,u,q,n,e,x,s,D)' \
            --bind 'esc:transform:[[ $FZF_PROMPT == "> " ]] && echo "disable-search+clear-query+change-prompt(: )+rebind(j,k,g,G,d,u,q,n,e,x,s,D)" || echo "abort"' \
            --bind 'ctrl-k:up,ctrl-l:clear-query' \
            --bind 'n:become(printf "ACTION:new")' \
            --bind 's:become(printf "ACTION:set")' \
            --bind 'e:become(printf "ACTION:edit:%s" {1})' \
            --bind "x:execute($SCRIPT_DIR/delete.sh {1})+reload-sync($SCRIPT_DIR/list.sh ${LIST_ARGS[*]})" \
            --bind "D:become(printf 'ACTION:dup:%s' \$($SCRIPT_DIR/duplicate.sh {1}))" \
            --bind 'enter:become(printf "ACTION:run:%s" {1})' \
            --bind 'space:become(printf "ACTION:run:%s" {1})' \
            2>/dev/null) || break # q/esc from main list closes popup

        case "$action" in
            ACTION:new)
                "$SCRIPT_DIR/prompt.sh" && break
                continue # cancelled, back to picker
                ;;
            ACTION:set)
                "$SCRIPT_DIR/settings.sh" || true
                continue # always return to picker
                ;;
            ACTION:edit:*)
                local edit_name="${action#ACTION:edit:}"
                edit_name=$(basename "$edit_name")
                # only user launchers can be edited, system launchers are read-only
                if [[ ! -f "$USER_LAUNCHERS/$edit_name" ]]; then
                    show_error "Cannot edit system launcher '$edit_name'"
                    continue
                fi
                "$SCRIPT_DIR/prompt.sh" --edit "$edit_name" && break
                continue
                ;;
            ACTION:dup:*)
                local dup_name="${action#ACTION:dup:}"
                dup_name=$(basename "$dup_name")
                "$SCRIPT_DIR/prompt.sh" --edit "$dup_name" && break
                # cancelled, clean up the copy and return to picker
                rm -f "$USER_LAUNCHERS/$dup_name"
                continue
                ;;
            ACTION:run:*)
                "$SCRIPT_DIR/run.sh" "${action#ACTION:run:}" && break
                continue
                ;;
            *)
                break
                ;;
        esac
    done
}

main "$@"
