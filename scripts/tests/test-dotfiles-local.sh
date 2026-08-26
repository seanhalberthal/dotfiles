#!/usr/bin/env bash
set -euo pipefail

# behavioural tests for the local-layer sync commands
# (dotfiles local / export / import)
#
# same style as test-dotfiles-cli.sh: exit codes, output substrings, and
# side effects on a sandbox HOME; no grepping for internal function names

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOTFILES_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

# shellcheck source=scripts/tests/_test-helpers.sh
source "$SCRIPT_DIR/_test-helpers.sh"

# the sandbox derives all config paths from HOME; make sure neither of
# these leaks in from the developer environment
unset XDG_CONFIG_HOME DOTFILES_LOCAL_DIR

echo "==========================================="
echo "Dotfiles Local-Layer Sync Tests"
echo "==========================================="

# write the preset file in the sandbox (default: minimal keeps pairs small)
seed_preset() {
    mkdir -p "$TEST_HOME/.config/dotfiles"
    printf '%s\n' "${1:-minimal}" >"$TEST_HOME/.config/dotfiles/preset"
}

# git identity for commits made inside the sandbox HOME
seed_gitconfig() {
    printf '[user]\n\tname = test\n\temail = test@test\n' >"$TEST_HOME/.gitconfig"
}

# minimal local-layer content for export tests
seed_local_files() {
    printf 'export SANDBOX=1\n' >"$TEST_HOME/.zshrc"
    mkdir -p "$TEST_HOME/.config/tmux" "$TEST_HOME/.config/dotfiles"
    printf 'set -g status off\n' >"$TEST_HOME/.config/tmux/local.conf"
    printf 'dracula\n' >"$TEST_HOME/.config/dotfiles/current-theme"
}

# ─── 1. unconfigured behaviour ────────────────────────────────────────

section "Unconfigured"

setup_cli_sandbox
seed_preset

out=$(dotfiles_run export) && rc=0 || rc=$?
if [[ $rc -ne 0 && "$out" == *"local init"* ]]; then
    pass "export errors with init hint when unconfigured"
else
    fail "export should fail with init hint (rc=$rc)"
fi

out=$(dotfiles_run import) && rc=0 || rc=$?
if [[ $rc -ne 0 && "$out" == *"local init"* ]]; then
    pass "import errors with init hint when unconfigured"
else
    fail "import should fail with init hint (rc=$rc)"
fi

out=$(dotfiles_run local status) && rc=0 || rc=$?
if [[ $rc -eq 0 && "$out" == *"No local repo configured"* ]]; then
    pass "local status is informational when unconfigured"
else
    fail "local status should exit 0 with 'not configured' (rc=$rc)"
fi

out=$(dotfiles_run local diff) && rc=0 || rc=$?
if [[ $rc -ne 0 ]]; then
    pass "local diff errors when unconfigured"
else
    fail "local diff should fail when unconfigured"
fi

cleanup_sandbox

# ─── 2. local init ────────────────────────────────────────────────────

section "local init"

setup_cli_sandbox
seed_preset

out=$(dotfiles_run local init) && rc=0 || rc=$?
if [[ $rc -eq 0 && -d "$TEST_HOME/.dotfiles-local/.git" ]]; then
    pass "init creates a git repo at the default location"
else
    fail "init should create ~/.dotfiles-local (rc=$rc)"
fi

if grep -q "secrets.zsh" "$TEST_HOME/.dotfiles-local/.gitignore" 2>/dev/null; then
    pass "init seeds .gitignore with secrets exclusion"
else
    fail "init should seed .gitignore with secrets.zsh"
fi

if [[ "$(cat "$TEST_HOME/.config/dotfiles/local-repo" 2>/dev/null)" == "$TEST_HOME/.dotfiles-local" ]]; then
    pass "init writes the pointer file"
else
    fail "init should write ~/.config/dotfiles/local-repo"
fi

out=$(dotfiles_run local init) && rc=0 || rc=$?
if [[ $rc -eq 0 && "$out" == *"Already configured"* ]]; then
    pass "init is idempotent"
else
    fail "second init should report already configured (rc=$rc)"
fi

out=$(dotfiles_run local init "git@example.com:me/dotfiles-local.git") && rc=0 || rc=$?
remote=$(git -C "$TEST_HOME/.dotfiles-local" remote get-url origin 2>/dev/null || echo none)
if [[ "$remote" == "git@example.com:me/dotfiles-local.git" ]]; then
    pass "init with url sets origin"
