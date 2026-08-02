# shellcheck shell=zsh
# =============================================================================
# DOTFILES ZSH FRAMEWORK
# =============================================================================
# shared shell configuration sourced by ~/.zshrc.
# do NOT symlink this file directly; source it from your personal ~/.zshrc:
#
#   source ~/dotfiles/zsh/dotfiles.zsh
#
# file structure:
#   ~/.zshrc                           - your personal config (sources this file)
#   ~/.zprofile                        - login shell config (PATH additions from installers)
#   ~/.p10k.zsh                        - powerlevel10k theme configuration
#   ~/.config/zsh/secrets.zsh          - API keys and credentials (not version controlled)

# =============================================================================
# STARTUP PROFILING (optional)
# =============================================================================
# enable with: ZPROF=1 zsh -i -c exit
# or use: zsh-profile-detailed
[[ -n "$ZPROF" ]] && zmodload zsh/zprof

# =============================================================================
# PLATFORM DETECTION
# =============================================================================
# detect platform for conditional configuration (must be before Homebrew-installed tools)
case "$(uname)" in
  Darwin)
    export IS_MACOS=1
    if [[ "$(uname -m)" == "arm64" ]]; then
      export IS_APPLE_SILICON=1
      export HOMEBREW_PREFIX="/opt/homebrew"
    else
      export IS_APPLE_SILICON=0
      export HOMEBREW_PREFIX="/usr/local"
    fi
    ;;
  Linux)
    export IS_MACOS=0
    export IS_APPLE_SILICON=0
    export HOMEBREW_PREFIX="/home/linuxbrew/.linuxbrew"
    ;;
esac

# require explicit trust for non-official Homebrew taps. newly tapped third-party
# repos must be approved with `brew trust --tap <user/repo>` before brew will load
# their formulae or casks, instead of being trusted by default. existing taps were
# trusted by the 0.2.104 migration; the Brewfile's taps are trusted during install
export HOMEBREW_REQUIRE_TAP_TRUST=1

# =============================================================================
# HOMEBREW ENVIRONMENT (non-login shells)
# =============================================================================
# ~/.zprofile runs `brew shellenv` for LOGIN shells. macOS terminals start a
# login shell, so that covers them; but most Linux terminal emulators
# (LXTerminal on Raspberry Pi OS, gnome-terminal, ...) open a NON-login
# interactive shell that skips ~/.zprofile, leaving brew — and everything it
# installs (fzf, direnv, gh) — off PATH. Re-run shellenv here, guarded so login
# shells that already ran it are a no-op, so non-login shells match.
if (( ! $+commands[brew] )); then
  for _brew in /opt/homebrew/bin/brew /usr/local/bin/brew /home/linuxbrew/.linuxbrew/bin/brew; do
    if [[ -x "$_brew" ]]; then
      eval "$("$_brew" shellenv)"
      break
    fi
  done
  unset _brew
fi

# =============================================================================
# FILE DESCRIPTOR LIMIT
# =============================================================================
# macOS default soft limit is 256, too low for nvim plugins that spawn many
# git subprocesses (diffview, gitsigns). raise to 10240 to prevent EMFILE errors
[[ "$IS_MACOS" == "1" ]] && ulimit -n 10240 2>/dev/null

# =============================================================================
# TERMINFO FALLBACK
# =============================================================================
# Ghostty sets TERM=xterm-ghostty, but remote machines (e.g. SSH targets)
# may not have the terminfo entry installed, causing garbled terminal output.
# fall back to xterm-256color when the terminfo is missing
if [[ "$TERM" == "xterm-ghostty" ]] && ! infocmp xterm-ghostty &>/dev/null; then
  export TERM=xterm-256color
fi

# load theme and config (installed via: brew install powerlevel10k)
if [[ -f "$HOMEBREW_PREFIX/share/powerlevel10k/powerlevel10k.zsh-theme" ]]; then
  source "$HOMEBREW_PREFIX/share/powerlevel10k/powerlevel10k.zsh-theme"
fi
[[ ! -f ~/.p10k.zsh ]] || source ~/.p10k.zsh

# =============================================================================
# PATH CONFIGURATION
# =============================================================================
# note: additional PATH entries may exist in ~/.zprofile (added by installers).
# ~/.zprofile already sets `typeset -U path PATH` so these appends auto-dedupe;
# we re-assert it here so non-login shells (sourcing dotfiles.zsh standalone)
# still benefit from deduplication
typeset -U path PATH

# Go workspace (GOPATH is where go install puts binaries)
export GOPATH=$HOME/go
export PATH=$PATH:$GOPATH/bin

# Rust/Cargo binaries (cargo install, rustup toolchains)
export PATH="$PATH:$HOME/.cargo/bin"

# Java (OpenJDK via Homebrew)
export PATH="$HOMEBREW_PREFIX/opt/openjdk/bin:$PATH"

# Python uv tool install (isolated CLI tool install)
export PATH="$PATH:$HOME/.local/bin"

# launchers (tmux session launchers, VS Code launcher, etc.)
export PATH="$PATH:$HOME/.local/launchers"

# user scripts directory (custom shell scripts)
export PATH="$HOME/bin:$PATH"

# nvim Mason LSP/tools (lua-language-server, gopls, pyright, etc.)
# appended (not prepended) so Homebrew-installed versions take priority
export PATH="$PATH:$HOME/.local/share/nvim/mason/bin"

# .NET global tools (EasyDotnet, etc.)
export PATH="$PATH:$HOME/.dotnet/tools"
export DOTNET_ROLL_FORWARD='Major'

# ARM embedded development (microcontroller/firmware work)
export INCLUDE="$HOMEBREW_PREFIX/arm-none-eabi/include"
# export LIB="$HOMEBREW_PREFIX/arm-none-eabi/lib"

# =============================================================================
# GOOGLE CLOUD SDK - LAZY LOADED
# =============================================================================
# lazy load gcloud CLI tools and shell completion (~260ms savings)
# only loads when you actually use gcloud/gsutil/bq
_load_gcloud() {
  unset -f gcloud gsutil bq
  local gcloud_dir="$HOMEBREW_PREFIX/share/google-cloud-sdk"
  if [[ -f "$gcloud_dir/path.zsh.inc" ]]; then
    source "$gcloud_dir/path.zsh.inc"
  fi
  if [[ -f "$gcloud_dir/completion.zsh.inc" ]]; then
    source "$gcloud_dir/completion.zsh.inc"
  fi
}
gcloud() { _load_gcloud && gcloud "$@"; }
gsutil() { _load_gcloud && gsutil "$@"; }
bq() { _load_gcloud && bq "$@"; }

# =============================================================================
# NODE.JS (FNM)
# =============================================================================
# fnm (Fast Node Manager): Rust-based, ~5ms init vs NVM's 300-500ms
# usage: fnm install 22, fnm use 20, fnm default 22
# reads .nvmrc and .node-version files automatically with --use-on-cd
if command -v fnm &>/dev/null; then
  eval "$(fnm env --use-on-cd)"
fi

