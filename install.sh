#!/usr/bin/env bash
# shellcheck disable=SC1091
set -euo pipefail

# dotfiles installation script
# usage: ./install.sh [--minimal|--core|--full] [OPTIONS]

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export DOTFILES_DIR

# source shared utilities
source "$DOTFILES_DIR/scripts/_lib/common.sh"
source "$DOTFILES_DIR/scripts/_lib/rollback.sh"

# preset definitions:
#   minimal - zsh + tmux only (servers, remote machines)
#   core    - minimal + nvim + ghostty + AI/CLI tools + session launch scripts (cross-platform dev)
#   full    - core + Hammerspoon + Karabiner (macOS power user)

# error handler for automatic rollback
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

# set up error trap
trap 'on_error $LINENO' ERR

# parse arguments
SKIP_BACKUP=0
SKIP_BREW=0
CHECK_ONLY=0
NO_LOGO=0
UPDATE_MODE=0
AUTO_YES=0
SKIP_STEPS=""
PRESET="full"  # default preset

while [[ $# -gt 0 ]]; do
    case "$1" in
        --minimal)
            PRESET="minimal"
            shift
            ;;
        --core)
            PRESET="core"
            shift
            ;;
        --full)
            PRESET="full"
            shift
            ;;
        --skip-backup)
            SKIP_BACKUP=1
            shift
            ;;
        --skip-brew)
            SKIP_BREW=1
            shift
            ;;
        --skip-steps)
            SKIP_STEPS="$2"
            shift 2
            ;;
        --check-only)
            CHECK_ONLY=1
            shift
            ;;
        --no-logo)
            NO_LOGO=1
            shift
            ;;
        --update)
            UPDATE_MODE=1
            NO_LOGO=1
            shift
            ;;
        --yes|-y)
            AUTO_YES=1
            shift
            ;;
        -h|--help)
            echo "Usage: ./install.sh [PRESET] [OPTIONS]"
            echo ""
            echo "Presets (pick one; default --full):"
            echo "  --minimal        Install zsh + tmux only (servers, remote machines)"
            echo "  --core           Install zsh, tmux, nvim, ghostty, CLI/AI tools"
            echo "  --full           Install everything including macOS apps (default)"
            echo ""
            echo "Options:"
            echo "  --skip-backup    Skip backing up existing config files"
            echo "  --skip-brew      Skip Homebrew installation and packages"
            echo "  --skip-steps L   Skip comma-separated list of steps"
            echo "                   (homebrew,packages,symlinks,keyd)"
            echo "  --check-only     Only run prerequisite and health checks"
            echo "  --update         Update mode (skips logo, uses update terminology)"
            echo "  --yes, -y        Skip confirmation prompt"
            echo "  -h, --help       Show this help message"
            echo ""
            echo "Examples:"
            echo "  ./install.sh                          # Full installation (default)"
            echo "  ./install.sh --core                   # Cross-platform dev setup"
            echo "  ./install.sh --minimal                # Lightweight server setup"
            echo ""
            echo "To rollback a failed installation:"
            echo "  ./scripts/install/rollback.sh"
            exit 0
            ;;
        -*)
            error "Unknown option: $1"
            echo "Run './install.sh --help' for usage."
            exit 1
            ;;
        *)
            error "Unexpected argument: $1"
            echo "Run './install.sh --help' for usage."
            exit 1
            ;;
    esac
done

# validate --skip-steps against known step names
if [[ -n "$SKIP_STEPS" ]]; then
    VALID_STEPS="homebrew,packages,symlinks,keyd"
    IFS=',' read -ra _skip_arr <<< "$SKIP_STEPS"
    for _step in "${_skip_arr[@]}"; do
        if [[ ",$VALID_STEPS," != *",$_step,"* ]]; then
            error "Unknown step name in --skip-steps: $_step"
            echo "Valid steps: $VALID_STEPS"
            exit 1
        fi
    done
    unset _skip_arr _step