else
    fail "init with url should set origin (got: $remote)"
fi

out=$(dotfiles_run local init "me/dotfiles-local") && rc=0 || rc=$?
remote=$(git -C "$TEST_HOME/.dotfiles-local" remote get-url origin 2>/dev/null || echo none)
if [[ "$remote" == "https://github.com/me/dotfiles-local.git" ]]; then
    pass "init expands owner/repo shorthand to a github https url"
else
    fail "shorthand should expand to https://github.com/me/dotfiles-local.git (got: $remote)"
fi

# an existing local path that happens to look like owner/repo is not expanded
mkdir -p "$TEST_DIR/me/dotfiles-local"
git -C "$TEST_DIR/me/dotfiles-local" init -q
(cd "$TEST_DIR" && dotfiles_run local init "me/dotfiles-local" >/dev/null) || true
remote=$(git -C "$TEST_HOME/.dotfiles-local" remote get-url origin 2>/dev/null || echo none)
if [[ "$remote" == "me/dotfiles-local" ]]; then
    pass "existing local path shaped like owner/repo passes through unexpanded"
else
    fail "existing path must not be rewritten (got: $remote)"
fi

cleanup_sandbox

# ─── 3. local clone ───────────────────────────────────────────────────

section "local clone"

setup_cli_sandbox
seed_preset
seed_gitconfig

# build a source repo and a bare remote to clone from
src="$TEST_DIR/src"
mkdir -p "$src"
git -C "$src" init -q
printf 'export CLONED=1\n' >"$src/zshrc"
git -C "$src" add -A
git -C "$src" commit -q -m "seed"
git clone -q --bare "$src" "$TEST_DIR/remote.git"

# remove the sandbox .zshrc so clone's auto-import can create it
rm -f "$TEST_HOME/.zshrc"

out=$(dotfiles_run local clone "$TEST_DIR/remote.git") && rc=0 || rc=$?
if [[ $rc -eq 0 && -f "$TEST_HOME/.dotfiles-local/zshrc" ]]; then
    pass "clone populates the default location"
else
    fail "clone should populate ~/.dotfiles-local (rc=$rc)"
fi

if grep -q "CLONED=1" "$TEST_HOME/.zshrc" 2>/dev/null; then
    pass "clone applies the layer immediately (auto-import)"
else
    fail "clone should import the layer after registering"
fi

if [[ "$(cat "$TEST_HOME/.config/dotfiles/local-repo" 2>/dev/null)" == "$TEST_HOME/.dotfiles-local" ]]; then
    pass "clone writes the pointer file"
else
    fail "clone should write the pointer file"
fi

out=$(dotfiles_run local clone) && rc=0 || rc=$?
if [[ $rc -ne 0 && "$out" == *"requires a repository url"* ]]; then
    pass "clone without url errors"
else
    fail "clone without url should error (rc=$rc)"
fi

cleanup_sandbox

# ─── 4. export ────────────────────────────────────────────────────────

section "export"

setup_cli_sandbox
seed_preset
seed_gitconfig
seed_local_files
dotfiles_run local init >/dev/null

out=$(dotfiles_run export) && rc=0 || rc=$?
repo="$TEST_HOME/.dotfiles-local"
if [[ $rc -eq 0 && -f "$repo/zshrc" && -f "$repo/config/tmux/local.conf" ]]; then
    pass "export copies files to expected repo paths"
else
    fail "export should copy zshrc/tmux (rc=$rc)"
fi

# theme is a per-machine choice: export must never capture current-theme
if [[ ! -e "$repo/config/dotfiles/current-theme" ]]; then
    pass "export leaves current-theme machine-local"
else
    fail "export must not sync current-theme"
fi

subject=$(git -C "$repo" log -1 --format=%s 2>/dev/null || echo none)
if [[ "$subject" == "export from"* ]]; then
    pass "export commits with 'export from' subject"
else
    fail "export commit subject wrong (got: $subject)"
fi

commits_before=$(git -C "$repo" rev-list --count HEAD)
out=$(dotfiles_run export) && rc=0 || rc=$?
commits_after=$(git -C "$repo" rev-list --count HEAD)
if [[ "$commits_before" == "$commits_after" && "$out" == *"Nothing to export"* ]]; then
    pass "export is idempotent (no empty commit)"
else
    fail "second export should be a no-op"
fi

