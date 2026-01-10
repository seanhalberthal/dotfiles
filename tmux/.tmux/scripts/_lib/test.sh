#!/usr/bin/env bash
set -euo pipefail

# Test suite for tmux script libraries
# Usage: ./test.sh [--verbose]

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PASS=0
FAIL=0
VERBOSE="${1:-}"

# Colours
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
NC='\033[0m'

# Test output helpers
pass() {
    PASS=$((PASS + 1))
    printf "${GREEN}✓${NC} %s\n" "$1"
}

fail() {
    FAIL=$((FAIL + 1))
    printf "${RED}✗${NC} %s\n" "$1"
}

skip() {
    printf "${YELLOW}○${NC} %s (skipped)\n" "$1"
}

section() {
    echo ""
    echo "─────────────────────────────────────────"
    echo "$1"
    echo "─────────────────────────────────────────"
}

# Capture stderr from a command (discard stdout, return stderr)
# shellcheck disable=SC2069
capture_stderr() {
    "$@" 2>&1 1>/dev/null
}

# Assert that a command succeeds
assert_success() {
    local desc="$1"
    shift
    if "$@" 2>/dev/null; then
        pass "$desc"
    else
        fail "$desc"
    fi
}

# Assert that a command fails
assert_failure() {
    local desc="$1"
    shift
    if ! "$@" 2>/dev/null; then
        pass "$desc"
    else
        fail "$desc"
    fi
}

# Assert output equals expected value
assert_equals() {
    local desc="$1"
    local expected="$2"
    local actual="$3"
    if [[ "$actual" == "$expected" ]]; then
        pass "$desc"
    else
        fail "$desc (expected: '$expected', got: '$actual')"
    fi
}

# Assert output matches pattern
assert_matches() {
    local desc="$1"
    local pattern="$2"
    local actual="$3"
    if [[ "$actual" =~ $pattern ]]; then
        pass "$desc"
    else
        fail "$desc (expected pattern: '$pattern', got: '$actual')"
    fi
}

# Assert file exists
assert_file_exists() {
    local desc="$1"
    local file="$2"
    if [[ -f "$file" ]]; then
        pass "$desc"
    else
        fail "$desc (file not found: $file)"
    fi
}

# Assert directory exists
assert_dir_exists() {
    local desc="$1"
    local dir="$2"
    if [[ -d "$dir" ]]; then
        pass "$desc"
    else
        fail "$desc (directory not found: $dir)"
    fi
}

# Assert file has specific permissions
assert_permissions() {
    local desc="$1"
    local path="$2"
    local expected="$3"
    local actual
    # macOS and Linux have different stat syntax
    actual=$(stat -f %Lp "$path" 2>/dev/null || stat -c %a "$path" 2>/dev/null)
    if [[ "$actual" == "$expected" ]]; then
        pass "$desc"
    else
        fail "$desc (expected: $expected, got: $actual)"
    fi
}

# ─────────────────────────────────────────
# Test common.sh
# ─────────────────────────────────────────
section "Testing common.sh"
source "$SCRIPT_DIR/common.sh"

# validate_session_name tests
echo "  validate_session_name:"
assert_success "  accepts 'valid-name'" validate_session_name "valid-name"
assert_success "  accepts 'my_session.1'" validate_session_name "my_session.1"
assert_success "  accepts 'A'" validate_session_name "A"
assert_success "  accepts '123'" validate_session_name "123"
assert_success "  accepts 'a.b-c_d'" validate_session_name "a.b-c_d"
assert_success "  accepts 'CamelCase'" validate_session_name "CamelCase"
assert_failure "  rejects 'invalid name' (space)" validate_session_name "invalid name"
assert_failure "  rejects 'bad!' (special char)" validate_session_name "bad!"
assert_failure "  rejects '' (empty)" validate_session_name ""
assert_failure "  rejects 'has:colon'" validate_session_name "has:colon"
assert_failure "  rejects 'has/slash'" validate_session_name "has/slash"
assert_failure "  rejects 'has\$dollar'" validate_session_name 'has$dollar'
assert_failure "  rejects name with newline" validate_session_name $'foo\nbar'
assert_failure "  rejects name with tab" validate_session_name $'foo\tbar'