fi

# check if a step should be skipped (by name)
is_step_skipped() {
    local step_name="$1"
    [[ ",$SKIP_STEPS," == *",$step_name,"* ]]
}

# validate preset value
case "$PRESET" in
    minimal|core|full)
        # valid preset
        ;;
    *)
        error "Invalid preset: $PRESET"
        echo "Valid presets are: minimal, core, full"
        exit 1
        ;;
esac

# export preset for sub-scripts
export DOTFILES_PRESET="$PRESET"

# step labels: update mode uses shorter verbs since the header already says "Applying Updates"
if [[ $UPDATE_MODE -eq 1 ]]; then
    STEP1_LABEL="Checking Homebrew..."
    STEP2_LABEL="Updating packages..."
    STEP5_LABEL="Updating symlinks..."
    STEP7_LABEL="Updating keyd configuration..."
else
    STEP1_LABEL="Setting up Homebrew..."
    STEP2_LABEL="Installing packages from Brewfile..."
    STEP5_LABEL="Creating symlinks..."
    STEP7_LABEL="Setting up keyd (keyboard remapping)..."
fi

# initialise rollback state
init_rollback_state

[[ $NO_LOGO -eq 0 ]] && print_logo

if [[ $UPDATE_MODE -eq 1 ]]; then
    print_header "Applying Updates"
else
    print_header "Dotfiles Installation"
    echo "Dotfiles directory: $DOTFILES_DIR"
    echo ""
fi

# display preset info and confirmation
echo "Selected preset: ${CYAN}${PRESET}${NC}"
if [[ $UPDATE_MODE -eq 0 ]]; then
    case "$PRESET" in
        minimal)
            echo "Components: zsh, tmux"
            ;;
        core)
            echo "Components: zsh, tmux, nvim, ghostty, AI/CLI tools, session launch scripts"
            ;;
        full)
            if is_macos; then
                echo "Components: Everything (core + Hammerspoon, Karabiner)"
            else
                echo "Components: Everything (core + keyd keyboard remapping)"
            fi
            ;;
    esac
fi
echo ""

# confirmation prompt (skipped in update mode or with --yes)
if [[ $AUTO_YES -eq 0 ]]; then
    if [[ -t 0 ]]; then
        printf 'Proceed with %s%s%s installation? [y/N] ' "${CYAN}" "${PRESET}" "${NC}"
        read -r response
    else
        error "Non-interactive shell detected. Cannot prompt for confirmation."
        info "Re-run with a TTY or pipe 'yes' to confirm."
        exit 1
    fi
    case "$response" in
        [yY][eE][sS]|[yY])
            echo ""
            ;;
        *)
            echo ""
            info "Installation cancelled."
            exit 0
            ;;
    esac
fi

# step 1: install/update Homebrew
if [[ $SKIP_BREW -eq 0 && $CHECK_ONLY -eq 0 ]] && ! is_step_skipped "homebrew"; then
    print_step 1 "$STEP1_LABEL"
    "$DOTFILES_DIR/scripts/install/install-homebrew.sh"
    record_step "homebrew"

    # ensure Homebrew is in PATH for subsequent steps
    # (the install script runs in a subshell, so PATH changes don't propagate)
    HOMEBREW_PREFIX=$(get_homebrew_prefix)
    if [[ -x "$HOMEBREW_PREFIX/bin/brew" ]]; then
        eval "$("$HOMEBREW_PREFIX/bin/brew" shellenv)"
    fi
    echo ""
else
    if [[ $CHECK_ONLY -eq 1 ]]; then
        print_skip 1 "Homebrew setup" "--check-only"
    elif is_step_skipped "homebrew"; then
        print_skip 1 "Homebrew" "unchanged"
    else
        print_skip 1 "Homebrew setup" "--skip-brew flag"
    fi
fi

