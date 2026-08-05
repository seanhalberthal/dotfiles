#!/usr/bin/env bash
set -euo pipefail

# verify dotfiles installation is correct
# checks symlinks, plugin managers, and basic functionality

# help flag handling
if [[ "${1:-}" == "--help" ]] || [[ "${1:-}" == "-h" ]]; then
    cat << 'EOF'
health-check.sh - Dotfiles installation health check

USAGE:
    ./scripts/install/health-check.sh

DESCRIPTION:
    Runs comprehensive health checks on the dotfiles installation:
      • Verifies all symlinks point to correct locations
      • Validates generated configs exist (tmux, ghostty, gh-dash, theme)
      • Checks plugin managers and TPM-managed plugins
      • Validates secrets file exists
      • Checks alert system hooks are executable
      • Reports local override file status
      • Tests custom scripts and tools are in PATH

OPTIONS:
    -h, --help   Show this help message

EXAMPLES:
    # Run health check from dotfiles root
    ./scripts/install/health-check.sh

    # Run from anywhere (if in PATH)
    health-check.sh

OUTPUT:
    Displays status for each check:
      ✓ Check passed (green OK)
      ✗ Check failed (red MISSING or WRONG TARGET)

    Exit code 0 if all checks pass, non-zero otherwise.

SEE ALSO:
    ./install.sh --check-only    Dry-run installation without changes
    ./scripts/install/rollback.sh  Restore backup if issues found
EOF
    exit 0
fi

SCRIPT_DIR="${BASH_SOURCE%/*}"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/../_lib/common.sh"

# derive DOTFILES_DIR from script location if not set
if [[ -z "${DOTFILES_DIR:-}" ]]; then
    DOTFILES_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
fi
export DOTFILES_DIR

PRESET="${DOTFILES_PRESET:-full}"

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
            printf '%sOK%s\n' "${GREEN}" "${NC}"
            return 0
        else
            printf '%sWRONG TARGET%s (points to %s)\n' "${YELLOW}" "${NC}" "$actual_target"
            ISSUES=1
            return 1
        fi
    elif [[ -e "$link" ]]; then
        printf '%sEXISTS BUT NOT SYMLINK%s\n' "${RED}" "${NC}"
        ISSUES=1
        return 1
    else
        printf '%sMISSING%s\n' "${RED}" "${NC}"
        ISSUES=1
        return 1
    fi
}

check_directory() {
    local dir="$1"
    local name="$2"

    printf "Checking %-30s" "$name..."

    if [[ -d "$dir" ]]; then
        printf '%sOK%s\n' "${GREEN}" "${NC}"
        return 0
    else
        printf '%sMISSING%s\n' "${RED}" "${NC}"
        ISSUES=1
        return 1
    fi
}

check_file() {
    local file="$1"
    local name="$2"

    printf "Checking %-30s" "$name..."

    if [[ -f "$file" ]]; then
        printf '%sOK%s\n' "${GREEN}" "${NC}"
        return 0
    else
        printf '%sMISSING%s\n' "${YELLOW}" "${NC}"
        ISSUES=1
        return 1
    fi
}

check_executable() {
    local file="$1"
    local name="$2"

    printf "Checking %-30s" "$name..."

    if [[ -x "$file" ]]; then
        printf '%sOK%s\n' "${GREEN}" "${NC}"
        return 0
    elif [[ -f "$file" ]]; then
        printf '%sNOT EXECUTABLE%s\n' "${YELLOW}" "${NC}"
        printf '  Run: chmod +x %s\n' "$file"
        ISSUES=1
        return 1
    else
        printf '%sMISSING%s\n' "${RED}" "${NC}"
        ISSUES=1
        return 1
    fi
}

# informational check, does not set ISSUES
check_local_override() {
    local file="$1"
    local name="$2"

    printf "Checking %-30s" "$name..."

    if [[ -f "$file" ]]; then
        printf '%sOK%s\n' "${GREEN}" "${NC}"
    else
        printf '%sNOT CREATED%s\n' "${CYAN}" "${NC}"
        printf '  Create from template with: dotfiles update\n'
    fi
    return 0
}

print_section "Dotfiles Health Check"
echo "Preset: $PRESET"
echo ""

echo "Symlinks:"
echo "---------"

