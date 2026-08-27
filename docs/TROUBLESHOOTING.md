# Troubleshooting Guide

Common issues and solutions for the dotfiles configuration.

## Table of Contents

- [Common Error Messages](#common-error-messages)
- [Installation Issues](#installation-issues)
  - [Installation Failed Mid-Way](#installation-failed-mid-way)
  - [Symlinks Not Working](#symlinks-not-working)
  - [Permission Denied on Scripts](#permission-denied-on-scripts)
  - [Backup Restoration](#backup-restoration)
- [Platform-Specific Issues](#platform-specific-issues)
  - [Linux Compatibility](#linux-compatibility)
  - [Apple Silicon vs Intel Mac](#apple-silicon-vs-intel-mac)
- [Zsh Issues](#zsh-issues)
  - [Slow Shell Startup](#slow-shell-startup)
  - [Insecure Completion Directories](#insecure-completion-directories)
  - [fnm / Node.js Not Working](#fnm--nodejs-not-working)
  - [ANDROID_HOME Issues](#android_home-issues)
  - [Powerlevel10k Not Loading](#powerlevel10k-not-loading)
  - [fzf Keybindings Not Working](#fzf-keybindings-not-working)
- [Tmux Issues](#tmux-issues)
- [Neovim Issues](#neovim-issues)
- [Debugging Commands](#debugging-commands)

---

## Common Error Messages

Quick reference for error messages and where to find solutions:

| Error Message                         | Likely Cause                        | Solution                                            |
| ------------------------------------- | ----------------------------------- | --------------------------------------------------- |
| `Permission denied: ./install.sh`     | Scripts not executable              | [Permission Denied](#permission-denied-on-scripts)  |
| `command not found: fnm`              | fnm not installed                   | [fnm Not Working](#fnm--nodejs-not-working)         |
| `command not found: node`             | Node.js not installed via fnm       | [fnm Not Working](#fnm--nodejs-not-working)         |
| `already exists and is not a symlink` | Existing config files               | [Installation Failed](#installation-failed-mid-way) |
| `Directory not found: ...`            | Launcher project path wrong         | Check PROJECT_DIR in the launcher script            |
| `tmux: command not found`             | tmux not installed                  | Run `brew install tmux`                             |
| `no matches found` (fzf)              | No results for search               | Expand search query                                 |
| `ANDROID_HOME: unbound variable`      | ANDROID_HOME not set                | See [ANDROID_HOME Issues](#android_home-issues)     |
| `lazy.nvim: not found`                | Neovim plugin manager not installed | Launch `nvim`, lazy.nvim auto-installs              |
| `LSP server not found`                | Mason LSP not installed             | Run `:Mason` in Neovim, install server              |

---

## Installation Issues

### Installation Failed Mid-Way

**Symptom**: Install script exited with error before completion, partial configuration applied.

**Diagnosis**:

```bash
# Check if rollback state exists
ls -la ~/dotfiles/.install-state/

# Check what steps completed
cat ~/dotfiles/.install-state/state.txt 2>/dev/null
```

**Solution**:

```bash
# Option 1: Run rollback to restore original configuration
./scripts/install/rollback.sh

# Fix the issue that caused failure, then re-run install
./install.sh

# Option 2: If rollback state doesn't exist, manually restore
# (if you have backups in ~/.dotfiles-backup/)
```

**Common Installation Failures**:

1. **Homebrew installation fails**:

   ```bash
   # Install Homebrew manually first
   /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

   # Then run dotfiles install with --skip-brew
   ./install.sh --skip-brew
   ```

2. **Existing config files conflict**:

   ```bash
   # The install script backs up existing files automatically
   # If it fails, check for files that aren't symlinks:
   file ~/.zshrc ~/.tmux.conf ~/.config/nvim

   # Manually backup if needed
   mv ~/.zshrc ~/.zshrc.backup
   mv ~/.tmux.conf ~/.tmux.conf.backup

   # Then re-run install
   ./install.sh
   ```

3. **TPM (Tmux Plugin Manager) clone fails**:

   ```bash
   # Manually clone TPM
   git clone https://github.com/tmux-plugins/tpm ~/.tmux/plugins/tpm

   # Then re-run install
   ./install.sh
   ```

4. **Permission errors**:
   ```bash
   # Ensure scripts are executable
   chmod +x install.sh scripts/**/*.sh launchers/*

   # Then re-run install
   ./install.sh
   ```

**Notes**:

- The install script records rollback state in `.install-state/` (symlinks, backup locations, completed steps)
- Backups are created in `~/.dotfiles-backup/` by the backup step
- Rollback script uses both state files and backups to restore previous configuration

### Symlinks Not Working

**Symptom**: Configuration not loading, symlinks pointing to wrong location.

**Diagnosis**:

```bash
# Check symlink targets
ls -la ~/.zshrc ~/.tmux.conf ~/.config/nvim

# Run health check
./scripts/install/health-check.sh
```

**Solution**:

```bash
# Re-run installation
./install.sh

# Or manually fix a symlink (example for .zprofile; ~/.zshrc is a user-owned
# copy created from zsh/zshrc.template, not a symlink)
ln -sf ~/dotfiles/zsh/zprofile ~/.zprofile
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
ls -la ~/.dotfiles-backup/

# Restore specific file
cp ~/.dotfiles-backup/<backup-dir>/.zshrc ~/.zshrc

# Restore everything
cp -r ~/.dotfiles-backup/<backup-dir>/* ~/
```

---

## Platform-Specific Issues

### Linux Compatibility

**Known Differences**:

| Feature         | macOS                  | Linux                                       |
| --------------- | ---------------------- | ------------------------------------------- |
| Homebrew path   | `/opt/homebrew`        | `/home/linuxbrew/.linuxbrew`                |
| Cask apps       | Hammerspoon, Karabiner | Not available (macOS-only casks)            |
| Clipboard       | `clip` (`pbcopy`)      | `clip` (`wl-copy`, `xclip`, or `xsel`)      |
| Package manager | `brew`                 | `brew` (Linuxbrew) or native (`apt`, `yum`) |

**Symptom**: Commands not found or apps not available on Linux.

**Solution**:

1. **Homebrew path not in PATH**:

   ```bash
   # Add to ~/.zshrc (already handled by dotfiles)
   eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"

   # Reload shell
   exec zsh
   ```

2. **Cask applications**:

   ```bash
   # Skip macOS-only casks during install
   # Edit Brewfile and comment out:
   # - Hammerspoon (macOS-only)
   # - Karabiner (macOS-only)
   # - Ghostty (macOS-only for now)

   # Then run
   brew bundle install --file=~/dotfiles/Brewfile
   ```

3. **Clipboard commands**:

   `clip` works on both platforms and needs no aliases: `<cmd> | clip` copies,
   bare `clip` pastes, and `clip -p` forces a paste when the direction must not
   depend on context (scripts). On Linux, `pbcopy` and `pbpaste` remain as
   shims so muscle memory and existing scripts keep working.

   Install the tool matching your session type. `clip` picks the backend from
   the live display server, so installing the wrong one has no effect:

   ```bash
   # Wayland (default on Fedora, Ubuntu, GNOME, KDE)
   sudo apt install wl-clipboard

   # X11
   sudo apt install xclip   # Debian/Ubuntu
   sudo yum install xclip   # RHEL/CentOS
   ```

   If a display server is running but its tool is missing, `clip` fails with
   the package to install rather than falling back. The fallback below would
   otherwise send the payload out through the terminal when the local clipboard
   was what you asked for.

   With no display server at all (headless, or over SSH without X11
   forwarding), `clip` falls back to OSC 52 and needs nothing installed: it
   writes an escape sequence that your terminal turns into a clipboard write.
   Paste is unavailable there, as most terminals refuse OSC 52 reads.

   **`clip` makes no security claims, and neither did `pbcopy`.** The system
   clipboard is a shared, unencrypted resource that any process on the machine
   can read, and clipboard managers (Raycast, Maccy) snapshot every copy to
   their own history, so clearing the clipboard afterwards does not un-copy it.
   Content reaches `clip` on stdin rather than as an argument, so it never
   appears in `ps` output, but the command itself still lands in
   `~/.zsh_history`. The OSC 52 fallback is the least private backend of the
   set: base64 is encoding rather than encryption, and the payload travels as
   terminal output, so tmux (which retains it in a buffer, readable via
   `tmux show-buffer`) and every SSH hop in between handle it in the clear. For
   secrets, prefer a password manager's own clipboard integration, which clears
   on a timer and keeps the value out of your shell history.

4. **tmux clipboard integration**:
   Handled automatically. `dotfiles theme` resolves the clipboard command at
   generation time and substitutes it into `{{CLIPBOARD_CMD}}`, using the same
   detection as `clip` (see `scripts/_lib/clipboard.sh`). If you switch between
   X11 and Wayland, re-run `dotfiles theme <name>` to re-resolve it.

### Apple Silicon vs Intel Mac

**Symptom**: Homebrew commands not found, or wrong architecture binaries.

**Diagnosis**:

```bash
# Check architecture
uname -m
# arm64 = Apple Silicon
# x86_64 = Intel

# Check Homebrew path
echo $HOMEBREW_PREFIX
# /opt/homebrew = Apple Silicon
# /usr/local = Intel
```

**Solution**:

1. **Homebrew in wrong location**:

   ```bash
   # Apple Silicon: reinstall to /opt/homebrew
   /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

   # Intel: reinstall to /usr/local
   # (Homebrew installer detects architecture automatically)
   ```

2. **Rosetta 2 required for some packages**:
   ```bash
   # Install Rosetta 2 (if needed)
   softwareupdate --install-rosetta
   ```

**Notes**:

- The dotfiles detect architecture automatically via `common.sh`
- Most packages are universal or have ARM64 builds now
- If a package requires Rosetta 2, Homebrew will warn you

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

### Insecure Completion Directories

**Symptom**: zsh prints `compinit: insecure directories, run compaudit for list` on startup, or prompts before loading completions.

**Cause**: Homebrew installs its share directory group-writable (775). On macOS that directory is group-owned by a shared group, so `compaudit` flags it. The config runs a full `compinit` once every 24 hours and reuses a cached dump otherwise, so the prompt appears on the first shell of the day. Linux gives each user a private single-member group, so the same permission bit is owner-only and the problem does not occur there.

**Diagnosis**:

```bash
dotfiles health    # reports under "compinit dir permissions"
zsh -fc 'autoload -Uz compaudit; compaudit'
```

**Solution**:

```bash
~/dotfiles/scripts/fix-compinit-insecure-dirs.sh --dry-run   # preview
~/dotfiles/scripts/fix-compinit-insecure-dirs.sh             # apply
```

The script only changes paths you own and rebuilds `~/.zcompdump`; anything root-owned is reported for a manual `sudo chmod go-w`. Homebrew can reintroduce the permission on reinstall, so this may need running again.

### fnm / Node.js Not Working

**Symptom**: `command not found: node`, `command not found: fnm`, or Node.js version not switching.

**Diagnosis**:

```bash
# Check if fnm is installed
which fnm

# Check fnm version
fnm --version

# List installed Node versions
fnm list

# Check current Node version
node --version

# Check if fnm environment is loaded
echo $FNM_DIR
```

**Solution**:

1. **fnm not installed**:

   ```bash
   # Install via Homebrew
   brew install fnm

   # Reload shell
   exec zsh

   # Install Node.js LTS
   fnm install --lts
   fnm default lts-latest
   ```

2. **fnm not initialised**:

   ```bash
   # The dotfiles framework (zsh/dotfiles.zsh) handles this automatically.
   # If missing, add to your ~/.zshrc:
   eval "$(fnm env --use-on-cd)"

   # Reload shell
   exec zsh
   ```

3. **No Node.js version installed**:

   ```bash
   # List available versions
   fnm list-remote

   # Install LTS version
   fnm install --lts

   # Set as default
   fnm default lts-latest

   # Verify
   node --version
   ```

4. **Node version not switching automatically**:

   ```bash
   # Ensure --use-on-cd is in fnm env command
   eval "$(fnm env --use-on-cd)"

   # Test with a project that has .nvmrc or .node-version
   cd ~/src/project-with-node-version
   node --version  # Should match .nvmrc
   ```

5. **PATH issues with fnm**:
   ```bash
   # Check if fnm shims are in PATH
   echo $PATH | grep fnm

   # Should see something like:
   # /Users/you/Library/Application Support/fnm/aliases/default/bin

   # If missing, fnm env may not be loaded - check .zshrc
   ```

**Notes**:

- fnm is a fast Node.js version manager (replaces nvm)
- `.nvmrc` and `.node-version` files trigger automatic version switching
- Default version is used when no version file exists
- fnm stores versions in `~/Library/Application Support/fnm/`

### ANDROID_HOME Issues

**Symptom**: Error about `ANDROID_HOME` being unbound or invalid PATH entry `/platform-tools`.

**Diagnosis**:

```bash
# Check if ANDROID_HOME is set
echo $ANDROID_HOME

# Check PATH for invalid entries
echo $PATH | tr ':' '\n' | grep platform-tools
```

**Solution**:

1. **ANDROID_HOME not set but needed**:

   ```bash
   # Add to ~/.config/zsh/secrets.zsh
   export ANDROID_HOME="$HOME/Library/Android/sdk"  # macOS
   export ANDROID_HOME="$HOME/Android/Sdk"          # Linux

   # Reload shell
   exec zsh
   ```

2. **ANDROID_HOME undefined but PATH entry added** (bug fixed in quick wins):

   **Old .zshrc (buggy)**:

   ```bash
   # Line 168 - WRONG
   export PATH=$PATH:$ANDROID_HOME/platform-tools
   ```

   **Fixed .zshrc**:

   ```bash
   # Line 168 - CORRECT
   [[ -n "$ANDROID_HOME" ]] && export PATH=$PATH:$ANDROID_HOME/platform-tools
   ```

   If you're experiencing this, update your `.zshrc` to use the conditional version.

**Notes**:

- `ANDROID_HOME` is only needed for Android development
- If you don't develop for Android, you can ignore this
- The conditional check prevents invalid PATH entries

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
tmux source-file ~/.config/tmux/tmux.conf

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
# Check undo files exist (XDG location)
ls -la ~/.cache/tmux/undo/

# Check legacy location (auto-migrated)
ls -la /tmp/tmux-undo-*

# Check script permissions
ls -la ~/.tmux/scripts/panes/undo.sh
ls -la ~/.tmux/scripts/windows/undo.sh
ls -la ~/.tmux/scripts/sessions/undo.sh
```

**Solution**:

```bash
# Make scripts executable
chmod +x ~/.tmux/scripts/**/*.sh

# Check if Alt key is being captured by terminal
# In Ghostty: add to ~/.config/ghostty/local:
# macos-option-as-alt = true
```

### Claude Switcher Shows No State Icons

**Symptom**: The Claude instance switcher (prefix + c) lists instances but every row shows the grey `·` placeholder instead of working/idle/input icons.

**Diagnosis**:

```bash
# state files should appear while a hooked claude session runs
ls ~/.config/tmux-alerts/agent-state/

# feed the hook a fake event; a state file should appear for your pane
echo '{"hook_event_name":"Stop","session_id":"t","cwd":"/tmp"}' \
  | ~/dotfiles/scripts/hooks/wrappers/claude-state.sh
cat ~/.config/tmux-alerts/agent-state/"$TMUX_PANE"

# the hook needs jq
command -v jq
```

**Solution**:

- Wire the `claude-state.sh` hooks into Claude Code's `settings.json` (see [AGENT-HOOKS.md](AGENT-HOOKS.md))
- Hook settings only apply to new Claude Code sessions; restart instances that were already running
- Install `jq` if missing (`brew install jq`); the hook exits silently without it
- Stale files from a tmux server restart clear themselves the next time the switcher opens

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
:MasonInstall basedpyright typescript-language-server lua-language-server gopls
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

**No inline suggestions at all (silent)**: copilot.lua needs the language
server to start. The config uses the standalone binary server (`server.type =
'binary'`), which auto-downloads and has no Node dependency, so a missing or
out-of-shell `node` no longer breaks completions. If you previously relied on
the Node server and it stopped working, confirm the binary downloaded:

```vim
:checkhealth copilot
```

### CodeCompanion: "Authorization header is badly formatted"

**Symptom**: every CodeCompanion chat submit fails with a 400 and
`bad request: Authorization header is badly formatted`.

**Cause**: `~/.config/github-copilot/apps.json` holds more than one
`github.com:*` entry (common once you have also signed into the gh CLI, Copilot
CLI, or VS Code). The Copilot adapter picks the first entry it finds; if that is
a stale entry, its token exchange returns 401 and the chat request goes out with
an empty bearer.

**Solution**: the config pins the copilot.vim app token (the `Iv1.*` entry) so
duplicates no longer break it; restart Neovim to pick up a fresh token. To check
which entries are still valid without printing secrets:

```bash
python3 - <<'PY'
import json, urllib.request
d = json.load(open(__import__('os').path.expanduser('~/.config/github-copilot/apps.json')))
for k, v in d.items():
    req = urllib.request.Request("https://api.github.com/copilot_internal/v2/token",
        headers={"Authorization": "Bearer " + v["oauth_token"], "User-Agent": "check"})
    try:
        r = urllib.request.urlopen(req, timeout=10)
        print(k, "OK" if json.load(r).get("token") else "no token")
    except Exception as e:
        print(k, "FAIL", e)
PY
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
tmux source-file ~/.config/tmux/tmux.conf
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
./scripts/install/health-check.sh

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

1. Check related documentation:
   - [Installation Guide](./INSTALLATION-GUIDE.md)
   - [Theme System](./THEME-SYSTEM.md)

2. Search for similar issues in the tool's documentation:
   - [Tmux manual](https://man7.org/linux/man-pages/man1/tmux.1.html)
   - [Neovim documentation](https://neovim.io/doc/)
   - [Powerlevel10k FAQ](https://github.com/romkatv/powerlevel10k#faq)

3. Check tool versions match requirements:
   ```bash
   tmux -V    # 3.3+
   nvim -v    # 0.11+
   zsh --version  # 5.8+
   ```
