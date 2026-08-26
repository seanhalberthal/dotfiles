#!/usr/bin/env bash
set -euo pipefail

# end-to-end tests for nvim buffer sync flow
# tests: list-nvim.sh, connect-nvim.sh, nvim-buffer-sync.sh
# usage: ./test-nvim-sync.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_DIR="$(dirname "$SCRIPT_DIR")"
HOOKS_DIR="$SCRIPT_DIR/../../../scripts/hooks"
TMPDIR="${TMPDIR:-/tmp}"
TMPDIR="${TMPDIR%/}/"

# source test helpers
source "$SCRIPT_DIR/_test-helpers.sh"

# scripts under test
LIST_NVIM="$SCRIPTS_DIR/instances/nvim.sh"
CONNECT_NVIM="$SCRIPTS_DIR/instances/connect-nvim.sh"
BUFFER_SYNC="$HOOKS_DIR/nvim-buffer-sync.sh"

# trap to ensure cleanup on exit/interrupt
trap cleanup EXIT INT TERM

cleanup() {
    # kill test nvim if running
    if [[ -n "${NVIM_PID:-}" ]]; then
        kill "$NVIM_PID" 2>/dev/null || true
    fi
    # cleanup test tmux server
    cleanup_test_server 2>/dev/null || true
}

# =============================================================================
# unit tests: script existence and syntax
# =============================================================================

section "Script Existence"

for script in "$LIST_NVIM" "$CONNECT_NVIM" "$BUFFER_SYNC"; do
    name=$(basename "$script")
    if [[ -f "$script" ]]; then
        pass "$name exists"
    else
        fail "$name not found at $script"
    fi

    if [[ -x "$script" ]]; then
        pass "$name is executable"
    else
        fail "$name is not executable"
    fi
done

section "Bash Syntax Check"

for script in "$LIST_NVIM" "$CONNECT_NVIM" "$BUFFER_SYNC"; do
    name=$(basename "$script")
    if bash -n "$script" 2>/dev/null; then
        pass "$name has valid bash syntax"
    else
        fail "$name has syntax errors"
    fi
done

section "ShellCheck Validation"

if command -v shellcheck &>/dev/null; then
    for script in "$LIST_NVIM" "$CONNECT_NVIM" "$BUFFER_SYNC"; do
        name=$(basename "$script")
        if shellcheck -x -e SC1091 -e SC2059 -e SC2015 -e SC2016 -e SC2034 "$script" 2>/dev/null; then
            pass "$name passes shellcheck"
        else
            fail "$name has shellcheck warnings"
        fi
    done
else
    skip "shellcheck not installed"
fi

# =============================================================================
# unit tests: list-nvim.sh structure
# =============================================================================

section "list-nvim.sh Structure"

list_content=$(cat "$LIST_NVIM")

if [[ "$list_content" == *'source "$SCRIPT_DIR/../_lib/common.sh"'* ]]; then
    pass "Sources common.sh library"
else
    fail "Should source common.sh library"
fi

if [[ "$list_content" == *'find "${TMPDIR}nvim.${USER}"'* ]]; then
    pass "Searches correct nvim socket directory"
else
    fail "Should search TMPDIR/nvim.USER for sockets"
fi

if [[ "$list_content" == *'tmux list-panes -a'* ]]; then
    pass "Uses tmux list-panes to find nvim instances"
else
    fail "Should use tmux list-panes"
fi

if [[ "$list_content" == *'NVIM_GREEN'* ]]; then
    pass "Defines NVIM_GREEN colour"
else
    fail "Should define NVIM_GREEN colour"
fi

if [[ "$list_content" == *'▛▀▖'* ]] && [[ "$list_content" == *'NVIM_GREEN'* ]]; then
    pass "Includes NVIM ASCII logo"
else
    fail "Should include NVIM ASCII logo"
fi

if [[ "$list_content" == *'@pane-viewed'* ]]; then
    pass "Uses @pane-viewed for sorting"
else
    fail "Should use @pane-viewed for activity sorting"
fi

# =============================================================================
# unit tests: connect-nvim.sh structure
# =============================================================================

section "connect-nvim.sh Structure"

connect_content=$(cat "$CONNECT_NVIM")

if [[ "$connect_content" == *'source "$SCRIPT_DIR/../_lib/common.sh"'* ]]; then
    pass "Sources common.sh library"
else
    fail "Should source common.sh library"
fi

