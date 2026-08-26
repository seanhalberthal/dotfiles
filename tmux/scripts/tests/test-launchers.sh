#!/usr/bin/env bash
set -euo pipefail

# unit tests for launcher management scripts:
#   - launchers/list.sh (output format, launcher discovery, dedup)
#   - launchers/run.sh (get_base_session_name, is_fixed_session, metadata)
#   - launchers/delete.sh (repo protection, path traversal guard)
#   - launchers/new.sh (name validation)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOTFILES_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
LIST_LAUNCHERS="$SCRIPT_DIR/../launchers/list.sh"
RUN_LAUNCHER="$SCRIPT_DIR/../launchers/run.sh"
DELETE_LAUNCHER="$SCRIPT_DIR/../launchers/delete.sh"
NEW_LAUNCHER="$SCRIPT_DIR/../launchers/new.sh"

source "$SCRIPT_DIR/_test-helpers.sh"

# ===========================================================================
# launchers/list.sh tests
# ===========================================================================

section "launchers/list.sh: Script Exists and Is Executable"

if [[ -f "$LIST_LAUNCHERS" ]]; then
    pass "launchers/list.sh exists"
else
    fail "launchers/list.sh not found at $LIST_LAUNCHERS"
    exit 1
fi

if [[ -x "$LIST_LAUNCHERS" ]]; then
    pass "launchers/list.sh is executable"
else
    fail "launchers/list.sh is not executable"
fi

section "launchers/list.sh: Shebang"

shebang=$(head -1 "$LIST_LAUNCHERS")
if [[ "$shebang" == "#!/usr/bin/env bash" ]]; then
    pass "uses portable shebang (#!/usr/bin/env bash)"
else
    fail "should use #!/usr/bin/env bash, got: $shebang"
fi

section "launchers/list.sh: ShellCheck Validation"

if command -v shellcheck &>/dev/null; then
    if shellcheck -x -e SC1091 -e SC2059 -e SC2155 -e SC2015 -e SC2016 -e SC2034 "$LIST_LAUNCHERS" 2>/dev/null; then
        pass "launchers/list.sh passes shellcheck"
    else
        fail "launchers/list.sh has shellcheck warnings"
    fi
else
    skip "shellcheck not installed"
fi

section "launchers/list.sh: Sources common.sh (no find_dotfiles_root duplication)"

list_content=$(cat "$LIST_LAUNCHERS")

if [[ "$list_content" == *'source "$SCRIPT_DIR/../_lib/common.sh"'* ]]; then
    pass "sources common.sh library"
else
    fail "should source common.sh library"
fi

if [[ "$list_content" == *"find_dotfiles_root"* ]]; then
    fail "should NOT contain find_dotfiles_root (use common.sh instead)"
else
    pass "no find_dotfiles_root duplication"
fi

section "launchers/list.sh: Output Format"

output=$("$LIST_LAUNCHERS" 2>&1) || true

# should have dotfiles ASCII art logo in header
if [[ "$output" == *'__| | ___ | |_'* ]]; then
    pass "output includes dotfiles logo header"
else
    fail "output should include dotfiles logo header"
fi

# should list repo launchers (dev has @description)
if [[ "$output" == *"dev"* ]]; then
    pass "output lists dev launcher"
else
    fail "output should list dev launcher (has @description tag)"
fi

# should show description from @description tag
if [[ "$output" == *"Dev session"* ]]; then
    pass "output shows dev description"
else
    fail "output should show dev @description text"
fi

# code launcher has no @description, should be hidden
if [[ "$output" != *"VS Code"* ]]; then
    pass "launchers without @description are hidden (code)"
else
    fail "launchers without @description should be hidden"
fi

# template should be excluded
if [[ "$output" != *"launcher.template"* ]]; then
    pass "template file is excluded from listing"
else
    fail "launcher.template should be excluded from listing"
fi

