#!/usr/bin/env bash
# shellcheck disable=SC1091
set -euo pipefail

# uninstall dotfiles: removes symlinks and optionally restores backups
# usage: ./scripts/install/uninstall.sh [--restore-backup] [--remove-brew-packages]

SCRIPT_DIR="${BASH_SOURCE%/*}"
DOTFILES_DIR="$(cd "$(dirname "$(dirname "$SCRIPT_DIR")")" && pwd)"
export DOTFILES_DIR

source "$SCRIPT_DIR/../_lib/common.sh"
source "$SCRIPT_DIR/../_lib/brewfile.sh"
source "$SCRIPT_DIR/../_lib/rollback.sh"

# parse arguments
RESTORE_BACKUP=0
REMOVE_BREW=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --restore-backup)
            RESTORE_BACKUP=1
            shift
            ;;
        --remove-brew-packages)
            REMOVE_BREW=1
            shift
            ;;
        -h|--help)
            cat << 'EOF'
uninstall.sh - Remove dotfiles installation

USAGE:
    ./scripts/install/uninstall.sh [OPTIONS]

OPTIONS:
    --restore-backup       Restore files from most recent backup
    --remove-brew-packages Also uninstall Homebrew packages from Brewfile
    -h, --help             Show this help message

DESCRIPTION:
    Removes all symlinks created by the dotfiles installation.

    By default, only symlinks are removed. Use --restore-backup to
    restore your original configuration files from ~/.dotfiles-backup/

EXAMPLES:
    # Just remove symlinks
    ./scripts/install/uninstall.sh

    # Remove symlinks and restore original configs
    ./scripts/install/uninstall.sh --restore-backup

    # Full uninstall including brew packages
    ./scripts/install/uninstall.sh --restore-backup --remove-brew-packages
EOF
            exit 0
            ;;
        *)
            error "Unknown option: $1"
            exit 1
            ;;
    esac
done

print_logo
print_header "Dotfiles Uninstall"

# define all symlinks that install.sh creates
# must match create-symlinks.sh exactly
# ~/.zshrc is handled separately (may be personal file, not symlink)
SYMLINKS=(
    # minimal
    "$HOME/.zprofile"
    "$HOME/.tmux.conf"
    "$HOME/.tmux"
    "$HOME/.local/bin/dotfiles"
    "$HOME/.prettierrc"
    "$HOME/.editorconfig"
    # core
    "$HOME/.config/nvim"
    "$HOME/.local/bin/dash-repo-sync"
    "$HOME/.local/launchers/dev"
    "$HOME/.config/lazygit/config.yml"
    "$HOME/.config/yazi/yazi.toml"
    "$HOME/.config/yazi/keymap.toml"
    "$HOME/.config/zed/keymap.json"
    "$HOME/.config/zed/tasks.json"
    "$HOME/.config/lazydocker/format-logs.awk"
    "${XDG_CONFIG_HOME:-$HOME/.config}/dotfiles/statusline-theme.sh"
    # full
    "$HOME/.hammerspoon/init.lua"
)

# macOS-only links: lazydocker lives under Application Support there, and the
# ImageMagick font map is not installed on linux
if [[ "$(uname)" == "Darwin" ]]; then
    SYMLINKS+=("$HOME/Library/Application Support/lazydocker/format-logs.awk")
    SYMLINKS+=("${XDG_CONFIG_HOME:-$HOME/.config}/ImageMagick/type.xml")
fi

# legacy macOS ghostty symlink (no longer created, Ghostty reads XDG natively)
if [[ "$(uname)" == "Darwin" ]] && [[ -L "$HOME/Library/Application Support/com.mitchellh.ghostty/config" ]]; then
    SYMLINKS+=("$HOME/Library/Application Support/com.mitchellh.ghostty/config")
fi

echo "This will remove the following symlinks:"

