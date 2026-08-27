#!/usr/bin/env bash
set -euo pipefail

# tests for ghdash_merge_local() from scripts/_lib/ghdash.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOTFILES_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

# source shared test helpers (colours, pass/fail/skip/section, assertions, sandbox)
source "$SCRIPT_DIR/_test-helpers.sh"

setup_sandbox
trap cleanup_sandbox EXIT

# source ghdash library (sets GHDASH_BASE, GHDASH_CONFIG, GHDASH_LOCAL)
source "$DOTFILES_DIR/scripts/_lib/common.sh"
source "$DOTFILES_DIR/scripts/_lib/ghdash.sh"

# ===========================================================================
# Tests
# ===========================================================================

section "ghdash merge — yq availability"

if ! command -v yq &>/dev/null; then
    skip "yq not installed — skipping merge tests"
    print_summary
    exit 0
fi

pass "yq is available"

section "ghdash merge — with local overrides"

# override module-level paths to use sandbox
GHDASH_DIR="$TEST_HOME/.config/gh-dash"
mkdir -p "$GHDASH_DIR"

GHDASH_BASE="$GHDASH_DIR/config.base.yml"
GHDASH_CONFIG="$GHDASH_DIR/config.yml"
GHDASH_LOCAL="$GHDASH_DIR/local.yml"

# test 1: merge with both base and local present
cat >"$GHDASH_BASE" <<'EOF'
prSections:
  - title: My PRs
    filters: author:@me
theme:
  colors:
    text: "#d4d4d4"
EOF

cat >"$GHDASH_LOCAL" <<'EOF'
prSections:
  - title: Team PRs
    filters: org:myorg
EOF

ghdash_merge_local --quiet

# *+ merge appends arrays, so local entries are added after base entries
if yq '.prSections[] | .title' "$GHDASH_CONFIG" 2>/dev/null | grep -q "Team PRs"; then
    pass "local.yml entries merged into base config"
else
    fail "local.yml entries not found in merged config"
fi

# verify base entries are also preserved
if yq '.prSections[] | .title' "$GHDASH_CONFIG" 2>/dev/null | grep -q "My PRs"; then
    pass "base config entries preserved after merge"
else
    fail "base config entries lost after merge"
fi

section "ghdash merge — missing local.yml"

# test 2: no local.yml, base should be promoted to config
cat >"$GHDASH_BASE" <<'EOF'
prSections:
  - title: My PRs
EOF
rm -f "$GHDASH_LOCAL"

ghdash_merge_local --quiet

if yq '.prSections[0].title' "$GHDASH_CONFIG" 2>/dev/null | grep -q "My PRs"; then
    pass "missing local.yml preserves base config"
else
    fail "base config was corrupted when local.yml absent"
fi

section "ghdash merge — empty local.yml"

# test 3: empty local.yml, base should be preserved
cat >"$GHDASH_BASE" <<'EOF'
prSections:
  - title: My PRs
EOF
touch "$GHDASH_LOCAL"

ghdash_merge_local --quiet

if yq '.prSections[0].title' "$GHDASH_CONFIG" 2>/dev/null | grep -q "My PRs"; then
    pass "empty local.yml preserves base config"
else
    fail "base config was corrupted with empty local.yml"
fi

section "ghdash merge — no base config"

# test 4: no base config, should return 0 and do nothing
rm -f "$GHDASH_BASE" "$GHDASH_CONFIG" "$GHDASH_LOCAL"

if ghdash_merge_local --quiet; then
    pass "no base config returns success (no-op)"
else
    fail "no base config should return 0"
fi

# ===========================================================================
# Summary
# ===========================================================================

print_summary
[[ $FAIL -gt 0 ]] && exit 1
exit 0