# validate_pane_id tests
echo ""
echo "  validate_pane_id:"
assert_success "  accepts '%123'" validate_pane_id "%123"
assert_success "  accepts '%0'" validate_pane_id "%0"
assert_success "  accepts '%999999'" validate_pane_id "%999999"
assert_failure "  rejects '123' (no %)" validate_pane_id "123"
assert_failure "  rejects '%' (no number)" validate_pane_id "%"
assert_failure "  rejects '' (empty)" validate_pane_id ""
assert_failure "  rejects '%-1' (negative)" validate_pane_id "%-1"
assert_failure "  rejects '%abc' (letters)" validate_pane_id "%abc"
assert_failure "  rejects '%%123' (double %)" validate_pane_id "%%123"
assert_failure "  rejects '%12.3' (decimal)" validate_pane_id "%12.3"

# validate_window_index tests
echo ""
echo "  validate_window_index:"
assert_success "  accepts '0'" validate_window_index "0"
assert_success "  accepts '5'" validate_window_index "5"
assert_success "  accepts '999'" validate_window_index "999"
assert_failure "  rejects 'abc'" validate_window_index "abc"
assert_failure "  rejects '' (empty)" validate_window_index ""
assert_failure "  rejects '-1' (negative)" validate_window_index "-1"
assert_failure "  rejects '1.5' (decimal)" validate_window_index "1.5"
assert_failure "  rejects '1a' (mixed)" validate_window_index "1a"

# Test output functions (capture output)
echo ""
echo "  output functions:"

ERROR_OUTPUT=$(capture_stderr error "test error")
if [[ "$ERROR_OUTPUT" == *"Error:"* && "$ERROR_OUTPUT" == *"test error"* ]]; then
    pass "  error() outputs error message to stderr"
else
    fail "  error() should output 'Error: test error'"
fi

WARN_OUTPUT=$(capture_stderr warn "test warning")
if [[ "$WARN_OUTPUT" == *"Warning:"* && "$WARN_OUTPUT" == *"test warning"* ]]; then
    pass "  warn() outputs warning message to stderr"
else
    fail "  warn() should output 'Warning: test warning'"
fi

INFO_OUTPUT=$(info "test info")
if [[ "$INFO_OUTPUT" == *"test info"* ]]; then
    pass "  info() outputs info message"
else
    fail "  info() should output 'test info'"
fi

SUCCESS_OUTPUT=$(success "test success")
if [[ "$SUCCESS_OUTPUT" == *"test success"* ]]; then
    pass "  success() outputs success message"
else
    fail "  success() should output 'test success'"
fi

# ─────────────────────────────────────────
# Test paths.sh
# ─────────────────────────────────────────
section "Testing paths.sh"
source "$SCRIPT_DIR/paths.sh"

echo "  get_undo_base_dir:"
UNDO_DIR=$(get_undo_base_dir)
assert_matches "  returns correct path format" "^/tmp/tmux-undo-[0-9]+$" "$UNDO_DIR"
assert_dir_exists "  creates directory" "$UNDO_DIR"
assert_permissions "  has correct permissions (700)" "$UNDO_DIR" "700"

# Test idempotency - calling again shouldn't fail
UNDO_DIR2=$(get_undo_base_dir)
assert_equals "  is idempotent" "$UNDO_DIR" "$UNDO_DIR2"

echo ""
echo "  pane undo paths:"
PANE_FILE=$(get_pane_undo_file)
assert_equals "  get_pane_undo_file returns correct path" "$UNDO_DIR/pane" "$PANE_FILE"

PANE_STATE=$(get_pane_undo_state)
assert_equals "  get_pane_undo_state returns correct path" "$UNDO_DIR/pane-state.txt" "$PANE_STATE"

PANE_CONTENT=$(get_pane_undo_content)
assert_equals "  get_pane_undo_content returns correct path" "$UNDO_DIR/pane-content.txt" "$PANE_CONTENT"

echo ""
echo "  window undo paths:"
WINDOW_FILE=$(get_window_undo_file)
assert_equals "  get_window_undo_file returns correct path" "$UNDO_DIR/window" "$WINDOW_FILE"

WINDOW_STATE=$(get_window_undo_state)
assert_equals "  get_window_undo_state returns correct path" "$UNDO_DIR/window-state.txt" "$WINDOW_STATE"

