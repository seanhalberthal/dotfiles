# =============================================================================
# ZSH PROFILE (Login Shell Configuration)
# =============================================================================
# This file is sourced for LOGIN shells only (e.g., when opening a new
# terminal window or SSH session). Use this for:
#   - PATH additions that installers add automatically
#   - Environment setup that only needs to run once per session
#
# For interactive shell config (aliases, functions, prompt), use ~/.zshrc
#
# Load order: .zshenv → .zprofile (login) → .zshrc (interactive) → .zlogin

# JetBrains Toolbox CLI tools (added by Toolbox App installer)
export PATH="$PATH:/Users/bssmnt/Library/Application Support/JetBrains/Toolbox/scripts"

# Python pipx (added by pipx installer - 2025-07-15)
export PATH="$PATH:/Users/bssmnt/.local/bin"