# show ~/.zshrc status
if [[ -L "$HOME/.zshrc" ]]; then
    echo "  - $HOME/.zshrc -> $(readlink "$HOME/.zshrc")"
elif [[ -f "$HOME/.zshrc" ]]; then
    echo "  - $HOME/.zshrc (personal file — will be preserved)"
fi

for link in "${SYMLINKS[@]}"; do
    if [[ -L "$link" ]]; then
        echo "  - $link -> $(readlink "$link")"
    elif [[ -e "$link" ]]; then
        echo "  - $link (exists but not a symlink - will skip)"
    fi
done
echo ""

if [[ $RESTORE_BACKUP -eq 1 ]]; then
    BACKUP_BASE="$HOME/.dotfiles-backup"
    if [[ -d "$BACKUP_BASE" ]]; then
        LATEST_BACKUP=$(find "$BACKUP_BASE" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | sort -r | head -1)
        if [[ -n "$LATEST_BACKUP" ]]; then
            echo "Will restore from backup: $LATEST_BACKUP"
            echo ""
        else
            warn "No backups found in $BACKUP_BASE"
            RESTORE_BACKUP=0
        fi
    else
        warn "Backup directory not found: $BACKUP_BASE"
        RESTORE_BACKUP=0
    fi
fi

if [[ $REMOVE_BREW -eq 1 ]]; then
    echo "Will also remove Homebrew packages from Brewfile"
    echo ""
fi

if ! confirm "Proceed with uninstall?"; then
    echo "Uninstall cancelled"
    exit 0
fi

echo ""

# handle ~/.zshrc: may be a symlink (old) or personal file (new)
if [[ -L "$HOME/.zshrc" ]]; then
    rm -f "$HOME/.zshrc"
    success "Removed: $HOME/.zshrc (symlink)"
elif [[ -f "$HOME/.zshrc" ]]; then
    if grep -q "dotfiles.zsh" "$HOME/.zshrc" 2>/dev/null; then
        warn "Kept ~/.zshrc (personal file — remove manually if desired)"
    fi
fi

# step 1: remove symlinks
info "Removing symlinks..."
for link in "${SYMLINKS[@]}"; do
    if [[ -L "$link" ]]; then
        rm -f "$link"
        success "Removed: $link"
    elif [[ -e "$link" ]]; then
        warn "Skipped (not a symlink): $link"
    fi
done

# step 2: restore from backup if requested
if [[ $RESTORE_BACKUP -eq 1 ]] && [[ -n "${LATEST_BACKUP:-}" ]]; then
    echo ""
    restore_from_backup "$LATEST_BACKUP"
fi

# step 3: remove additional created files/directories
echo ""
info "Cleaning up additional files..."

# remove the yazi config dir: a real directory holds the generated theme.toml
# (per-file symlinks removed above); a legacy install may still have a whole-dir
# symlink
if [[ -L "$HOME/.config/yazi" ]]; then
    rm -f "$HOME/.config/yazi"
    success "Removed: ~/.config/yazi (legacy symlink)"
elif [[ -d "$HOME/.config/yazi" ]]; then
    rm -rf "$HOME/.config/yazi"
    success "Removed: ~/.config/yazi (config dir + generated theme)"
fi

# remove TPM if installed by us
if [[ -d "$HOME/.tmux/plugins/tpm" ]]; then
    if confirm "Remove TPM (Tmux Plugin Manager)?"; then
        rm -rf "$HOME/.tmux/plugins"
        success "Removed: ~/.tmux/plugins"
    fi
fi

# remove secrets file if empty
ZSH_CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/zsh"
if [[ -f "$ZSH_CONFIG_DIR/secrets.zsh" ]]; then
    if [[ ! -s "$ZSH_CONFIG_DIR/secrets.zsh" ]]; then
        rm -f "$ZSH_CONFIG_DIR/secrets.zsh"
        success "Removed empty secrets file"
    else
        warn "Kept $ZSH_CONFIG_DIR/secrets.zsh (contains data)"
    fi
