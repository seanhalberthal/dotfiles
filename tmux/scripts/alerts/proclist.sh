#!/usr/bin/env bash
# proclist: unified picker source for running + finished processes.
#   running rows come from the in-flight registry (RUNNING_DIR), written by the
#   zsh cmd-alert hook while a tracked command is executing.
#   finished rows come from the alerts file (:exit: lines), set on completion.
# emits a 3-line legend header then tab-delimited rows for fzf:
#   {1}=display(shown)  {2}=type(run|exit)  {3}=jump/preview target
#   {4}=argA  {5}=argB   (run: argA=pane_id; exit: argA=session, argB=window)
# the prefix+P binding in tmux.conf.template runs fzf over this output.
set -euo pipefail

SCRIPT_DIR="${BASH_SOURCE%/*}"
source "$SCRIPT_DIR/../_lib/alerts.sh"

# _ansi and _fmt_elapsed come from _lib/alerts.sh

# legend header (3 lines, matched by --header-lines=3 in the binding)
run_disp=$(get_running_display)
run_icon="${run_disp%%|*}"
run_col="${run_disp##*|}"
ok_disp=$(get_exit_code_display 0)
ok_icon="${ok_disp%%|*}"
ok_col="${ok_disp##*|}"
err_disp=$(get_exit_code_display 1)
err_icon="${err_disp%%|*}"
err_col="${err_disp##*|}"
int_disp=$(get_exit_code_display 130)
int_icon="${int_disp%%|*}"
int_col="${int_disp##*|}"
echo ""
printf '  %s running  %s done  %s failed  %s stopped\n' \
    "$(_ansi "$run_col" "$run_icon")" \
    "$(_ansi "$ok_col" "$ok_icon")" \
    "$(_ansi "$err_col" "$err_icon")" \
    "$(_ansi "$int_col" "$int_icon")"
echo ""

# without tmux there is nothing to map rows against
command -v tmux >/dev/null 2>&1 || exit 0
tmux list-sessions >/dev/null 2>&1 || exit 0

# one pass over every pane: pane_id -> jump target + "session:window" display,
# and (session<TAB>window_name) -> window_id for resolving finished rows.
# window_name is last so an (improbable) embedded tab can't shift other fields
TAB=$(printf '\t')
declare -A pane_target pane_display wid_exists
while IFS="$TAB" read -r pid sess widx pidx winid wname; do
    [[ -n "$pid" ]] || continue
    pane_target["$pid"]="${sess}:${widx}.${pidx}"
    pane_display["$pid"]="${sess}:${wname}"
    wid_exists["$winid"]=1
done < <(tmux list-panes -a -F \
    "#{pane_id}${TAB}#{session_name}${TAB}#{window_index}${TAB}#{pane_index}${TAB}#{window_id}${TAB}#{window_name}" \
    2>/dev/null)