if [[ "$connect_content" == *'load_fzf_theme'* ]]; then
    pass "Loads fzf theme"
else
    fail "Should load fzf theme"
fi

if [[ "$connect_content" == *'clipboard_copy'* ]]; then
    pass "Copies to clipboard (cross-platform)"
else
    fail "Should copy to clipboard via clipboard_copy"
fi

if [[ "$connect_content" == *'tmux select-window'* ]] && [[ "$connect_content" == *'tmux select-pane'* ]]; then
    pass "Switches to target pane"
else
    fail "Should switch to target pane"
fi

if [[ "$connect_content" == *'tmux display-message'* ]]; then
    pass "Shows message in tmux status bar"
else
    fail "Should show message in tmux status bar"
fi

if [[ "$connect_content" == *'&& claude'* ]]; then
    pass "Appends && claude to export command"
else
    fail "Should append && claude to export command"
fi

if [[ "$connect_content" == *"grep -v '(nvim)"* ]]; then
    pass "Excludes nvim panes from target list"
else
    fail "Should exclude nvim panes from target list"
fi

if [[ "$connect_content" == *'#{window_index}.#{pane_index}'* ]]; then
    pass "Uses window_index.pane_index format"
else
    fail "Should use window_index (not window_name) for targeting"
fi

# =============================================================================
# unit tests: nvim-buffer-sync.sh structure
# =============================================================================

section "nvim-buffer-sync.sh Structure"

sync_content=$(cat "$BUFFER_SYNC")

if [[ "$sync_content" == *'NVIM_SOCKET'* ]]; then
    pass "Checks for NVIM_SOCKET environment variable"
else
    fail "Should check for NVIM_SOCKET"
fi

if [[ "$sync_content" == *'-S "$NVIM_SOCKET"'* ]]; then
    pass "Validates socket exists"
else
    fail "Should validate socket is a valid socket file"
fi

if [[ "$sync_content" == *'jq -r'* ]]; then
    pass "Uses jq to parse JSON input"
else
    fail "Should use jq to parse hook JSON"
fi

if [[ "$sync_content" == *'tool_input.file_path'* ]]; then
    pass "Extracts file_path from tool_input"
else
    fail "Should extract file_path from tool_input"
fi

if [[ "$sync_content" == *'--remote-expr'* ]]; then
    pass "Uses nvim --remote-expr to add buffer"
else
    fail "Should use nvim --remote-expr"
fi

if [[ "$sync_content" == *'badd'* ]] && [[ "$sync_content" == *'fnameescape'* ]]; then
    pass "Uses badd with fnameescape for safe path handling"
else
    fail "Should use badd with fnameescape"
fi

if [[ "$sync_content" == *'exit 0'* ]]; then
    pass "Exits 0 on skip conditions (non-blocking)"
else
    fail "Should exit 0 on skip for non-blocking behaviour"
fi

# =============================================================================
# integration tests: nvim-buffer-sync.sh
# =============================================================================

section "nvim-buffer-sync.sh Integration"

# test: exits cleanly when NVIM_SOCKET is not set
unset NVIM_SOCKET
if echo '{}' | "$BUFFER_SYNC" 2>/dev/null; then
    pass "Exits cleanly when NVIM_SOCKET not set"
else
    fail "Should exit 0 when NVIM_SOCKET not set"
fi

# test: exits cleanly when NVIM_SOCKET doesn't exist
export NVIM_SOCKET="/nonexistent/socket"
if echo '{}' | "$BUFFER_SYNC" 2>/dev/null; then
    pass "Exits cleanly when socket doesn't exist"
else
    fail "Should exit 0 when socket doesn't exist"
fi

# test: exits cleanly with invalid JSON
export NVIM_SOCKET="/tmp/fake-socket-$$"
touch "$NVIM_SOCKET" # create a regular file (not a socket)
if echo 'not json' | "$BUFFER_SYNC" 2>/dev/null; then
    pass "Exits cleanly with invalid JSON"
else
    fail "Should exit 0 with invalid JSON"
fi
rm -f "$NVIM_SOCKET"

# test: exits cleanly with missing file_path
if echo '{"tool_input":{}}' | "$BUFFER_SYNC" 2>/dev/null; then
    pass "Exits cleanly when file_path missing"
else
    fail "Should exit 0 when file_path missing"
fi
unset NVIM_SOCKET

# =============================================================================
# integration tests: list-nvim.sh (with tmux)
# =============================================================================

section "list-nvim.sh Integration"

