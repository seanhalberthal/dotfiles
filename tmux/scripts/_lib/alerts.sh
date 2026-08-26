#!/usr/bin/env bash
# agent alert utilities for tmux scripts
# source this file after common.sh

# guard against multiple sourcing
[[ -n "${_TMUX_ALERTS_SH_LOADED:-}" ]] && return 0
_TMUX_ALERTS_SH_LOADED=1

# alerts file location (only set if not already defined, allowing tests to override)
if [[ -z "${ALERTS_FILE:-}" ]]; then
    readonly ALERTS_FILE="${XDG_CONFIG_HOME:-$HOME/.config}/tmux-alerts/alerts"
fi

# running-process registry: one file per pane (named by pane number) holding an
# in-flight tracked command. written by the zsh preexec hook, removed by precmd.
# kept in sync with _CMD_RUNNING_DIR in scripts/hooks/cmd-alert-hook.zsh
if [[ -z "${RUNNING_DIR:-}" ]]; then
    readonly RUNNING_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/tmux-alerts/running"
fi

# finished-process history: appended on every tracked completion (regardless of
# whether you switched away, unlike the alerts file which only records
# switched-away results for the status bar). feeds the proclist "done" rows.
# kept in sync with _CMD_FINISHED_FILE in scripts/hooks/cmd-alert-hook.zsh
# fields: finish_epoch<tab>exit_code<tab>session<tab>window_id<tab>window<tab>label<tab>cmd
# (cmd is the full command as typed, for proclist rerun; absent on pre-rerun rows)
if [[ -z "${FINISHED_FILE:-}" ]]; then
    readonly FINISHED_FILE="${XDG_CONFIG_HOME:-$HOME/.config}/tmux-alerts/finished"
fi

# kill-suppress markers: one file per pane, touched by proclist-action.sh
# right before it sends the interrupting Ctrl-C. the shell's precmd hook
# checks for this marker on completion and, if present, skips both the
# finished-history row and the status-right alert, since the kill was
# intentional rather than a run-to-completion result. kept in sync with
# _CMD_SUPPRESS_DIR in scripts/hooks/cmd-alert-hook.zsh
if [[ -z "${SUPPRESS_DIR:-}" ]]; then
    readonly SUPPRESS_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/tmux-alerts/suppress"
fi

# agent-state registry: one file per pane (named by pane id, e.g. %12) holding
# the last hook-reported state for the agent running in it. written by
# scripts/hooks/agent-state.sh, removed on SessionEnd and by stale-file GC.
# fields: agent<tab>state<tab>epoch<tab>event<tab>session_id<tab>cwd
# (cwd last so an embedded tab can't shift earlier fields)
if [[ -z "${AGENT_STATE_DIR:-}" ]]; then
    readonly AGENT_STATE_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/tmux-alerts/agent-state"
fi

# alert file format: session:window:agent
# future enhancement: add timestamp field for age-based sorting and auto-expiry
# proposed format: session:window:agent:timestamp

# percent-encode a window name for safe storage in the colon-delimited alerts
# file. tmux allows colons in window names (e.g. via automatic-rename from a
# process title), and a literal colon would be mistaken for the field
# separator and corrupt parsing. encode '%' first so the transform is
# reversible, then ':'. sessions use a restricted charset and never need
# encoding; labels are always the trailing field so their colons are harmless
# usage: encoded=$(alerts_encode_window "$window_name")
alerts_encode_window() {
    local s="$1"
    s="${s//%/%25}"
    s="${s//:/%3A}"
    printf '%s' "$s"
}

# inverse of alerts_encode_window. decode ':' before '%' to mirror the encode
# order so a literal "%3A" in the original name survives the round-trip
# usage: name=$(alerts_decode_window "$encoded")
alerts_decode_window() {
    local s="$1"
    s="${s//%3A/:}"
    s="${s//%25/%}"
    printf '%s' "$s"
}

# ansi-colour a string: _ansi "#rrggbb" "text"
_ansi() {
    local c="$1" text="$2"
    printf '\033[38;2;%d;%d;%dm%s\033[0m' \
        "0x${c:1:2}" "0x${c:3:2}" "0x${c:5:2}" "$text"
}

