#!/usr/bin/env bash
# process management utilities for graceful termination
# ensures running processes are properly shut down before killing panes/windows/sessions
#
# pattern: SIGTERM, wait (2s), SIGKILL (matches instances/kill.sh)

# list pids whose process name matches exactly, from two sources because
# neither alone is complete. pgrep excludes itself and all of its ancestors
# (see -a in man pgrep), so a script running inside the pane it inspects never
# sees that pane's own process through pgrep. the ps pass has no exclusion.
# both match the executable basename, not argv[0]
# usage: match_process_pids <name>
match_process_pids() {
    local name="$1"
    {
        pgrep -x "$name" 2>/dev/null || true
        ps -axo pid=,comm= 2>/dev/null | awk -v n="$name" '
            {
                pid = $1
                sub(/^[[:space:]]*[0-9]+[[:space:]]+/, "")
                sub(/.*\//, "")
                if ($0 == n) print pid
            }'
    } | sort -un
}

# first direct child of a pid matching name, by pgrep then executable basename
# usage: match_child_pid <parent_pid> <name> [pgrep_flag]
match_child_pid() {
    local parent="$1" name="$2" flag="${3:--x}"
    local pid cmd
    pid=$(pgrep -P "$parent" "$flag" "$name" 2>/dev/null | head -1)
    if [[ -n "$pid" ]]; then
        echo "$pid"
        return 0
    fi
    for pid in $(pgrep -P "$parent" 2>/dev/null); do
        cmd=$(ps -o comm= -p "$pid" 2>/dev/null) || continue
        cmd="${cmd##*/}"
        if [[ "$cmd" == "$name" ]]; then
            echo "$pid"
            return 0
        fi
    done
    return 1
}

# get all descendant PIDs of a given PID (recursive, depth-first)
# outputs deepest descendants first for clean teardown order
get_descendant_pids() {
    local parent_pid="$1"
    local children
    children=$(pgrep -P "$parent_pid" 2>/dev/null) || return 0
    local pid
    for pid in $children; do
        get_descendant_pids "$pid"
        echo "$pid"
    done
}

# send SIGTERM to a list of PIDs, wait for graceful exit, then SIGKILL survivors
# args: grace_seconds pid1 [pid2 ...]
graceful_kill_pids() {
    local grace_seconds="$1"
    shift
    local pids=("$@")
    [[ ${#pids[@]} -eq 0 ]] && return 0

    # send SIGTERM to all
    local pid
    for pid in "${pids[@]}"; do
        kill -TERM "$pid" 2>/dev/null || true
    done

    # wait for graceful exit (polling at 100ms intervals)
    local i=0
    local max_wait=$((grace_seconds * 10))
    while [ "$i" -lt "$max_wait" ]; do
        local any_alive=false
        for pid in "${pids[@]}"; do
            if kill -0 "$pid" 2>/dev/null; then
                any_alive=true
                break
            fi
        done
        $any_alive || return 0
        sleep 0.1
        i=$((i + 1))
    done

    # SIGKILL survivors
    for pid in "${pids[@]}"; do
        if kill -0 "$pid" 2>/dev/null; then
            kill -KILL "$pid" 2>/dev/null || true
        fi
    done
}

# collect all descendant PIDs for a single tmux pane
# args: pane_target (e.g. "session:window.pane")
collect_pane_descendant_pids() {
    local pane_target="$1"
    local pane_pid
    pane_pid=$(tmux display-message -t "$pane_target" -p '#{pane_pid}' 2>/dev/null) || return 0
    [[ -z "$pane_pid" || "$pane_pid" == "0" ]] && return 0
    get_descendant_pids "$pane_pid"
}

# gracefully terminate all processes in a single pane
# args: pane_target [grace_seconds=2]
terminate_pane_processes() {
    local pane_target="$1"
    local grace_seconds="${2:-2}"

    local pids=()
    while IFS= read -r pid; do
        [[ -n "$pid" ]] && pids+=("$pid")
    done < <(collect_pane_descendant_pids "$pane_target")

    [[ ${#pids[@]} -eq 0 ]] && return 0
    graceful_kill_pids "$grace_seconds" "${pids[@]}"
}

# gracefully terminate all processes across all panes in a window
# sends SIGTERM to everything at once, waits once: O(1) delay regardless of pane count
# args: window_target (e.g. "session:window") [grace_seconds=2]
terminate_window_processes() {
    local window_target="$1"
    local grace_seconds="${2:-2}"

    local pids=()
    local pane_index
    while IFS= read -r pane_index; do
        [[ -z "$pane_index" ]] && continue
        while IFS= read -r pid; do
            [[ -n "$pid" ]] && pids+=("$pid")
        done < <(collect_pane_descendant_pids "${window_target}.${pane_index}")
    done < <(tmux list-panes -t "$window_target" -F '#{pane_index}' 2>/dev/null)

    [[ ${#pids[@]} -eq 0 ]] && return 0
    graceful_kill_pids "$grace_seconds" "${pids[@]}"
}

# gracefully terminate all processes across all panes in a session
# sends SIGTERM to everything at once, waits once: O(1) delay regardless of pane count
# args: session_name [grace_seconds=2]
terminate_session_processes() {
    local session_name="$1"
    local grace_seconds="${2:-2}"

    local pids=()
    local win_idx pane_idx
    while IFS='|' read -r win_idx pane_idx; do
        [[ -z "$win_idx" || -z "$pane_idx" ]] && continue
        while IFS= read -r pid; do
            [[ -n "$pid" ]] && pids+=("$pid")
        done < <(collect_pane_descendant_pids "${session_name}:${win_idx}.${pane_idx}")
    done < <(tmux list-panes -t "$session_name" -s -F '#{window_index}|#{pane_index}' 2>/dev/null)

    [[ ${#pids[@]} -eq 0 ]] && return 0
    graceful_kill_pids "$grace_seconds" "${pids[@]}"
}
