#!/usr/bin/env bash
# alert picker: lists active alerts and navigates to the selected one
# if only one alert exists, jumps directly without showing a picker

SCRIPT_DIR="${BASH_SOURCE%/*}"
source "$SCRIPT_DIR/../_lib/alerts.sh"

# --list mode: output entries only (used by fzf reload-sync)
# detect this early so the hot reload path can skip the picker-only
# initialisation (common.sh, ui.sh, load_fzf_theme); those together
# add ~100ms of bash sourcing that visibly stalls the UI on every `x`
LIST_MODE=0
[[ "${1:-}" == "--list" ]] && LIST_MODE=1

if [[ $LIST_MODE -eq 0 ]]; then
    source "$SCRIPT_DIR/../_lib/common.sh"
    source "$SCRIPT_DIR/../_lib/ui.sh"
    load_fzf_theme
fi

CURRENT_SESSION=$(tmux display-message -p '#S' 2>/dev/null)
CURRENT_WINDOW=$(tmux display-message -p '#W' 2>/dev/null)

if [[ ! -f "$ALERTS_FILE" ]] || [[ ! -s "$ALERTS_FILE" ]]; then
    [[ $LIST_MODE -eq 1 ]] && exit 0
    show_centered_message "Alerts" "No active alerts"
    read -rsn1
    exit 0
fi

# load entries from alerts file
_load_entries() {
    local entries=()
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue

        IFS=':' read -r session window field3 field4 field5 field6 <<<"$line"
        [[ -z "$session" || -z "$window" || -z "$field3" ]] && continue

        # window names are stored percent-encoded; decode for display, the
        # current-window check, and the tmux navigation target
        window=$(alerts_decode_window "$window")

        # skip alerts for the current window (already visible)
        [[ "$session" == "$CURRENT_SESSION" && "$window" == "$CURRENT_WINDOW" ]] && continue

        local target="${session}:${window}"
        local icon colour display label

        if [[ "$field3" == "exit" ]]; then
            # exit line is session:window:exit:window_id:code:label
            label="$field6"
            display=$(get_exit_code_display "$field5")
            icon="${display%%|*}"
            colour="${display##*|}"
        else
            label="$field3"
            display=$(get_agent_display "$field3")
            icon="${display%%|*}"
            colour="${display##*|}"
        fi

        entries+=("$(printf '\033[38;2;%d;%d;%dm%s  %s  %s\033[0m' \
            "0x${colour:1:2}" "0x${colour:3:2}" "0x${colour:5:2}" \
            "$icon" "$target" "$label")")
    done <"$ALERTS_FILE"

    printf '%s\n' "${entries[@]}"
}

# extract session:window target from a picker line (strip ANSI, grab field 2)
_extract_target() {
    printf '%s' "$1" | sed 's/\x1b\[[0-9;]*m//g' | awk '{print $2}'
}

# resolve a session + exact window name to an unambiguous window-id (@N).
# window names can contain dots ("2.1.186") or colons, which collide with
# tmux's session:window.pane target syntax; matching by id sidesteps parsing
_resolve_window_id() {
    local session="$1" name="$2" tab
    printf -v tab '\t'
    tmux list-windows -t "$session" -F "#{window_id}${tab}#{window_name}" 2>/dev/null |
        awk -F'\t' -v n="$name" '$2 == n { print $1; exit }'
}

# navigate the client to an alert target given as "session:window-name".
# resolves to a window-id first so dotted/colon-bearing names don't misparse,
# falling back to the raw target if the lookup fails (e.g. window just closed)
_navigate_to_target() {
    local target="$1"
    [[ -n "$target" ]] || return 0
    local session="${target%%:*}" name="${target#*:}" current wid dst
    current=$(tmux display-message -p '#S' 2>/dev/null)
    wid=$(_resolve_window_id "$session" "$name")
    dst="${wid:-$target}"
    if [[ "$session" != "$current" ]]; then
        tmux switch-client -t "$dst" 2>/dev/null || tmux select-window -t "$dst" 2>/dev/null || true
    else
        tmux select-window -t "$dst" 2>/dev/null || true
    fi
}

entry_list=$(_load_entries)
count=$(printf '%s\n' "$entry_list" | grep -c .)

# --list mode: just output entries for fzf reload (empty if none)
if [[ $LIST_MODE -eq 1 ]]; then
    printf '%s\n' "$entry_list"
    exit 0
fi

# check if all alerts are on current window (filtered out)
if [[ $count -eq 0 ]] && [[ -f "$ALERTS_FILE" ]] && [[ -s "$ALERTS_FILE" ]]; then
    show_centered_message "Alerts" "Alert is on current window"
    read -rsn1
    exit 0
fi

# no alerts: show message and wait
if [[ $count -eq 0 ]]; then
    show_centered_message "Alerts" "No active alerts"
    read -rsn1
    exit 0
fi

# single alert: jump directly instead of paying for an fzf startup
if [[ $count -eq 1 ]]; then
    _navigate_to_target "$(_extract_target "$entry_list")"
    exit 0
fi

# show fzf picker (handles single or multiple alerts)
selected=$(printf '%s\n' "$entry_list" | fzf \
    --ansi --reverse --exact --cycle \
    --no-info --no-header \
    --prompt ': ' \
    --border=rounded \
    --color="label:${TMUX_FG_PRIMARY:-#ffffff}" \
    --border-label=' j/k · spc/⏎ sel · x clear · / srch · q/esc ' \
    --border-label-pos=bottom \
    --bind 'j:down,k:up,q:abort,space:accept' \
    --bind 'enter:accept' \
    --bind 'change:transform:[[ $FZF_PROMPT == ": " ]] && echo "clear-query"' \
    --bind '/:enable-search+change-prompt(> )+unbind(j,k,q,space,x)' \
    --bind 'esc:transform:[[ $FZF_PROMPT == "> " ]] && echo "disable-search+clear-query+change-prompt(: )+rebind(j,k,q,space,x)" || echo "abort"' \
    --bind 'ctrl-k:up,ctrl-l:clear-query' \
    --bind "x:execute-silent(
        target=\$(echo {} | sed 's/\x1b\[[0-9;]*m//g' | awk '{print \$2}')
        session=\${target%%:*}
        window=\${target#*:}
        $SCRIPT_DIR/clear.sh \"\$session\" \"\$window\"
    )+reload-sync($SCRIPT_DIR/pick.sh --list)")

[[ -z "$selected" ]] && exit 0

_navigate_to_target "$(_extract_target "$selected")"
