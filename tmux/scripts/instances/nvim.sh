#!/usr/bin/env bash
# list all running nvim instances across all tmux sessions
# shows session, window, pane, and cwd information for each instance

set -euo pipefail

SCRIPT_DIR="${BASH_SOURCE%/*}"
source "$SCRIPT_DIR/../_lib/common.sh"

# check if tmux is available
if ! command -v tmux &>/dev/null; then
    exit 1
fi

# check if any sessions exist
if ! tmux list-sessions &>/dev/null; then
    exit 0
fi

# find nvim sockets and map PID -> socket
declare -A socket_map=()
while IFS= read -r sock; do
    [[ -z "$sock" ]] && continue
    pid=$(basename "$sock" | sed 's/nvim\.\([0-9]*\)\..*/\1/')
    socket_map[$pid]="$sock"
done < <(find "${TMPDIR}nvim.${USER}" -type s -name "nvim.*" 2>/dev/null || true)

# build PID -> PPID map for all nvim socket PIDs in one ps call.
# this avoids repeated ps calls when walking the process tree
declare -A ppid_map=()
if [[ ${#socket_map[@]} -gt 0 ]]; then
    # collect all PIDs we might need to walk (nvim pids + ancestors up to 5 levels)
    all_pids=()
    for pid in "${!socket_map[@]}"; do
        all_pids+=("$pid")
    done
    # get ppid for all processes in one call (faster than per-pid ps)
    while IFS= read -r pline; do
        [[ -z "$pline" ]] && continue
        p_pid="${pline%% *}"
        p_pid="${p_pid// /}"
        p_ppid="${pline##* }"
        p_ppid="${p_ppid// /}"
        [[ "$p_pid" =~ ^[0-9]+$ ]] || continue
        ppid_map[$p_pid]="$p_ppid"
    done < <(ps -e -o pid=,ppid= 2>/dev/null)
fi

# pre-fetch window names: "session:window_index window_name"
declare -A window_names
while IFS= read -r wline; do
    key="${wline%% *}"
    name="${wline#* }"
    window_names["$key"]="$name"
done < <(tmux list-windows -a -F '#{session_name}:#{window_index} #{window_name}')

# store results
nvim_panes=()

# iterate through all panes in all sessions, sorted by last viewed (most recent first)
while IFS= read -r line; do
    # parse: "last_viewed session:window_index.pane_index pane_pid command"
    rest="${line#* }"       # strip last_viewed
    target="${rest%% *}"    # session:window_index.pane_index
    rest2="${rest#* }"      # pane_pid command
    pane_pid="${rest2%% *}" # pane_pid
    command="${rest2#* }"   # command

    # check if the command is nvim
    [[ "$command" == "nvim" ]] || continue

    # extract session and window_idx for lookups
    session="${target%%:*}"
    win_pane="${target#*:}"
    window_idx="${win_pane%%.*}"

    window_name="${window_names["${session}:${window_idx}"]:-}"

    # find the nvim socket for this pane (check nvim PID and children)
    socket=""
    # first check if pane_pid itself is nvim
    if [[ -n "${socket_map[$pane_pid]:-}" ]]; then
        socket="${socket_map[$pane_pid]}"
    else
        # check child processes for nvim using pre-built ppid_map
        for nvim_pid in "${!socket_map[@]}"; do
            check_pid="$nvim_pid"
            for _ in {1..5}; do
                if [[ "$check_pid" == "$pane_pid" ]]; then
                    socket="${socket_map[$nvim_pid]}"
                    break 2
                fi
                check_pid="${ppid_map[$check_pid]:-}"
                [[ -z "$check_pid" || "$check_pid" == "1" ]] && break
            done
        done
    fi

    # build display: target window_name <tab> socket
    display="${target} ${window_name}"

    # append socket path after tab for pick-nvim.sh to extract
    if [[ -n "$socket" ]]; then
        nvim_panes+=("${display}"$'\t'"${socket}")
    else
        nvim_panes+=("${display}"$'\t'"")
    fi
done < <(tmux list-panes -a -F '#{?#{@pane-viewed},#{@pane-viewed},0} #{session_name}:#{window_index}.#{pane_index} #{pane_pid} #{pane_current_command}' | sort -rn)

# add NVIM logo at top, match the Keyword highlight from the active nvim colorscheme
# (same colour the Snacks dashboard header displays)
load_fzf_theme
LOGO_COLOUR=""
_nvim_colors="${XDG_CONFIG_HOME:-$HOME/.config}/nvim/colors"
_scheme="${NVIM_COLORSCHEME:-dracula}"
SCHEME_FILE="${_nvim_colors}/${_scheme}.lua"
[[ -f "$SCHEME_FILE" ]] || SCHEME_FILE="${_nvim_colors}/generated/${_scheme}.lua"
if [[ -f "$SCHEME_FILE" ]]; then
    # try direct hex: hl('Keyword', { fg = '#rrggbb' })
    LOGO_COLOUR=$(grep "^hl('Keyword'" "$SCHEME_FILE" | grep -oE "'#[0-9a-fA-F]{6}'" | tr -d "'" | head -1 || true)
    if [[ -z "$LOGO_COLOUR" ]]; then
        # named colour: hl('Keyword', { fg = colors.name })
        _cname=$(grep "^hl('Keyword'" "$SCHEME_FILE" | grep -oE 'colors\.[a-z_]+' | head -1 | cut -d. -f2 || true)
        [[ -n "$_cname" ]] && LOGO_COLOUR=$(grep "  ${_cname} = '#" "$SCHEME_FILE" | grep -oE "'#[0-9a-fA-F]{6}'" | tr -d "'" | head -1 || true)
    fi
fi
[[ -z "$LOGO_COLOUR" ]] && LOGO_COLOUR="${TMUX_ACCENT_GREEN:-#50fa7b}"
NVIM_GREEN=$(hex_fg "$LOGO_COLOUR")
echo ""
printf "${NVIM_GREEN}            ▗${NC}\n"
printf "${NVIM_GREEN}▛▀▖▞▀▖▞▀▖▌ ▌▄ ▛▚▀▖${NC}\n"
printf "${NVIM_GREEN}▌ ▌▛▀ ▌ ▌▐▐ ▐ ▌▐ ▌${NC}\n"
printf "${NVIM_GREEN}▘ ▘▝▀▘▝▀  ▘ ▀▘▘▝ ▘${NC}\n"
echo ""

# display results (empty list shows just the logo)
if [[ ${#nvim_panes[@]} -eq 0 ]]; then
    exit 0
fi

# output list (display<tab>socket)
for pane_info in "${nvim_panes[@]}"; do
    echo "$pane_info"
done
