#!/usr/bin/env bash
# shellcheck disable=SC2155,SC2059
set -euo pipefail

# ══════════════════════════════════════════════════════════════
# Tmux Theme List Provider
# ══════════════════════════════════════════════════════════════
# lists themes (with current/favourite markers) for the picker
# called by picker.sh to feed fzf; also handles --reload/--pos/--toggle-fav

SCRIPT_DIR="${BASH_SOURCE%/*}"

# shellcheck source=tmux/scripts/_lib/common.sh
source "$SCRIPT_DIR/../_lib/common.sh"

# load current theme colours for fzf
load_fzf_theme
THEMES_DIR="$DOTFILES_ROOT/themes"
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/dotfiles"
CURRENT_THEME_FILE="$CONFIG_DIR/current-theme"

# get current theme
get_current_theme() {
    if [[ -f "$CURRENT_THEME_FILE" ]]; then
        cat "$CURRENT_THEME_FILE"
    else
        echo "dracula"
    fi
}

# check if a hand-crafted theme exists for a given name
is_custom_theme() {
    [[ -f "$THEMES_DIR/$1.theme" ]]
}

# list themes in fzf-compatible format, sorted by most recently used
list_themes_for_fzf() {
    local current_theme
    current_theme=$(get_current_theme)

    # header (consumed by fzf --header-lines)
    printf "${CYAN}╭─────────────────────────────────────────────────────────────╮${NC}\n"
    printf "${CYAN}│${NC}  ${GREEN}Theme Switcher${NC}                                            ${CYAN}│${NC}\n"
    printf "${CYAN}│${NC}  Select a theme to apply to tmux and ghostty               ${CYAN}│${NC}\n"
    printf "${CYAN}╰─────────────────────────────────────────────────────────────╯${NC}\n"
    printf "\n"

    # collect all themes into temp files
    tmpdir=$(mktemp -d)
    trap 'rm -rf "${tmpdir:-}"' EXIT

    local all_themes="$tmpdir/all"
    {
        "$DOTFILES_ROOT/scripts/generate-theme" list 2>/dev/null || true
        for theme_file in "$THEMES_DIR"/*.theme; do
            if [[ -f "$theme_file" ]]; then
                basename "$theme_file" .theme
            fi
        done
    } | sort -u >"$all_themes"

    # build MRU list from history (most recent first, deduplicated)
    local mru_file="$tmpdir/mru"
    touch "$mru_file"
    if [[ -f "$THEME_HISTORY" ]]; then
        awk '{ lines[NR] = $0; count = NR } END { for (i = count; i >= 1; i--) print lines[i] }' "$THEME_HISTORY" |
            awk '!seen[$0]++' >"$mru_file"
    fi

    # build lookup sets using associative arrays (O(1) vs per-line grep)
    declare -A valid_set fav_set custom_set bright_set emitted

    while IFS= read -r t; do valid_set["$t"]=1; done <"$all_themes"
    if [[ -f "$THEME_FAVOURITES" ]]; then
        while IFS= read -r t; do [[ -n "$t" ]] && fav_set["$t"]=1; done <"$THEME_FAVOURITES"
    fi
    for theme_file in "$THEMES_DIR"/*.theme; do
        [[ -f "$theme_file" ]] && custom_set["$(basename "$theme_file" .theme)"]=1
    done
    while IFS= read -r t; do [[ -n "$t" ]] && bright_set["$t"]=1; done \
        < <("$DOTFILES_ROOT/scripts/generate-theme" bright-list 2>/dev/null)

    local -a mru_list=()
    while IFS= read -r t; do [[ -n "$t" ]] && mru_list+=("$t"); done <"$mru_file"

    # format a single theme line for fzf
    _format_line() {
        local id="$1"
        local marker
        if [[ "$id" == "$current_theme" ]]; then
            marker="${GREEN}● ${NC}"
        else
            marker="${GREY}○ ${NC}"
        fi
        local tag=""
        [[ -n "${custom_set[$id]:-}" ]] && tag+=" ${YELLOW}#custom${NC}"
        [[ -n "${bright_set[$id]:-}" ]] && tag+=" ${RED}#bright${NC}"
        [[ -n "${fav_set[$id]:-}" ]] && tag+=" ${CYAN}★${NC}"
        printf "%s %b%s%b\n" "$id" "$marker" "$id" "$tag"
    }

    # order: favourites (MRU then alpha) -> non-fav MRU -> remaining alpha

    # pass 1: fav MRU
    for t in "${mru_list[@]}"; do
        [[ -n "${valid_set[$t]:-}" && -n "${fav_set[$t]:-}" && -z "${emitted[$t]:-}" ]] || continue
        emitted["$t"]=1
        _format_line "$t"
    done
    # pass 2: fav non-MRU (alpha; all_themes is pre-sorted)
    while IFS= read -r t; do
        [[ -n "${fav_set[$t]:-}" && -z "${emitted[$t]:-}" ]] || continue
        emitted["$t"]=1
        _format_line "$t"
    done <"$all_themes"
    # pass 3: non-fav MRU
    for t in "${mru_list[@]}"; do
        [[ -n "${valid_set[$t]:-}" && -z "${emitted[$t]:-}" ]] || continue
        emitted["$t"]=1
        _format_line "$t"
    done
    # pass 4: remaining alpha
    while IFS= read -r t; do
        [[ -z "${emitted[$t]:-}" ]] || continue
        emitted["$t"]=1
        _format_line "$t"
    done <"$all_themes"

}

# toggle a theme's favourite status
toggle_favourite() {
    local theme_id="$1"
    local fav_dir
    fav_dir="$(dirname "$THEME_FAVOURITES")"
    mkdir -p "$fav_dir"

    if [[ -f "$THEME_FAVOURITES" ]] && grep -qxF "$theme_id" "$THEME_FAVOURITES" 2>/dev/null; then
        # remove from favourites
        grep -vxF "$theme_id" "$THEME_FAVOURITES" >"$THEME_FAVOURITES.tmp" || true
        mv "$THEME_FAVOURITES.tmp" "$THEME_FAVOURITES"
    else
        # add to favourites
        printf '%s\n' "$theme_id" >>"$THEME_FAVOURITES"
    fi
}

# pick a random non-bright theme and apply it
random_theme() {
    local all_themes bright_themes
    all_themes=$("$DOTFILES_ROOT/scripts/generate-theme" list 2>/dev/null)
    bright_themes=$("$DOTFILES_ROOT/scripts/generate-theme" bright-list 2>/dev/null)

    # filter out bright themes and current theme, pick one at random
    local current_theme pick
    current_theme=$(cat "${XDG_CONFIG_HOME:-$HOME/.config}/dotfiles/current-theme" 2>/dev/null || true)
    pick=$(comm -23 <(echo "$all_themes" | sort) <(echo "$bright_themes" | sort) |
        grep -vxF "$current_theme" |
        awk -v seed="$RANDOM" 'BEGIN{srand(seed)} {a[NR]=$0} END{print a[int(rand()*NR)+1]}')

    if [[ -n "$pick" ]]; then
        echo "$pick"
    fi
}

# get 1-based position of current theme in the fzf item list
# generates the list internally (skipping 5 header lines) and finds the ● marker
get_current_position() {
    local output
    output=$(list_themes_for_fzf)
    local pos
    pos=$(printf '%s\n' "$output" | tail -n +6 | grep -n '● ' | head -1 | cut -d: -f1) || true
    echo "${pos:-1}"
}

# generate theme list for fzf reload and stash the target theme's position
# usage: pick.sh --reload [theme-id]
# outputs the full list to stdout (for fzf reload-sync)
# writes "pos(N)" to /tmp/.fzf-theme-pos (for fzf transform)
reload_with_position() {
    local target="${1:-$(get_current_theme)}"
    local pos_file="/tmp/.fzf-theme-pos"
    local output
    output=$(list_themes_for_fzf)
    local pos
    pos=$(printf '%s\n' "$output" | tail -n +6 | grep -n "^${target} " | head -1 | cut -d: -f1)
    printf 'pos(%s)\n' "${pos:-1}" >"$pos_file"
    printf '%s\n' "$output"
}

# main
main() {
    case "${1:-}" in
        --pos)
            get_current_position
            ;;
        --reload)
            reload_with_position "${2:-}"
            ;;
        --toggle-fav)
            toggle_favourite "${2:?theme name required}"
            ;;
        --random)
            random_theme
            ;;
        *)
            list_themes_for_fzf
            ;;
    esac
}

main "$@"
