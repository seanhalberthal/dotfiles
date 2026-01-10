# Troubleshooting Guide

Common issues and solutions for the dotfiles configuration.

## Table of Contents

- [Installation Issues](#installation-issues)
- [Zsh Issues](#zsh-issues)
- [Tmux Issues](#tmux-issues)
- [Neovim Issues](#neovim-issues)
- [Debugging Commands](#debugging-commands)

---

## Installation Issues

### Symlinks Not Working

**Symptom**: Configuration not loading, symlinks pointing to wrong location.

**Diagnosis**:
```bash
# Check symlink targets
ls -la ~/.zshrc ~/.tmux.conf ~/.config/nvim

# Run health check
./scripts/health-check.sh
```

**Solution**:
```bash
# Re-run installation
./install.sh

# Or manually fix a symlink
ln -sf ~/dotfiles/zsh/.zshrc ~/.zshrc
```

### Permission Denied on Scripts

**Symptom**: `Permission denied` when running install.sh or scripts.

**Solution**:
```bash
chmod +x install.sh scripts/*.sh
```

### Backup Restoration

**Symptom**: Need to restore original configuration after installation.

**Solution**:
```bash
# Find your backup
ls -la ~/.dotfiles-backup-*

# Restore specific file
cp ~/.dotfiles-backup-YYYYMMDD-HHMMSS/.zshrc ~/.zshrc

# Restore everything
cp -r ~/.dotfiles-backup-YYYYMMDD-HHMMSS/* ~/
```

---

## Zsh Issues

### Slow Shell Startup

**Symptom**: Terminal takes more than 500ms to start.

**Diagnosis**:
```bash
# Time shell startup
time zsh -i -c exit

# Profile startup (add to top of .zshrc temporarily)
zmodload zsh/zprof
# ... at end of .zshrc
zprof
```

**Common Causes**:
1. NVM instead of fnm (300-500ms slower)
2. Uncached completions
3. Too many plugins

**Solution**:
- Use fnm instead of NVM (already configured)
- Ensure compinit caching is working
- Check `~/.zcompdump` exists and is recent

### Powerlevel10k Not Loading

**Symptom**: Plain prompt instead of styled prompt.

**Diagnosis**:
```bash
# Check if p10k is installed
ls -la ~/.p10k.zsh

# Check if instant prompt cache exists
ls -la ~/.cache/p10k-instant-prompt-*.zsh
```

**Solution**:
```bash
# Re-run p10k configuration
p10k configure

# Clear instant prompt cache
rm -f ~/.cache/p10k-instant-prompt-*.zsh
```

### fzf Keybindings Not Working

**Symptom**: Ctrl+R, Ctrl+T, or Alt+C not triggering fzf.

**Diagnosis**:
```bash
# Check if fzf is installed
which fzf

# Check key bindings file
ls -la /opt/homebrew/opt/fzf/shell/key-bindings.zsh
```

**Solution**:
```bash
# Install fzf with keybindings
$(brew --prefix)/opt/fzf/install
```

---

## Tmux Issues

### Plugins Not Installing

**Symptom**: Tmux plugins not loading after installation.

**Diagnosis**:
```bash
# Check TPM installation
ls -la ~/.tmux/plugins/tpm

# Check plugin directory
ls -la ~/.tmux/plugins/
```

**Solution**:
```bash
# Install TPM
git clone https://github.com/tmux-plugins/tpm ~/.tmux/plugins/tpm

# Inside tmux, press:
# prefix + I (capital I) to install plugins
# prefix + U (capital U) to update plugins
```

### Prefix Key Not Working

**Symptom**: Backtick (`) not registering as prefix.

**Diagnosis**:
```bash
# Check prefix setting
tmux show-option -g prefix

# List key bindings
tmux list-keys | grep prefix
```

**Solution**:
```bash
# Reload tmux config
tmux source-file ~/.tmux.conf

# Or restart tmux server
tmux kill-server && tmux
```

### Colours Not Displaying Correctly

**Symptom**: Wrong colours, no true colour support.

**Diagnosis**:
```bash
# Check TERM setting
echo $TERM

# Test true colour
printf "\x1b[38;2;255;100;0mTrue Colour Test\x1b[0m\n"
```

**Solution**:
```bash
# Ensure terminal supports true colour
# In Ghostty config:
# term = xterm-256color

# Restart tmux with correct TERM
TERM=xterm-256color tmux
```

### Undo Not Working

**Symptom**: Alt+u not restoring killed panes/windows.

**Diagnosis**:
```bash
# Check undo files exist
ls -la /tmp/tmux-undo-*

# Check script permissions
ls -la ~/.tmux/scripts/undo-*.sh
```

**Solution**:
```bash
# Make scripts executable
chmod +x ~/.tmux/scripts/*.sh

# Check if Alt key is being captured by terminal
# In Ghostty: macos-option-as-alt = true
```

---

## Neovim Issues

### Plugins Not Loading

**Symptom**: Errors on startup, missing functionality.

**Diagnosis**:
```bash
# Check lazy.nvim installation
ls -la ~/.local/share/nvim/lazy/

# Check for errors
nvim --headless "+Lazy! sync" +qa
```

**Solution**:
```bash
# Clear plugin cache and reinstall
rm -rf ~/.local/share/nvim/lazy/
rm -rf ~/.local/state/nvim/lazy/

# Open Neovim to trigger reinstall
nvim
```

### LSP Not Working

**Symptom**: No autocomplete, go-to-definition not working.

**Diagnosis**:
```vim
" In Neovim
:LspInfo
:Mason
```

**Solution**:
```vim
" Install missing language servers
:MasonInstall pyright typescript-language-server lua-language-server gopls
```

### Copilot Not Activating

**Symptom**: No Copilot suggestions appearing.

**Diagnosis**:
```vim
:Copilot status
:Copilot auth
```

**Solution**:
```vim
" Authenticate with GitHub
:Copilot auth

" Check if file type is supported
:echo &filetype
```

---

## Debugging Commands

### Shell

```bash
# Time shell startup
time zsh -i -c exit

# Profile shell startup
zsh -xv 2>&1 | head -50

# Check PATH
echo $PATH | tr ':' '\n'

# Verify shell is zsh
echo $SHELL
```

### Tmux

```bash
# Check tmux version
tmux -V

# List sessions
tmux list-sessions

# List windows
tmux list-windows

# Show all options
tmux show-options -g

# Check for errors in config
tmux source-file ~/.tmux.conf
```

### Neovim

```bash
# Check Neovim version
nvim --version

# Check health
nvim +checkhealth

# Start without config
nvim -u NONE

# Debug startup
nvim --startuptime startup.log
cat startup.log
```

### General

```bash
# Run health check
./scripts/health-check.sh

# Check all symlinks
ls -la ~/{.zshrc,.zprofile,.p10k.zsh,.tmux.conf} ~/.config/{nvim,ghostty}

# Check XDG directories
echo "Config: ${XDG_CONFIG_HOME:-~/.config}"
echo "Data: ${XDG_DATA_HOME:-~/.local/share}"
echo "Cache: ${XDG_CACHE_HOME:-~/.cache}"
```

---

## Getting Help

If you're still experiencing issues:

1. Check the component-specific README files:
   - `zsh/.zsh/README.md`
   - `tmux/.tmux/README.md`
   - `nvim/README.md` (if present)

2. Search for similar issues in the tool's documentation:
   - [Tmux manual](https://man7.org/linux/man-pages/man1/tmux.1.html)
   - [Neovim documentation](https://neovim.io/doc/)
   - [Powerlevel10k FAQ](https://github.com/romkatv/powerlevel10k#faq)

3. Check tool versions match requirements:
   ```bash
   tmux -V    # 3.3+
   nvim -v    # 0.9+
   zsh --version  # 5.8+
   ```
