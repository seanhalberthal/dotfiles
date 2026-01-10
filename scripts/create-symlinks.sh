#!/usr/bin/env bash
set -euo pipefail

# Create symlinks for all dotfiles
# Requires DOTFILES_DIR to be set

DOTFILES_DIR="${DOTFILES_DIR:-$HOME/dotfiles}"

# Colours (using $'...' for proper escape interpretation)
GREEN=$'\033[0;32m'
RED=$'\033[0;31m'
NC=$'\033[0m'

FAILED=0

create_link() {
    local source="$1"
    local dest="$2"

    # Ensure parent directory exists
    mkdir -p "$(dirname "$dest")"

    # Remove existing symlink if present
    if [[ -L "$dest" ]]; then
        rm "$dest"
    fi

    # Fail if destination exists and is not a symlink
    if [[ -e "$dest" ]]; then
        printf "${RED}FAILED:${NC} %s already exists and is not a symlink\n" "$dest"
        FAILED=1
        return 1
    fi

    # Create symlink
    if ln -sf "$source" "$dest"; then
        printf "${GREEN}Created:${NC} %s -> %s\n" "$dest" "$source"
        return 0
    else
        printf "${RED}FAILED:${NC} Could not create symlink %s\n" "$dest"
        FAILED=1
        return 1
    fi
}

echo "============================================"
echo "Creating symlinks"
echo "============================================"
echo ""
echo "Source: $DOTFILES_DIR"
echo ""

# Zsh
echo "Zsh configuration:"
create_link "$DOTFILES_DIR/zsh/.zshrc" "$HOME/.zshrc"
create_link "$DOTFILES_DIR/zsh/.zprofile" "$HOME/.zprofile"
create_link "$DOTFILES_DIR/zsh/.p10k.zsh" "$HOME/.p10k.zsh"
create_link "$DOTFILES_DIR/zsh/.zsh" "$HOME/.zsh"

echo ""
echo "Tmux configuration:"
create_link "$DOTFILES_DIR/tmux/.tmux.conf" "$HOME/.tmux.conf"
create_link "$DOTFILES_DIR/tmux/.tmux" "$HOME/.tmux"

echo ""
echo "Neovim configuration:"
create_link "$DOTFILES_DIR/nvim" "$HOME/.config/nvim"

echo ""
echo "Hammerspoon configuration:"
create_link "$DOTFILES_DIR/hammerspoon" "$HOME/.hammerspoon"

echo ""
echo "Ghostty configuration:"
mkdir -p "$HOME/.config/ghostty"
create_link "$DOTFILES_DIR/ghostty/config" "$HOME/.config/ghostty/config"

echo ""
echo "Karabiner configuration:"
mkdir -p "$HOME/.config/karabiner"
create_link "$DOTFILES_DIR/karabiner/karabiner.json" "$HOME/.config/karabiner/karabiner.json"

echo ""
echo "Custom scripts (bin):"
mkdir -p "$HOME/.local/bin"
create_link "$DOTFILES_DIR/bin/tm" "$HOME/.local/bin/tm"
create_link "$DOTFILES_DIR/bin/dana" "$HOME/.local/bin/dana"

echo ""

if [[ $FAILED -eq 0 ]]; then
    echo "${GREEN}All symlinks created successfully!${NC}"
    exit 0
else
    echo "${RED}Some symlinks failed to create. Check the output above.${NC}"
    exit 1
fi
