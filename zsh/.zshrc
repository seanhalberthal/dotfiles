# =============================================================================
# ZSH CONFIGURATION
# =============================================================================
# See ~/.zsh/README.md for full documentation and setup guide.
#
# File structure:
#   ~/.zshrc            - Main config (this file), loaded for interactive shells
#   ~/.zprofile         - Login shell config (PATH additions from installers)
#   ~/.p10k.zsh         - Powerlevel10k theme configuration
#   ~/.zsh/.secrets.zsh - API keys and credentials (not version controlled)
#   ~/.zsh/README.md    - Documentation

# =============================================================================
# POWERLEVEL10K PROMPT
# =============================================================================
# Instant prompt: caches prompt to display immediately while rest of zshrc loads
# Disabled for SSH to avoid input issues with remote connections
if [[ -z "$SSH_CONNECTION" && -r "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh" ]]; then
  source "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh"
fi

# Load theme and config (installed via: brew install powerlevel10k)
source /opt/homebrew/share/powerlevel10k/powerlevel10k.zsh-theme
[[ ! -f ~/.p10k.zsh ]] || source ~/.p10k.zsh

# =============================================================================
# PATH CONFIGURATION
# =============================================================================
# Note: Additional PATH entries may exist in ~/.zprofile (added by installers)

# Homebrew (Apple Silicon location)
export PATH=/opt/homebrew/bin:/opt/homebrew/sbin:$PATH

# Go workspace (GOPATH is where go install puts binaries)
export GOPATH=$HOME/go
export PATH=$PATH:$GOPATH/bin

# Java (OpenJDK via Homebrew)
export PATH="/opt/homebrew/opt/openjdk/bin:$PATH"

# Python pipx (isolated CLI tool installation)
export PATH="$PATH:/Users/bssmnt/.local/bin"

# User scripts directory (custom shell scripts)
export PATH="$HOME/bin:$PATH"

# Neovim Mason LSP/tools (lua-language-server, gopls, pyright, etc.)
export PATH="$HOME/.local/share/nvim/mason/bin:$PATH"

# ARM embedded development (for microcontroller/firmware work)
export INCLUDE=/opt/homebrew/arm-none-eabi/include
# export LIB=/opt/homebrew/arm-none-eabi/lib

# =============================================================================
# GOOGLE CLOUD SDK - LAZY LOADED
# =============================================================================
# Lazy load gcloud CLI tools and shell completion (~260ms savings)
# Only loads when you actually use gcloud/gsutil/bq
_load_gcloud() {
  unset -f gcloud gsutil bq
  if [ -f '/Users/bssmnt/google-cloud-sdk/path.zsh.inc' ]; then
    . '/Users/bssmnt/google-cloud-sdk/path.zsh.inc'
  fi
  if [ -f '/Users/bssmnt/google-cloud-sdk/completion.zsh.inc' ]; then
    . '/Users/bssmnt/google-cloud-sdk/completion.zsh.inc'
  fi
}
gcloud() { _load_gcloud && gcloud "$@"; }
gsutil() { _load_gcloud && gsutil "$@"; }
bq() { _load_gcloud && bq "$@"; }

# =============================================================================
# NODE.JS (FNM)
# =============================================================================
# fnm (Fast Node Manager) - Rust-based, ~5ms init vs NVM's 300-500ms
# Usage: fnm install 22, fnm use 20, fnm default 22
# Reads .nvmrc and .node-version files automatically with --use-on-cd
eval "$(fnm env --use-on-cd)"

# =============================================================================
# DOCKER & COMPLETIONS
# =============================================================================
# Docker CLI completions (docker, docker-compose commands)
fpath=(/Users/bssmnt/.docker/completions $fpath)

