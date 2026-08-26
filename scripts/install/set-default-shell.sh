#!/usr/bin/env bash
set -euo pipefail

# set default shell to zsh

SCRIPT_DIR="${BASH_SOURCE%/*}"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/../_lib/common.sh"

ZSH_PATH="$(command -v zsh 2>/dev/null || true)"

if [[ -z "$ZSH_PATH" ]]; then
    warn "zsh not found in PATH. Install zsh first."
    exit 0
fi

if [[ "$SHELL" == *zsh ]]; then
    echo "Default shell is already zsh."
    exit 0
fi

echo "Changing default shell to zsh ($ZSH_PATH)..."

# ensure zsh is in /etc/shells (required by chsh on most systems).
# don't suppress sudo's stderr: the password prompt must be visible or this
# silently blocks waiting for input.
if [[ -f /etc/shells ]] && ! grep -qx "$ZSH_PATH" /etc/shells 2>/dev/null; then
    echo "Adding $ZSH_PATH to /etc/shells (may require sudo password)..."
    echo "$ZSH_PATH" | sudo tee -a /etc/shells >/dev/null ||
        warn "Could not add zsh to /etc/shells"
fi

# chsh prompts for your login password via PAM (written to stderr). Never
# redirect stderr here: doing so hides the prompt and makes the step look
# frozen while it waits for input.
info "chsh may prompt for your login password..."
if chsh -s "$ZSH_PATH"; then
    success "Default shell changed to zsh"
else
    warn "Could not change default shell automatically."
    echo "Run manually: chsh -s $ZSH_PATH"
fi