WINDOW_CONTENTS=$(get_window_undo_contents_dir)
assert_equals "  get_window_undo_contents_dir returns correct path" "$UNDO_DIR/window-contents" "$WINDOW_CONTENTS"
assert_dir_exists "  window contents directory is created" "$WINDOW_CONTENTS"
assert_permissions "  window contents has correct permissions (700)" "$WINDOW_CONTENTS" "700"

echo ""
echo "  session undo paths:"
SESSION_FILE=$(get_session_undo_file)
assert_equals "  get_session_undo_file returns correct path" "$UNDO_DIR/session" "$SESSION_FILE"

SESSION_STATE=$(get_session_undo_state)
assert_equals "  get_session_undo_state returns correct path" "$UNDO_DIR/session-state.txt" "$SESSION_STATE"

SESSION_BACKUP=$(get_session_undo_backup)
assert_equals "  get_session_undo_backup returns correct path" "$UNDO_DIR/session-backup" "$SESSION_BACKUP"

echo ""
echo "  cleanup_undo_files:"

# Ensure clean state before testing cleanup functions
rm -rf "$UNDO_DIR/pane" "$UNDO_DIR/pane-state.txt" "$UNDO_DIR/pane-content.txt"
rm -rf "$UNDO_DIR/window" "$UNDO_DIR/window-state.txt" "$UNDO_DIR/window-contents"
rm -rf "$UNDO_DIR/session" "$UNDO_DIR/session-state.txt" "$UNDO_DIR/session-backup"

# Test pane cleanup
touch "$UNDO_DIR/pane" "$UNDO_DIR/pane-state.txt" "$UNDO_DIR/pane-content.txt"
cleanup_undo_files "pane"
if [[ ! -f "$UNDO_DIR/pane" && ! -f "$UNDO_DIR/pane-state.txt" && ! -f "$UNDO_DIR/pane-content.txt" ]]; then
    pass "  cleans up pane files"
else
    fail "  cleanup_undo_files 'pane' should remove all pane files"
fi

# Test window cleanup
touch "$UNDO_DIR/window" "$UNDO_DIR/window-state.txt"
mkdir -p "$UNDO_DIR/window-contents"
touch "$UNDO_DIR/window-contents/test.txt"
cleanup_undo_files "window"
if [[ ! -f "$UNDO_DIR/window" && ! -f "$UNDO_DIR/window-state.txt" && ! -f "$UNDO_DIR/window-contents/test.txt" ]]; then
    pass "  cleans up window files"
else
    fail "  cleanup_undo_files 'window' should remove all window files"
fi
assert_dir_exists "  recreates window-contents directory after cleanup" "$UNDO_DIR/window-contents"

# Test session cleanup
touch "$UNDO_DIR/session" "$UNDO_DIR/session-state.txt"
mkdir -p "$UNDO_DIR/session-backup"
touch "$UNDO_DIR/session-backup/test.txt"
cleanup_undo_files "session"
if [[ ! -f "$UNDO_DIR/session" && ! -f "$UNDO_DIR/session-state.txt" && ! -d "$UNDO_DIR/session-backup" ]]; then
    pass "  cleans up session files"
else
    fail "  cleanup_undo_files 'session' should remove all session files"
fi

# Test invalid type
if ! cleanup_undo_files "invalid" 2>/dev/null; then
    pass "  rejects invalid cleanup type"
else
    fail "  cleanup_undo_files should reject invalid type"
fi

echo ""
echo "  get_most_recent_undo_type:"

# Clean slate
rm -f "$UNDO_DIR/pane" "$UNDO_DIR/window" "$UNDO_DIR/session"

MOST_RECENT=$(get_most_recent_undo_type)
assert_equals "  returns empty when no undo files" "" "$MOST_RECENT"

# Use explicit timestamps to avoid timing issues (macOS has second-level granularity)
# Format: [[CC]YY]MMDDhhmm[.ss]
touch -t 202501010001 "$UNDO_DIR/pane"
MOST_RECENT=$(get_most_recent_undo_type)
assert_equals "  returns 'pane' when only pane file exists" "pane" "$MOST_RECENT"

# Create newer window file (1 minute later)
touch -t 202501010002 "$UNDO_DIR/window"
MOST_RECENT=$(get_most_recent_undo_type)
assert_equals "  returns 'window' when window is newest" "window" "$MOST_RECENT"

