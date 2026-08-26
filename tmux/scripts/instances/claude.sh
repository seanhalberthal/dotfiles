#!/usr/bin/env bash
# list all running Claude Code instances across all tmux sessions
# emits a 7-line header (logo + state legend) then tab-delimited rows for fzf:
#   {1}=display(shown)  {2}=jump/preview target session:window.pane
# state comes from the agent-state registry (AGENT_STATE_DIR), written by the
# claude code hooks (scripts/hooks/agent-state.sh); "stuck" is derived here
# from event age plus the pane title losing claude's braille spinner, and a
# stale needs-input flips back to working when the spinner returns

set -euo pipefail

SCRIPT_DIR="${BASH_SOURCE%/*}"
source "$SCRIPT_DIR/../_lib/common.sh"
source "$SCRIPT_DIR/../_lib/alerts.sh"
source "$SCRIPT_DIR/../_lib/process.sh"

# a working state older than this with no spinner in the title reads as stuck
STUCK_SECS="${AGENT_STUCK_SECS:-120}"

# check if tmux is available
if ! command -v tmux &>/dev/null; then
    exit 1
fi

# check if any sessions exist
if ! tmux list-sessions &>/dev/null; then
    exit 0
fi

# build set of PIDs that are ancestors of an active (non-suspended) claude process
# walks up the process tree so wrapper scripts (e.g., ralph -> claude) are detected.
# match_process_pids also catches versioned binaries pgrep -x can't see
declare -A active_claude_ppids
while IFS= read -r cpid; do
    state=$(ps -o state= -p "$cpid" 2>/dev/null) || continue
    [[ "$state" == T* ]] && continue
    # include claude itself: tmux new-window 'claude ...' execs claude as the pane process
    active_claude_ppids[$cpid]=1
    pid="$cpid"
    while true; do
        ppid=$(ps -o ppid= -p "$pid" 2>/dev/null) || break
        ppid="${ppid// /}"
        [[ "$ppid" == "0" || "$ppid" == "1" || -z "$ppid" ]] && break
        active_claude_ppids[$ppid]=1
        pid="$ppid"
    done
done < <(match_process_pids claude)

# pre-fetch window names: "session:window_index window_name"
declare -A window_names
while IFS= read -r wline; do
    key="${wline%% *}"
    name="${wline#* }"
    window_names["$key"]="$name"
done < <(tmux list-windows -a -F '#{session_name}:#{window_index} #{window_name}')

TAB=$(printf '\t')
now=$(date +%s)

# claude code shows a braille char (U+2800-U+28FF) in the pane title while
# working, and U+2733 (\u2733) when idle. test the raw leading utf-8 bytes (E2 with
# a second byte in A0-A3 is exactly the braille block) rather than a codepoint
# range: a C/POSIX locale collapses [\u2800-\u28ff] to a byte range that also matches \u2733,
# which would silently hide every stuck instance. called only for stale working
# and needs-input panes, so the fork is rare
_title_has_spinner() {
    local hex
    hex=$(printf '%s' "$1" | od -An -tx1 -N2 2>/dev/null | tr -d ' \n')
    case "$hex" in e2a0 | e2a1 | e2a2 | e2a3) return 0 ;; *) return 1 ;; esac
}

# store results; track panes for the stale-state sweep below
claude_panes=()
declare -A pane_seen pane_has_claude

