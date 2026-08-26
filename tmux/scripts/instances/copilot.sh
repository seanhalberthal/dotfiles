#!/usr/bin/env bash
# list all running GitHub Copilot CLI instances across all tmux sessions
# shows session, window, and pane information for each instance

set -euo pipefail

SCRIPT_DIR="${BASH_SOURCE%/*}"
source "$SCRIPT_DIR/../_lib/common.sh"
source "$SCRIPT_DIR/../_lib/alerts.sh"

# check if tmux is available
if ! command -v tmux &>/dev/null; then
    exit 1
fi

# check if any sessions exist
if ! tmux list-sessions &>/dev/null; then
    exit 0
fi

# build set of PIDs that are ancestors of an active (non-suspended) copilot process
# walks up the process tree so wrapper scripts are detected
declare -A active_copilot_ppids
while IFS= read -r cpid; do
    state=$(ps -o state= -p "$cpid" 2>/dev/null) || continue
    [[ "$state" == T* ]] && continue
    pid="$cpid"
    while true; do
        ppid=$(ps -o ppid= -p "$pid" 2>/dev/null) || break
        ppid="${ppid// /}"
        [[ "$ppid" == "0" || "$ppid" == "1" || -z "$ppid" ]] && break
        active_copilot_ppids[$ppid]=1
        pid="$ppid"
    done
done < <(pgrep -x copilot 2>/dev/null)

# pre-fetch window names: "session:window_index window_name"
declare -A window_names
while IFS= read -r wline; do
    key="${wline%% *}"
    name="${wline#* }"
    window_names["$key"]="$name"
done < <(tmux list-windows -a -F '#{session_name}:#{window_index} #{window_name}')

# pre-load alerts file content (if it exists)
alerts_content=""
if [[ -f "$ALERTS_FILE" ]]; then
    alerts_content=$(<"$ALERTS_FILE")
fi

# store results
copilot_panes=()

# iterate through all panes in all sessions, sorted by last viewed (most recent first)
while IFS= read -r line; do
    # parse: "last_viewed session:window_index.pane_index pane_pid"
    rest="${line#* }"      # strip last_viewed
    target="${rest%% *}"   # session:window_index.pane_index
    pane_pid="${rest##* }" # pane_pid

    # check if this pane has an active copilot child
    [[ -n "${active_copilot_ppids[$pane_pid]:-}" ]] || continue

    # extract session and window_idx for lookups
    session="${target%%:*}"
    win_pane="${target#*:}"
    window_idx="${win_pane%%.*}"

    window_name="${window_names["${session}:${window_idx}"]:-}"

    # check if this window has an alert for copilot.
    # window names are stored percent-encoded; encode first, then escape '.'
    # (valid in tmux names but a regex wildcard)
    _session_pat="${session//./\\.}"
    _window_pat="$(alerts_encode_window "$window_name")"
    _window_pat="${_window_pat//./\\.}"
    if [[ -n "$alerts_content" ]] && printf '%s' "$alerts_content" | grep -q "^${_session_pat}:${_window_pat}:copilot$" 2>/dev/null; then
        display=$(get_agent_display "copilot")
        icon="${display%%|*}"
        colour="${display##*|}"
        ANSI_COLOUR="\033[38;2;$(printf '%d;%d;%d' "0x${colour:1:2}" "0x${colour:3:2}" "0x${colour:5:2}")m"
        ANSI_RESET="\033[0m"
        copilot_panes+=("${target} ${window_name} $(printf "${ANSI_COLOUR}${icon}${ANSI_RESET}")")
    else
        copilot_panes+=("${target} ${window_name}")
    fi
done < <(tmux list-panes -a -F '#{?#{@pane-viewed},#{@pane-viewed},0} #{session_name}:#{window_index}.#{pane_index} #{pane_pid}' | sort -rn)

# GitHub Copilot logo: periwinkle eyes, purple/green mouth bar
COPILOT_PERIWINKLE="\033[38;5;147m"
COPILOT_PURPLE="\033[38;5;176m"
COPILOT_GREEN="\033[38;5;107m"
echo ""
printf "   ${COPILOT_PERIWINKLE}╭─╮╭─╮${NC}\n"
printf "   ${COPILOT_PERIWINKLE}╰─╯╰─╯${NC}\n"
printf "   ${COPILOT_PURPLE}█${NC} ${COPILOT_GREEN}▘▝${NC} ${COPILOT_PURPLE}█${NC}\n"
printf "    ${COPILOT_PURPLE}▔▔▔▔${NC}\n"
echo ""

# display results (empty list shows just the logo)
if [[ ${#copilot_panes[@]} -eq 0 ]]; then
    exit 0
fi

# simple list below logo
for pane_info in "${copilot_panes[@]}"; do
    echo "$pane_info"
done
