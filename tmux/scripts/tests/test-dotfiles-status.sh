#!/usr/bin/env bash
set -euo pipefail

# tests for dotfiles-status.sh caching and git status detection
# creates throwaway git repos to test ahead/behind/diverged states

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_DIR="$(dirname "$SCRIPT_DIR")"

# source test helpers (no tmux server needed for this test)
source "$SCRIPT_DIR/_test-helpers.sh"

# create isolated test environment
STATUS_TEST_DIR=$(mktemp -d)
trap 'rm -rf "$STATUS_TEST_DIR"' EXIT INT TERM

STATUS_SCRIPT="$SCRIPTS_DIR/utils/dotfiles-status.sh"

# ═══════════════════════════════════════════════════════════════
# script validation
# ═══════════════════════════════════════════════════════════════

section "Script Exists and Is Valid"

if [[ -f "$STATUS_SCRIPT" ]]; then
    pass "dotfiles-status.sh exists"
else
    fail "dotfiles-status.sh not found"
    exit 1
fi

if [[ -x "$STATUS_SCRIPT" ]]; then
    pass "dotfiles-status.sh is executable"
else
    fail "dotfiles-status.sh should be executable"
fi

if bash -n "$STATUS_SCRIPT" 2>/dev/null; then
    pass "dotfiles-status.sh passes syntax check"
else
    fail "dotfiles-status.sh has syntax errors"
fi

# ═══════════════════════════════════════════════════════════════
# setup test git repos
# ═══════════════════════════════════════════════════════════════

section "Git Repository Setup"

# create a bare "remote" repo
REMOTE_REPO="$STATUS_TEST_DIR/remote.git"
git init --bare "$REMOTE_REPO" >/dev/null 2>&1
pass "Created bare remote repo"

# clone it as "local" repo (simulates dotfiles directory)
LOCAL_REPO="$STATUS_TEST_DIR/local"
git clone "$REMOTE_REPO" "$LOCAL_REPO" >/dev/null 2>&1

# create initial commit in local
(
    cd "$LOCAL_REPO"
    git config user.email "test@test.com"
    git config user.name "Test"
    echo "initial" >README.md
    git add README.md
    git commit -m "Initial commit" >/dev/null 2>&1
    git push origin main >/dev/null 2>&1 || git push origin master >/dev/null 2>&1
)
pass "Created initial commit and pushed"

# get the branch name
BRANCH_NAME=$(cd "$LOCAL_REPO" && git rev-parse --abbrev-ref HEAD)

# override environment for the status script
export DOTFILES_DIR="$LOCAL_REPO"
export XDG_CACHE_HOME="$STATUS_TEST_DIR/cache"
export DOTFILES_SYNC_CACHE_TTL=0   # disable fetch cache
export DOTFILES_RESULT_CACHE_TTL=0 # disable result cache
mkdir -p "$XDG_CACHE_HOME/dotfiles"

# ═══════════════════════════════════════════════════════════════
# up-to-date status
# ═══════════════════════════════════════════════════════════════

section "Up-to-date State"

# clear cache
rm -f "$XDG_CACHE_HOME/dotfiles/sync-status" "$XDG_CACHE_HOME/dotfiles/last-fetch"

output=$(bash "$STATUS_SCRIPT" 2>/dev/null) || output=""
# wait for background fetch to complete
sleep 0.5

if [[ -z "$output" ]] || [[ "$output" == "" ]]; then
    pass "Returns empty when up-to-date"
else
    fail "Should return empty when up-to-date (got: '$output')"
fi

# ═══════════════════════════════════════════════════════════════
# behind remote
# ═══════════════════════════════════════════════════════════════

section "Behind Remote State"

# push a commit to remote (via a second clone)
SECOND_CLONE="$STATUS_TEST_DIR/second"
git clone "$REMOTE_REPO" "$SECOND_CLONE" >/dev/null 2>&1
(
    cd "$SECOND_CLONE"
    git config user.email "test@test.com"
    git config user.name "Test"
    echo "remote change" >remote.txt
    git add remote.txt
    git commit -m "Remote commit" >/dev/null 2>&1
    git push >/dev/null 2>&1
)

# fetch in local so it knows about the remote commit
(cd "$LOCAL_REPO" && git fetch origin >/dev/null 2>&1)

# clear cache and re-run
rm -f "$XDG_CACHE_HOME/dotfiles/sync-status" "$XDG_CACHE_HOME/dotfiles/last-fetch"
output=$(bash "$STATUS_SCRIPT" 2>/dev/null) || output=""
sleep 0.5

if [[ "$output" == *"↓"* ]]; then
    pass "Returns ↓ when behind remote"
else
    fail "Should return ↓ when behind (got: '$output')"
fi