section "launchers/list.sh: Launcher Dedup (user overrides repo)"

# create temporary user launcher dir with a duplicate name
TEST_XDG=$(mktemp -d)
TEST_USER_DIR="$TEST_XDG/dotfiles/launchers"
mkdir -p "$TEST_USER_DIR"
cat >"$TEST_USER_DIR/dev" <<'TESTEOF'
#!/usr/bin/env bash
# @description: User override of dev
echo "user dev"
TESTEOF
chmod +x "$TEST_USER_DIR/dev"

dedup_output=$(XDG_CONFIG_HOME="$TEST_XDG" "$LIST_LAUNCHERS" 2>&1) || true
# strip ANSI for counting
plain_dedup=$(printf '%s' "$dedup_output" | sed 's/\x1b\[[0-9;]*m//g')
dev_count=$(printf '%s' "$plain_dedup" | grep -c 'dev' || true)

if [[ "$dev_count" -eq 1 ]]; then
    pass "dedup: dev appears exactly once when user overrides repo"
else
    fail "dedup: dev should appear once, got $dev_count times"
fi

# user version description should win
if [[ "$dedup_output" == *"User override"* ]]; then
    pass "dedup: user launcher description takes priority"
else
    fail "dedup: user launcher description should override repo"
fi

rm -rf "$TEST_XDG"

section "launchers/list.sh: Performance Guardrails"

if grep -q "mktemp -d" "$LIST_LAUNCHERS"; then
    fail "launchers/list.sh should avoid temp-dir churn on hot path"
else
    pass "launchers/list.sh avoids temp-dir churn"
fi

if grep -q "grep -m1 '# @description:'" "$LIST_LAUNCHERS"; then
    fail "launchers/list.sh should not fork grep for each launcher description"
else
    pass "launchers/list.sh parses descriptions without per-file grep"
fi

# ===========================================================================
# launchers/run.sh tests (pure function logic)
# ===========================================================================

section "launchers/run.sh: Script Exists and Is Executable"

if [[ -f "$RUN_LAUNCHER" ]]; then
    pass "launchers/run.sh exists"
else
    fail "launchers/run.sh not found"
fi

if [[ -x "$RUN_LAUNCHER" ]]; then
    pass "launchers/run.sh is executable"
else
    fail "launchers/run.sh is not executable"
fi

section "launchers/run.sh: ShellCheck Validation"

if command -v shellcheck &>/dev/null; then
    if shellcheck -x -e SC1091 -e SC2059 -e SC2155 -e SC2015 -e SC2016 -e SC2034 "$RUN_LAUNCHER" 2>/dev/null; then
        pass "launchers/run.sh passes shellcheck"
    else
        fail "launchers/run.sh has shellcheck warnings"
    fi
else
    skip "shellcheck not installed"
fi

section "launchers/run.sh: get_base_session_name() Regex Parsing"

# source launchers/run.sh functions by extracting and testing them
# we can't source the whole file (it has side effects), so test via grep/pattern
run_content=$(cat "$RUN_LAUNCHER")

# verify function exists
if [[ "$run_content" == *"get_base_session_name()"* ]]; then
    pass "get_base_session_name function exists"
else
    fail "get_base_session_name function should exist"
fi

# test the regex patterns by creating a mini test harness
test_base_session() {
    local input="$1"
    local expected="$2"
    local desc="$3"

    # replicate the function's logic
    local val="$input"
    local result
    if [[ "$val" =~ :-([^}]+)\} ]]; then
        result="${BASH_REMATCH[1]}"
    else
        # shellcheck disable=SC2016
        result=$(printf '%s' "$val" | tr -d '${}')
    fi

    if [[ "$result" == "$expected" ]]; then
        pass "get_base_session_name: $desc"
    else
        fail "get_base_session_name: $desc (expected '$expected', got '$result')"
    fi
}

# plain session name
test_base_session "myproject" "myproject" "plain value 'myproject'"