# step 2: install packages from Brewfile
if [[ $SKIP_BREW -eq 0 && $CHECK_ONLY -eq 0 ]] && ! is_step_skipped "packages"; then
    print_step 2 "$STEP2_LABEL"
    "$DOTFILES_DIR/scripts/install/install-packages.sh"
    record_step "packages"
    echo ""
else
    if [[ $CHECK_ONLY -eq 1 ]]; then
        print_skip 2 "package installation" "--check-only"
    elif is_step_skipped "packages"; then
        print_skip 2 "packages" "unchanged"
    else
        print_skip 2 "package installation" "--skip-brew flag"
    fi
fi

# step 3: check prerequisites
print_step 3 "Checking prerequisites..."
if ! "$DOTFILES_DIR/scripts/install/check-prerequisites.sh"; then
    echo ""
    error "Some required tools are missing."
    if [[ $CHECK_ONLY -eq 1 ]]; then
        echo "Run './install.sh --core' to install them."
    elif [[ $SKIP_BREW -eq 1 ]]; then
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

# step 4: backup existing files
echo ""
if [[ $SKIP_BACKUP -eq 0 ]]; then
    print_step 4 "Backing up existing configuration..."
    BACKUP_DIR=$("$DOTFILES_DIR/scripts/install/backup-existing.sh" | tail -n1)
    record_step "backup"
else
    print_skip 4 "backup" "--skip-backup flag"
fi

# step 5: create symlinks
echo ""
if ! is_step_skipped "symlinks"; then
    print_step 5 "$STEP5_LABEL"
    if ! "$DOTFILES_DIR/scripts/install/create-symlinks.sh"; then
        echo ""
        error "Some symlinks failed. Check the output above."
        echo ""
        echo "To rollback, run: ./scripts/install/rollback.sh"
        exit 1
    fi
    record_step "symlinks"
else
    print_skip 5 "symlinks" "unchanged"
fi

# step 6: install plugin managers
echo ""
print_step 6 "Installing plugin managers..."

# TPM (tmux plugin manager), all presets
if [[ ! -d "$HOME/.tmux/plugins/tpm" ]]; then
    echo "Installing TPM..."
    if git clone --branch v3.1.0 --depth 1 https://github.com/tmux-plugins/tpm "$HOME/.tmux/plugins/tpm"; then
        success "TPM installed. Press prefix + I inside tmux to install plugins."
    else
        warn "Failed to clone TPM (network issue?). Tmux plugins won't be available."
        warn "Install manually: git clone https://github.com/tmux-plugins/tpm ~/.tmux/plugins/tpm"
    fi
else
    echo "TPM already installed."
fi
record_step "plugin-managers"

# lazy.nvim is auto-installed by nvim config (core preset and above)
if [[ "$PRESET" == "core" || "$PRESET" == "full" ]]; then
    echo "lazy.nvim will be auto-installed when you first open Neovim."
fi

# step 7: setup keyd (Linux keyboard remapping, equivalent of Karabiner)
if is_linux && should_install "full" && ! is_step_skipped "keyd"; then
    echo ""
    print_step 7 "$STEP7_LABEL"
    "$DOTFILES_DIR/scripts/install/setup-keyd.sh"
    record_step "keyd"
else
    if is_step_skipped "keyd"; then
        print_skip 7 "keyd" "unchanged"
    elif is_macos; then
        print_skip 7 "keyd setup" "macOS (using Karabiner)"
    else
        print_skip 7 "keyd setup" "not included in $PRESET preset"
    fi
fi

# step 8: set default shell to zsh
echo ""
print_step 8 "Setting default shell..."
"$DOTFILES_DIR/scripts/install/set-default-shell.sh"
record_step "default-shell"

# step 9: set default apps (macOS: route code files to Zed)
echo ""
if is_macos; then
    print_step 9 "Setting default apps..."
    "$DOTFILES_DIR/scripts/install/set-default-apps.sh"
    record_step "default-apps"
else
    print_skip 9 "default apps" "macOS only"
fi

