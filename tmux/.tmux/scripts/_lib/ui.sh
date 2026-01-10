#!/usr/bin/env bash
# Terminal UI utilities for tmux scripts
# Source this file after common.sh

# Display a centered message box
# Usage: show_centered_message "Title" "Message line 1" "Message line 2" ...
show_centered_message() {
    local title="$1"
    shift
    local lines=("$@")

    # Calculate dimensions
    local max_width=0
    for line in "$title" "${lines[@]}"; do
        local len=${#line}
        ((len > max_width)) && max_width=$len
    done

    local box_width=$((max_width + 6))
    local box_height=$((${#lines[@]} + 4))

    local term_height term_width
    term_height=$(tput lines)
    term_width=$(tput cols)

    local v_pad=$(( (term_height - box_height) / 2 ))
    [[ $v_pad -lt 0 ]] && v_pad=0

    local h_pad=$(( (term_width - box_width) / 2 ))
    [[ $h_pad -lt 0 ]] && h_pad=0

    local pad
    pad=$(printf '%*s' "$h_pad" '')

    clear

    # Vertical padding
    for ((i=0; i<v_pad; i++)); do
        printf '\n'
    done

    # Title
    printf '%s\033[38;5;141m%s\033[0m\n' "$pad" "$title"
    printf '%s\033[38;5;60m%s\033[0m\n' "$pad" "$(printf '%.0s─' $(seq 1 ${#title}))"
    printf '\n'

    # Message lines
    for line in "${lines[@]}"; do
        printf '%s%s\n' "$pad" "$line"
    done

    printf '\n'
}

# Display a confirmation dialog (y/n)
# Usage: confirm_action "Are you sure?" && do_something
confirm_action() {
    local prompt="${1:-Are you sure?}"
    local response

    read -r -p "$prompt [y/N] " response
    [[ "$response" =~ ^[Yy]$ ]]
}

# Display a centered confirmation dialog
# Usage: show_centered_confirm "Title" "Message" && do_something
show_centered_confirm() {
    local title="$1"
    local message="$2"

    show_centered_message "$title" "$message" "" "Press y to confirm, any other key to cancel"

    local response
    read -rsn1 response
    [[ "$response" =~ ^[Yy]$ ]]
}

# Wait for any key press
wait_for_key() {
    local prompt="${1:-Press any key to continue...}"
    read -rsn1 -p "$prompt"
}

# Show a brief notification that auto-dismisses
# Usage: show_notification "Success!" 2
show_notification() {
    local message="$1"
    local duration="${2:-1}"

    local term_height term_width
    term_height=$(tput lines)
    term_width=$(tput cols)

    local h_pad=$(( (term_width - ${#message}) / 2 ))
    [[ $h_pad -lt 0 ]] && h_pad=0

    local v_pad=$(( term_height / 2 ))

    clear
    for ((i=0; i<v_pad; i++)); do
        printf '\n'
    done

    printf '%*s\033[32m%s\033[0m\n' "$h_pad" '' "$message"

    sleep "$duration"
}