# zsh (minimal)
printf "Checking %-30s" ".zshrc..."
if [[ -f "$HOME/.zshrc" ]]; then
    if grep -q "dotfiles.zsh" "$HOME/.zshrc" 2>/dev/null; then
        printf '%sOK%s\n' "${GREEN}" "${NC}"
    else
        printf '%sWARN%s\n' "${YELLOW}" "${NC}"
        echo "  ~/.zshrc exists but doesn't source dotfiles.zsh"
        ISSUES=1
    fi
else
    printf '%sMISSING%s\n' "${RED}" "${NC}"
    echo "  Run: cp ~/dotfiles/zsh/zshrc.template ~/.zshrc"
    ISSUES=1
fi
check_symlink "$HOME/.zprofile" "$DOTFILES_DIR/zsh/zprofile" ".zprofile"
check_file "$HOME/.p10k.zsh" ".p10k.zsh"

# formatters
check_symlink "$HOME/.prettierrc" "$DOTFILES_DIR/formatters/prettierrc.json" ".prettierrc"
check_symlink "$HOME/.editorconfig" "$DOTFILES_DIR/formatters/editorconfig" ".editorconfig"

# dotfiles CLI (minimal)
check_symlink "$HOME/.local/bin/dotfiles" "$DOTFILES_DIR/scripts/dotfiles" "dotfiles CLI"

# tmux (minimal)
# note: .tmux.conf is generated to XDG location and symlinked
XDG_TMUX_CONF="${XDG_CONFIG_HOME:-$HOME/.config}/tmux/tmux.conf"
check_symlink "$HOME/.tmux.conf" "$XDG_TMUX_CONF" ".tmux.conf"
check_symlink "$HOME/.tmux" "$DOTFILES_DIR/tmux" ".tmux"

# nvim (core)
if should_install "core"; then
    check_symlink "$HOME/.config/nvim" "$DOTFILES_DIR/nvim" "nvim config"
fi

# lazygit (core)
if should_install "core"; then
    check_symlink "$HOME/.config/lazygit/config.yml" "$DOTFILES_DIR/lazygit/config.yml" "lazygit config"
fi

# gh-dash sync (core)
if should_install "core"; then
    check_symlink "$HOME/.local/bin/dash-repo-sync" "$DOTFILES_DIR/gh-dash/dash-repo-sync" "dash-repo-sync"
fi

# hammerspoon (full)
if should_install "full"; then
    check_symlink "$HOME/.hammerspoon/init.lua" "$DOTFILES_DIR/hammerspoon/init.lua" "hammerspoon"
fi

# Ghostty (core)
# config is generated to XDG; Ghostty reads ~/.config/ghostty/config natively on all platforms
if should_install "core"; then
    check_file "$HOME/.config/ghostty/config" "ghostty config (XDG)"
    # the generated config includes config-file = ~/.config/ghostty/local
    check_file "$HOME/.config/ghostty/local" "ghostty local override"
fi

# Zed (core)
if should_install "core"; then
    check_symlink "$HOME/.config/zed/keymap.json" "$DOTFILES_DIR/zed/keymap.json" "zed keymap"
    check_symlink "$HOME/.config/zed/tasks.json" "$DOTFILES_DIR/zed/tasks.json" "zed tasks"
    check_file "$HOME/.config/zed/settings.json" "zed settings (copy-on-install)"
fi

# Karabiner (full)
if should_install "full"; then
    check_file "$HOME/.config/karabiner/karabiner.json" "karabiner config"
fi

echo ""
echo "Generated Configs:"
echo "------------------"

# tmux generated config (minimal): the file that .tmux.conf symlinks to
check_file "${XDG_CONFIG_HOME:-$HOME/.config}/tmux/tmux.conf" "tmux config (generated)"

# current theme (minimal)
printf "Checking %-30s" "current theme..."
THEME_FILE="${XDG_CONFIG_HOME:-$HOME/.config}/dotfiles/current-theme"
if [[ -f "$THEME_FILE" ]]; then
    printf '%sOK%s (%s)\n' "${GREEN}" "${NC}" "$(cat "$THEME_FILE")"
else
    printf '%sMISSING%s\n' "${YELLOW}" "${NC}"
    printf '  Run: dotfiles theme switch <theme-name>\n'
    ISSUES=1