# step 10: create secrets file if needed
echo ""
print_step 10 "Setting up secrets..."
SECRETS_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/zsh"
mkdir -p "$SECRETS_DIR"

if [[ ! -f "$SECRETS_DIR/secrets.zsh" ]]; then
    if [[ -f "$DOTFILES_DIR/zsh/secrets.zsh.template" ]]; then
        cp "$DOTFILES_DIR/zsh/secrets.zsh.template" "$SECRETS_DIR/secrets.zsh"
        chmod 600 "$SECRETS_DIR/secrets.zsh"
        warn "Created secrets file from template."
        echo "Edit $SECRETS_DIR/secrets.zsh to add your API keys and tokens."
    else
        # create secrets file with restrictive permissions from the start
        (
            umask 077
            touch "$SECRETS_DIR/secrets.zsh"
        )
        chmod 600 "$SECRETS_DIR/secrets.zsh"  # belt and suspenders
        warn "Created empty secrets file."
    fi
else
    echo "Secrets file already exists."
fi
record_step "secrets"

# step 11: run health check
echo ""
print_step 11 "Running health check..."
if "$DOTFILES_DIR/scripts/install/health-check.sh"; then
    success "Health check passed"
else
    warn "Health check reported issues (see above). Installation completed with warnings."
fi
record_step "health-check"

# step 12: save preset for future updates
echo ""
print_step 12 "Saving preset configuration..."
PRESET_CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/dotfiles"
mkdir -p "$PRESET_CONFIG_DIR"
echo "$PRESET" > "$PRESET_CONFIG_DIR/preset"
success "Preset '$PRESET' saved to $PRESET_CONFIG_DIR/preset"
record_step "save-preset"

# step 13: configure project directories (optional)
echo ""
print_step 13 "Project directories (optional)..."

state_dir="$PRESET_CONFIG_DIR/.state"
dirs_asked_file="$state_dir/prompted"

if grep -q '^export DEV_ROOT=' "$HOME/.zshrc" 2>/dev/null; then
    success "DEV_ROOT already configured"
elif [[ -f "$dirs_asked_file" ]]; then
    success "DEV_ROOT skipped (set later with: dotfiles set dev <path>)"
elif [[ -t 0 ]]; then
    info "DEV_ROOT sets your main development directory for the launcher picker."
    printf '  Default: %s\n' "$HOME/src"
    printf '  Enter path (or press Enter for default, "skip" to skip): '
    read -r dev_root_input
    case "$dev_root_input" in
        skip|s)
            info "Skipped. Set later with: dotfiles set dev <path>"
            ;;
        "")
            dev_root_input="$HOME/src"
            update_zshrc_export "DEV_ROOT" "$dev_root_input"
            mkdir -p "$dev_root_input"
            success "DEV_ROOT set to $dev_root_input"
            ;;
        *)
            dev_root_input="${dev_root_input/#\~/$HOME}"
            update_zshrc_export "DEV_ROOT" "$dev_root_input"
            mkdir -p "$dev_root_input"
            success "DEV_ROOT set to $dev_root_input"
            ;;
    esac
fi

if grep -q '^export PROJECTS_ROOT=' "$HOME/.zshrc" 2>/dev/null; then
    success "PROJECTS_ROOT already configured"
elif [[ -f "$dirs_asked_file" ]]; then
    success "PROJECTS_ROOT skipped (set later with: dotfiles set projects <path>)"
elif [[ -t 0 ]]; then
    info "PROJECTS_ROOT sets a secondary directory (side projects, playground, etc.)."
    printf '  Enter path (or press Enter to skip): '
    read -r projects_root_input
    case "$projects_root_input" in
        ""|skip|s)
            info "Skipped. Set later with: dotfiles set projects <path>"
            ;;
        *)
            projects_root_input="${projects_root_input/#\~/$HOME}"
            update_zshrc_export "PROJECTS_ROOT" "$projects_root_input"
            mkdir -p "$projects_root_input"
            success "PROJECTS_ROOT set to $projects_root_input"
            ;;
    esac
