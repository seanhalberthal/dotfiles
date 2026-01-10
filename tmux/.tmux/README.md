# Tmux Configuration

A modern tmux setup with ergonomic keybindings, Dracula theme, and per-session backup/restore.

## Quick Reference

| Action                | Keybinding / Command              |
| --------------------- | --------------------------------- |
| **Prefix**            | `` ` `` (backtick)                |
| **Start dev session** | `tm` (from any directory)         |
| Help popup            | `` ` h ``                         |
| Save sessions         | `` ` w `` (like vim :w)           |
| List backups          | `prefix + S` or `tls`             |
| Restore session       | `prefix + R` or `trestore <name>` |

## Setup Guide (New Machine)

### 1. Install tmux

```bash
brew install tmux
```

### 2. Copy configuration files

Copy the following to your home directory:

```
~/.tmux.conf                    # Main configuration
~/.tmux/
├── scripts/
│   ├── resurrect-restore.sh
│   └── resurrect-split.sh
~/bin/
├── tm                          # Dev session launcher
└── dana                        # Project-specific launcher (optional)
```

### 3. Install TPM (Tmux Plugin Manager)

```bash
git clone https://github.com/tmux-plugins/tpm ~/.tmux/plugins/tpm
```

### 4. Install plugins

Start tmux and press `prefix + I` (that's `` ` `` then `Shift+i`) to install plugins.

### 5. Add shell aliases

Add to your `~/.zshrc`:

```bash
# tmux session management
alias tls="~/.tmux/scripts/resurrect-restore.sh --list"
alias trestore="~/.tmux/scripts/resurrect-restore.sh"
alias tkill="tmux kill-server; rm -rf ~/.tmux/resurrect/*"

# Smart attach: connects to running session, or restores from backup
ta() {
  if tmux a -t "$1" 2>/dev/null; then return 0; fi
  local backup="${HOME}/.tmux/resurrect/sessions/$1.txt"
  if [[ -f "$backup" ]]; then
    echo "Restoring '$1' from backup..."
    if ~/.tmux/scripts/resurrect-restore.sh "$1" && tmux a -t "$1"; then
      return 0
    fi
    echo "Backup stale, removing: $1"
    rm -f "$backup"
    return 1
  fi
  echo "No session or backup found: $1"
  return 1
}
```

Then reload: `source ~/.zshrc`

### 6. Optional: Create help file