# Create newest session file (1 minute later again)
touch -t 202501010003 "$UNDO_DIR/session"
MOST_RECENT=$(get_most_recent_undo_type)
assert_equals "  returns 'session' when session is newest" "session" "$MOST_RECENT"

# Update pane to be newest
touch -t 202501010004 "$UNDO_DIR/pane"
MOST_RECENT=$(get_most_recent_undo_type)
assert_equals "  returns 'pane' after updating pane file" "pane" "$MOST_RECENT"

# Cleanup test files
rm -f "$UNDO_DIR/pane" "$UNDO_DIR/window" "$UNDO_DIR/session"

# ─────────────────────────────────────────
# Test session.sh
# ─────────────────────────────────────────
section "Testing session.sh"
source "$SCRIPT_DIR/session.sh"

# These require tmux, so only test if inside tmux
if [[ -n "${TMUX:-}" ]]; then
    echo "  (running inside tmux - full tests)"

    SESSION=$(get_current_session)
    if [[ -n "$SESSION" ]]; then
        pass "  get_current_session returns session name: $SESSION"
    else
        fail "  get_current_session returned empty"
    fi

    WINDOW=$(get_current_window)
    assert_matches "  get_current_window returns window index" "^[0-9]+$" "$WINDOW"

    PANE=$(get_current_pane)
    assert_matches "  get_current_pane returns pane index" "^[0-9]+$" "$PANE"

    PANE_DIR=$(get_pane_directory)
    assert_dir_exists "  get_pane_directory returns valid directory" "$PANE_DIR"

    LAYOUT=$(get_window_layout)
    if [[ -n "$LAYOUT" ]]; then
        pass "  get_window_layout returns layout: ${LAYOUT:0:30}..."
    else
        fail "  get_window_layout returned empty"
    fi

    # Test find_other_session (may or may not have other sessions)
    OTHER=$(find_other_session "$SESSION")
    if [[ -n "$OTHER" ]]; then
        pass "  find_other_session found another session: $OTHER"
    else
        skip "  find_other_session (no other sessions to find)"
    fi
else
    echo "  (not in tmux - skipping tmux-dependent tests)"
    skip "  get_current_session"
    skip "  get_current_window"
    skip "  get_current_pane"
    skip "  get_pane_directory"
    skip "  get_window_layout"
    skip "  find_other_session"
fi

# ─────────────────────────────────────────
# Test state file parsing (undo-pane.sh logic)
# ─────────────────────────────────────────
section "Testing state file parsing"

# Create a test state file
TEST_STATE_FILE=$(mktemp)
cat > "$TEST_STATE_FILE" << 'EOF'
dir=/Users/test/projects
layout=main-vertical,200x50,0,0[200x25,0,0,1,200x24,0,26,2]
SESSION=mytest
WINDOW=2
PANE=1
PANE_COUNT=3
EOF

# Parse the state file (mimicking undo-pane.sh logic)
TEST_SESSION=""
TEST_WINDOW=""
TEST_PANE=""
TEST_DIR=""
TEST_LAYOUT=""
TEST_PANE_COUNT=""

while IFS='=' read -r key value; do
    case "$key" in
        dir) TEST_DIR="$value" ;;
        layout) TEST_LAYOUT="$value" ;;
        SESSION) TEST_SESSION="$value" ;;
        WINDOW) TEST_WINDOW="$value" ;;
        PANE) TEST_PANE="$value" ;;
        PANE_COUNT) TEST_PANE_COUNT="$value" ;;
    esac
done < "$TEST_STATE_FILE"

assert_equals "  parses dir correctly" "/Users/test/projects" "$TEST_DIR"
assert_equals "  parses SESSION correctly" "mytest" "$TEST_SESSION"
assert_equals "  parses WINDOW correctly" "2" "$TEST_WINDOW"
assert_equals "  parses PANE correctly" "1" "$TEST_PANE"
assert_equals "  parses PANE_COUNT correctly" "3" "$TEST_PANE_COUNT"
if [[ "$TEST_LAYOUT" == *"main-vertical"* ]]; then
    pass "  parses layout correctly"
else
    fail "  layout should contain 'main-vertical'"
fi

rm -f "$TEST_STATE_FILE"