fi

# remove local-aliases backup if it exists
if [[ -f "$ZSH_CONFIG_DIR/local-aliases.zsh.bak" ]]; then
    rm -f "$ZSH_CONFIG_DIR/local-aliases.zsh.bak"
    success "Removed local-aliases.zsh.bak"
fi

# remove local-aliases.zsh if still present and empty
if [[ -f "$ZSH_CONFIG_DIR/local-aliases.zsh" ]]; then
    if [[ ! -s "$ZSH_CONFIG_DIR/local-aliases.zsh" ]]; then
        rm -f "$ZSH_CONFIG_DIR/local-aliases.zsh"
        success "Removed empty local-aliases.zsh"
    else
        warn "Kept $ZSH_CONFIG_DIR/local-aliases.zsh (contains data)"
    fi
fi

# handle Ghostty local override file
ghostty_local="$HOME/.config/ghostty/local"
if [[ -f "$ghostty_local" ]]; then
    # check if it has any non-comment, non-blank content
    if grep -qE '^[^#[:space:]]' "$ghostty_local" 2>/dev/null; then
        warn "Kept $ghostty_local (contains your personal overrides — remove manually if desired)"
    else
        rm -f "$ghostty_local"
        success "Removed $ghostty_local (empty/template-only)"
    fi
fi

# handle tmux local override file
tmux_local="${XDG_CONFIG_HOME:-$HOME/.config}/tmux/local.conf"
if [[ -f "$tmux_local" ]]; then
    if grep -qE '^[^#[:space:]]' "$tmux_local" 2>/dev/null; then
        warn "Kept $tmux_local (contains your personal overrides — remove manually if desired)"
    else
        rm -f "$tmux_local"
        success "Removed $tmux_local (empty/template-only)"
    fi
fi

# handle nvim local override file
nvim_local="$HOME/.config/nvim/local.lua"
if [[ -f "$nvim_local" ]]; then
    if grep -qE '^[^-[:space:]]' "$nvim_local" 2>/dev/null; then
        warn "Kept $nvim_local (contains your personal overrides — remove manually if desired)"
    else
        rm -f "$nvim_local"
        success "Removed $nvim_local (empty/template-only)"
    fi
fi

# handle user-owned config files (copy-on-install pattern)
# these are personal configs: warn and preserve, like ~/.zshrc

p10k_conf="$HOME/.p10k.zsh"
if [[ -f "$p10k_conf" ]]; then
    warn "Kept $p10k_conf (personal config — remove manually if desired)"
fi

btop_conf="$HOME/.config/btop/btop.conf"
if [[ -f "$btop_conf" ]]; then
    warn "Kept $btop_conf (personal config — remove manually if desired)"
fi

karabiner_conf="$HOME/.config/karabiner/karabiner.json"
if [[ -f "$karabiner_conf" ]]; then
    warn "Kept $karabiner_conf (personal config — remove manually if desired)"
fi

zed_settings="$HOME/.config/zed/settings.json"
if [[ -f "$zed_settings" ]]; then
    warn "Kept $zed_settings (personal config — remove manually if desired)"
fi

hammerspoon_dir="$HOME/.hammerspoon"
if [[ -d "$hammerspoon_dir" && ! -L "$hammerspoon_dir" ]]; then
    warn "Kept $hammerspoon_dir/ (personal config — remove manually if desired)"
fi

if [[ "$(uname)" == "Darwin" ]]; then
    lazygit_conf="$HOME/Library/Application Support/lazygit/config.yml"
    lazydocker_conf="$HOME/Library/Application Support/lazydocker/config.yml"
else
    lazygit_conf="$HOME/.config/lazygit/config.yml"
    lazydocker_conf="$HOME/.config/lazydocker/config.yml"
fi
if [[ -f "$lazygit_conf" ]]; then
    warn "Kept $lazygit_conf (personal config — remove manually if desired)"