Create `~/.tmux/tmux-help.txt` with keybinding reference (displayed with `` ` h ``).

---

## Keybindings

### Prefix

The prefix key is **`` ` ``** (backtick - double-tap for literal).

### Help Popup

Press `` ` h `` to display the keybinding reference. Close it by pressing `Esc`.

### Windows (Tabs)

| Action           | Keybinding                    |
| ---------------- | ----------------------------- |
| Next window      | `Opt+]` or `Ctrl+Enter`       |
| Previous window  | `Opt+[` or `Ctrl+Shift+Enter` |
| New window       | `Opt+t`                       |
| Go to window 1-5 | `prefix + 1-5`                |
| Rename window    | `Opt+Shift+n`                 |
| Swap window left | `Opt+Shift+[`                 |
| Swap window right| `Opt+Shift+]`                 |
| Kill window      | `Opt+x`                       |
| Undo kill        | `Opt+u`                       |

### Panes

| Action            | Keybinding          |
| ----------------- | ------------------- |
| Navigate left     | `Opt+h` or `Ctrl+,` |
| Navigate down     | `Opt+j` or `Ctrl+.` |
| Navigate up       | `Opt+k`             |
| Navigate right    | `Opt+l`             |
| Split left        | `Opt+'`             |
| Split right       | `Opt+\`             |
| Split down        | `Opt+-`             |
| Close pane        | `Opt+s`             |
| Undo close        | `Opt+u`             |
| Zoom (fullscreen) | `Opt+z`             |
| Swap up/down      | `prefix + H/J/K/L`  |
| Resize left       | `Opt+Shift+h`       |
| Resize down       | `Opt+Shift+j`       |
| Resize up         | `Opt+Shift+k`       |
| Resize right      | `Opt+Shift+l`       |

### URL Picker

| Action    | Keybinding |
| --------- | ---------- |
| Open URLs | `Opt+y`    |

Opens a fzf popup with all URLs from the current pane's scrollback. Uses the same vim-style navigation as other switchers (j/k, g/G, f/b, d/u). Press `y` to yank a URL to clipboard instead of opening.

### Undo

| Action              | Keybinding |
| ------------------- | ---------- |
| Undo last kill      | `Opt+u`    |

Restores the last closed pane or window (whichever was killed most recently). Restores directory, layout, and scrollback contents. Works with both `Opt+s` (close pane) and `Opt+x` (kill window).

### Scroll Mode (Copy Mode)

| Action            | Keybinding            |
| ----------------- | --------------------- |
| Enter scroll mode | `Opt+v` or `prefix+v` |
| Navigate          | `h` / `j` / `k` / `l` |
| Page down/up      | `f` / `b`             |
| Half-page down/up | `d` / `u` (cursor moves to screen edge) |
| Top of history    | `g`                   |
| Bottom of history | `G`                   |
| Search down/up    | `/` / `?`             |
| Next/prev match   | `n` / `N`             |
| Select chars      | `v`                   |
| Select line       | `V`                   |
| Yank selection    | `y`                   |
| Yank line         | `Y`                   |
| Exit scroll mode  | `q` or `Esc`          |

**Note:** `Ctrl+f`/`Ctrl+b` and `Ctrl+d`/`Ctrl+u` also work for page and half-page navigation.

**Vim-style yank:** To yank from cursor to top/bottom of history, use visual mode: `v` → `g` (or `G`) → `y`.

### Sessions

| Action                   | Keybinding                     |
| ------------------------ | ------------------------------ |
| Switch window (fzf)      | `prefix + f`                   |
| Switch session (fzf)     | `prefix + s`                   |
| Save all sessions        | `` ` w `` or `prefix + Ctrl+s` |
| Restore all sessions     | `prefix + Ctrl+r`              |
| List saved backups       | `prefix + S`                   |
| Restore specific session | `prefix + R`                   |

### Session/Window Switchers (Vim-Style Navigation)

Both `prefix + s` (sessions) and `prefix + f` (windows) use vim-style navigation.

**Sorting:** Lists are automatically sorted by recently accessed, with the most recently used items at the top.
- **Sessions:** Sorted by `#{session_activity}` (built-in tmux variable)
- **Windows:** Sorted by custom `@last-viewed` timestamp updated via `after-select-window` hook

| Action              | Key                      |
| ------------------- | ------------------------ |
| Move down/up        | `j` / `k`                |
| First/last item     | `g` / `G`                |
| Page down/up        | `f` / `b`                |
| Half-page down/up   | `d` / `u`                |
| Select              | `Space` or `Enter`       |
| Start searching     | `/`                      |
| Quit                | `q` (nav mode) or `Esc`  |
| Clear line          | `Ctrl+w` (in search mode)|
| Delete line         | `Ctrl+k`                 |
| Toggle all sessions | `a` (windows only)       |
| Kill session/window | `Opt+x`                  |
| Undo kill           | `Opt+u`                  |
| New session         | `n` (sessions only)      |
| Rename session      | `r` (sessions only)      |

**Toggle all sessions:** In the window switcher (`prefix + f`), press `a` to toggle between showing windows from the current session only (`:` prompt) and windows from all sessions (`*` prompt). When viewing all sessions, selecting a window will switch to that session and window.

**New session:** Press `n` to open a dialog to create a new session. Type the name and press `Enter` to create (starts at `~`), or `Esc` to cancel. If a session with that name already exists, it will switch to it instead.

**Rename:** Press `r` to open a rename dialog with the current session name pre-filled. Edit the name and press `Enter` to confirm, or `Esc` to cancel.

**Modes:** Switchers start in navigation mode (`:` prompt). Press `/` to search (`>` prompt), `Esc` to return.

Navigation keys (`j`, `k`, `g`, `G`, `f`, `b`, `d`, `u`) are automatically unbound in search mode so you can type them normally, then rebound when you exit search mode.

**Undo:** When you kill a session or window with `Opt+x`, press `Opt+u` to restore it. Sessions are restored with all windows and panes; windows are restored with layout and scrollback contents.

### Plugins (TPM)

| Action          | Keybinding       |
| --------------- | ---------------- |
| Install plugins | `prefix + I`     |
| Update plugins  | `prefix + U`     |
| Clean unused    | `prefix + Alt+u` |

---

## Shell Commands & Aliases

### `tm` - Dev Session Launcher

Start a tmux dev session named after the current directory:

```bash
cd ~/src/myproject
tm
```

This creates a session called `myproject` with:

- **Window 1 (dev):** Claude Code (zoomed) + terminal (split panes)
- **Window 2 (edit):** neovim

If a session with that name already exists, `tm` attaches to it instead of creating a new one.

Location: `~/bin/tm`

### Aliases

| Alias             | Description                                                                                                                                    |
| ----------------- | ---------------------------------------------------------------------------------------------------------------------------------------------- |
| `tls`             | List saved session backups with window/pane counts                                                                                             |
| `trestore <name>` | Restore a specific saved session                                                                                                               |
| `tkill <name>`    | Kill a specific session and remove its backup                                                                                                  |
| `ta <name>`       | Smart attach: connects to running session, or restores from backup if not running. Automatically cleans up stale backups that fail to restore. |
| `dana`            | Launch/attach to the dana project session                                                                                                      |

---

## Session Management

This setup extends tmux-resurrect with custom per-session backup and restore.

### How Saving Works

1. Press `` ` w `` to save all sessions
2. tmux-resurrect saves everything to a single timestamped file
3. The post-save hook (`resurrect-split.sh`) automatically splits this into individual per-session files
4. Each session gets its own backup file in `sessions/` directory

**Auto-cleanup:** When you kill a session (e.g., with `Opt+x` in the session switcher), a save is automatically triggered to update the backup files. The killed session is removed from `tls` listings.

### How Restoring Works

**Restore all sessions (built-in):**

- Press `prefix + Ctrl+r`
- Restores everything from the last combined save

**Restore a single session (custom):**

- Press `prefix + R` and enter the session name, OR
- Run `trestore <session-name>` from the shell
- Only that specific session is restored

### Storage Location

```
~/.tmux/resurrect/
├── last                        # Symlink to latest combined save
├── tmux_resurrect_*.txt        # Timestamped combined saves
├── pane_contents.tar.gz        # Terminal contents (optional)
└── sessions/
    ├── myproject.txt           # Per-session backup
    └── another-session.txt
```

### Listing Backups

```bash
$ tls

Available session backups:

  dana                  5 windows,  6 panes  (2025-12-29 23:08) [ACTIVE]
  supplyscan-mcp        2 windows,  3 panes  (2025-12-29 23:08)
```

---

## File Structure

```
~/.tmux.conf                              # Main configuration
~/.tmux/
├── plugins/
│   ├── tpm/                              # Tmux Plugin Manager
│   ├── tmux-resurrect/                   # Session save/restore
│   ├── tmux-continuum/                   # Auto-save (every 1 min)
│   ├── tmux-cpu/                         # CPU/RAM monitoring
│   ├── tmux-battery/                     # Battery monitoring
│   └── tmux-open/                        # Open highlighted selection
├── resurrect/
│   ├── sessions/                         # Per-session backup files
│   └── last                              # Symlink to latest save
├── scripts/
│   ├── kill-pane.sh                      # Kill pane (Opt+s, saves state)
│   ├── kill-window.sh                    # Kill window (Opt+x, saves state)
│   ├── resurrect-delete.sh               # Delete session backup
│   ├── resurrect-restore.sh              # Individual session restore
│   ├── resurrect-split.sh                # Post-save hook (splits backups)
│   ├── session-kill.sh                   # Kill session (picker, with confirm)
│   ├── session-new.sh                    # Create new session dialog
│   ├── session-rename.sh                 # Rename session dialog
│   ├── session-undo.sh                   # Restore killed session (picker)
│   ├── timestamp.sh                      # Window access tracking hook
│   ├── undo-dispatch.sh                  # Undo dispatcher (Opt+u)
│   ├── undo-pane.sh                      # Restore killed pane
│   ├── undo-session.sh                   # Restore killed session (silent)
│   ├── undo-window.sh                    # Restore killed window
│   ├── url-picker.sh                     # URL picker (Opt+y)
│   └── window-kill.sh                    # Kill window (picker, saves state)
└── README.md                             # This file

~/bin/
├── tm                                    # Dev session launcher
└── dana                                  # Dana project launcher
```

---

## Plugins

### TPM (Tmux Plugin Manager)

Manages plugin installation and updates.

- Repository: https://github.com/tmux-plugins/tpm
- Location: `~/.tmux/plugins/tpm/`

### tmux-resurrect

Saves and restores tmux sessions (windows, panes, working directories).

- Repository: https://github.com/tmux-plugins/tmux-resurrect
- Save: `` ` w `` (or `prefix + Ctrl+s`)
- Restore: `prefix + Ctrl+r`

### tmux-continuum

Automatic background saving every 1 minute.

- Repository: https://github.com/tmux-plugins/tmux-continuum
- Save interval: 1 minute (configured via `@continuum-save-interval`)
- Auto-restore on tmux start is **disabled** (manual restore preferred)

### tmux-cpu

Displays CPU and RAM usage in the status bar.

- Repository: https://github.com/tmux-plugins/tmux-cpu
- Shows icons that change based on load level (=, ≡, ≣)
- CPU colours: cyan (low) → purple (medium) → pink (high)
- RAM colours: green (low) → teal (medium) → purple (high)

### tmux-battery

Displays battery percentage in the status bar.

- Repository: https://github.com/tmux-plugins/tmux-battery
- Shows percentage with colour-coded background
- Green when above 20%, red when 20% or below

### tmux-open

Opens highlighted file/URL from copy mode.

- Repository: https://github.com/tmux-plugins/tmux-open
- In copy mode: `o` opens selection, `Ctrl+o` opens in `$EDITOR`
- `Shift+s` searches selection with default search engine

### tmux-yank

System clipboard integration for copying text.

- Repository: https://github.com/tmux-plugins/tmux-yank
- In copy mode: `y` copies selection to system clipboard
- `prefix + y` copies current command line to clipboard
- `prefix + Y` copies current working directory to clipboard

---

## Theme

Uses a Dracula-inspired colour scheme:

- **Background:** `#282a36` (dark)
- **Active elements:** `#bd93f9` (purple)
- **Inactive elements:** `#6272a4` (grey)
- **Session name:** `#cc6699` (pink)
- **Command prompt:** purple background with dark text (matches active tabs)

---

## Configuration

Main config file: `~/.tmux.conf`

Key settings:

- Prefix: `` ` `` (backtick)
- Mouse: enabled
- Base index: 1 (windows and panes start at 1)
- History: 50,000 lines
- Escape time: 0 (no delay for vim)
- Auto-rename: shows directory name or running command
- Auto-save: every 1 minute
- Status refresh: every 2 seconds
- Status bar: shows zoom indicator (yellow `Z`), CPU (⚙), RAM (☰), and battery % with Dracula-themed colour indicators
- Status bar time: background aligned with powerlevel10k right prompt edge
- Bell monitoring: windows are highlighted in red when they send a bell (used by Claude Code hooks to signal when attention is needed)

---

## Troubleshooting

### Plugins not working

Run `prefix + I` to install plugins, then restart tmux.

### Session restore fails

Check that the session backup exists:

```bash
ls ~/.tmux/resurrect/sessions/
```

### Keybindings not working

Reload the config:

```bash
tmux source ~/.tmux.conf
```

### Clear all saved sessions

```bash
tkill
# or manually:
rm -rf ~/.tmux/resurrect/{sessions/*,last,*.txt,*.tar.gz}
```