# ${SESSION_NAME:-default} pattern
test_base_session '${SESSION_NAME:-acme}' "acme" '${SESSION_NAME:-acme} extracts default'

# complex default with dashes
test_base_session '${SESSION_NAME:-my-app}' "my-app" '${SESSION_NAME:-my-app} preserves dashes'

section "launchers/run.sh: is_fixed_session() Detection"

# is_fixed_session returns true when session_value is non-empty
if [[ "$run_content" == *"is_fixed_session()"* ]]; then
    pass "is_fixed_session function exists"
else
    fail "is_fixed_session function should exist"
fi

# dev has no SESSION= line, should be detected as parameterised
if grep -q '^SESSION=' "$DOTFILES_ROOT/launchers/dev"; then
    fail "dev should NOT have a SESSION= line (it's parameterised)"
else
    pass "dev correctly has no SESSION= line (parameterised launcher)"
fi

# launcher.template has SESSION=, should be detected as fixed
if grep -q '^SESSION=' "$DOTFILES_ROOT/launchers/launcher.template"; then
    pass "launcher.template has SESSION= line (fixed launcher)"
else
    fail "launcher.template should have a SESSION= line"
fi

section "launchers/run.sh: Metadata Extraction"

# verify @description extraction pattern
if [[ "$run_content" == *'# @description:'* ]]; then
    pass "extracts @description metadata"
else
    fail "should extract @description metadata"
fi

# verify @instance extraction pattern
if [[ "$run_content" == *'# @instance:'* ]]; then
    pass "extracts @instance metadata"
else
    fail "should extract @instance metadata"
fi

section "launchers/run.sh: Input Sanitisation"

# check that fzf become() commands sanitise user input
if [[ "$run_content" == *"tr -c '[:alnum:]_-' '-'"* ]]; then
    pass "sanitises suffix input in become() command (dots excluded)"
else
    fail "should sanitise suffix with tr in become() command (dots excluded)"
fi

if [[ "$run_content" == *"new-dir.sh"* ]]; then
    pass "delegates new directory creation to new-dir.sh"
else
    fail "should delegate new directory creation to new-dir.sh"
fi

section "launchers/run.sh: DOTFILES_ROOT Validation"

if [[ "$run_content" == *'DOTFILES_ROOT'*'invalid'* ]] || [[ "$run_content" == *'-z "${DOTFILES_ROOT'* ]]; then
    pass "validates DOTFILES_ROOT after sourcing common.sh"
else
    fail "should validate DOTFILES_ROOT is set and valid"
fi

section "launchers/run.sh: fzf Dependency Check"

if [[ "$run_content" == *"require_fzf"* ]]; then
    pass "checks for fzf availability"
else
    fail "should check for fzf availability"
fi

# ===========================================================================
# launchers/delete.sh tests
# ===========================================================================

section "launchers/delete.sh: Script Exists and Is Executable"

if [[ -f "$DELETE_LAUNCHER" ]]; then
    pass "launchers/delete.sh exists"
else
    fail "launchers/delete.sh not found"
fi

if [[ -x "$DELETE_LAUNCHER" ]]; then
    pass "launchers/delete.sh is executable"
else
    fail "launchers/delete.sh is not executable"
fi

section "launchers/delete.sh: ShellCheck Validation"

if command -v shellcheck &>/dev/null; then
    if shellcheck -x -e SC1091 -e SC2059 -e SC2155 -e SC2015 -e SC2016 -e SC2034 "$DELETE_LAUNCHER" 2>/dev/null; then
        pass "launchers/delete.sh passes shellcheck"
    else
        fail "launchers/delete.sh has shellcheck warnings"
    fi
else
    skip "shellcheck not installed"
fi

section "launchers/delete.sh: Path Traversal Protection"

del_content=$(cat "$DELETE_LAUNCHER")

