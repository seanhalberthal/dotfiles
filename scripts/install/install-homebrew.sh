#!/usr/bin/env bash
set -euo pipefail

# Install Homebrew if not present, update if already installed

SCRIPT_DIR="${BASH_SOURCE%/*}"
source "$SCRIPT_DIR/../_lib/common.sh"

print_section "Homebrew Setup"

HOMEBREW_PREFIX=$(get_homebrew_prefix)

# Check if Homebrew is installed
if command_exists brew; then
    success "Homebrew is already installed"
    echo ""

    info "Updating Homebrew..."
    brew update

    echo ""
    success "Homebrew updated successfully"
else
    warn "Homebrew not found. Installing..."
    echo ""

    # Check for Command Line Tools
    if ! xcode-select -p &>/dev/null; then
        warn "Installing Command Line Tools..."
        echo "A dialog may appear - please click 'Install' and wait for completion."
        xcode-select --install

        # Wait for installation with timeout
        echo ""
        echo "Waiting for Command Line Tools installation..."
        if ! read_with_timeout "Press Enter once the installation is complete: " _ 600; then
            error "Timed out waiting for Command Line Tools"
            exit 1
        fi
    fi

    # Install Homebrew
    info "Installing Homebrew..."
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

    # Add Homebrew to PATH for this session
    eval "$("$HOMEBREW_PREFIX/bin/brew" shellenv)"

    echo ""
    success "Homebrew installed successfully"
fi

# Verify installation
echo ""
echo "Homebrew version: $(brew --version | head -n1)"
echo "Homebrew prefix: $(brew --prefix)"

# Disable analytics (optional but recommended for privacy)
brew analytics off 2>/dev/null || true

echo ""
success "Homebrew setup complete"