# ── running rows (registry), most recently started first ────────────────────
now=$(date +%s)
if [[ -d "$RUNNING_DIR" ]]; then
    run_rows=()
    for f in "$RUNNING_DIR"/*; do
        [[ -e "$f" ]] || continue
        IFS="$TAB" read -r r_pane r_start r_shell r_label <"$f"
        [[ -n "$r_pane" ]] || {
            rm -f "$f"
            continue
        }
        # stale if the owning shell died before precmd could clean up
        if [[ -n "$r_shell" ]] && ! kill -0 "$r_shell" 2>/dev/null; then
            rm -f "$f"
            continue
        fi
        target="${pane_target[$r_pane]:-}"
        disp_sw="${pane_display[$r_pane]:-}"
        # pane no longer exists -> stale entry
        [[ -n "$target" ]] || {
            rm -f "$f"
            continue
        }
        r_label="${r_label//$TAB/ }"
        if [[ "$r_start" =~ ^[0-9]+$ ]] && ((r_start > 0)); then
            elapsed=$((now - r_start))
            ((elapsed < 0)) && elapsed=0
            meta=$(_fmt_elapsed "$elapsed")
        else
            elapsed=0
            meta="·"
        fi
        display="$(_ansi "$run_col" "$run_icon")  ${disp_sw}  ${r_label}  ${meta}"
        # leading sort key (elapsed, zero-padded) is stripped after sorting
        run_rows+=("$(printf '%012d%s%s%srun%s%s%s%s%s-' \
            "$elapsed" "$TAB" "$display" "$TAB" "$TAB" "$target" "$TAB" "$r_pane" "$TAB")")
    done
    if ((${#run_rows[@]})); then
        printf '%s\n' "${run_rows[@]}" | sort -n | cut -f2-
    fi
fi

# prune stale kill-suppress markers: precmd consumes and removes its own
# marker on completion, but if the interrupted command took the whole pane
# down with it (no further precmd ever fires), the marker would otherwise sit
# forever. anything older than a normal command-exit turnaround is orphaned
SUPPRESS_MAX_AGE=10
if [[ -d "$SUPPRESS_DIR" ]]; then
    for f in "$SUPPRESS_DIR"/*; do
        [[ -e "$f" ]] || continue
        mtime=$(stat -f %m "$f" 2>/dev/null || stat -c %Y "$f" 2>/dev/null) || continue
        ((now - mtime > SUPPRESS_MAX_AGE)) && rm -f "$f"
    done
fi

# ── finished rows (history file): newest first, last hour ───────────────────
# the alerts file (status-right + window-status exit indicators) has no TTL of
# its own: an exit line clears only when its window is selected or its session
# dies. the finished file ages out at an hour, so a window you never revisit
# kept its indicator long after the proclist "done" row had gone. when a row is
# dropped here (aged out, or evicted to bound the file) we clear that window's
# exit indicator too, keyed on the stable window_id, unless a retained row still
# justifies it
FINISHED_MAX_AGE=3600 # drop entries older than an hour
FINISHED_MAX_SHOW=20  # show at most this many
FINISHED_MAX_KEEP=200 # retain at most this many in the file (newest first),
# bounds growth under heavy churn; kept > shown so rows
# below the fold still pair with their indicator
if [[ -f "$FINISHED_FILE" ]]; then
    cutoff=$((now - FINISHED_MAX_AGE))
    declare -A drop_wids keep_wids # windows losing / retaining a finished row
    fresh=()                       # within-age TSV lines, epoch-prefixed for newest-first sort
    done_rows=()                   # display rows, prefixed with epoch for sorting
    total=0                        # every line read, to decide whether a GC rewrite is needed
    while IFS="$TAB" read -r f_epoch f_exit f_sess f_wid f_wname f_label f_cmd; do
        total=$((total + 1))
        [[ "$f_epoch" =~ ^[0-9]+$ ]] || continue
        if ((f_epoch < cutoff)); then
            # aged out: candidate for clearing a now-stranded exit indicator
            [[ -n "$f_wid" ]] && drop_wids["$f_wid"]=1
            continue
        fi
        # within age: retain verbatim (epoch sort-key prefix stripped on write),
        # cmd field (rerun source) rides along untouched
        fresh+=("$(printf '%s%s%s%s%s%s%s%s%s%s%s%s%s%s%s' \
            "$f_epoch" "$TAB" "$f_epoch" "$TAB" "$f_exit" "$TAB" "$f_sess" "$TAB" "$f_wid" "$TAB" "$f_wname" "$TAB" "$f_label" "$TAB" "$f_cmd")")
        f_label="${f_label//$TAB/ }"
        disp=$(get_exit_code_display "$f_exit")
        icon="${disp%%|*}"
        col="${disp##*|}"
        ago=$(_fmt_elapsed "$((now - f_epoch))")
        display="$(_ansi "$col" "$icon")  ${f_sess}:${f_wname}  ${f_label}  (${ago} ago)"
        # jump target = window_id if that window still exists, else blank
        tgt=""
        [[ -n "${wid_exists[$f_wid]:-}" ]] && tgt="$f_wid"
        done_rows+=("$(printf '%s%s%s%sdone%s%s%s%s%s%s' \
            "$f_epoch" "$TAB" "$display" "$TAB" "$TAB" "$tgt" "$TAB" "$f_epoch" "$TAB" "$f_wid")")
    done <"$FINISHED_FILE"

    # emit newest first, capped (awk drains stdin so sort never hits SIGPIPE)
    if ((${#done_rows[@]})); then
        printf '%s\n' "${done_rows[@]}" | sort -rn |
            awk -v n="$FINISHED_MAX_SHOW" 'NR<=n' | cut -f2-
    fi

    # retain the newest FINISHED_MAX_KEEP within-age rows; rows beyond the cap
    # (and the aged rows above) are dropped and their windows flagged for an
    # indicator clear unless a retained row keeps the window justified
    keep_lines=()
    if ((${#fresh[@]})); then
        idx=0
        while IFS="$TAB" read -r _sk k_epoch k_exit k_sess k_wid k_wname k_label k_cmd; do
            if ((idx < FINISHED_MAX_KEEP)); then
                keep_lines+=("$(printf '%s%s%s%s%s%s%s%s%s%s%s%s%s' \
                    "$k_epoch" "$TAB" "$k_exit" "$TAB" "$k_sess" "$TAB" "$k_wid" "$TAB" "$k_wname" "$TAB" "$k_label" "$TAB" "$k_cmd")")
                [[ -n "$k_wid" ]] && keep_wids["$k_wid"]=1
            else
                [[ -n "$k_wid" ]] && drop_wids["$k_wid"]=1
            fi
            idx=$((idx + 1))
        done < <(printf '%s\n' "${fresh[@]}" | sort -rn)
    fi

    # rewrite the file if any line was dropped (aged, over-cap, or malformed)
    if ((${#keep_lines[@]} != total)); then
        tmpf=$(mktemp "${FINISHED_FILE}.XXXXXX" 2>/dev/null) || tmpf=""
        if [[ -n "$tmpf" ]]; then
            ((${#keep_lines[@]})) && printf '%s\n' "${keep_lines[@]}" >"$tmpf" || : >"$tmpf"
            mv "$tmpf" "$FINISHED_FILE" 2>/dev/null || rm -f "$tmpf"
        fi
    fi

    # clear exit indicators stranded by the drops above, keyed on window_id
    for wid in "${!drop_wids[@]}"; do
        [[ -n "${keep_wids[$wid]:-}" ]] && continue
        clear_window_exit_alert "$wid" || true
    done
fi