if [[ "$del_content" == *"basename"* ]]; then
    pass "uses basename to strip path separators"
else
    fail "should use basename to prevent path traversal"
fi

# check for dot/dotdot rejection
if [[ "$del_content" == *'".."'* ]] || [[ "$del_content" == *'"."'* ]]; then
    pass "rejects . and .. as launcher names"
else
    fail "should reject . and .. as launcher names"
fi

section "launchers/delete.sh: Repo Launcher Protection"

if [[ "$del_content" == *"Cannot delete repo launcher"* ]]; then
    pass "protects repo launchers from deletion"
else
    fail "should prevent deletion of repo launchers"
fi

if [[ "$del_content" == *"show_visual_confirm"* ]]; then
    pass "shows confirmation dialog before deleting"
else
    fail "should show confirmation before deleting"
fi

# ===========================================================================
# launchers/new.sh tests (name validation)
# ===========================================================================

section "launchers/new.sh: Script Exists and Is Executable"

if [[ -f "$NEW_LAUNCHER" ]]; then
    pass "launchers/new.sh exists"
else
    fail "launchers/new.sh not found"
fi

if [[ -x "$NEW_LAUNCHER" ]]; then
    pass "launchers/new.sh is executable"
else
    fail "launchers/new.sh is not executable"
fi

section "launchers/new.sh: ShellCheck Validation"

if command -v shellcheck &>/dev/null; then
    if shellcheck -x -e SC1091 -e SC2059 -e SC2155 -e SC2015 -e SC2016 -e SC2034 "$NEW_LAUNCHER" 2>/dev/null; then
        pass "launchers/new.sh passes shellcheck"
    else
        fail "launchers/new.sh has shellcheck warnings"
    fi
else
    skip "shellcheck not installed"
fi

section "launchers/new.sh: Name Validation"

nl_content=$(cat "$NEW_LAUNCHER")

# sanitise_launcher_name lives in tmux/scripts/_lib/common.sh
COMMON_LIB="$DOTFILES_ROOT/tmux/scripts/_lib/common.sh"
common_lib_content=$(cat "$COMMON_LIB")

# launchers/new.sh should call sanitise_launcher_name (from common.sh)
if [[ "$nl_content" == *"sanitise_launcher_name"* ]]; then
    pass "calls sanitise_launcher_name from shared library"
else
    fail "should call sanitise_launcher_name from shared library"
fi

# should sanitise special characters
if [[ "$common_lib_content" == *"tr -c '[:alnum:]_.-' '-'"* ]] || [[ "$common_lib_content" == *"tr -c '[:alnum:]_-' '-'"* ]]; then
    pass "sanitises special characters in launcher names"
else
    fail "should sanitise special characters in launcher names"
fi

# should lowercase names
if [[ "$common_lib_content" == *"tr '[:upper:]' '[:lower:]'"* ]]; then
    pass "lowercases launcher names"
else
    fail "should lowercase launcher names"
fi

# should strip leading dots/dashes
if [[ "$common_lib_content" == *'strip leading dots/dashes'* ]] || [[ "$common_lib_content" == *'%%[[:alnum:]_]'* ]]; then
    pass "strips leading dots/dashes from names"
else
    fail "should strip leading dots/dashes from names"
fi

# should enforce length limit
if [[ "$common_lib_content" == *':0:64'* ]] || [[ "$common_lib_content" == *'{name:0:64}'* ]]; then
    pass "enforces 64-character name length limit"
else
    fail "should enforce 64-character name length limit"
fi

# should block shell reserved words
if [[ "$common_lib_content" == *"test|cd|ls"* ]] || [[ "$common_lib_content" == *"test | cd | ls"* ]]; then
    pass "blocks shell reserved words as launcher names"
else
    fail "should block shell reserved words (test, cd, ls, etc.)"
fi

section "launchers/new.sh: Window Count Cap"

