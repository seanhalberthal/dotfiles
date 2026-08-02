<div align="center">

<picture>
  <source media="(prefers-color-scheme: dark)" srcset=".github/assets/logo-dark.svg">
  <source media="(prefers-color-scheme: light)" srcset=".github/assets/logo-light.svg">
  <img alt="dotfiles" src=".github/assets/logo-dark.svg" width="480">
</picture>

**Personal configuration files for zsh, tmux, neovim, ghostty, git and much more.**

[![CI](https://img.shields.io/github/actions/workflow/status/undont/dotfiles/ci.yml?branch=main&style=flat&logo=githubactions&logoColor=white&label=CI)](https://github.com/undont/dotfiles/actions)
[![Zsh Startup](https://img.shields.io/endpoint?url=https://gist.githubusercontent.com/undont/fa735d81db7a1bfb7662671f293e4c35/raw/zsh-startup.json&style=flat&logo=ghostty&logoColor=white)](https://github.com/undont/dotfiles/actions/workflows/ci.yml)
[![Licence](https://img.shields.io/github/license/undont/dotfiles?style=flat&label=licence&color=6A9462)](LICENCE)
[![Neovim](https://img.shields.io/badge/Neovim-0.11+-57A143?style=flat&logo=neovim&logoColor=white)](https://neovim.io/)
[![Tmux](https://img.shields.io/badge/Tmux-3.3+-1BB91F?style=flat&logo=tmux&logoColor=white)](https://github.com/tmux/tmux)
[![macOS](https://img.shields.io/badge/macOS-supported-6e7681?style=flat&logo=apple&logoColor=white)]()
[![Linux](https://img.shields.io/badge/Linux-supported-6e7681?style=flat&logo=linux&logoColor=white)]()

[Quick Start](#quick-start) · [How it works](#how-it-works) · [Features](#features) · [Themes](#themes) · [Brewfile](#brewfile) · [Keybindings](#keybindings) · [Docs](#documentation)

</div>

---

## Quick Start

Prerequisites: macOS or Linux. On a fresh macOS, run `xcode-select --install` first.

```bash
git clone https://github.com/undont/dotfiles.git ~/dotfiles
cd ~/dotfiles
./install.sh            # full install (default)
```

### Install presets

| Preset      | Components                                        | Use case                          |
| ----------- | ------------------------------------------------- | --------------------------------- |
| `--minimal` | zsh, tmux                                         | servers, remote machines, SSH     |
| `--core`    | + nvim, ghostty, AI/CLI tools, launchers          | Linux desktop, cross-platform dev |
| `--full`    | + Hammerspoon, Karabiner, Raycast, music-presence | macOS power user (default)        |

The installer backs up existing configs, installs Homebrew packages filtered by preset, creates symlinks, sets up plugin managers, and runs a health check. Your preset is saved so `dotfiles update` remembers it.

<details>
<summary><b>All installation options</b></summary>

```bash
./install.sh              # full installation (default)
./install.sh --minimal    # lightweight server setup
./install.sh --core       # cross-platform dev setup
./install.sh --full       # everything including macOS apps
./install.sh --skip-brew  # skip Homebrew/package installation
./install.sh --skip-backup # skip backing up existing configs
./install.sh --check-only  # only run prerequisite and health checks
```

</details>

---

## How it works

The setup is layered: a shared base lives in this repo and gets symlinked into place, and tools that support it (tmux, ghostty, nvim, lazygit, gh-dash, hammerspoon) load a `local.*` file on top that `dotfiles update` never touches. Clone the repo, keep your tweaks in the local files, and run `dotfiles update` to pull upstream changes; your overrides survive. Fork it if you really want to make it your own or take the base in a different direction.

Version-gated scripts in [`scripts/migrations/`](scripts/migrations) run automatically during `dotfiles update` to handle changes the normal installer can't (converting a symlink to a user-owned copy, removing a deprecated package, fixing a config that drifted). They're idempotent and only run once per version range.

Built around staying on the keyboard: `` ` `` as the tmux prefix, fzf pickers everywhere, vim motions under space as `<leader>` in nvim, and zsh aliases for anything frequent enough to warrant one. Used daily across personal and work machines on macOS and Linux.

---

## Features

### Ghostty

> The terminal that powers everything.

Configured as a clean input layer rather than a productivity surface: keybind remappings emit consistent escape sequences across macOS and Linux (via a `{{PLATFORM_MOD}}` template), so the same tmux and nvim keybinds work identically on both platforms. Shell integration is enabled, the colour scheme follows the active dotfiles theme, and `~/.config/ghostty/local` is loaded at the end of the config so cursor style, fonts, and personal tweaks survive updates.

### Neovim

> Modular config based on kickstart.nvim with lazy.nvim, Treesitter, and Mason-managed language servers. Startup is roughly 100ms.

- **LSP** for TypeScript, Go, Python, Lua, C#/.NET (Roslyn), C/C++/Objective-C (clangd), Swift (sourcekit-lsp), ESLint, Bash, CSS/Tailwind, HTML, YAML and more, with formatting (clang-format, swift-format), linting (swiftlint), and codelldb debugging wired up for the C family and Swift
- **SonarLint** as a second LSP client surfacing SonarQube/SonarCloud diagnostics for JS/TS, Python, Go, C/C++, PHP, HTML/CSS, IaC (Terraform/HCL), Docker, YAML, and XML (no local C# analysis: its bundled omnisharp would fight the Roslyn setup, see [docs/SONARLINT.md](docs/SONARLINT.md)); connected mode auto-enables when `SONARQUBE_TOKEN` and `SONARQUBE_ORG` are set, with per-project binding via `.sonarlint/connectedMode.json` and ESLint-style rule overrides via `.sonarlint/localRules.json`, which you can edit by hand or populate from the `gra` code-action menu ("silence rule project-wide" / "in test files"); the first code action opens a rich rule-description popup that, for deprecation findings, leads with the deprecated symbol and its recommended replacement (see [docs/SONARLINT.md](docs/SONARLINT.md))
- **Diffs and PR review** via differ.nvim (my own plugin): local side-by-side diffs, file history, staging, GitHub PR review, merge conflict resolution, and diff-by-ticket (`<leader>dT`) through one renderer, with `<leader>d*` diff launchers and `<leader>p*` PR launchers (thread actions are in-diff gestures: `ga` comment, `gp` reply, `gr` resolve); Octo.nvim stays installed as a `:Octo` fallback, and gitsigns handles inline hunk decorations
- **The tpope suite:** fugitive (git wrapper), rhubarb (GitHub adapter for fugitive), abolish (case-aware substitution and coercion), repeat (extend `.` to plugin maps), and sleuth (auto-detect indent settings)
- **Build picker** (`Space q`) auto-detects Go, TypeScript, .NET, and Makefile projects and runs the appropriate build into the quickfix list
- **Tests** via Neotest (Go, Vitest/Bun, Jest/React Native, and pytest adapters), with .NET handled separately by easy-dotnet's dedicated test runner (`<leader>te` opens its Test Explorer)
- **Go editing helpers**: gomodifytags-backed struct tag add/clear (`<leader>la`/`<leader>lc`) and iferr block generation (`<leader>le`), plus `:GoAddTags`/`:GoRmTags`/`:GoIfErr`; both tools are Mason-managed
- **Binary object viewer**: opening a `.o`, `.a`, `.dylib`, or `.so` renders a decoded read-only view (demangled symbols, disassembly, hex dump) instead of raw bytes, with `s`/`d`/`x` to switch between them
- **Custom dashboard** plus a searchable cheatsheet (`Space ?`) for the keybindings
- **Self-contained colourschemes** with no plugin dependencies, so generated themes drop in as plain Lua files
- **GitHub Copilot** configured to refuse `.env`, credentials, and other secret files
- `~/.config/nvim/local.lua` is loaded before plugin specs (so `vim.g.*` is visible to them) and survives updates

### Tmux

> `` ` `` as the prefix, vim-style navigation between panes and windows, and a help popup (`` ` h ``) if you forget anything.

- **Session save and restore** with tmux-resurrect + continuum, plus a custom extension that splits the combined save into per-session backups, so you can restore one session without bringing back everything else (and sessions survive reboots)
- **fzf pickers everywhere:** sessions (`` ` s ``), windows (`` ` f ``), running nvim instances, AI agent instances (Claude / OpenCode / Copilot / Codex), themes (`` ` t ``), and URLs from scrollback (`` ` u ``); popups auto-size between compact and full-screen depending on terminal width
- **Multi-agent alerts** show coloured indicators in the session list when Claude, OpenCode, Copilot, or Codex need attention, clearing automatically when you switch to the session; all four CLIs are wired in via dedicated hooks under `scripts/hooks/wrappers/` (each CLI needs its hooks set up; see [docs/AGENT-HOOKS.md](docs/AGENT-HOOKS.md))
- **Live agent state in the Claude switcher** (`` ` c ``): each instance shows what it's doing (● working, ◐ waiting for input, ○ idle, ✗ errored, ⚠ stuck) and, once it's waiting on you, how long it's been idle or blocked, driven by Claude Code hooks writing per-pane state files; stuck detection cross-checks the pane title so long tool runs aren't flagged (see [docs/AGENT-HOOKS.md](docs/AGENT-HOOKS.md))
- **Command exit alerts** flag the result with ✓ or ✗ when a long-running command finishes in a pane you've switched away from
- **Process list** (`` ` `` <kbd>Shift</kbd>+<kbd>P</kbd>) is one fzf switcher over everything you're watching: running commands (tests, builds, servers) as live ● rows with elapsed time, plus finished commands as ✓/✗ rows; jump to any, press <kbd>x</kbd> to stop a running one or clear a finished one, or rerun a finished command with <kbd>r</kbd> (stage it on its window's prompt to review) or <kbd>R</kbd> (stage and run); finished rows also clear once you view their window
- **Undo system** (`Opt/Alt+u`) restores the most recently closed pane or window with full directory, scrollback, and layout intact
- **Session launchers** (`` ` p ``) cover `dev`, `github` (gh-dash), `btop`, `docker` (lazydocker), `dotfiles`, and `config`; an interactive wizard (`n`) scaffolds new ones, and user launchers in `~/.config/dotfiles/launchers/` override repo launchers by name. The same system is reachable from a plain shell: `tl` opens the picker, and `tl <query>` resolves a directory via zoxide, then attaches to its `dev` session or creates one
- **Navigation history** (`` ` - `` / `` ` = ``) for browser-style back/forward across windows and sessions
- `~/.config/tmux/local.conf` survives theme changes and updates

### Zsh

- **Powerlevel10k** prompt with instant prompt and git status
- **Performance:** lazy-loaded completions, fnm (~5ms) over nvm (~300ms), and cached eval for direnv and fzf, with median startup benchmarked in CI on every push and PR (the job fails if it exceeds 125ms)
- **carapace** as the completion bridge, so modern completion specs (gh, kubectl, docker, etc.) work in zsh without per-tool wrangling
- **zoxide** for a `cd` that learns the directories you actually use
- **fzf integration:** `Ctrl+R` for history search, `Ctrl+T` for file finding, and `Opt/Alt+A` for directory history
- **Git aliases** for the things you do all day: `gs` (status), `gl` (log), `gfp` (fetch + prune), `gpr` (prune local branches gone from remote), `grmc` (untrack files), and many more
- **Directory navigation:** `cdb`/`cdf` for browser-style back/forward, `mkcd` to make and enter, and `cl` for a full terminal reset
- **Clipboard:** `<cmd> | clip` copies and bare `clip` pastes, on macOS and Linux alike. The backend follows the live display server (`pbcopy`, `wl-copy`, `xclip`, `xsel`), falling back to OSC 52 so it still works headless and over SSH
- **Editing:** `Ctrl+G` opens the current command in `$EDITOR`, and `Spacebar` expands the alias under the cursor
- **Man pages** open in nvim, so search, `K` on a cross-reference, and yank all behave as they do in any other buffer; shells started inside nvim keep plain `less` instead of nesting an editor
- **Tab completion** for the dotfiles CLI and the tmux helper commands; run `dot aliases` for the full list

### Dotfiles CLI

```bash
dotfiles update    # smart incremental update (only re-runs changed steps)
dotfiles status    # version, sync status, and local changes
dotfiles health    # full health check (symlinks, plugins, env vars)
dotfiles links     # show all managed symlinks and their status
dotfiles theme     # list, switch, or generate themes
dotfiles export    # export your local layer to a private repo
dotfiles import    # import your local layer from a private repo
dotfiles local     # manage the private local-layer repo
dotfiles aliases   # browse all shell aliases and shortcuts
dotfiles notes     # browse the changelog in a pager
dotfiles version   # current version, release/update dates, preset, and theme
dotfiles edit      # open dotfiles in $EDITOR
```

`dot` is a shorthand for `dotfiles`. Both have full tab completion.

---

## Themes

> From within tmux, `` ` t `` opens an fzf picker over the hand-crafted set and Ghostty's themes; selecting one re-skins tmux, ghostty, neovim, fzf, gh-dash, and lazygit instantly with no restart. Selecting a Ghostty theme generates it on the fly.

The `dotfiles theme` CLI is the management surface, useful for scripting, listing, switching by name, and generating themes from a Ghostty palette:

```bash
dotfiles theme                                 # list available themes
dotfiles theme switch dracula                  # switch by name
dotfiles theme generate "Catppuccin Latte"     # generate a theme from a Ghostty palette
```

Two sources feed the picker:

- **14 hand-crafted themes** with tuned palettes, all checked against WCAG 2.1 contrast ratios: Dracula, Catppuccin Mocha, Tokyo Night, Nord, Rosé Pine, Kanagawa, Gruvbox, Synthwave, One Dark, Monokai, Nightfox, Everforest, Ayu Dark, Solarized.
- **~460 Ghostty themes** generatable on the fly: the Lua pipeline parses a Ghostty palette (16 ANSI colours + foreground/background), derives semantic roles (six accents, selection, secondary surfaces), corrects for WCAG 2.1 (4.5:1 minimum contrast), and outputs a `.theme` file plus a self-contained neovim colourscheme

An AI CLI coding agent's statusline can follow the active theme too, for agents that render their statusline by running a script (Claude Code, GitHub Copilot CLI, Antigravity CLI). Source `~/.config/dotfiles/statusline-theme.sh` to get `SL_*` ANSI colour variables mapped from the current palette, then use them behind your own defaults (e.g. `${SL_BRANCH:-…}`); semantic roles (the git `+/-` diff and status markers) are hue-locked so additions/deletions always read green/red whatever the theme. It reads the theme live, so the statusline re-colours on the next render after `dotfiles theme switch`. See [docs/THEME-SYSTEM.md](docs/THEME-SYSTEM.md#statusline-integration).

Themes are pure colour palettes; anything else you want to customise (fonts, cursor style, extra keybindings, per-machine settings) goes in the per-tool `local.*` files, which sit alongside the theme-generated configs and never get touched by `dotfiles update`:

| Tool        | Override file                     |
| ----------- | --------------------------------- |
| Tmux        | `~/.config/tmux/local.conf`       |
| Neovim      | `~/.config/nvim/local.lua`        |
| Ghostty     | `~/.config/ghostty/local`         |
| gh-dash     | `~/.config/gh-dash/local.yml`     |
| LazyGit     | `~/.config/lazygit/local.yml`     |
| Hammerspoon | `~/.hammerspoon/local.lua`        |
| Zsh         | `~/.zshrc` (your personal config) |

See [docs/THEME-SYSTEM.md](docs/THEME-SYSTEM.md) for the architecture.

### Syncing the local layer between machines

The base repo stays generic, but the local layer (the override files above, plus `~/.zshrc`, personal launchers, and the copy-on-install configs) can be synced across your own machines via a private git repo. The public repo never references it; the link is a machine-local pointer (`~/.config/dotfiles/local-repo`, or the `DOTFILES_LOCAL_DIR` env var). Secrets are never synced, and neither is the current theme: it stays a per-machine choice.

```bash
# one machine (urls accept GitHub owner/repo shorthand)
dotfiles local init you/dotfiles-local
dotfiles export --push        # capture, commit, push

# another machine (clone registers the repo and applies it immediately)
dotfiles local clone you/dotfiles-local

# picking up later changes on demand (updates also import automatically)
dotfiles import               # skips files that differ; --force overwrites, --prune deletes launchers removed upstream

# sync a single entry instead of the whole layer
dotfiles import zshrc --force # pull just ~/.zshrc; selectors match by path, suffix, basename, or a launcher name
dotfiles export tmux/local.conf
```

On a fresh machine, clone the private repo to `~/.dotfiles-local` before running the installer and it is adopted and imported automatically. `dotfiles local status` shows sync state; `dotfiles local diff` shows exactly what differs; `dotfiles local edit` opens the local-layer repo in `$EDITOR`.

**Which copy do I edit?** Edit the **installed** file (e.g. `~/.config/nvim/local.lua`), not the copy under `~/.dotfiles-local`. The installed file is what the tool actually loads and it works standalone, whether or not a local-layer repo exists. The `~/.dotfiles-local` copy is a sync snapshot that nothing loads directly: `dotfiles export` copies installed to repo (and stages it in git), `dotfiles import` copies repo to installed. So the flow is edit the live file, `dotfiles export`, then commit in the local repo.

`dotfiles local diff` reports drift between the two copies. Because `export` auto-commits, it also flags any uncommitted change in `~/.dotfiles-local` (scoped to the managed files): that state only arises when a repo file was edited by hand, and a later `export` would overwrite it, so the command surfaces it even when the two copies otherwise match. Avoid editing the `~/.dotfiles-local` copy directly: it has no effect until you `dotfiles import`, and a later `export` treats the installed file as the source of truth and overwrites any repo-only edit you never imported. If you do author on the repo side (to push a change out to another machine), run `dotfiles import` straight after so the live file gets it and the next `export` cannot clobber it.

---

## Brewfile

> Three flavours selected at install time (`--minimal`, `--core`, `--full`), filtered from a single `Brewfile` via preset markers.

### My own tools

| Tool                                               | What it does                                                                               |
| -------------------------------------------------- | ------------------------------------------------------------------------------------------ |
| [supplyscan](https://github.com/undont/supplyscan) | Go CLI / MCP that scans JS-ecosystem projects for vulnerabilities and supply-chain attacks |
| [jiru](https://github.com/undont/jiru)             | Bubble Tea TUI for managing Jira issues and Confluence pages                               |
| [seeql](https://github.com/undont/seeql)           | SQL client TUI                                                                             |
| [gh-bench](https://github.com/undont/gh-bench)     | `gh` CLI extension for benchmarking GitHub Actions and tracking failures                   |

### gh CLI extensions (auto-installed)

| Extension                                          | What it does                                                                                     |
| -------------------------------------------------- | ------------------------------------------------------------------------------------------------ |
| [gh-dash](https://github.com/dlvhdr/gh-dash)       | Terminal dashboard for GitHub PRs, issues, and repos. Themed and re-skinned by `dotfiles theme`. |
| [gh-enhance](https://github.com/dlvhdr/gh-enhance) | Enhanced PR view and review workflow on top of `gh pr`.                                          |

Bundled helper: **`dash-repo-sync`** (in `~/.local/bin/`) scans `DEV_ROOT` and `PROJECTS_ROOT` for git repos with GitHub remotes, syncs them into gh-dash's `repoPaths`, and prunes stale entries. Wildcard entries are preserved. Run on demand; pass `--dry-run` to preview changes

### Other tools included

| Category            | Tools                                                                                                                                                                                             |
| ------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Shell completion    | `carapace` (multi-shell completion bridge), `zsh-autosuggestions`, `direnv`                                                                                                                       |
| Git & GitHub        | `gh`, `lazygit`, `diffnav`, `act` (run GitHub Actions locally)                                                                                                                                    |
| Containers & shells | `lazydocker`, `lazyssh`, `cloudflared`                                                                                                                                                            |
| Search & files      | `fd`, `ripgrep`, `bat`, `jq`, `yq`, `zoxide`, `fzf`, `yazi` (file manager), `poppler` (PDF previews), `ffmpegthumbnailer` (video previews), `resvg` (SVG previews), `sevenzip` (archive previews) |
| System              | `btop`, `gdu` (disk usage TUI), `fastfetch`                                                                                                                                                       |
| Media & display     | `ffmpeg`, `imagemagick`, `chafa`, `glow`                                                                                                                                                          |
| Terminal extras     | `asciinema`, `figlet`, `toilet`, `tmux-fingers`                                                                                                                                                   |
| Languages           | `fnm`, `bun` (Node), `go`, `python@3.13`, `openjdk` (Java), `dotnet-sdk` (.NET)                                                                                                                   |

### Tap trust

Homebrew is set to require explicit trust for non-official taps (`HOMEBREW_REQUIRE_TAP_TRUST=1`). The taps these tools come from are trusted automatically during install, and any taps you already had are trusted on update. To add a new third-party tap yourself, approve it once with `brew trust --tap <user/repo>` before installing from it.

### macOS-only (full preset)

- **Hammerspoon:** centres and resizes windows to 70% of the screen on creation for Ghostty, Arc, Dia, Discord, Slack, and Obsidian (skipping if already roughly centred); CLI access via the `hs` IPC binary, with a `~/.hammerspoon/local.lua` override
- **Karabiner Elements:** Caps Lock to Escape, Right Option to Control (for Ghostty + JetBrains keybind compatibility), UK keyboard layout fixes
- **Raycast:** Spotlight replacement
- **music-presence:** Discord Rich Presence for Apple Music
- **Default apps:** `scripts/install/set-default-apps.sh` makes Zed the default handler for code file types (`.ts`, `.json`, `.md`, `.toml`, and so on) via `duti`; runs whenever Zed is installed (core preset and up)

### Linux-only

- **keyd:** keyboard remapping daemon, the Linux equivalent of Karabiner, config at `keyd/default.conf`, deployed and enabled by `scripts/install/setup-keyd.sh`

---

## Keybindings

<table>
<tr><td>

### Tmux

| Action                 | Keybinding                                 |
| ---------------------- | ------------------------------------------ |
| Prefix                 | <kbd>`</kbd>                               |
| Help popup             | <kbd>`</kbd> <kbd>h</kbd>                  |
| Launcher picker        | <kbd>`</kbd> <kbd>p</kbd>                  |
| Process list           | <kbd>`</kbd> <kbd>Shift</kbd>+<kbd>P</kbd> |
| Theme picker           | <kbd>`</kbd> <kbd>t</kbd>                  |
| Save session           | <kbd>`</kbd> <kbd>w</kbd>                  |
| Session switcher       | <kbd>`</kbd> <kbd>s</kbd>                  |
| Window switcher        | <kbd>`</kbd> <kbd>f</kbd>                  |
| URL picker             | <kbd>`</kbd> <kbd>u</kbd>                  |
| Navigate back          | <kbd>`</kbd> <kbd>-</kbd>                  |
| Navigate forward       | <kbd>`</kbd> <kbd>=</kbd>                  |
| Rename window          | <kbd>Opt/Alt</kbd>+<kbd>r</kbd>            |
| Close pane             | <kbd>Opt/Alt</kbd>+<kbd>s</kbd>            |
| Close window           | <kbd>Opt/Alt</kbd>+<kbd>x</kbd>            |
| Undo pane/window       | <kbd>Opt/Alt</kbd>+<kbd>u</kbd>            |
| Reload local overrides | <kbd>`</kbd> <kbd>r</kbd>                  |
| Reload all shells      | <kbd>`</kbd> <kbd>R</kbd>                  |

</td><td>

### Neovim

| Action                    | Keybinding                                 |
| ------------------------- | ------------------------------------------ |
| Leader                    | <kbd>Space</kbd>                           |
| Cheatsheet                | <kbd>Space</kbd> <kbd>?</kbd>              |
| Find files                | <kbd>Space</kbd> <kbd>s</kbd> <kbd>f</kbd> |
| Find files (regex)        | <kbd>Space</kbd> <kbd>s</kbd> <kbd>F</kbd> |
| Live grep                 | <kbd>Space</kbd> <kbd>s</kbd> <kbd>g</kbd> |
| File explorer             | <kbd>Space</kbd> <kbd>e</kbd>              |
| Git (LazyGit)             | <kbd>Space</kbd> <kbd>g</kbd>              |
| Build (quickfix)          | <kbd>Space</kbd> <kbd>q</kbd>              |
| Format                    | <kbd>Space</kbd> <kbd>f</kbd>              |
| Test nearest              | <kbd>Space</kbd> <kbd>t</kbd> <kbd>t</kbd> |
| Diagnostics (live list)   | <kbd>Space</kbd> <kbd>x</kbd> <kbd>x</kbd> |
| Git-modified diagnostics  | <kbd>Space</kbd> <kbd>x</kbd> <kbd>m</kbd> |
| Branch diagnostics        | <kbd>Space</kbd> <kbd>x</kbd> <kbd>b</kbd> |
| Ticket-commit diagnostics | <kbd>Space</kbd> <kbd>x</kbd> <kbd>T</kbd> |
| Project-wide diagnostics  | <kbd>Space</kbd> <kbd>x</kbd> <kbd>S</kbd> |
| Grep yank to quickfix     | <kbd>Space</kbd> <kbd>x</kbd> <kbd>/</kbd> |
| PR diff review            | <kbd>Space</kbd> <kbd>d</kbd> <kbd>p</kbd> |

</td><td>

### Zsh

| Action                    | Keybinding                      |
| ------------------------- | ------------------------------- |
| History search            | <kbd>Ctrl</kbd>+<kbd>R</kbd>    |
| File finder               | <kbd>Ctrl</kbd>+<kbd>T</kbd>    |
| Directory history         | <kbd>Opt/Alt</kbd>+<kbd>A</kbd> |
| Edit command in editor    | <kbd>Ctrl</kbd>+<kbd>G</kbd>    |
| Expand alias under cursor | <kbd>Spacebar</kbd>             |

</td></tr>
</table>

---

## Uninstalling

```bash
./scripts/install/uninstall.sh                                          # remove symlinks only
./scripts/install/uninstall.sh --restore-backup                         # restore original configs
./scripts/install/uninstall.sh --restore-backup --remove-brew-packages  # full uninstall
```

---

## Contents

<details>
<summary><b>Repository structure</b></summary>

```
dotfiles/
├── zsh/              # Zsh shell configuration
│   ├── dotfiles.zsh  # Shared framework (sourced by ~/.zshrc)
│   ├── zshrc         # Backwards-compat wrapper for legacy symlinks
│   ├── zshrc.template # Template for user's personal ~/.zshrc
│   ├── zprofile      # Login shell config
│   └── p10k.zsh      # Powerlevel10k theme
├── tmux/             # Tmux terminal multiplexer
│   ├── tmux.conf.template # Config template (processed by dotfiles theme)
│   ├── scripts/      # Custom scripts across 11 categories
│   ├── plugins/      # TPM-managed plugins
│   └── tmux-help.template # Keybinding help (renders Opt/Alt per platform)
├── nvim/             # Neovim configuration
│   ├── init.lua      # Entry point
│   ├── colors/       # Self-contained colourschemes (hand-crafted + generated)
│   ├── cheatsheet.txt # Searchable keybinding reference (Space ?)
│   ├── snippets/     # Custom LuaSnip snippets
│   └── lua/custom/   # Modular config
│       ├── core/     # Options, keymaps, autocmds, theme, quickfix
│       └── plugins/  # Plugin configurations
├── lazygit/          # LazyGit configuration
├── lazydocker/       # LazyDocker configuration
├── btop/             # System monitor configuration
├── yazi/             # Terminal file manager (larger PDF/image previews)
├── launchers/        # Session launch scripts (picker: prefix + p)
├── hammerspoon/      # macOS automation (auto-centre windows)
├── gh-dash/          # GitHub dashboard (themed, keybindings, local overrides)
├── ghostty/          # Terminal emulator (themed via dotfiles theme)
├── karabiner/        # macOS keyboard customisation
├── keyd/             # Linux keyboard customisation
├── scripts/          # Installation and utility scripts
│   ├── dotfiles      # CLI for managing dotfiles (includes theme management)
│   ├── install/      # Installer modules
│   ├── hooks/        # Agent alert, command exit alert + buffer sync hooks
│   ├── tests/        # Test suites
│   └── _lib/         # Shared shell libraries
├── themes/           # Hand-crafted + generated theme definitions (WCAG checked)
├── docs/             # Documentation
└── Brewfile          # Homebrew dependencies (preset-filtered)
```

</details>

<details>
<summary><b>Manual symlink commands</b></summary>

```bash
# Zsh (template creates ~/.zshrc which sources dotfiles.zsh)
cp ~/dotfiles/zsh/zshrc.template ~/.zshrc  # only if ~/.zshrc doesn't exist
ln -sf ~/dotfiles/zsh/zprofile ~/.zprofile
ln -sf ~/dotfiles/zsh/p10k.zsh ~/.p10k.zsh

# Tmux (symlink entire directory, config is generated)
ln -sf ~/dotfiles/tmux ~/.tmux
# config generated by: dotfiles theme switch dracula

# Neovim
ln -sf ~/dotfiles/nvim ~/.config/nvim

# Session launchers
mkdir -p ~/.local/launchers
ln -sf ~/dotfiles/launchers/dev ~/.local/launchers/dev

# Dotfiles CLI + utilities
mkdir -p ~/.local/bin
ln -sf ~/dotfiles/scripts/dotfiles ~/.local/bin/dotfiles
ln -sf ~/dotfiles/gh-dash/dash-repo-sync ~/.local/bin/dash-repo-sync

# LazyGit (symlinked base + local override)
mkdir -p ~/.config/lazygit
ln -sf ~/dotfiles/lazygit/config.yml ~/.config/lazygit/config.yml
cp -n ~/dotfiles/lazygit/local.yml.template ~/.config/lazygit/local.yml

# Hammerspoon (symlinked init.lua + local override)
ln -sf ~/dotfiles/hammerspoon/init.lua ~/.hammerspoon/init.lua
cp -n ~/dotfiles/hammerspoon/local.lua.template ~/.hammerspoon/local.lua

# Ghostty (config generated by dotfiles theme to ~/.config/ghostty/config)
mkdir -p ~/.config/ghostty

# Karabiner Elements (copy-on-install, user-owned after first install)
mkdir -p ~/.config/karabiner
cp -n ~/dotfiles/karabiner/karabiner.json ~/.config/karabiner/karabiner.json
```

</details>

## Documentation

- [Agent Hooks](docs/AGENT-HOOKS.md): setup guide for agent alert hooks (Claude Code, OpenCode)
- [Command Exit Alerts](docs/CMD-ALERTS.md): auto ✓/✗ alerts when commands finish in other windows
- [Installation Guide](docs/INSTALLATION-GUIDE.md): detailed walkthrough of each installation step
- [Theme System](docs/THEME-SYSTEM.md): how themes work, the Ghostty theme generator, and WCAG contrast checks
- [Troubleshooting](docs/TROUBLESHOOTING.md): common issues and solutions

---

## Licence

[MIT](LICENCE)
