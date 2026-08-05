# Brewfile - Homebrew Bundle
# Install with: brew bundle install
#
# Preset markers:
#   @preset: minimal - included in minimal, core, and full
#   @preset: core    - included in core and full
#   @preset: full    - included in full only

# Taps
tap "Adembc/homebrew-tap"
tap "charmbracelet/tap"
tap "libsql/sqld"
tap "morantron/tmux-fingers"
tap "neur0map/tap"
tap "oven-sh/bun"
tap "undont/tap"
tap "teamookla/speedtest"

# =============================================================================
# @preset: minimal
# Shell & Terminal Essentials (zsh + tmux)
# =============================================================================

brew "zsh"
brew "tmux"                   # >= 3.3 required for popup support
brew "powerlevel10k"
brew "zsh-autosuggestions"
brew "zsh-completions"
brew "fzf"                    # >= 0.40 for --tmux flag
brew "direnv"
brew "carapace"               # Multi-shell completion provider (bridges zsh completion)

# =============================================================================
# @preset: core
# Editors & Development Tools
# =============================================================================

# Editors
brew "neovim"            # >= 0.11 required for nvim-treesitter
brew "tree-sitter-cli"   # Required by nvim-treesitter for parser compilation
cask "zed"               # editor
brew "duti"              # macOS-only; sets Zed as default handler for code files

# AI Coding Assistants
brew "opencode"
cask "codexbar" # Menu bar usage monitor for Codex and Claude

# Git & GitHub
brew "gh"
brew "lazygit"       # Git TUI

# Search & Navigation
brew "ripgrep"       # >= 13.0
brew "fd"            # Fast find alternative
brew "tree"
brew "jq"
brew "yq"            # YAML processor (used by gh-dash local merge)
brew "wget"
brew "bat"           # Cat with syntax highlighting
brew "diffnav"       # Diff navigator for GitHub PRs
brew "monolith" unless OS.linux? && Hardware::CPU.arm?  # No Linux ARM bottle
brew "zoxide"        # smart cd replacement

# File Manager
brew "yazi"          # Terminal file manager
brew "poppler"       # PDF rendering (pdftoppm) for yazi file previews
brew "ffmpegthumbnailer"  # Video thumbnails for yazi file previews
brew "resvg"         # SVG rendering for yazi file previews
brew "sevenzip"      # Archive previews (7zz) for yazi file previews

# Build Tools
brew "binutils" # GNU binary utilities
brew "gcc"      # GNU compiler collection
brew "nasm"     # Netwide assembler
brew "nano"     # Text editor
brew "bear"     # Generates compile_commands.json for clang tooling (C/C++/ObjC)

# Tmux Extras
brew "morantron/tmux-fingers/tmux-fingers" # Quick pattern copy (requires gcc on Linux)
brew "undont/tap/poke"                     # Terminal-native teammate pokes (tmux status segment)

# =============================================================================
# @preset: core
# Languages & Runtimes
# =============================================================================

# Node.js (via fnm - Fast Node Manager)
brew "fnm"             # macOS-only (Linux uses curl installer)
brew "oven-sh/bun/bun" # >= 1.0

# Go
brew "go"

# Python
brew "python@3.13"
brew "uv"            # Python package + tool manager (replaces pipx; `uv tool install`, `uvx`)


# Java
brew "openjdk"
cask "zulu@17"

# Android (commandline tools — SDK manager, emulator, adb)
cask "android-commandlinetools"

# .NET
cask "dotnet-sdk"

# =============================================================================
# @preset: core
# Development Tools
# =============================================================================

# Code Quality
brew "shellcheck"                    # Shell script linter
brew "luacheck"                      # Lua linter
brew "undont/tap/supplyscan" # Supply chain vulnerability scanner
brew "sonar-scanner"

# Database
brew "postgresql@17"
brew "mongosh"
brew "libsql/sqld/sqld"
brew "undont/tap/seeql"     # SQL client TUI

# Containers & Infrastructure
brew "act"                          # GitHub Actions locally
brew "cloudflared"                  # Cloudflare Tunnel client
brew "lazydocker"                   # Docker TUI
brew "Adembc/homebrew-tap/lazyssh"  # SSH host manager TUI

# Misc Dev Tools
brew "cmake"
brew "staticcheck"   # Go linter
brew "golangci-lint" # Go meta-linter
brew "swift-format"  # macOS-only
brew "swiftlint"     # macOS-only; Swift linter (nvim-lint)
brew "golang-migrate"
brew "scc"
brew "httpyac"

# =============================================================================
# @preset: core
# Extra Utilities & Tools
# =============================================================================

brew "ffmpeg"
brew "imagemagick"
brew "btop"                          # System monitor (htop replacement)
brew "gdu"                           # Disk usage analyzer TUI (du replacement)
brew "watch"                         # Periodic command refresh (flicker-free re-render)
brew "fastfetch"                     # neofetch replacement (faster, maintained)
brew "teamookla/speedtest/speedtest" # Speedtest CLI from Ookla
brew "glow"                          # Markdown renderer
brew "asciinema"                     # Terminal session recorder
brew "figlet"                        # ASCII art text banners
brew "toilet"                        # Unicode/colour text banners (figlet-compatible)
brew "chafa"                         # Terminal image renderer (used by music.nvim)
brew "charmbracelet/tap/freeze"      # Render code/terminal output to an image
brew "undont/tap/jiru"               # Jira TUI app
brew "neur0map/tap/gpk"              # Unified package manager TUI
brew "snitch" unless OS.linux? && Hardware::CPU.arm? # No Linux ARM bottle

# =============================================================================
# @preset: core
# Terminal & Fonts
# =============================================================================

# Terminal
cask "ghostty"

# Cloud
cask "gcloud-cli"

# Nerd Fonts for terminal icons
cask "font-meslo-lg-nerd-font"
cask "font-jetbrains-mono-nerd-font"
cask "font-monaspace-nf"            # Monaspace Neon NF

# =============================================================================
# @preset: full
# macOS-Specific Applications
# =============================================================================

# Automation
cask "hammerspoon"
cask "karabiner-elements"  # Keyboard customisation

# Music
cask "music-presence"      # Discord Rich Presence for Apple Music

# Utilities
cask "raycast"             # Spotlight replacement