fi

# mark that we've asked about project directories
mkdir -p "$(dirname "$dirs_asked_file")"
touch "$dirs_asked_file"

record_step "project-dirs"

# step 14: import local layer (only when a private local-layer repo is
# configured; see `dotfiles help local`). runs after the preset save so the
# manifest gating reads the fresh preset. unconfigured machines skip
# silently, but a repo already cloned to the default location is adopted
# so "clone dotfiles-local, then install" needs no extra configuration
LOCAL_PTR="${XDG_CONFIG_HOME:-$HOME/.config}/dotfiles/local-repo"
DEFAULT_LOCAL_DIR="$HOME/.dotfiles-local"
LOCAL_ADOPTED=0
if [[ -z "${DOTFILES_LOCAL_DIR:-}" && ! -f "$LOCAL_PTR" ]] \
    && git -C "$DEFAULT_LOCAL_DIR" rev-parse --git-dir &>/dev/null; then
    mkdir -p "$(dirname "$LOCAL_PTR")"
    printf '%s\n' "$DEFAULT_LOCAL_DIR" > "$LOCAL_PTR"
    LOCAL_ADOPTED=1
fi
if [[ -n "${DOTFILES_LOCAL_DIR:-}" || -f "$LOCAL_PTR" ]]; then
    echo ""
    print_step 14 "Importing local layer..."
    if [[ $LOCAL_ADOPTED -eq 1 ]]; then
        info "Found local layer repo at $DEFAULT_LOCAL_DIR, registered it"
    fi
    "$DOTFILES_DIR/scripts/dotfiles" import \
        || warn "Local layer import reported issues (non-fatal)"
    record_step "local-import"
fi

# clean up rollback state on success. everything below this point is
# reporting, so the last mutating step has already succeeded
cleanup_rollback_state

# detect what's already configured to tailor next steps
has_tmux_plugins=false
has_lazy_nvim=false
has_node=false
has_secrets_content=false
has_dev_root=false
has_projects_root=false
has_p10k=false

# tmux plugins already installed?
if [[ -d "$HOME/.tmux/plugins/tmux-resurrect" ]]; then
    has_tmux_plugins=true
fi

# nvim lazy.nvim packages populated?
if [[ -d "$HOME/.local/share/nvim/lazy" ]]; then
    lazy_count=$(find "$HOME/.local/share/nvim/lazy" -maxdepth 1 -mindepth 1 -type d 2>/dev/null | wc -l)
    if [[ "$lazy_count" -gt 1 ]]; then
        has_lazy_nvim=true
    fi
fi

# Node.js available?
if command -v node &>/dev/null; then
    has_node=true
fi

# secrets file has real content (not just template comments)?
secrets_file="${XDG_CONFIG_HOME:-$HOME/.config}/zsh/secrets.zsh"
if [[ -f "$secrets_file" ]] && grep -q '^export ' "$secrets_file" 2>/dev/null; then
    has_secrets_content=true
fi

# Powerlevel10k configured?
if [[ -f "$HOME/.p10k.zsh" ]]; then
    has_p10k=true
fi

# project directories configured?
if grep -q '^export DEV_ROOT=' "$HOME/.zshrc" 2>/dev/null; then
    has_dev_root=true
fi
if grep -q '^export PROJECTS_ROOT=' "$HOME/.zshrc" 2>/dev/null; then
    has_projects_root=true
fi

# done
[[ $NO_LOGO -eq 0 ]] && print_logo

if [[ $UPDATE_MODE -eq 1 ]]; then
    print_header "Update Complete!"
else
    print_header "Installation Complete!"
fi

echo "Preset: $PRESET"
echo ""

# collect next steps into an array, only including relevant ones
STEPS=()

if [[ $UPDATE_MODE -eq 0 ]]; then
    STEPS+=("Restart your terminal or run: source ~/.zshrc")
