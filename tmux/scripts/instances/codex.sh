#!/usr/bin/env bash
# list all running codex instances across all tmux sessions
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

# build set of PIDs that are ancestors of an active (non-suspended) codex process
# walks up the process tree so wrapper scripts are detected
declare -A active_codex_ppids
while IFS= read -r cpid; do
    state=$(ps -o state= -p "$cpid" 2>/dev/null) || continue
    [[ "$state" == T* ]] && continue
    pid="$cpid"
    while true; do
        ppid=$(ps -o ppid= -p "$pid" 2>/dev/null) || break
        ppid="${ppid// /}"
        [[ "$ppid" == "0" || "$ppid" == "1" || -z "$ppid" ]] && break
        active_codex_ppids[$ppid]=1
        pid="$ppid"
    done
done < <(pgrep -x codex 2>/dev/null)

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
codex_panes=()

# iterate through all panes in all sessions, sorted by last viewed (most recent first)
while IFS= read -r line; do
    # parse: "last_viewed session:window_index.pane_index pane_pid"
    rest="${line#* }"      # strip last_viewed
    target="${rest%% *}"   # session:window_index.pane_index
    pane_pid="${rest##* }" # pane_pid

    # check if this pane has an active codex child
    [[ -n "${active_codex_ppids[$pane_pid]:-}" ]] || continue

    # extract session and window_idx for lookups
    session="${target%%:*}"
    win_pane="${target#*:}"
    window_idx="${win_pane%%.*}"

    window_name="${window_names["${session}:${window_idx}"]:-}"

    # check if this window has an alert for codex (names stored percent-encoded)
    if [[ -n "$alerts_content" ]] && printf '%s' "$alerts_content" | grep -q "^${session}:$(alerts_encode_window "$window_name"):codex$" 2>/dev/null; then
        display=$(get_agent_display "codex")
        icon="${display%%|*}"
        codex_panes+=("${target} ${window_name} ${icon}")
    else
        codex_panes+=("${target} ${window_name}")
    fi
done < <(tmux list-panes -a -F '#{?#{@pane-viewed},#{@pane-viewed},0} #{session_name}:#{window_index}.#{pane_index} #{pane_pid}' | sort -rn)

# add codex logo at top
echo ""
printf "${GREEN}█▀▀ █▀▀█ █▀▀▄ █▀▀ █ █${NC}\n"
printf "${GREEN}█   █  █ █  █ █▀▀ ▄▀▄${NC}\n"
printf "${GREEN}▀▀▀ ▀▀▀▀ ▀▀▀  ▀▀▀ ▀ ▀${NC}\n"
echo ""

# display results (empty list shows just the logo)
if [[ ${#codex_panes[@]} -eq 0 ]]; then
    exit 0
fi

# simple list below logo
for pane_info in "${codex_panes[@]}"; do
    echo "$pane_info"
done
