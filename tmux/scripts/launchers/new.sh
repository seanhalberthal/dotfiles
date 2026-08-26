#!/usr/bin/env bash
# shellcheck disable=SC2059,SC2016
set -euo pipefail

# ══════════════════════════════════════════════════════════════
# New Launcher Wizard
# ══════════════════════════════════════════════════════════════
# step-based wizard for creating/editing session launchers
# supports ctrl+b to go back a step
#
# usage: new.sh [name]
#        new.sh --edit SOURCE [name]

SCRIPT_DIR="${BASH_SOURCE%/*}"
# shellcheck source=tmux/scripts/_lib/common.sh
source "$SCRIPT_DIR/../_lib/common.sh"

USER_LAUNCHERS="${XDG_CONFIG_HOME:-$HOME/.config}/dotfiles/launchers"

# strip shell-escape backslashes from a pasted path. fzf gives literal text
# (not shell-parsed), so `~/Library/Mobile\ Documents/...` arrives with the
# backslashes intact and fails the [[ -d ... ]] check downstream
unescape_paste() {
    local s="$1"
    s="${s//\\ / }"
    s="${s//\\~/~}"
    printf '%s' "$s"
}

# expand a leading ~ or $HOME into an absolute path for filesystem checks
expand_path() {
    local s="$1"
    s="${s/#\~\//$HOME/}"
    s="${s/#\~/$HOME}"
    s="${s/#\$HOME/$HOME}"
    printf '%s' "$s"
}

# first configured project root (~ form), the default base for new launchers.
# pulls from PROJECT_DIRS (colon-separated, like list_project_dirs) rather than
# hardcoding ~/src
default_project_root() {
    local first="${PROJECT_DIRS:-$HOME/src}"
    first="${first%%:*}"
    first="${first/#\~/$HOME}"
    printf '%s' "${first/#$HOME/\~}"
}

# ensure stdin/stdout use terminal (needed when called via fzf become() in a pipeline)
# security note: this redirects to the controlling terminal, bypassing any pipe isolation
# safe here because this script is only invoked interactively from the launcher picker
exec </dev/tty >/dev/tty

# ─────────────────────────────────────────
# argument parsing
# ─────────────────────────────────────────
edit_source=""
name=""

if [[ "${1:-}" == "--edit" ]]; then
    edit_source="${2:-}"
    shift 2
fi

name="${1:-}"

# ─────────────────────────────────────────
# helpers for edit mode
# ─────────────────────────────────────────
resolve_edit_source() {
    local source="$1"
    source=$(basename "$source")
    if [[ "$source" == "." ]] || [[ "$source" == ".." ]] || [[ "$source" == *"/"* ]]; then
        printf '%s' ""
        return 1
    fi
    if [[ -x "$USER_LAUNCHERS/$source" ]]; then
        printf '%s' "$USER_LAUNCHERS/$source"
        return 0
    fi
    if [[ -x "$SCRIPT_DIR/../launchers/$source" ]]; then
        printf '%s' "$SCRIPT_DIR/../launchers/$source"
        return 0
    fi
    printf '%s' ""
    return 1
}

