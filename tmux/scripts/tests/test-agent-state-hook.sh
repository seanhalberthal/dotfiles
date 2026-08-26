#!/usr/bin/env bash
set -euo pipefail

# unit tests for agent-state.sh (and its claude wrapper)
# functional: feeds hook JSON on stdin with AGENT_STATE_DIR pointed at a temp
# dir and TMUX_PANE faked, then asserts on the written state file. no tmux
# server needed

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK_SCRIPT="$SCRIPT_DIR/../../../scripts/hooks/agent-state.sh"
WRAPPER_SCRIPT="$SCRIPT_DIR/../../../scripts/hooks/wrappers/claude-state.sh"

source "$SCRIPT_DIR/_test-helpers.sh"

STATE_DIR=$(mktemp -d)
PANE="%99"
STATE_FILE="$STATE_DIR/$PANE"
trap 'rm -rf "$STATE_DIR"' EXIT

# run the hook with a payload; a fresh state dir survives between calls so
# no-change events can be asserted against the previous file
# usage: run_hook '<json>' [pane]
run_hook() {
    local payload="$1" pane="${2:-$PANE}"
    printf '%s\n' "$payload" | TMUX_PANE="$pane" AGENT_STATE_DIR="$STATE_DIR" bash "$HOOK_SCRIPT" claude
}

# read a single field from the state file (1-based)
field() {
    cut -f"$1" <"$STATE_FILE"
}

# ===========================================================================
# tests
# ===========================================================================

section "Script Exists and Is Executable"

for f in "$HOOK_SCRIPT" "$WRAPPER_SCRIPT"; do
    if [[ -x "$f" ]]; then
        pass "$(basename "$f") exists and is executable"
    else
        fail "$(basename "$f") missing or not executable"
    fi
done

section "ShellCheck and Syntax"

if command -v shellcheck &>/dev/null; then
    if shellcheck -x -e SC1091 -e SC2059 -e SC2015 -e SC2016 -e SC2034 "$HOOK_SCRIPT" "$WRAPPER_SCRIPT" 2>/dev/null; then
        pass "hook scripts pass shellcheck"
    else
        fail "hook scripts have shellcheck warnings"
    fi
else
    skip "shellcheck not installed"
fi

if bash -n "$HOOK_SCRIPT" && bash -n "$WRAPPER_SCRIPT"; then
    pass "hook scripts have valid bash syntax"
else
    fail "hook scripts have syntax errors"
fi

if ! command -v jq &>/dev/null; then
    skip "jq not installed; skipping functional tests"
    print_summary
    exit 0
fi

section "Event Mapping"

run_hook '{"hook_event_name":"SessionStart","source":"startup","session_id":"s1","cwd":"/tmp/proj"}'
assert_equals "SessionStart maps to idle" "idle" "$(field 2)"
assert_equals "agent field is claude" "claude" "$(field 1)"
assert_equals "session_id is recorded" "s1" "$(field 5)"
assert_equals "cwd is recorded" "/tmp/proj" "$(field 6)"

run_hook '{"hook_event_name":"UserPromptSubmit","session_id":"s1","cwd":"/tmp/proj"}'
assert_equals "UserPromptSubmit maps to working" "working" "$(field 2)"

run_hook '{"hook_event_name":"PreToolUse","tool_name":"Bash","session_id":"s1","cwd":"/tmp/proj"}'
assert_equals "PreToolUse (Bash) maps to working" "working" "$(field 2)"
assert_equals "event records the tool" "PreToolUse:Bash" "$(field 4)"

run_hook '{"hook_event_name":"PreToolUse","tool_name":"AskUserQuestion","session_id":"s1","cwd":"/tmp/proj"}'
assert_equals "PreToolUse (AskUserQuestion) maps to needs-input" "needs-input" "$(field 2)"

run_hook '{"hook_event_name":"PreToolUse","tool_name":"ExitPlanMode","session_id":"s1","cwd":"/tmp/proj"}'
assert_equals "PreToolUse (ExitPlanMode) maps to needs-input" "needs-input" "$(field 2)"

run_hook '{"hook_event_name":"PostToolUse","tool_name":"AskUserQuestion","session_id":"s1","cwd":"/tmp/proj"}'
assert_equals "PostToolUse (question answered) maps to working" "working" "$(field 2)"