# humanise elapsed seconds: 45s, 12m, 1h03m
_fmt_elapsed() {
    local s="$1"
    if ((s < 60)); then
        printf '%ds' "$s"
    elif ((s < 3600)); then
        printf '%dm' "$((s / 60))"
    else
        printf '%dh%02dm' "$((s / 3600))" "$(((s % 3600) / 60))"
    fi
}

# get agent icon (compatible with bash 3.2, no associative arrays)
# usage: get_agent_icon "agent_name"
# returns: icon symbol
get_agent_icon() {
    local agent="$1"
    case "$agent" in
        claude) echo "⚡" ;;
        codex) echo "⌘" ;;
        opencode) echo "" ;;
        copilot) echo "" ;;
        *) echo "󱜙" ;;
    esac
}

# get agent colour (compatible with bash 3.2, no associative arrays)
# usage: get_agent_colour "agent_name"
# returns: hex colour code
get_agent_colour() {
    local agent="$1"
    case "$agent" in
        claude) echo "#f1fa8c" ;;   # yellow
        codex) echo "#50fa7b" ;;    # dracula green (matches codex logo)
        opencode) echo "#bd93f9" ;; # dracula purple
        copilot) echo "#58a6ff" ;;  # GitHub blue
        *) echo "#6272a4" ;;        # dracula blue
    esac
}

# get agent display icon and colour (inlined to avoid subshell forks)
# usage: get_agent_display "agent_name"
# returns: "icon|colour"
get_agent_display() {
    case "$1" in
        claude) echo "⚡|#f1fa8c" ;;
        codex) echo "⌘|#50fa7b" ;;
        opencode) echo "|#bd93f9" ;;
        copilot) echo "|#58a6ff" ;;
        *) echo "󱜙|#6272a4" ;;
    esac
}

# get agent state display icon and colour (inlined to avoid subshell forks)
# states come from the agent-state registry; "stuck" is derived at render time
# usage: get_agent_state_display "state"
# returns: "icon|colour"
get_agent_state_display() {
    case "$1" in
        working) echo "●|#d8a657" ;;     # amber: in progress
        needs-input) echo "◐|#f1fa8c" ;; # yellow: waiting on permission/question
        idle) echo "○|#8a8f98" ;;        # muted grey: finished, awaiting prompt
        error) echo "✗|#c07878" ;;       # muted red: turn died on an API error
        stuck) echo "⚠|#d77757" ;;       # terracotta: working but no recent activity
        *) echo "·|#6272a4" ;;           # unknown: no state recorded
    esac
}

# a shell reports a signal death as exit code 128+N (SIGINT 130, SIGTERM 143,
# SIGKILL 137, SIGHUP 129). those are interruptions, not run-to-completion
# failures, so they get a neutral state rather than the red ✗
_exit_code_is_signal() {
    [[ "$1" =~ ^[0-9]+$ ]] && (($1 > 128))
}

# exit code icon (separate from agent icons)
# usage: get_exit_code_icon "exit_code"
get_exit_code_icon() {
    local code="$1"
    _exit_code_is_signal "$code" && {
        echo "⊘"
        return
    }
    case "$code" in
        0) echo "✓" ;;
        *) echo "✗" ;;
    esac
}

# exit code colour
# usage: get_exit_code_colour "exit_code"
get_exit_code_colour() {
    local code="$1"
    _exit_code_is_signal "$code" && {
        echo "#8a8f98"
        return
    } # muted grey
    case "$code" in
        0) echo "#7aab88" ;; # muted green
        *) echo "#c07878" ;; # muted red
    esac
}

# running-process display (combined icon|colour, avoids subshell forks)
# distinct from the ✓/✗ exit icons: an in-flight command has no exit code yet
# usage: get_running_display
get_running_display() {
    echo "●|#d8a657" # amber: in progress
}

# exit code display (combined icon|colour, avoids subshell forks)
# usage: get_exit_code_display "exit_code"
get_exit_code_display() {
    local code="$1"
    _exit_code_is_signal "$code" && {
        echo "⊘|#8a8f98"
        return
    } # interrupted
    case "$code" in
        0) echo "✓|#7aab88" ;;
        *) echo "✗|#c07878" ;;
    esac
}

