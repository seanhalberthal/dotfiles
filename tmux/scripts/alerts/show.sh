#!/usr/bin/env bash
# display agent alerts for tmux status bar (Claude, OpenCode, etc.)
# shows one alert per session (aggregates all windows in that session)
# also handles command exit alerts (session:window:exit:<window_id>:<code>:<label>)
#
# compatible with bash 3.2 (macOS stock); no associative arrays

SCRIPT_DIR="${BASH_SOURCE%/*}"

# resolve the path for the pre-source bail-out without binding ALERTS_FILE: the
# library declares that name readonly when it loads, so assigning it here first
# would trip a readonly error if the source order were ever reversed
_alerts_file="${XDG_CONFIG_HOME:-$HOME/.config}/tmux-alerts/alerts"

# bail before spawning tmux or sourcing libs; this runs every status-interval
# and the common case is no alerts at all
if [[ ! -f "$_alerts_file" ]] || [[ ! -s "$_alerts_file" ]]; then
    exit 0
fi

CURRENT_SESSION=$(tmux display-message -p '#S' 2>/dev/null)

# source the alerts library for agent configuration
[[ -f "$SCRIPT_DIR/../_lib/alerts.sh" ]] || exit 0
source "$SCRIPT_DIR/../_lib/alerts.sh"

# parallel arrays for bash 3.2 compatibility (no associative arrays)
# sessions[i]     unique session name
# sess_agents[i]  comma-separated agent names
# sess_exit[i]    "icon|colour|label" for exit alert (last wins per session)
sessions=()
sess_agents=()
sess_exit=()

# find index of session, or echo -1
_find_idx() {
    local target="$1" i
    for ((i = 0; i < ${#sessions[@]}; i++)); do
        [[ "${sessions[$i]}" == "$target" ]] && echo "$i" && return
    done
    echo "-1"
}

while IFS= read -r line; do
    [[ -z "$line" ]] && continue

    # split on ':'; exit alerts have 6 fields, agent alerts have 3
    IFS=':' read -r session _window field3 _wid field5 field6 <<<"$line"

    # skip current session and malformed entries
    [[ "$session" == "$CURRENT_SESSION" ]] && continue
    [[ -z "$session" || -z "$field3" ]] && continue

    idx=$(_find_idx "$session")
    if [[ "$idx" == "-1" ]]; then
        idx=${#sessions[@]}
        sessions+=("$session")
        sess_agents+=("")
        sess_exit+=("")
    fi

    if [[ "$field3" == "exit" ]]; then
        local_code="$field5"
        local_label="$field6"
        # escape '#' to prevent tmux format injection
        local_label="${local_label//\#/##}"
        display=$(get_exit_code_display "$local_code")
        sess_exit[idx]="${display}|${local_label}"
    else
        agent="$field3"
        if [[ -z "${sess_agents[idx]}" ]]; then
            sess_agents[idx]="$agent"
        else
            # append agent if not already present
            case ",${sess_agents[idx]}," in
                *,"$agent",*) ;;
                *) sess_agents[idx]="${sess_agents[idx]},${agent}" ;;
            esac
        fi
    fi
done <"$ALERTS_FILE"

session_count=${#sessions[@]}
[[ $session_count -eq 0 ]] && exit 0

output=""

for ((i = 0; i < session_count && i < 3; i++)); do
    session="${sessions[$i]}"

    # agent icons first; also shows the session name
    if [[ -n "${sess_agents[$i]}" ]]; then
        icons=""
        IFS=',' read -ra agent_list <<<"${sess_agents[$i]}"
        for agent in "${agent_list[@]}"; do
            display=$(get_agent_display "$agent")
            icon="${display%%|*}"
            colour="${display##*|}"
            icons="${icons}#[fg=${colour},bold]${icon}"
        done
        output="${output}${icons} ${session}#[default] "
    fi

    # exit alert: icon and label only, coloured; session name shown separately
    if [[ -n "${sess_exit[$i]}" ]]; then
        exit_data="${sess_exit[$i]}"
        exit_icon="${exit_data%%|*}"
        rest="${exit_data#*|}"
        exit_colour="${rest%%|*}"
        exit_label="${rest##*|}"
        if [[ -z "${sess_agents[$i]}" ]]; then
            output="${output}#[fg=${exit_colour},bold]${session} ${exit_icon} ${exit_label}#[default] "
        else
            output="${output}#[fg=${exit_colour},bold]${exit_icon} ${exit_label}#[default] "
        fi
    fi
done

# show overflow count if more than 3 sessions
if [[ $session_count -gt 3 ]]; then
    echo "${output}+ $((session_count - 3)) "
else
    echo "$output"
fi