# wired for all tools: an approved tool's completion is the first hook event
# after a permission prompt, so it must clear needs-input
run_hook '{"hook_event_name":"PostToolUse","tool_name":"Bash","session_id":"s1","cwd":"/tmp/proj"}'
assert_equals "PostToolUse (any tool) maps to working" "working" "$(field 2)"

run_hook '{"hook_event_name":"PermissionRequest","tool_name":"Bash","session_id":"s1","cwd":"/tmp/proj"}'
assert_equals "PermissionRequest maps to needs-input" "needs-input" "$(field 2)"

run_hook '{"hook_event_name":"Stop","session_id":"s1","cwd":"/tmp/proj"}'
assert_equals "Stop maps to idle" "idle" "$(field 2)"

run_hook '{"hook_event_name":"StopFailure","error_type":"rate_limit","session_id":"s1","cwd":"/tmp/proj"}'
assert_equals "StopFailure maps to error" "error" "$(field 2)"

section "Notification Sub-Types"

run_hook '{"hook_event_name":"Notification","notification_type":"permission_prompt","session_id":"s1","cwd":"/tmp/proj"}'
assert_equals "permission_prompt maps to needs-input" "needs-input" "$(field 2)"
assert_equals "event keeps the notification type" "Notification:permission_prompt" "$(field 4)"

run_hook '{"hook_event_name":"Notification","notification_type":"idle_prompt","session_id":"s1","cwd":"/tmp/proj"}'
assert_equals "idle_prompt maps to idle" "idle" "$(field 2)"

run_hook '{"hook_event_name":"Notification","notification_type":"auth_success","session_id":"s1","cwd":"/tmp/proj"}'
assert_equals "auth_success leaves previous state untouched" "idle" "$(field 2)"

section "No-Change Events"

run_hook '{"hook_event_name":"UserPromptSubmit","session_id":"s1","cwd":"/tmp/proj"}'
run_hook '{"hook_event_name":"SubagentStop","session_id":"s1","cwd":"/tmp/proj"}'
assert_equals "SubagentStop leaves parent state untouched" "working" "$(field 2)"

run_hook '{"hook_event_name":"SomeFutureEvent","session_id":"s1","cwd":"/tmp/proj"}'
assert_equals "unknown events are ignored" "working" "$(field 2)"

section "SessionEnd Removes State"

run_hook '{"hook_event_name":"SessionEnd","reason":"exit","session_id":"s1","cwd":"/tmp/proj"}'
if [[ ! -e "$STATE_FILE" ]]; then
    pass "SessionEnd removes the state file"
else
    fail "SessionEnd should remove the state file"
fi

section "Guards"

printf '%s\n' '{"hook_event_name":"Stop"}' | env -u TMUX_PANE AGENT_STATE_DIR="$STATE_DIR" bash "$HOOK_SCRIPT" claude
if [[ ! -e "$STATE_FILE" ]] && [[ -z "$(ls -A "$STATE_DIR")" ]]; then
    pass "no TMUX_PANE writes nothing and exits 0"
else
    fail "no TMUX_PANE should write nothing"
fi

run_hook '{"hook_event_name":"Stop"}' '../evil'
if [[ -z "$(ls -A "$STATE_DIR")" ]]; then
    pass "malformed TMUX_PANE writes nothing and exits 0"
else
    fail "malformed TMUX_PANE should write nothing"
fi

run_hook 'not json at all'
if [[ -z "$(ls -A "$STATE_DIR")" ]]; then
    pass "malformed JSON writes nothing and exits 0"
else
    fail "malformed JSON should write nothing"
fi

section "Atomic Write Hygiene"

run_hook '{"hook_event_name":"Stop","session_id":"s1","cwd":"/tmp/proj"}'
tmp_litter=("$STATE_DIR"/*.tmp.*)
if [[ ! -e "${tmp_litter[0]}" ]]; then
    pass "no tmp file litter left behind"
else
    fail "tmp files left in state dir"
fi

section "Wrapper Delegation"

printf '%s\n' '{"hook_event_name":"Stop","session_id":"w1","cwd":"/tmp/proj"}' |
    TMUX_PANE="$PANE" AGENT_STATE_DIR="$STATE_DIR" bash "$WRAPPER_SCRIPT"
assert_equals "wrapper writes claude agent rows" "claude" "$(field 1)"
assert_equals "wrapper passes stdin through" "w1" "$(field 5)"

# ===========================================================================
# summary
# ===========================================================================

print_summary
[[ $FAIL -gt 0 ]] && exit 1
exit 0