# build alert icon string from tmux window options output
# usage: icons=$(get_window_alert_icons "$opts")
# returns: ANSI-coloured icon string (empty if no alerts)
get_window_alert_icons() {
    local opts="$1"
    local icons=""

    # exit alert
    if printf '%s\n' "$opts" | grep -q '^@exit_alert '; then
        local exit_code exit_label display icon colour
        exit_code=$(printf '%s\n' "$opts" | grep '^@exit_alert_code ' | cut -d' ' -f2)
        exit_label=$(printf '%s\n' "$opts" | grep '^@exit_alert_label ' | cut -d' ' -f2-)
        exit_label="${exit_label#\"}"
        exit_label="${exit_label%\"}"
        # escape '#' to prevent tmux format injection
        exit_label="${exit_label//\#/##}"
        display=$(get_exit_code_display "$exit_code")
        icon="${display%%|*}"
        colour="${display##*|}"
        icons="${icons}\033[38;2;$(printf '%d;%d;%d' "0x${colour:1:2}" "0x${colour:3:2}" "0x${colour:5:2}")m${icon} ${exit_label}\033[0m "
    fi

    # agent alerts
    local agent
    for agent in claude codex opencode copilot; do
        if printf '%s\n' "$opts" | grep -q "^@${agent}_alert "; then
            display=$(get_agent_display "$agent")
            icon="${display%%|*}"
            colour="${display##*|}"
            # apply colour only for non-emoji icons (emojis are self-coloured)
            case "$agent" in
                copilot)
                    icons="${icons}\033[38;2;$(printf '%d;%d;%d' "0x${colour:1:2}" "0x${colour:3:2}" "0x${colour:5:2}")m${icon}\033[0m "
                    ;;
                *)
                    icons="${icons}${icon} "
                    ;;
            esac
        fi
    done

    printf '%s' "$icons"
}

# build alert icons from pre-read alerts file content
# avoids per-window tmux calls by reading the flat file once
# usage: icons=$(build_alert_icons "$alerts_content" "^session_name:" [dedupe])
#   $1 - full alerts file content (pre-read)
#   $2 - grep pattern to filter entries (e.g. "^mysession:" or "^mysession:mywindow:")
#   $3 - optional: pass "dedupe" to deduplicate agent icons across entries
# returns: ANSI-coloured icon string (empty if no alerts match)
build_alert_icons() {
    local alerts_content="$1"
    local pattern="$2"
    local dedupe="${3:-}"

    [[ -z "$alerts_content" ]] && return

    local icons="" seen_agents="" display icon colour line prefix

    case "$pattern" in
        ^*:*)
            prefix="${pattern#^}"
            prefix="${prefix%:}"
            ;;
        *) prefix="" ;;
    esac

    while IFS= read -r line; do
        [[ -n "$line" ]] || continue
        [[ -n "$prefix" && "$line" != "$prefix:"* ]] && continue

        IFS=: read -r _sess _win field3 rest <<<"$line"
        if [[ "$field3" == "exit" ]]; then
            # exit alert: rest is "window_id:code:label" (id is the match key)
            local _cl="${rest#*:}"
            local code="${_cl%%:*}"
            local label="${_cl#*:}"
            # escape '#' to prevent tmux format injection
            label="${label//\#/##}"
            display=$(get_exit_code_display "$code")
            icon="${display%%|*}"
            colour="${display##*|}"
            icons="${icons}\033[38;2;$(printf '%d;%d;%d' "0x${colour:1:2}" "0x${colour:3:2}" "0x${colour:5:2}")m${icon} ${label}\033[0m "
        else
            # agent alert: field3 is agent name
            local agent="$field3"
            if [[ "$dedupe" == "dedupe" ]]; then
                case "$seen_agents" in *"|${agent}|"*) continue ;; esac
                seen_agents="${seen_agents}|${agent}|"
            fi
            display=$(get_agent_display "$agent")
            icon="${display%%|*}"
            colour="${display##*|}"
            case "$agent" in
                copilot)
                    icons="${icons}\033[38;2;$(printf '%d;%d;%d' "0x${colour:1:2}" "0x${colour:3:2}" "0x${colour:5:2}")m${icon}\033[0m "
                    ;;
                *)
                    icons="${icons}${icon} "
                    ;;
            esac
        fi
    done <<<"$alerts_content"

    printf '%s' "$icons"
}

