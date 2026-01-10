# Dotfiles

[![CI](https://github.com/seanhalberthal/dotfiles/actions/workflows/ci.yml/badge.svg)](https://github.com/seanhalberthal/dotfiles/actions/workflows/ci.yml)
[![Neovim](https://img.shields.io/badge/Neovim-0.9+-green?logo=neovim)](https://neovim.io/)
[![Tmux](https://img.shields.io/badge/Tmux-3.3+-orange?logo=tmux)](https://github.com/tmux/tmux)
[![License](https://img.shields.io/badge/License-MIT-yellow)](LICENSE)

Personal configuration files for zsh, tmux, neovim, hammerspoon, ghostty, and karabiner.

## Contents

```
dotfiles/
├── zsh/              # Zsh shell configuration
│   ├── .zshrc
│   ├── .zprofile
│   ├── .p10k.zsh     # Powerlevel10k theme
│   └── .zsh/         # Additional zsh configs
├── tmux/             # Tmux terminal multiplexer
│   ├── .tmux.conf
│   └── .tmux/        # Scripts and help files
├── nvim/             # Neovim configuration
│   ├── init.lua      # Entry point
│   └── lua/custom/   # Modular config
│       ├── core/     # Options, keymaps, autocmds
│       └── plugins/  # Plugin configurations
├── bin/              # Custom scripts
│   ├── tm            # Tmux dev session launcher
│   └── dana          # Dana project launcher
├── hammerspoon/      # macOS automation
│   └── init.lua
├── ghostty/          # Terminal emulator
│   └── config
├── karabiner/        # Keyboard customisation
│   └── karabiner.json
├── scripts/          # Installation and utility scripts
│   ├── install/      # Installer modules
│   ├── hooks/        # Tool hooks (e.g. Claude alerts)
│   └── _lib/         # Shared shell libraries
└── Brewfile          # Homebrew dependencies
```

## Quick Start

### Prerequisites

- macOS (some features are macOS-specific, keybind remapping is Macbook Pro specific)

### Automatic Installation

```bash
# Clone the repository
git clone https://github.com/seanhalberthal/dotfiles.git ~/dotfiles
cd ~/dotfiles

# Run the installer
./install.sh
```

The installer will:
1. Install/update Homebrew
2. Install all packages from `Brewfile`
3. Check prerequisites
4. Backup existing configuration
5. Create symlinks
6. Install plugin managers (TPM)
7. Create secrets file from template
8. Run a health check

### Installation Options

```bash
./install.sh              # Full installation
./install.sh --skip-brew  # Skip Homebrew/package installation
./install.sh --skip-backup # Skip backing up existing configs
./install.sh --check-only  # Only run prerequisite and health checks
```

### Post-Installation

1. **Restart your terminal** or run `source ~/.zshrc`
2. **Install tmux plugins**: Open tmux and press `` ` + I ``
3. **Configure Neovim**: Open nvim - plugins install automatically
4. **Add secrets**: Edit `~/.zsh/.secrets.zsh` with your API keys
5. **Install Node.js**: `fnm install --lts && fnm default lts-latest`

### Verification

```bash
# Run health check
./scripts/install/health-check.sh

# Check prerequisites
./scripts/install/check-prerequisites.sh
```

### Manual Installation

If you prefer manual setup, see the symlink commands below:

<details>
<summary>Click to expand manual symlink commands</summary>

```bash
# Zsh
ln -sf ~/dotfiles/zsh/.zshrc ~/.zshrc
ln -sf ~/dotfiles/zsh/.zprofile ~/.zprofile
ln -sf ~/dotfiles/zsh/.p10k.zsh ~/.p10k.zsh
ln -sf ~/dotfiles/zsh/.zsh ~/.zsh

# Tmux
ln -sf ~/dotfiles/tmux/.tmux.conf ~/.tmux.conf
ln -sf ~/dotfiles/tmux/.tmux ~/.tmux

# Neovim
ln -sf ~/dotfiles/nvim ~/.config/nvim

# Custom scripts
mkdir -p ~/.local/bin
ln -sf ~/dotfiles/bin/tm ~/.local/bin/tm
ln -sf ~/dotfiles/bin/dana ~/.local/bin/dana

# Hammerspoon
ln -sf ~/dotfiles/hammerspoon ~/.hammerspoon

# Ghostty
mkdir -p ~/.config/ghostty
ln -sf ~/dotfiles/ghostty/config ~/.config/ghostty/config

# Karabiner Elements
mkdir -p ~/.config/karabiner
ln -sf ~/dotfiles/karabiner/karabiner.json ~/.config/karabiner/karabiner.json
```

</details>

### Troubleshooting

See [docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md) for common issues and solutions.

## Updating

```bash
cd ~/dotfiles
git pull
```

Then reload your shell: `source ~/.zshrc`

## Key Features

### Zsh
- Powerlevel10k prompt with instant prompt
- fzf integration for fuzzy finding
- Lazy-loaded completions for performance
- Custom aliases and functions

### Tmux
- Backtick (`` ` ``) as prefix key
- Vim-style navigation
- Session save/restore (tmux-resurrect + continuum)
- fzf session switcher
- Dracula theme

### Neovim
- lazy.nvim plugin manager
- LSP support (TypeScript, Go, Python, Lua, C#)
- Telescope fuzzy finder
- GitHub Copilot (disabled for sensitive files)
- Treesitter syntax highlighting

### Hammerspoon
- Auto-centre windows for specified apps
- CLI enabled via IPC

### Ghostty
- Dracula colour scheme
- Zsh shell integration
- macOS optimised (glass icon, left Option as Alt)

### Karabiner Elements
- Caps Lock to Escape (Ghostty only)
- Right Option to Left Control
- UK keyboard layout fixes for Apple keyboards

## Keybinding Quick Reference

### Tmux
| Action | Keybinding |
|--------|------------|
| Prefix | `` ` `` |
| Help | `` ` h `` |
| Save session | `` ` w `` |
| Session switcher | `` ` s `` |
| Window switcher | `` ` f `` |
| Rename window | `Opt+r` |
| Close pane | `Opt+s` |
| Close window | `Opt+x` |
| URL picker | `Opt+y` |
| Undo pane/window | `Opt+u` |

### Neovim
| Action | Keybinding |
|--------|------------|
| Leader | `Space` |
| Help | `` ` h `` (in tmux) |
| Find files | `Space sf` |
| Live grep | `Space sg` |
| File explorer | `Space e` |
| Git (Neogit) | `Space g` |
| Format | `Space f` |
