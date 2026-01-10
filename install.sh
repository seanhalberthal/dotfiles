#!/usr/bin/env bash
# shellcheck disable=SC1091
set -euo pipefail

# Dotfiles installation script
# Usage: ./install.sh [--skip-backup] [--skip-brew] [--check-only]

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export DOTFILES_DIR

# Source shared utilities
source "$DOTFILES_DIR/scripts/_lib/common.sh"
source "$DOTFILES_DIR/scripts/_lib/rollback.sh"

# Error handler for automatic rollback
on_error() {
    local exit_code=$?
    local line_no=$1

    echo ""
    error "Installation failed at line $line_no (exit code: $exit_code)"
    echo ""

    if has_rollback_state; then
        warn "Installation state detected. You can rollback with:"
        echo "  ./scripts/install/rollback.sh"
        echo ""
        echo "Or to manually restore your backup:"
        backup_dir=$(get_backup_location)
        if [[ -n "$backup_dir" ]] && [[ -d "$backup_dir" ]]; then
            echo "  cp -r $backup_dir/* \$HOME/"
        fi
    fi

    exit $exit_code
}

# Set up error trap
trap 'on_error $LINENO' ERR

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
            echo ""
            echo "To rollback a failed installation:"
            echo "  ./scripts/install/rollback.sh"
            exit 0
            ;;
        *)
            error "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Initialise rollback state
init_rollback_state

print_header "Dotfiles Installation"
echo "Dotfiles directory: $DOTFILES_DIR"
echo ""

# Step 1: Install/Update Homebrew
if [[ $SKIP_BREW -eq 0 ]]; then
    print_step 1 "Setting up Homebrew..."
    "$DOTFILES_DIR/scripts/install/install-homebrew.sh"
    record_step "homebrew"
    echo ""
else
    print_skip 1 "Homebrew setup" "--skip-brew flag"
fi

# Step 2: Install packages from Brewfile
if [[ $SKIP_BREW -eq 0 ]]; then
    print_step 2 "Installing packages from Brewfile..."
    "$DOTFILES_DIR/scripts/install/install-packages.sh"
    record_step "packages"
    echo ""
else
    print_skip 2 "package installation" "--skip-brew flag"
fi

# Step 3: Check prerequisites
print_step 3 "Checking prerequisites..."
if ! "$DOTFILES_DIR/scripts/install/check-prerequisites.sh"; then
    echo ""
    error "Some required tools are missing."
    if [[ $SKIP_BREW -eq 1 ]]; then
        echo "Try running without --skip-brew to install missing packages."
    fi
    exit 1
fi
record_step "prerequisites"

if [[ $CHECK_ONLY -eq 1 ]]; then
    echo ""
    info "Running health check..."
    echo ""
    "$DOTFILES_DIR/scripts/install/health-check.sh" || true
    cleanup_rollback_state
    exit 0
fi

# Step 4: Backup existing files
echo ""
if [[ $SKIP_BACKUP -eq 0 ]]; then
    print_step 4 "Backing up existing configuration..."
    BACKUP_DIR=$("$DOTFILES_DIR/scripts/install/backup-existing.sh" | tail -n1)
    record_step "backup"
else
    print_skip 4 "backup" "--skip-backup flag"
fi

# Step 5: Create symlinks
echo ""
print_step 5 "Creating symlinks..."
if ! "$DOTFILES_DIR/scripts/install/create-symlinks.sh"; then
    echo ""
    error "Some symlinks failed. Check the output above."
    echo ""
    echo "To rollback, run: ./scripts/install/rollback.sh"
    exit 1
fi
record_step "symlinks"

# Step 6: Install plugin managers
echo ""
print_step 6 "Installing plugin managers..."

# TPM (Tmux Plugin Manager)
if [[ ! -d "$HOME/.tmux/plugins/tpm" ]]; then
    echo "Installing TPM..."
    git clone https://github.com/tmux-plugins/tpm "$HOME/.tmux/plugins/tpm"
    success "TPM installed. Press prefix + I inside tmux to install plugins."
else
    echo "TPM already installed."
fi
record_step "plugin-managers"

# lazy.nvim is auto-installed by Neovim config
echo "lazy.nvim will be auto-installed when you first open Neovim."

# Step 7: Create secrets file if needed
echo ""
print_step 7 "Setting up secrets..."
if [[ ! -f "$HOME/.zsh/.secrets.zsh" ]]; then
    if [[ -f "$DOTFILES_DIR/zsh/.zsh/.secrets.zsh.template" ]]; then
        cp "$DOTFILES_DIR/zsh/.zsh/.secrets.zsh.template" "$HOME/.zsh/.secrets.zsh"
        chmod 600 "$HOME/.zsh/.secrets.zsh"
        warn "Created secrets file from template."
        echo "Edit ~/.zsh/.secrets.zsh to add your API keys and tokens."
    else
        touch "$HOME/.zsh/.secrets.zsh"
        chmod 600 "$HOME/.zsh/.secrets.zsh"
        warn "Created empty secrets file."
    fi
else
    echo "Secrets file already exists."
fi
record_step "secrets"

# Step 8: Run health check
echo ""
print_step 8 "Running health check..."
"$DOTFILES_DIR/scripts/install/health-check.sh" || true
record_step "health-check"

# Clean up rollback state on success
cleanup_rollback_state

# Done
print_header "Installation Complete!"

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