# hard exclusion: secrets never land in the repo
mkdir -p "$TEST_HOME/.config/zsh"
printf 'export API_KEY=nope\n' >"$TEST_HOME/.config/zsh/secrets.zsh"
dotfiles_run export >/dev/null
if [[ -z "$(find "$repo" -name 'secrets.zsh' -not -path '*/.git/*')" ]]; then
    pass "secrets.zsh is never exported"
else
    fail "secrets.zsh must not appear in the local repo"
fi

# --push to a bare remote
git clone -q --bare "$repo" "$TEST_DIR/remote.git"
git -C "$repo" remote add origin "$TEST_DIR/remote.git"
printf 'set -g mouse on\n' >>"$TEST_HOME/.config/tmux/local.conf"
out=$(dotfiles_run export --push) && rc=0 || rc=$?
local_head=$(git -C "$repo" rev-parse HEAD)
remote_head=$(git -C "$TEST_DIR/remote.git" rev-parse HEAD 2>/dev/null || echo none)
if [[ $rc -eq 0 && "$local_head" == "$remote_head" ]]; then
    pass "export --push updates the remote"
else
    fail "export --push should push HEAD to origin (rc=$rc)"
fi

cleanup_sandbox

# ─── 5. launchers directory export ────────────────────────────────────

section "export: launchers directory"

setup_cli_sandbox
seed_preset core
seed_gitconfig
seed_local_files
mkdir -p "$TEST_HOME/.config/dotfiles/launchers"
printf '#!/usr/bin/env bash\necho hi\n' >"$TEST_HOME/.config/dotfiles/launchers/foo"
touch "$TEST_HOME/.config/dotfiles/launchers/.DS_Store"
dotfiles_run local init >/dev/null
dotfiles_run export >/dev/null

repo="$TEST_HOME/.dotfiles-local"
if [[ -f "$repo/config/dotfiles/launchers/foo" ]]; then
    pass "launcher script exported"
else
    fail "launcher script should be exported"
fi

if [[ ! -e "$repo/config/dotfiles/launchers/.DS_Store" ]]; then
    pass ".DS_Store filtered from directory export"
else
    fail ".DS_Store must not be exported"
fi

rm "$TEST_HOME/.config/dotfiles/launchers/foo"
dotfiles_run export >/dev/null
if git -C "$repo" ls-files | grep -q "launchers/foo"; then
    fail "deleted launcher should be removed from the repo"
else
    pass "system-side deletion propagates on re-export"
fi

cleanup_sandbox

# ─── 5b. launchers directory import prune ─────────────────────────────

section "import: prune launchers removed upstream"

setup_cli_sandbox
seed_preset core
seed_gitconfig
seed_local_files
mkdir -p "$TEST_HOME/.config/dotfiles/launchers"
printf '#!/usr/bin/env bash\necho keep\n' >"$TEST_HOME/.config/dotfiles/launchers/keep"
printf '#!/usr/bin/env bash\necho gone\n' >"$TEST_HOME/.config/dotfiles/launchers/gone"
dotfiles_run local init >/dev/null
dotfiles_run export >/dev/null

repo="$TEST_HOME/.dotfiles-local"
# upstream drops one launcher
rm "$repo/config/dotfiles/launchers/gone"
git -C "$repo" add -A
git -C "$repo" commit -q -m "drop gone launcher"

out=$(dotfiles_run import) && rc=0 || rc=$?
if [[ $rc -eq 0 && "$out" == *"launchers/gone"* && -f "$TEST_HOME/.config/dotfiles/launchers/gone" ]]; then
    pass "import reports the orphan without deleting by default"
else
    fail "default import should report but keep the orphan (rc=$rc)"
fi

# --force overwrites differing files but must never delete orphaned launchers:
# a machine-local launcher looks identical to one removed upstream
out=$(dotfiles_run import --force) && rc=0 || rc=$?
if [[ $rc -eq 0 && -f "$TEST_HOME/.config/dotfiles/launchers/gone" ]]; then
    pass "import --force keeps orphaned launchers (machine-local safe)"
else
    fail "import --force must not prune orphans (rc=$rc)"
fi

out=$(dotfiles_run import --prune) && rc=0 || rc=$?
if [[ $rc -eq 0 && ! -e "$TEST_HOME/.config/dotfiles/launchers/gone" &&
    -f "$TEST_HOME/.config/dotfiles/launchers/keep" ]]; then
    pass "import --prune prunes upstream-removed launchers, keeps tracked ones"
