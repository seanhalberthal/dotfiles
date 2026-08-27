#!/usr/bin/env bash
# dotfiles sync status indicator for tmux status bar
# shows icon when local dotfiles are behind/ahead of origin
#
# output:
#   ↓  behind origin (updates available)
#   ↑  ahead of origin (unpushed commits)
#   ↕  diverged (both ahead and behind)
#   (empty) up-to-date or error (silent fail)
#
# caches git fetch (default: 5 min) and computed result (default: 30s)
# to avoid expensive git operations on every status bar refresh

set -euo pipefail

DOTFILES_DIR="${DOTFILES_DIR:-$HOME/dotfiles}"
CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/dotfiles"
CACHE_FILE="$CACHE_DIR/sync-status"
FETCH_CACHE_FILE="$CACHE_DIR/last-fetch"
CACHE_TTL_SECONDS="${DOTFILES_SYNC_CACHE_TTL:-300}"   # 5 minutes default
RESULT_TTL_SECONDS="${DOTFILES_RESULT_CACHE_TTL:-30}" # 30 seconds default

# silent exit helper (no output on failure)
bail() {
    exit 0
}

# serve from result cache if fresh. this is the hot path (runs every
# status-interval), so it uses bash builtins only, no date/stat/cat forks.
# cache format: line 1 = epoch written, line 2 = payload
now="${EPOCHSECONDS:-$(date +%s)}"
if [[ -f "$CACHE_FILE" ]]; then
    { IFS= read -r cache_ts && IFS= read -r cache_payload; } <"$CACHE_FILE" 2>/dev/null ||
        {
            cache_ts=0
            cache_payload=""
        }
    if [[ "$cache_ts" =~ ^[0-9]+$ ]] && ((now - cache_ts < RESULT_TTL_SECONDS)); then
        printf '%s' "$cache_payload"
        exit 0
    fi
fi

# ensure cache directory exists (only reached on cache miss)
[[ -d "$CACHE_DIR" ]] || mkdir -p "$CACHE_DIR"

# check if we're in a git repo
cd "$DOTFILES_DIR" 2>/dev/null || bail
git rev-parse --git-dir &>/dev/null || bail

# get the default remote branch (origin/main, origin/master, etc.)
get_remote_branch() {
    local ref
    # try to get the default branch from origin
    ref=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null) || {
        # fallback: try to detect from remote
        ref=$(git remote show origin 2>/dev/null | grep 'HEAD branch' | awk '{print $NF}')
        if [[ -n "$ref" ]]; then
            echo "origin/$ref"
            return
        fi
        # last resort: try common names
        if git rev-parse --verify origin/main &>/dev/null; then
            echo "origin/main"
        elif git rev-parse --verify origin/master &>/dev/null; then
            echo "origin/master"
        else
            return 1
        fi
        return
    }
    # convert refs/remotes/origin/main -> origin/main
    echo "${ref#refs/remotes/}"
}

# fetch from origin if cache is stale
maybe_fetch() {
    local now last_fetch age

    now=$(date +%s)

    if [[ -f "$FETCH_CACHE_FILE" ]]; then
        last_fetch=$(<"$FETCH_CACHE_FILE") || last_fetch=0
        age=$((now - last_fetch))

        if [[ $age -lt $CACHE_TTL_SECONDS ]]; then
            return 0 # cache still fresh
        fi
    fi

    # fetch in background to avoid blocking tmux
    git fetch origin --quiet 2>/dev/null &
    echo "$now" >"$FETCH_CACHE_FILE"
}

# main logic
main() {
    local remote_branch behind ahead output=""

    remote_branch=$(get_remote_branch) || bail

    # trigger background fetch if needed
    maybe_fetch

    # count commits behind and ahead
    behind=$(git rev-list HEAD.."$remote_branch" --count 2>/dev/null) || behind=0
    ahead=$(git rev-list "$remote_branch"..HEAD --count 2>/dev/null) || ahead=0

    # build output
    if [[ $behind -gt 0 && $ahead -gt 0 ]]; then
        output="↕ "
    elif [[ $behind -gt 0 ]]; then
        output="↓ "
    elif [[ $ahead -gt 0 ]]; then
        output="↑ "
    fi

    # cache the result (line 1 = epoch, line 2 = payload; read by the
    # builtin-only hot path above)
    printf '%s\n%s\n' "$now" "$output" >"$CACHE_FILE"

    # output for tmux
    printf "%s" "$output"
}

main