if [[ "$nl_content" == *"-gt 20"* ]]; then
    pass "caps maximum window count at 20"
else
    fail "should cap window count at 20"
fi

section "launchers/new.sh: Single-Quote Escaping in Generated Scripts"

if [[ "$nl_content" == *"wcmd=\"\${wcmd//\\'/"* ]] || [[ "$nl_content" == *"Escape single quotes"* ]]; then
    pass "escapes single quotes in generated send-keys commands"
else
    fail "should escape single quotes in user commands for generated scripts"
fi

section "launchers/new.sh: Tmux Exact-Match Session Targets"

# regression guard: the wizard template must emit `=$SESSION` for tmux
# session targets. bare `"$SESSION"` triggers tmux's prefix-matching,
# so launching "foo-15" would silently re-attach to a running "foo-1533"
# instead of creating a new session
if [[ "$nl_content" == *'tmux has-session -t "=$SESSION"'* ]]; then
    pass "generated has-session uses exact-match (=\$SESSION)"
else
    fail "generated has-session should use =\$SESSION (prefix-match bug)"
fi

if [[ "$nl_content" == *'tmux switch-client -t "=$SESSION"'* ]]; then
    pass "generated switch-client uses exact-match (=\$SESSION)"
else
    fail "generated switch-client should use =\$SESSION (prefix-match bug)"
fi

if [[ "$nl_content" == *'tmux attach-session -t "=$SESSION"'* ]]; then
    pass "generated attach-session uses exact-match (=\$SESSION)"
else
    fail "generated attach-session should use =\$SESSION (prefix-match bug)"
fi

# same guard for the shared `dev` launcher (uses lowercase $session)
dev_launcher="$DOTFILES_ROOT/launchers/dev"
if [[ -f "$dev_launcher" ]]; then
    dev_content=$(cat "$dev_launcher")
    if [[ "$dev_content" == *'tmux has-session -t "=$session"'* ]] &&
        [[ "$dev_content" == *'tmux switch-client -t "=$session"'* ]] &&
        [[ "$dev_content" == *'tmux attach-session -t "=$session"'* ]]; then
        pass "launchers/dev uses exact-match for all tmux session targets"
    else
        fail "launchers/dev should use =\$session for all tmux session targets"
    fi
else
    skip "launchers/dev not found"
fi

section "launchers/new.sh: exec < /dev/tty Documentation"

if [[ "$nl_content" == *"Security note"* ]] || [[ "$nl_content" == *"controlling terminal"* ]]; then
    pass "documents exec < /dev/tty security implications"
else
    fail "should document exec < /dev/tty security implications"
fi

# ===========================================================================
# Shared library: launcher path constants
# ===========================================================================

section "Shared Library: Launcher Path Constants"

common_content=$(cat "$DOTFILES_ROOT/tmux/scripts/_lib/common.sh")

if [[ "$common_content" == *"USER_LAUNCHERS="* ]]; then
    pass "common.sh defines USER_LAUNCHERS constant"
else
    fail "common.sh should define USER_LAUNCHERS constant"
fi

if [[ "$common_content" == *"DOTFILES_LAUNCHERS="* ]]; then
    pass "common.sh defines DOTFILES_LAUNCHERS constant"
else
    fail "common.sh should define DOTFILES_LAUNCHERS constant"
fi

if [[ "$common_content" == *"require_fzf()"* ]]; then
    pass "common.sh defines require_fzf helper"
else
    fail "common.sh should define require_fzf helper"
fi

# ===========================================================================
# launchers/list.sh: Tab-delimited format (name weighting for fzf)
# ===========================================================================

section "launchers/list.sh: Tab-Delimited Output Format"

list_output=$("$LIST_LAUNCHERS" 2>&1) || true

# strip header lines (7 logo lines), then check data lines
data_lines=$(printf '%s\n' "$list_output" | tail -n +8)