else
    fail "import --prune should delete gone but keep keep (rc=$rc)"
fi

# a system symlink with no repo counterpart survives prune (export never
# captures symlinks, so they are not orphans)
ln -s "$TEST_HOME/.config/dotfiles/launchers/keep" "$TEST_HOME/.config/dotfiles/launchers/linked"
dotfiles_run import --prune >/dev/null
if [[ -L "$TEST_HOME/.config/dotfiles/launchers/linked" ]]; then
    pass "import --prune leaves symlinked launchers untouched"
else
    fail "symlinked launcher must survive prune"
fi

cleanup_sandbox

# ─── 5c. targeted import / export selectors ───────────────────────────

section "targeted export/import selectors"

setup_cli_sandbox
seed_preset core
seed_gitconfig
seed_local_files
mkdir -p "$TEST_HOME/.config/dotfiles/launchers"
printf '#!/usr/bin/env bash\necho acme\n' >"$TEST_HOME/.config/dotfiles/launchers/acme"
printf '#!/usr/bin/env bash\necho beta\n' >"$TEST_HOME/.config/dotfiles/launchers/beta"
dotfiles_run local init >/dev/null

# targeted export captures only the selected file
out=$(dotfiles_run export zshrc) && rc=0 || rc=$?
repo="$TEST_HOME/.dotfiles-local"
if [[ $rc -eq 0 && -f "$repo/zshrc" && ! -e "$repo/config/tmux/local.conf" ]]; then
    pass "export <selector> captures only the matched entry"
else
    fail "targeted export should capture zshrc but not tmux (rc=$rc)"
fi

# targeted export of a single launcher does not pull in the others
out=$(dotfiles_run export launchers/acme) && rc=0 || rc=$?
if [[ $rc -eq 0 && -f "$repo/config/dotfiles/launchers/acme" &&
    ! -e "$repo/config/dotfiles/launchers/beta" ]]; then
    pass "export launchers/<name> captures a single launcher"
else
    fail "targeted launcher export should capture only acme (rc=$rc)"
fi

# unknown selector errors without touching the repo
out=$(dotfiles_run export nope 2>&1) && rc=0 || rc=$?
if [[ $rc -ne 0 && "$out" == *"No local-layer entry matches"* ]]; then
    pass "unknown selector errors"
else
    fail "unknown selector should error (rc=$rc)"
fi

# now capture everything, then diverge system files and import selectively
dotfiles_run export >/dev/null
printf 'export SANDBOX=2\n' >"$TEST_HOME/.zshrc"
printf 'set -g status on\n' >"$TEST_HOME/.config/tmux/local.conf"

# targeted import --force applies only the selected file, leaves the other differing
out=$(dotfiles_run import zshrc --force) && rc=0 || rc=$?
if [[ $rc -eq 0 ]] && grep -q "SANDBOX=1" "$TEST_HOME/.zshrc" &&
    grep -q "status on" "$TEST_HOME/.config/tmux/local.conf"; then
    pass "import <selector> --force applies only the matched entry"
else
    fail "targeted import should overwrite zshrc but not tmux (rc=$rc)"
fi

# targeted single-launcher import never prunes the others even with --prune
rm "$repo/config/dotfiles/launchers/beta"
git -C "$repo" commit -qam "drop beta" 2>/dev/null || true
out=$(dotfiles_run import launchers/acme --prune) && rc=0 || rc=$?
if [[ $rc -eq 0 && -f "$TEST_HOME/.config/dotfiles/launchers/beta" ]]; then
    pass "targeted launcher import does not prune siblings"
else
    fail "single-launcher import must not prune beta (rc=$rc)"
fi

cleanup_sandbox

# ─── 6. import ────────────────────────────────────────────────────────

section "import"

setup_cli_sandbox
seed_preset
seed_gitconfig
seed_local_files
dotfiles_run local init >/dev/null
dotfiles_run export >/dev/null

# create-if-absent
rm "$TEST_HOME/.config/tmux/local.conf"
out=$(dotfiles_run import) && rc=0 || rc=$?
if [[ $rc -eq 0 && "$out" == *"Created"* && -f "$TEST_HOME/.config/tmux/local.conf" ]]; then
    pass "import creates absent files"
else
    fail "import should create absent files (rc=$rc)"
fi

