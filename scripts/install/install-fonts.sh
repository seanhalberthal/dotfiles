#!/usr/bin/env bash
set -euo pipefail

# install Nerd Fonts on Linux.
#
# on macOS these come from the Brewfile casks (font-meslo-lg-nerd-font,
# font-jetbrains-mono-nerd-font, font-monaspace-nf), but Homebrew casks are
# macOS-only, so Linux has no brew path to them. this fetches the matching
# release archives and installs the terminal weights into the user font
# directory. glyphs only render on a locally-attached display; over SSH the
# client terminal supplies the font, so this is skipped on headless servers by
# virtue of running only for the core preset and above.
#
# two sources: the standard Nerd Fonts (Meslo, JetBrainsMono) come from
# ryanoasis/nerd-fonts as TTF assets with stable names; Monaspace comes from
# githubnext/monaspace's own NF build (family name "Monaspace Neon NF", matching
# the macOS cask) as OTF, in a version-embedded asset that has to be resolved
# via the GitHub API rather than the latest/download shortcut.

SCRIPT_DIR="${BASH_SOURCE%/*}"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/../_lib/common.sh"

# fonts to install, keyed by the release asset name (<name>.zip) on
# github.com/ryanoasis/nerd-fonts/releases. mirrors the Brewfile casks.
NERD_FONTS=("Meslo" "JetBrainsMono")

# only the four terminal weights, for both the standard and Mono (single-cell
# glyph) variants; Propo (proportional) is skipped. the leading-hyphen suffixes
# match exact weights only, so -Bold does not also pull -ExtraBold/-SemiBold.
FONT_WEIGHTS=("Regular" "Bold" "Italic" "BoldItalic")

# Monaspace families to install from githubnext/monaspace (family token as it
# appears in the file name, e.g. MonaspaceNeonNF-Regular.otf). Neon only mirrors
# the daily-driver terminal font; add "Argon"/"Xenon"/"Radon"/"Krypton" here to
# pull the other voices. the exact-name match below keeps this to the standard
# width, so the Wide/SemiWide variants are left out.
MONASPACE_FAMILIES=("Neon")

FONT_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/fonts"
NF_DIR="$FONT_DIR/nerd-fonts"
FORCE="${1:-}"

if is_macos; then
    info "Nerd Fonts install via Homebrew casks on macOS — skipping Linux path."
    exit 0
fi

# required tooling; fonts are non-critical so warn and skip rather than fail
for tool in curl unzip fc-cache; do
    if ! command_exists "$tool"; then
        warn "'$tool' not found — skipping Nerd Font install."
        echo "  Install $tool and re-run: dotfiles update --force"
        exit 0
    fi
done

installed_any=0

install_font() {
    local name="$1"
    local dest="$NF_DIR/$name"

    # idempotent: skip if we already populated this font's directory
    if [[ "$FORCE" != "--force" ]] && compgen -G "$dest/*.ttf" >/dev/null 2>&1; then
        echo "$name Nerd Font already installed."
        return 0
    fi

    local tmp
    tmp="$(mktemp -d)"
    # shellcheck disable=SC2064
    trap "rm -rf '$tmp'" RETURN

    local url="https://github.com/ryanoasis/nerd-fonts/releases/latest/download/${name}.zip"
    echo "Downloading $name Nerd Font..."
    if ! curl -fL --retry 2 -o "$tmp/$name.zip" "$url"; then
        warn "Failed to download $name Nerd Font (network issue?). Skipping."
        return 0
    fi

    if ! unzip -o -q "$tmp/$name.zip" -d "$tmp/extract"; then
        warn "Failed to extract $name Nerd Font. Skipping."
        return 0
    fi

    # build the -name predicate list for the wanted weights x variants
    local find_args=()
    local variant weight first=1
    for variant in NerdFont NerdFontMono; do
        for weight in "${FONT_WEIGHTS[@]}"; do
            [[ $first -eq 1 ]] || find_args+=(-o)
            find_args+=(-name "*${variant}-${weight}.ttf")
            first=0
        done
    done

    mkdir -p "$dest"
    local before after
    before=$(find "$dest" -maxdepth 1 -name '*.ttf' 2>/dev/null | wc -l)
    find "$tmp/extract" -type f \( "${find_args[@]}" \) -exec cp {} "$dest/" \;
    after=$(find "$dest" -maxdepth 1 -name '*.ttf' 2>/dev/null | wc -l)

    if [[ "$after" -gt "$before" ]]; then
        success "Installed $name Nerd Font ($((after - before)) files)"
        installed_any=1
    else
        warn "No matching $name Nerd Font files found (upstream naming changed?)."
        rmdir "$dest" 2>/dev/null || true
    fi
}