# iterate through all panes in all sessions, sorted by last viewed (most recent
# first). pane_title is last so an embedded tab in it can't shift other fields
while IFS="$TAB" read -r _viewed session window_idx pane_idx pane_id pane_pid title; do
    [[ -n "$pane_id" ]] || continue
    pane_seen[$pane_id]=1

    # check if this pane has an active claude child
    [[ -n "${active_claude_ppids[$pane_pid]:-}" ]] || continue
    pane_has_claude[$pane_id]=1

    target="${session}:${window_idx}.${pane_idx}"
    window_name="${window_names["${session}:${window_idx}"]:-}"

    # per-pane label from claude's own pane title, so split panes in one
    # window don't all inherit the active pane's name via automatic-rename.
    # squash tabs (title is untrusted), strip the leading state glyph, and
    # fall back to the window name until claude sets a session title
    label="${title//$TAB/ }"
    label="${label#"${label%%[a-zA-Z0-9]*}"}"
    case "$label" in "" | "Claude Code" | claude) label="$window_name" ;; esac

    # state + age from the registry (agent/state/epoch lead the line and are
    # always non-empty, so a plain tab read is safe)
    state="" age_str=""
    state_file="$AGENT_STATE_DIR/$pane_id"
    if [[ -f "$state_file" ]]; then
        s_agent="" s_state="" s_epoch=""
        IFS="$TAB" read -r s_agent s_state s_epoch _ <"$state_file" || true
        if [[ "$s_agent" == "claude" && -n "$s_state" && "$s_epoch" =~ ^[0-9]+$ ]]; then
            state="$s_state"
            age=$((now - s_epoch))
            ((age < 0)) && age=0
            # stuck: nominally working, no hook event for a while, and the
            # pane title no longer shows the spinner
            if [[ "$state" == "working" ]] && ((age > STUCK_SECS)) && ! _title_has_spinner "$title"; then
                state="stuck"
            fi
            # the reverse: no hook fires when a permission prompt is
            # approved, so needs-input goes stale while the agent runs. a
            # spinner in the title means it's actively working again
            if [[ "$state" == "needs-input" ]] && _title_has_spinner "$title"; then
                state="working"
            fi
            # age reads as "how long it's been waiting on you" for idle/input,
            # or how long it's been wedged for stuck/error. for a live working
            # turn it just tracks the last tool call and jitters, so it's hidden
            [[ "$state" != "working" ]] && age_str=$(_fmt_elapsed "$age")
        fi
    fi

    sdisp=$(get_agent_state_display "$state")
    row="$(_ansi "${sdisp##*|}" "${sdisp%%|*}")  ${session}:${window_idx}.${pane_idx} ${label}"
    [[ -n "$age_str" ]] && row="${row}  ${age_str}"

    claude_panes+=("${row}${TAB}${target}")
done < <(tmux list-panes -a -F "#{?#{@pane-viewed},#{@pane-viewed},0}${TAB}#{session_name}${TAB}#{window_index}${TAB}#{pane_index}${TAB}#{pane_id}${TAB}#{pane_pid}${TAB}#{pane_title}" | sort -rn)

# opportunistic GC: drop state files (and tmp litter) for panes that are gone,
# and claude files for panes whose claude has exited. other agents' files are
# left for their own listers
if [[ -d "$AGENT_STATE_DIR" ]]; then
    for f in "$AGENT_STATE_DIR"/*; do
        [[ -e "$f" ]] || continue
        fname="${f##*/}"
        if [[ -z "${pane_seen[$fname]:-}" ]]; then
            rm -f "$f"
        elif [[ -z "${pane_has_claude[$fname]:-}" ]]; then
            f_agent=""
            IFS="$TAB" read -r f_agent _ <"$f" || true
            [[ "$f_agent" == "claude" ]] && rm -f "$f"
        fi
    done
fi

# add Claude Code ghost at top (Anthropic terracotta: #D77757 = 215;119;87)
echo ""
printf "\033[38;2;215;119;87m ▐▛███▜▌\033[0m\n"
printf "\033[38;2;215;119;87m▝▜█████▛▘\033[0m\n"
printf "\033[38;2;215;119;87m  ▘▘ ▝▝\033[0m\n"
echo ""

# state legend (line 6 of the 7-line header)
l_working=$(get_agent_state_display working)
l_input=$(get_agent_state_display needs-input)
l_idle=$(get_agent_state_display idle)
l_error=$(get_agent_state_display error)
l_stuck=$(get_agent_state_display stuck)
printf '  %s working %s input %s idle %s error %s stuck\n' \
    "$(_ansi "${l_working##*|}" "${l_working%%|*}")" \
    "$(_ansi "${l_input##*|}" "${l_input%%|*}")" \
    "$(_ansi "${l_idle##*|}" "${l_idle%%|*}")" \
    "$(_ansi "${l_error##*|}" "${l_error%%|*}")" \
    "$(_ansi "${l_stuck##*|}" "${l_stuck%%|*}")"
echo ""

# display results (empty list shows just the header)
if [[ ${#claude_panes[@]} -eq 0 ]]; then
    exit 0
fi

# tab-delimited rows below the header
for pane_info in "${claude_panes[@]}"; do
    printf '%s\n' "$pane_info"
done