fi

# gh-dash generated config (core)
if should_install "core"; then
    check_file "$HOME/.config/gh-dash/config.yml" "gh-dash config (generated)"
fi

echo ""
echo "Plugin Managers:"
echo "----------------"
check_directory "$HOME/.tmux/plugins/tpm" "TPM (Tmux Plugin Manager)"

# key TPM-managed plugins (installed via prefix + I inside tmux)
printf "Checking %-30s" "tmux plugins (via TPM)..."
MISSING_PLUGINS=()
for plugin in tmux-resurrect tmux-continuum tmux-yank tmux-fingers; do
    if [[ ! -d "$HOME/.tmux/plugins/$plugin" ]]; then
        MISSING_PLUGINS+=("$plugin")
    fi
done
if [[ ${#MISSING_PLUGINS[@]} -eq 0 ]]; then
    printf '%sOK%s\n' "${GREEN}" "${NC}"
else
    printf '%sWARN%s\n' "${YELLOW}" "${NC}"
    printf '  Missing: %s\n' "${MISSING_PLUGINS[*]}"
    printf '  Install with: prefix + I (inside tmux)\n'
    ISSUES=1
fi

if should_install "core"; then
    check_directory "$HOME/.local/share/nvim/lazy" "lazy.nvim (Neovim)"

    # warn if old packer install exists; it shadows lazy.nvim plugins in the
    # runtimepath and can cause "attempt to call field X (a nil value)" errors
    # when nvim loads the wrong (pre-rewrite) version of a plugin module
    PACKER_DIR="$HOME/.local/share/nvim/site/pack/packer"
    printf "Checking %-30s" "no stale packer install..."
    if [[ -d "$PACKER_DIR" ]]; then
        printf '%sWARN%s\n' "${YELLOW}" "${NC}"
        printf '  Stale packer plugins at %s\n' "$PACKER_DIR"
        printf '  These shadow lazy.nvim plugins and can break Neovim.\n'
        printf '  Remove with: rm -rf %s\n' "$PACKER_DIR"
        ISSUES=1
    else
        printf '%sOK%s\n' "${GREEN}" "${NC}"
    fi
fi

echo ""
echo "Secrets:"
echo "--------"
ZSH_CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/zsh"
check_file "$ZSH_CONFIG_DIR/secrets.zsh" "Secrets file"

# environment variables used by plugins (core), informational only
if should_install "core"; then
    echo ""
    echo "Environment Variables:"
    echo "----------------------"

    # informational check, does not set ISSUES (copilot is the default adapter)
    check_env_var() {
        local var="$1"
        local desc="$2"

        printf "Checking %-30s" "$var..."

        if [[ -n "${!var:-}" ]]; then
            printf '%sOK%s\n' "${GREEN}" "${NC}"
        else
            printf '%sNOT SET%s\n' "${CYAN}" "${NC}"
            printf '  %s\n' "$desc"
        fi
        return 0
    }

    check_env_var "ANTHROPIC_API_KEY" "Optional: enables anthropic adapter in codecompanion.nvim"
fi

# session launchers (core)
if should_install "core"; then
    echo ""
    echo "Session Launchers:"
    echo "------------------"
    if command_exists dev; then
        printf "Checking %-30s${GREEN}OK${NC}\n" "dev command"
    else
        printf "Checking %-30s${YELLOW}NOT IN PATH${NC}\n" "dev command"
        echo "  Add ~/.local/launchers to your PATH"
    fi

fi

echo ""
echo "Alerts System:"
echo "--------------"

# hook scripts (must be executable for alerts to fire)
check_executable "$DOTFILES_DIR/scripts/hooks/agent-alert.sh" "agent-alert hook"
check_executable "$DOTFILES_DIR/scripts/hooks/agent-alert-clear.sh" "agent-alert-clear hook"
check_executable "$DOTFILES_DIR/scripts/hooks/cmd-alert.sh" "cmd-alert hook"

# wrapper scripts (used by Claude Code and OpenCode hook configs)
check_executable "$DOTFILES_DIR/scripts/hooks/wrappers/claude-alert.sh" "claude alert wrapper"
check_executable "$DOTFILES_DIR/scripts/hooks/wrappers/claude-alert-clear.sh" "claude alert-clear wrapper"
check_executable "$DOTFILES_DIR/scripts/hooks/wrappers/opencode-alert.sh" "opencode alert wrapper"
check_executable "$DOTFILES_DIR/scripts/hooks/wrappers/opencode-alert-clear.sh" "opencode alert-clear wrapper"

echo ""
echo "Local Overrides:"
echo "----------------"

# these are user-owned files created from templates, informational only
check_local_override "${XDG_CONFIG_HOME:-$HOME/.config}/tmux/local.conf" "tmux local.conf"
if should_install "core"; then
    check_local_override "$HOME/.config/nvim/local.lua" "nvim local.lua"
    check_local_override "$HOME/.config/lazygit/local.yml" "lazygit local.yml"
    check_local_override "$HOME/.config/gh-dash/local.yml" "gh-dash local.yml"
fi
if should_install "full"; then
    check_local_override "$HOME/.hammerspoon/local.lua" "hammerspoon local.lua"
fi

# local layer sync (optional feature, informational; a broken pointer warns
# but never fails the check)
printf "Checking %-30s" "local layer sync..."
local_layer_dir="${DOTFILES_LOCAL_DIR:-}"
local_ptr="${XDG_CONFIG_HOME:-$HOME/.config}/dotfiles/local-repo"
if [[ -z "$local_layer_dir" && -f "$local_ptr" ]]; then
    local_layer_dir=$(head -1 "$local_ptr")
fi
if [[ -z "$local_layer_dir" ]]; then
    printf '%sNOT CONFIGURED%s\n' "${CYAN}" "${NC}"
    printf '  Optional: sync personal config with: dotfiles local init | clone <url>\n'
elif git -C "$local_layer_dir" rev-parse --git-dir &>/dev/null; then
    printf '%sOK%s (%s)\n' "${GREEN}" "${NC}" "$local_layer_dir"
else
    printf '%sWARN%s\n' "${YELLOW}" "${NC}"
    echo "  Configured repo missing or not a git repository: $local_layer_dir"
    echo "  Fix with: dotfiles local init (or remove $local_ptr)"
fi

echo ""
echo "Tools & PATH:"
echo "-------------"

# ~/.local/bin in PATH (required for dotfiles CLI, dash-repo-sync)
# shellcheck disable=SC2088
printf "Checking %-30s" "~/.local/bin in PATH..."
if [[ ":$PATH:" == *":$HOME/.local/bin:"* ]]; then
    printf '%sOK%s\n' "${GREEN}" "${NC}"
else
    printf '%sNOT IN PATH%s\n' "${YELLOW}" "${NC}"
    printf '  dotfiles CLI requires ~/.local/bin in PATH\n'
    ISSUES=1
fi

# yq (required for gh-dash local merge)
if should_install "core"; then
    printf "Checking %-30s" "yq (gh-dash merge)..."
    if command_exists yq; then
        printf '%sOK%s\n' "${GREEN}" "${NC}"
    else
        printf '%sNOT FOUND%s\n' "${YELLOW}" "${NC}"
        printf '  gh-dash local overrides will not apply without yq\n'
        printf '  Install with: brew install yq\n'
        ISSUES=1
    fi
fi

# zsh completion dirs; a dirty compaudit makes the daily full compinit prompt
printf "Checking %-30s" "compinit dir permissions..."
if ! command_exists zsh; then
    printf '%sSKIPPED%s (zsh not found)\n' "${YELLOW}" "${NC}"
elif [[ -z "$(zsh -fc 'autoload -Uz compaudit; compaudit' 2>/dev/null)" ]]; then
    printf '%sOK%s\n' "${GREEN}" "${NC}"
else
    printf '%sINSECURE DIRS%s\n' "${YELLOW}" "${NC}"
    printf '  compinit prompts on its next full run (zsh/dotfiles.zsh runs one daily)\n'
    printf '  Fix with: %s/scripts/fix-compinit-insecure-dirs.sh\n' "$DOTFILES_DIR"
    ISSUES=1
fi

echo ""

if [[ $ISSUES -eq 0 ]]; then
    success "All checks passed! Your dotfiles are correctly installed."
    exit 0
else
    warn "Some issues were found. See above for details."
    exit 1
fi
