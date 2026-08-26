#!/usr/bin/env bash
# terminal UI utilities for tmux scripts
# source this file after common.sh

# guard against multiple sourcing
[[ -n "${_TMUX_UI_SH_LOADED:-}" ]] && return 0
_TMUX_UI_SH_LOADED=1

# convert hex colour (#rrggbb) to truecolour ANSI foreground escape
# returns empty string if input is empty (caller should use fallback)
_hex_fg() {
    local hex="${1:-}"
    [[ -z "$hex" ]] && return
    printf '\033[38;2;%d;%d;%dm' \
        "$((16#${hex:1:2}))" "$((16#${hex:3:2}))" "$((16#${hex:5:2}))"
}

# display a visual confirmation for last window/pane scenarios
# shows confirmation first, then switches to another session if user confirms
# usage: tmux_confirm_last_item "window" "session_name" "target" "window_name" ["window_id"]
#        tmux_confirm_last_item "pane" "session_name" "target" "" ""
tmux_confirm_last_item() {
    local item_type="$1"       # "window" or "pane"
    local current_session="$2" # session being affected
    local target="$3"          # full target (e.g. "session:window" or "session:window.pane")
    local window_name="$4"     # window name (for clearing alerts, optional)
    local window_id="${5:-}"   # window id (for clearing alerts, optional)

    local other_session
    other_session=$(find_other_session "$current_session")

    # clear alerts before showing confirmation
    if [[ -n "$window_name" && "$item_type" == "window" ]]; then
        clear_window_alerts "$current_session" "$window_name" "$window_id"
    fi

    local message command

    if [[ -n "$other_session" ]]; then
        message="Last ${item_type} in '${current_session}'. Kill and switch to '${other_session}'?"
        command="switch-client -t \"${other_session}\" \\; kill-${item_type} -t \"${target}\""
    else
        message="Kill session '${current_session}' (last ${item_type})?"
        command="kill-${item_type} -t \"${target}\""
    fi

    # use tmux's built-in confirm-before
    tmux confirm-before -p "$message (y/n) " "$command"
    return $?
}

# display a centered message box
# usage: show_centered_message "Title" "Message line 1" "Message line 2" ...
show_centered_message() {
    local title="$1"
    shift
    local lines=("$@")

    # calculate dimensions
    local max_width=0
    for line in "$title" "${lines[@]}"; do
        local len=${#line}
        ((len > max_width)) && max_width=$len
    done

    local box_width=$((max_width + 6))
    local box_height=$((${#lines[@]} + 4))

    # use LINES/COLUMNS if set (tmux popup), otherwise fall back to tput
    local term_height term_width
    term_height=${LINES:-$(tput lines)}
    term_width=${COLUMNS:-$(tput cols)}

    local v_pad=$(((term_height - box_height) / 2))
    [[ $v_pad -lt 0 ]] && v_pad=0

    local h_pad=$(((term_width - box_width) / 2))
    [[ $h_pad -lt 0 ]] && h_pad=0

    local pad
    pad=$(printf '%*s' "$h_pad" '')

    clear

    # vertical padding
    for ((i = 0; i < v_pad; i++)); do
        printf '\n'
    done

    # theme-aware colours (fall back to 256-colour defaults)
    local title_col sep_col
    title_col=$(_hex_fg "${TMUX_STATUS_ACTIVE_BG:-}") || true
    sep_col=$(_hex_fg "${TMUX_FG_SECONDARY:-}") || true
    [[ -z "$title_col" ]] && title_col=$'\033[38;5;141m'
    [[ -z "$sep_col" ]] && sep_col=$'\033[38;5;60m'

    # title
    printf '%s%s%s\033[0m\n' "$pad" "$title_col" "$title"
    printf '%s%s%s\033[0m\n' "$pad" "$sep_col" "$(printf '%.0s─' $(seq 1 ${#title}))"
    printf '\n'

    # message lines
    for line in "${lines[@]}"; do
        printf '%s%s\n' "$pad" "$line"
    done

    printf '\n'
}

# display a confirmation dialog (y/n)
# usage: confirm_action "Are you sure?" && do_something
confirm_action() {
    local prompt="${1:-Are you sure?}"
    local response

    read -r -p "$prompt [y/N] " response
    [[ "$response" =~ ^[Yy]$ ]]
}

# display a centered confirmation dialog
# usage: show_centered_confirm "Title" "Message" && do_something
show_centered_confirm() {
    local title="$1"
    local message="$2"

    show_centered_message "$title" "$message" "" "Press y to confirm, any other key to cancel"

    local response
    read -rsn1 response
    [[ "$response" =~ ^[Yy]$ ]]
}

# visual confirmation dialog using fzf with Yes/No options
# usage: show_visual_confirm "Title" "Message"
# returns: 0 if confirmed, 1 if cancelled
show_visual_confirm() {
    local title="$1"
    local message="$2"

    # load current theme colours for fzf
    load_fzf_theme

    local choice
    # use printf to interpret \n in the message
    choice=$(printf "yes\nno" | fzf \
        --height=100% --layout=reverse --disabled --cycle \
        --prompt=': ' \
        --border=rounded \
        --border-label=" ${title} " \
        --border-label-pos=top \
        --header="$(printf '%b' "$message")" \
        --no-info \
        --pointer='▌' \
        --bind 'j:down,k:up,space:accept,enter:accept' \
        --bind 'y:pos(1)+accept,n:pos(2)+accept' \
        --bind 'esc:abort,q:abort' \
        --bind 'change:clear-query') || return 1

    [[ "$choice" == "yes" ]]
}

# wait for any key press
# usage: wait_for_key "prompt" [true], pass true as second arg to centre the prompt
wait_for_key() {
    local prompt="${1:-Press any key to continue...}"
    local centred="${2:-false}"

    if [[ "$centred" == "true" ]]; then
        local term_width
        term_width=${COLUMNS:-$(tput cols)}
        local h_pad=$(((term_width - ${#prompt}) / 2))
        [[ $h_pad -lt 0 ]] && h_pad=0
        prompt=$(printf '%*s%s' "$h_pad" '' "$prompt")
    fi

    read -rsn1 -p "$prompt"
}

# show a brief notification that auto-dismisses
# usage: show_notification "Success!" 2
show_notification() {
    local message="$1"
    local duration="${2:-1}"

    # use LINES/COLUMNS if set (tmux popup), otherwise fall back to tput
    local term_height term_width
    term_height=${LINES:-$(tput lines)}
    term_width=${COLUMNS:-$(tput cols)}

    local h_pad=$(((term_width - ${#message}) / 2))
    [[ $h_pad -lt 0 ]] && h_pad=0

    local v_pad=$((term_height / 2))

    clear
    for ((i = 0; i < v_pad; i++)); do
        printf '\n'
    done

    local notify_col
    notify_col=$(_hex_fg "${TMUX_ACCENT_GREEN:-}") || true
    [[ -z "$notify_col" ]] && notify_col=$'\033[32m'

    printf '%*s%s%s\033[0m\n' "$h_pad" '' "$notify_col" "$message"

    sleep "$duration"
}