index_for_window() {
    local target="$1"
    local i
    for ((i = 0; i < ${#win_names[@]}; i++)); do
        if [[ "${win_names[$i]}" == "$target" ]]; then
            printf '%s' "$i"
            return 0
        fi
    done
    return 1
}

load_existing_launcher() {
    local file="$1"

    description=$(grep -m1 '# @description:' "$file" 2>/dev/null | sed 's/.*# @description: *//' || true)
    if grep -q '# @instance: *prompt' "$file" 2>/dev/null; then
        instance_mode="y"
    else
        instance_mode="n"
    fi
    # new format: separate `_<SESSION>_ROOT_DEFAULT="$HOME/path"` line, handles
    # paths containing apostrophes (which break `"${VAR:-default}"` parsing)
    # old format (kept for backward compat): `PROJECT_DIR="${VAR:-default}"`
    project_dir=$(grep -m1 '^_[A-Z0-9_]*_ROOT_DEFAULT=' "$file" 2>/dev/null |
        sed 's/^[^=]*=//' | sed 's/^"//; s/"$//' || true)
    if [[ -z "$project_dir" ]]; then
        project_dir=$(grep -m1 '^PROJECT_DIR=' "$file" 2>/dev/null | sed 's/^PROJECT_DIR=//' | tr -d '"' || true)
        if [[ "$project_dir" =~ :-(.+)\}$ ]]; then
            project_dir="${BASH_REMATCH[1]}"
        fi
    fi
    project_dir="${project_dir/#\$HOME/\~}"

    # detect worktree configuration
    if grep -q '^WORKTREES_DIR=\|^_[A-Z0-9_]*_WORKTREES_DEFAULT=' "$file" 2>/dev/null; then
        worktree_aware="y"
        worktrees_dir=$(grep -m1 '^_[A-Z0-9_]*_WORKTREES_DEFAULT=' "$file" 2>/dev/null |
            sed 's/^[^=]*=//' | sed 's/^"//; s/"$//' || true)
        if [[ -z "$worktrees_dir" ]]; then
            worktrees_dir=$(grep -m1 '^WORKTREES_DIR=' "$file" 2>/dev/null | sed 's/^WORKTREES_DIR=//' | tr -d '"' || true)
            if [[ "$worktrees_dir" =~ :-(.+)\}$ ]]; then
                worktrees_dir="${BASH_REMATCH[1]}"
            fi
        fi
        worktrees_dir="${worktrees_dir/#\$HOME/\~}"
    else
        worktree_aware="n"
    fi

    win_names=()
    win_cmds=()
    win_splits=()
    win_split_cmds=()

    local current_win=""
    while IFS= read -r line; do
        if [[ "$line" =~ ^tmux\ new-session.*-n\ \"?([^\"]+)\"? ]]; then
            current_win="${BASH_REMATCH[1]}"
            win_names+=("$current_win")
            win_cmds+=("")
            win_splits+=("no")
            win_split_cmds+=("")
        elif [[ "$line" =~ ^tmux\ new-window.*-n\ \"?([^\"]+)\"? ]]; then
            current_win="${BASH_REMATCH[1]}"
            win_names+=("$current_win")
            win_cmds+=("")
            win_splits+=("no")
            win_split_cmds+=("")
        elif [[ "$line" =~ ^tmux\ split-window.*-t\ \"?\$SESSION:([^\"\ ]+)\"? ]]; then
            # target may be the window name (our format) or include a pane index
            # like `dev.1` (hand-written launchers); strip a trailing .N so the
            # window still matches and the split flag is preserved
            local split_win="${BASH_REMATCH[1]}"
            [[ "$split_win" =~ \.[0-9]+$ ]] && split_win="${split_win%.*}"
            if idx=$(index_for_window "$split_win"); then
                win_splits[idx]="yes"
            fi
        elif [[ "$line" =~ ^tmux\ send-keys\ -t\ \"?\$SESSION:([^\"\ ]+)\.([12])\"?\ \'(.*)\'\ Enter ]]; then
            local cmd_win="${BASH_REMATCH[1]}"
            local pane="${BASH_REMATCH[2]}"
            local cmd="${BASH_REMATCH[3]}"
            if idx=$(index_for_window "$cmd_win"); then
                if [[ "$pane" == "1" ]]; then
                    win_cmds[idx]="$cmd"
                else
                    win_split_cmds[idx]="$cmd"
                fi
            fi
        elif [[ "$line" =~ ^tmux\ send-keys\ -t\ \"?\$SESSION:([^\"\ ]+)\"?\ \'(.*)\'\ Enter ]]; then
            local cmd_win="${BASH_REMATCH[1]}"
            local cmd="${BASH_REMATCH[2]}"
            if idx=$(index_for_window "$cmd_win"); then
                win_cmds[idx]="$cmd"
            fi
        fi
    done <"$file"

    if [[ ${#win_names[@]} -gt 0 ]]; then
        num_windows="${#win_names[@]}"
    fi

    # recalculate total steps with pre-loaded window count
    if [[ -n "$num_windows" ]]; then
        total_steps=$((4 + num_windows))
    fi
}

# ─────────────────────────────────────────
# additional colour definitions
# ─────────────────────────────────────────
DIM=$'\033[2m'

# ─────────────────────────────────────────
# ctrl+b back navigation
# ─────────────────────────────────────────
# read -e enables readline. rebind ctrl+b to: clear line → insert
# text marker → auto-submit. the ask functions detect the marker
# and return 1 (go back). left arrow still works for cursor movement
BACK_MARKER="__BACK__"
bind '"\C-b": "\C-a\C-k__BACK__\C-m"' 2>/dev/null

# ─────────────────────────────────────────
# UI helpers
# ─────────────────────────────────────────

# draw wizard header with step indicator
# usage: draw_header "step_num" "total_steps"
draw_header() {
    local step="$1"
    local total="$2"
    local width=62
    local title
    if [[ -n "$edit_source" ]]; then
        title="Edit Launcher"
    else
        title="New Launcher"
    fi
    local indicator="step $step of $total"
    local label_plain="$title  ·  $indicator"
    local label="$title  ${DIM}·  $indicator${NC}"

    # centre the box horizontally
    local term_width=${COLUMNS:-$(tput cols)}
    local box_width=$((width + 2)) # ╭ + inner + ╮
    local margin=$(((term_width - box_width) / 2))
    [[ $margin -lt 0 ]] && margin=0
    local pad
    pad=$(printf '%*s' "$margin" '')

    clear
    printf "\n"
    printf "%s${CYAN}╭%s╮${NC}\n" "$pad" "$(printf '─%.0s' $(seq 1 $width))"
    printf "%s${CYAN}│${NC}  %s%*s${CYAN}│${NC}\n" "$pad" "$label" $((width - ${#label_plain} - 2)) ""
    printf "%s${CYAN}╰%s╯${NC}\n" "$pad" "$(printf '─%.0s' $(seq 1 $width))"
    printf "\n"
}

# draw footer with controls (fzf border-label style)
# usage: draw_footer "back_hint"
#   "false"  = no back option (not shown)
#   "true"   = ^b back
#   "rename" = ^b rename
draw_footer() {
    local back_hint="$1"
    local hints=" enter"
    case "$back_hint" in
        true) hints="$hints · ^b back" ;;
        rename) hints="$hints · ^b rename" ;;
    esac
    hints="$hints · ^c cancel "

    # centre the footer and pin to bottom of screen
    local term_width=${COLUMNS:-$(tput cols)}
    local term_height=${LINES:-$(tput lines)}
    local hints_len=${#hints}
    local side_len=$(((term_width - hints_len) / 2))
    [[ $side_len -lt 1 ]] && side_len=1
    local left_border
    left_border=$(printf '─%.0s' $(seq 1 $side_len))
    local right_border
    right_border=$(printf '─%.0s' $(seq 1 $side_len))

    local footer_line="${DIM}${left_border}${NC}${CYAN}${hints}${NC}${DIM}${right_border}${NC}"

    # save cursor, jump to bottom, print footer, restore cursor
    printf '\033[s'
    printf '\033[%d;1H' "$((term_height - 1))"
    printf '%s' "$footer_line"
    printf '\033[u'
}

# show context from previous steps (dim)
# usage: show_context "label" "value"
show_context() {
    local label="$1"
    local value="$2"
    if [[ -n "$value" ]]; then
        printf "  ${DIM}%s: %s${NC}\n" "$label" "$value"
    fi
}

# prompt for input with default value, respects ctrl+b
# usage: ask "label" "default_value" result_var
# returns 1 if ctrl+b was pressed (go back)
ask() {
    local label="$1"
    local default="$2"
    local -n _result="$3"

    # use \001/\002 to mark non-printing chars so readline calculates width correctly
    local rl_cyan=$'\001'"${CYAN}"$'\002'
    local rl_nc=$'\001'"${NC}"$'\002'
    local prompt
    if [[ -n "$default" ]]; then
        prompt="  ${rl_cyan}${label}${rl_nc}: "
        read -er -i "$default" -p "$prompt" _result || true
    else
        prompt="  ${rl_cyan}${label}${rl_nc}: "
        read -er -p "$prompt" _result || true
    fi

    # detect the back marker injected by the ctrl+b readline binding
    if [[ "$_result" == *"$BACK_MARKER"* ]]; then
        return 1
    fi

    if [[ -z "$_result" && -n "$default" ]]; then
        _result="$default"
    fi
    return 0
}

# prompt for yes/no with default, respects ctrl+b
# usage: ask_yn "label" "default" result_var
# returns 1 if ctrl+b was pressed (go back)
ask_yn() {
    local label="$1"
    local default="$2"
    local -n _yn_result="$3"
    local prompt_hint

    if [[ "$default" == "y" ]]; then
        prompt_hint="Y/n"
    else
        prompt_hint="y/N"
    fi

    # use \001/\002 to mark non-printing chars so readline calculates width correctly
    local rl_cyan=$'\001'"${CYAN}"$'\002'
    local rl_nc=$'\001'"${NC}"$'\002'
    local prompt="  ${rl_cyan}${label}${rl_nc} [${prompt_hint}]: "

    read -er -p "$prompt" _yn_result || true

    # detect the back marker injected by the ctrl+b readline binding
    if [[ "$_yn_result" == *"$BACK_MARKER"* ]]; then
        return 1
    fi

    if [[ -z "$_yn_result" ]]; then
        _yn_result="$default"
    fi
    return 0
}

# ─────────────────────────────────────────
# worktree directory suggestions
# ─────────────────────────────────────────

# list worktree directory suggestions based on project directory
# combines smart suggestions with existing directories and general project dirs
list_worktree_suggestions() {
    local proj_dir="$1"
    # expand $HOME and ~ for filesystem operations
    local expanded="${proj_dir//\$HOME/$HOME}"
    expanded="${expanded/#\~/$HOME}"
    local proj_parent proj_basename
    proj_parent=$(dirname "$expanded")
    proj_basename=$(basename "$expanded")

    # smart suggestions based on project location
    printf '%s\n' "${proj_parent/#$HOME/\~}/${proj_basename}-worktrees"
    printf '%s\n' "${proj_parent/#$HOME/\~}/worktrees"

    # existing worktree-like directories near the project
    if [[ -d "$proj_parent" ]]; then
        for d in "$proj_parent"/*worktree*/; do
            [[ -d "$d" ]] || continue
            d="${d%/}"
            printf '%s\n' "${d/#$HOME/\~}"
        done
    fi

    # general project directories for flexibility
    list_project_dirs
}

# ─────────────────────────────────────────
# state variables
# ─────────────────────────────────────────
description=""
instance_mode=""
project_dir=""
num_windows=""
declare -a win_names=()
declare -a win_cmds=()
declare -a win_splits=()
declare -a win_split_cmds=()
worktree_aware=""
worktrees_dir=""
default_names=("dev" "edit" "shell")

# calculate total steps (recalculated after step 4)
total_steps=4
step=1

# handle edit mode: resolve source and load existing values
if [[ -n "$edit_source" ]]; then
    edit_source=$(basename "$edit_source")
    edit_file=$(resolve_edit_source "$edit_source")
    if [[ -z "$edit_file" ]]; then
        clear
        printf "\n"
        printf "  ${RED}Launcher '%s' not found${NC}\n\n" "$edit_source"
        exit 1
    fi
    load_existing_launcher "$edit_file"
    if [[ -z "$name" ]]; then
        name="$edit_source"
    fi
fi

# if name was provided, start at step 1 (description)
# but validate/sanitise it first
if [[ -n "$name" ]]; then
    name=$(sanitise_launcher_name "$name")
    if [[ -z "$edit_source" && -f "$USER_LAUNCHERS/$name" ]]; then
        clear
        printf "\n"
        printf "  ${RED}Launcher '%s' already exists${NC}\n\n" "$name"
        printf "  ${DIM}%s/%s${NC}\n" "$USER_LAUNCHERS" "$name"

        # pin hint to bottom (prefixed to avoid polluting global namespace)
        _err_tw=${COLUMNS:-$(tput cols)}
        _err_th=${LINES:-$(tput lines)}
        _err_hint=" spc/enter back · q/esc close "
        _err_side=$(((_err_tw - ${#_err_hint}) / 2))
        [[ $_err_side -lt 1 ]] && _err_side=1
        _err_border=$(printf '─%.0s' $(seq 1 $_err_side))
        printf '\033[%d;1H' "$((_err_th - 1))"
        printf "${DIM}%s${NC}${CYAN}%s${NC}${DIM}%s${NC}" "$_err_border" "$_err_hint" "$_err_border"
        printf '\033[6;1H'

        while true; do
            read -rsn1 _err_key
            case "$_err_key" in
                r | ' ' | '') exec "$SCRIPT_DIR/prompt.sh" ;;
                q | $'\x1b') exit 0 ;;
            esac
        done
    fi
fi

# ─────────────────────────────────────────
# main wizard loop
# ─────────────────────────────────────────
while true; do
    case $step in
        1)
            # step 1: description
            draw_header 1 "$total_steps"
            printf "  ${GREEN}What does this launcher do?${NC}\n\n"
            show_context "Name" "$name"
            draw_footer "rename"

            local_desc=""
            if ask "Description" "${description:-$name project session}" local_desc; then
                description="$local_desc"
                step=2
            else
                # ctrl+b on step 1, go back to name prompt
                if [[ -n "$edit_source" ]]; then
                    exec "$SCRIPT_DIR/prompt.sh" --edit "$edit_source"
                fi
                exec "$SCRIPT_DIR/prompt.sh"
            fi
            ;;

        2)
            # step 2: project directory (inline fzf picker)
            load_fzf_theme
            draw_header 2 "$total_steps"
            printf "  ${GREEN}Where is the project?${NC}\n\n"
            show_context "Name" "$name"
            show_context "Desc" "$description"
            printf "\n"

            local_default_dir="${project_dir:-$(default_project_root)/$name}"
            # display ~ rather than the literal $HOME that gets stored on the way forward
            local_default_dir="${local_default_dir/#\$HOME/\~}"

            local_fzf_result=""
            local_fzf_exit=0
            local_fzf_result=$(list_project_dirs | fzf \
                --exact \
                --print-query \
                --query="$local_default_dir" \
                --prompt='  Directory: ' \
                --header='  opt-enter: use typed path' \
                --height=~60% \
                --layout=reverse \
                --no-info \
                --pointer='▸' \
                --bind 'enter:accept' \
                --bind 'alt-enter:become(echo {q})' \
                --bind 'esc:abort' \
                2>/dev/null) || local_fzf_exit=$?

            # exit 130 = esc/abort, exit 2 = error → go back
            # exit 1 = no match → use the typed query
            # alt-enter uses become() so exits 0 with just the query (no line 2)
            if [[ $local_fzf_exit -gt 1 ]]; then
                step=1
                continue
            fi

            # --print-query: line 1 = query, line 2 = selected item
            local_query=$(printf '%s' "$local_fzf_result" | sed -n '1p' | sed 's/^[[:space:]]*//')
            local_selected=$(printf '%s' "$local_fzf_result" | sed -n '2p' | sed 's/^[[:space:]]*//')
            local_dir="${local_selected:-$local_query}"

            local_dir=$(unescape_paste "$local_dir")

            if [[ -z "$local_dir" ]]; then
                local_dir="$local_default_dir"
            fi

            # check if directory exists (expand ~ and $HOME for the check)
            local_expanded=$(expand_path "$local_dir")
            if [[ ! -d "$local_expanded" ]]; then
                printf "\n"
                printf "  ${YELLOW}Directory not found:${NC} %s\n" "$local_dir"
                local_create=""
                if ask_yn "Create it?" "y" local_create; then
                    if [[ "$local_create" =~ ^[Yy] ]]; then
                        mkdir -p "$local_expanded"
                    fi
                else
                    # ctrl+b → stay on step 2
                    continue
                fi
            fi

            project_dir="$local_dir"
            # expand ~ for template but keep $HOME in generated script
            if [[ "$project_dir" == "~" ]]; then
                project_dir="\$HOME"
            else
                project_dir="${project_dir/#\~\//\$HOME/}"
            fi
            step=3
            ;;

        3)
            # step 3: instance mode + worktree awareness
            # sub-steps: instance y/n → worktree y/n → worktree dir (fzf picker)
            # worktree is only offered when instances are enabled, since worktree
            # resolution depends on the instance suffix in the session name
            local_sub=1
            while true; do
                case $local_sub in
                    1)
                        # instance mode question
                        draw_header 3 "$total_steps"
                        printf "  ${GREEN}Instance configuration${NC}\n"
                        printf "  ${DIM}e.g. ticket numbers: %s-1234${NC}\n\n" "$name"
                        show_context "Name" "$name"
                        show_context "Desc" "$description"
                        show_context "Dir" "$project_dir"
                        draw_footer "true"

                        local_instance=""
                        if ask_yn "Prompt for instance name?" "${instance_mode:-n}" local_instance; then
                            if [[ "$local_instance" =~ ^[Yy] ]]; then
                                instance_mode="y"
                                local_sub=2
                            else
                                instance_mode="n"
                                worktree_aware="n"
                                worktrees_dir=""
                                step=4
                                break
                            fi
                        else
                            step=2
                            break
                        fi
                        ;;

                    2)
                        # worktree awareness (only when instances are enabled)
                        draw_header 3 "$total_steps"
                        printf "  ${GREEN}Resolve worktree directories for instances?${NC}\n"
                        printf "  ${DIM}e.g. %s-1252 → %s-1252-*${NC}\n\n" "$name" "$(printf '%s' "$name" | tr '[:lower:]' '[:upper:]')"
                        show_context "Name" "$name"
                        show_context "Desc" "$description"
                        show_context "Dir" "$project_dir"
                        show_context "Instances" "yes"
                        draw_footer "true"

                        local_wt=""
                        if ask_yn "Worktree aware?" "${worktree_aware:-n}" local_wt; then
                            if [[ "$local_wt" =~ ^[Yy] ]]; then
                                worktree_aware="y"
                                local_sub=3
                            else
                                worktree_aware="n"
                                worktrees_dir=""
                                step=4
                                break
                            fi
                        else
                            local_sub=1
                        fi
                        ;;

                    3)
                        # worktree directory picker (fzf with smart suggestions)
                        load_fzf_theme
                        draw_header 3 "$total_steps"
                        printf "  ${GREEN}Where are the worktrees?${NC}\n\n"
                        show_context "Name" "$name"
                        show_context "Desc" "$description"
                        show_context "Dir" "$project_dir"
                        show_context "Instances" "yes (worktree aware)"
                        printf "\n"

                        # derive default from project dir if not already set
                        local_wt_default="${worktrees_dir:-}"
                        local_wt_default="${local_wt_default/#\$HOME/\~}"
                        if [[ -z "$local_wt_default" ]]; then
                            local_proj_display="${project_dir/#\$HOME/\~}"
                            local_proj_parent=$(dirname "$local_proj_display")
                            local_proj_basename=$(basename "$local_proj_display")
                            local_wt_default="${local_proj_parent}/${local_proj_basename}-worktrees"
                        fi

                        local_fzf_result=""
                        local_fzf_exit=0
                        local_fzf_result=$(list_worktree_suggestions "$project_dir" | sort -u | fzf \
                            --exact \
                            --print-query \
                            --query="$local_wt_default" \
                            --prompt='  Worktrees dir: ' \
                            --header='  opt-enter: use typed path' \
                            --height=~60% \
                            --layout=reverse \
                            --no-info \
                            --pointer='▸' \
                            --bind 'enter:accept' \
                            --bind 'alt-enter:become(echo {q})' \
                            --bind 'esc:abort' \
                            2>/dev/null) || local_fzf_exit=$?

                        if [[ $local_fzf_exit -gt 1 ]]; then
                            local_sub=2
                            continue
                        fi

                        local_query=$(printf '%s' "$local_fzf_result" | sed -n '1p' | sed 's/^[[:space:]]*//')
                        local_selected=$(printf '%s' "$local_fzf_result" | sed -n '2p' | sed 's/^[[:space:]]*//')
                        local_wtdir="${local_selected:-$local_query}"

                        local_wtdir=$(unescape_paste "$local_wtdir")

                        if [[ -z "$local_wtdir" ]]; then
                            local_wtdir="$local_wt_default"
                        fi

                        worktrees_dir="$local_wtdir"
                        if [[ "$worktrees_dir" == "~" ]]; then
                            worktrees_dir="\$HOME"
                        else
                            worktrees_dir="${worktrees_dir/#\~\//\$HOME/}"
                        fi
                        step=4
                        break
                        ;;
                esac
            done
            ;;

        4)
            # step 4: number of windows
            draw_header 4 "$total_steps"
            printf "  ${GREEN}How many windows?${NC}\n\n"
            show_context "Name" "$name"
            show_context "Desc" "$description"
            show_context "Dir" "$project_dir"
            if [[ "$instance_mode" == "y" ]]; then
                if [[ "$worktree_aware" == "y" ]]; then
                    show_context "Instances" "yes (worktree: $worktrees_dir)"
                else
                    show_context "Instances" "yes"
                fi
            fi
            draw_footer "true"

            local_num=""
            if ask "Number of windows" "${num_windows:-3}" local_num; then
                # validate it's a number between 1 and 20
                if ! [[ "$local_num" =~ ^[0-9]+$ ]] || [[ "$local_num" -lt 1 ]]; then
                    local_num=3
                elif [[ "$local_num" -gt 20 ]]; then
                    local_num=20
                fi
                # only reset window arrays if count changed
                if [[ "$local_num" != "$num_windows" ]]; then
                    win_names=()
                    win_cmds=()
                    win_splits=()
                    win_split_cmds=()
                fi
                num_windows="$local_num"
                total_steps=$((4 + num_windows))
                step=5
            else
                step=3
            fi
            ;;

        *)
            # steps 5+: window configuration
            local_win_idx=$((step - 4)) # 1-based window index

            if [[ $local_win_idx -gt $num_windows ]]; then
                # past last window, done
                break
            fi

            draw_header "$step" "$total_steps"
            printf "  ${GREEN}Window %d${NC}\n\n" "$local_win_idx"
            show_context "Name" "$name"
            show_context "Desc" "$description"
            show_context "Dir" "$project_dir"
            if [[ "$instance_mode" == "y" ]]; then
                if [[ "$worktree_aware" == "y" ]]; then
                    show_context "Instances" "yes (worktree: $worktrees_dir)"
                else
                    show_context "Instances" "yes"
                fi
            fi

            # show previously configured windows
            for ((p = 1; p < local_win_idx; p++)); do
                local_p_idx=$((p - 1))
                if [[ $local_p_idx -lt ${#win_names[@]} ]]; then
                    local_split_info=""
                    if [[ "${win_splits[$local_p_idx]:-no}" == "yes" ]]; then
                        local_split_info=" (split)"
                    fi
                    show_context "Win $p" "${win_names[$local_p_idx]}${local_split_info}"
                fi
            done
            draw_footer "true"

            local_default="${default_names[$((local_win_idx - 1))]:-window-$local_win_idx}"

            # get existing values for this window if going back
            local_prev_name="${win_names[$((local_win_idx - 1))]:-}"
            local_prev_cmd="${win_cmds[$((local_win_idx - 1))]:-}"
            local_prev_split="${win_splits[$((local_win_idx - 1))]:-no}"
            local_prev_scmd="${win_split_cmds[$((local_win_idx - 1))]:-}"

            local_wname=""
            if ! ask "Name" "${local_prev_name:-$local_default}" local_wname; then
                step=$((step - 1))
                continue
            fi

            local_wcmd=""
            if ! ask "Command" "${local_prev_cmd}" local_wcmd; then
                step=$((step - 1))
                continue
            fi

            local_wsplit=""
            local_wsplit_default="n"
            if [[ "$local_prev_split" == "yes" ]]; then
                local_wsplit_default="y"
            fi
            if ! ask_yn "Split pane?" "$local_wsplit_default" local_wsplit; then
                step=$((step - 1))
                continue
            fi

            local_wscmd=""
            if [[ "$local_wsplit" =~ ^[Yy] ]]; then
                if ! ask "Split command" "${local_prev_scmd}" local_wscmd; then
                    step=$((step - 1))
                    continue
                fi
            fi

            # store window config (replace if going forward again)
            local_arr_idx=$((local_win_idx - 1))
            win_names[local_arr_idx]="$local_wname"
            win_cmds[local_arr_idx]="$local_wcmd"
            if [[ "$local_wsplit" =~ ^[Yy] ]]; then
                win_splits[local_arr_idx]="yes"
            else
                win_splits[local_arr_idx]="no"
            fi
            win_split_cmds[local_arr_idx]="$local_wscmd"

            step=$((step + 1))
            ;;
    esac
done

# ─────────────────────────────────────────
# generate launcher file (edit-aware)
# ─────────────────────────────────────────

mkdir -p "$USER_LAUNCHERS"

target_name="$name"
target_path="$USER_LAUNCHERS/$target_name"

# if editing a user launcher and the name changed, remove the old file
if [[ -n "$edit_source" ]]; then
    if [[ -f "$USER_LAUNCHERS/$edit_source" && "$edit_source" != "$target_name" ]]; then
        rm -f "$USER_LAUNCHERS/$edit_source"
    fi
fi

# session name: strip dots (tmux uses '.' as pane separator in target syntax)
session_name=$(printf '%s' "$name" | tr '.' '-' | sed 's/-*$//')
session_var=$(printf '%s' "$name" | tr '[:lower:]' '[:upper:]' | tr '.-' '_')

{
    instance_tag=""
    if [[ "$instance_mode" == "y" ]]; then
        instance_tag=$'\n'"# @instance: prompt"
    fi

    cat <<PREAMBLE
#!/usr/bin/env bash
set -euo pipefail

# @description: $description${instance_tag}

# Help flag handling
if [[ "\${1:-}" == "--help" ]] || [[ "\${1:-}" == "-h" ]]; then
    cat << 'EOF'
$name - Project tmux session launcher

USAGE:
    $name

DESCRIPTION:
    Creates or attaches to the '$name' tmux session.

OPTIONS:
    -h, --help   Show this help message
EOF
    exit 0
fi

PREAMBLE

    # generate SESSION and PROJECT_DIR (worktree-aware or simple)
    #
    # path defaults are staged in `_<SESSION>_…_DEFAULT` variables rather than
    # embedded inline as `${VAR:-/path}`, because single quotes inside a
    # parameter-expansion default (e.g. `${VAR:-/foo's/bar}`) trip bash's
    # quoter even within `"…"`. a regular `VAR="…"` assignment handles
    # apostrophes natively; the `${VAR:-$_DEFAULT}` then references it safely.
    # the `${PATH/#\~/$HOME}` lines expand a leading `~` in case an env-var
    # override (e.g. `FOO_ROOT="~/x"`) ships a literal tilde
    if [[ "$worktree_aware" == "y" ]]; then
        worktree_prefix=$(printf '%s' "$name" | tr '[:lower:]' '[:upper:]')
        cat <<WTBLOCK
SESSION="\${SESSION_NAME:-$session_name}"
_${session_var}_WORKTREES_DEFAULT="$worktrees_dir"
_${session_var}_ROOT_DEFAULT="$project_dir"
WORKTREES_DIR="\${${session_var}_WORKTREES:-\$_${session_var}_WORKTREES_DEFAULT}"
BASE_DIR="\${${session_var}_ROOT:-\$_${session_var}_ROOT_DEFAULT}"
WORKTREES_DIR="\${WORKTREES_DIR/#\\~/\$HOME}"
BASE_DIR="\${BASE_DIR/#\\~/\$HOME}"

# resolve project directory: check for a matching worktree when session has a suffix
PROJECT_DIR="\$BASE_DIR"
if [[ "\$SESSION" =~ -([0-9]+)\$ ]]; then
    ticket_num="\${BASH_REMATCH[1]}"
    for wt in "\$WORKTREES_DIR"/${worktree_prefix}-"\${ticket_num}"-*; do
        if [[ -d "\$wt" ]]; then
            PROJECT_DIR="\$wt"
            break
        fi
    done
fi
WTBLOCK
    else
        cat <<SIMPLE
SESSION="\${SESSION_NAME:-$session_name}"
_${session_var}_ROOT_DEFAULT="$project_dir"
PROJECT_DIR="\${${session_var}_ROOT:-\$_${session_var}_ROOT_DEFAULT}"
PROJECT_DIR="\${PROJECT_DIR/#\\~/\$HOME}"
SIMPLE
    fi

    cat <<'VALIDATE'

# Validate project directory exists
if [[ ! -d "$PROJECT_DIR" ]]; then
    echo "Error: Project directory not found: $PROJECT_DIR" >&2
    exit 1
fi

# Check if session already exists (= forces exact match; bare names would
# prefix-match e.g. "foo-15" against an existing "foo-1533")
if tmux has-session -t "=$SESSION" 2>/dev/null; then
    if [[ -n "${TMUX:-}" ]]; then
        tmux switch-client -t "=$SESSION"
    else
        tmux attach-session -t "=$SESSION"
    fi
    exit 0
fi

VALIDATE

    # generate window commands
    for ((i = 0; i < ${#win_names[@]}; i++)); do
        wname="${win_names[$i]}"
        wcmd="${win_cmds[$i]}"
        wsplit="${win_splits[$i]}"
        wscmd="${win_split_cmds[$i]}"

        # escape single quotes for safe embedding in generated send-keys commands
        wcmd="${wcmd//\'/\'\\\'\'}"
        wscmd="${wscmd//\'/\'\\\'\'}"

        if [[ $i -eq 0 ]]; then
            printf '# Window 1: %s\n' "$wname"
            printf 'tmux new-session -d -s "$SESSION" -n "%s" -c "$PROJECT_DIR"\n' "$wname"
        else
            printf '\n# Window %d: %s\n' "$((i + 1))" "$wname"
            printf 'tmux new-window -t "$SESSION:" -n "%s" -c "$PROJECT_DIR"\n' "$wname"
        fi

        if [[ "$wsplit" == "yes" ]]; then
            printf 'tmux split-window -t "$SESSION:%s" -h -c "$PROJECT_DIR"\n' "$wname"
            if [[ -n "$wcmd" ]]; then
                printf 'tmux send-keys -t "$SESSION:%s.1" '\''%s'\'' Enter\n' "$wname" "$wcmd"
            fi
            if [[ -n "$wscmd" ]]; then
                printf 'tmux send-keys -t "$SESSION:%s.2" '\''%s'\'' Enter\n' "$wname" "$wscmd"
            fi
        elif [[ -n "$wcmd" ]]; then
            printf 'tmux send-keys -t "$SESSION:%s" '\''%s'\'' Enter\n' "$wname" "$wcmd"
        fi
    done

    cat <<'FOOTER'

# Select first window
tmux select-window -t "$SESSION:1"
tmux select-pane -t "$SESSION:1.1"

# Attach to session
if [[ -n "${TMUX:-}" ]]; then
    tmux switch-client -t "=$SESSION"
else
    tmux attach-session -t "=$SESSION"
fi
FOOTER
} >"$target_path"

chmod +x "$target_path"

# show success
clear
printf "\n\n"
if [[ -n "$edit_source" ]]; then
    printf "  ${GREEN}Launcher updated${NC}\n\n"
else
    printf "  ${GREEN}Launcher created${NC}\n\n"
fi
printf "  ${DIM}%s/%s${NC}\n" "$USER_LAUNCHERS" "$target_name"
printf "  ${DIM}It will appear in the launcher picker (prefix + p)${NC}\n"
sleep 2