# differing file: skipped without --force, exit 0
printf 'set -g status on\n' >"$TEST_HOME/.config/tmux/local.conf"
out=$(dotfiles_run import) && rc=0 || rc=$?
if [[ $rc -eq 0 && "$out" == *"differs"* ]] && grep -q "status on" "$TEST_HOME/.config/tmux/local.conf"; then
    pass "import leaves differing files alone by default"
else
    fail "import without --force must not overwrite (rc=$rc)"
fi

out=$(dotfiles_run import --force) && rc=0 || rc=$?
if [[ $rc -eq 0 ]] && grep -q "status off" "$TEST_HOME/.config/tmux/local.conf"; then
    pass "import --force overwrites differing files"
else
    fail "import --force should overwrite (rc=$rc)"
fi

# symlinked destination: refused even with --force
rm "$TEST_HOME/.zshrc"
printf 'elsewhere\n' >"$TEST_HOME/other-zshrc"
ln -s "$TEST_HOME/other-zshrc" "$TEST_HOME/.zshrc"
out=$(dotfiles_run import --force) && rc=0 || rc=$?
if [[ $rc -eq 0 && "$out" == *"symlink"* && -L "$TEST_HOME/.zshrc" ]] &&
    grep -q "elsewhere" "$TEST_HOME/other-zshrc"; then
    pass "import refuses symlinked destinations"
else
    fail "import must not touch symlinked destinations (rc=$rc)"
fi

cleanup_sandbox

# ─── 7. import pulls from remote ──────────────────────────────────────

section "import: pull"

setup_cli_sandbox
seed_preset
seed_gitconfig

# machine A pushes new content; machine B (this sandbox) imports it
src="$TEST_DIR/machine-a"
mkdir -p "$src"
git -C "$src" init -q -b main 2>/dev/null || git -C "$src" init -q
mkdir -p "$src/config/tmux"
printf 'set -g history-limit 5000\n' >"$src/config/tmux/local.conf"
git -C "$src" add -A
git -C "$src" commit -q -m "from machine a"
git clone -q --bare "$src" "$TEST_DIR/remote.git"

# clone auto-imports, so the system file exists with machine A's old content
dotfiles_run local clone "$TEST_DIR/remote.git" >/dev/null

git -C "$src" remote add origin "$TEST_DIR/remote.git"
printf 'set -g history-limit 9999\n' >"$src/config/tmux/local.conf"
git -C "$src" add -A
git -C "$src" commit -q -m "update from machine a"
git -C "$src" push -q origin HEAD

# plain import pulls the new commit but must not clobber the existing file
out=$(dotfiles_run import) && rc=0 || rc=$?
if [[ $rc -eq 0 && "$out" == *"differs"* ]] &&
    grep -q "5000" "$TEST_HOME/.config/tmux/local.conf" 2>/dev/null &&
    grep -q "9999" "$TEST_HOME/.dotfiles-local/config/tmux/local.conf" 2>/dev/null; then
    pass "import pulls new commits and reports drift without clobbering"
else
    fail "import should pull from origin and leave the differing file (rc=$rc)"
fi

out=$(dotfiles_run import --force) && rc=0 || rc=$?
if [[ $rc -eq 0 ]] && grep -q "9999" "$TEST_HOME/.config/tmux/local.conf" 2>/dev/null; then
    pass "import --force applies the pulled changes"
else
    fail "import --force should apply upstream content (rc=$rc)"
fi

cleanup_sandbox

# ─── 8. env override ──────────────────────────────────────────────────

section "DOTFILES_LOCAL_DIR override"

setup_cli_sandbox
seed_preset
dotfiles_run local init >/dev/null # pointer -> ~/.dotfiles-local

alt="$TEST_DIR/alt-local"
mkdir -p "$alt"
git -C "$alt" init -q

out=$(DOTFILES_LOCAL_DIR="$alt" "$TEST_DOTFILES_DIR/scripts/dotfiles" local status 2>&1) && rc=0 || rc=$?
if [[ $rc -eq 0 && "$out" == *"$alt"* && "$out" == *"DOTFILES_LOCAL_DIR"* ]]; then
    pass "env var overrides the pointer file"
else
    fail "DOTFILES_LOCAL_DIR should take precedence (rc=$rc)"
fi

cleanup_sandbox

# ─── 9. preset gating ─────────────────────────────────────────────────

section "preset gating"

setup_cli_sandbox
seed_preset minimal
seed_gitconfig
seed_local_files
mkdir -p "$TEST_HOME/.hammerspoon"
printf 'print("local")\n' >"$TEST_HOME/.hammerspoon/local.lua"
dotfiles_run local init >/dev/null
dotfiles_run export >/dev/null