# set an exit code alert for the current window
# usage: set_exit_alert "exit_code" "label" [ring_bell]
# sets @exit_alert* window options and adds a 6-field entry to the alerts file
# (session:window:exit:window_id:code:label); the id is the dismiss/GC key
set_exit_alert() {
    local code="$1"
    local label="$2"
    local ring_bell="${3:-true}"

    # ensure alerts directory exists
    local alerts_dir
    alerts_dir="$(dirname "$ALERTS_FILE")"
    if [[ ! -d "$alerts_dir" ]]; then
        mkdir -p "$alerts_dir"
        chmod 700 "$alerts_dir"
    fi

    # get colour for this exit code
    local colour
    colour="$(get_exit_code_colour "$code")"

    # determine the window target, prefer TMUX_PANE (a pane ID like %12) since
    # it's set to the origin pane by cmd-alert.sh and works even when we've
    # switched windows. tmux accepts pane IDs directly as -wt targets
    local target=""
    if [[ -n "${TMUX_PANE:-}" ]]; then
        target="$TMUX_PANE"
    fi

    # set the @exit_alert and @exit_alert_colour window options on the origin window
    if [[ -n "$target" ]]; then
        tmux set-option -wt "$target" "@exit_alert" 1 2>/dev/null
        tmux set-option -wt "$target" "@exit_alert_colour" "$colour" 2>/dev/null
        tmux set-option -wt "$target" "@exit_alert_code" "$code" 2>/dev/null
        tmux set-option -wt "$target" "@exit_alert_label" "$label" 2>/dev/null
    fi

    # resolve session, window id and window name for the alerts file. the id is
    # the authoritative match key (stable for the server's life, never reused);
    # the name is volatile under automatic-rename and kept only for legacy
    # prefix maintenance. one round-trip, window name last so an embedded tab
    # can't shift the earlier fields
    local sess="" win="" wid="" _meta=""
    if [[ -n "${TMUX_PANE:-}" ]]; then
        _meta=$(tmux display-message -t "$TMUX_PANE" -p $'#S\t#{window_id}\t#W' 2>/dev/null || true)
    fi
    if [[ -z "$_meta" && -n "${TMUX:-}" ]]; then
        _meta=$(tmux display-message -p $'#S\t#{window_id}\t#W' 2>/dev/null || true)
    fi
    [[ -n "$_meta" ]] && IFS=$'\t' read -r sess wid win <<<"$_meta"

    # add window to alerts file (6-field format:
    # session:window:exit:window_id:code:label). window_id is the dismiss/GC key
    # session: project convention (alnum, dot, underscore, hyphen)
    # window: any non-control chars (allows spaces and colons); colons are
    # percent-encoded so they don't collide with the field separator
    if [[ -n "$wid" ]] && [[ "$sess" =~ ^[a-zA-Z0-9._-]+$ ]] && [[ "$win" =~ ^[^[:cntrl:]]+$ ]]; then
        local enc_win
        enc_win=$(alerts_encode_window "$win")
        local entry="${sess}:${enc_win}:exit:${wid}:${code}:${label}"
        grep -qxF "$entry" "$ALERTS_FILE" 2>/dev/null || echo "$entry" >>"$ALERTS_FILE"
    fi

    # ring the bell at the attached client terminal(s) rather than the origin
    # pane. a pane bell trips monitor-bell and leaves a window_bell_flag that
    # lingers as a status highlight until the window is viewed (and which the
    # proclist dismiss can't clear); the @exit_alert option already marks the
    # window, so this is just the audible cue, delivered wherever you're attached
    if [[ "$ring_bell" == "true" ]]; then
        local _ctty
        while IFS= read -r _ctty; do
            [[ -n "$_ctty" && -w "$_ctty" ]] && printf '\a' >"$_ctty" 2>/dev/null
        done < <(tmux list-clients -F '#{client_tty}' 2>/dev/null)
    fi
}

