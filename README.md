# Dotfiles

Personal configuration files for zsh, tmux, neovim, hammerspoon, and ghostty.

## Contents

```
dotfiles/
├── zsh/           # Zsh shell configuration
│   ├── .zshrc
│   ├── .zprofile
│   ├── .p10k.zsh  # Powerlevel10k theme
│   └── .zsh/      # Additional zsh configs
├── tmux/          # Tmux terminal multiplexer
│   ├── .tmux.conf
│   └── .tmux/     # Scripts and help files
├── nvim/          # Neovim configuration
│   ├── init.lua
│   └── lua/
├── bin/           # Custom scripts
│   ├── tm         # Tmux session launcher
│   └── dana       # Dana project launcher (see below)
├── hammerspoon/   # macOS automation
│   └── init.lua
├── ghostty/       # Terminal emulator
│   └── config
└── README.md
```

## Prerequisites

Install these via Homebrew:

```bash
# Core tools
brew install neovim tmux fzf

# Zsh enhancements
brew install powerlevel10k zsh-autosuggestions direnv

# Development tools (optional)
brew install gh lazygit

# macOS apps
brew install --cask ghostty hammerspoon
```

Install a Nerd Font for icons:
```bash
brew install --cask font-jetbrains-mono-nerd-font
```

## Installation

### 1. Clone the repository

```bash
git clone https://github.com/seanhalberthal/dotfiles.git ~/dotfiles
```

### 2. Create symlinks

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
mkdir -p ~/bin
ln -sf ~/dotfiles/bin/tm ~/bin/tm
ln -sf ~/dotfiles/bin/dana ~/bin/dana

# Hammerspoon (remove existing directory first)
rm -rf ~/.hammerspoon
ln -sf ~/dotfiles/hammerspoon ~/.hammerspoon

# Ghostty
mkdir -p ~/.config/ghostty
ln -sf ~/dotfiles/ghostty/config ~/.config/ghostty/config
```

### 3. Set up secrets

```bash
cd ~/dotfiles/zsh/.zsh
cp .secrets.zsh.template .secrets.zsh
chmod 600 .secrets.zsh
# Edit .secrets.zsh with your actual API keys
```

### 4. Install tmux plugins

Start tmux and press `` ` `` then `I` (capital i) to install TPM plugins.

### 5. Install neovim plugins

Open Neovim - lazy.nvim will auto-install plugins on first launch.

Or manually: `:Lazy sync`

### 6. Source zsh config

```bash
source ~/.zshrc
```

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
- macOS optimised (glass icon, Option as Alt)

### Dana Project Launcher
The `dana` script creates a tmux session with pre-configured windows:

| Window | Name | Directory | Purpose |
|--------|------|-----------|---------|
| 1 | backend | ~/src/dana/backend | Backend development |
| 2 | web | ~/src/dana/web | Web frontend |
| 3 | mobile | ~/src/dana/mobile | Mobile app |
| 4 | tools | split panes | Left: `bun dev`, Right: `npx expo` |
| 5 | commit-and-push | ~/src/dana | Git operations |
| 6 | zsh | ~ | General shell |

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
| URL picker | `Opt+u` |

### Neovim
| Action | Keybinding |
|--------|------------|
| Leader | `Space` |
| Help | `Space h` |
| Find files | `Space sf` |
| Live grep | `Space sg` |
| File explorer | `Space e` |
| Format | `Space f` |
