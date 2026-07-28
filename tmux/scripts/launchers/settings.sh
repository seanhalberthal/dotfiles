#!/usr/bin/env bash
# shellcheck disable=SC2155
set -euo pipefail

# ══════════════════════════════════════════════════════════════
# Launcher Settings (inline root directory configuration)
# ══════════════════════════════════════════════════════════════
# configures DEV_ROOT and PROJECTS_ROOT from within the launcher
# picker. updates ~/.zshrc using the shared helper.
#
# called via ACTION:set from picker.sh

SCRIPT_DIR="${BASH_SOURCE%/*}"

# shellcheck source=tmux/scripts/_lib/common.sh
source "$SCRIPT_DIR/../_lib/common.sh"
# shellcheck source=scripts/_lib/common.sh
source "$DOTFILES_ROOT/scripts/_lib/common.sh"

# load current theme colours for fzf
load_fzf_theme
require_fzf

# ─────────────────────────────────────────
# resolve current values
# ─────────────────────────────────────────
dev_root="${DEV_ROOT:-}"
projects_root="${PROJECTS_ROOT:-}"

dev_display="${dev_root:-not set}"
[[ -z "$dev_root" ]] || dev_display="${dev_root/#$HOME/\~}"

proj_display="${projects_root:-not set}"
[[ -z "$projects_root" ]] || proj_display="${projects_root/#$HOME/\~}"

# ─────────────────────────────────────────
# show setting picker
# ─────────────────────────────────────────
content=""
content+=$'\n'
content+="  ${GREEN}Settings${NC}"$'\n'
content+="  ${GREY}Configure project root directories${NC}"$'\n'
content+=$'\n'
content+=$'\n'
content+="    DEV_ROOT          ${GREY}${dev_display}${NC}"$'\n'
content+="    PROJECTS_ROOT     ${GREY}${proj_display}${NC}"$'\n'

selection=$(printf '%s' "$content" | fzf \
    --ansi --reverse --disabled --cycle \
    --header-lines=5 \
    --padding=0,0,1,0 \
    --prompt=': ' \
    --border=rounded \
    --border-label=' j/k · spc/⏎ sel · q/esc ' \
    --border-label-pos=bottom \
    --bind 'j:down,k:up,q:abort' \
    --bind 'space:accept,enter:accept' \
    --bind 'esc:abort' \
    2>/dev/null) || exit 130

# extract selected variable name
var_name=$(printf '%s' "$selection" | awk '{print $1}')

case "$var_name" in
    DEV_ROOT)
        current_value="$dev_display"
        ;;
    PROJECTS_ROOT)
        current_value="$proj_display"
        ;;
    *)
        exit 130
        ;;
esac

# ─────────────────────────────────────────
# prompt for new value
# ─────────────────────────────────────────
default_query=""
[[ "$current_value" == "not set" ]] || default_query="$current_value"

new_value=$(printf '' | fzf \
    --print-query \
    --query="$default_query" \
    --prompt="${var_name}: " \
    --height=100% --layout=reverse \
    --border=rounded \
    --border-label=' ⏎ save · esc cancel ' \
    --border-label-pos=bottom \
    --no-info --pointer=' ' \
    --bind 'enter:print-query' \
    --bind 'esc:abort' \
    2>/dev/null | head -1) || exit 130

[[ -n "$new_value" ]] || exit 0

# expand ~ and resolve
new_value="${new_value/#\~/$HOME}"
if [[ -d "$new_value" ]]; then
    new_value=$(cd "$new_value" && pwd)
fi

# store with $HOME for portability
stored_value="\$HOME${new_value#"$HOME"}"

update_zshrc_export "$var_name" "$stored_value"

# show confirmation via tmux message, or stdout when outside tmux
if [[ -n "${TMUX:-}" ]]; then
    tmux display-message "${var_name} set to ${new_value/#$HOME/\~} (source ~/.zshrc to apply)"
else
    info "${var_name} set to ${new_value/#$HOME/\~} (source ~/.zshrc to apply)"
fi
