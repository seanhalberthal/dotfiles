# Local Layer

The base repo stays generic. Everything personal or machine-specific lives in a
separate "local layer" that `dotfiles update` never touches, and which can be
synced across your own machines through a private git repo.

## What the local layer is

Tools that support an include mechanism load a `local.*` file on top of the
symlinked base config:

| Tool        | Override file                     |
| ----------- | --------------------------------- |
| Tmux        | `~/.config/tmux/local.conf`       |
| Neovim      | `~/.config/nvim/local.lua`        |
| Ghostty     | `~/.config/ghostty/local`         |
| gh-dash     | `~/.config/gh-dash/local.yml`     |
| LazyGit     | `~/.config/lazygit/local.yml`     |
| Hammerspoon | `~/.hammerspoon/local.lua`        |
| Zsh         | `~/.zshrc` (your personal config) |

The layer also covers personal launchers and the copy-on-install configs (btop,
lazydocker, karabiner, zed's `settings.json`).

Each file is created from a `*.template` on first install and is yours from then
on. Updates never overwrite them.

## Syncing between machines

The public repo never references your private one. The link is a machine-local
pointer at `~/.config/dotfiles/local-repo`, or the `DOTFILES_LOCAL_DIR`
environment variable.

```bash
# one machine (urls accept GitHub owner/repo shorthand)
dotfiles local init you/dotfiles-local
dotfiles export --push        # capture, commit, push

# another machine (clone registers the repo and applies it immediately)
dotfiles local clone you/dotfiles-local

# picking up later changes on demand (updates also import automatically)
dotfiles import               # skips files that differ

# sync a single entry instead of the whole layer
dotfiles import zshrc --force # selectors match by path, suffix, basename, or launcher name
dotfiles export tmux/local.conf
```

`--force` overwrites files that differ; `--prune` deletes launchers removed
upstream. Pruning is deliberately not part of `--force`, so a launcher created on
one machine survives an overwrite import on another.

On a fresh machine, clone the private repo to `~/.dotfiles-local` before running
the installer and it is adopted and imported automatically.

Inspect state with `dotfiles local status`, see exactly what differs with
`dotfiles local diff`, and open the repo in `$EDITOR` with `dotfiles local edit`.

## What is never synced

Secrets (`~/.config/zsh/secrets.zsh`), the `.state/` directory, and the
`current-theme` pointer are hard-excluded. Theme is a per-machine choice.

## Which copy do I edit?

Edit the **installed** file (e.g. `~/.config/nvim/local.lua`), not the copy under
`~/.dotfiles-local`.

The installed file is what the tool actually loads, and it works standalone
whether or not a local-layer repo exists. The `~/.dotfiles-local` copy is a sync
snapshot that nothing loads directly:

- `dotfiles export` copies installed to repo, and stages it in git
- `dotfiles import` copies repo to installed

So the flow is: edit the live file, `dotfiles export`, then commit in the local
repo.

`dotfiles local diff` reports drift between the two copies. Because `export`
auto-commits, it also flags any uncommitted change in `~/.dotfiles-local`, scoped
to the managed files. That state only arises when a repo file was edited by hand,
and a later `export` would overwrite it, so the command surfaces it even when the
two copies otherwise match.

Avoid editing the `~/.dotfiles-local` copy directly: it has no effect until you
`dotfiles import`, and a later `export` treats the installed file as the source of
truth and overwrites any repo-only edit you never imported. If you do author on
the repo side, to push a change out to another machine, run `dotfiles import`
straight after so the live file gets it and the next `export` cannot clobber it.