if [[ ! -e "$TEST_HOME/.dotfiles-local/hammerspoon/local.lua" ]]; then
    pass "minimal preset does not export full-preset files"
else
    fail "hammerspoon local.lua must not export on minimal preset"
fi

seed_preset full
dotfiles_run export >/dev/null
if [[ -f "$TEST_HOME/.dotfiles-local/hammerspoon/local.lua" ]]; then
    pass "full preset exports hammerspoon local.lua"
else
    fail "hammerspoon local.lua should export on full preset"
fi

cleanup_sandbox

# ─── 10. local diff ───────────────────────────────────────────────────

section "local diff"

setup_cli_sandbox
seed_preset
seed_gitconfig
seed_local_files
dotfiles_run local init >/dev/null
dotfiles_run export >/dev/null

out=$(dotfiles_run local diff) && rc=0 || rc=$?
if [[ $rc -eq 0 && "$out" == *"matches"* ]]; then
    pass "local diff reports match when in sync"
else
    fail "local diff should report match (rc=$rc)"
fi

printf 'set -g status on\n' >"$TEST_HOME/.config/tmux/local.conf"
out=$(dotfiles_run local diff) && rc=0 || rc=$?
if [[ "$out" == *"config/tmux/local.conf"* && "$out" == *"+set -g status on"* ]]; then
    pass "local diff shows unified diff for drift"
else
    fail "local diff should show the changed lines"
fi

cleanup_sandbox

# a repo file edited by hand (not via export) leaves the local repo uncommitted;
# export auto-commits, so this state is invisible to the repo↔system comparison
# and must be surfaced separately
setup_cli_sandbox
seed_preset
seed_gitconfig
seed_local_files
dotfiles_run local init >/dev/null
dotfiles_run export >/dev/null

printf '\nexport HAND_EDIT=1\n' >>"$TEST_HOME/.dotfiles-local/zshrc"
out=$(dotfiles_run local diff) && rc=0 || rc=$?
if [[ "$out" == *"uncommitted in the local repo"* && "$out" == *"HAND_EDIT"* ]]; then
    pass "local diff flags hand-edited uncommitted repo files"
else
    fail "local diff should flag uncommitted repo edits"
fi

cleanup_sandbox

# ─── 11. manifest drift guard ─────────────────────────────────────────

section "manifest drift guard"

# every install_local/copy_config destination in create-symlinks.sh must be
# represented in _local_pairs (full preset) or explicitly excluded here.
# a new local override added to the installer without a manifest entry
# fails this test: add it to _local_pairs in scripts/_lib/local-layer.sh
# or record the exclusion below with a reason
drift_exclusions=(
    # none currently
)

manifest=$(bash -c '
    export DOTFILES_DIR="'"$DOTFILES_DIR"'"
    source "$DOTFILES_DIR/scripts/_lib/common.sh"
    source "$DOTFILES_DIR/scripts/_lib/cli.sh"
    source "$DOTFILES_DIR/scripts/_lib/local-layer.sh"
    PRESET=full
    _local_pairs
    printf "%s\n" "${LOCAL_PAIRS[@]}" "${LOCAL_DIR_PAIRS[@]}"
')

installer_sources=$(grep -E '^[[:space:]]*(install_local|copy_config) ' \
    "$DOTFILES_DIR/scripts/install/create-symlinks.sh" |
    sed -E 's/^[[:space:]]*(install_local|copy_config) "\$DOTFILES_DIR\/([^"]+)".*/\2/' |
    sed 's/\.template$//')

drift_ok=1
while IFS= read -r src_rel; do
    [[ -z "$src_rel" ]] && continue
    excluded=0
    for ex in "${drift_exclusions[@]:-}"; do
        [[ "$src_rel" == "$ex" ]] && excluded=1
    done
    [[ $excluded -eq 1 ]] && continue
    # installer path tool/file must appear in some manifest repo path
    if ! printf '%s\n' "$manifest" | grep -qF "$src_rel"; then
        fail "manifest drift: '$src_rel' installed by create-symlinks.sh but missing from _local_pairs"
        drift_ok=0
    fi
done <<<"$installer_sources"

if [[ $drift_ok -eq 1 ]]; then
    pass "all installer local files are covered by _local_pairs"
fi

# ─── summary ──────────────────────────────────────────────────────────

print_summary

[[ $FAIL -gt 0 ]] && exit 1
exit 0