# =============================================================================
# DOCKER & COMPLETIONS
# =============================================================================
# dotfiles autoloaded functions and completions.
# DOTFILES_ROOT must be set before this fpath entry, otherwise the path
# resolves to "/zsh/functions" and _dotfiles fails to autoload ("function
# definition file not found"). it only appeared to work inside tmux because the
# export below was inherited from the parent shell's environment
export DOTFILES_ROOT="${DOTFILES_DIR:-$HOME/dotfiles}"
fpath=("$DOTFILES_ROOT/zsh/functions" $fpath)

# Docker CLI completions (docker, docker-compose commands)
fpath=("$HOME/.docker/completions" $fpath)

# systemd tools (loginctl, hostnamectl, timedatectl, networkctl, busctl, ...):
# carapace ships no completer for most of the systemd family, so expose the
# OS-provided zsh completions instead. Linux-only: the dir is absent on macOS
# (no systemd), so the guard makes this a no-op there. Appended, not prepended,
# so it only fills gaps and never shadows brew's own site-functions; carapace
# still wins for the systemd tools it does own (systemctl, journalctl, ...) as
# it re-registers those via compdef after compinit below.
[[ -d /usr/share/zsh/vendor-completions ]] && fpath=($fpath /usr/share/zsh/vendor-completions)

# Homebrew zsh-completions (brew install zsh-completions): extra completion
# definitions for tools that ship none of their own. installs to its own
# share/zsh-completions dir, separate from brew's site-functions, so add it
# explicitly. appended so it only fills gaps, and it must precede compinit below
[[ -d "$HOMEBREW_PREFIX/share/zsh-completions" ]] && fpath=($fpath "$HOMEBREW_PREFIX/share/zsh-completions")