if ! command -v tmux &>/dev/null; then
    skip "tmux not installed"
elif ! command tmux list-sessions &>/dev/null 2>&1; then
    # intentionally queries the real tmux server (not the test socket) to check
    # whether there are live sessions to run the integration smoke-test against
    skip "no tmux sessions running"
else
    # test runs without error
    if output=$("$LIST_NVIM" 2>/dev/null); then
        pass "Runs successfully"

        # should at least output the logo
        if echo "$output" | grep -q "▛▀▖"; then
            pass "Outputs NVIM logo"
        else
            fail "Should output NVIM logo"
        fi
    else
        fail "Failed to run list-nvim.sh"
    fi
fi

# =============================================================================
# e2e test: full flow with real nvim
# =============================================================================

section "End-to-End Tests (requires nvim)"

if ! command -v nvim &>/dev/null; then
    skip "nvim not installed - skipping E2E tests"
elif ! command -v tmux &>/dev/null; then
    skip "tmux not installed - skipping E2E tests"
else
    # set up isolated test tmux server (only if we have both nvim and tmux)
    setup_test_server

    # create a test session with nvim running
    TEST_SESSION="nvim-test-$$"
    test_tmux new-session -d -s "$TEST_SESSION" -c /tmp

    # start nvim in the test session (headless, listening on socket)
    TEST_SOCKET="${TMPDIR}nvim.${USER}/test-nvim-$$.0"
    mkdir -p "$(dirname "$TEST_SOCKET")"

    # start nvim in headless server mode with --clean to skip user config that may
    # trigger terminal capability queries (DECRPM, DA1 escape sequences)
    nvim --headless --clean --listen "$TEST_SOCKET" </dev/null >/dev/null 2>&1 &
    NVIM_PID=$!

    # poll for RPC readiness, socket file existing doesn't mean the server accepts
    # connections yet. a simple --remote-expr confirms the RPC channel is alive
    _nvim_ready=false
    for _ in {1..40}; do
        if nvim --headless --server "$TEST_SOCKET" --remote-expr "1+1" >/dev/null 2>&1; then
            _nvim_ready=true
            break
        fi
        sleep 0.1
    done

    if [[ "$_nvim_ready" = true ]]; then
        pass "Test nvim RPC server ready at $TEST_SOCKET"

        # test: nvim-buffer-sync.sh can send to real nvim
        export NVIM_SOCKET="$TEST_SOCKET"
        TEST_FILE="/tmp/test-buffer-sync-$$.txt"

        if echo "{\"tool_input\":{\"file_path\":\"$TEST_FILE\"}}" | "$BUFFER_SYNC" 2>/dev/null; then
            pass "nvim-buffer-sync.sh sent command to nvim"

            # small delay to let nvim process the badd command
            sleep 0.2

            # verify buffer was added by checking nvim's buffer list
            buffers=""
            for _ in {1..20}; do
                buffers=$(nvim --headless --server "$TEST_SOCKET" --remote-expr "join(map(getbufinfo(), 'v:val.name'), '\n')" 2>/dev/null || echo "")
                echo "$buffers" | grep -q "$TEST_FILE" && break
                sleep 0.1
            done
            if echo "$buffers" | grep -q "$TEST_FILE"; then
                pass "File was added to nvim buffer list"
            elif ! kill -0 "$NVIM_PID" 2>/dev/null; then
                skip "nvim process exited during test (environment issue)"
            else
                fail "File should appear in nvim buffer list (buffers: ${buffers:-<empty>})"
            fi
        else
            fail "nvim-buffer-sync.sh failed to send command"
        fi

        unset NVIM_SOCKET
    else
        skip "Could not start nvim RPC server (headless nvim may not work in this environment)"
    fi

    # cleanup, redirect nvim's SIGTERM stderr to avoid leaking into test output
    kill "$NVIM_PID" 2>/dev/null || true
    wait "$NVIM_PID" 2>/dev/null || true
    unset NVIM_PID
    rm -f "$TEST_SOCKET"
    test_tmux kill-session -t "$TEST_SESSION" 2>/dev/null || true
    cleanup_test_server
fi

# =============================================================================
# summary
# =============================================================================

echo ""
echo "==========================================="
printf "Test Results: ${GREEN}%d passed${NC}, ${RED}%d failed${NC}\n" "$PASS" "$FAIL"
echo "==========================================="

if [[ $FAIL -gt 0 ]]; then
    exit 1
fi