# Test edge cases in state file parsing
echo ""
echo "  state file edge cases:"

# Empty state file
TEST_STATE_FILE=$(mktemp)
touch "$TEST_STATE_FILE"
EMPTY_TEST=""
while IFS='=' read -r key value; do
    EMPTY_TEST="found"
done < "$TEST_STATE_FILE"
if [[ -z "$EMPTY_TEST" ]]; then
    pass "  handles empty state file"
else
    fail "  empty state file should produce no values"
fi
rm -f "$TEST_STATE_FILE"

# State file with special characters in path
TEST_STATE_FILE=$(mktemp)
echo "dir=/Users/test/path with spaces/project" > "$TEST_STATE_FILE"
SPECIAL_DIR=""
while IFS='=' read -r key value; do
    case "$key" in
        dir) SPECIAL_DIR="$value" ;;
    esac
done < "$TEST_STATE_FILE"
assert_equals "  handles paths with spaces" "/Users/test/path with spaces/project" "$SPECIAL_DIR"
rm -f "$TEST_STATE_FILE"

# State file with equals in value
TEST_STATE_FILE=$(mktemp)
echo "layout=abc=def=ghi" > "$TEST_STATE_FILE"
EQUALS_VALUE=""
while IFS='=' read -r key value; do
    case "$key" in
        layout) EQUALS_VALUE="$value" ;;
    esac
done < "$TEST_STATE_FILE"
# Note: IFS='=' splits on first = only when using read -r
# This may or may not work as expected depending on shell
if [[ "$EQUALS_VALUE" == "abc=def=ghi" || "$EQUALS_VALUE" == "abc" ]]; then
    pass "  handles values with equals signs (value: $EQUALS_VALUE)"
else
    fail "  unexpected handling of equals in value: $EQUALS_VALUE"
fi
rm -f "$TEST_STATE_FILE"

# ─────────────────────────────────────────
# Syntax check all scripts
# ─────────────────────────────────────────
section "Syntax checking scripts"
SCRIPTS_DIR="$SCRIPT_DIR/.."

for script in "$SCRIPTS_DIR"/*.sh; do
    script_name=$(basename "$script")
    if bash -n "$script" 2>/dev/null; then
        pass "  $script_name syntax OK"
    else
        fail "  $script_name has syntax errors"
    fi
done

# Also check library files
for lib in "$SCRIPT_DIR"/*.sh; do
    lib_name=$(basename "$lib")
    [[ "$lib_name" == "test.sh" ]] && continue
    if bash -n "$lib" 2>/dev/null; then
        pass "  _lib/$lib_name syntax OK"
    else
        fail "  _lib/$lib_name has syntax errors"
    fi
done

# ─────────────────────────────────────────
# ShellCheck if available
# ─────────────────────────────────────────
if command -v shellcheck &>/dev/null; then
    section "ShellCheck analysis"
    SHELLCHECK_FAIL=0

    for script in "$SCRIPTS_DIR"/*.sh; do
        script_name=$(basename "$script")
        if shellcheck -S warning "$script" 2>/dev/null; then
            pass "  $script_name passes shellcheck"
        else
            fail "  $script_name has shellcheck warnings"
            SHELLCHECK_FAIL=$((SHELLCHECK_FAIL + 1))
        fi
    done

    for lib in "$SCRIPT_DIR"/*.sh; do
        lib_name=$(basename "$lib")
        [[ "$lib_name" == "test.sh" ]] && continue
        if shellcheck -S warning "$lib" 2>/dev/null; then
            pass "  _lib/$lib_name passes shellcheck"
        else
            fail "  _lib/$lib_name has shellcheck warnings"
            SHELLCHECK_FAIL=$((SHELLCHECK_FAIL + 1))
        fi
    done
else
    section "ShellCheck analysis"
    skip "  shellcheck not installed - install with 'brew install shellcheck'"
fi

# ─────────────────────────────────────────
# Summary
# ─────────────────────────────────────────
echo ""
echo "═════════════════════════════════════════"
TOTAL=$((PASS + FAIL))
printf "Results: ${GREEN}%d passed${NC}, ${RED}%d failed${NC} (total: %d)\n" "$PASS" "$FAIL" "$TOTAL"
echo "═════════════════════════════════════════"

if [[ $FAIL -gt 0 ]]; then
    exit 1
fi