# set an alert for the current window
# usage: set_window_alert "agent_name" [ring_bell]
# sets tmux window option and adds to alerts file
set_window_alert() {
    local agent="${1:-claude}"
    local ring_bell="${2:-true}"

    # validate agent name against whitelist
    case "$agent" in
        claude | codex | opencode | copilot) ;;
        *) return 1 ;;
    esac

    # ensure alerts directory exists
    local alerts_dir
    alerts_dir="$(dirname "$ALERTS_FILE")"
    if [[ ! -d "$alerts_dir" ]]; then
        mkdir -p "$alerts_dir"
        chmod 700 "$alerts_dir"
    fi

    # get current tmux session and window names separately, so a colon in the
    # window name can't be confused with the session:window join
    local sess="" win=""
    if [[ -n "${TMUX_PANE:-}" ]]; then
        sess=$(tmux display-message -t "$TMUX_PANE" -p '#S' 2>/dev/null)
        win=$(tmux display-message -t "$TMUX_PANE" -p '#W' 2>/dev/null)
    fi
    if [[ -z "$sess" && -n "${TMUX:-}" ]]; then
        sess=$(tmux display-message -p '#S' 2>/dev/null)
        win=$(tmux display-message -p '#W' 2>/dev/null)
    fi

    # set the @agent_alert window option. prefer the origin pane id, it's
    # unambiguous even when the window name contains a colon or spaces
    if [[ -n "${TMUX_PANE:-}" ]]; then
        tmux set-option -wt "$TMUX_PANE" "@${agent}_alert" 1 2>/dev/null
    elif [[ -n "$sess" ]]; then
        tmux set-option -wt "${sess}:${win}" "@${agent}_alert" 1 2>/dev/null
    fi

    # add window to alerts file with agent type if not already present
    # session: project convention (alnum, dot, underscore, hyphen)
    # window: any non-control chars (allows spaces and colons); colons are
    # percent-encoded so they don't collide with the field separator
    if [[ "$sess" =~ ^[a-zA-Z0-9._-]+$ ]] && [[ "$win" =~ ^[^[:cntrl:]]+$ ]]; then
        local enc_win
        enc_win=$(alerts_encode_window "$win")
        local entry="${sess}:${enc_win}:${agent}"
        grep -qxF "$entry" "$ALERTS_FILE" 2>/dev/null || echo "$entry" >>"$ALERTS_FILE"
    fi

    # ring the terminal bell (only if requested and /dev/tty is available)
    if [[ "$ring_bell" == "true" ]]; then
        {
            if [[ -w /dev/tty ]]; then
                printf '\a' >/dev/tty
            fi
        } 2>/dev/null || true
    fi
}

# file locking: uses mkdir as an atomic lock primitive (POSIX guarantees mkdir
# is atomic even on NFS). lock acquisition retries 10 times with 100ms backoff
# (1 second total timeout). this prevents concurrent alert updates from
# corrupting the alerts file when multiple tmux scripts fire simultaneously
#
# stale lock recovery: if the lock holder PID is no longer alive, the lock is
# removed and acquisition retried
#
# grep exit codes: 0 = lines matched (filtered), 1 = no matches (file cleared),
# both are valid. exit code 2+ indicates an actual error

# acquire the alerts file lock
# usage: _acquire_alerts_lock
# returns: 0 on success, 1 on failure
_acquire_alerts_lock() {
    local lock_dir="${ALERTS_FILE}.lock"
    local pid_file="${lock_dir}/pid"

    for _ in {1..10}; do
        if mkdir "$lock_dir" 2>/dev/null; then
            echo $$ >"$pid_file" 2>/dev/null
            return 0
        fi

        # check for stale lock, if holder PID is no longer alive, remove it
        if [[ -f "$pid_file" ]]; then
            local holder_pid
            holder_pid=$(cat "$pid_file" 2>/dev/null) || true
            if [[ -n "$holder_pid" ]] && ! kill -0 "$holder_pid" 2>/dev/null; then
                rmdir "$lock_dir" 2>/dev/null || rm -rf "$lock_dir" 2>/dev/null || true
                continue
            fi
        fi

        sleep 0.1
    done

    return 1
}

# release the alerts file lock
# usage: _release_alerts_lock
_release_alerts_lock() {
    local lock_dir="${ALERTS_FILE}.lock"
    rm -f "${lock_dir}/pid" 2>/dev/null
    rmdir "$lock_dir" 2>/dev/null || true
}

