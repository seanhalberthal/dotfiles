#!/usr/bin/env bash
set -euo pipefail

# Verify dotfiles installation is correct
# Checks symlinks, plugin managers, and basic functionality

DOTFILES_DIR="${DOTFILES_DIR:-$HOME/dotfiles}"

# Colours
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
NC='\033[0m'

ISSUES=0

check_symlink() {
    local link="$1"
    local target="$2"
    local name="$3"

    printf "Checking %-30s" "$name..."

    if [[ -L "$link" ]]; then
        local actual_target
        actual_target=$(readlink "$link")
        if [[ "$actual_target" == "$target" ]]; then
            printf "${GREEN}OK${NC}\n"
            return 0
        else
            printf "${YELLOW}WRONG TARGET${NC} (points to %s)\n" "$actual_target"
            ISSUES=1
            return 1
        fi
    elif [[ -e "$link" ]]; then
        printf "${RED}EXISTS BUT NOT SYMLINK${NC}\n"
        ISSUES=1
        return 1
    else
        printf "${RED}MISSING${NC}\n"
        ISSUES=1
        return 1
    fi
}

check_directory() {
    local dir="$1"
    local name="$2"

    printf "Checking %-30s" "$name..."

    if [[ -d "$dir" ]]; then
        printf "${GREEN}OK${NC}\n"
        return 0
    else
        printf "${RED}MISSING${NC}\n"
        ISSUES=1
        return 1
    fi
}

check_file() {
    local file="$1"
    local name="$2"

    printf "Checking %-30s" "$name..."

    if [[ -f "$file" ]]; then
        printf "${GREEN}OK${NC}\n"
        return 0
    else
        printf "${YELLOW}MISSING${NC}\n"
        return 1
    fi
}

echo "============================================"
echo "Dotfiles Health Check"
echo "============================================"
echo ""

echo "Symlinks:"
echo "---------"
check_symlink "$HOME/.zshrc" "$DOTFILES_DIR/zsh/.zshrc" ".zshrc"
check_symlink "$HOME/.zprofile" "$DOTFILES_DIR/zsh/.zprofile" ".zprofile"
check_symlink "$HOME/.p10k.zsh" "$DOTFILES_DIR/zsh/.p10k.zsh" ".p10k.zsh"
check_symlink "$HOME/.zsh" "$DOTFILES_DIR/zsh/.zsh" ".zsh"
check_symlink "$HOME/.tmux.conf" "$DOTFILES_DIR/tmux/.tmux.conf" ".tmux.conf"
check_symlink "$HOME/.tmux" "$DOTFILES_DIR/tmux/.tmux" ".tmux"
check_symlink "$HOME/.config/nvim" "$DOTFILES_DIR/nvim" "nvim config"
check_symlink "$HOME/.hammerspoon" "$DOTFILES_DIR/hammerspoon" "hammerspoon"
check_symlink "$HOME/.config/ghostty/config" "$DOTFILES_DIR/ghostty/config" "ghostty config"
check_symlink "$HOME/.config/karabiner/karabiner.json" "$DOTFILES_DIR/karabiner/karabiner.json" "karabiner config"

echo ""
echo "Plugin Managers:"
echo "----------------"
check_directory "$HOME/.tmux/plugins/tpm" "TPM (Tmux Plugin Manager)"
check_directory "$HOME/.local/share/nvim/lazy" "lazy.nvim (Neovim)"

echo ""
echo "Secrets:"
echo "--------"
check_file "$HOME/.zsh/.secrets.zsh" "Secrets file"

echo ""
echo "Custom Scripts:"
echo "---------------"
if command -v tm &>/dev/null; then
    printf "Checking %-30s${GREEN}OK${NC}\n" "tm command"
else
    printf "Checking %-30s${YELLOW}NOT IN PATH${NC}\n" "tm command"
    echo "  Add ~/.local/bin to your PATH"
fi

if command -v dana &>/dev/null; then
    printf "Checking %-30s${GREEN}OK${NC}\n" "dana command"
else
    printf "Checking %-30s${YELLOW}NOT IN PATH${NC}\n" "dana command"
    echo "  Add ~/.local/bin to your PATH"
fi

echo ""

if [[ $ISSUES -eq 0 ]]; then
    printf "${GREEN}All checks passed! Your dotfiles are correctly installed.${NC}\n"
    exit 0
else
    printf "${YELLOW}Some issues were found. See above for details.${NC}\n"
    exit 1
fi