if [[ -n "$data_lines" ]]; then
    # every data line should contain a tab separator
    bad_lines=0
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        if [[ "$line" != *$'\t'* ]]; then
            bad_lines=$((bad_lines + 1))
        fi
    done <<<"$data_lines"

    if [[ $bad_lines -eq 0 ]]; then
        pass "all data lines contain tab delimiter"
    else
        fail "$bad_lines data line(s) missing tab delimiter"
    fi

    # field 1 (before tab) should be the launcher name, field 2 should also contain it
    first_line=$(printf '%s\n' "$data_lines" | head -1)
    field1=$(printf '%s' "$first_line" | cut -d$'\t' -f1)
    field2=$(printf '%s' "$first_line" | cut -d$'\t' -f2-)

    if [[ -n "$field1" ]] && [[ "$field2" == *"$field1"* ]]; then
        pass "hidden field 1 name appears in display field 2"
    else
        fail "field 1 ('$field1') should appear in field 2 for name weighting"
    fi
else
    fail "no data lines found in list output"
fi

# header lines should also have tab prefix (for --with-nth=2 compatibility)
header_lines=$(printf '%s\n' "$list_output" | head -7)
header_has_tabs=true
while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    if [[ "$line" != $'\t'* ]]; then
        header_has_tabs=false
        break
    fi
done <<<"$header_lines"

if [[ "$header_has_tabs" == true ]]; then
    pass "header lines have tab prefix for --with-nth=2 compatibility"
else
    fail "header lines should have tab prefix for --with-nth=2"
fi

section "launchers/picker.sh: Name Weighting Configuration"

picker_content=$(cat "$SCRIPT_DIR/../launchers/picker.sh")

if [[ "$picker_content" == *"--with-nth=2"* ]]; then
    pass "picker uses --with-nth=2 to hide name weight field"
else
    fail "picker should use --with-nth=2 to hide name weight field"
fi

if [[ "$picker_content" == *"--tiebreak=begin"* ]]; then
    pass "picker uses --tiebreak=begin to prefer name matches"
else
    fail "picker should use --tiebreak=begin to prefer name matches"
fi

# ===========================================================================
# launchers/duplicate.sh tests
# ===========================================================================

DUPLICATE_LAUNCHER="$SCRIPT_DIR/../launchers/duplicate.sh"

section "launchers/duplicate.sh: Script Exists and Is Executable"

if [[ -f "$DUPLICATE_LAUNCHER" ]]; then
    pass "launchers/duplicate.sh exists"
else
    fail "launchers/duplicate.sh not found"
fi

if [[ -x "$DUPLICATE_LAUNCHER" ]]; then
    pass "launchers/duplicate.sh is executable"
else
    fail "launchers/duplicate.sh is not executable"
fi

section "launchers/duplicate.sh: ShellCheck Validation"

if command -v shellcheck &>/dev/null; then
    if shellcheck -x -e SC1091 -e SC2059 -e SC2155 -e SC2015 -e SC2016 -e SC2034 "$DUPLICATE_LAUNCHER" 2>/dev/null; then
        pass "launchers/duplicate.sh passes shellcheck"
    else
        fail "launchers/duplicate.sh has shellcheck warnings"
    fi
else
    skip "shellcheck not installed"
fi

section "launchers/duplicate.sh: Path Traversal Protection"

dup_content=$(cat "$DUPLICATE_LAUNCHER")

if [[ "$dup_content" == *"basename"* ]]; then
    pass "uses basename to strip path separators"
else
    fail "should use basename to prevent path traversal"
fi

if [[ "$dup_content" == *'".."'* ]] || [[ "$dup_content" == *'"."'* ]]; then
    pass "rejects . and .. as launcher names"
else
    fail "should reject . and .. as launcher names"
fi

section "launchers/duplicate.sh: Copy Naming Logic"

if [[ "$dup_content" == *"-copy"* ]]; then
    pass "uses -copy suffix for duplicates"