# cached compinit: only regenerate completion dump once per day (~50-100ms savings)
# the (#q...) glob qualifier requires EXTENDED_GLOB; anonymous function scopes it
# so it doesn't leak globally (local_options only works inside functions)
autoload -Uz compinit
# shellcheck disable=SC1009,SC1036,SC1072,SC1073
(){ setopt local_options EXTENDED_GLOB
  if [[ -n ~/.zcompdump(#qN.mh+24) ]]; then
    compinit
  else
    compinit -C
  fi
}

# gh CLI completions: gh generates a compdef line inside its completion file that
# conflicts with zsh autoload. re-register after compinit so it resolves correctly.
# see: https://github.com/cli/cli/issues/8462
(( $+commands[gh] )) && compdef _gh gh 2>/dev/null

# =============================================================================
# CACHED EVAL HELPER
# =============================================================================
# cache the output of slow eval commands (direnv, fzf) to avoid forking on
# every shell startup. cache is invalidated when the binary is newer than the
# cached file (covers brew upgrade). usage: _cached_eval <name> <command...>
_cached_eval() {
  local name="$1"; shift
  local cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}/zsh"
  local cache_file="$cache_dir/$name.zsh"
  local bin_path="${commands[$name]}"

  # tool not installed (or not on PATH): skip silently rather than running the
  # hook and printing "command not found" on every prompt. minimal installs
  # legitimately lack direnv/fzf.
  [[ -n "$bin_path" ]] || return 0

  if [[ -s "$cache_file" && "$cache_file" -nt "$bin_path" ]]; then
    source "$cache_file"
  else
    [[ -d "$cache_dir" ]] || mkdir -p "$cache_dir"
    "$@" > "$cache_file"
    if [[ -s "$cache_file" ]]; then
      source "$cache_file"
    else
      rm -f "$cache_file"
    fi
  fi
}

# =============================================================================
# DIRENV
# =============================================================================
# automatically load/unload environment variables when entering directories
# with .envrc files. great for per-project env vars
_cached_eval direnv direnv hook zsh

# =============================================================================
# ZSH LINE EDITOR (ZLE) BASE KEYMAP
# =============================================================================
# set emacs mode BEFORE plugins and custom bindings so they layer on top
# rather than being wiped. must precede fzf, zsh-autosuggestions, and any
# custom ZLE widgets (e.g. _cdl-widget bound to Opt+A)
bindkey -e                             # force emacs mode (Ctrl+A, Ctrl+E, etc.)

# prevent accidental vi-mode activation from Option+key combinations
# Option+key sends ESC followed by another character. setting KEYTIMEOUT to 1
# (10ms) means ESC alone won't trigger vi-mode, but ESC sequences from Option+key
# will be processed correctly, and tools like fzf can still use ESC to exit
export KEYTIMEOUT=1                    # wait 10ms for more chars after ESC

# inside tmux, ignore EOF (Ctrl+D) at the prompt so an accidental press doesn't
# close the shell, which would tear down the pane and, if last, the window.
# outside tmux, Ctrl+D still exits normally
[[ -n "$TMUX" ]] && setopt IGNORE_EOF

# treat hyphens, dots, underscores, and slashes as word separators so
# Opt+Backspace and Ctrl+W delete one segment at a time for kebab-case,
# snake_case, dotted.name, and file/paths
WORDCHARS='*?[]~=&;!#$%^(){}<>'

# =============================================================================
# ZSH PLUGINS
# =============================================================================
# zsh-autosuggestions: suggests commands as you type based on history
# accept suggestion: Right arrow or End key
if [[ -f "$HOMEBREW_PREFIX/share/zsh-autosuggestions/zsh-autosuggestions.zsh" ]]; then
  source "$HOMEBREW_PREFIX/share/zsh-autosuggestions/zsh-autosuggestions.zsh"
fi

# fzf: fuzzy finder for files, history, and more
# keybindings: Ctrl+R (history), Ctrl+T (files), Opt+C (cd to directory)
_cached_eval fzf fzf --zsh

# apply theme colours to fzf (and auto-refresh on theme-switch)
# DOTFILES_ROOT is exported earlier (see the fpath block); fzf-theme.sh relies
# on it to skip its subshell-based path detection
if [[ -f "$DOTFILES_ROOT/scripts/fzf-theme.sh" ]]; then
  source "$DOTFILES_ROOT/scripts/fzf-theme.sh"
  _fzf_theme_cached="${CURRENT_THEME:-}"

  # re-source fzf-theme.sh if the active theme has changed since last check
  _fzf_theme_refresh() {
    local live
    live=$(<"${XDG_CONFIG_HOME:-$HOME/.config}/dotfiles/current-theme" 2>/dev/null) || return
    if [[ "$live" != "$_fzf_theme_cached" ]]; then
      source "$DOTFILES_ROOT/scripts/fzf-theme.sh"
      _fzf_theme_cached="$live"
    fi
  }

  # wrap fzf ZLE widgets so Ctrl+R/T pick up theme changes immediately
  for _w in fzf-file-widget fzf-history-widget; do
    if zle -l "$_w" &>/dev/null; then
      zle -A "$_w" "_orig-$_w"
      eval "_wrapped-${_w}() { _fzf_theme_refresh; zle _orig-${_w}; }"
      zle -N "$_w" "_wrapped-${_w}"
    fi
  done
  unset _w

  # unbind Alt+C (fzf-cd-widget): terminals send the same escape sequence for
  # Esc+c and Alt+C, causing accidental triggers when pressing Esc then "c".
  # the Opt+A cdl-widget is the preferred directory picker
  bindkey -r '\ec'

  # Opt+A: directory history picker (inline fzf selection + BUFFER cd)
  # follows fzf's own Alt-C pattern: run fzf directly in the widget,
  # then set BUFFER to the cd command and accept-line to execute it
  _cdl-widget() {
    if (( ${#_dir_back_stack} == 0 )); then
      zle redisplay
      return 0
    fi
    setopt localoptions pipefail 2>/dev/null
    local -a reversed=()
    local prev="" i
    for (( i=${#_dir_back_stack}; i>=1; i-- )); do
      local entry="${_dir_back_stack[$i]}"
      if [[ "$entry" != "$prev" ]]; then
        reversed+=("$entry")
        prev="$entry"
      fi
    done
    local count=${#reversed[@]}
    _fzf_theme_refresh 2>/dev/null
    local dir
    dir="$(printf '%s\n' "${reversed[@]}" | fzf \
      --height=40% --reverse \
      --header="$count entries" \
      --preview='ls -CF {}' \
    )"
    if [[ -z "$dir" ]]; then
      zle redisplay
      return 0
    fi
    if [[ -d "$dir" ]]; then
      builtin cd -- "$dir"
      # re-run precmd hooks so P10k regenerates the prompt string with the
      # new directory, then reset-prompt to display it
      local f; for f in $precmd_functions; do "$f" 2>/dev/null; done
      zle reset-prompt
    else
      zle redisplay
    fi
  }
  zle -N _cdl-widget
  bindkey '\ea' _cdl-widget
fi
# =============================================================================
# CARAPACE COMPLETIONS
# =============================================================================
# multi-shell completion provider. bridges zsh's existing completion system,
# so builtin zsh completions continue to work. cached via _cached_eval so we
# don't fork `carapace _carapace` on every shell start
export CARAPACE_BRIDGES='zsh'
zstyle ':completion:*:git:*' group-order 'main commands' 'alias commands' 'external commands'
zstyle ':completion:*' format $'\e[2;37mCompleting %d\e[m'
zstyle ':completion:*' menu select
zstyle ':completion:*' group-name ''
if (( $+commands[carapace] )); then
  _cached_eval carapace carapace _carapace
fi

# =============================================================================
# TERMINAL TITLE HOOKS
# =============================================================================
# dynamic terminal/tab titles that show context
# _dotfiles_precmd: runs before each prompt (shows directory + git branch)
# _dotfiles_preexec: runs before each command (shows running command)
# uses *_functions arrays to stack with other hooks (p10k, plugins, etc.)
#
# performance: git branch is cached in _git_branch to avoid forking
# git rev-parse on every prompt (~28ms). cache is refreshed on directory
# change (chpwd) and after git commands (preexec)

_git_branch=""

_update_git_branch() {
  _git_branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null)
}

# refresh branch cache when changing directories
chpwd_functions+=(_update_git_branch)

# defer initial cache population to the first prompt (saves ~14ms at source time)
_update_git_branch_once() {
  _update_git_branch
  precmd_functions=(${precmd_functions:#_update_git_branch_once})
}
precmd_functions+=(_update_git_branch_once)

_dotfiles_precmd() {
  if [[ -n "$_git_branch" ]]; then
    print -Pn "\e]0;%1~ ($_git_branch)\a"
  else
    print -Pn "\e]0;%1~\a"
  fi
}
precmd_functions+=(_dotfiles_precmd)

_dotfiles_preexec() {
  # extract first word safely using parameter expansion
  local cmd="${1%% *}"

  # resolve job-control resumes (fg, fg %2, %2) to the job's real command via
  # $jobtexts, otherwise the title becomes "fg" and tmux automatic-rename
  # picks it up as the window name for title-named panes (claude)
  local job=""
  case "$cmd" in
    fg) local -a words; words=(${(z)1}); job="${words[2]:-%+}" ;;
    %*) job="$cmd" ;;
  esac
  [[ "$job" == (%*|<->) ]] && cmd="${${jobtexts[$job]:-$cmd}%% *}"

  print -Pn "\e]0;${cmd}\a"

  # refresh git branch cache after git commands that may change the branch
  case "$cmd" in
    git|gh|tig) _update_git_branch ;;
  esac
}
preexec_functions+=(_dotfiles_preexec)

# =============================================================================
# SECRETS & CREDENTIALS
# =============================================================================
# API keys and tokens loaded from separate file (not version controlled)
# see ~/dotfiles/zsh/secrets.zsh.template for structure
ZSH_CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/zsh"
if [[ -f "$ZSH_CONFIG_DIR/secrets.zsh" ]]; then
  source "$ZSH_CONFIG_DIR/secrets.zsh"
fi

# Android SDK (installed via Homebrew cask: android-commandlinetools)
# provides sdkmanager, avdmanager, adb, fastboot, emulator
if [[ -d "$HOMEBREW_PREFIX/share/android-commandlinetools" ]]; then
  export ANDROID_HOME="$HOMEBREW_PREFIX/share/android-commandlinetools"
  export PATH="$PATH:$ANDROID_HOME/cmdline-tools/latest/bin:$ANDROID_HOME/platform-tools:$ANDROID_HOME/emulator"
fi

# =============================================================================
# .NET
# =============================================================================
# disable Microsoft telemetry for .NET CLI
export DOTNET_CLI_TELEMETRY_OPTOUT='true'
# prevent MSBuild from keeping worker nodes alive between builds
export MSBUILDDISABLENODEREUSE=1

# =============================================================================
# SONARCLOUD
# =============================================================================
# SonarScanner CLI for code quality analysis
export SONAR_HOST_URL="https://sonarcloud.io"

# =============================================================================
# GIT
# =============================================================================
# skip the optional index.lock that read-only git commands (status, diff) take
# just to write back a refreshed index. without this, frequent background status
# polls collide with an in-flight commit and fail it with
# "Unable to create '.../index.lock': File exists". the usual culprits are an
# editor's git integration or several claude code sessions open on one worktree,
# each refreshing status. real index writes (add, commit) still lock normally
export GIT_OPTIONAL_LOCKS=0

# =============================================================================
# LAZYGIT
# =============================================================================
# load base config (symlinked from dotfiles) + personal local overrides.
# local.yml only needs the keys you want to override; lazygit merges both files.
# LG_CONFIG_FILE overrides the default path, so we use ~/.config/lazygit/ on all platforms
_lg_base="$HOME/.config/lazygit/config.yml"
_lg_local="$HOME/.config/lazygit/local.yml"
if [[ -f "$_lg_local" ]]; then
    export LG_CONFIG_FILE="$_lg_base,$_lg_local"
else
    export LG_CONFIG_FILE="$_lg_base"
fi
unset _lg_base _lg_local

# =============================================================================
# OPENCODE
# =============================================================================
# point opencode-tmux-alert plugin to dotfiles hook scripts
export OPENCODE_ALERT_SCRIPT="$DOTFILES_ROOT/scripts/hooks/wrappers/opencode-alert.sh"
export OPENCODE_CLEAR_SCRIPT="$DOTFILES_ROOT/scripts/hooks/agent-alert-clear.sh"

# =============================================================================
# SSH WRAPPER
# =============================================================================
# Ghostty sets TERM=xterm-ghostty which most remote hosts don't recognise.
# override TERM for SSH connections so the remote PTY gets xterm-256color
ssh() {
  if [[ "$TERM" == "xterm-ghostty" ]]; then
    TERM=xterm-256color command ssh "$@"
  else
    command ssh "$@"
  fi
}

# =============================================================================
# ALIASES & FUNCTIONS
# =============================================================================
# The `dotfiles aliases` cheatsheet renders this section by parsing:
#   # @section: <Name>                       — section header (uppercased for display)
#   alias name="..."  # description           — alias entry (description required)
#   # @cheat: <name> | <description>          — free-form entry (any line)
#   # @cheat: <description>                   — function entry, paired with the
#   followed by `name() { ... }`                 next function definition
# aliases without trailing descriptions are silently skipped, which keeps the
# cheatsheet curated. See cmd_aliases / _aliases_parse in scripts/dotfiles

# editor (used as default $EDITOR for git, etc.)
export EDITOR="nvim"

# render man pages in nvim instead of less; plain less inside :terminal so
# `man foo` from an nvim shell doesn't nest another nvim
if [[ -n "$NVIM" ]]; then
  export MANPAGER="less"
else
  export MANPAGER="nvim +Man!"
fi

# @section: NAVIGATION

alias c="clear"                                                                # clear
alias cl="printf '\033[2J\033[3J\033[H'; [[ -n \$TMUX ]] && tmux clear-history || true"   # clear + scrollback
# @cheat: ..  | cd ..
alias ..="cd .."
# @cheat: ... | cd ../..
alias ...="cd ../.."

# @cheat: mkcd <dir> | mkdir + cd
mkcd() { mkdir -p "$1" && cd "$1"; }

# directory back/forward navigation (browser-style).
# cdb: previous directory; cdf: forward (after going back)
typeset -ga _dir_back_stack _dir_forward_stack
_dir_nav_active=0

_dir_track_chpwd() {
  # skip tracking when cdb/cdf triggered the change
  if (( _dir_nav_active )); then return; fi
  _dir_back_stack+=("$OLDPWD")
  _dir_forward_stack=()
  # cap stack size at 50 entries
  (( ${#_dir_back_stack} > 50 )) && _dir_back_stack=("${_dir_back_stack[@]: -50}")
}
chpwd_functions+=(_dir_track_chpwd)

# @cheat: cd back (browser)
cdb() {
  if (( ${#_dir_back_stack} == 0 )); then
    echo "No previous directory" >&2
    return 1
  fi
  local dest="${_dir_back_stack[-1]}"
  _dir_back_stack[-1]=()
  _dir_forward_stack+=("$PWD")
  _dir_nav_active=1
  cd "$dest"
  _dir_nav_active=0
}

# @cheat: cd forward (after cdb)
cdf() {
  if (( ${#_dir_forward_stack} == 0 )); then
    echo "No forward directory" >&2
    return 1
  fi
  local dest="${_dir_forward_stack[-1]}"
  _dir_forward_stack[-1]=()
  _dir_back_stack+=("$PWD")
  _dir_nav_active=1
  cd "$dest"
  _dir_nav_active=0
}

# directory history picker (autoloaded; bound to Opt+A via _cdl-widget earlier in this file)
autoload -Uz _cdl

# @cheat: Opt+A | cd from history (fzf)

# open buffer line in editor
autoload -Uz edit-command-line
zle -N edit-command-line
bindkey '^g' edit-command-line  # Ctrl+G to open current command line in $EDITOR (e.g. nvim)

# magic space binding to spacebar
bindkey ' ' magic-space  # Spacebar to expand aliases and re-evaluate the command line

# @section: FILES

# file listing (colour-aware: BSD ls uses -G, GNU ls uses --color=auto)
if [[ "$IS_MACOS" == "1" ]]; then
  alias ls="ls -G"                                                             # ls (colour-aware)
else
  alias ls="ls --color=auto"
fi
alias ll="ls -alF"                                                             # ls -alF
alias la="ls -A"                                                               # ls -A
alias l="ls -CF"                                                               # ls -CF

# safer file operations
alias cp="cp -i"                                                               # cp -i (safe overwrite)
alias mv="mv -i"                                                               # mv -i (safe overwrite)

# suffix aliases
alias -s md='-t glow' # View markdown files with syntax highlighting using glow (if installed)

# yazi: launch the file manager, then cd the shell to wherever you quit.
# uses --cwd-file so a plain `q` lands you in the last-browsed directory
# @cheat: yazi file manager (cd to last dir on quit)
y() {
  local tmp cwd
  tmp="$(mktemp -t yazi-cwd.XXXXXX)"
  yazi "$@" --cwd-file="$tmp"
  if cwd="$(command cat -- "$tmp")" && [[ -n "$cwd" && "$cwd" != "$PWD" ]]; then
    builtin cd -- "$cwd"
  fi
  rm -f -- "$tmp"
}

# @section: SEARCH & PROCESS

alias grep="grep --color=auto"                                                 # grep --color=auto
# @cheat: rg | ripgrep (fast search)
# @cheat: psg <name> | ps aux | grep
alias psg="ps aux | grep -v grep | grep"
alias ports="lsof -i -P -n | grep LISTEN"                                      # lsof ports (local)

# @section: GIT

alias gs="git status -sb"                                                      # git status -sb
alias gd="git diff"                                                            # git diff
alias gdn="git diff | diffnav"                                                 # git diff (diffnav)
alias gds="git diff --stat"                                                    # git diff --stat
alias gl="git log --graph --decorate --format='%C(yellow)%h%C(reset) %s %C(dim)(%ar, %an)%C(reset)' -20"                          # git log (last 20)
alias glf="git log --graph --decorate --format='%C(yellow)%h%C(reset) %s %C(dim)(%ad, %an)%C(reset)' --date=format:'%d %B %Y %H:%M'"  # git log (full)
alias gco="git checkout"                                                       # git checkout
alias gsw="git switch"                                                         # git switch
alias gb="git branch -vv"                                                      # git branch -vv
alias gp="git push"                                                            # git push
alias gpl="git pull"                                                           # git pull
alias gst="git stash"                                                          # git stash
alias gfp="git fetch -pf"                                                      # git fetch --prune
alias gpr="git branch -vv | grep ': gone]' | awk '{print \$1}' | xargs -r git branch -D"  # prune local branches
alias grmc="git rm --cached"                                                   # git rm --cached
alias gca="git commit --amend"                                                 # git commit --amend

# make: forward to repo root when no Makefile in current directory
make() {
  if [[ ! -f Makefile && ! -f makefile && ! -f GNUmakefile ]]; then
    local root
    root=$(git rev-parse --show-toplevel 2>/dev/null)
    if [[ -n "$root" && -f "$root/Makefile" ]]; then
      command make -C "$root" "$@"
      return
    fi
  fi
  command make "$@"
}

# @section: TMUX

alias tls="~/.tmux/scripts/resurrect/restore.sh --list"                        # list session backups
# @cheat: ta/tattach | attach/restore session
alias ta="tattach"
# @cheat: ac | clear all tmux alerts
alias alerts-clear="rm -rf ${XDG_CONFIG_HOME:-$HOME/.config}/tmux-alerts"
alias ac="alerts-clear"
alias tcleanup="~/.tmux/scripts/tests/cleanup-tests.sh"                        # clean test resources

# asciinema demo recording (no cheatsheet entry)
alias demo-rec='asciinema rec --idle-time-limit 2 --cols 120 --rows 35'

# functions (instead of aliases) for tab completion support
# @cheat: restore from backup
trestore() {
  ~/.tmux/scripts/resurrect/restore.sh "$@"
}

# @cheat: delete session backup
tkill() {
  ~/.tmux/scripts/resurrect/delete.sh "$@"
}

# attach to tmux session, restoring from backup if needed
tattach() {
  # try to attach to running session
  if tmux a -t "$1" 2>/dev/null; then return 0; fi

  # not running, try to restore from backup
  local backup="${HOME}/.tmux/resurrect/sessions/$1.txt"
  if [[ -f "$backup" ]]; then
    echo "Restoring '$1' from backup..."
    if ~/.tmux/scripts/resurrect/restore.sh --session "$1" && tmux a -t "$1"; then
      return 0
    fi
    # restore failed, backup is stale
    echo "Backup stale, removing: $1"
    rm -f "$backup"
    return 1
  fi
  echo "No session or backup found: $1"
  return 1
}

# terminal entry to the launcher system: no args opens the launcher picker,
# with a query it resolves a directory via zoxide and opens a dev session
# there (attaches if the session already exists, creates it otherwise)
# @cheat: tl | launcher picker (no args) or zoxide query into a dev session
tl() {
  if (( $# == 0 )); then
    ~/.tmux/scripts/launchers/picker.sh
    return
  fi

  local dir
  if [[ -d "$1" ]]; then
    dir="$1"
  elif ! dir=$(zoxide query -- "$@" 2>/dev/null); then
    echo "tl: no directory match for '$*'" >&2
    return 1
  fi

  # keep frecency fresh when launched from an explicit path
  zoxide add "$dir" 2>/dev/null || true
  dev "$dir"
}

# tab completion for tmux commands
_trestore_complete() {
  local -a options sessions
  options=(
    '--session[Restore a specific session]:session:->sessions'
    '-s[Restore a specific session]:session:->sessions'
    '--delete[Delete a session backup]:session:->sessions'
    '-d[Delete a session backup]:session:->sessions'
    '--list[List available sessions]'
    '-l[List available sessions]'
    '--replace[Kill existing session before restoring]'
    '--help[Show usage]'
    '-h[Show usage]'
  )

  _arguments -s "${options[@]}"

  case "$state" in
    sessions)
      sessions=(${(f)"$(ls ~/.tmux/resurrect/sessions/*.txt 2>/dev/null | xargs -n1 basename -s .txt)"})
      _describe 'session backups' sessions
      ;;
  esac
}

_tmux_sessions_running() {
  # complete with running tmux sessions (for tkill and tattach)
  local -a sessions
  sessions=(${(f)"$(tmux list-sessions -F '#{session_name}' 2>/dev/null)"})
  _describe 'running tmux sessions' sessions
}

# register completion functions
compdef _trestore_complete trestore
compdef _tmux_sessions_running tkill
compdef _tmux_sessions_running tattach

# @section: SYSTEM & NETWORK

alias df="df -h"                                                               # df -h
alias du="du -sh"                                                              # du -sh
alias myip="curl -s ifconfig.me"                                               # curl ifconfig.me
alias v="cl && nvim"                                                           # clear + nvim

# edit a root-owned file with your real nvim config. sudoedit copies the file
# to a temp path, opens it as YOU (so plugins/config load normally, and nvim
# never runs as root), then writes it back with elevated privileges. this also
# sidesteps the reason plain `sudo nvim` fails: sudo's secure_path doesn't
# include Homebrew's bin, so root can't find nvim at all.
# SUDO_EDITOR must be an ABSOLUTE path: sudoedit resolves a bare editor name
# against secure_path (not your shell's PATH), so "nvim" isn't found there and
# sudo silently falls back to its compiled default editor (nano). command -v
# expands it to the real Homebrew path, portable across the macOS/Linux prefixes
# @cheat: svim <file> | sudo-edit a root-owned file (sudoedit + nvim)
svim() { SUDO_EDITOR="$(command -v nvim)" sudoedit "$@"; }

# open: platform-aware (macOS: open, Linux: xdg-open)
if [[ "$IS_MACOS" == "1" ]]; then
  alias o="open"                                                               # open file/dir
  alias finder="open ."                                                        # open in Finder (macOS)
else
  alias o="xdg-open"
fi

# quick access to config files
alias config="v ~/.config"                                                     # open nvim in ~/.config (dir)
alias cache="v ~/.cache"                                                       # open nvim in ~/.cache (dir)
alias zshrc="v ~/.zshrc"                                                       # open nvim in ~/.zshrc (file)
alias secrets="v ~/.config/zsh/secrets.zsh"                                    # open nvim in secrets.zsh (file)
alias launchers="v ~/.config/dotfiles/launchers"                               # open launcher configs (dir)
alias nconf="v ~/.config/nvim/local.lua"                                       # open nvim local config (file)
alias gconf="v ~/.config/ghostty/local"                                        # open ghostty local config (file)
alias tconf="v ~/.config/tmux/local.conf"                                      # open tmux local config (file)

# font preview (figlet/toilet font browser with fzf)
# @cheat: font-preview | font browser (fzf)
autoload -Uz font-preview

# clipboard: `<cmd> | clip` copies, bare `clip` pastes, -p forces paste.
# the backend is chosen from the live display server rather than binary presence
# alone: a wayland session usually has xclip installed too (via XWayland), and
# choosing it there writes to a clipboard nothing reads back. with no display
# server at all (headless, ssh) it falls back to OSC 52, which tmux forwards to
# the outer terminal via `set-clipboard on`. mirrors scripts/_lib/clipboard.sh;
# keep the two in sync
# @cheat: clip [-p] | copy stdin to clipboard, bare or -p pastes
clip() {
  emulate -L zsh
  local paste=0

  case "$1" in
    -p|-o|--paste) paste=1 ;;
    -h|--help)
      printf 'usage: <cmd> | clip    copy stdin to the clipboard\n'
      printf '       clip [-p]       paste the clipboard to stdout\n'
      return 0
      ;;
    # nothing piped in: read the clipboard rather than copy over it. stdin is
    # not a tty in a script, so bare `clip` copies there and blocks on empty
    # stdin, exactly as bare `pbcopy` does; use -p where the direction must not
    # depend on context
    '') [[ -t 0 ]] && paste=1 ;;
    *)
      printf 'clip: unknown option: %s\n' "$1" >&2
      return 2
      ;;
  esac

  local backend
  if [[ "$IS_MACOS" == "1" ]]; then
    backend=pb
  elif [[ -n "$WAYLAND_DISPLAY" ]] && (( $+commands[wl-copy] )); then
    backend=wayland
  elif [[ -n "$DISPLAY" ]] && (( $+commands[xclip] )); then
    backend=xclip
  elif [[ -n "$DISPLAY" ]] && (( $+commands[xsel] )); then
    backend=xsel
  elif (( $+commands[clip.exe] )); then
    backend=wsl
  elif (( $+commands[termux-clipboard-set] )); then
    backend=termux
  elif [[ -n "$WAYLAND_DISPLAY" || -n "$DISPLAY" ]]; then
    # a display server is running but its tool is missing. this must not fall
    # through to OSC 52: that silently pushes the payload out through the
    # terminal, and any ssh hop or tmux in between, when the local clipboard
    # sitting right there was what was asked for
    backend=missing
  else
    backend=osc52
  fi

  if (( paste )); then
    case "$backend" in
      pb)      pbpaste ;;
      wayland) wl-paste --no-newline ;;
      xclip)   xclip -selection clipboard -o ;;
      xsel)    xsel --clipboard --output ;;
      wsl)     powershell.exe -NoProfile -Command Get-Clipboard | tr -d '\r' ;;
      termux)  termux-clipboard-get ;;
      missing) _clip_missing ;;
      # OSC 52 reads are refused or prompt-gated by most terminals, so there is
      # nothing to fall back to here
      osc52)
        printf 'clip: no clipboard to read from (no display server; OSC 52 is write-only)\n' >&2
        return 1
        ;;
    esac
  else
    case "$backend" in
      pb)      pbcopy ;;
      wayland) wl-copy ;;
      xclip)   xclip -selection clipboard ;;
      xsel)    xsel --clipboard --input ;;
      wsl)     clip.exe ;;
      termux)  termux-clipboard-set ;;
      missing) _clip_missing ;;
      osc52)   _clip_osc52 ;;
    esac
  fi
}