fi
if [[ -f "$lazydocker_conf" ]]; then
    warn "Kept $lazydocker_conf (personal config — remove manually if desired)"
fi

# local-layer repo and its pointer are user data; never removed
local_ptr="${XDG_CONFIG_HOME:-$HOME/.config}/dotfiles/local-repo"
if [[ -f "$local_ptr" ]]; then
    warn "Kept local layer repo $(head -1 "$local_ptr") and pointer $local_ptr (user data)"
fi

# step 4: remove Homebrew packages if requested
if [[ $REMOVE_BREW -eq 1 ]]; then
    echo ""
    info "Removing Homebrew packages..."

    if [[ -f "$DOTFILES_DIR/Brewfile" ]] && command_exists brew; then
        # load saved preset
        PRESET_FILE="${XDG_CONFIG_HOME:-$HOME/.config}/dotfiles/preset"
        if [[ -f "$PRESET_FILE" ]]; then
            PRESET=$(cat "$PRESET_FILE")
            echo "Using saved preset: $PRESET"
        else
            PRESET="full"
            echo "No saved preset found, assuming: $PRESET"
        fi

        # create filtered Brewfile
        FILTERED_BREWFILE=$(create_filtered_brewfile "$PRESET" "$DOTFILES_DIR/Brewfile")

        # set up cleanup trap for filtered Brewfile
        # shellcheck disable=SC2064
        trap "rm -f '$FILTERED_BREWFILE'" EXIT

        echo ""
        echo "Packages to remove (based on $PRESET preset):"
        grep -E '^(brew|cask) "' "$FILTERED_BREWFILE" | head -20
        TOTAL=$(grep -cE '^(brew|cask) "' "$FILTERED_BREWFILE" || echo 0)
        if [[ $TOTAL -gt 20 ]]; then
            echo "  ... and $((TOTAL - 20)) more"
        fi
        echo ""

        if confirm "Remove these $TOTAL packages?"; then
            warn "Note: Some packages may be shared with non-dotfiles software."
            failed=0
            while IFS= read -r pkg; do
                if brew uninstall --ignore-dependencies "$pkg" 2>/dev/null; then
                    success "Removed: $pkg"
                else
                    warn "Failed to remove: $pkg (may be a dependency or already removed)"
                    failed=$((failed + 1))
                fi
            done < <(grep -E '^brew "' "$FILTERED_BREWFILE" | sed 's/brew "//;s/".*//')
            while IFS= read -r pkg; do
                if brew uninstall --cask "$pkg" 2>/dev/null; then
                    success "Removed: $pkg"
                else
                    warn "Failed to remove cask: $pkg"
                    failed=$((failed + 1))
                fi
            done < <(grep -E '^cask "' "$FILTERED_BREWFILE" | sed 's/cask "//;s/".*//')
            if [[ $failed -gt 0 ]]; then
                warn "$failed package(s) could not be removed"
            else
                success "Homebrew packages removed"
            fi
        fi
    else
        warn "Brewfile not found or brew not installed"
    fi
fi

# step 5: remove preset config (after brew removal since we need to read it)
PRESET_CONFIG_FILE="${XDG_CONFIG_HOME:-$HOME/.config}/dotfiles/preset"
if [[ -f "$PRESET_CONFIG_FILE" ]]; then
    rm -f "$PRESET_CONFIG_FILE"
    rmdir "${XDG_CONFIG_HOME:-$HOME/.config}/dotfiles" 2>/dev/null || true
    success "Removed preset configuration"
fi

echo ""
print_logo
print_header "Uninstall Complete"

echo "Dotfiles symlinks have been removed."
if [[ $RESTORE_BACKUP -eq 1 ]]; then
    echo "Original configuration files have been restored."
fi
echo ""
echo "Note: Backups are preserved at ~/.dotfiles-backup/"
echo "You can delete them manually if no longer needed."