else
    fail "should use -copy suffix for duplicates"
fi

# Should handle successive copies (-copy-2, -copy-3, ...)
if [[ "$dup_content" == *"-copy-\${n}"* ]] || [[ "$dup_content" == *'copy-${n}'* ]]; then
    pass "auto-increments copy suffix (-copy-2, -copy-3, ...)"
else
    fail "should auto-increment copy suffix"
fi

# Should strip existing -copy suffix before generating new one
if [[ "$dup_content" == *"-copy"*"sed"* ]] || [[ "$dup_content" == *"s/-copy"* ]]; then
    pass "strips existing -copy suffix before renumbering"
else
    fail "should strip existing -copy suffix to avoid name-copy-copy"
fi

section "launchers/duplicate.sh: Description Update"

if [[ "$dup_content" == *"Copy of"* ]]; then
    pass "updates @description to indicate copy"
else
    fail "should update @description to 'Copy of <name>'"
fi

section "launchers/duplicate.sh: Functional Test"

# create a temporary launcher to duplicate
TEST_XDG=$(mktemp -d)
TEST_USER_DIR="$TEST_XDG/dotfiles/launchers"
mkdir -p "$TEST_USER_DIR"
cat >"$TEST_USER_DIR/test-dup" <<'TESTEOF'
#!/usr/bin/env bash
# @description: Test launcher
echo "test"
TESTEOF
chmod +x "$TEST_USER_DIR/test-dup"

# duplicate it
copy_name=$(XDG_CONFIG_HOME="$TEST_XDG" "$DUPLICATE_LAUNCHER" "test-dup" 2>/dev/null) || true

if [[ "$copy_name" == "test-dup-copy" ]]; then
    pass "first copy gets -copy suffix"
else
    fail "first copy should be 'test-dup-copy', got '$copy_name'"
fi

if [[ -f "$TEST_USER_DIR/test-dup-copy" ]]; then
    pass "copy file was created"
else
    fail "copy file should exist at $TEST_USER_DIR/test-dup-copy"
fi

if [[ -x "$TEST_USER_DIR/test-dup-copy" ]]; then
    pass "copy file is executable"
else
    fail "copy file should be executable"
fi

# check description was updated
if grep -q "Copy of test-dup" "$TEST_USER_DIR/test-dup-copy" 2>/dev/null; then
    pass "copy has updated @description"
else
    fail "copy should have '@description: Copy of test-dup'"
fi

# duplicate again, should get -copy-2
copy_name2=$(XDG_CONFIG_HOME="$TEST_XDG" "$DUPLICATE_LAUNCHER" "test-dup" 2>/dev/null) || true

if [[ "$copy_name2" == "test-dup-copy-2" ]]; then
    pass "second copy gets -copy-2 suffix"
else
    fail "second copy should be 'test-dup-copy-2', got '$copy_name2'"
fi

# duplicate the copy itself, should still base on original name
copy_name3=$(XDG_CONFIG_HOME="$TEST_XDG" "$DUPLICATE_LAUNCHER" "test-dup-copy" 2>/dev/null) || true

if [[ "$copy_name3" == "test-dup-copy-3" ]]; then
    pass "duplicating a copy bases numbering on original name"
else
    fail "duplicating a copy should produce 'test-dup-copy-3', got '$copy_name3'"
fi

# empty name should exit cleanly
empty_result=$(
    XDG_CONFIG_HOME="$TEST_XDG" "$DUPLICATE_LAUNCHER" "" 2>/dev/null
    echo "exit:$?"
) || true
if [[ "$empty_result" == *"exit:0"* ]]; then
    pass "empty name exits cleanly"
else
    fail "empty name should exit 0"
fi

rm -rf "$TEST_XDG"

# ===========================================================================
# Summary
# ===========================================================================

print_summary
[[ $FAIL -gt 0 ]] && exit 1
exit 0