# Cached compinit - only regenerate completion dump once per day (~50-100ms savings)
autoload -Uz compinit
if [[ -n ~/.zcompdump(#qN.mh+24) ]]; then
  compinit
else
  compinit -C
fi

# =============================================================================
# DIRENV
# =============================================================================
# Automatically load/unload environment variables when entering directories
# with .envrc files. Great for per-project env vars.
eval "$(direnv hook zsh)"

# =============================================================================
# ZSH PLUGINS
# =============================================================================
# zsh-autosuggestions: suggests commands as you type based on history
# Accept suggestion: Right arrow or End key
source /opt/homebrew/share/zsh-autosuggestions/zsh-autosuggestions.zsh

# fzf: fuzzy finder for files, history, and more
# Keybindings: Ctrl+R (history), Ctrl+T (files), Opt+C (cd to directory)
eval "$(fzf --zsh)"

# =============================================================================
# TERMINAL TITLE HOOKS
# =============================================================================
# Dynamic terminal/tab titles that show context
# precmd: runs before each prompt (shows directory + git branch)
# preexec: runs before each command (shows running command)
precmd() {
  local branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null)
  if [[ -n "$branch" ]]; then
    print -Pn "\e]0;%1~ ($branch)\a"
  else
    print -Pn "\e]0;%1~\a"
  fi
}

preexec() {
  print -Pn "\e]0;$(echo $1 | cut -d' ' -f1)\a"
}

# =============================================================================
# SECRETS & CREDENTIALS
# =============================================================================
# API keys and tokens loaded from separate file (not version controlled)
# See ~/.zsh/README.md for structure of .secrets.zsh
if [[ -f "$HOME/.zsh/.secrets.zsh" ]]; then
  source "$HOME/.zsh/.secrets.zsh"
fi

# Android SDK platform tools (adb, fastboot)
export PATH=$PATH:$ANDROID_HOME/platform-tools

# =============================================================================
# .NET
# =============================================================================
# Disable Microsoft telemetry for .NET CLI
export DOTNET_CLI_TELEMETRY_OPTOUT='true'

# =============================================================================
# SONARCLOUD
# =============================================================================
# SonarScanner CLI for code quality analysis
export SONAR_HOST_URL="https://sonarcloud.io"

export PATH="$HOME/bin:$PATH"

# =============================================================================
# ALIASES & FUNCTIONS
# =============================================================================
# Editor
export EDITOR="nvim"                   # Default editor for git, etc.
alias oc="opencode"                    # Launch OpenCode editor

# MCP (Model Context Protocol)
alias mcp-sync="~/.config/sync-mcp-servers.sh"    # Sync MCP servers across tools

# Claude Code Plans
alias plans="cd ~/.claude/plans"
alias commands="cd ~/.claude/commands"

# Dana 
alias da="cd ~/src/dana"
alias dap="cd ~/src/dana/.claude/plans/"

# Kill Vite Server
alias killvite="pkill -f "vite" 2>/dev/null"

# dotfiles 
alias dot="cd ~/dotfiles"
alias dotp="cd ~/dotfiles/.claude/plans"

# claude-config 
alias claudeconfig="cd ~/claude-config"

# Tmux session management (see ~/.tmux/README.md)
alias tls="~/.tmux/scripts/resurrect-restore.sh --list"

# Functions (instead of aliases) for tab completion support
trestore() {
  ~/.tmux/scripts/resurrect-restore.sh "$@"
}

tkill() {
  ~/.tmux/scripts/resurrect-delete.sh "$@"
}

# Tab completion for tmux commands
_tmux_sessions_backup() {
  # Complete with saved session backups (for trestore)
  local -a sessions
  sessions=(${(f)"$(ls ~/.tmux/resurrect/sessions/*.txt 2>/dev/null | xargs -n1 basename -s .txt)"})
  _describe 'tmux session backups' sessions
}

_tmux_sessions_running() {
  # Complete with running tmux sessions (for tkill and ta)
  local -a sessions
  sessions=(${(f)"$(tmux list-sessions -F '#{session_name}' 2>/dev/null)"})
  _describe 'running tmux sessions' sessions
}

# Register completion functions
compdef _tmux_sessions_backup trestore
compdef _tmux_sessions_running tkill
compdef _tmux_sessions_running ta

# Attach to tmux session, restoring from backup if needed
ta() {
  # Try to attach to running session
  if tmux a -t "$1" 2>/dev/null; then return 0; fi

  # Not running - try to restore from backup
  local backup="${HOME}/.tmux/resurrect/sessions/$1.txt"
  if [[ -f "$backup" ]]; then
    echo "Restoring '$1' from backup..."
    if ~/.tmux/scripts/resurrect-restore.sh "$1" && tmux a -t "$1"; then
      return 0
    fi
    # Restore failed - backup is stale
    echo "Backup stale, removing: $1"
    rm -f "$backup"
    return 1
  fi
  echo "No session or backup found: $1"
  return 1
}

# Development tools
alias gols="ls ~/go/bin"               # List installed Go binaries

# Homebrew update
alias brewup="brew update && brew upgrade"

# =============================================================================
# ZSH LINE EDITOR (ZLE) KEYBINDINGS
# =============================================================================
# Disable vi-mode completely - use emacs keybindings (default)
bindkey -e                             # Force emacs mode (Ctrl+A, Ctrl+E, etc.)

# Prevent accidental vi-mode activation from Option+key combinations
# Option+key sends ESC followed by another character. Setting KEYTIMEOUT to 1
# (10ms) means ESC alone won't trigger vi-mode, but ESC sequences from Option+key
# will be processed correctly, and tools like fzf can still use ESC to exit.
export KEYTIMEOUT=1                    # Wait 10ms for more chars after ESC

# Ensure common word deletion shortcuts work correctly
bindkey '^[^?' backward-kill-word      # Option+Backspace: delete word backwards
bindkey '^W' backward-kill-word        # Ctrl+W: delete word backwards