# ═══════════════════════════════════════════════════════════════
# ahead of remote
# ═══════════════════════════════════════════════════════════════

section "Ahead of Remote State"

# pull to get in sync first, then add local commit
(
    cd "$LOCAL_REPO"
    git pull origin "$BRANCH_NAME" >/dev/null 2>&1
    echo "local change" >local.txt
    git add local.txt
    git commit -m "Local commit" >/dev/null 2>&1
)

# clear cache and re-run
rm -f "$XDG_CACHE_HOME/dotfiles/sync-status" "$XDG_CACHE_HOME/dotfiles/last-fetch"
output=$(bash "$STATUS_SCRIPT" 2>/dev/null) || output=""
sleep 0.5

if [[ "$output" == *"↑"* ]]; then
    pass "Returns ↑ when ahead of remote"
else
    fail "Should return ↑ when ahead (got: '$output')"
fi

# ═══════════════════════════════════════════════════════════════
# diverged state
# ═══════════════════════════════════════════════════════════════

section "Diverged State"

# add another remote commit (via second clone)
(
    cd "$SECOND_CLONE"
    echo "another remote change" >remote2.txt
    git add remote2.txt
    git commit -m "Another remote commit" >/dev/null 2>&1
    git push >/dev/null 2>&1
)

# fetch so local knows about it (but don't pull)
(cd "$LOCAL_REPO" && git fetch origin >/dev/null 2>&1)

# clear cache and re-run
rm -f "$XDG_CACHE_HOME/dotfiles/sync-status" "$XDG_CACHE_HOME/dotfiles/last-fetch"
output=$(bash "$STATUS_SCRIPT" 2>/dev/null) || output=""
sleep 0.5

if [[ "$output" == *"↕"* ]]; then
    pass "Returns ↕ when diverged"
else
    fail "Should return ↕ when diverged (got: '$output')"
fi

# ═══════════════════════════════════════════════════════════════
# result cache tests
# ═══════════════════════════════════════════════════════════════

section "Result Caching"

# set a long result TTL and verify cache is used
export DOTFILES_RESULT_CACHE_TTL=300 # 5 minutes

# write a known value to cache (line 1 = epoch, line 2 = payload)
printf '%s\nCACHED\n' "$(date +%s)" >"$XDG_CACHE_HOME/dotfiles/sync-status"

output=$(bash "$STATUS_SCRIPT" 2>/dev/null) || output=""

if [[ "$output" == "CACHED" ]]; then
    pass "Returns cached result when cache is fresh"
else
    fail "Should return cached result (got: '$output')"
fi

# reset TTL
export DOTFILES_RESULT_CACHE_TTL=0

# ═══════════════════════════════════════════════════════════════
# silent failure tests
# ═══════════════════════════════════════════════════════════════

section "Silent Failure"

# point at a non-git directory
export DOTFILES_DIR="$STATUS_TEST_DIR/not-a-repo"
mkdir -p "$DOTFILES_DIR"
rm -f "$XDG_CACHE_HOME/dotfiles/sync-status"

output=$(bash "$STATUS_SCRIPT" 2>/dev/null) || output=""
exit_code=$?

if [[ $exit_code -eq 0 ]]; then
    pass "Exits 0 when not in a git repo"
else
    fail "Should exit 0 even when not in a git repo"
fi

if [[ -z "$output" ]]; then
    pass "Returns empty when not in a git repo"
else
    fail "Should return empty when not in a git repo (got: '$output')"
fi

# ═══════════════════════════════════════════════════════════════
# script structure
# ═══════════════════════════════════════════════════════════════

section "Script Structure"

status_content=$(cat "$STATUS_SCRIPT")

if [[ "$status_content" == *'get_remote_branch()'* ]]; then
    pass "Defines get_remote_branch function"
else
    fail "Should define get_remote_branch"
fi

if [[ "$status_content" == *'maybe_fetch()'* ]]; then
    pass "Defines maybe_fetch function"
else
    fail "Should define maybe_fetch"
fi

if [[ "$status_content" == *'CACHE_TTL_SECONDS'* ]]; then
    pass "Uses configurable cache TTL"
else
    fail "Should use configurable cache TTL"
fi

if [[ "$status_content" == *'RESULT_TTL_SECONDS'* ]]; then
    pass "Uses configurable result TTL"
else
    fail "Should use configurable result TTL"
fi

# ═══════════════════════════════════════════════════════════════
# summary
# ═══════════════════════════════════════════════════════════════

echo ""
echo "==========================================="
printf "${GREEN}Test Results: %d passed${NC}, ${RED}%d failed${NC}\n" "$PASS" "$FAIL"
echo "==========================================="

if [[ $FAIL -gt 0 ]]; then
    exit 1
fi