# a display server is running but no tool for it is installed. name the one that
# matches the session rather than listing all of them
_clip_missing() {
  emulate -L zsh
  if [[ -n "$WAYLAND_DISPLAY" ]]; then
    printf 'clip: no clipboard tool for this wayland session; install wl-clipboard\n' >&2
  else
    printf 'clip: no clipboard tool for this X11 session; install xclip or xsel\n' >&2
  fi
  return 1
}

# write stdin to the terminal clipboard via OSC 52. needs a writable tty, and
# terminals cap the payload, so oversized input is refused rather than silently
# truncated into a half-copy. writes to /dev/tty, never stdout, so redirecting
# clip's output never lands the escape sequence in a file
_clip_osc52() {
  emulate -L zsh
  local b64
  b64=$(base64 | tr -d '\r\n') || return 1

  if [[ ! -w /dev/tty ]]; then
    printf 'clip: no tty available for OSC 52\n' >&2
    return 1
  fi
  if (( ${#b64} > 74994 )); then
    printf 'clip: input too large for OSC 52 (%d encoded bytes)\n' "${#b64}" >&2
    return 1
  fi

  printf '\033]52;c;%s\a' "$b64" > /dev/tty
}

# compat shims, Linux only: macOS has the real binaries, and anything piping to
# pbcopy keeps working. no cheatsheet entry (clip is the documented name)
if [[ "$IS_MACOS" != "1" ]]; then
  alias pbcopy="clip"
  alias pbpaste="clip -p"
fi

# @section: DEVELOPMENT

alias opencode="cl && opencode"                                                # cl + opencode
alias oc="opencode"
alias claude="cl && claude"                                                    # cl + claude
alias ralph="cl && ralph"
alias ralf="cl && ralf"
alias copilot="cl && copilot"                                                  # cl + copilot
alias btop="cl && btop"
alias drs="dash-repo-sync"                                                     # sync repo paths
alias ff="fastfetch"                                                           # fastfetch system info
alias dash="cl && gh dash"                                                     # cl + gh dash
alias j="cl && jiru"                                                           # cl + jiru (Jira TUI)
alias lg="cl && lazygit"                                                       # cl + lazygit
alias ld="cl && lazydocker"                                                    # cl + lazydocker
# aerc reads config from ~/Library/Preferences/aerc on macOS by default; point it
# at ~/.config/aerc so it matches the rest of the dotfiles (harmless on linux)
alias aerc='aerc -C "${XDG_CONFIG_HOME:-$HOME/.config}/aerc/aerc.conf" -A "${XDG_CONFIG_HOME:-$HOME/.config}/aerc/accounts.conf" -B "${XDG_CONFIG_HOME:-$HOME/.config}/aerc/binds.conf"'  # terminal email client
alias gols="ls ~/go/bin"                                                       # list Go binaries
alias nvim-clear="rm -rf ~/.cache/nvim/luac/ && echo 'Cleared Neovim bytecode cache'"   # clear nvim cache

# sync all Lazy.nvim plugins (headless)
# @cheat: nvim-sync | sync Lazy.nvim plugins
nvim-sync() {
  printf "Syncing Neovim plugins...\n"
  nvim --headless "+Lazy! sync" +qa
  printf "\033[0;32m✔\033[0m Neovim plugins synced\n"
}

# render code or terminal output to an image, defaulting to a mono / nerd font.
# freeze's built-in default points at an uninstalled family and silently falls
# back to a proportional sans, so force a real monospace family. pass -F to pick
# another installed mono font via fzf; the choice persists in $FREEZE_FONT for
# the session (bare `freeze -F` just sets it). an explicit --font.family /
# --font.file always wins.
# @cheat: freeze [-F] <file> | render code/output to an image (mono font)
freeze() {
  emulate -L zsh
  local default_font="JetBrainsMono Nerd Font Mono"
  local -a args
  local a picked=0

  for a in "$@"; do
    case "$a" in
      -F|--pick-font) picked=1 ;;
      *) args+=("$a") ;;
    esac
  done

  if (( picked )); then
    local chosen
    # installed monospace families, collapsed to base names: drop style/weight
    # variants, the non-mono "Nerd Font" spelling and the NF/NFM abbreviations
    # (keeping Monaspace, whose canonical family name ends in NF)
    chosen=$(fc-list :spacing=mono family 2>/dev/null \
      | tr ',' '\n' | sed 's/^[[:space:]]*//; s/[[:space:]]*$//' \
      | grep -v '^\.' | grep -viE 'emoji|lastresort|times lt mm' \
      | grep -viE 'extrabold|extralight|semibold|semiwide|medium|light|thin|bold|italic|wide|narrow|black|retina|condensed|oblique' \
      | awk '/ Nerd Font$/ {next} /Monaspace/ {print; next} / NFM?$/ {next} {print}' \
      | sort -u \
      | fzf --prompt='freeze font ❯ ' --height=40% --reverse)
    [[ -n "$chosen" ]] && export FREEZE_FONT="$chosen" \
      && printf '\033[0;32m✔\033[0m freeze font → %s\n' "$chosen"
    (( ${#args} )) || return 0
  fi

  if [[ "${args[*]}" != *--font.family* && "${args[*]}" != *--font.file* ]]; then
    args=(--font.family "${FREEZE_FONT:-$default_font}" "${args[@]}")
  fi

  command freeze "${args[@]}"
}

# completion for the freeze wrapper: carapace's freeze spec completes flags and
# their values (-l languages, -t themes, ...) but offers nothing for the file
# positional and errors on our synthetic -F. delegate to carapace with -F hidden,
# then add file completion for the positional (skipped after a non-file value
# flag so languages/themes aren't mixed with filenames). wins over carapace's
# catch-all because this compdef runs after it
_freeze() {
  local -a _ws _fw
  local _cur _i _rm

  if (( $+functions[_carapace_completer] )); then
    _ws=("${words[@]}"); _cur=$CURRENT; _rm=0
    for (( _i = 1; _i <= $#words; _i++ )); do
      if (( _i != CURRENT )) && [[ ${words[_i]} == (-F|--pick-font) ]]; then
        (( _i < CURRENT )) && (( _rm++ ))
        continue
      fi
      _fw+=("${words[_i]}")
    done
    words=("${_fw[@]}"); (( CURRENT -= _rm ))
    _carapace_completer
    words=("${_ws[@]}"); CURRENT=$_cur
  fi

  case ${words[CURRENT-1]} in
    -l|--language|-t|--theme|-w|--wrap|-x|--execute|-b|--background|-m|--margin|-p|--padding|-W|--width|-H|--height|-r|--border.radius|--border.width|--border.color|--shadow.blur|--shadow.x|--shadow.y|--font.family|--font.size|--line-height) ;;
    *) _files; compadd -- -F --pick-font ;;
  esac
}
(( $+functions[compdef] )) && compdef _freeze freeze

alias brewup="brew update && brew upgrade"                                     # brew update + upgrade
alias nuke-node='killall -9 node 2>/dev/null && echo "done" || echo "no node processes"'                                                                                            # kill all node procs
alias nuke-nvim='ps -eo pid,ppid,args | awk "/nvim --embed/ && \$2 == 1 {print \$1}" | xargs kill 2>/dev/null && echo "done" || echo "no stale nvim processes"'                       # kill stale nvim procs
alias nuke-dotnet='dotnet build-server shutdown 2>/dev/null; pkill -f "OmniSharp.dll" 2>/dev/null; pkill -f "EasyDotnet.BuildServer.dll" 2>/dev/null; pkill -f "dotnet-easydotnet" 2>/dev/null; pkill -f "VBCSCompiler" 2>/dev/null; pkill -f "vstest.console.dll" 2>/dev/null; echo "done"'   # kill stale dotnet procs
alias dot="dotfiles"

# relocate claude code per-project data (session transcripts + memories) so it
# follows a moved project. claude keys the dir on the absolute path with every
# non-alphanumeric char replaced by '-'. refuses to merge onto an existing
# destination to avoid clobbering a memory index; leaves the source in place
_move_claude_data() {
  emulate -L zsh
  local base="$HOME/.claude/projects"
  local src_dir="$base/${1//[^A-Za-z0-9]/-}"
  local dest_dir="$base/${2//[^A-Za-z0-9]/-}"

  [[ -d "$src_dir" && "$src_dir" != "$dest_dir" ]] || return 0

  if [[ -e "$dest_dir" ]]; then
    printf "\033[0;33m!\033[0m claude history exists at the destination; left it at %s\n" "${src_dir:t}" >&2
    return 0
  fi

  command mv "$src_dir" "$dest_dir" \
    && printf "\033[0;32m✔\033[0m claude history + memories moved\n"
}

# move a project between playground (PROJECTS_ROOT) and code (DEV_ROOT).
# graduate promotes playground → code; relegate sends code → playground.
# moves claude history, repoints gh-dash paths, then cd into the new home
_move_project() {
  emulate -L zsh
  local src_root="$1" dest_root="$2" name="${3:t}" verb="$4"

  if [[ -z "$name" ]]; then
    printf "usage: %s <project>\n" "$verb" >&2
    return 2
  fi

  local src="$src_root/$name" dest="$dest_root/$name"
  if [[ ! -d "$src" ]]; then
    printf "\033[0;31m✘\033[0m not found: %s\n" "$src" >&2
    return 1
  fi
  if [[ -e "$dest" ]]; then
    printf "\033[0;31m✘\033[0m already exists: %s\n" "$dest" >&2
    return 1
  fi

  command mkdir -p "$dest_root"
  command mv "$src" "$dest" || return 1
  printf "\033[0;32m✔\033[0m %s → %s\n" "$src" "$dest"

  _move_claude_data "$src" "$dest"

  if command -v dash-repo-sync >/dev/null 2>&1; then
    dash-repo-sync >/dev/null 2>&1 && printf "\033[0;32m✔\033[0m gh-dash paths synced\n"
  fi

  cd "$dest"
}

# @cheat: promote to code
graduate() {
  local name="${1:t}"
  _move_project "${PROJECTS_ROOT:-$HOME/playground}" "${DEV_ROOT:-$HOME/code}" "$name" graduate || return
  # nvim resolves local dev plugins from playground only (lazy dev.path), so a
  # graduated plugin silently falls back to its remote; flag it
  if [[ "$name" == *.nvim || -d "$PWD/lua" ]]; then
    printf "\033[0;33m!\033[0m looks like an nvim plugin: lazy dev.path points at playground, so this'll fall back to the remote. keep it in playground or update nvim/init.lua\n" >&2
  fi
}

# @cheat: demote to playground
relegate() {
  _move_project "${DEV_ROOT:-$HOME/code}" "${PROJECTS_ROOT:-$HOME/playground}" "${1:t}" relegate
}

# graduate completes from playground dirs, relegate from code dirs
_graduate_complete() {
  local root="${PROJECTS_ROOT:-$HOME/playground}"
  local -a projects; projects=(${root}/*(/N:t))
  _describe 'playground projects' projects
}
_relegate_complete() {
  local root="${DEV_ROOT:-$HOME/code}"
  local -a projects; projects=(${root}/*(/N:t))
  _describe 'code projects' projects
}
compdef _graduate_complete graduate
compdef _relegate_complete relegate

# promote/demote synonyms (completion follows the alias automatically)
alias promote="graduate"
alias demote="relegate"

# =============================================================================
# ZSH LINE EDITOR (ZLE) KEYBINDINGS
# =============================================================================
# note: bindkey -e (emacs mode) and KEYTIMEOUT are set earlier, before plugins,
# so custom bindings from fzf and ZLE widgets aren't wiped

# ensure common word deletion shortcuts work correctly
bindkey '^[^?' backward-kill-word      # Option+Backspace: delete word backwards
bindkey '^W' backward-kill-word        # Ctrl+W: delete word backwards

# Shift+Tab walks backwards through menu completions (complements Tab going forward)
bindkey '^[[Z' reverse-menu-complete

# bind Home/End in both forms: Ghostty sends CSI H/F directly; tmux with
# extended-keys re-encodes them as VT220-style \x1b[1~ and \x1b[4~
bindkey '\e[H'  beginning-of-line      # Home (Ghostty, CSI)
bindkey '\e[F'  end-of-line            # End (Ghostty, CSI)
bindkey '\e[1~' beginning-of-line      # Home (tmux-encoded)
bindkey '\e[4~' end-of-line            # End (tmux-encoded)
# \e[1~ shares the prefix \e[1 with modifier+arrow sequences (\e[1;2A etc).
# binding the full sequences resolves the ambiguity so ZLE doesn't garble them
bindkey '\e[1;2A' up-line-or-history   # Shift+Up
bindkey '\e[1;2B' down-line-or-history # Shift+Down
bindkey '\e[1;2C' forward-word         # Shift+Right
bindkey '\e[1;2D' backward-word        # Shift+Left
bindkey '\e[1;3A' up-line-or-history   # Opt+Up
bindkey '\e[1;3B' down-line-or-history # Opt+Down
bindkey '\e[1;5H' beginning-of-line   # Cmd+Up (via Ghostty: super+up → Ctrl+Home)
bindkey '\e[1;5F' end-of-line         # Cmd+Down (via Ghostty: super+down → Ctrl+End)

# Ctrl+J / Ctrl+K as Down/Up for menu + line nav (overrides accept-line/kill-line;
# Return still submits via ^M). scoped to zsh so nvim's own C-j/C-k are untouched
# @cheat: Ctrl+J / Ctrl+K | down / up in history, line, and completion menu
bindkey '^j' down-line-or-history     # Ctrl+J → Down
bindkey '^k' up-line-or-history       # Ctrl+K → Up
# and move the highlight inside the tab-completion menu
zmodload -i zsh/complist 2>/dev/null
bindkey -M menuselect '^j' down-line-or-history
bindkey -M menuselect '^k' up-line-or-history
# @cheat: Cmd+Backspace | delete to line start
bindkey '\e[127;5u' backward-kill-line # Cmd+Backspace (via Ghostty: super+backspace → Ctrl+Backspace)

# Ghostty sends these sequences for modifier+enter combos; bind them to
# accept-line so they act as Enter in zsh instead of printing garbage
bindkey '\e[13;5u'  accept-line        # Ctrl+Enter (kitty protocol)
bindkey '\e[13;6u'  accept-line        # Ctrl+Shift+Enter (kitty protocol)
bindkey '\e[;5;13~' accept-line        # Ctrl+Enter (Ghostty variant)
bindkey '\e[;6;13~' accept-line        # Ctrl+Shift+Enter (Ghostty variant)

# Ctrl+key combos with no legacy control-char encoding (Ctrl+-, Ctrl+=)
# arrive as CSI-u sequences (extended-keys-format csi-u). bind the actual
# csi-u form so ZLE consumes the whole sequence instead of leaking the tail
# (e.g. ';5u') as literal text. Ctrl+Shift+- already maps to undo via the
# legacy ^_ byte, so wire Ctrl+- to redo as its mirror
bindkey    '\e[45;5u' redo             # Ctrl+- → redo (mirrors Ctrl+Shift+- → undo)
bindkey -s '\e[61;5u' ''               # Ctrl+= (swallow)
# legacy modifyOtherKeys fallback (if extended-keys-format ever changes)
bindkey    '\e[27;5;45~' redo          # Ctrl+- → redo
bindkey -s '\e[27;5;61~' ''            # Ctrl+= (swallow)

# =============================================================================
# DOTFILES CLI
# =============================================================================
# tab completion for dotfiles command (autoloaded from zsh/functions/_dotfiles)
autoload -Uz _dotfiles
compdef _dotfiles dotfiles
compdef _dotfiles dot

# =============================================================================
# COMMAND EXIT ALERTS (auto-alert for long-running commands)
# =============================================================================
# automatically sends a tmux alert when a command finishes after ≥10 seconds
# and you've switched away from the window while it was running
[[ -f "$DOTFILES_ROOT/scripts/hooks/cmd-alert-hook.zsh" ]] && source "$DOTFILES_ROOT/scripts/hooks/cmd-alert-hook.zsh"

# =============================================================================
# ZOXIDE
# =============================================================================
# eager init so `z` is defined in every shell mode: interactive, `zsh -i -c`
# (Claude Code's !-shell), and `zsh -c` (Bash tool).
#
# override __zoxide_doctor with a no-op. its heuristic checks whether
# __zoxide_hook lives in chpwd_functions, but Claude Code's shell snapshots
# capture function definitions without the chpwd_functions array, so the
# check fails spuriously on every replay. env-based silencing via
# _ZO_DOCTOR=0 doesn't survive snapshotting; overriding the function does
if command -v zoxide >/dev/null 2>&1; then
  eval "$(zoxide init --cmd cd zsh)"
  __zoxide_doctor() { :; }
fi

# =============================================================================
# SHELL STARTUP PROFILING
# =============================================================================
# @section: PROFILING

# quick benchmark: runs zsh 5 times and shows startup time
# @cheat: benchmark startup (5x)
zsh-profile() {
  echo "Running 5 iterations..."
  for i in {1..5}; do
    time zsh -i -c exit
  done
}

# detailed profiling: shows what's taking time during startup
# @cheat: detailed (ZPROF)
zsh-profile-detailed() {
  ZPROF=1 zsh -i -c exit
}

# =============================================================================
# DOTFILES CLI CHEATSHEET
# =============================================================================
# these rows describe `dotfiles` subcommands (not zsh aliases), declared as
# free-form @cheat directives so `dotfiles aliases` can render them alongside
# the shell shortcuts above
# @section: DOTFILES CLI
# @cheat: update  -u | smart update
# @cheat: status  -s | version + sync + changes
# @cheat: health | full health check
# @cheat: links   -l | managed symlinks
# @cheat: theme   -t | colour themes
# @cheat: set dev <d> | set DEV_ROOT
# @cheat: diff    -d | copy-on-install diffs
# @cheat: sync | sync copy-on-install
# @cheat: export | local layer to private repo
# @cheat: import | local layer from private repo
# @cheat: local | manage local-layer repo
# @cheat: notes   -n | browse changelog
# @cheat: version -v | version, preset, theme
# @cheat: edit    -e | open in $EDITOR
# @cheat: aliases -a | show this reference
# @cheat: dot | shorthand for dotfiles
# @cheat: help | show help message

# =============================================================================
# ZPROF OUTPUT (end of startup)
# =============================================================================
# print profiling results if ZPROF is set
[[ -n "$ZPROF" ]] && zprof || true
