#!/usr/bin/env bash
set -euo pipefail

# Install packages from Brewfile

DOTFILES_DIR="${DOTFILES_DIR:-$HOME/dotfiles}"

# Colours
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
NC='\033[0m'

echo "============================================"
echo "Installing Homebrew Packages"
echo "============================================"
echo ""

# Check if Brewfile exists
if [[ ! -f "$DOTFILES_DIR/Brewfile" ]]; then
    echo "${RED}Error: Brewfile not found at $DOTFILES_DIR/Brewfile${NC}"
    exit 1
fi

# Check if brew is available
if ! command -v brew &>/dev/null; then
    echo "${RED}Error: Homebrew not found. Run install-homebrew.sh first.${NC}"
    exit 1
fi

# Install packages from Brewfile
echo "Installing packages from Brewfile..."
echo "This may take a while on first run."
echo ""

if brew bundle install --file="$DOTFILES_DIR/Brewfile" --no-lock; then
    echo ""
    echo "${GREEN}All packages installed successfully${NC}"
else
    echo ""
    echo "${YELLOW}Some packages may have failed to install.${NC}"
    echo "Check the output above for details."
    echo ""
    echo "You can retry failed packages with:"
    echo "  brew bundle install --file=$DOTFILES_DIR/Brewfile"
fi

# Post-installation setup for specific tools
echo ""
echo "${CYAN}Running post-installation setup...${NC}"
echo ""

# fzf keybindings and completion
if command -v fzf &>/dev/null; then
    FZF_INSTALL="$(brew --prefix)/opt/fzf/install"
    if [[ -f "$FZF_INSTALL" ]]; then
        echo "Setting up fzf keybindings..."
        "$FZF_INSTALL" --key-bindings --completion --no-update-rc --no-bash --no-fish
    fi
fi

# fnm shell setup reminder
if command -v fnm &>/dev/null; then
    echo ""
    echo "${CYAN}fnm installed.${NC} To install Node.js:"
    echo "  fnm install --lts"
    echo "  fnm default lts-latest"
fi

# pipx path setup
if command -v pipx &>/dev/null; then
    pipx ensurepath 2>/dev/null || true
fi

echo ""
echo "${GREEN}Package installation complete${NC}"
