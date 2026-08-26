#!/usr/bin/env bash
set -euo pipefail

# tests for migration version comparison and state tracking logic
# tests the _version_gt function and migration filtering/tracking behaviour

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# source shared test helpers
source "$SCRIPT_DIR/_test-helpers.sh"

# source _version_gt from cli.sh (it moved out of scripts/dotfiles).
# extract the function definition directly so we don't have to satisfy the
# library's load-guard preconditions (DOTFILES_DIR, common.sh, colour vars)
eval "$(sed -n '/^_version_gt()/,/^}/p' "$DOTFILES_ROOT/scripts/_lib/cli.sh")"

# ═══════════════════════════════════════════════════════════════
# _version_gt Tests
# ═══════════════════════════════════════════════════════════════

section "_version_gt - basic comparisons"

if _version_gt "0.2.60" "0.2.59"; then
    pass "0.2.60 > 0.2.59"
else
    fail "0.2.60 should be greater than 0.2.59"
fi

if ! _version_gt "0.2.59" "0.2.60"; then
    pass "0.2.59 is not > 0.2.60"
else
    fail "0.2.59 should not be greater than 0.2.60"
fi

if ! _version_gt "0.2.60" "0.2.60"; then
    pass "0.2.60 is not > 0.2.60 (equal)"
else
    fail "Equal versions should not be greater"
fi

section "_version_gt - edge cases"

if _version_gt "1.0.0" "0.99.99"; then
    pass "1.0.0 > 0.99.99 (major bump)"
else
    fail "1.0.0 should be greater than 0.99.99"
fi

if _version_gt "0.3.0" "0.2.99"; then
    pass "0.3.0 > 0.2.99 (minor bump)"
else
    fail "0.3.0 should be greater than 0.2.99"
fi

if _version_gt "0.2.100" "0.2.99"; then
    pass "0.2.100 > 0.2.99 (triple-digit patch)"
else
    fail "0.2.100 should be greater than 0.2.99"
fi

# ═══════════════════════════════════════════════════════════════
# Migration Filtering Tests (version range logic)
# ═══════════════════════════════════════════════════════════════

section "Migration version range filtering"

# simulate the migration filtering logic from _run_pending_migrations
# range: (old_version, new_version], exclusive start, inclusive end
_in_migration_range() {
    local migration_version="$1" old_version="$2" new_version="$3"
    _version_gt "$migration_version" "$old_version" &&
        ! _version_gt "$migration_version" "$new_version"
}

# upgrading from 0.2.56 to 0.2.60
if _in_migration_range "0.2.57" "0.2.56" "0.2.60"; then
    pass "0.2.57 is in range (0.2.56, 0.2.60]"
else
    fail "0.2.57 should be in range"
fi

if _in_migration_range "0.2.60" "0.2.56" "0.2.60"; then
    pass "0.2.60 is in range (0.2.56, 0.2.60] (inclusive end)"
else
    fail "0.2.60 should be in range (inclusive end)"
fi

if ! _in_migration_range "0.2.56" "0.2.56" "0.2.60"; then
    pass "0.2.56 is not in range (0.2.56, 0.2.60] (exclusive start)"
else
    fail "0.2.56 should not be in range (exclusive start)"
fi

if ! _in_migration_range "0.2.61" "0.2.56" "0.2.60"; then
    pass "0.2.61 is not in range (0.2.56, 0.2.60]"
else
    fail "0.2.61 should not be in range"
fi

if ! _in_migration_range "0.2.55" "0.2.56" "0.2.60"; then
    pass "0.2.55 is not in range (0.2.56, 0.2.60]"
else
    fail "0.2.55 should not be in range"
fi

# ═══════════════════════════════════════════════════════════════
# Applied Migration State Tracking Tests
# ═══════════════════════════════════════════════════════════════

section "Applied migration state tracking"

setup_sandbox
state_dir="$TEST_HOME/.config/dotfiles/.state"
mkdir -p "$state_dir"
applied_file="$state_dir/migrations"
touch "$applied_file"

# record a migration as applied
echo "0.2.57-unlink-p10k.sh" >>"$applied_file"

