#!/usr/bin/env bash
set -euo pipefail

# Check all prerequisites for dotfiles installation
# Returns 0 if all checks pass, 1 otherwise

# Colours
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'

FAILED=0

check() {
    local name="$1"
    local cmd="$2"
    local install_hint="${3:-}"

    printf "Checking %-20s" "$name..."

    if command -v "$cmd" &>/dev/null; then
        printf "${GREEN}OK${NC}\n"
        return 0
    else
        printf "${RED}MISSING${NC}\n"
        if [[ -n "$install_hint" ]]; then
            printf "  ${YELLOW}Install with:${NC} %s\n" "$install_hint"
        fi
        FAILED=1
        return 1
    fi
}

check_optional() {
    local name="$1"
    local cmd="$2"
    local install_hint="${3:-}"

    printf "Checking %-20s" "$name (optional)..."

    if command -v "$cmd" &>/dev/null; then
        printf "${GREEN}OK${NC}\n"
    else
        printf "${YELLOW}MISSING${NC}\n"
        if [[ -n "$install_hint" ]]; then
            printf "  ${YELLOW}Install with:${NC} %s\n" "$install_hint"
        fi
    fi
}

echo "============================================"
echo "Dotfiles Prerequisites Check"
echo "============================================"
echo ""

echo "Required - Core Tools:"
echo "----------------------"
check "git" "git" "xcode-select --install"
check "zsh" "zsh" "brew install zsh"
check "tmux" "tmux" "brew install tmux"
check "neovim" "nvim" "brew install neovim"
check "fzf" "fzf" "brew install fzf"
check "bun" "bun" "brew install bun"
check "ghostty" "ghostty" "brew install --cask ghostty"
check "go" "go" "brew install go"
check "ripgrep" "rg" "brew install ripgrep"
check "lazygit" "lazygit" "brew install lazygit"
check "gh" "gh" "brew install gh"
check "direnv" "direnv" "brew install direnv"
check "jq" "jq" "brew install jq"
check "tree" "tree" "brew install tree"
check "shellcheck" "shellcheck" "brew install shellcheck"

echo ""
echo "Required - AI & Dev Tools:"
echo "--------------------------"
check "claude" "claude" "brew install --cask claude-code"
check "dotnet" "dotnet" "brew install --cask dotnet-sdk"
check "act" "act" "brew install act"
check "cmake" "cmake" "brew install cmake"
check "staticcheck" "staticcheck" "brew install staticcheck"
check "swift-format" "swift-format" "brew install swift-format"
check "golang-migrate" "migrate" "brew install golang-migrate"

echo ""
echo "Required - Databases:"
echo "---------------------"
check "postgresql" "psql" "brew install postgresql@14"
check "mongosh" "mongosh" "brew install mongosh"
check "turso" "turso" "brew install turso"
check "sqld" "sqld" "brew install sqld"

echo ""
echo "Required - Utilities:"
echo "---------------------"
check "neofetch" "neofetch" "brew install neofetch"
check "speedtest" "speedtest" "brew install speedtest"
check "glow" "glow" "brew install glow"

echo ""
echo "Required - macOS Apps:"
echo "----------------------"
# Karabiner is checked via app existence since CLI isn't in PATH
printf "Checking %-20s" "karabiner..."
if [[ -d "/Applications/Karabiner-Elements.app" ]]; then
    printf "${GREEN}OK${NC}\n"
else
    printf "${RED}MISSING${NC}\n"
    printf "  ${YELLOW}Install with:${NC} brew install --cask karabiner-elements\n"
    FAILED=1
fi

echo ""
echo "Optional tools:"
echo "---------------"
check_optional "fnm" "fnm" "brew install fnm"
check_optional "python" "python3" "brew install python"
check_optional "gcloud" "gcloud" "brew install --cask google-cloud-sdk"
check_optional "hammerspoon" "hs" "brew install --cask hammerspoon"
check_optional "fd" "fd" "brew install fd"
check_optional "bat" "bat" "brew install bat"

echo ""

if [[ $FAILED -eq 0 ]]; then
    printf "${GREEN}All required prerequisites are installed!${NC}\n"
    exit 0
else
    printf "${RED}Some required tools are missing. Please install them before continuing.${NC}\n"
    exit 1
fi