# drop finished-history rows for a window so "done" rows clear once viewed,
# mirroring how clear_window_alerts dismisses agent/exit alerts on select.
# keyed on window_id (field 4); tmux never reuses ids within a server lifetime,
# so a rename can't strand the entry. no-op without an id (the only reliable key)
# usage: clear_window_finished "window_id"
clear_window_finished() {
    local window_id="$1"
    [[ -n "$window_id" && -f "$FINISHED_FILE" ]] || return 0

    # fast path: skip the rewrite when this window has no finished rows. a stray
    # field-4-shaped match in a label only costs a no-op rewrite, never a miss
    grep -qF "$window_id" "$FINISHED_FILE" 2>/dev/null || return 0

    local tmpf
    tmpf=$(mktemp "${FINISHED_FILE}.XXXXXX") || return 0
    if awk -F'\t' -v w="$window_id" '$4 != w' "$FINISHED_FILE" >"$tmpf" 2>/dev/null; then
        mv "$tmpf" "$FINISHED_FILE" 2>/dev/null || rm -f "$tmpf"
    else
        rm -f "$tmpf"
    fi
}

# drop finished-history rows for an entire session, mirroring clear_window_finished
# but keyed on the session field (field 3) so destroying a session scrubs the
# done rows for every window at once, including windows that closed earlier and
# whose rows still linger under the file's own TTL. session names are unique
# among live sessions; a row written before a rename keeps the old name and ages
# out via the picker instead, matching how the alerts file handles renames
# usage: clear_session_finished "session"
clear_session_finished() {
    local session="$1"
    [[ -n "$session" && -f "$FINISHED_FILE" ]] || return 0

    # fast path: skip the rewrite when this session has no finished rows. a stray
    # field-3-shaped match in a label only costs a no-op rewrite, never a miss
    grep -qF "$session" "$FINISHED_FILE" 2>/dev/null || return 0

    local tmpf
    tmpf=$(mktemp "${FINISHED_FILE}.XXXXXX") || return 0
    if awk -F'\t' -v s="$session" '$3 != s' "$FINISHED_FILE" >"$tmpf" 2>/dev/null; then
        mv "$tmpf" "$FINISHED_FILE" 2>/dev/null || rm -f "$tmpf"
    else
        rm -f "$tmpf"
    fi
}

# drop a window's exit alert from the status bar: the @exit_alert* options that
# drive the icon plus its exit line in the alerts file. agent alerts on the same
# window are left intact. lets a dismissed proclist "done" row also clear the
# status-right indicator. keyed on window_id (alerts file field 4), which is
# stable under automatic-rename; the stored window name is not, so name-matching
# would miss the line whenever the window auto-renamed after completion
# usage: clear_window_exit_alert "window_id"
clear_window_exit_alert() {
    local window_id="$1"
    [[ -n "$window_id" ]] || return 0

    # unset the window options that render the status-right exit icon
    local opt
    for opt in @exit_alert @exit_alert_code @exit_alert_label @exit_alert_colour; do
        tmux set-option -wt "$window_id" -u "$opt" 2>/dev/null || true
    done

    # remove the matching exit line from the alerts file (used by show.sh).
    # fields are colon-clean (session restricted, name percent-encoded, id/code
    # colon-free), so -F: splits exit lines into exactly session:window:exit:id:…
    [[ -f "$ALERTS_FILE" ]] || return 0
    _acquire_alerts_lock || return 0
    local tmp_file
    tmp_file=$(mktemp "${ALERTS_FILE}.tmp.XXXXXX")
    if awk -F: -v w="$window_id" '!($3 == "exit" && $4 == w)' "$ALERTS_FILE" >"$tmp_file" 2>/dev/null; then
        mv "$tmp_file" "$ALERTS_FILE" 2>/dev/null || rm -f "$tmp_file" 2>/dev/null
    else
        rm -f "$tmp_file" 2>/dev/null
    fi
    _release_alerts_lock
}