# Monaspace ships its own NF build under a different repo/format to ryanoasis,
# so it gets a dedicated path: the release asset name embeds the version
# (monaspace-nerdfonts-vX.Y.Z.zip), which the latest/download shortcut can't
# target, so resolve the current asset URL from the GitHub API first.
install_monaspace() {
    local dest="$NF_DIR/Monaspace"

    # idempotent: skip if we already populated the directory with OTFs
    if [[ "$FORCE" != "--force" ]] && compgen -G "$dest/*.otf" >/dev/null 2>&1; then
        echo "Monaspace Nerd Font already installed."
        return 0
    fi

    local api="https://api.github.com/repos/githubnext/monaspace/releases/latest"
    local url
    url="$(curl -fsSL --retry 2 "$api" 2>/dev/null |
        grep -oE '"browser_download_url":[[:space:]]*"[^"]*monaspace-nerdfonts-[^"]*\.zip"' |
        sed -E 's/.*"(https[^"]*)"/\1/' | head -1)"
    if [[ -z "$url" ]]; then
        warn "Could not resolve latest Monaspace release (API/network issue?). Skipping."
        return 0
    fi

    local tmp
    tmp="$(mktemp -d)"
    # shellcheck disable=SC2064
    trap "rm -rf '$tmp'" RETURN

    echo "Downloading Monaspace Nerd Font..."
    if ! curl -fL --retry 2 -o "$tmp/monaspace.zip" "$url"; then
        warn "Failed to download Monaspace Nerd Font (network issue?). Skipping."
        return 0
    fi

    if ! unzip -o -q "$tmp/monaspace.zip" -d "$tmp/extract"; then
        warn "Failed to extract Monaspace Nerd Font. Skipping."
        return 0
    fi

    # exact-name predicates for the wanted families x weights; the standard
    # width has no width token (Wide/SemiWide) in the file name, so an exact
    # match cleanly excludes those broader variants.
    local find_args=()
    local family weight first=1
    for family in "${MONASPACE_FAMILIES[@]}"; do
        for weight in "${FONT_WEIGHTS[@]}"; do
            [[ $first -eq 1 ]] || find_args+=(-o)
            find_args+=(-name "Monaspace${family}NF-${weight}.otf")
            first=0
        done
    done

    mkdir -p "$dest"
    local before after
    before=$(find "$dest" -maxdepth 1 -name '*.otf' 2>/dev/null | wc -l)
    find "$tmp/extract" -type f \( "${find_args[@]}" \) -exec cp {} "$dest/" \;
    after=$(find "$dest" -maxdepth 1 -name '*.otf' 2>/dev/null | wc -l)

    if [[ "$after" -gt "$before" ]]; then
        success "Installed Monaspace Nerd Font ($((after - before)) files)"
        installed_any=1
    else
        warn "No matching Monaspace Nerd Font files found (upstream naming changed?)."
        rmdir "$dest" 2>/dev/null || true
    fi
}

echo "Installing Nerd Fonts (Linux)..."
mkdir -p "$NF_DIR"
for font in "${NERD_FONTS[@]}"; do
    install_font "$font"
done
install_monaspace

# refresh the fontconfig cache once, only if we added anything
if [[ "$installed_any" -eq 1 ]]; then
    echo "Rebuilding font cache..."
    fc-cache -f "$FONT_DIR" >/dev/null 2>&1 || warn "fc-cache reported an issue."
    success "Nerd Fonts ready. Set your terminal font to 'JetBrainsMono Nerd Font', 'MesloLGS Nerd Font', or 'Monaspace Neon NF'."
fi
