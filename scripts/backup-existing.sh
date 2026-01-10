#!/usr/bin/env bash
set -euo pipefail

# Backup existing configuration files before creating symlinks
# Creates timestamped backup directory

BACKUP_DIR="$HOME/.dotfiles-backup-$(date +%Y%m%d-%H%M%S)"

# Colours
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'

backup_if_exists() {
    local source="$1"
    local dest="$2"

    if [[ -e "$source" ]] || [[ -L "$source" ]]; then
        mkdir -p "$(dirname "$dest")"
        mv "$source" "$dest"
        printf "${YELLOW}Backed up:${NC} %s -> %s\n" "$source" "$dest"
        return 0
    fi
    return 1
}

echo "============================================"
echo "Backing up existing configuration files"
echo "============================================"
echo ""

BACKED_UP=0

# Zsh
backup_if_exists "$HOME/.zshrc" "$BACKUP_DIR/.zshrc" && BACKED_UP=1
backup_if_exists "$HOME/.zprofile" "$BACKUP_DIR/.zprofile" && BACKED_UP=1
backup_if_exists "$HOME/.p10k.zsh" "$BACKUP_DIR/.p10k.zsh" && BACKED_UP=1
backup_if_exists "$HOME/.zsh" "$BACKUP_DIR/.zsh" && BACKED_UP=1

# Tmux
backup_if_exists "$HOME/.tmux.conf" "$BACKUP_DIR/.tmux.conf" && BACKED_UP=1
backup_if_exists "$HOME/.tmux" "$BACKUP_DIR/.tmux" && BACKED_UP=1

# Neovim
backup_if_exists "$HOME/.config/nvim" "$BACKUP_DIR/.config/nvim" && BACKED_UP=1

# Hammerspoon
backup_if_exists "$HOME/.hammerspoon" "$BACKUP_DIR/.hammerspoon" && BACKED_UP=1

# Ghostty
backup_if_exists "$HOME/.config/ghostty" "$BACKUP_DIR/.config/ghostty" && BACKED_UP=1

# Karabiner
backup_if_exists "$HOME/.config/karabiner" "$BACKUP_DIR/.config/karabiner" && BACKED_UP=1

echo ""

if [[ $BACKED_UP -eq 1 ]]; then
    echo "${GREEN}Backup complete!${NC}"
    echo "Backup location: $BACKUP_DIR"
    echo ""
    echo "To restore, run:"
    echo "  cp -r $BACKUP_DIR/* \$HOME/"
else
    echo "No existing configuration files found to backup."
fi

echo "$BACKUP_DIR"