# clear all alerts for a specific window
# usage: clear_window_alerts "session" "window" ["window_id"]
clear_window_alerts() {
    local session="$1"
    local window="$2"
    local window_id="${3:-}"

    # finished-process rows clear on the same select that dismisses alerts
    clear_window_finished "$window_id"

    # remove from alerts file (any agent) with file locking. agent lines match
    # on session:window (names are stored percent-encoded, so encode the lookup);
    # exit lines additionally match on window_id (field 4) because their stored
    # name drifts under automatic-rename and an exact-name match would miss them
    if [[ -f "$ALERTS_FILE" ]] && _acquire_alerts_lock; then
        local tmp_file enc_window
        tmp_file=$(mktemp "${ALERTS_FILE}.tmp.XXXXXX")
        enc_window=$(alerts_encode_window "$window")
        if awk -F: -v s="$session" -v w="$enc_window" -v wid="$window_id" '
            ($1 == s && $2 == w) { next }
            (wid != "" && $3 == "exit" && $4 == wid) { next }
            { print }
        ' "$ALERTS_FILE" >"$tmp_file" 2>/dev/null; then
            mv "$tmp_file" "$ALERTS_FILE" 2>/dev/null || rm -f "$tmp_file" 2>/dev/null
        else
            rm -f "$tmp_file" 2>/dev/null
        fi

        _release_alerts_lock
    fi

    # unset all @*_alert window options (agent-agnostic wildcard clearing)
    local target
    if [[ -n "$window_id" ]]; then
        target="$window_id"
    else
        target="${session}:${window}"
    fi

    local alert_options
    alert_options=$(tmux show-options -wt "$target" 2>/dev/null | grep '@.*_alert' | cut -d' ' -f1 || true)

    if [[ -n "$alert_options" ]]; then
        while IFS= read -r option; do
            tmux set-option -wt "$target" -u "$option" 2>/dev/null || true
        done <<<"$alert_options"
    fi
}

# clean up stale alerts (for windows/sessions that no longer exist)
# usage: cleanup_stale_alerts
cleanup_stale_alerts() {
    [[ ! -f "$ALERTS_FILE" ]] && return 0

    _acquire_alerts_lock || return 1

    local tmp_file
    tmp_file=$(mktemp "${ALERTS_FILE}.tmp.XXXXXX")
    local cleaned=0

    # read each alert and verify its target window still exists
    # lines may be 3-field (session:window:agent) or 6-field
    # (session:window:exit:window_id:code:label), so read the leading fields and
    # validate per type: agent alerts by window name, exit alerts by window_id
    while IFS= read -r line; do
        IFS=':' read -r session window field3 field4 _rest <<<"$line"

        # validate format, need at least session, window, and one more field
        if [[ -z "$session" || -z "$window" || -z "$field3" ]]; then
            cleaned=1
            continue
        fi

        # check if session exists
        if ! tmux has-session -t "$session" 2>/dev/null; then
            cleaned=1
            continue
        fi

        if [[ "$field3" == "exit" ]]; then
            # exit alerts are keyed on window_id (field 4). the stored name
            # drifts under automatic-rename, so validating by name would GC live
            # alerts; the id is stable. this also purges old nameless-id lines
            if [[ -z "$field4" ]] || ! tmux list-windows -t "$session" -F '#{window_id}' 2>/dev/null | grep -qxF "$field4"; then
                cleaned=1
                continue
            fi
        else
            # agent alerts: check the window name exists in the session. the
            # stored name is percent-encoded; decode before comparing
            local decoded_window
            decoded_window=$(alerts_decode_window "$window")
            if ! tmux list-windows -t "$session" -F '#{window_name}' 2>/dev/null | grep -qxF "$decoded_window"; then
                cleaned=1
                continue
            fi
        fi

        # target exists, keep the alert, preserve original line intact
        echo "$line" >>"$tmp_file"
    done <"$ALERTS_FILE"

    if [[ $cleaned -eq 1 ]]; then
        if [[ -f "$tmp_file" ]]; then
            mv "$tmp_file" "$ALERTS_FILE" 2>/dev/null
        else
            : >"$ALERTS_FILE"
        fi
    else
        rm -f "$tmp_file"
    fi

    _release_alerts_lock
}

# drop agent-state files whose pane no longer exists. per-pane files are
# independent, so no locking is needed; catches orphans left by crashed agents
# or a tmux server restart (SessionEnd handles the normal exit path)
# usage: cleanup_stale_agent_state
cleanup_stale_agent_state() {
    [[ -d "$AGENT_STATE_DIR" ]] || return 0

    local live_panes
    live_panes=$(tmux list-panes -a -F '#{pane_id}' 2>/dev/null) || return 0

    local f pane
    for f in "$AGENT_STATE_DIR"/*; do
        [[ -e "$f" ]] || continue
        pane="${f##*/}"
        grep -qxF "$pane" <<<"$live_panes" || rm -f "$f"
    done
}