if grep -qxF "0.2.57-unlink-p10k.sh" "$applied_file"; then
    pass "Applied migration is recorded in state file"
else
    fail "Should record applied migration"
fi

# verify already-applied migration is detected
if grep -qxF "0.2.57-unlink-p10k.sh" "$applied_file"; then
    pass "Already-applied migration detected via grep -qxF"
else
    fail "Should detect already-applied migration"
fi

# verify unapplied migration is not detected
if ! grep -qxF "0.2.59-remove-cronboard.sh" "$applied_file"; then
    pass "Unapplied migration not in state file"
else
    fail "Unapplied migration should not be in state file"
fi

# record multiple migrations and verify order
echo "0.2.59-remove-cronboard.sh" >>"$applied_file"
echo "0.2.60-remove-csharpier.sh" >>"$applied_file"

line_count=$(wc -l <"$applied_file" | tr -d ' ')
assert_equals "State file has 3 entries" "3" "$line_count"

cleanup_sandbox

# ═══════════════════════════════════════════════════════════════
# Migration Discovery and Ordering Tests
# ═══════════════════════════════════════════════════════════════

section "Migration discovery and ordering"

setup_sandbox
migrations_dir="$TEST_HOME/migrations"
mkdir -p "$migrations_dir"

# create test migration scripts
echo '#!/bin/bash' >"$migrations_dir/0.2.57-first.sh"
echo '#!/bin/bash' >"$migrations_dir/0.2.59-second.sh"
echo '#!/bin/bash' >"$migrations_dir/0.2.60-third.sh"
chmod +x "$migrations_dir"/*.sh

# verify glob ordering (same logic as _run_pending_migrations)
local_migrations=()
for migration in "$migrations_dir"/*.sh; do
    [[ -f "$migration" ]] || continue
    local_migrations+=("${migration##*/}")
done

assert_equals "Discovers 3 migration scripts" "3" "${#local_migrations[@]}"
assert_equals "First migration is 0.2.57" "0.2.57-first.sh" "${local_migrations[0]}"
assert_equals "Second migration is 0.2.59" "0.2.59-second.sh" "${local_migrations[1]}"
assert_equals "Third migration is 0.2.60" "0.2.60-third.sh" "${local_migrations[2]}"

# test version extraction from filename
basename="0.2.57-unlink-p10k.sh"
migration_version="${basename%%-*}"
assert_equals "Extracts version from filename" "0.2.57" "$migration_version"

basename="0.2.60-remove-csharpier.sh"
migration_version="${basename%%-*}"
assert_equals "Extracts version from multi-word filename" "0.2.60" "$migration_version"

cleanup_sandbox

# ═══════════════════════════════════════════════════════════════
# Migration Idempotency Tests
# ═══════════════════════════════════════════════════════════════

section "Migration idempotency"

setup_sandbox
state_dir="$TEST_HOME/.config/dotfiles/.state"
mkdir -p "$state_dir"
applied_file="$state_dir/migrations"
touch "$applied_file"

# create a migration that creates a file
migrations_dir="$TEST_HOME/migrations"
mkdir -p "$migrations_dir"
cat >"$migrations_dir/0.2.57-test.sh" <<'MIGRATION'
#!/bin/bash
set -euo pipefail
touch "$HOME/migration-ran"
MIGRATION
chmod +x "$migrations_dir/0.2.57-test.sh"

# run it
bash "$migrations_dir/0.2.57-test.sh"
echo "0.2.57-test.sh" >>"$applied_file"

if [[ -f "$TEST_HOME/migration-ran" ]]; then
    pass "Migration creates marker file on first run"
else
    fail "Migration should create marker file"
fi

# simulate skipping (as _run_pending_migrations does)
if grep -qxF "0.2.57-test.sh" "$applied_file"; then
    pass "Already-applied migration would be skipped"
else
    fail "Should detect migration as already applied"
fi

cleanup_sandbox

# ═══════════════════════════════════════════════════════════════
# Summary
# ═══════════════════════════════════════════════════════════════

print_summary

if [[ $FAIL -gt 0 ]]; then
    exit 1
fi
