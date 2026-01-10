#!/usr/bin/env bash
set -euo pipefail

# Dotfiles installation script
# Usage: ./install.sh [--skip-backup] [--skip-brew] [--check-only]

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export DOTFILES_DIR

# Colours
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
NC='\033[0m'

# Parse arguments
SKIP_BACKUP=0
SKIP_BREW=0
CHECK_ONLY=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --skip-backup)
            SKIP_BACKUP=1
            shift
            ;;
        --skip-brew)
            SKIP_BREW=1
            shift
            ;;
        --check-only)
            CHECK_ONLY=1
            shift
            ;;
        -h|--help)
            echo "Usage: ./install.sh [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --skip-backup    Skip backing up existing config files"
            echo "  --skip-brew      Skip Homebrew installation and packages"
            echo "  --check-only     Only run prerequisite and health checks"
            echo "  -h, --help       Show this help message"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

echo ""
echo "${CYAN}╔════════════════════════════════════════════╗${NC}"
echo "${CYAN}║           Dotfiles Installation            ║${NC}"
echo "${CYAN}╚════════════════════════════════════════════╝${NC}"
echo ""
echo "Dotfiles directory: $DOTFILES_DIR"
echo ""

# Step 1: Install/Update Homebrew
if [[ $SKIP_BREW -eq 0 ]]; then
    echo "${CYAN}Step 1: Setting up Homebrew...${NC}"
    echo ""
    "$DOTFILES_DIR/scripts/install-homebrew.sh"
    echo ""
else
    echo "${YELLOW}Step 1: Skipping Homebrew setup (--skip-brew flag)${NC}"
    echo ""
fi

# Step 2: Install packages from Brewfile
if [[ $SKIP_BREW -eq 0 ]]; then
    echo "${CYAN}Step 2: Installing packages from Brewfile...${NC}"
    echo ""
    "$DOTFILES_DIR/scripts/install-packages.sh"
    echo ""
else
    echo "${YELLOW}Step 2: Skipping package installation (--skip-brew flag)${NC}"
    echo ""
fi

# Step 3: Check prerequisites
echo "${CYAN}Step 3: Checking prerequisites...${NC}"
echo ""
if ! "$DOTFILES_DIR/scripts/check-prerequisites.sh"; then
    echo ""
    echo "${RED}Some required tools are missing.${NC}"
    if [[ $SKIP_BREW -eq 1 ]]; then
        echo "Try running without --skip-brew to install missing packages."
    fi
    exit 1
fi

if [[ $CHECK_ONLY -eq 1 ]]; then
    echo ""
    echo "${CYAN}Running health check...${NC}"
    echo ""
    "$DOTFILES_DIR/scripts/health-check.sh" || true
    exit 0
fi

# Step 4: Backup existing files
echo ""
echo "${CYAN}Step 4: Backing up existing configuration...${NC}"
echo ""
if [[ $SKIP_BACKUP -eq 0 ]]; then
    BACKUP_DIR=$("$DOTFILES_DIR/scripts/backup-existing.sh" | tail -n1)
else
    echo "${YELLOW}Skipping backup (--skip-backup flag)${NC}"
fi

# Step 5: Create symlinks
echo ""
echo "${CYAN}Step 5: Creating symlinks...${NC}"
echo ""
if ! "$DOTFILES_DIR/scripts/create-symlinks.sh"; then
    echo ""
    echo "${RED}Some symlinks failed. Check the output above.${NC}"
    if [[ $SKIP_BACKUP -eq 0 ]] && [[ -d "${BACKUP_DIR:-}" ]]; then
        echo ""
        echo "To restore your backup, run:"
        echo "  cp -r $BACKUP_DIR/* \$HOME/"
    fi
    exit 1
fi

# Step 6: Install plugin managers
echo ""
echo "${CYAN}Step 6: Installing plugin managers...${NC}"
echo ""

# TPM (Tmux Plugin Manager)
if [[ ! -d "$HOME/.tmux/plugins/tpm" ]]; then
    echo "Installing TPM..."
    git clone https://github.com/tmux-plugins/tpm "$HOME/.tmux/plugins/tpm"
    echo "${GREEN}TPM installed. Press prefix + I inside tmux to install plugins.${NC}"
else
    echo "TPM already installed."
fi

# lazy.nvim is auto-installed by Neovim config
echo "lazy.nvim will be auto-installed when you first open Neovim."

# Step 7: Create secrets file if needed
echo ""
echo "${CYAN}Step 7: Setting up secrets...${NC}"
echo ""
if [[ ! -f "$HOME/.zsh/.secrets.zsh" ]]; then
    if [[ -f "$DOTFILES_DIR/zsh/.zsh/.secrets.zsh.template" ]]; then
        cp "$DOTFILES_DIR/zsh/.zsh/.secrets.zsh.template" "$HOME/.zsh/.secrets.zsh"
        echo "${YELLOW}Created secrets file from template.${NC}"
        echo "Edit ~/.zsh/.secrets.zsh to add your API keys and tokens."
    else
        touch "$HOME/.zsh/.secrets.zsh"
        echo "${YELLOW}Created empty secrets file.${NC}"
    fi
else
    echo "Secrets file already exists."
fi

# Step 8: Run health check
echo ""
echo "${CYAN}Step 8: Running health check...${NC}"
echo ""
"$DOTFILES_DIR/scripts/health-check.sh" || true

# Done
echo ""
echo "${GREEN}╔════════════════════════════════════════════╗${NC}"
echo "${GREEN}║         Installation Complete!             ║${NC}"
echo "${GREEN}╚════════════════════════════════════════════╝${NC}"
echo ""
echo "Next steps:"
echo "  1. Restart your terminal or run: source ~/.zshrc"
echo "  2. Open tmux and press \` + I to install plugins"
echo "  3. Open Neovim to trigger lazy.nvim plugin installation"
echo "  4. Install Node.js: fnm install --lts && fnm default lts-latest"
echo "  5. Edit ~/.zsh/.secrets.zsh to add your API keys"
echo ""
if [[ $SKIP_BACKUP -eq 0 ]] && [[ -d "${BACKUP_DIR:-}" ]]; then
    echo "Backup location: $BACKUP_DIR"
    echo ""
fi
