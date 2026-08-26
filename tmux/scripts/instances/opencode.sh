#!/usr/bin/env bash
# list all running OpenCode instances across all tmux sessions
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

# build set of pane PIDs that have an active (non-suspended) opencode child process
# done once upfront to avoid forking pgrep+ps per pane in the loop
declare -A active_opencode_ppids
while IFS= read -r cpid; do
    state=$(ps -o state= -p "$cpid" 2>/dev/null) || continue
    [[ "$state" == T* ]] && continue
    ppid=$(ps -o ppid= -p "$cpid" 2>/dev/null) || continue
    active_opencode_ppids[${ppid// /}]=1
done < <(pgrep -f opencode 2>/dev/null)

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
opencode_panes=()

# iterate through all panes in all sessions, sorted by last viewed (most recent first)
while IFS= read -r line; do
    # parse: "last_viewed session:window_index.pane_index pane_pid"
    rest="${line#* }"      # strip last_viewed
    target="${rest%% *}"   # session:window_index.pane_index
    pane_pid="${rest##* }" # pane_pid

    # check if this pane has an active opencode child
    [[ -n "${active_opencode_ppids[$pane_pid]:-}" ]] || continue

    # extract session and window_idx for lookups
    session="${target%%:*}"
    win_pane="${target#*:}"
    window_idx="${win_pane%%.*}"

    window_name="${window_names["${session}:${window_idx}"]:-}"

    # check if this window has an alert for opencode (names stored percent-encoded)
    if [[ -n "$alerts_content" ]] && printf '%s' "$alerts_content" | grep -q "^${session}:$(alerts_encode_window "$window_name"):opencode$" 2>/dev/null; then
        display=$(get_agent_display "opencode")
        icon="${display%%|*}"
        opencode_panes+=("${target} ${window_name} ${icon}")
    else
        opencode_panes+=("${target} ${window_name}")
    fi
done < <(tmux list-panes -a -F '#{?#{@pane-viewed},#{@pane-viewed},0} #{session_name}:#{window_index}.#{pane_index} #{pane_pid}' | sort -rn)

# add OpenCode logo at top (theme-aware, two-tone blue from cyan accent)
load_fzf_theme
ACCENT_CYAN="${TMUX_ACCENT_CYAN:-#8be9fd}"
DARK=$(hex_fg "$(hex_dim "$ACCENT_CYAN" 65)")
LIGHT=$(hex_fg "$ACCENT_CYAN")
echo ""
printf "${DARK}█▀▀█ █▀▀█ █▀▀█ █▀▀▄${NC} ${LIGHT}█▀▀ █▀▀█ █▀▀▄ █▀▀█${NC}\n"
printf "${DARK}█  █ █  █ █▀▀▀ █  █${NC} ${LIGHT}█   █  █ █  █ █▀▀▀${NC}\n"
printf "${DARK}▀▀▀▀ █▀▀▀ ▀▀▀▀ ▀  ▀${NC} ${LIGHT}▀▀▀ ▀▀▀▀ ▀▀▀▀ ▀▀▀▀${NC}\n"
echo ""
# display results (empty list shows just the logo)
if [[ ${#opencode_panes[@]} -eq 0 ]]; then
    exit 0
fi

# simple list below logo
for pane_info in "${opencode_panes[@]}"; do
    echo "$pane_info"
done
