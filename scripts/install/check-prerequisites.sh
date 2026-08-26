#!/usr/bin/env bash
set -euo pipefail

# verify the two tools the install bootstrap needs: git and brew
# everything else is installed by `brew bundle` during install.sh

if [[ "${1:-}" == "--help" ]] || [[ "${1:-}" == "-h" ]]; then
    cat <<'EOF'
check-prerequisites.sh - Verify install bootstrap prerequisites

USAGE:
    ./scripts/install/check-prerequisites.sh

DESCRIPTION:
    Checks the two tools needed to bootstrap the install:
      • git  - to clone/update the repo
      • brew - to install everything in Brewfile

    Everything else (nvim, tmux, fzf, language toolchains, etc.) is
    installed by `brew bundle` during install.sh, so it's deliberately
    not checked here — gating on those would just produce false-MISSING
    noise on a fresh machine and duplicate what `brew bundle` will do
    moments later.

    Run health-check.sh after install if you want to verify the resulting
    toolchain.

OPTIONS:
    -h, --help   Show this help message

EXIT CODES:
    0 - git and brew are both present
    1 - one or both missing

SEE ALSO:
    ./install.sh                       Main installation script
    ./scripts/install/health-check.sh  Post-install verification
EOF
    exit 0
fi

SCRIPT_DIR="${BASH_SOURCE%/*}"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/../_lib/common.sh"

FAILED=0

print_section "Dotfiles Prerequisites Check"
echo ""

if is_macos; then
    git_hint="xcode-select --install"
else
    git_hint="install via your system package manager (apt/pacman/dnf/...)"
fi

check_command "git" "git" "$git_hint" || FAILED=1
check_command "Homebrew" "brew" "see https://brew.sh" || FAILED=1

echo ""

if [[ $FAILED -eq 0 ]]; then
    success "Bootstrap prerequisites present: install can proceed."
    exit 0
else
    error "Install git and brew, then re-run."
    exit 1
fi
