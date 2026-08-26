#!/usr/bin/env bash
# agent state hook: maintain a per-pane state file for the instance switchers
# usage: agent-state.sh [agent_name]   (agent hook JSON on stdin)
# writes $AGENT_STATE_DIR/<pane_id>, one line:
#   agent<tab>state<tab>epoch<tab>event<tab>session_id<tab>cwd
# states: working | needs-input | idle | error ("stuck" is derived at render
# time by the reader). events that carry no state change exit without writing

set -euo pipefail

# no pane to key on (agent running outside tmux) or no jq: nothing to do
[[ "${TMUX_PANE:-}" =~ ^%[0-9]+$ ]] || exit 0
command -v jq &>/dev/null || exit 0

AGENT="${1:-claude}"
STATE_DIR="${AGENT_STATE_DIR:-${XDG_CONFIG_HOME:-$HOME/.config}/tmux-alerts/agent-state}"
STATE_FILE="$STATE_DIR/$TMUX_PANE"

# single parse of the hook payload, one field per line (tab-joined output
# would collapse empty fields: tab is IFS whitespace to read). cwd is last so
# an embedded newline in it can't shift the fields that matter.
# malformed json -> no output -> empty event -> exit
mapfile -t _fields < <(
    jq -r '.hook_event_name // "", .notification_type // "", .tool_name // "",
           .session_id // "", .cwd // ""' 2>/dev/null
)
event="${_fields[0]:-}"
ntype="${_fields[1]:-}"
tool="${_fields[2]:-}"
session_id="${_fields[3]:-}"
cwd="${_fields[4]:-}"
[[ -n "$event" ]] || exit 0

case "$event" in
    SessionStart) state="idle" ;;
    UserPromptSubmit) state="working" ;;
    PreToolUse)
        # a question or plan-approval prompt is presented before the tool runs
        case "$tool" in
            AskUserQuestion | ExitPlanMode) state="needs-input" ;;
            *) state="working" ;;
        esac
        ;;
    # wired for all tools: no hook fires when a permission prompt is
    # approved, so the approved tool's completion is the first signal
    # that the agent is back to work
    PostToolUse) state="working" ;;
    PermissionRequest) state="needs-input" ;;
    Notification)
        case "$ntype" in
            permission_prompt | elicitation_dialog | agent_needs_input) state="needs-input" ;;
            idle_prompt) state="idle" ;;
            *) exit 0 ;;
        esac
        ;;
    Stop) state="idle" ;;
    StopFailure) state="error" ;;
    SessionEnd)
        rm -f "$STATE_FILE"
        exit 0
        ;;
    *) exit 0 ;;
esac

if [[ ! -d "$STATE_DIR" ]]; then
    mkdir -p "$STATE_DIR"
    chmod 700 "$STATE_DIR"
fi

# atomic write: the readers scan this dir on every popup refresh
printf '%s\t%s\t%s\t%s\t%s\t%s\n' \
    "$AGENT" "$state" "$(date +%s)" "$event${ntype:+:$ntype}${tool:+:$tool}" \
    "$session_id" "$cwd" >"$STATE_FILE.tmp.$$"
mv -f "$STATE_FILE.tmp.$$" "$STATE_FILE"
