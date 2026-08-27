#!/usr/bin/env bash
set -euo pipefail

# migration: replace pipx with uv
#
# the Brewfile now ships `uv` instead of `pipx`. `uv tool install <name>`
# and `uvx <name>` are drop-in replacements for `pipx install` / `pipx run`,
# so the pipx formula and its managed venvs are no longer needed
#
# we can't silently re-home pipx-managed apps under uv; uv keeps its own
# venv tree under `~/.local/share/uv/tools/` and the user may not want every
# pipx app reinstalled. instead we list what was managed by pipx, snapshot
# it to disk so the user has a record, uninstall the apps + their venvs,
# then drop the pipx formula. re-install anything you still want with
# `uv tool install <name>`

if ! command -v brew >/dev/null 2>&1; then
    echo "    brew not found — skipping pipx removal"
    exit 0
fi

if ! brew list --formula --versions pipx >/dev/null 2>&1; then
    echo "    pipx not installed — nothing to remove"
    exit 0
fi

state_dir="${XDG_CONFIG_HOME:-$HOME/.config}/dotfiles/.state"
mkdir -p "$state_dir"
snapshot="$state_dir/pipx-uninstalled.txt"
notice_file="$state_dir/update-notices.txt"

managed=""
if command -v pipx >/dev/null 2>&1; then
    managed="$(pipx list --short 2>/dev/null | awk '{print $1}' | sort -u || true)"
    if [[ -n "$managed" ]]; then
        echo "    Snapshotting pipx-managed apps to $snapshot"
        {
            echo "# pipx-managed apps removed by 0.2.99-uninstall-pipx.sh"
            echo "# Re-install with: uv tool install <name>"
            echo "$managed"
        } >"$snapshot"

        echo "    Uninstalling pipx-managed apps:"
        while IFS= read -r app; do
            [[ -z "$app" ]] && continue
            echo "      - $app"
        done <<<"$managed"

        if ! pipx uninstall-all >/dev/null 2>&1; then
            echo "    pipx uninstall-all failed — re-run manually before removing pipx"
            exit 1
        fi
    else
        echo "    No pipx-managed apps to remove"
    fi
fi

echo "    Uninstalling pipx formula..."
brew uninstall --formula pipx

# append a notice so the end-of-update summary surfaces this; the mid-run
# output above will have scrolled past by the time the installer finishes
{
    echo "pipx has been removed; uv replaces it."
    if [[ -n "$managed" ]]; then
        echo "  Apps uninstalled (re-install with \`uv tool install <name>\`):"
        while IFS= read -r app; do
            [[ -z "$app" ]] && continue
            echo "    - $app"
        done <<<"$managed"
        echo "  Snapshot saved to: $snapshot"
    else
        echo "  No pipx-managed apps were present."
    fi
    echo ""
} >>"$notice_file"

echo "    pipx removed"
