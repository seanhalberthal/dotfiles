#!/usr/bin/env bash
set -euo pipefail

# Install Homebrew if not present, update if already installed

# Colours
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'

echo "============================================"
echo "Homebrew Setup"
echo "============================================"
echo ""

# Check for Apple Silicon vs Intel
if [[ "$(uname -m)" == "arm64" ]]; then
    HOMEBREW_PREFIX="/opt/homebrew"
else
    HOMEBREW_PREFIX="/usr/local"
fi

# Check if Homebrew is installed
if command -v brew &>/dev/null; then
    echo "${GREEN}Homebrew is already installed${NC}"
    echo ""

    # Update Homebrew
    echo "Updating Homebrew..."
    brew update

    echo ""
    echo "${GREEN}Homebrew updated successfully${NC}"
else
    echo "${YELLOW}Homebrew not found. Installing...${NC}"
    echo ""

    # Check for Command Line Tools
    if ! xcode-select -p &>/dev/null; then
        echo "${YELLOW}Installing Command Line Tools...${NC}"
        echo "A dialog may appear - please click 'Install' and wait for completion."
        xcode-select --install

        # Wait for installation
        echo ""
        echo "Waiting for Command Line Tools installation..."
        echo "Press Enter once the installation is complete."
        read -r
    fi

    # Install Homebrew
    echo "Installing Homebrew..."
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

    # Add Homebrew to PATH for this session
    eval "$("$HOMEBREW_PREFIX/bin/brew" shellenv)"

    echo ""
    echo "${GREEN}Homebrew installed successfully${NC}"
fi

# Verify installation
echo ""
echo "Homebrew version: $(brew --version | head -n1)"
echo "Homebrew prefix: $(brew --prefix)"

# Disable analytics (optional but recommended for privacy)
brew analytics off 2>/dev/null || true

echo ""
echo "${GREEN}Homebrew setup complete${NC}"