fi

if [[ "$has_tmux_plugins" == false ]]; then
    STEPS+=("Open tmux and press \` + I to install plugins")
fi

if [[ "$PRESET" == "core" || "$PRESET" == "full" ]] && [[ "$has_lazy_nvim" == false ]]; then
    STEPS+=("Open Neovim to trigger lazy.nvim plugin installation")
fi

if [[ "$PRESET" == "core" || "$PRESET" == "full" ]] && [[ "$has_node" == false ]]; then
    STEPS+=("Install Node.js: fnm install --lts && fnm default lts-latest")
fi

if [[ "$has_p10k" == false ]]; then
    STEPS+=("Configure your prompt: p10k configure")
fi

if [[ "$has_secrets_content" == false ]]; then
    STEPS+=("Edit ~/.config/zsh/secrets.zsh to add your API keys")
fi

if [[ "$has_dev_root" == false ]] || [[ "$has_projects_root" == false ]]; then
    STEPS+=("Configure project directories: dotfiles set dev <path>")
fi

if [[ -z "${DOTFILES_LOCAL_DIR:-}" && ! -f "$LOCAL_PTR" ]]; then
    STEPS+=("Optional: sync personal config across machines: dotfiles local init | clone <url>")
fi

# local overrides: only show files relevant to the preset
local_overrides=""
if [[ "$PRESET" == "core" || "$PRESET" == "full" ]]; then
    local_overrides+="       ~/.config/nvim/local.lua       → Neovim options, keymaps, cursor style\n"
    local_overrides+="       ~/.config/ghostty/local        → Ghostty font/window overrides\n"
fi
local_overrides+="       ~/.config/tmux/local.conf      → Extra tmux settings"
STEPS+=("Personalise with local override files (never overwritten by updates):\n${local_overrides}")

# print numbered steps
if [[ ${#STEPS[@]} -gt 0 ]]; then
    echo "Next steps:"
    for i in "${!STEPS[@]}"; do
        printf "  %d. %b\n" "$((i + 1))" "${STEPS[$i]}"
    done
    echo ""
fi

if [[ $SKIP_BACKUP -eq 0 ]] && [[ -d "${BACKUP_DIR:-}" ]]; then
    echo "Backup location: $BACKUP_DIR"
    echo ""
fi

# when nearly everything is already done, show a positive message
if [[ ${#STEPS[@]} -le 2 ]]; then
    if [[ $UPDATE_MODE -eq 1 ]]; then
        success "Update applied successfully!"
    else
        success "Everything looks good — you're all set!"
    fi
fi

# post-update notices left by migrations. install.sh is invoked fresh
# from disk after `dotfiles update` pulls, so this path is the new
# version even on the upgrade hop where the running `dotfiles`
# dispatcher is still the pre-pull copy parsed in memory. the
# cmd_update dispatcher also calls a notice helper as a safety net
# for the "already up-to-date" branch on subsequent runs; this clears
# the file so it doesn't double-print
notice_file="${XDG_CONFIG_HOME:-$HOME/.config}/dotfiles/.state/update-notices.txt"
if [[ -s "$notice_file" ]]; then
    echo ""
    printf "%sNotices from this update:%s\n" "${YELLOW:-}" "${NC:-}"
    sed 's/^/  /' "$notice_file"
    rm -f "$notice_file"
fi

# stamp the last install/update time. reaching here means the apply succeeded.
# `dotfiles update` early-returns before invoking install.sh when nothing is to
# be applied, so this only advances on a real install or update. read back by
# `dotfiles version`/`status` as the "Updated" field (UPDATE_STAMP_FILE in cli.sh)
update_stamp_dir="${XDG_CONFIG_HOME:-$HOME/.config}/dotfiles/.state"
mkdir -p "$update_stamp_dir"
date '+%Y-%m-%d %H:%M' > "$update_stamp_dir/last-update"
