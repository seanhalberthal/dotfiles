#!/usr/bin/env bash
# migration: add squash & merge keybinding to gh-dash local.yml
# overrides the built-in 'm' key to use --squash --delete-branch

set -euo pipefail

local_yml="${XDG_CONFIG_HOME:-$HOME/.config}/gh-dash/local.yml"

if [[ ! -f "$local_yml" ]]; then
    echo "    No gh-dash local.yml found, skipping"
    exit 0
fi

if grep -q 'squash.*delete-branch' "$local_yml" 2>/dev/null; then
    echo "    Squash & merge keybinding already present, skipping"
    exit 0
fi

# check for an existing keybindings.prs section to append to
if grep -q '^keybindings:' "$local_yml" 2>/dev/null; then
    if grep -q '^\s*prs:' "$local_yml" 2>/dev/null; then
        # append entry under existing prs key
        sed -i.bak '/^[[:space:]]*prs:/a\
        - key: m\
          name: squash \& merge\
          command: gh pr merge --squash --delete-branch --repo {{.RepoName}} {{.PrNumber}}' "$local_yml"
    else
        # keybindings exists but no prs section, add one
        sed -i.bak '/^keybindings:/a\
    prs:\
        - key: m\
          name: squash \& merge\
          command: gh pr merge --squash --delete-branch --repo {{.RepoName}} {{.PrNumber}}' "$local_yml"
    fi
else
    # no keybindings section at all, append to end of file
    cat >>"$local_yml" <<'EOF'
keybindings:
    prs:
        - key: m
          name: squash & merge
          command: gh pr merge --squash --delete-branch --repo {{.RepoName}} {{.PrNumber}}
EOF
fi

rm -f "${local_yml}.bak"
echo "    Added squash & merge keybinding to gh-dash"
