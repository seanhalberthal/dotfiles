#!/usr/bin/env bash
set -euo pipefail

# install the Ghostty theme catalogue on Linux boxes that don't have Ghostty.
#
# `dotfiles theme generate <builtin>` imports a colour palette from Ghostty's
# bundled theme files (its source of truth), but Ghostty isn't packaged on some
# Linux distros (e.g. Debian / Raspberry Pi OS), so those files are absent and
# generation fails. The theme resolver already searches
# ~/.local/share/ghostty/themes, so we populate that with the upstream Ghostty
# theme files (from mbadolato/iTerm2-Color-Schemes, which ships a ready-made
# ghostty/ directory) — no Ghostty binary required.
#
# On macOS the themes live inside Ghostty.app; where Ghostty is packaged
# (Arch/Fedora) /usr/share/ghostty/themes exists — both are skipped.

SCRIPT_DIR="${BASH_SOURCE%/*}"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/../_lib/common.sh"

SCHEMES_REPO="https://github.com/mbadolato/iTerm2-Color-Schemes"
DEST="${XDG_DATA_HOME:-$HOME/.local/share}/ghostty/themes"
FORCE="${1:-}"

if is_macos; then
    info "Ghostty ships its own themes on macOS — skipping."
    exit 0
fi

# if Ghostty is installed system-wide, it already provides the catalogue
for d in /usr/share/ghostty/themes /usr/local/share/ghostty/themes; do
    if [[ -d "$d" ]]; then
        info "Ghostty theme catalogue already present ($d)."
        exit 0
    fi
done

# idempotent: skip if we already populated the user dir
if [[ "$FORCE" != "--force" ]] && compgen -G "$DEST/*" >/dev/null 2>&1; then
    echo "Ghostty theme catalogue already installed at $DEST."
    exit 0
fi

if ! command_exists git; then
    warn "git not found — skipping Ghostty theme catalogue."
    exit 0
fi

echo "Fetching Ghostty theme catalogue (enables 'dotfiles theme generate' without Ghostty)..."
tmp="$(mktemp -d)"
# shellcheck disable=SC2064
trap "rm -rf '$tmp'" EXIT

# partial + sparse clone: fetch only the ghostty/ directory's blobs, not the
# repo's large screenshot history
if ! git clone --depth 1 --filter=blob:none --sparse "$SCHEMES_REPO" "$tmp/repo" 2>/dev/null; then
    warn "Failed to clone theme catalogue (network issue?). Skipping."
    exit 0
fi
if ! git -C "$tmp/repo" sparse-checkout set ghostty 2>/dev/null; then
    warn "Failed to sparse-checkout ghostty themes. Skipping."
    exit 0
fi

if [[ ! -d "$tmp/repo/ghostty" ]]; then
    warn "ghostty/ directory not found in theme catalogue. Skipping."
    exit 0
fi

mkdir -p "$DEST"
count=0
for f in "$tmp/repo/ghostty"/*; do
    if [[ -f "$f" ]]; then
        cp "$f" "$DEST/"
        count=$((count + 1))
    fi
done

if [[ "$count" -gt 0 ]]; then
    success "Installed $count Ghostty themes to $DEST"
    echo "  Try: dotfiles theme generate kanagawa-dragon"
else
    warn "No Ghostty theme files found in catalogue."
fi