# update window name in alerts file (for window renames)
# usage: update_window_name_in_alerts "session" "old_window" "new_window"
update_window_name_in_alerts() {
    local session="$1"
    local old_window="$2"
    local new_window="$3"

    [[ ! -f "$ALERTS_FILE" ]] && return 0

    # window names are stored percent-encoded; encode both sides to match
    local enc_old enc_new
    enc_old=$(alerts_encode_window "$old_window")
    enc_new=$(alerts_encode_window "$new_window")

    # check if there are any alerts for this window before locking
    grep -qF "${session}:${enc_old}:" "$ALERTS_FILE" 2>/dev/null || return 0

    if ! _acquire_alerts_lock; then
        return 0
    fi

    local tmp_file
    tmp_file=$(mktemp "${ALERTS_FILE}.tmp.XXXXXX")
    local update_success=0

    if sed "s|^${session}:${enc_old}:|${session}:${enc_new}:|" "$ALERTS_FILE" >"$tmp_file" 2>/dev/null; then
        if mv "$tmp_file" "$ALERTS_FILE" 2>/dev/null; then
            update_success=1
        fi
    fi

    # clean up temp file if update failed
    if [[ $update_success -eq 0 ]]; then
        rm -f "$tmp_file"
    fi

    _release_alerts_lock
}

# update session name in alerts file (for session renames)
# usage: update_session_name_in_alerts "old_session" "new_session"
update_session_name_in_alerts() {
    local old_session="$1"
    local new_session="$2"

    [[ ! -f "$ALERTS_FILE" ]] && return 0

    # check if there are any alerts for the old session before locking
    grep -qF "${old_session}:" "$ALERTS_FILE" 2>/dev/null || return 0

    if ! _acquire_alerts_lock; then
        return 0
    fi

    local tmp_file
    tmp_file=$(mktemp "${ALERTS_FILE}.tmp.XXXXXX")
    local update_success=0

    if sed "s|^${old_session}:|${new_session}:|" "$ALERTS_FILE" >"$tmp_file" 2>/dev/null; then
        if mv "$tmp_file" "$ALERTS_FILE" 2>/dev/null; then
            update_success=1
        fi
    fi

    # clean up temp file if update failed
    if [[ $update_success -eq 0 ]]; then
        rm -f "$tmp_file"
    fi

    _release_alerts_lock
}

# clear all alerts for a session
# usage: clear_session_alerts "session"
clear_session_alerts() {
    local session="$1"

    # finished-process rows for every window in this session clear with it,
    # mirroring how clear_window_alerts drops a single window's rows on select
    clear_session_finished "$session"

    # remove all entries for this session from alerts file with locking
    if [[ -f "$ALERTS_FILE" ]] && _acquire_alerts_lock; then
        local tmp_file
        tmp_file=$(mktemp "${ALERTS_FILE}.tmp.XXXXXX")
        local grep_exit=0
        grep -vF "${session}:" "$ALERTS_FILE" >"$tmp_file" 2>/dev/null || grep_exit=$?

        # exit code 0 or 1 are both success (0 = matches found, 1 = no matches/all filtered)
        if [[ $grep_exit -le 1 ]]; then
            mv "$tmp_file" "$ALERTS_FILE" 2>/dev/null || rm -f "$tmp_file" 2>/dev/null
        else
            rm -f "$tmp_file" 2>/dev/null
        fi

        _release_alerts_lock
    fi

    # unset agent options for all windows in session
    local win
    for win in $(tmux list-windows -t "$session" -F '#D' 2>/dev/null); do
        local alert_options
        alert_options=$(tmux show-options -wt "$win" 2>/dev/null | grep '@.*_alert' | cut -d' ' -f1 || true)

        if [[ -n "$alert_options" ]]; then
            while IFS= read -r option; do
                tmux set-option -wt "$win" -u "$option" 2>/dev/null || true
            done <<<"$alert_options"
        fi
    done
}
