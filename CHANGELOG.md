# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [0.2.139] - 2026-08-18

### Added

- busted and luassert types in lua spec files, through lazydev rather than `.luarc.json`: `${3rd}/busted/library` behind a `describe%s*%(` trigger and `${3rd}/luassert/library` behind `assert%.`. Any `workspace.library` entry in `.luarc.json`, including a lone `${3rd}` one, makes lua_ls stop resolving a project's own `require`d modules, so `gd` on a cross-file symbol reports "No definitions found" while same-file lookups still work; routing third-party libraries through lazydev keeps that file clean. `words` are matched with a bare substring find, so there is no `it%s*%(` trigger, which would fire inside `split(`, `edit(` and `wait(`; busted's library declares `it` alongside `describe`, so the one trigger covers a whole spec file. `nvim/lua/custom/plugins/lazydev.lua`, `.claude/rules/neovim.md`
- `<leader>sS` and `:Snippets` open a telescope picker over every snippet that can expand in the current buffer, previewing the body with the buffer's filetype and expanding the selection at the cursor. Snippets were the one completion source with nothing behind them: friendly-snippets ships JSON data with no vimdoc, blink exposes no browser command, and its menu only reveals a body once a prefix has already been typed, so a prefix you don't know is unreachable. The picker reads blink's own registry, built from the live source opts, so the search paths and `friendly_snippets` setting always match what the menu serves rather than a second guess at them. It also lists the lua snippets loaded into LuaSnip, which the menu never shows at all: blink's `default` preset scans for `%.json$` only, so `nvim/snippets/all.lua` is invisible to it, and those entries expand through `snip_expand` instead of `vim.snippet.expand`. `nvim/lua/custom/features/snippets.lua`, `nvim/lua/custom/core/keymaps.lua`, `nvim/cheatsheet.txt`

### Changed

- The empty-buffer cleanup checks a tracked candidate set instead of rescanning every open buffer. It ran the full list on every `BufEnter`, six `nvim_buf_*` calls per buffer, on an event that fires about as often as a keystroke does. Only a buffer that was created unnamed can ever qualify, so `BufNew`/`BufAdd` collect those (seeded once from the buffer list, since the startup `[No Name]` buffer predates the autocmd) and the scheduled pass walks just them, returning before it schedules anything when the set is empty. The pass re-validates each candidate, so one that has since been named, filled or given a `buftype` drops out of the set rather than being rechecked forever. Which buffers get deleted is unchanged. `nvim/lua/custom/core/autocmds.lua`
- The telescope grep pickers exclude `.git/` at the rg level rather than after the fact. `--hidden` lifts ripgrep's own skip of dotfiles, so every search descended into the repository's object store: 2707 files opened and scanned in this repo, all of them then discarded by the `%.git/` entry in `file_ignore_patterns`. `--glob=!.git/` stops the walk instead, so the results are unchanged and the work isn't done. The exclusion is repeated at the `<leader>sG` call site because telescope merges picker config with a shallow `tbl_extend("force", ...)`, so a call-site `additional_args` replaces the picker default outright rather than adding to it. `nvim/lua/custom/plugins/telescope.lua`
- `:grep`, along with `grepadd`, `lgrep` and `lgrepadd`, runs silently and opens the list it fills. `:grep` shells `grepprg` out through `:!`, so it echoed the command line with its tmpfile path, then every raw ripgrep match, then the jump message, and finished on a hit-enter prompt; under `cmdheight=0` that forces the cmdline area open for the length of the output and collapses it again. A cmdline abbreviation prepends `silent`, and a `QuickFixCmdPost` hook runs `cwindow` (`lwindow` for the location-list variants), which opens the window only when there are entries and closes a stale one when there aren't. The abbreviation carries no bang of its own: an abbreviation fires on the non-keyword character that follows it, so `:grep!` expands at the `!`, and a baked-in bang would yield `:grep!!`, which searches for `!` and takes the real pattern as a path. `:grep` therefore still jumps to the first match and `:grep!` still doesn't. The expansion is guarded on the cmdline being nothing but the command, so `:vimgrep`, `:Ggrep` and an explicit `:silent grep` are left alone. Silencing swallows the zero-match case whole, since a `grepprg`-based `:grep` reports no `E480`, so an empty result notifies instead. `nvim/lua/custom/features/lists.lua`, `nvim/cheatsheet.txt`
- `listchars` renders tabs blank instead of `» `. indent-blankline already paints leading indentation with its own `tab_char`, so the `listchars` glyph only ever surfaced where ibl doesn't reach: mid-line tabs, and commented-out code, where prepending `// ` takes the indentation out of leading position and unmasks the arrows for a whole commented block. The value is two spaces rather than an omitted key; with `list` set, dropping `tab` falls back to `^I`. `nvim/lua/custom/core/options.lua`
- Go's `tdt` table-driven test snippet uses the `tests`/`tt`/`name` naming from the standard library's own tests rather than friendly-snippets' `testCases`/`tC`/`desc`. It is the first entry in `nvim/snippets/`, which blink's default preset already scans ahead of friendly-snippets but never deduplicated against it: `sources.deduplicate` is unimplemented upstream and `filter_snippets` only drops whole files, so a local override would have sat in the menu next to the copy it replaces. A `transform_items` on the snippets provider keeps the first item for each label, which is the local one wherever a prefix collides, so a single snippet can be replaced without taking over the filetype. Its only other effect is on markdown, where it collapses the nine entries `global.json` contributes twice by being registered for both `all` and `markdown`. `nvim/snippets/go.json`, `nvim/lua/custom/plugins/completion.lua`

### Fixed

- Quitting nvim no longer waits on a language server. nvim's own `VimLeavePre` handler takes the largest `exit_timeout` across every attached client and `vim.wait`s for them all to close, so a server too busy to answer spends the whole budget: copilot's 1000 cost a full second per quit under a loaded solution, where an idle one answers in about 10ms. The `ExitPre` hook that already force-killed roslyn now covers every client, and copilot's timeout drops to 200. roslyn's `filewatching` moves off `auto` to `roslyn`, sparing `Client:stop` the cancellation of ~500 FSEvents watchers at ~1.2ms each, another ~560ms on `:q` in a .NET repo. Runtime restarts (`:lsp restart roslyn`) still get the per-client timeouts. `nvim/lua/custom/plugins/lsp.lua`, `nvim/lua/custom/plugins/copilot.lua`, `nvim/lua/custom/plugins/dotnet.lua`
- The exit hook no longer loads dap just to terminate it. `require('dap')` in the config's own `VimLeavePre` pulled the whole plugin in, ~18ms, to end a session that cannot exist if dap was never loaded, so it is guarded on `package.loaded['dap']`. `nvim/lua/custom/core/autocmds.lua`
- The dashboard's statusline hide follows window focus rather than firing once on open. `laststatus` is global, so a one-shot toggle leaks in both directions: snacks' own startup hide gives up the first time another window is entered and never comes back, which is why closing a `:Differ` tabpage landed on a dashboard with a statusline drawn over it, while hiding on `SnacksDashboardOpened` instead followed the dashboard into every other window. A `BufEnter`/`WinEnter` watcher now syncs the option to whether the focused window holds the dashboard buffer, and it is created and torn down with the dashboard itself, so ordinary editing carries no extra per-event hook. Floating windows are skipped, so a picker opened over the dashboard doesn't flip the statusline back on behind it. `nvim/lua/custom/plugins/dashboard.lua`
- Spell autocorrect restores `wrapscan` and the saved view even when the range walk throws. `wrapscan` is global and is cleared for the duration so `]s` can't wrap past the range, so a throw partway through (an out-of-range cursor set, say) left the whole session without search wrapping and skipped the `winrestview` on the way out. The walk moved into a local function called through `pcall`, with both restores on the common path and the error rethrown afterwards. `nvim/lua/custom/core/spellcheck.lua`

### Removed

- The Ookla `speedtest` CLI and its `teamookla/speedtest` tap from the Brewfile. Nothing in the dotfiles referenced it: no alias, no tools-table row, no docs mention. As with the `lazycron` removal, no uninstall migration ships alongside it, so it stays usable wherever it is already installed. `Brewfile`
- The cursor-hold diagnostic float, reinstated in 0.2.138, goes again. Its `_hover_open` guard was only ever set by a `K` wrapper that 0.2.137 deleted along with the rest of the float, so the guard came back inert and the float opened over the LSP hover on every idle. It also won that overlap outright: `open_float` derives its `zindex` as `50` from the parent window, while noice renders hover at `45`. The virtual lines under the cursor line already carry the message, which is why the float was dropped in the first place. Its `CursorMoved` handler went with it, taking the `virtual_text` restore that had been switching end-of-line text back on after the first float closed, leaving both renderings of the same diagnostic on screen. `nvim/lua/custom/core/autocmds.lua`

## [0.2.138] - 2026-08-05

### Added

- `dotfiles health` reports zsh completion directory permissions. Homebrew installs its share directory group-writable, which `compaudit` flags and which makes the daily full `compinit` prompt before loading completions. The check runs `compaudit` in a clean zsh, names the fix script when it finds anything, and skips where zsh is absent so it stays quiet on a minimal Linux box. `scripts/install/health-check.sh`, `docs/TROUBLESHOOTING.md`
- nvim declares a clipboard provider on headless machines. On a bare ssh box with no display server and no tmux, nvim finds no clipboard tool at all: xsel and xclip are only considered when `$DISPLAY` is set, and nvim's own OSC 52 fallback is deliberately skipped whenever `clipboard` is non-empty. Copy now goes out over OSC 52, which reaches the clipboard of whichever machine the terminal is running on. Paste reads a local cache file rather than OSC 52, because a clipboard read blocks for up to ten seconds waiting on a response most terminals never send, which under `unnamedplus` would stall every `p`; the cache carries the register type on its first line, so blockwise and linewise yanks paste back with the shape they were yanked with. Inside tmux the tmux provider already covers this, so only standalone nvim declares one. `nvim/lua/custom/core/options.lua`
- Reopening a file returns the cursor to where it was left, centred in the window. nvim ships no such default. The centring is deferred a tick, so it re-checks that the window it was scheduled for still holds the same buffer: a background `bufload` runs the autocmd in a throwaway window that is gone by the time the schedule fires, and an unguarded `zz` recentres whichever window happens to be current, scrolling the view out from under you when a plugin loads a file visited earlier in the session. Commit and rebase buffers are skipped, since git reuses one path for them and the stored mark points partway into the previous message. `nvim/lua/custom/core/autocmds.lua`

### Changed

- The cursor-hold diagnostic float returns, alongside the virtual lines from 0.2.137. It tracks its own window handle and closes it deterministically on `CursorMoved`, `InsertEnter`, `BufLeave` and `WinLeave`, rather than relying on `open_float`'s close events, which miss window and buffer switches and can orphan the window when a new `CursorHold` fires before the one-shot close lands. Virtual text is hidden while the float is open and restored when it closes, and the `_hover_open` guard keeps the float off `K`. `nvim/lua/custom/core/autocmds.lua`
- Italic carries one meaning across every colourscheme: text that is not literal code. `Comment`, `SpecialComment` and `@markup.italic` keep it, and every other group loses it, with colours unchanged in all cases. That covers `@variable.parameter` in dracula, monokai, solarized-dark and synthwave, monokai's seven type roles, dracula's `Special`, `SpecialChar` and `@type.builtin`, and nightfox's `@tag.attribute`. Parameter italics were the one rule whose rendering depended on which language server was attached, since gopls sends no semantic tokens by default while Roslyn's reach every reference rather than the declaration alone. `bold` is untouched, since several themes use it as part of their own character. `nvim/colors/*.lua`, `docs/THEME-SYSTEM.md`
- nord's `SpecialComment` returns to the comment colour it shares with every other theme, having been moved onto cyan by the 0.2.135 syntax-role redistribution. `nvim/colors/nord.lua`
- `fix-compinit-insecure-dirs.sh` moves from `scripts/one-off/` to `scripts/`. It addresses a recurring condition rather than a spent one, since Homebrew reinstates the permission whenever it reinstalls, and `one-off/` gave it no discoverability. `scripts/fix-compinit-insecure-dirs.sh`
- The noice signature help popup is capped at 80 columns by 5 rows and no longer offsets to the right of the cursor. noice has no view of its own for signature help, so it borrows the hover view: 120 by 20, anchored to the cursor, and offset two columns right by the `lsp_doc_border` preset. Since the formatter appends the whole documentation body after the call signature, a function like `nvim_create_autocmd` fills every one of those rows, and the result lands over the code the moment the opening paren is typed. The cap keeps the signature and the active parameter, which is the part worth seeing mid-call, and the rest stays reachable by scrolling. The overrides are per-kind, so `K` hover keeps the full 120 by 20. `nvim/lua/custom/plugins/ui.lua`

### Fixed

- Obsidian vault notes are written in place rather than through a rename. Under the default `backupcopy=auto`, a write may be implemented as a rename of the original followed by a fresh file at the same path; a sync watcher reads that as an unlink and replicates a genuine delete of the note to every device, immediately followed by a re-create. `backupcopy=yes` forces copy-then-overwrite, so the original inode survives and the watcher sees a plain change. It is set buffer-local under the vault root, since `auto` is faster everywhere else. The backup directory also moves off the leading `.` entry, which had been writing backup files alongside the note inside the vault. `nvim/lua/custom/core/autocmds.lua`, `nvim/lua/custom/core/options.lua`
- The snacks dashboard no longer inherits syntax attributes from the active theme. Its `Desc`, `File` and `Special` groups linked to `Special`, which is a syntax role rather than a UI one, so any attribute a theme attached to it rendered on the startup screen: under dracula the menu entries and recent-file names came out italic. The three groups now take `Special`'s resolved foreground and set no attributes of their own, so a theme still controls the dashboard's colour while its attributes cannot reach it, including in generated themes that are never hand-audited. `nvim/lua/custom/plugins/dashboard.lua`
- The statusline no longer draws over the dashboard. snacks hides it for the dashboard it opens at startup and restores it the first time another window is entered, then forgets, so a dashboard rendered after that point kept a statusline across its last row; closing oil over the dashboard is the usual way to hit it. The hide is now mirrored on the dashboard's own `SnacksDashboardOpened` and `SnacksDashboardClosed` events, and skipped at startup where snacks has already hidden it, so the two never fight. `nvim/lua/custom/plugins/dashboard.lua`
- copilot's language server no longer outlives nvim. `exit_timeout` defaults to `false`, and on that default nvim's `VimLeavePre` handler neither force-stops the server nor waits for it: it fires an async shutdown request, calls `vim.wait(0)`, then exits, so a server too slow to answer inside that window reparents to pid 1 still holding its resident memory. Under memory pressure that is every session, and the orphans compound the pressure that caused them. A number instead defers a force-stop and makes the handler wait for it, returning as soon as the server closes; 1000ms is long enough for a healthy exit and short enough that nvim's "waiting for LSP exit" notice, which appears after 100ms, stays rare. `nvim/lua/custom/plugins/copilot.lua`
- tmux stops stacking duplicate `terminal-features` and `terminal-overrides` entries on reload. Both were appended with `-a`, which adds an array entry rather than replacing one, so every `source-file` grew the list again; they are now unset with `set -su` first. Both are server options, so the appends move from `-ag` to `-sa`. The `terminal-overrides` entry also separated its capabilities with a comma, which tmux reads as two array entries rather than two capabilities on one terminal, so `kend` replaced `khome` instead of joining it. They are colon-separated now, and Home/End reach pane apps as intended. `tmux/tmux.conf.template`
- The postgresql@17 cluster init no longer aborts the Linux install when no UTF-8 locale is available. `grep` exits 1 when it matches nothing, and under `set -e` that ended the script before either fallback could run, leaving the `C` locale default unreachable. Both lookups are guarded. `scripts/install/install-packages.sh`

### Removed

- The `gemini` alias, whose binary is neither installed nor in the Brewfile; the `cl &&` prefix meant running it cleared the scrollback before failing. Gemini's tmux integration went several releases ago and this was the remaining fragment. `zsh/dotfiles.zsh`, `docs/CMD-ALERTS.md`
- `lua/kickstart/health.lua`, reachable only through `:checkhealth kickstart` and covered by `check-prerequisites.sh` and `dotfiles health`, plus the `dev` block passed to `lazy.setup`, which nothing opted into: the local checkouts name their own directories with `dir=`. `nvim/init.lua`
- `e2backup.sh`, which mirrored a tree off an unmounted ext2/3/4 image and had nothing to do with the dotfiles. `scripts/one-off/` goes with it.
- Four migrations that only uninstalled a package (cronboard and posting, CSharpier, openapi-tui, postgresql@14). Uninstall migrations go obsolete once the version they target is well behind the current release, since the worst case for skipping one is unused software left installed; migrations that repair state are kept, because that state stays broken until something fixes it. `scripts/migrations/`
- `lazycron` from the Brewfile, along with its `lc` alias, its entry in the tools table and its place in the command-alert exclusion list. No uninstall migration ships alongside it, unlike previous Brewfile removals, since the tool stays usable wherever it is already installed. `Brewfile`, `zsh/dotfiles.zsh`, `README.md`, `docs/CMD-ALERTS.md`, `scripts/hooks/cmd-alert-hook.zsh`
- aerc is no longer managed by the dotfiles. The `aerc/` configs, the installer's core-tier symlink step, the `aerc` wrapper alias, the `accounts.conf` entry in the local-layer manifest, and the chmod-600 special case in `dotfiles import` all go, along with the `aerc` and `w3m` formulae; `w3m` was present only for aerc's html filter and nothing else depends on it. A migration removes the two symlinks that now dangle, but only where they are genuinely broken links into an aerc path, so a hand-rolled config is left alone. `accounts.conf` is kept and reported rather than deleted, since it is user-owned and holds account details, and the formulae are left installed for the same reason. `Brewfile`, `zsh/dotfiles.zsh`, `scripts/install/create-symlinks.sh`, `scripts/_lib/local-layer.sh`, `scripts/dotfiles`, `scripts/tests/test-dotfiles-local.sh`, `scripts/migrations/0.2.138-remove-aerc.sh`

## [0.2.137] - 2026-07-29

### Added

- `tl` reaches the tmux launcher system from a plain shell. With no arguments it opens the launcher picker; with a query it resolves a directory through zoxide (a literal path is taken as-is and fed back to zoxide to keep frecency fresh) and hands it to the `dev` launcher, which attaches to that directory's session or creates one. Since the picker is now reachable from outside tmux, the paths it drives fall back accordingly: session focus uses `attach-session` instead of `switch-client`, and the launcher's error and settings confirmations print to the terminal instead of vanishing with `display-message`. `zsh/dotfiles.zsh`, `tmux/scripts/_lib/common.sh`, `tmux/scripts/launchers/run.sh`, `tmux/scripts/launchers/settings.sh`
- `gd` is a second binding for go-to-definition in nvim, alongside `grd`. It goes through the same dedup wrapper, and shadows the built-in `gd` (go to local declaration), which `grD` already covers via the LSP. `nvim/lua/custom/plugins/lsp.lua`, `nvim/cheatsheet.txt`
- Man pages render in nvim through `MANPAGER="nvim +Man!"`, so `man foo` gets the built-in man filetype (syntax highlighting, `K` on a cross-reference, search and yank in a normal buffer) instead of `less`. Shells started inside nvim keep plain `less`, since `$NVIM` is set there and paging a man page through a nested nvim inside `:terminal` is worse than the default. `zsh/dotfiles.zsh`

### Changed

- The default obsidian vault root is `~/obsidian` rather than the iCloud container path. iCloud's on-demand eviction makes reads on an evicted note block indefinitely when `fileproviderd` is wedged, which hangs anything walking the vault (telescope, grep). Machines that keep their vault elsewhere still point at it with `vim.g.obsidian_vault_root` in `local.lua`, and the plugin is skipped entirely when neither resolves. `nvim/lua/custom/plugins/obsidian.lua`, `nvim/local.lua.template`
- Nvim diagnostics render as virtual lines under the cursor line rather than end-of-line virtual text. Long messages wrap instead of running off the right edge, and every diagnostic on a line is shown: the virtual-text handler only ever draws the *last* one, so stacked findings were silently hidden. Signs still mark affected lines everywhere else. The cursor-hold diagnostic float and the virtual-text hide/restore it drove are removed, since the virtual lines already show the message in place; `K` hover loses the `_hover_open` guard that existed only to keep the float off it. gopls labels analyzer findings with the placeholder code `default`, which the built-in formatter would render as a `default: ` prefix, so codes are only prefixed when they carry a real rule id. `nvim/lua/custom/plugins/lsp.lua`, `nvim/lua/custom/core/autocmds.lua`

### Fixed

- Session-collision detection works again for parameterised launchers. The `dev` launcher stopped suffixing `-dev` on derived session names in 0.2.92, but the picker kept deriving `<basename>-<launcher>` when checking for an existing session, so the check never matched and launching into a directory that already had a session skipped the collision prompt. Parameterised launchers all derive the session from the directory basename (the scaffold template produces fixed-session launchers), so the picker now uses the bare sanitised basename. `tmux/scripts/launchers/run.sh`, `launchers/dev`
- Diagnostics on generated files no longer fill the nvim lists. Generated code (sqlc, protoc-gen-go, mockgen, stringer) carries the Go canonical `// Code generated ... DO NOT EDIT.` sentinel on an early line; it is regenerated wholesale and never hand-edited, so findings on it are noise. The check sits next to the existing library/vendor filter and is shared by the live `<leader>xx` list and the git-scoped scans, cached per buffer against `changedtick`. The live list also collapses rows on file, line, column and text: `vim.diagnostic.get(nil)` spans every buffer, so the same file open under two bufnrs (a diff/review split, a second-window reopen) yielded byte-identical duplicates. `nvim/lua/custom/features/scan-runner.lua`, `nvim/lua/custom/features/lists.lua`, `nvim/lua/custom/features/diag-scan.lua`
- golangci-lint no longer double-reports what gopls already covers. lspconfig roots `golangci_lint_ls` at `go.work`/`go.mod`/`.git`, so it started in every Go project with golangci's default linter set (govet, staticcheck, ineffassign, unused); both servers publish to their own namespace and draw their own extmark, so each finding appeared twice. It now activates only where a project opts in with a `.golangci.{yml,yaml,toml,json}`, via a `root_dir` function that skips `on_dir` (overriding `root_markers` would not work: `vim.lsp.config` deep-merges lists by index, so the shorter list leaves lspconfig's `go.mod`/`.git` entries trailing). The server is also passed `-nolintername`, which stops it baking the linter name into the message text on top of the `source` field; that produced "errcheck: errcheck: ..." wherever we prefix by source. `nvim/lua/custom/plugins/lsp.lua`

## [0.2.136] - 2026-07-24

### Changed

- oil.nvim takes machine-local overrides through `vim.g.oil_opts`, matching the `vim.g.differ_opts` pattern. The spec deep-merges the global over its own defaults rather than replacing them, so naming one key keeps the `-` close handler, hidden files and the `<BS>`/`gi`/`go` maps intact; list-like values such as `columns` merge by index, so give the whole list, and a keymap is disabled with `false`. Existing `local.lua` files are never overwritten, so the documented examples only appear in a freshly installed one. `nvim/lua/custom/plugins/navigation.lua`, `nvim/local.lua.template`

## [0.2.135] - 2026-07-23

### Changed

- Nvim syntax roles are redistributed across the hand-written themes so keywords, types, identifiers and constants no longer collapse onto one or two accents. Each theme names its own role colours (mirroring the upstream palette it derives from) instead of repeating literal hexes, so `Type`/`Structure`/`Typedef` read distinctly from `Keyword`/`Conditional`/`Operator`, and `Constant`/`Identifier` no longer inherit the number colour. `nvim/colors/*.lua`

### Fixed

- Generated themes rescue near-grey accents: an accent with chroma below 30 (RGB max minus min) reads as tinted grey and cannot differentiate syntax roles, so it swaps to the theme's own bright palette variant when that is meaningfully more chromatic (e.g. Kanagawa Dragon's normal-row pink and cyan). Dull-but-chromatic accents stay untouched so deliberately muted themes keep their designer palette. `scripts/_lib/generate-theme.lua`, `nvim/colors/generated/`, `scripts/tests/test-generate-theme.lua`, `docs/THEME-SYSTEM.md`
- Go `chan`/`map` capture as keywords. Upstream captures them as `@type.builtin` alongside builtin type names, so `chan string` rendered as a single colour; re-capturing them as keywords lets the keyword and its element type read distinctly. `nvim/after/queries/go/highlights.scm`
- Snippet tabstops no longer paint a bright block over the argument just typed. `vim.snippet` highlights the active tabstop with `SnippetTabstop`, which defaults to `Visual`, so accepting an LSP call snippet (gopls) left the placeholder inverted; it is re-linked to the subtle `LspReferenceText` band every theme defines. The session is also stopped on return to normal mode, since the built-in only ends it on cursor moves in insert/select mode, leaving the tabstop extmark and its highlight alive indefinitely after Esc. `nvim/lua/custom/core/autocmds.lua`

## [0.2.134] - 2026-07-19

### Added

- `clip` copies and pastes on macOS and Linux alike: `<cmd> | clip` copies, bare `clip` pastes, `clip -p` forces a paste where the direction must not depend on context. The backend follows the live display server (`pbcopy`, `wl-copy`, `xclip`, `xsel`, `clip.exe`, `termux-clipboard-set`) rather than binary presence alone, since a Wayland session usually has xclip installed via XWayland and picking it there writes to a clipboard nothing reads back. With no display server (headless, or SSH without X11 forwarding) it falls back to OSC 52, which tmux forwards onward via `set-clipboard on`. On Linux `pbcopy`/`pbpaste` remain as shims, so existing muscle memory and scripts keep working. `zsh/dotfiles.zsh`, `scripts/_lib/clipboard.sh`
- Copilot accept-word on `<M-Tab>`: takes just the next word of the inline suggestion, alongside the full accept on `<Tab>`. `nvim/lua/custom/plugins/copilot.lua`, `nvim/cheatsheet.txt`
- `theme-switch help` (also `-h`/`--help`) prints usage with options and examples, and an unknown option now errors with usage instead of being looked up as a theme name. The usage text renders the invocation path via the same `DOTFILES_INVOKED_AS` convention as `generate-theme`/`theme-delete`: `dotfiles theme switch <name>` when delegated by the CLI, `theme-switch <name>` when run directly. `scripts/theme-switch`, `scripts/dotfiles`

### Changed

- Clipboard backend detection lives in `scripts/_lib/clipboard.sh` and is shared by the tmux scripts and `theme-switch`. The two carried separate copies with conflicting precedence (`common.sh` preferred xclip, `theme-switch` preferred wl-copy), so on a Wayland box with xclip installed, tmux copy-mode `y` and `pick-url.sh` wrote to different clipboards. `scripts/_lib/clipboard.sh`, `tmux/scripts/_lib/common.sh`, `scripts/theme-switch`
- Linux clipboard docs describe `clip` and cover Wayland, replacing the hand-written `xclip` alias snippet it supersedes. Adds a note that the clipboard is a shared, unencrypted resource and that `clip` makes no security claims. `docs/TROUBLESHOOTING.md`, `README.md`
- Ghostty dims unfocused splits (`unfocused-split-opacity = 0.5`), so the active split reads at a glance. `ghostty/config.template`
- `codex` added to the cmd-alert interactive-command exclude list, so its TUI sessions don't fire completion alerts. `scripts/hooks/cmd-alert-hook.zsh`, `docs/CMD-ALERTS.md`

### Fixed

- Claude instance picker labels each pane with its own pane title instead of the window name. The window name comes from automatic-rename, which tmux expands against the window's active pane only, so two claude splits in one window showed the same label (whichever pane was active last). The title's leading state glyph is stripped, and the window name remains the fallback until claude sets a session title. `tmux/scripts/instances/claude.sh`
- Clipboard detection no longer falls back to OSC 52 when a display server is running but its tool is missing. That case silently pushed the payload out through the terminal, and any SSH hop or tmux in between, when the local clipboard was what was asked for; it now fails naming the package to install. OSC 52 stays the fallback only when there is genuinely no display server. `zsh/dotfiles.zsh`, `scripts/_lib/clipboard.sh`
- `theme-switch` no longer bakes `pbcopy` into the generated tmux config when it finds no Linux clipboard tool; the shared detection returns a discard instead, and tmux's own `set-clipboard on` handles the OSC 52 path. `scripts/theme-switch`
- The clipboard precedence test exercises the real `scripts/_lib/clipboard.sh` instead of an inlined copy of its logic, which passed regardless of what the implementation did. `scripts/tests/test-linux-compat.sh`
- Per-session restore now replays saved scrollback. The plugin's save archives pane contents into `pane_contents.tar.gz`, but restore never extracted it and looked for loose files in a directory the plugin doesn't write, so `@resurrect-capture-pane-contents` was a silent no-op for per-session restores. The archive is extracted before panes are created and the extracted copy removed afterwards (on error too). `tmux/scripts/resurrect/restore.sh`, `tmux/scripts/tests/test-resurrect.sh`
- Quoted `@resurrect-processes` entries with spaces (`"~rails server"`) now match: naive word-splitting left literal quotes on the tokens, so those commands were never restored. The list is tokenised via `xargs`, and the defaults gain `btop` and `"~gh dash"` (the latter only possible with this fix). `tmux/scripts/resurrect/restore.sh`, `tmux/scripts/tests/test-resurrect.sh`, `tmux/tmux.conf.template`
- Grep-yanked-text (`<leader>x/`) no longer breaks when the yank contains `|`: the unescaped bar split vim's `:grep` command line, running everything after it as a separate command. `nvim/lua/custom/features/lists.lua`
- Nvim: the treesitter parser-purge rev guard actually works now. The old shell capture set an empty `GIT_DIR` in the environment, which makes git fail outright ("not a git repository: ''"), so the captured rev was always empty and the ABI purge never fired; worse, one launch captured shell diagnostics into the marker file. The rev is now read via `vim.system` argv (no shell) with `--git-dir` neutralising any inherited `GIT_DIR`, and only output matching a hex rev is trusted. `nvim/lua/custom/features/treesitter-parsers.lua`
- Nvim: `purge_if_updated` clears every `.so` from the plugin's legacy `parser/` directory, not just the nvim-bundled names. Stale binaries there (from an old install layout) shadowed the real install dir on the runtimepath, satisfied the missing-parser probe, and were invisible to the rev purge, so months-old parsers kept loading against current queries. `nvim/lua/custom/features/treesitter-parsers.lua`
- Nvim: the startup install of missing parsers passes `force = true`. nvim-treesitter counts a language as installed if its query directory merely exists, so a stale query dir made the plain `install()` a silent no-op for exactly the parsers the probe had found broken, retrying every launch without ever installing anything. `nvim/lua/custom/plugins/treesitter.lua`

## [0.2.133] - 2026-07-15

### Changed

- `dotfiles local diff` now also flags uncommitted changes in the local-layer repo, scoped to the managed pairs. `export` auto-commits, so an uncommitted change means a repo file was edited by hand: the repo↔system comparison can report a clean match while such an edit sits unsaved (and a later `export`, treating the system file as the source of truth, would overwrite it), so it was previously invisible. The command now exits non-zero when there is drift or uncommitted state, and returns 0 only when fully clean. `scripts/dotfiles`, `scripts/tests/test-dotfiles-local.sh`
- `set-default-apps.sh` asks about each file type only once. macOS 15+ shows a modal consent dialog on every programmatic handler change, so the step now skips a type when Zed already handles it and records a decline in `.state/declined-default-apps` when the user keeps the existing app, instead of re-prompting on every `dotfiles update`. `scripts/install/set-default-apps.sh`
- tmux Codex instance switcher rebound from prefix+`C` to prefix+`x`. `tmux/tmux.conf.template`, `tmux/tmux-help.template`

### Added

- `.log` files route to Zed. they're governed by the system `com.apple.log` UTI that Console claims, so the UTI is bound directly since the bare extension loses to it. `scripts/install/set-default-apps.sh`

### Fixed

- `svim` resolves `nvim` via `command -v` for `SUDO_EDITOR` instead of passing the bare name. sudoedit resolves `SUDO_EDITOR` against `secure_path`, not the shell's `PATH`, so the bare name wasn't found and sudo silently fell back to its compiled default editor. `zsh/dotfiles.zsh`
- `gpr` uses `xargs -r` so it no-ops instead of erroring when there are no gone branches to prune. `zsh/dotfiles.zsh`

## [0.2.132] - 2026-07-10

### Added

- `dotfiles local edit` opens the private local-layer repo in `$EDITOR`, mirroring `dotfiles edit` for the base repo; resolves the configured repo via `_local_dir_required`, so it errors cleanly with an init/clone hint when none is set. `scripts/dotfiles`, `zsh/functions/_dotfiles`
- `dotfiles export` and `dotfiles import` accept positional selectors to sync a single entry instead of the whole layer (e.g. `dotfiles import zshrc --force`, `dotfiles export launchers/acme`). A selector matches a manifest entry by repo-relative path, path suffix, basename, or system path, or a single file inside the launchers dir; a targeted export scopes its commit to just what it captured, and a single-file launcher selection flows through the ordinary file path so it never triggers the wholesale dir mirror or prune. Unknown selectors error. `scripts/_lib/local-layer.sh` (`_local_select`), `scripts/dotfiles`, `scripts/tests/test-dotfiles-local.sh`

### Changed

- Theme is no longer part of the local-layer sync: `current-theme` is dropped from the manifest and hard-excluded (seeded into the private repo's `.gitignore`), so each machine keeps its own theme instead of a synced pointer showing up as a perpetual `differs` that only `--force` could clear. `scripts/_lib/local-layer.sh`, `scripts/dotfiles`
- Launcher pruning on `import` is decoupled from `--force`: `--force` now overwrites differing files but never deletes orphaned launchers, and a new `--prune` flag gates deletion. A launcher created on one machine (an orphan relative to the shared repo) survives a `--force` import on another. `scripts/dotfiles`, `zsh/functions/_dotfiles`, `scripts/tests/test-dotfiles-local.sh`

## [0.2.131] - 2026-07-10

### Added

- Local-layer sync across personal machines via a private git repo: `dotfiles local init|clone|status|diff` plus top-level `dotfiles export [--push]` and `dotfiles import [--force]`; `local clone` applies the layer immediately after registering. The manifest covers the layered `local.*` overrides, copy-on-install configs, `~/.zshrc`, personal launchers, and the current-theme pointer; secrets, `.state/`, and the preset file are hard-excluded. The repo is referenced only by a machine-local pointer (`~/.config/dotfiles/local-repo`, env override `DOTFILES_LOCAL_DIR`); the public repo never knows about it. `scripts/dotfiles`, `scripts/_lib/local-layer.sh`, `scripts/_lib/cli.sh`
- Installer step 14 imports the local layer when configured, and auto-adopts a repo already cloned to `~/.dotfiles-local`, so "clone dotfiles-local, then install" personalises a fresh machine with zero configuration. Health check gains an informational local-layer row; uninstall reports the repo and pointer as kept user data. `install.sh`, `scripts/install/health-check.sh`, `scripts/install/uninstall.sh`, `docs/INSTALLATION-GUIDE.md`
- Tab completion and cheatsheet rows for the new commands. `zsh/functions/_dotfiles`, `zsh/dotfiles.zsh`
- Behavioural test suite for the sync commands, including a manifest drift guard that fails when an `install_local`/`copy_config` destination in the installer is missing from the sync manifest. `scripts/tests/test-dotfiles-local.sh`, `scripts/tests/test-dotfiles-cli.sh`
- SSH sessions assert `COLORTERM=truecolor` so remote TUIs render 24-bit colour instead of downsampling to the 256 palette; ssh doesn't forward `COLORTERM` and we always drive from a truecolor terminal. `zsh/zprofile`
- zsh-completions installed via Homebrew, with it and the OS systemd vendor completions appended to `fpath` so they only fill gaps carapace and brew don't already cover. `Brewfile`, `zsh/dotfiles.zsh`
- Shared `ClaudeIcon` highlight between which-key and the `claude` code-fence glyph, with the me-speaker glyph pinned on nroff so render-markdown resolves the fence word before mini. `nvim/lua/custom/plugins/mini.lua`, `nvim/lua/custom/plugins/ui.lua`

### Fixed

- Pinned copilot to full-document LSP sync to avoid a `:Cfilter` crash. `nvim/lua/custom/plugins/copilot.lua`
- Claude launcher window keeps its auto-name through job-control resume and refocus: window 3 is left unnamed so `automatic-rename-format` kebab-cases claude's OSC title instead of freezing on a passed `-n`, and `fg`/`%n` resumes resolve to the job's real command in preexec so the title doesn't become "fg". `launchers/dev`, `zsh/dotfiles.zsh`
- Finished cmd-alert rows clear at session scope on teardown: `clear_session_finished` scrubs every window's done rows when a session is destroyed, a transiently-blank window name is recovered from the stable window id, and the clear hook exits 0 so a backgrounded `run-shell` can't leak a non-zero to the status line. `tmux/scripts/_lib/alerts.sh`, `tmux/scripts/alerts/clear.sh`, `tmux/scripts/panes/kill.sh`, `tmux/scripts/windows/kill.sh`, `tmux/scripts/tests/test-cmd-alert-hooks.sh`

## [0.2.130] - 2026-07-08

### Added

- `jiru`, `lazycron` added to the interactive-command exclude list so cmd-alert doesn't fire completion alerts for their TUI sessions. `docs/CMD-ALERTS.md`, `scripts/hooks/cmd-alert-hook.zsh`

### Changed

- New tmux instance windows for `claude` keep `automatic-rename` on (other processes still get it turned off), so the window name tracks the session title via `automatic-rename-format`'s OSC-title branch instead of staying pinned to the launch command. `tmux/scripts/instances/new.sh`

## [0.2.129] - 2026-07-06

### Added

- macOS default-app handlers: `scripts/install/set-default-apps.sh` sets Zed as the default handler for code file types (`md`, `ts`, `tsx`, `json`, `yaml`, `yml`, `toml`, `css`, `js`) via `duti`, wired in as install step 9 (macOS only) and re-run on `dotfiles update`. Zed's LaunchServices record is refreshed first so the binding wins over competing apps (this is why `toml` had been silently staying on another app), and extensions with no stable UTI (`go`, `cs`, `lua`, `env`, `jsx`) are skipped instead of failing with `-50`; Zed already opens `go`/`jsx` via its own bundle. `duti` added to the Brewfile. `scripts/install/set-default-apps.sh`, `install.sh`, `Brewfile`, `docs/INSTALLATION-GUIDE.md`

### Fixed

- Popup transparency and window-title underlines broken by new tmux master defaults: upstream commit `8c55a388` gave popups and menus an opaque theme-grey background and `f59921ce` made the current window title default to underscore. `popup-style`, `popup-border-style`, `menu-style`, `menu-border-style`, and `window-status-current-style` are now pinned to `default` so they inherit the pane background and theme as before. `tmux/tmux.conf.template`
- Claude switcher showed a stale "needs input" for an agent that was already working again: no Claude Code hook fires at the moment a permission prompt is approved, so the needs-input state written by `PermissionRequest` lingered until the next tool call's `PreToolUse` (long thinks made it very visible). Two-part fix: the state hook is now wired for `PostToolUse` on all tools (the approved tool's completion is the first available signal), and the switcher derives the remainder at render time, flipping a stored needs-input back to working when the pane title shows Claude's braille spinner (the reverse of the existing "stuck" derivation). `scripts/hooks/agent-state.sh`, `tmux/scripts/instances/claude.sh`, `docs/AGENT-HOOKS.md`, `tmux/scripts/tests/test-agent-state-hook.sh`, `tmux/scripts/tests/test-list-claude.sh`
- Process list popup (prefix + P) never refreshed on its own, unlike the Claude/Codex/opencode/copilot instance switchers, which all reload every 2s: a process that finished or a new alert while the popup was open stayed invisible until a manual reopen. Added the same `every(2):reload-sync` binding used by those switchers. `tmux/tmux.conf.template`

## [0.2.128] - 2026-07-06

### Added

- Per-pane agent-state layer for the Claude instance switcher: Claude Code hooks (`scripts/hooks/agent-state.sh` + `wrappers/claude-state.sh`) write one state file per tmux pane under `~/.config/tmux-alerts/agent-state/`, and prefix+c renders each instance's state (● working, ◐ needs input, ○ idle, ✗ error) plus, for the states where you're waiting on it (idle/needs-input/error/stuck), how long it's been in that state. "Stuck" is derived at render time: working state older than `AGENT_STUCK_SECS` (default 120s) with no braille spinner left in the pane title. Stale files are swept by SessionEnd, the switcher itself, and the session-closed/renamed cleanup hook. `tmux/scripts/instances/claude.sh`, `tmux/scripts/_lib/alerts.sh`, `tmux/scripts/alerts/cleanup.sh`, `tmux/tmux.conf.template`, `tmux/scripts/tests/test-agent-state-hook.sh`, `docs/AGENT-HOOKS.md`
- Claude switcher layout reworked to the proclist pattern: tab-delimited rows with the jump target hidden (`--with-nth=1`), a 60% preview that drops to a bottom split below 60 columns, and a state legend in the header, so rows have room for state and age. `tmux/tmux.conf.template`, `tmux/scripts/instances/claude.sh`
- Zed: in the project-search results view (`space s g` / `cmd-shift-f`), `n`/`shift-n` step to the next/previous match. Scoped to the results view (`ProjectSearchView > Editor`) so vim's own `n`/`N` search-repeat still works in normal editors. `zed/keymap.json`
- Zed settings (copy-on-install): vim smartcase find and relative-number toggle, signature help after edits and on typing, autoscroll on clicks, current-line highlight, `unnecessary_code_fade`, and the agent-review toolbar. `zed/settings.json`
- `dotfiles diff` and `dotfiles sync` now track `zed/settings.json`, so repo changes to the copy-on-install Zed settings surface to users instead of being silently missed. `scripts/dotfiles`, `scripts/tests/test-dotfiles-cli.sh`

### Fixed

- Claude instance detection: the claude launcher now execs a versioned binary (kernel name e.g. `2.1.201`), so `pgrep -x claude` stopped matching and both the prefix+c listing and its `x` kill binding were silently empty/broken. New `match_process_pids`/`match_child_pid` helpers in `tmux/scripts/_lib/process.sh` also match the argv[0] basename. `tmux/scripts/instances/claude.sh`, `tmux/scripts/instances/kill.sh`

### Changed

- `_ansi` and `_fmt_elapsed` moved from `proclist.sh` into `tmux/scripts/_lib/alerts.sh` so the instance switchers can share them. `tmux/scripts/alerts/proclist.sh`

### Removed

- Redundant per-row alert icon (⚡) in the Claude instance switcher: the state dot already shows idle/needs-input in this Claude-only view, so the alert lookup was dropped. `tmux/scripts/instances/claude.sh`, `tmux/scripts/tests/test-list-claude.sh`

## [0.2.127] - 2026-07-05

### Added

- Zed: `keymap.json` and `tasks.json` are now symlinked from the repo (`zed/`); `settings.json` is copy-on-install since it mixes shareable prefs with per-machine font/theme values and Zed has no include/override mechanism to split them. Verified against upstream source that Zed's own writers (GUI keymap editor, atomic settings save) write through the symlink or its canonicalised target rather than replacing it. `scripts/install/create-symlinks.sh`, `scripts/install/health-check.sh`, `scripts/install/uninstall.sh`, `scripts/tests/test-create-symlinks.sh`, `zed/keymap.json`, `zed/tasks.json`, `zed/settings.json`, `CLAUDE.md`, `docs/INSTALLATION-GUIDE.md`
- `zed` cask to the Brewfile (Editors section), replacing `visual-studio-code`. `Brewfile`
- Copilot: buffers under `~/.ssh` are now blocked by path, since ssh keys/config have no distinguishing filetype to catch with the existing pattern list. `nvim/lua/custom/plugins/copilot.lua`

### Changed

- Copilot: markdown suggestions disabled (`filetypes.markdown` now `false`). `nvim/lua/custom/plugins/copilot.lua`
- Nvim: `<leader>do` now opens `Differ` (working tree) instead of `Differ HEAD` (vs index). `nvim/lua/custom/plugins/differ.lua`

### Fixed

- cmd-alert-hook: the clear-then-run launcher check now reads the fully alias-expanded command (`$2`) instead of the typed alias's own definition, so nested launcher chains (e.g. `config` -> `v` -> `cl && nvim`) are recognised even though the outer alias never mentions `cl`/`clear` itself. `scripts/hooks/cmd-alert-hook.zsh`, `tmux/scripts/tests/test-cmd-alert-hooks.sh`
- tmux claude instance detection: the claude process's own pid is now included in the active-ppid set, since `tmux new-window 'claude ...'` execs claude as the pane process rather than spawning it as a child. `tmux/scripts/instances/claude.sh`

### Removed

- `visual-studio-code` cask from the Brewfile

## [0.2.126] - 2026-07-05

### Added

- Tmux: process list `x` binding now suppresses the alert + finished row for the process it interrupts. It touches a per-pane marker right before sending Ctrl-C; the shell's precmd hook consumes and deletes it on that completion, so only an intentional kill from proclist goes silent, a manually-typed Ctrl-C still gets the usual ⊘ treatment. Orphaned markers (pane died with the command) are pruned after 10s. `scripts/hooks/cmd-alert-hook.zsh`, `tmux/scripts/_lib/alerts.sh`, `tmux/scripts/alerts/proclist-action.sh`, `tmux/scripts/alerts/proclist.sh`, `tmux/scripts/tests/test-cmd-alert-hooks.sh`, `docs/CMD-ALERTS.md`

### Changed

- Nvim: `<leader>dT` (diff by ticket) moves from diffview.nvim to differ.nvim, reusing the same ticket/commit-grep discovery (`features/ticket.lua`). differ's existing revspec grammar (single-rev vs worktree, two-dot range) already covers both shapes the feature needs, so no differ-side change was required. `nvim/lua/custom/plugins/differ.lua`

### Removed

- Nvim: diffview.nvim dropped entirely, its last live keymap (`<leader>dT`) having moved to differ.nvim. Removed its plugin spec, upstream-bug patches, and buffer-local which-key/fold-compat wiring from `pr-review.lua`; deleted `features/diff-edit.lua` (its diffview close-wrapper and octo edit-file branch were only ever reachable through diffview's own `FileType` autocmd, so both were dead once it's gone). Review-context detection, roslyn/sonarlint suppression gates, the gitsigns buffer skip, and the zoom/refresh/which-key/diff-highlight integrations now cover octo (and differ, where applicable) only. `nvim/lua/custom/plugins/pr-review.lua`, `nvim/lua/custom/core/review-context.lua`, `nvim/lua/custom/core/windows.lua`, `nvim/lua/custom/core/refresh.lua`, `nvim/lua/custom/core/diff-highlights.lua`, `nvim/lua/custom/plugins/sonarlint.lua`, `nvim/lua/custom/plugins/dotnet.lua`, `nvim/lua/custom/plugins/gitsigns.lua`, `nvim/lua/custom/plugins/ui.lua`

## [0.2.125] - 2026-07-04

### Added

- Monaspace Neon Nerd Font added to the font set on both platforms: the `font-monaspace-nf` cask on macOS and fetched from githubnext/monaspace's own NF build on Linux via `install-fonts.sh`. `Brewfile`, `scripts/install/install-fonts.sh`
- Ghostty theme catalogue fetched on Linux boxes without Ghostty installed. `dotfiles theme generate` reads Ghostty's bundled theme files as its source of truth, which don't exist on distros that don't package Ghostty (e.g. Debian, Raspberry Pi OS); `install-ghostty-themes.sh` populates `~/.local/share/ghostty/themes` from `mbadolato/iTerm2-Color-Schemes`'s ready-made `ghostty/` directory via a sparse clone, so theme generation works without the Ghostty binary. `scripts/install/install-ghostty-themes.sh`, `scripts/install/install-packages.sh`
- Tmux: poke status segment in status-right (`poke render`) shows pending team pokes, with prefix + b to dismiss them (`poke clear`).

### Changed

- Tmux: the process list popup's running rows sort most recently started first, instead of longest-running first. `tmux/scripts/alerts/proclist.sh`

### Fixed

- Installer: `postgresql@17`'s data cluster is initialized on Linux when Homebrew's own `post_install` locale (`en_US.UTF-8`) doesn't exist on the machine. Outside US locale setups (common on Linux; macOS ships that locale by default) the bottle installs but leaves the cluster uninitialized, so this finishes the job with a UTF-8 locale that's actually present. `scripts/install/install-packages.sh`
- Nvim: treesitter setup reinstalls parsers whose `highlights.scm` is missing from the runtimepath. A stray or legacy parser binary can satisfy the `language.inspect` probe while shipping no query files, which previously skipped the install and left that language unhighlighted; the check is file existence rather than query compilation to keep startup fast. `nvim/lua/custom/plugins/treesitter.lua`
- LazyDocker: `format-logs.awk`'s path is resolved at runtime via `uname` instead of hardcoded to the macOS `Library/Application Support` directory, so Linux's `.config/lazydocker` location works without a manual edit. `lazydocker/config.yml`
- Tmux: the resurrect session list's "modified" timestamp column no longer shows garbled output on Linux. GNU `stat -f` is a _filesystem_-info flag, not BSD's format-string flag, so the previous `stat -f ... || stat -c ...` fallback never triggered -- the BSD call "succeeds" with unrelated filesystem info instead of erroring. Branches explicitly on `uname` instead. `tmux/scripts/resurrect/restore.sh`
- Tmux: duplicating a launcher (`launchers/duplicate.sh`) silently failed on Linux. It used BSD `sed -i ''` syntax, which GNU sed parses as an entirely different (and erroring) invocation; under `set -e` the script died right after copying the file but before printing the new name or updating its `@description` tag. Tmux scripts get their own `sed_inplace` helper (mirroring the installer's), which also now preserves the original file's permissions across its temp-file swap -- `mktemp` defaults to 600, which was silently dropping the executable bit `chmod +x` had just set. `tmux/scripts/_lib/common.sh`, `tmux/scripts/launchers/duplicate.sh`, `scripts/_lib/common.sh`, `scripts/tests/test-linux-compat.sh`
- Tmux: `nav.sh back`/`forward` could resolve to the wrong tmux session's active window when invoked with no attached client and more than one session on the server. The unscoped `tmux display-message -p` query still answers in that case, but arbitrarily picks a session rather than erroring, silently corrupting the navigation history. Now only trusted when `$TMUX` confirms an attached client; otherwise falls straight to the existing all-sessions active-window scan. `tmux/scripts/utils/nav.sh`

## [0.2.124] - 2026-06-30

### Changed

- Nvim: image.nvim no longer renders remote images in markdown (`download_remote_images = false`). Remote badge SVGs (shields.io and the like) render poorly inline and pull in network requests on every markdown open; local screenshots and diagrams still render. `nvim/lua/custom/plugins/image.lua`

### Added

- Nvim: mugshot.nvim plugin spec for a gitlens-style blame card on the current line, triggered with `gb` (`[G]it [B]lame card`), dismissed with `q`/`<Esc>`; in-card gestures open the commit (`o`), copy the sha (`y`), and open the PR (`p`). The author's GitHub avatar renders inline via image.nvim, which is pinned as a hard dependency so the card works in any filetype (image.nvim itself only loads on markdown). Distinct from fugitive's `<leader>Gb` and gitsigns inline blame, which both stay. `nvim/lua/custom/plugins/mugshot.lua`, `nvim/cheatsheet.txt`
- ImageMagick: macOS font map symlinked to `~/.config/ImageMagick/type.xml`. Homebrew's imagemagick ships empty `type-*.xml` stubs whose glyph paths resolve to nothing, leaving the type cache with zero usable fonts; any text-bearing SVG (image.nvim rendering a shields.io badge in a markdown buffer) then fails `identify` with "unable to read font", which image.nvim surfaces as a Lua error. The map points a few always-present macOS system fonts (Helvetica, Arial, Courier New) at the cache. Symlinked into a path imagemagick already searches so `brew upgrade` never wipes it; installed on macOS only, since Linux imagemagick has a working fontconfig cache that this would clobber. `imagemagick/type.xml`, `scripts/install/create-symlinks.sh`

## [0.2.123] - 2026-06-30

### Added

- aerc: terminal email client wired into the dotfiles. `aerc.conf` (dracula styleset, threading, HTML rendered by w3m and piped into `less` for vim-style scrolling) and `binds.conf` are symlinked; `accounts.conf` is user-owned from `accounts.conf.template` with credentials pulled from the macOS keychain via `*-cred-cmd`, so no secrets land in the repo. The `aerc` shell alias passes `-C`/`-A`/`-B` so aerc reads `~/.config/aerc` instead of its macOS-default `~/Library/Preferences/aerc`. Custom message-list binds: `fu`/`fr`/`ff`/`fa` filter unread/read/flagged/all and `tu`/`tr` toggle the seen flag. `aerc/`, `scripts/install/create-symlinks.sh`, `zsh/dotfiles.zsh`, `Brewfile`
- Tmux: fzf switcher previews now refresh live and anchor to the bottom. Previews re-render on a 0.5s timer (`every(0.5):refresh-preview`) so a previewed pane keeps updating while the cursor sits on it, not only when you move off and back onto the row. A new `preview-pane.sh` helper replaces the inline `capture-pane`: it strips the trailing blank rows `capture-pane` emits (one line per pane row) and tails the result to the preview window height (`$FZF_PREVIEW_LINES`), so fzf's top-anchoring no longer clips the most recent rows (statusline / prompt) on full panes, while idle panes still render from the top with no blank padding. Applies to the process list (prefix + Shift+P), session (prefix + s), window (prefix + f), and instance switchers (claude/codex/opencode/copilot/nvim). `tmux/scripts/utils/preview-pane.sh`, `tmux/tmux.conf.template`
- Shell: `freeze` wrapper renders code or terminal output to an image with a forced monospace font. freeze's built-in default points at an uninstalled family and silently falls back to a proportional sans, so the wrapper injects `--font.family` (default `JetBrainsMono Nerd Font Mono`). `-F` opens an fzf picker over installed monospace families and persists the choice in `$FREEZE_FONT` for the session; an explicit `--font.family`/`--font.file` always wins. A `_freeze` completion delegates to carapace (with the synthetic `-F` hidden) and adds file completion for the positional. Installed from the new `charmbracelet/tap`. `Brewfile`, `zsh/dotfiles.zsh`
- Nvim: differ.nvim panel toggle on `<leader>dd` (`Differ panel`); `<leader>do` now diffs against `HEAD` explicitly. A `BufWinEnter` hook re-pins `<Space>`/`]`/`[` to which-key on `differ://` buffers, mirroring the diffview workaround: which-key's auto-trigger suspends on `ModeChanged`/`BufNew` and each `wk.add` drops triggers globally, a gap a `.cs` diff (roslyn open churn) reliably hits. `nvim/lua/custom/plugins/differ.lua`, `nvim/cheatsheet.txt`
- Nvim: image.nvim renders images inline in markdown buffers via the kitty graphics protocol (ghostty + tmux, the existing `allow-passthrough on` covers the tmux requirement). Uses the `magick_cli` processor so it needs only the existing imagemagick install, not the magick luarock (`build = false` skips the rock build); loads on the markdown filetype and caps images at 50% window height. `nvim/lua/custom/plugins/image.lua`

### Changed

- Tmux: copy-mode `r` clears the current selection and enables live-follow of the pane (`clear-selection` then `refresh-on`). Recent tmux changed the default `r` from a one-shot `refresh-from-pane` to a stateful `refresh-toggle`; `refresh-on` is idempotent, so every press refreshes rather than toggling follow off on alternate presses. `tmux/tmux.conf.template`
- Tmux: the process list popup (prefix + Shift+P) preview pane is narrower (`right,55%`, falling back to a bottom split under 60 columns) so the command column has more room. `tmux/tmux.conf.template`
- Nvim: mason installs `golangci-lint-langserver` instead of the bare `golangci-lint` binary, so Go diagnostics arrive over LSP. `nvim/lua/custom/plugins/lsp.lua`
- Nvim: clipboard register rework. Only yanks reach the system clipboard now: a `TextYankPost` hook mirrors `y` to `"+` while `clipboard=unnamedplus` is dropped, so `d`/`c`/`x` no longer overwrite it. `<leader>v`/`<leader>V` paste the last yank (`"0p`/`"0P`) regardless of intervening deletes, replacing the old `dd`=black-hole / `dy`=cut mappings. `nvim/lua/custom/core/autocmds.lua`, `nvim/lua/custom/core/keymaps.lua`, `nvim/lua/custom/core/options.lua`, `nvim/cheatsheet.txt`
- Nvim: gopls `workspace/symbol` is scoped to the workspace (`symbolScope = 'workspace'`), so symbol search no longer surfaces dependencies under `~/go/pkg/mod`. `nvim/lua/custom/plugins/lsp.lua`

### Fixed

- Tmux: command exit alerts are now keyed on `window_id` rather than the window name. The alerts file gains a sixth field (`session:window:exit:window_id:code:label`) and dismissal/GC match on the id, which is stable for the server's life; the stored name drifts under automatic-rename, so a window that auto-renamed after a command finished could strand its exit indicator or have it wrongly garbage-collected. `tmux/scripts/_lib/alerts.sh`, `tmux/scripts/alerts/pick.sh`, `tmux/scripts/alerts/proclist-action.sh`, `tmux/scripts/alerts/show.sh`, `tmux/scripts/tests/test-cmd-alert-hooks.sh`, `tmux/scripts/tests/test-rename-session.sh`, `tmux/scripts/tests/test-session-kill-logic.sh`
- Nvim: telescope pickers launched from a quickfix/loclist window open the selection in a real editing window instead of replacing the list. `get_selection_window` prefers the previous window, then the first normal window in the tabpage, and splits a new one above the list when the qf window is the only one. `o` in qf buffers is also mapped to `<CR>` (jump to entry) since the buffer is unmodifiable. `nvim/lua/custom/plugins/telescope.lua`, `nvim/lua/custom/features/lists.lua`
- Nvim: `<leader>wh`/`<leader>wl` resized the vertical split in the wrong direction; they now shrink/grow to match the `h`/`l` mnemonic. `nvim/lua/custom/core/windows.lua`
- Nvim: astro files behave around treesitter injections, with an `after/indent/astro.lua` override papering over an upstream astro.vim `indentkeys` issue. `nvim/after/indent/astro.lua`, `nvim/lua/custom/plugins/lsp.lua`
- Shell: `GIT_OPTIONAL_LOCKS=0` stops read-only git commands (status, diff) taking the `index.lock` just to write back a refreshed index, so frequent background status polls (an editor's git integration, or several Claude Code sessions on one worktree) no longer collide with an in-flight commit and fail it with `Unable to create '.../index.lock': File exists`. Real index writes (add, commit) still lock normally. `zsh/dotfiles.zsh`
- Nvim: obsidian frontmatter keeps its key order on save (`sort = false`); the builtin was alphabetising keys on every write. `nvim/lua/custom/plugins/obsidian.lua`
- Nvim: the statusline shows the real source language while diffing in differ.nvim. differ diff buffers carry a private `differdiff` filetype (so foreign `FileType` consumers don't attach to a throwaway `differ://` buffer), which left the statusline fileinfo section blank; it now reads the stashed `b:differ_filetype` so the language and its icon still render. `nvim/lua/custom/features/statusline.lua`
- Tmux: command exit alerts and their process-list "done" row now agree on the window. The finished-history write resolved the window with a bare `tmux display-message -p`, which from an interactive shell reports the _client's active window_, not the pane the command ran in; since an exit alert only fires once you have switched away from the origin pane, the completion got filed under whatever window you were viewing (and dropped when that window was later cleared), so a finished command showed in the status-right exit alert but was missing from the process list. The write now targets the captured origin pane, matching how the alert itself is set. `scripts/hooks/cmd-alert-hook.zsh`
- Tmux: status-right exit indicators no longer outlive their process-list "done" row. The finished-history file ages out at an hour, but the alerts file that drives the status-right and window-status exit icons had no TTL of its own (an exit line clears only when its window is selected or its session dies), so a window you never revisited kept its indicator long after the process-list row had gone. The process list now clears a window's exit indicator when its finished rows are dropped (aged out, or evicted to bound the file), keyed on the stable `window_id` and skipped when a retained row still justifies it. The finished file also gains a hard retention cap (200 newest within the hour) so it can't grow unbounded under heavy churn. `tmux/scripts/alerts/proclist.sh`
- Tmux: `show.sh` no longer assigns `ALERTS_FILE` before sourcing `alerts.sh`, which declares that name readonly on load; the pre-source bail-out reads a local path variable instead, removing a latent readonly-reassignment error if the source order were ever reversed. `tmux/scripts/alerts/show.sh`
- Tmux: the library test suite runs to completion on tmux 3.x+. The end-to-end colon-in-window-name checks created a window whose name contained a literal `:`, which newer tmux rejects via `new-window`/`rename-window` and sanitises to `_` under automatic-rename; the unguarded failure aborted the whole suite under `set -e` (0 failures reported but a non-zero exit). Those checks now skip gracefully when tmux won't accept a colon-named window, leaving the encode/decode round-trip coverage intact. `tmux/scripts/_lib/test-tmux-libs.sh`

## [0.2.122] - 2026-06-25

### Added

- Tmux: process list switcher (prefix + Shift+P) merging running and finished commands into one fzf picker. Running commands (tests, builds, servers) show as live ● rows with elapsed time from a new per-pane registry the zsh cmd-alert hook writes during execution; finished commands show ✓/✗/⊘ rows from a new finished-history file recorded on every tracked completion (so a command you watched finish in place still appears, unlike the switch-away-gated status-bar alerts), keeping the last 20 within the hour. Signal deaths (exit > 128, e.g. Ctrl-C) render as a neutral ⊘ "stopped" rather than a red ✗ failure. Jump to any entry, or `x` to interrupt a running process / dismiss a finished one; dismissing a finished row also clears that window's exit indicator from the status-right and window-status, and the completion bell now rings at the attached client terminal rather than the origin pane so a dismissed alert leaves no lingering window highlight. `tmux/scripts/alerts/proclist.sh`, `tmux/scripts/alerts/proclist-action.sh`, `tmux/scripts/_lib/alerts.sh`, `scripts/hooks/cmd-alert-hook.zsh`, `tmux/tmux.conf.template`
- Tmux: process list rerun. `r` stages a finished command back onto its origin window's prompt (jumps you there with the command typed, no Enter, ready to edit), `R` stages and runs it straight away. The command is stored as typed in a new finished-history field, so `$VAR` references stay references (re-expanded by the shell on rerun, not captured as values; the same exposure as `~/.zsh_history`), and it is read back by key (epoch+window_id) so the raw text never crosses the fzf/shell boundary. Finished "done" rows also clear on view now, the same way exit and agent alerts dismiss when you switch to their window. `tmux/scripts/alerts/proclist-rerun.sh`, `tmux/scripts/alerts/proclist.sh`, `tmux/scripts/_lib/alerts.sh`, `scripts/hooks/cmd-alert-hook.zsh`, `tmux/tmux.conf.template`
- Nvim: `<leader>mr` toggles render-markdown's inline rendering for the current buffer (markdown only). `nvim/lua/custom/plugins/markdown-ui.lua`

### Changed

- Tmux/zsh: command exit alerts now match the exclude list against the alias-expanded command as well as what you typed, so short git aliases (`gfp` -> `git fetch --prune`) are covered by the `git` entry; added `fg`/`bg` to the defaults so resuming a suspended job no longer registers as a process. Aliases defined as a clear-then-run (`cl && X`) are recognised as interactive launchers from zsh's alias map and excluded automatically, so agents and TUIs (`claude`, `ralph`, `gemini`, `lg`, ...) stay out of the process list with no per-launcher list to maintain. `scripts/hooks/cmd-alert-hook.zsh`
- Nvim: differ.nvim dev mode is now guarded by a real local checkout. The dev toggle only swaps lazy to `~/code/differ.nvim` when its entry module is present, so the toggle can stay enabled in shared dotfiles: machines without the checkout (or with an empty/half-cloned one) fall back to the installed release instead of pointing lazy at a dir with no modules. `nvim/lua/custom/plugins/differ.lua`
- Shell: shebang normalisation. Executable scripts use `#!/usr/bin/env bash`, while sourced data files (theme files, `theme-defaults.sh`) drop the `#!/bin/bash` shebang for a `# shellcheck shell=bash` directive since they are sourced, not executed; the theme generator emits the directive and the validation test now fails any theme file that carries a shebang. `scripts/_lib/generate-theme.lua`, `scripts/tests/test-theme-validation.sh`, `themes/*.theme`, `themes/theme-defaults.sh`, `scripts/fzf-theme.sh`, `scripts/migrations/*.sh`, `tmux/scripts/themes/reload-*.sh`, `tmux/scripts/windows/move.sh`

### Fixed

- Tmux/zsh: command exit alerts now fire when you switch to a different **session** (not just another window) before a command finishes. The completion guard compared the origin pane against `display-message`'s pane, which run from a background pane resolves to the origin session's active pane, so a session switch looked like "still here" and suppressed the alert; it now checks whether any attached client is actually viewing the origin pane via `list-clients`. `scripts/hooks/cmd-alert-hook.zsh`
- Nvim: qf/loclist buffers are unlisted while open, so they no longer surface in telescope's buffers picker or mini.bracketed's `]b`/`[b` (both filter on `buflisted`). `nvim/lua/custom/features/lists.lua`
- Tmux: new-launcher flow expands `~` and `$HOME` when checking whether the target directory exists, defaults the project root from `PROJECT_DIRS` rather than a hardcoded `~/src`, and strips a trailing pane index (`dev.1`) when matching split-window targets so hand-written launchers still load with their split flags. `tmux/scripts/launchers/new.sh`

## [0.2.121] - 2026-06-24

### Added

- Nvim: Go editing helpers. `<leader>la`/`<leader>lc` add json / clear struct tags via gomodifytags, `<leader>le` generates an `if err != nil` block via iferr, with `:GoAddTags`/`:GoRmTags`/`:GoIfErr` commands; both tools are Mason-managed. `nvim/lua/custom/features/go.lua`
- Zsh: `graduate`/`relegate` (aliases `promote`/`demote`) move a project between `~/playground` and `~/code`, relocating its Claude Code history and memories, repointing gh-dash paths, and cd-ing into the new home. Tab-completion lists the source-root projects. `zsh/dotfiles.zsh`
- CI/Make: zsh syntax linting (`zsh -n`) over `zsh/*.zsh`, templates, and shell hooks, wired into `make lint` (`lint-zsh`) and a new CI step. `.github/workflows/ci.yml`, `Makefile`
- Nvim: differ.nvim local-dev toggle (`DIFFER_DEV`) to run the plugin from a `~/code/differ.nvim` checkout instead of the installed release. `nvim/lua/custom/plugins/differ.lua`

### Changed

- Nvim: format-on-save honours `vim.g.disable_autoformat` / `vim.b.disable_autoformat`, so differ's merge tool can suppress formatting over conflict markers. `nvim/lua/custom/plugins/lsp.lua`
- Docs: cheatsheet diff/PR sections rewritten for differ.nvim keymaps; README and installation guide describe differ.nvim as the diff/PR engine. `nvim/cheatsheet.txt`, `README.md`, `docs/INSTALLATION-GUIDE.md`
- Tooling: `scripts/migrations/0.2.121-rename-dotfiles-remote.sh` repoints the dotfiles `origin` from the old GitHub account to `undont`, completing the 0.2.120 rename so clones stop relying on GitHub's redirect.

### Fixed

- Nvim: astro `<script>` blocks no longer double-inject (javascript over typescript); a `query.set` override forces typescript-only injection. `nvim/queries/astro/injections.scm`, `nvim/lua/custom/plugins/treesitter.lua`
- Tmux: alert navigation resolves the target window by id, so window names containing dots or colons no longer misparse against tmux's `session:window.pane` syntax. `tmux/scripts/alerts/pick.sh`

## [0.2.120] - 2026-06-22

### Changed

- Renamed the personal GitHub account from `seanhalberthal` to `undont`. Updated the Homebrew tap and the `supplyscan`/`seeql`/`lazycron`/`jiru` formula prefixes (`Brewfile`), badge/clone URLs and personal-tool links (`README.md`), the `differ.nvim` and `music.nvim` plugin owners, the `gh-bench` extension install (`scripts/install/install-packages.sh`), and the `opencode-tmux-alert` link (`docs/AGENT-HOOKS.md`). GitHub redirects the old paths for a while, so existing clones keep working. Optionally point your clone at the new owner: `git -C ~/dotfiles remote set-url origin https://github.com/undont/dotfiles.git`. `scripts/migrations/0.2.120-rename-brew-tap.sh` drops the old tap so `brew bundle` reinstalls the formulae from the new tap with no gap.

## [0.2.119] - 2026-06-22

### Changed

- Ghostty: reverted `super+backspace` back to `text:\x15`. The zsh `backward-kill-line` bindkey and nvim `<C-BS>` mapping are unchanged. `ghostty/config.template`

## [0.2.118] - 2026-06-22

### Added

- Nvim: differ.nvim drives local diffs, file history, staging, PR review, and merge conflicts through one renderer. It owns the `<leader>d*` diff launchers and the `<leader>p*` PR launchers, with in-diff thread/comment gestures (`ga` comment, `gp` reply, `gr` resolve, `gx` delete, `gc` collapse, `]t`/`[t` thread nav). The build hook compiles its Go sidecar (`make go-build`) on install/update; local diffs work without it. `nvim/lua/custom/plugins/differ.lua`
- Zsh: Ctrl+J / Ctrl+K act as down/up in history, line nav, and the tab-completion menu (Return still submits via `^M`). Scoped to zsh so nvim's own `C-j`/`C-k` are untouched. `zsh/dotfiles.zsh`
- Nvim/Zsh: Cmd+Backspace deletes to the start of the line inside tmux when Ghostty emits ctrl+backspace in csi-u form (`\e[127;5u`), since tmux has no super modifier. zsh binds that sequence to `backward-kill-line` and nvim maps `<C-BS>` to `<C-u>`, keeping the existing direct `<D-BS>` binding for the no-tmux case. `nvim/lua/custom/core/macos-nav.lua`, `zsh/dotfiles.zsh`
- Fzf: Ctrl+J / Ctrl+K move the selection down/up in the picker, alongside the existing `ctrl-d`/`ctrl-u` half-page binds. `scripts/fzf-theme.sh`
- Nvim: `<leader>xS` runs an all-LSP diagnostics scan over every project file (`git ls-files -co`), the diagnostic-scan analogue of sonar's `<leader>lS`. A confirm prompt guards runs above 500 files since roslyn and friends are heavy. Also exposed as `:ProjectScan`. `nvim/lua/custom/features/diag-scan.lua`
- Nvim: `<leader>lb` runs a SonarLint scan over every file changed vs `merge-base(main)`, the sonar analogue of `<leader>xb`. Shares branch-file discovery with the all-LSP scan via `features/ticket.lua`. `nvim/lua/custom/plugins/sonarlint.lua`
- Nvim: `:Cfilter`/`:Lfilter` now preserve the source list's `Kind:` title prefix, so a filtered diagnostics list keeps auto-clearing resolved entries (stock cfilter.vim retitles to `:Cfilter /pat/`, dropping the prefix `build.lua` keys on). `nvim/lua/custom/features/lists.lua`

### Changed

- Nvim: the branch diagnostics scan moves from `<leader>xt` to `<leader>xb` (`:BranchScan` unchanged), aligning the letter with the new sonar `<leader>lb` and freeing `t`. `<leader>xT` still scans ticket commits. `nvim/lua/custom/features/diag-scan.lua`, `nvim/cheatsheet.txt`
- Nvim: the library/dependency path filter (stdlib, `node_modules`, `vendor`, etc.) moved into the shared `scan-runner` as `in_library`, so the git-scoped batch scans drop the same vendored and out-of-root diagnostics as the live `<leader>xx` list. `nvim/lua/custom/features/scan-runner.lua`
- Nvim: PR review and local diffs move from diffview/octo to differ.nvim. diffview stays installed and keeps `<leader>dT` (diff by ticket); octo stays installed as a fallback for PR search and issues, reachable via `:Octo`. `nvim/lua/custom/plugins/pr-review.lua`
- Nvim: the make build-target detector matches `check` anywhere in a target name, so bare `check` and prefixed variants (`typecheck`, `lint-check`) both register as build targets. `nvim/lua/custom/features/build.lua`
- Zsh: `vconf` renamed to `nconf` (open the nvim local config). `zsh/dotfiles.zsh`
- Fzf: the theme cache now invalidates when `scripts/fzf-theme.sh` itself changes, so bind and colour edits propagate without a manual cache clear. `scripts/fzf-theme.sh`

### Fixed

- Nvim: library and dependency diagnostics no longer land in the live diagnostics list. Files outside the project root (stdlib, global module caches) or under an in-tree vendored directory (`node_modules`, `vendor`, `site-packages`, `dist-packages`, `pkg/mod`, `.venv`, `.cargo`) are filtered out, so an LSP attaching after a go-to-definition jump no longer parks read-only notes in the list. `nvim/lua/custom/features/lists.lua`

## [0.2.117] - 2026-06-16

### Fixed

- Tmux: the launcher picker (prefix + p) directory list no longer comes up empty for users who set `DEV_ROOT`/`PROJECTS_ROOT`/`PROJECT_DIRS` in `~/.zshrc`. The picker runs in a `display-popup`, which inherits tmux's session environment, not the interactive shell's; those vars were never in `update-environment`, so a popup only saw them if the server happened to be started from a shell that already had them exported. They are now in `update-environment`, so each client attach imports them into the session environment the popup inherits (existing servers need one detach + reattach to pick them up). `tmux/tmux.conf.template`
- Tmux: when the launcher directory list is empty, the picker now shows why ("No project directories found" plus the current `PROJECT_DIRS` value and a hint to set it in `~/.zshrc`, then detach + reattach) instead of a blank list. `tmux/scripts/launchers/run.sh`
- Nvim: with `cmdheight=0`, the height-resize maps (`<leader>wj`/`wk`/`wJ`/`wK`) no longer re-expose the last typed `:` command. A height resize on a window with no vertical neighbour has nowhere to put the freed rows, so nvim grew the command line; the maps now run the resize only when a window sits directly above or below. `nvim/lua/custom/core/windows.lua`
- Nvim: `<leader>Hu` (undo stage hunk) now calls `gitsigns.stage_hunk`, which toggles staging on the hunk under the cursor, replacing the deprecated `undo_stage_hunk`. `nvim/lua/custom/plugins/gitsigns.lua`

## [0.2.116] - 2026-06-13

### Added

- Nvim: `<leader>xt` scans every file changed on the branch vs `merge-base(main, HEAD)` (committed branch work plus uncommitted/untracked changes) and dumps their diagnostics into the quickfix list, the diagnostic-scan analogue of `<leader>dt`'s diffview. Completes the lower/upper scan pair alongside `<leader>xT` (ticket commits); file discovery shares `core/ticket.lua` (`branch_files()`), and the scan reuses the batched `scan_files` driver, so peak roslyn memory stays bounded. Also exposed as `:BranchScan`. `nvim/lua/custom/core/ticket.lua`, `nvim/lua/custom/core/lists.lua`, `nvim/cheatsheet.txt`
- Ghostty: commented `font-feature` example for Monaspace in `local.template`. Monaspace hides its coding ligatures behind stylistic sets (`ss01`-`ss09`) rather than plain `liga`, so the example documents which sets to enable and warns that font-features are global (don't enable them on JetBrains Mono). `ghostty/local.template`
- Zsh: `vconf`/`gconf`/`tconf` aliases open the nvim/ghostty/tmux layered local-override files (`~/.config/nvim/local.lua`, `~/.config/ghostty/local`, `~/.config/tmux/local.conf`) directly, alongside the existing `config`/`zshrc`/`secrets` openers. `zsh/dotfiles.zsh`

### Changed

- Nvim: oil.nvim is now the default file explorer. It loads at startup (`lazy = false`) so its directory-hijack autocmd is registered before a directory buffer (e.g. `nvim ~/.config`) is processed, and neo-tree no longer hijacks netrw (`hijack_netrw_behavior = 'disabled'`). Neo-tree stays available on `|`. `nvim/lua/custom/plugins/navigation.lua`, `nvim/lua/kickstart/plugins/neo-tree.lua`
- Nvim: cheatsheet keybinding notation normalised to nvim form (`<C-d>`, `<M-Down>`, `<Tab>`) instead of the mixed `Ctrl+d` / `Alt+Down` style. `nvim/cheatsheet.txt`

### Fixed

- Nvim: oil entry IDs (the `/006 ` line prefix) no longer leak on a fresh open. Oil's `set_win_options` reads `nvim_get_current_win()` from inside an `nvim_buf_call`, which switches the buffer context but not the window, so on a fresh open it can apply `conceallevel` to the wrong window; the safety-net autocmd ran synchronously on `BufWinEnter`/`WinEnter` and hit the same race. It now defers one tick (past oil's render and competing FileType handlers) and sets `conceallevel`/`concealcursor` on the resolved oil window explicitly instead of the current window. `nvim/lua/custom/plugins/navigation.lua`
- Nvim: the statusline branch and diff counts no longer stay stale after git operations done inside the lazygit float. lazygit runs in an in-process terminal that fires no shell event for gitsigns to hook, so `vim.g.lazygit_on_exit_callback` now re-runs `gitsigns.refresh()` on exit to re-diff every buffer. `nvim/lua/custom/plugins/git.lua`
- Zsh: `_dotfiles` autoload no longer fails outside tmux. `DOTFILES_ROOT` is now exported before the `fpath` entry that depends on it; previously it was set later (for fzf-theme) and only appeared to work inside tmux because the export was inherited from the parent shell. `zsh/dotfiles.zsh`

## [0.2.115] - 2026-06-11

### Added

- Tmux: `set -g allow-passthrough on` so TUIs like yazi can talk to the outer terminal directly. Without it yazi's image preview and startup escape sequences leak through tmux instead of reaching the terminal; passthrough lets the `\ePtmux;...` escape sequence reach the outer terminal unmodified. `tmux/tmux.conf.template`

## [0.2.114] - 2026-06-11

### Added

- Tmux: the battery/cpu/ram status-right segment is now rendered by a cached wrapper `tmux/scripts/utils/sysinfo.sh` (TTL ~5s) instead of being inlined. With `status-interval 1` the clock ticks every second, but the stock tmux-battery/tmux-cpu plugin scripts (which exec ~22 tmux option reads each) only run once per TTL; the segment is served from a cache in between, cutting hundreds of process spawns per minute. Plugins stay unpatched upstream clones; icons and colour pass via `@sysinfo_*` options to avoid tmux format-expanding `#rrggbb` colour arguments. `tmux/scripts/utils/sysinfo.sh`, `tmux/tmux.conf.template`
- CLI: `dotfiles version` and `dotfiles status` now show `Released:` (commit time of the matching `vX.Y.Z` tag, or the dated CHANGELOG heading for untagged `-dev` builds) and `Updated:` (timestamp of the last successful install/update apply). `install.sh` stamps the apply time to `~/.config/dotfiles/.state/last-update` on completion. `scripts/dotfiles`, `scripts/_lib/cli.sh`, `install.sh`
- Nvim: oil gains `gi` (select/enter) and `go` (parent directory) as alternates to `<CR>`/`<BS>`. `nvim/lua/custom/plugins/navigation.lua`

### Changed

- Ghostty: `ghostty/local.template` now ships a `font-family = ""` reset followed by the default `JetBrainsMono Nerd Font Mono`, so changing the single font line in `~/.config/ghostty/local` takes effect. Ghostty chains repeated `font-family` values into a fallback list (first entry = primary) rather than last-value-wins, so a bare `font-family = MyFont` in the local override was landing as a fallback behind the base config's font, not replacing it. The misleading "last-value-wins" and "reload with prefix + r" comments in the template are corrected (Ghostty config reloads with `Cmd+Shift+,`, not a tmux reload). `ghostty/local.template`
- Tmux: `dotfiles-status.sh` reads its result cache with bash builtins only (no `date`/`stat`/`cat` forks) on the hot path, storing the epoch on line 1 and the payload on line 2; `alerts/show.sh` bails on an empty/missing alerts file before spawning tmux or sourcing libs. `tmux/scripts/utils/dotfiles-status.sh`, `tmux/scripts/alerts/show.sh`
- Install: `brew bundle check` output is discarded (exit code only) so the alarming "can't satisfy your Brewfile's dependencies" summary no longer prints on an out-of-date machine, where it just means the install below will run. `scripts/install/install-packages.sh`

### Fixed

- Zsh: `Ctrl+-` now triggers `redo` (mirroring `Ctrl+Shift+-` → undo) and `Ctrl+=` is swallowed cleanly. With `extended-keys-format csi-u` these combos arrive as CSI-u sequences; binding the actual csi-u form makes ZLE consume the whole sequence instead of leaking the tail (e.g. `;5u`) as literal text. The legacy modifyOtherKeys form is kept as a fallback. `zsh/dotfiles.zsh`
- Ghostty: migration `0.2.114-ghostty-font-family-reset.sh` patches existing `~/.config/ghostty/local` files (copy-on-install, never overwritten) by inserting the `font-family = ""` reset ahead of an existing font-family override so the chosen font becomes primary. Idempotent and a no-op when no override is set or a reset already exists. `scripts/migrations/0.2.114-ghostty-font-family-reset.sh`

## [0.2.113] - 2026-06-10

### Added

- Nvim: oil conceal autocmd re-asserts `conceallevel=3`/`concealcursor=nvic` on `BufWinEnter`/`WinEnter` for `oil://` buffers, so entry IDs stay hidden when an oil buffer is displayed in a split or session-restored window that never ran oil's own set_win_options. `nvim/lua/custom/plugins/navigation.lua`

### Changed

- Nvim: copilot.lua switches to the standalone binary language server (`server = { type = 'binary' }`). The Node server requires `node` ≥ 22 on PATH at Neovim launch; on machines where nvim starts outside an fnm/nvm shell (GUI, launcher, bare login) that silently produces zero completions. The binary auto-downloads from GitHub releases and has no Node dependency. `nvim/lua/custom/plugins/copilot.lua`
- Nvim: codecompanion copilot adapter pre-seeds the `Iv1.*` (copilot.vim) oauth token on startup. `~/.config/github-copilot/apps.json` can hold several `github.com:*` entries (gh CLI, Copilot CLI, VS Code); the upstream adapter returns whichever `pairs()` yields first, often a stale entry whose token exchange 401s and produces an empty bearer, triggering a 400 "Authorization header is badly formatted" on every chat. `nvim/lua/custom/plugins/codecompanion.lua`
- Nvim: `<leader>dT` (diff branch total) switched from three-dot to single-rev `DiffviewOpen` form. The two-dot `base...HEAD` form diffed merge-base against HEAD only; the single-rev form includes uncommitted and unstaged working-tree changes, matching what the tooltip describes. `nvim/lua/custom/plugins/pr-review.lua`
- Tmux/fzf pickers: `ctrl-k` rebound from `kill-line` to `up` (move up the list); `ctrl-l` added as `clear-query`. Applies to all tmux popup pickers: sessions, windows, AI instances, alerts, launchers, themes, and the URL picker. `tmux/tmux.conf.template`, `tmux/scripts/**`
- Ghostty: default font size bumped from 13 to 18 in the template. `ghostty/config.template`

### Fixed

- Docs: added troubleshooting entries for copilot binary server (no inline suggestions when `node` is absent from the launch environment) and codecompanion "Authorization header is badly formatted" (multi-entry apps.json token selection). `docs/TROUBLESHOOTING.md`

## [0.2.112] - 2026-06-08

### Added

- Zsh: `launchers` alias opens `~/.config/dotfiles/launchers` in nvim. `zsh/dotfiles.zsh`

### Changed

- Nvim: diagnostic scans (`<leader>xm`/`<leader>xT`) now hidden-load files in bounded batches (12 at a time) instead of opening the whole changeset at once. Roslyn's analyzer scope is `openFiles` and on Sonar-adopted branches every compilation hosts the full SonarAnalyzer.CSharp ruleset, so a 100-file diff loaded in one go drove the language server to ~4GB. Each batch is loaded, snapshotted, then its created buffers are torn down (the `didClose` drops them from roslyn's open-doc set) before the next batch loads, so peak open-file count and analyzer memory stay bounded regardless of diff size; the solution stays loaded across batches. `scan_runner.start` gained an `on_complete` mode that hands a batch's items back for merging into one quickfix. `nvim/lua/custom/core/lists.lua`, `nvim/lua/custom/core/scan_runner.lua`
- Nvim: roslyn now runs under workstation GC (`DOTNET_gcServer=0` via `cmd_env`). Its `runtimeconfig.json` pins server GC, which allocates roughly one GC heap per core — a heavy idle memory and thread footprint on many-core machines. The server targets net10.0 and on .NET 9+ environment variables override `runtimeconfig` settings, so the env var forces fewer heaps and lower memory at a modest background-analysis throughput cost. Scoped to the roslyn process only, so easy-dotnet's builds/tests/BuildHost are unaffected. `nvim/lua/custom/plugins/dotnet.lua`
- Nvim: which-key hides the macOS-style navigation keymaps (`<M-CR>`, `<M-BS>`, `<D-BS>`, `<M-Right>`/`<M-Left>`, `<M-f>`/`<M-b>`, `<Home>`/`<End>`) so they stay out of the popup. `nvim/lua/custom/plugins/ui.lua`

### Fixed

- Nvim: roslyn semantic colours no longer sit stale after a buffer's analysis settles. The existing project-wide progress-`end` token refresh can fire before a given buffer's tokens are ready (the race tightened under workstation GC), so a per-buffer `DiagnosticChanged` refresh was added — debounced, last-scheduled-wins, gated to visible roslyn `.cs` buffers so a 100-file scan doesn't pile refreshes onto hidden buffers. `nvim/lua/custom/plugins/dotnet.lua`
- Nvim: the diagnostic float is now closed deterministically. `open_float`'s own `close_events` miss window/buffer switches and can orphan the float when a new `CursorHold` re-opens before the one-shot close fires, so the window handle is tracked and closed explicitly on `CursorMoved`/`CursorMovedI`/`InsertEnter`/`BufLeave`/`WinLeave`. `nvim/lua/custom/core/autocmds.lua`
- Nvim: formatting (`<leader>f` and format-on-save) now skips non-file buffers. Diffview/fugitive views carry a `scheme://` name or non-empty `buftype`; formatting them is meaningless and crashed csharpier, which tried to resolve a config dir from the bogus URI path. `nvim/lua/custom/plugins/lsp.lua`

## [0.2.111] - 2026-06-05

### Added

- Nvim: `<leader>lT` runs a sonar scan scoped to ticket-matching commits — the third sonar scan flavour alongside `<leader>lm` (changed/untracked files, the sonar-only analogue of `<leader>xm`) and `<leader>lS` (whole project). Commit discovery is identical to `<leader>dT` / `<leader>xT` (merge-base with main, ticket default from the branch name, `--fixed-strings` grep in `base..HEAD`, per-commit `diff-tree` file union, modified/untracked files joining only when the ticket is the branch tip), with the file list filtered to sonarlint-scannable extensions. `nvim/lua/custom/plugins/sonarlint.lua`
- Theme generation: inverted-selection handling in the generated Neovim colourscheme. Themes that pair a light `selection-background` with a dark `selection-foreground` (e.g. Bluloco Dark) now render `Visual` with the selection foreground forced, matching Ghostty's flip to dark text, instead of leaving syntax colours to vanish at ~1:1 contrast on the light band. Reference-style highlights (`LspReference*`, `TelescopeSelection`) must preserve per-token syntax colours, so they switch to a new derived dark `reference` band rather than the inverted selection colour. `scripts/_lib/generate-theme.lua`, `docs/THEME-SYSTEM.md`

### Changed

- Nvim: sonarlint drops `sonarcsharp.jar` and the omnisharp init options — both were inert (the jar is flagged `SonarLint-Supported: false`, so the language server silently skipped it and `.cs` files always scanned clean while SonarCloud reported issues). Local C# analysis is now documented as deliberately absent: the working sonarlint C# path spawns a bundled omnisharp whose second MSBuild solution load fights roslyn.nvim's. The investigation (including the omnisharp `-v` NullReferenceException on MSBuild 18+ and the 60s `projectLoadTimeout` trap) is recorded in `.claude/rules/sonarlint.md`. `nvim/lua/custom/plugins/sonarlint.lua`, `docs/SONARLINT.md`
- Theme generation: WCAG corrections now demand only 3:1 against the cursor-line highlight (a transient emphasis surface where the large-text minimum applies) instead of 4.5:1, so deliberately muted themes (e.g. Spacegray Eighties Dull) keep their designer palette instead of being brightened. Accents that still fail prefer the theme's own bright palette variant (where the real identity colours often live, e.g. Bluloco Dark's blues) before falling back to synthetic HSL lightening. `scripts/_lib/generate-theme.lua`
- Nvim: `<leader>dT` (diff branch by ticket) diffs against the working tree when the newest ticket-matching commit is HEAD, so uncommitted changes are part of the review; when later non-matching commits exist it sticks to the fixed commit range as before. `<leader>xT` (ticket scan) mirrors the same rule, unioning modified/untracked files into the scan only when the ticket is the branch tip. `nvim/lua/custom/plugins/pr-review.lua`, `nvim/lua/custom/core/lists.lua`
- Nvim: ticket commit discovery (prompt with branch-derived default, merge-base, commit grep, file union + working-tree rule) extracted from `pr-review.lua` and `lists.lua` into a shared `nvim/lua/custom/core/ticket.lua`, now used by `<leader>dT`, `<leader>xT` and the new `<leader>lT` so the three stay identical by construction. The ticket scan keymap is renamed `<leader>xt` → `<leader>xT` to match the capital-T ticket convention, and the changed-files sonar scan `<leader>ls` → `<leader>lm` to mirror `<leader>xm`
- Nvim: the three "modified" bindings now pull the same file set via a shared `modified_files()` in `core/ticket.lua`: staged or unstaged changes vs HEAD (excluding deletions) plus untracked files. Previously each used a different definition — `<leader>xm`'s `ls-files -m -o` missed staged-but-uncommitted files, and `<leader>sm`'s `git_status` picker listed deletions that can't be opened. `<leader>sm` becomes a plain file picker over that set (no status letters or `<Tab>` staging, which `builtin.git_status` provided). `nvim/lua/custom/core/lists.lua`, `nvim/lua/custom/plugins/sonarlint.lua`, `nvim/lua/custom/plugins/telescope.lua`
- Nvim: scan snapshots (`<leader>xm`/`<leader>xT`) also drop roslyn's IDE0005 ("Using directive is unnecessary") — like IDE0079 it needs the full compilation pass the scan-time pull doesn't run. Diagnostic codes are now normalised (string, number, or raw `user_data.lsp.code`) before the ignore lookup. `nvim/lua/custom/core/lists.lua`

### Fixed

- Nvim: diagnostic scans (`<leader>xm`/`<leader>xT`) now set each hidden-loaded buffer's filetype explicitly — `bufload` alone doesn't reliably fire detection, so scanned buffers sat with no filetype: sonarlint (which attaches via FileType) silently never analysed them, C# buffers skipped roslyn's project-init pull gate, and qf entries lost their `[source]` label fallback. Mirrors what the sonar project scan already did. `nvim/lua/custom/core/lists.lua`
- Nvim: phantom IDE0079/IDE0005 entries no longer linger in the live `<leader>xx` diagnostics list. Ignored-code diagnostics on buffers not displayed in any window are dropped from the list — hidden buffers only ever get roslyn's reduced-pass pull, so they never receive the full pass that self-corrects these false positives in-editor. Displayed buffers keep theirs. `nvim/lua/custom/core/lists.lua`
- Nvim: theme watcher now forces the colourscheme reload. A regenerated scheme keeps the same name, so the skip-if-unchanged guard left stale highlights after `dotfiles theme generate` reran on the active theme. `nvim/lua/custom/core/theme.lua`
- Nvim: transient `roslyn: -30099: Failed to get language for textDocument/diagnostic` error bursts are silenced. Nvim core auto-pulls diagnostics the moment roslyn attaches to a buffer, but roslyn can't resolve a file's language until its project has loaded, so scans hidden-loading many C# files during a cold solution load fired one error notification per file. The errors are harmless (diagnostics arrive once project init completes; the scans' own pulls are init-gated) and remain visible in `lsp.log`. `nvim/lua/custom/plugins/ui.lua`

## [0.2.110] - 2026-06-04

### Added

- Nvim: sonarlint silence-rule code actions. The `gra` picker on any sonar finding now offers up to two quick fixes per rule: **silence project-wide** (sets `rules["<code>"] = "off"`) and **silence in test files** (adds or extends an `overrides` entry with the language's test globs; only for languages with a settled test-naming convention). Both write `.sonarlint/localRules.json` (creating it if needed, preserving existing entries) and apply live — the project-wide variant pushes the updated config to the running server, the test variant recompiles the override matchers — so the warning clears without a restart. The actions ride inside sonar's own codeAction response so they sit directly under its entries rather than in a separate group at the bottom. `nvim/lua/custom/plugins/sonarlint.lua`, `docs/SONARLINT.md`
- Nvim: richer sonar "Show issue details" popup. Replaces sonarlint.nvim's generic renderer with a centred markdown popup that renders contextual tabs properly (per-framework "How to fix it" variants each under their own subheading, default context first — upstream shows these tabs empty), drops sonar's no-content "others" fallback section, and floats the "Show issue details" action to the top of the `gra` picker. For deprecation findings (S1874 and equivalents, detected via the LSP `Deprecated` diagnostic tag from any language server), the popup leads with the deprecated symbol's signature and its `@deprecated` replacement note pulled from the editor-facing server's hover — the specific guidance sonar's generic rule text defers to. `nvim/lua/custom/plugins/sonarlint.lua`, `docs/SONARLINT.md`
- Nvim: `<leader>xx` diagnostics quickfix list is now **live**. While the current qf list is the `Diagnostics: all` one, a debounced `DiagnosticChanged` rebuild keeps it current in both directions: fixed entries drop out (as the auto-clear prune already did) and new diagnostics flow in, so there's no need to re-press `<leader>xx` after each round of fixes. The current entry survives rebuilds (or snaps to its nearest predecessor) so `]q` keeps advancing forward. Pushing any other list (`:Cfilter`, a build, a scan) pauses the sync; `<leader>x[` back to the live list resumes it. `<leader>xx` also toggles: pressing it while the qf window shows the live list closes the window. `nvim/lua/custom/core/lists.lua`
- Nvim: git-modified diagnostics scan (`<leader>xm`) shows fidget progress ("N/M file(s) reported") while it runs. `nvim/lua/custom/core/lists.lua`
- Nvim: `<leader>xt` / `:TicketScan` scans the files touched by ticket-matching commits. Commit discovery mirrors `<leader>dT` (merge-base with main, ticket default from the branch name, commit subjects grepped with `--fixed-strings` in `base..HEAD`), but instead of opening a diffview it hidden-loads the union of files touched by exactly the matched commits (per-commit `diff-tree`, so interleaved unrelated commits don't drag their files in) and dumps their diagnostics into a `Ticket: diagnostics` quickfix list via the same scan driver as `<leader>xm` (fidget progress, adaptive debounce, sonarlint gate, auto-clear pruning). `nvim/lua/custom/core/lists.lua`, `nvim/lua/custom/core/build.lua`
- Nvim: `scan_runner` gains an adaptive debounce (`settled_debounce_ms`): once every watched buffer has reported at least one `DiagnosticChanged`, the remaining quiet window drops from 5s to 500ms, so small fast changesets finalise in under a second. A `settle_check` gate keeps the full 5s when a sonarlint client is attached to a scanned buffer, since its java analyzers publish seconds after the buffer's fastest LSP first reports (roslyn is already covered by the project-init pull gate). Also new: `on_report` callback. `nvim/lua/custom/core/scan_runner.lua`
- Nvim: `vim.o.exrc` enabled — a project-local `.nvim.lua` in the working directory is sourced on startup (Neovim prompts to trust it on first load). `nvim/lua/custom/core/options.lua`

### Changed

- Nvim: `<leader>xx` and `<leader>xX` now notify "clean" when there are no diagnostics instead of silently doing nothing. `nvim/lua/custom/core/lists.lua`
- Nvim: scan snapshots (`<leader>xm`/`<leader>xt`) drop roslyn's IDE0079 ("Suppression is unnecessary") diagnostics. Roslyn's scan-time pull for hidden-loaded buffers runs a reduced analyzer pass that can't see the suppressed analyzer's warning, so it flags valid suppressions — a long-standing roslyn defect (dotnet/roslyn#47288, #75887). In-editor the full pass self-corrects, but in a scan snapshot the phantom entries would sit in the quickfix until each file was visited. `nvim/lua/custom/core/lists.lua`

## [0.2.109] - 2026-06-03

### Added

- Yazi: theme flavour generated from the active dotfiles theme. `dotfiles theme` now renders `yazi/theme.toml.template` to `~/.config/yazi/theme.toml`, recolouring the manager, tabs, mode line, status bar, which-key, pickers, tasks, help and filetype rules from the theme's palette (reusing the existing `{{TMUX_*}}` colour variables), so yazi matches tmux/ghostty/gh-dash on every theme switch. Only colour-bearing keys are overridden; icons and layout fall through to yazi's bundled preset. `scripts/theme-switch`, `yazi/theme.toml.template`
- Yazi: new keymaps in `yazi/keymap.toml`. `o` opens the selection in the system file explorer (Finder via `open`, Linux via `xdg-open`) and `<C-g>` opens lazygit in the current directory. `<Enter>` keeps the default open (directories still open in `$EDITOR`).
- Yazi: `y()` shell wrapper (`zsh/dotfiles.zsh`) launches yazi via `--cwd-file` and cd's the shell to the last-browsed directory on quit. Picked up by the `dotfiles aliases` cheatsheet.
- Yazi: `ffmpegthumbnailer` (video thumbnails), `resvg` (SVG previews) and `sevenzip` (archive previews via `7zz`) added to the `Brewfile` to fill the preview backends yazi was missing.

### Changed

- Yazi: `~/.config/yazi` is now symlinked **per file** (`yazi.toml`, `keymap.toml`) instead of as a whole directory, so the generated `theme.toml` can live in the XDG config dir without landing back in the repo. `scripts/install/create-symlinks.sh` creates the per-file links and `scripts/install/uninstall.sh` removes them plus the generated theme. The `0.2.109-yazi-perfile-symlinks.sh` migration converts existing whole-dir symlinks on `dotfiles update` (it runs before the symlinks step, which then recreates the per-file links). `yazi/theme.toml` is gitignored defensively.

## [0.2.108] - 2026-06-03

### Added

- Yazi: the terminal file manager is now a managed tool. `yazi/yazi.toml` raises the image preview caps to `max_width = 1200` / `max_height = 1800` (yazi's defaults are 600x900). The bundled PDF previewer renders pages with `pdftoppm` and precaches the image capped to those dimensions, and yazi won't upscale past the cached size, so on a large terminal PDFs and images previewed noticeably small; the larger caps render bigger, sharper previews. `yazi` and `poppler` (which provides `pdftoppm`) are added to the `Brewfile`, and `~/.config/yazi` is symlinked as a whole directory (the nvim pattern) by `scripts/install/create-symlinks.sh` and removed by `scripts/install/uninstall.sh`.

### Changed

- Nvim: obsidian.nvim completion now flows through its built-in `obsidian-ls` LSP server (added in v3.16) rather than the `nvim_cmp`/`blink` opt-in switches, which are deprecated and removed in obsidian.nvim 4.0. blink.cmp's `lsp` source picks the server up automatically, so the explicit `nvim_cmp = false` / `blink = true` flags are dropped and only `min_chars` remains. `nvim/lua/custom/plugins/obsidian.lua`

### Fixed

- Nvim: treesitter no longer retries (and fails) to install `jsonc` on every startup. `jsonc` was removed from nvim-treesitter's `main`-branch parser registry, so the startup install loop kept it permanently in the "missing" set and ran `install('jsonc')` each launch, which errored with "couldn't install jsonc" for anyone without a stale `jsonc.so` left over from an older revision. Dropped `jsonc` from the parsers list; the `json` parser highlights JSON-with-comments files and `json5` covers stricter cases. `nvim/lua/custom/plugins/treesitter.lua`

## [0.2.107] - 2026-06-02

### Added

- Nvim: explicit mini.icons glyphs for the `sh`/`bash`/`zsh` extensions. mini has no built-in extension entry for these and resolves them through `vim.filetype.match()`, which returns nil during the dashboard's first paint at startup, so mini cached the generic glyph for the session; pinning the glyphs (and matching highlights: sh/bash grey, zsh green) makes resolution independent of filetype-match timing. `nvim/lua/custom/plugins/mini.lua`

### Changed

- Nvim: statusline redesign. The filename is now shown relative to the git/project root (falling back to a `~`-relative path outside a repo) and adapts to the available width: it stays in full while it fits and only collapses parent dirs to initials when the rest of the line leaves no room, keeping the filename intact rather than mini's mid-word left-cut on deep paths. The git branch sits in a theme-accent block; diff counts (`+`/`~`/`-`) and per-severity diagnostics (`E`/`W`/`I`/`H`) are colour-coded inline on the neutral middle so they follow terminal transparency; fileinfo shows the filetype glyph tinted by its mini.icons highlight and surfaces encoding/line-ending only when they deviate from utf-8/unix. All section colours are derived from groups the active theme already defines and re-derived on `ColorScheme`, so every hand-crafted and generated theme stays consistent. `nvim/lua/custom/plugins/mini.lua`

### Fixed

- Nvim: an empty filename section (quickfix, `[No Name]`, terminal) no longer floods the statusline with the mode colour; the neutral filename group is pinned right before `%=` so the expanding gap always fills neutral. `nvim/lua/custom/plugins/mini.lua`
- Tmux: tmux-fingers no longer fires its install/update wizard at config-load time. The binary is supplied by brew and kept current by `dotfiles update`, but the loader compared the brew binary's version against the TPM clone's `shard.yml` on every reload and, when they drifted, ran the update wizard, which fails non-interactively (`install-wizard.sh ... returned 1`). `@fingers-skip-wizard 1` gates only the update wizard, not the first-run bootstrap, so fresh installs still work. `tmux/tmux.conf.template`

## [0.2.106] - 2026-06-01

### Fixed

- Install: `brew update` is no longer fatal during `dotfiles update`. Homebrew can crash on the run where it self-updates (e.g. `uninitialized constant DescriptionCacheStore::FormulaVersions` on 5.x, reached when `HOMEBREW_REQUIRE_TAP_TRUST` is set), which under `set -e` aborted the entire update before symlinks or packages were applied. The step now retries `brew update` once (the bug self-clears on the second run, since Homebrew has already updated itself) and, if it still fails, warns and continues rather than aborting. `brew update` is only a metadata refresh and does not gate the package install that follows. `scripts/install/install-homebrew.sh`

## [0.2.105] - 2026-06-01

### Added

- Nvim: lazydev.nvim supplies lua_ls type libraries on demand. It loads a plugin's annotations when its trigger word appears in a lua buffer (`Snacks`, `Mini*`, and the luvit types behind `vim.uv`), so `K` hover and completion now work for those globals where `.luarc.json`'s `diagnostics.globals` previously only silenced the undefined-global warning without giving them a type. Also wired in as a blink completion source (`score_offset = 100`) for `require()` paths and plugin module annotations. `nvim/lua/custom/plugins/lazydev.lua`, `nvim/lua/custom/plugins/completion.lua`, `nvim/lua/custom/plugins/init.lua`
- `bear` (generates `compile_commands.json` so clang tooling works on C/C++/ObjC projects) and `gdu` (disk-usage analyser TUI, a `du` replacement) added to the Brewfile. `Brewfile`, `README.md`

### Changed

- Nvim: `<leader>ld` now toggles the snacks dashboard rather than only rendering it. On a normal buffer it stashes the current buffer and opens the dashboard in that window; pressing it again on the dashboard restores the stashed buffer (falling back to the alternate buffer `#` if the stash is gone). `nvim/lua/custom/core/refresh.lua`
- Nvim: `.luarc.json` no longer carries type libraries. With lazydev supplying plugin and Neovim-runtime types on demand, `.luarc.json.template` drops `workspace.library` and the `Snacks`/`Mini*` globals (a static `workspace.library` would override what lazydev pushes through the client and break hover), and `create-symlinks.sh` now installs it as a plain copy rather than detecting VIMRUNTIME and substituting `{{NVIM_RUNTIME_LUA}}`. `.luarc.json.template`, `scripts/install/create-symlinks.sh`
- Nvim: `<leader>na` (.NET attach) now maps to `Dotnet debug attach`, and the custom easy-dotnet `terminal` command builder plus `enable_buffer_test_execution` were removed in favour of the plugin defaults. `nvim/lua/custom/plugins/dotnet.lua`
- Removed the JetBrains Toolbox CLI `PATH` entry from `zsh/zprofile`.

### Fixed

- Tmux: `prefix+Space` (tmux-fingers) restored. tmux-fingers 2.7.0 turned `@fingers-enabled-builtin-patterns` into an enum whose validator silently rejects the documented comma-separated subset list, which killed the keybinding; set to `all`, the only multi-pattern value that validates on both 2.6.x and 2.7.x. `tmux/tmux.conf.template`

## [0.2.104] - 2026-05-31

### Added

- Homebrew now requires explicit trust for non-official taps. `zsh/dotfiles.zsh` exports `HOMEBREW_REQUIRE_TAP_TRUST=1`, so a newly tapped third-party repo must be approved with `brew trust --tap <user/repo>` before brew will load its formulae or casks, rather than being trusted by default (Homebrew 5.x deprecates the old implicit-trust behaviour and warns once per tap until a future release turns it into an error). To keep existing setups working under the stricter mode, migration `0.2.104-trust-homebrew-taps.sh` records every currently-installed tap in Homebrew's trust store (`$HOMEBREW_PREFIX/var/homebrew/trust.json`) on update, and `scripts/install/install-packages.sh` trusts the Brewfile's own taps before `brew bundle` so a fresh install isn't blocked. Both guard on the presence of `brew trust` (Homebrew 5.x+) and no-op on older versions. `zsh/dotfiles.zsh`, `scripts/migrations/0.2.104-trust-homebrew-taps.sh`, `scripts/install/install-packages.sh`
- Nvim: `<leader>ld` re-renders the snacks dashboard in the current window without touching LSP or buffers. Closing oil with `-` now also restores the dashboard when oil was launched over it: the dashboard buffer is `bufhidden=wipe`, so oil wipes it and falls back to a blank `enew`; `oil_close` detects that empty landing buffer and re-renders the dashboard instead. `nvim/lua/custom/core/refresh.lua`, `nvim/lua/custom/plugins/navigation.lua`

### Fixed

- Tmux: agent alerts no longer corrupt or drop windows whose name contains a colon (tmux derives names from process titles, which can include `:`, and `:` is also the alerts-file field separator). Window names are now percent-encoded (`%`→`%25`, `:`→`%3A`) on write and decoded on read across the alert lifecycle — set, clear, rename, move, stale-cleanup, the per-agent instance pickers, and the window list — and session/window are fetched separately rather than via a `#S:#W` join. Validation in `clear.sh` and `update-rename.sh` loosened accordingly to accept colons. Adds a round-trip regression test. `tmux/scripts/_lib/alerts.sh`, `tmux/scripts/_lib/test-tmux-libs.sh`, `tmux/scripts/alerts/clear.sh`, `tmux/scripts/alerts/pick.sh`, `tmux/scripts/alerts/update-rename.sh`, `tmux/scripts/instances/*.sh`, `tmux/scripts/windows/list.sh`, `tmux/scripts/windows/move.sh`

## [0.2.103] - 2026-05-29

### Added

- Nvim: C/C++/Objective-C/Swift language support rounded out. Swift gets a new LSP client — `sourcekit-lsp`, launched via `xcrun sourcekit-lsp` on macOS (so it resolves against the active Xcode/Swift toolchain) and the PATH binary on Linux, configured and `vim.lsp.enable`d directly because it ships with the toolchain rather than Mason. Its filetypes are restricted to `swift` so it doesn't double-attach over the C family alongside clangd, which keeps ownership of c/cpp/objc and now duplicates no diagnostics. Formatting via conform: `clang-format` for c/cpp/objc/objcpp and `swift-format` for swift, and `format_on_save` no longer skips c/cpp. Linting via nvim-lint: `swiftlint` for swift (added to the Brewfile). Treesitter parsers added for `cpp`, `objc`, and `swift`. Debugging via a Mason-installed `codelldb` adapter (spawned per-session on `${port}` so a crash can't orphan a fixed port) with shared launch configs for c/cpp/objc/swift that prompt for the compiled binary. `nvim/lua/custom/plugins/lsp.lua`, `lint.lua`, `treesitter.lua`, `kickstart/plugins/debug.lua`, `Brewfile`
- Nvim: binary object/library viewer. Opening a `.o`/`.a`/`.dylib`/`.so` no longer shows raw binary noise — a `BufReadCmd` autocmd renders a decoded, read-only view instead: demangled symbol table (`nm` piped through `c++filt`) by default, with disassembly (`otool` on macOS, `objdump` elsewhere) and a hex dump (`xxd`, capped at 128 KiB) a keypress away via buffer-local `s`/`d`/`x`. The buffer is `nowrite` with no swap and undo disabled so the decoded text can never be flushed back over the binary; output is capped at 50k lines and each view degrades gracefully when its tool isn't installed. `nvim/lua/custom/core/binary-view.lua`, `core/keymaps.lua`
- Nvim: `<leader>x/` greps the yank register (register `0`, untouched by deletes) as a literal string (`grep! -F`) into the quickfix list via `grepprg` (rg), collapsing a multiline yank to its first line. `nvim/lua/custom/core/lists.lua`

### Changed

- Nvim: debugger UI migrated from nvim-dap-ui to nvim-dap-view. A single bottom panel with a winbar switches between scopes (the landing view), watches, threads, breakpoints, exceptions, and repl, with the debuggee terminal in a side split (hidden for Go, whose delve uses an external terminal). dap-view's built-in inline virtual-text values replace the separate nvim-dap-virtual-text plugin, and `auto_toggle` opens the panel on session start / closes it when sessions end, replacing the manual `event_initialized`/`event_terminated` listeners. `codelldb` added to `ensure_installed`; `nvim-dap-ui`, `nvim-nio`, and `nvim-dap-virtual-text` dropped as dependencies. `nvim/lua/kickstart/plugins/debug.lua`
- Theme generation: syntax palette refined. Comments now blend 30% toward the background with a 4.0 contrast floor, where they previously shared `fg_secondary` verbatim with `@variable.parameter`/`LineNr` and read just as loud as parameter names. Keywords, conditionals, loops, labels, exceptions, and storage-class move to pink while number/constant literals keep purple so the two read distinctly; symbolic operators drop to plain `fg_primary` to de-emphasise punctuation; and `@variable` renders as plain `fg_primary`. `scripts/_lib/generate-theme.lua`
- Nvim: neotest status virtual text disabled (signs only). `nvim/lua/custom/plugins/test.lua`
- CI: dropped `.github/workflows/ci.yml` from the startup-benchmark paths filter, so editing the workflow no longer triggers a benchmark re-run. `.github/workflows/ci.yml`

## [0.2.102] - 2026-05-27

### Added

- AI agent statusline theme integration. New `scripts/_lib/statusline-theme.sh` (symlinked to `~/.config/dotfiles/statusline-theme.sh`, core preset) is sourced by an AI CLI coding agent's statusline command — anything that renders its statusline by running a script (Claude Code, GitHub Copilot CLI, Antigravity CLI) — to colour it from the active `dotfiles theme`. It resolves the dotfiles checkout (via `DOTFILES_DIR`/`DOTFILES_ROOT` or by walking up its own real path through the `~/.config/dotfiles` symlink), reads `current-theme`, and parses the theme file's `TMUX_*` palette assignments with `sed` without sourcing it (hand-crafted themes call shell functions that shouldn't run here). It exports `SL_*` ANSI 24-bit foreground escapes for each statusline role plus the raw `SL_HEX_*` hexes; callers keep their own defaults behind `${SL_*:-…}`, so sourcing is always safe — it sets nothing when no theme resolves. Role colours (model, dir, branch, time, context, separators) follow the palette directly, while the semantic roles carrying universal add/delete/modify/warn meaning (`SL_STAGED`, `SL_LINES_ADD`, `SL_MODIFIED`, `SL_DELETED`, `SL_LINES_DEL`, `SL_WARNING`) are hue-locked: `__sl_huelock` converts the source accent to HSL, clamps the hue into a green/red/orange/amber band — keeping the theme's own lightness and saturation, with a saturation floor and lightness window to rescue grey or washed-out accents — and converts back, so the git +/- diff and status markers always read correctly even under a theme whose "green" slot is teal or whose "red" is a washed-out pink. Reads the theme live, so the statusline re-colours on the next render after `dotfiles theme switch`. Documented in `docs/THEME-SYSTEM.md`, `README.md`, and `CLAUDE.md`
- CI: the startup-benchmark job accepts a manual `workflow_dispatch` trigger that forces a re-measure and badge update regardless of which files changed. The badge only updates on push when a zsh-affecting file changed (so it doesn't flap on unrelated CI-runner noise), which left a bad cold-run number stuck until the next zsh change; a manual run from the Actions tab now re-rolls it without touching any file. The `paths-filter` step is skipped on dispatch (no base to diff against) and the badge-update step gates on `main` and `(push + zsh change) || workflow_dispatch`

### Changed

- Theme generation: the `CursorLine`/`ColorColumn` line-highlight colour now lifts very dark backgrounds a little more — `+7` lightness below 0.03 background luminance, `+5` otherwise, where it was previously a flat `+4` — so the cursor-line band registers the same visual step on near-black palettes instead of washing out. `scripts/_lib/generate-theme.lua`
- Docs: stripped em-dashes from `docs/**` and `README.md` (replaced with colons, semicolons, or split sentences) and added a `.claude/rules/docs.md` style rule mandating it for those paths going forward (`CHANGELOG.md`, `.claude/`, and code/comments stay out of scope)

## [0.2.101] - 2026-05-26

### Added

- Nvim: LSP rename (`grn`) now writes the files it changed to disk. `vim.lsp.buf.rename` applies the workspace edit to every affected file, but the ones not already open are edited in unsaved background buffers — they never fire the auto-save autocmd (programmatic edits to a non-current buffer raise no `TextChanged`, and the buffers are never entered/left for `BufLeave`), so renamed symbols in other modules stayed off disk: invisible to Diffview (which diffs against disk) and surfacing only as a "save changes?" cascade on `:qa`. `nvim/lua/custom/plugins/lsp.lua` overrides `vim.lsp.handlers['textDocument/rename']` with a handler that mirrors the default (applies the edit) then writes every touched buffer — walking `result.documentChanges` (array of edits, skipping create/rename/delete resource ops that carry no `textDocument`) or `result.changes` (URI-keyed map), writing only loaded, modified, modifiable, normal-`buftype` buffers. `vim.lsp.buf.rename` already dispatches through this handler (`client.handlers[...] or vim.lsp.handlers[...]`), so it covers renames from any trigger, not just `grn`

### Fixed

- Nvim: `<leader>z` zoom no longer kills `j`/`k` (and the rest of the panel keymaps) inside Diffview or Octo review file panels. The zoom does `tab split`, but both plugins scope their view — and every panel action, which dispatches via a `get_current_view()`/`get_current_review()` lookup keyed on `nvim_get_current_tabpage()` — to the original tab, so in the new zoom tab `next_entry`/`prev_entry` and friends silently no-op (plain motions like `^d`/`gg` kept working precisely because they don't route through the plugin). A float-based zoom doesn't help either: entry navigation moves the cursor in the panel's own tracked `winid`, not the focused window. `nvim/lua/custom/core/windows.lua` now detects a scoped view (`package.loaded['diffview.lib'].get_current_view()` or `package.loaded['octo.reviews'].get_current_review()`, read without forcing either module to load) and maximises the window in place instead — lifting the panel's `winfixwidth`/`winfixheight` pins, `wincmd _` then `wincmd |`, and stashing `winrestcmd()` plus the winfix values (in a module-local table keyed by tabpage) to restore on toggle-off. Ordinary splits keep the tab-split zoom and its bit-for-bit `tab close` restore

## [0.2.100] - 2026-05-26

### Added

- Dotfiles CLI: `dotfiles update` now prints a "Notices from this update" block at the end if any migration left a notice — migrations append to `~/.config/dotfiles/.state/update-notices.txt` and the file is printed + cleared at end of update. The print lives in `install.sh` (which is re-read fresh from disk after the pull, so it works on the upgrade hop itself — the running `cmd_update` is still the pre-pull copy parsed in memory and can't run new helpers) with a safety-net call from `cmd_update` for the "already up-to-date" branch on subsequent runs. Surfaces messages (like "these apps were removed") that the installer's normal output would otherwise have scrolled past
- Nvim: SonarLint project-local rule overrides via `.sonarlint/localRules.json`, ESLint-style. `nvim/lua/custom/plugins/sonarlint.lua` reads the file in `before_init` (`read_project_config`) and applies two fields. `rules` maps a rule key (e.g. `go:S100`) to an ESLint severity — `"off"` | `"warn"` | `"error"` (or `0` | `1` | `2`), or the array form `["error", { params }]` for parameterised rules — which `eslint_to_sonarlint_rules` normalises to the server's native `{ level, parameters }` shape and merges into `settings.sonarlint.rules` (applies globally; in connected mode an explicit `"off"` wins over the server profile's `"on"`). SonarLint has no warn/error split, so `"warn"` and `"error"` both map to `level "on"` — only `"off"` silences a rule. `overrides` is an eslintrc-style array of `{ "files": [glob], "rules": {...} }` entries applied client-side at diagnostic publish time via a wrapped `publishDiagnostics` handler; it can only subtractively silence diagnostics, since a globally-off rule can't be re-enabled per-glob once the server has stopped emitting it. Globs are compiled with `vim.glob.to_lpeg` (needs nvim 0.10+) and matched against both absolute and project-relative paths
- Nvim: `<leader>sF` regex find-files picker. `nvim/lua/custom/plugins/telescope.lua` builds a custom picker whose finder re-runs `fd --type f --hidden --exclude .git --regex <prompt>` on every keystroke (`finders.new_job`), paired with `sorters.highlighter_only` so telescope's fuzzy sorter doesn't re-filter the job output and reject regex metacharacters like `.*`. Complements the default fuzzy `<leader>sf` (`builtin.find_files`) for when you want true regex matching on the path. README keybindings table and the cheatsheet `search` section updated
- Nvim: Diffview and Octo file panels follow the theme palette. `nvim/lua/custom/core/diff-highlights.lua`'s `apply()` now pins `DiffviewFilePanelInsertions` / `OctoDiffstatAdditions` / `OctoPullAdditions` to theme green and the deletion counterparts to theme red (independent of how the theme defines `diffAdded`/`diffRemoved`), and gives the file-status markers (`DiffviewStatus*` / `OctoStatus*` — A/D/M/R/C/?/U/T/X/B/!) a shared semantic palette so the letter agrees with the diffstat bar: added/untracked → theme green, modified → yellow, renamed/copied/typechange → blue (`Function`), unmerged → orange (`Number`), unknown/ignored → grey (`Comment`), deleted/broken → red. Type-changes are keyed off the `…StatusTypeChanged` group both plugins actually render (their defaults link the `…StatusTypeChange` name instead). Re-derived on every `:colorscheme` switch like the rest of the module

### Changed

- Nvim: `<leader>xx` (dump all diagnostics to quickfix) now runs `checktime` first, reloading any open buffer whose file was changed on disk by an external writer (Claude Code, another nvim instance, a script) before snapshotting diagnostics. The LSP republishes via `on_lines` after the reload, so a second `<leader>xx` reflects the new state. `nvim/lua/custom/core/lists.lua`
- Brew: `pipx` replaced with `uv` in the Brewfile. `uv tool install <name>` and `uvx <name>` are drop-in replacements for `pipx install` / `pipx run`, with a single Rust binary, much faster installs, and shared caching. A new `scripts/migrations/0.2.100-uninstall-pipx.sh` snapshots any pipx-managed apps to `~/.config/dotfiles/.state/pipx-uninstalled.txt`, runs `pipx uninstall-all` so the venvs under `~/.local/pipx/` are cleaned up rather than orphaned, then drops the pipx formula. The list of removed apps is appended to the new update-notices file so it surfaces in the end-of-update summary. Re-install anything you still want with `uv tool install <name>`. The `~/.local/bin` PATH entry from `zsh/zprofile`/`dotfiles.zsh` stays — `uv tool install` drops binaries there too. `docs/INSTALLATION-GUIDE.md` updated to mention uv instead of pipx
- Nvim: easy-dotnet's `auto_start_testrunner` set to `false`. The test runner no longer spins up automatically on LSP attach in a .NET project — it's started on demand via the run/debug test bindings (`<leader>tr` / `<leader>td`) instead, avoiding the upfront cost on every C# buffer
- Tmux: the alert picker's `--list` mode no longer pays for picker-only initialisation. `--list` is invoked by fzf's `reload-sync` on every `x` keypress to refresh the entry list, but `tmux/scripts/alerts/pick.sh` was sourcing `common.sh` and `ui.sh` and calling `load_fzf_theme` regardless — ~100ms of bash sourcing that visibly stalled the popup on each refresh, when list mode only needs `alerts.sh`. The flag is now detected before those sources and they're skipped in list mode; the empty-alerts branch also exits cleanly (`exit 0`) instead of trying to draw the "No active alerts" message it can't render

### Fixed

- Nvim: LSP location jumps routed through `lsp_dedup` (go-to-definition and friends) no longer hand `vim.lsp.util.show_document` a half-specified range. When a request resolved to a single location the range carried only `start` and no `end`; `nvim/lua/custom/plugins/lsp.lua` now sets `end` to the same line/column so the jump is well-formed rather than relying on the handler tolerating a missing field
- Tmux: clicking the left status bar (`MouseDown1StatusLeft`) opens the session picker without two phantom entries at the top of the list. `print_dotfiles_logo` emits a 7-line block (a leading blank, five logo rows, a trailing blank), but the fzf invocation in `tmux/tmux.conf.template` froze only `--header-lines=5`, leaking the last logo row and trailing blank into the selectable session list. Bumped to 7 so the whole logo block is treated as header
- Nvim: Dropped the `extensions = { razor = { enabled = false } }` override from the roslyn.nvim config in `nvim/lua/custom/plugins/dotnet.lua`. roslyn.nvim removed all built-in razor flag injection upstream (`--razorSourceGenerator` / `--razorDesignTimePath`) and then deprecated the `extensions` option entirely, so the override was both a no-op (the cmd-builder only acts on `enabled = true` extensions) and the trigger for a `vim.deprecate` warning + stack traceback on every C#/razor LSP start. Razor is now bundled and enabled by default in the server itself

## [0.2.99] - 2026-05-23

### Added

- Tmux: `@browser-app` user option to send URLs from the `prefix + u` picker to a specific macOS app instead of the LaunchServices default. `tmux/scripts/_lib/common.sh`'s `open_url()` now reads `tmux show-options -gv "@browser-app"` on Darwin and, when non-empty, invokes `open -a "$app" "$url"` instead of plain `open "$url"`; unset value preserves the existing behaviour exactly, so the change is a no-op for users who don't opt in. The lookup is gated behind `command -v tmux` so the function still works for callers outside a tmux context. Set in `~/.config/tmux/local.conf`, e.g. `set -g @browser-app 'Arc'` (or `'Google Chrome'`, `'Safari'`). Example added to `tmux/local.conf.template` and a one-line pointer added to the URL picker section in `tmux/tmux.conf.template`. Linux/WSL branches (`xdg-open`/`wslview`) are unchanged — those already respect their own system-level default-browser settings

## [0.2.98] - 2026-05-21

### Added

- Nvim: `<leader>na` (`:Dotnet attach`) for attaching the .NET debugger to a running process. Cheatsheet entry added under the `dotnet` section
- Nvim: JS/TS DAP adapters wired up via vscode-js-debug. `nvim/lua/kickstart/plugins/debug.lua` registers the `pwa-node`, `pwa-chrome`, `pwa-msedge`, `node-terminal`, and `pwa-extensionHost` adapters pointed at Mason's `js-debug-adapter/js-debug/src/dapDebugServer.js`, using `${port}` so each session gets a free port and a crashed run can't leave an orphan squatting on a fixed one. `js` is added to `mason-nvim-dap`'s `ensure_installed`. neotest-vitest's `strategy = 'dap'` now picks the `pwa-node` adapter automatically
- Nvim: Go "Attach (remote dlv)" launch config. `nvim/lua/kickstart/plugins/debug.lua` appends a `request = 'attach', mode = 'remote'` entry that prompts for a port (default 38697) and connects to a headless dlv you started yourself (`dlv attach <pid> --headless --listen=...` or `dlv exec ./binary --headless --listen=...`). Comment above the config notes the constraints that force this workflow for TUI binaries: delve's DAP server ignores `console: integratedTerminal` when actually debugging, and `dlv dap` has no `--tty` flag
- Nvim: `mini.icons` registers explicit `cs` / `csharp` filetype glyphs (`nf-md-language_csharp`, `MiniIconsGreen`). `render-markdown` resolves code-fence languages as filetypes, so without this `csharp` blocks fell back to the generic file icon instead of the C# icon mini.icons already ships under the `cs` _extension_
- Nvim: render-markdown gets a dedicated code-block highlight. `nvim/lua/custom/core/autocmds.lua` adds a `ColorScheme` autocmd that derives `RenderMarkdownCode` / `RenderMarkdownCodeBorder` / `RenderMarkdownCodeInline` / `RenderMarkdownInlineHighlight` from the active palette via `diff_highlights.tint_bg`, so code blocks no longer collide with the `CursorLine` tint they used to inherit (render-markdown links them to `ColorColumn` by default). Re-runs on every `:colorscheme` switch and on startup
- Nvim: render-markdown's anti-conceal now keeps the code-block background tint visible when the cursor crosses into a code block (`anti_conceal.ignore.code_background = false`). The default revealed the raw markdown but also stripped the tint, leaving the fence visually identical to surrounding prose while you edit
- Zsh: `setopt IGNORE_EOF` inside tmux. A stray Ctrl+D at the prompt no longer closes the shell — which would tear down the pane and, when last, the window. Outside tmux, Ctrl+D still exits normally
- Fzf: `FZF_DEFAULT_OPTS` now binds `ctrl-d` / `ctrl-u` to half-page-down/up and `ctrl-l` to clear-query, applied to every fzf invocation that picks up the dotfiles theme

### Changed

- Tmux: Generated session launchers can handle project/worktree paths containing apostrophes (e.g. `~/foo's/bar`). `tmux/scripts/launchers/new.sh` now stages the default path in a `_<SESSION>_ROOT_DEFAULT="…"` / `_<SESSION>_WORKTREES_DEFAULT="…"` variable and references it via `"${VAR:-$_DEFAULT}"`, since single quotes inside an inline parameter-expansion default (`${VAR:-/foo's/bar}`) trip bash's quoter even within `"…"`. A `${PATH/#~/$HOME}` expansion handles env-var overrides that ship a literal `~`. The existing `PROJECT_DIR="${VAR:-default}"` format is still parsed by the "edit existing launcher" path, so older launchers keep loading without regeneration
- Nvim: neotest-vitest's `vitestCommand` returns `node <vitest.mjs>` instead of the `.bin/vitest` shim when running under DAP. neotest-vitest passes `command[1]` straight through to DAP's `runtimeExecutable`, which must be a node-equivalent runtime — the wrapper script breaks package.json resolution under js-debug. Falls back to `.bin/vitest` if `node_modules/vitest/vitest.mjs` isn't present (older vitest layouts)
- Nvim: neotest-vitest no longer overrides `cwd`. The adapter's default is the directory of the nearest `vitest.config.*`, which in a bun/hoisted monorepo is the per-project root — forcing the hoisted-node_modules root caused vitest's per-project `include` globs to miss the test file with "No test files found". `find_vitest_root` is still used by `vitestCommand` to locate the binary
- Nvim: `mason-nvim-dap` switched to `automatic_installation = false`. `ensure_installed` handles upfront install, and `automatic_installation` races with it whenever an adapter is registered via `dap.adapters[...]` in the same session — installs got stuck mid-flight on a Mason registry lockfile collision
- Nvim: Obsidian `frontmatter.func` only emits `aliases:` when the note actually has aliases. The previous `out.aliases = {}` from 0.2.97 kept the slot as an empty placeholder but rendered as a literal `aliases:` line in YAML on every save
- Shell: `dotfiles set dev|projects` now preserves a customised `PROJECT_DIRS` line that already references both `$DEV_ROOT` and `$PROJECTS_ROOT` (e.g. `PROJECT_DIRS="$DEV_ROOT:$PROJECTS_ROOT:$HOME/work"` with an extra appended root). A stale `PROJECT_DIRS` that's missing one of the refs (e.g. a hardcoded path from a pre-`set` `.zshrc`) is still rewritten to the canonical form so the auto-derivation can take over. New `scripts/tests/test-dotfiles-cli.sh` cases cover both branches
- Zsh: `zsh/zprofile` adds `$HOME/.local/bin` to `PATH` — a common install target for `pipx`, `cargo install`, and language CLIs that drop binaries there

## [0.2.97] - 2026-05-18

### Added

- Nvim: `render-markdown.nvim` for in-buffer markdown rendering. Spec lives in `nvim/lua/custom/plugins/markdown-ui.lua` alongside the existing `mkdnflow` (interactive editing) and `markdown-preview.nvim` (browser preview). Opts trimmed close to a VS-Code-editor look: `heading.icons = {}` + `heading.backgrounds = {}` (no glyph prefix or coloured bar — relies on treesitter for heading colour/weight), `bullet.enabled = false` (raw `-`/`1.` markers, no `●`/`①` swap), `sign.enabled = false` (no gutter glyphs). Code blocks, quotes, tables, checkboxes, and links keep their defaults. `obsidian.nvim`'s `ui.enable = false` comment updated to reflect the new display layer
- Nvim: `neotest-jest` adapter for Jest projects (React Native, RTL, plain JS/TS). `nvim/lua/custom/plugins/test.lua` registers `haydenmeade/neotest-jest` alongside the existing vitest/golang/python adapters, resolving `node_modules/.bin/jest` with the same walk-up + monorepo-subdir lookup the vitest adapter uses. `find_vitest_root` was generalised to `find_node_bin_root(path, bin)` with thin `find_vitest_root` / `find_jest_root` wrappers, and the bin-root cache is now keyed per `(path, bin)`. The jest adapter's `is_test_file` requires `find_jest_root` to return non-nil, so vitest projects keep using vitest even though both adapters claim `.test.`/`.spec.` files by default. README testing bullet updated to mention Jest/React Native
- Nvim: Markdown `gf` follows `[[wiki-style]]` links. `nvim/after/ftplugin/markdown.lua` prepends `.md` to `suffixesadd` and points `includeexpr` at a new `nvim/lua/custom/wiki.lua` resolver that strips `|alias`/`#anchor` from the link, tries the sibling `.md` first, then walks the buffer's nearest `.git` root for a matching file. Works in any markdown buffer outside an obsidian vault; vault buffers get their own `gf` handler (see Obsidian entry below)
- Nvim: Obsidian vault buffers map `gf` to obsidian.nvim's in-nvim `follow_link` action (same behaviour as `<CR>`). `nvim/lua/custom/plugins/obsidian.lua` adds a `callbacks.enter_note` hook that sets a buffer-local `gf` keymap calling `obsidian.actions.follow_link` with the link returned by `obsidian.api.cursor_link()`. Two API quirks made this fiddlier than expected — `follow_link(nil, ...)` doesn't auto-grab the cursor link despite the docs implying it does, and `open_strategy` is used as a literal vim command rather than a strategy enum (`'edit'` works, `'current'` produces a `:current /path` syntax error). Comment in the file flags both
- Brew/Zsh: Android command-line tools available via the `android-commandlinetools` cask. `Brewfile` adds the cask; `zsh/dotfiles.zsh` exports `ANDROID_HOME` to the Homebrew-managed location and prepends `cmdline-tools/latest/bin`, `platform-tools`, and `emulator` to `PATH` when the directory exists. Provides `sdkmanager`, `avdmanager`, `adb`, `fastboot`, and `emulator` on a fresh machine without manual download

### Changed

- Nvim: Diagnostic source labels fall back to the buffer's filetype when there's no explicit mapping in `SOURCE_LABEL`. `nvim/lua/custom/core/scan_runner.lua`'s `source_label` previously returned the raw `d.source` for unmapped sources, which let gopls subanalyzers leak through as `[modernize]`, `[stringscut]`, `[minmax]`, `[stringsseq]`, etc. — same diagnostic stream, different analyser names, cluttered prefixes. The filetype fallback collapses them all under `[go]`. Explicit `SOURCE_LABEL` mappings still win, and raw `d.source` remains the last resort when there's no buffer filetype
- Nvim: Obsidian `<leader>os` (Search vault) renamed to `<leader>og` (Grep vault) to mirror the telescope live-grep binding at `<leader>sg`. Same `:Obsidian search` command underneath; only the binding letter changed. `nvim/cheatsheet.txt` updated
- Nvim: Obsidian `frontmatter.func` strips the auto-generated `id` field on save. The vault uses human-readable filenames (`note_id_func` returns the title verbatim) and wiki+shortest links resolve by title, so the builtin's `id` field just duplicated the filename. The existing `aliases = {}` override stays (kept as an empty placeholder for alternate titles). Existing notes with an `id:` line in their frontmatter aren't auto-stripped — only new saves go without

## [0.2.96] - 2026-05-16

### Added

- Nvim: Python toolchain. `nvim/lua/custom/plugins/test.lua` registers the `neotest-python` adapter with `runner = 'pytest'` and `dap.justMyCode = false` so test debugging steps through dependencies. `nvim/lua/kickstart/plugins/debug.lua` adds `nvim-dap-python` as a dependency, adds `debugpy` to `mason-nvim-dap`'s `ensure_installed`, and points `dap-python` at Mason's debugpy venv (`stdpath('data') .. '/mason/packages/debugpy/venv/bin/python'`) so debugging doesn't depend on a project-local venv being active — `nvim-dap-python` still falls back to a project venv automatically when one is detected. `nvim/lua/custom/plugins/lsp.lua` adds `ruff` to Mason's `ensure_installed` and registers it as the python conform formatter (`ruff_organize_imports`, then `ruff_format`). `nvim/lua/kickstart/plugins/lint.lua` declares `ruff` as the python linter. README testing bullet updated to mention pytest alongside Go and Vitest/Bun
- Nvim: Quickfix entries now carry a `[source]` prefix so each warning shows which LSP it came from (sonarlint → `[sonar]`, tsserver → `[ts]`, lua_ls → `[lua]`, roslyn → `[cs]`, etc.). A `SOURCE_LABEL` table at the top of `nvim/lua/custom/core/scan_runner.lua` shortens the raw `d.source` strings to 3–5 char labels — unmapped sources fall through unchanged so new LSPs degrade gracefully. Applied automatically to project sonar scans (`<leader>ls` / `<leader>lS`), the git-modified scan (`<leader>xm`), and the native diagnostic dumps (`<leader>xx` / `<leader>xX`). `<leader>xx` / `<leader>xX` were rewritten to bypass `vim.diagnostic.setqflist` / `setloclist` and route through `scan_runner.diag_to_item` so they get the same prefix
- Zsh: `cache` alias to open `~/.cache` in nvim, mirroring the existing `config` shortcut for `~/.config`

### Changed

- Nvim: Quickfix auto-clear no longer drops stale entries just because _any_ diagnostic happens to land on the same line. `build.lua`'s `prune_diag_list` now matches diagnostic-sourced lists (`Sonar:`, `Modified:`, `Diagnostics:`) on `(lnum, text)` — comparing against the same `[source] message` produced by `scan_runner.qf_text(d)` — so a tsserver warning landing where a fixed sonar issue used to live no longer keeps the resolved entry alive. `Build:` qf entries keep the old line-only match because compiler output doesn't carry a `[source]` prefix to compare against. `AUTO_CLEAR_KINDS` was refactored from `{kind = label}` to `{kind = {label, match}}` so each list type picks its own strategy
- Nvim: `nvim/lua/kickstart/plugins/lint.lua`'s `BufWritePost` / `BufEnter` autocmd now filters `linters_by_ft` through `vim.fn.executable()` before calling `lint.try_lint()`, so missing linter binaries no longer surface `cmd '<linter>' is not executable` errors on every save — relevant for machines that haven't installed ruff/markdownlint/etc yet

## [0.2.95] - 2026-05-15

### Fixed

- Nvim: `vim.g.obsidian_vault_root` now works for single-vault layouts (e.g. `~/notes` with `.obsidian/` directly inside). `nvim/lua/custom/plugins/obsidian.lua` only scanned _subdirectories_ of the root for `.obsidian/`, which fit the "parent of multiple vaults" layout but not the more common case where the root **is** the vault — obsidian.nvim then crashed with `At least one workspace is required!`. Discovery now treats the root as a workspace if it has `.obsidian/` directly, and falls back to scanning immediate subdirectories otherwise. If neither yields any vaults the plugin spec is skipped with a `vim.notify` warning, so a mistyped path never crashes startup. Template (`nvim/local.lua.template`) updated to show both layouts

### Changed

- Nvim: `<leader>on` / `<leader>oN` swapped so the easier-to-press lowercase binding is the more common action. `<leader>on` now creates a note from a template if the active vault has a `templates/` folder, otherwise falls back to the blank-note title prompt — picked at keypress time, so it honours `<leader>ow` workspace switches. `<leader>oN` is always the blank-note title prompt. Users without a `templates/` folder see no behavioural change on `<leader>on`
- Tmux: Launcher picker (`prefix + p`) hides the dotfiles ASCII logo when the popup itself is cramped, not just when the host terminal is in mobile mode. `tmux/scripts/launchers/picker.sh` queries the popup pty via `stty size` and drops the logo when popup width < 80 cols (matching the session picker's `<80(bottom,40%)` vertical-preview threshold) or popup height < 20 rows. `tmux/scripts/launchers/list.sh` honours an explicit `--no-logo` override; the `bind p` `if-shell` in `tmux/tmux.conf.template` no longer needs to pass it. Wide+tall popups still show the logo
- Tmux: `prefix + h` (help) no longer fails with `Height too large` on short terminals, and the popup now snaps to whichever help variant will fit instead of leaving the compact text marooned in the top-left of a 95%×95% popup. `bind h` in `tmux/tmux.conf.template` delegates to a new `tmux/scripts/utils/show-help-popup.sh` wrapper, which receives `#{client_width}` / `#{client_height}` as args from the binding (querying them via `tmux display-message` inside `run-shell` produced a `returned 129` / SIGHUP error) and picks one of: `74×40` (full template), `74×24` (compact, wide enough), `95%×24` (compact, narrow), or `95%×95%` (tiny terminal fallback). A new 21-row `tmux/tmux-help-compact.template` covers the same shortcuts in roughly half the rows, and `tmux/scripts/utils/show-help.sh` picks it via `stty size` when popup height < 38

## [0.2.94] - 2026-05-15

### Added

- Nvim: `razor` added to the treesitter parser list

### Fixed

- Nvim: `vim.g.obsidian_vault_root` set in `~/.config/nvim/local.lua` is now honoured. `local.lua` was loaded at the end of `init.lua`, after `lazy.setup` had already imported plugin specs — so `nvim/lua/custom/plugins/obsidian.lua` resolved the vault root before the user's override existed and silently fell back (or returned an empty spec on non-iCloud machines). `local.lua` is now loaded before `lazy.setup` so plugin specs see user-set `vim.g.*`. Plugin-dependent calls in `local.lua` (e.g. mutating `require('music.config').options`) must now be wrapped in `vim.schedule(...)` — template updated to show this
- Nvim: C# semantic tokens on `.cs` open now settle to correct colours on their own. The flicker itself is unchanged — Roslyn emits partial classifications while it loads — but tokens no longer get stuck on stale warmup state until a manual `<leader>lt`. Three changes in `nvim/lua/custom/plugins/dotnet.lua`. (1) Roslyn 5.8.0 declares `semanticTokensProvider.range` statically in `initialize`, so Neovim 0.12's viewport-only range requests race the full-document requests and overwrite them with whatever's classified at that moment — an `LspAttach` hook now disables `server_capabilities.semanticTokensProvider.range` for roslyn clients (`stp.range = false`) before `STHighlighter:on_attach` caches `supports_range`, killing the range/full race. (2) The `client/registerCapability` filter that previously tried to do this was dead code (Roslyn declares range statically, not dynamically) and has been removed. (3) The `RoslynInitialized → force_refresh` handler is replaced with an `LspProgress` listener that debounces (300ms) and refreshes when Roslyn emits `kind == 'end'` — `workspace/projectInitializationComplete` fires before per-file analysis is done, so the old single-shot refresh landed on stale tokens; progress 'end' events are emitted after actual analysis chunks complete
- Nvim: Quitting with `.cs` buffers open is now instant. `exit_timeout = 5000` was needed to make `:lsp restart roslyn` work (Roslyn is sluggish to ack `shutdown`), but it also made `VimLeavePre` wait up to 5s on actual exit. An `ExitPre` autocmd in `nvim/lua/custom/plugins/lsp.lua` zeros every roslyn client's `exit_timeout` and force-stops it before `VimLeavePre` runs; runtime restarts still get the 5s grace
- Nvim: Roslyn no longer exits on startup against Razor projects. `roslyn.nvim` was still passing `--razorSourceGenerator` / `--razorDesignTimePath` to the server, but Roslyn 5.8.0-1.26262.10 (Mason 2026-05-14) bundles Razor natively and rejects those flags. `extensions.razor.enabled = false` in the plugin opts stops the flags being added (seblyng/roslyn.nvim#360)
- Nvim: `mini.bracketed` mappings (`]b`/`[b`, `]f`/`[f`, `]d`/`[d`, …) are now no-ops inside qf/loclist buffers — those operate on the underlying editing window but fire against the list buffer when it's focused, which was confusing. `]q`/`[q` and `]l`/`[l` (real list navigation) stay live

### Changed

- Installer: `scripts/install/check-prerequisites.sh` slimmed to the two tools the install bootstrap actually needs — `git` and `brew`. The full toolchain (nvim, tmux, fzf, language SDKs, …) is installed by `brew bundle` during `install.sh`, so pre-gating on it just produced false-MISSING noise on a fresh machine. Use `health-check.sh` post-install for the wider toolchain audit
- Scripts: `theme-contrast-check` now reports the bright-black/background ratio but doesn't count it as a failure. ANSI 8 is conventionally a dim/decorative colour and many palettes (Monokai Pro family, etc.) intentionally place it below WCAG AA

## [0.2.93] - 2026-05-15

### Removed

- Installer: `postgresql` dropped from the prerequisites check — the dotfiles install doesn't need postgres to be present, so gating on `psql` just produced false-MISSING noise. Postgres is still in the brew preset (`postgresql@17`) for users who want it.

## [0.2.92] - 2026-05-15

### Added

- Brew: `watch` (GNU procps) added to the core preset — flicker-free re-renderer for periodic commands
- Brew: `gpk` (from `neur0map/tap`) added to the core preset — TUI dashboard that unifies 34 package managers into one searchable view
- Brew: `httpyac` added to the dev preset — `.http`/`.rest` file runner
- Ghostty: `cursor-warp.glsl` (corner-aware easing — leading corners snap, trailing ease) replaces the deleted `cursor-trail.glsl`. `tft.glsl` (scanline + grille) added alongside. Activate via `custom-shader =` in `~/.config/ghostty/local`
- Karabiner: cmd+ctrl chords are absorbed while Ghostty is frontmost, except `cmd+ctrl(+shift)+space/left/right` which pass through. Stops macOS Spaces shortcuts leaking into the terminal. `karabiner/karabiner.json` is copy-on-install, so existing users must patch the installed JSON by hand
- Tmux: `pane-focus-in` hook clears the alert on the focused agent — covers `cmd+`` swaps between Ghostty clients attached to the same tmux server, where `after-select-window`doesn't fire. Documented in`docs/AGENT-HOOKS.md`
- Tmux: `CLAUDE_CODE_TMUX_TRUECOLOR=1` exported to children — Claude Code ≥2.1.77 clamps chalk to 256 colours under `$TMUX`; the env var opts back into 24-bit RGB (anthropics/claude-code#36785, #46146)
- Tmux: `alerts/pick.sh` jumps directly to the target window when there's only one pending alert, skipping fzf
- Tmux: `instances/claude.sh` ghost renders Anthropic's terracotta (`#D77757`) in 24-bit RGB instead of the closest 256-colour approximation (`174`)
- Nvim: `<M-CR>` at blink.cmp prompts inserts a literal newline without accepting the visible completion — Ghostty sends Shift+Enter as `ESC+CR`, so multi-line input in Claude/Octo/comment buffers no longer commits a stray suggestion
- Nvim: `<leader>sr` (Telescope resume) refreshes the resumed picker once it's ready, so the list reflects current workspace state instead of cached entries
- Nvim: `LazyDimmed` re-linked to `Comment` — lazy.nvim's default link to `Conceal` rendered chore-bump commit lines effectively invisible on dark themes
- Nvim: `zig`, `awk`, `toml` added to the treesitter parser list

### Fixed

- Launchers: tmux session lookups now use exact-match targets (`=$SESSION`) instead of bare names. The previous form silently prefix-matched — creating a `dana-15` instance while `dana-1533` was running would re-attach to `dana-1533` instead of creating a new session. Fixed in the wizard template (`tmux/scripts/launchers/new.sh`), the shared `launchers/dev` script, and migration `0.2.92-fix-launcher-prefix-match.sh` patches existing user-owned launchers in `~/.config/dotfiles/launchers/`
- Nvim: `<leader>do` no longer surfaces Vim's `(L)oad File` prompt after an external agent edits files mid-cascade — `autoread` is silently bypassed whenever any buffer is transiently `modified=true` (diffview's mid-layout buffers, etc.). Three changes in `core/autocmds.lua`: dropped `BufEnter` from the reload trigger list, added `FocusLost`/`BufLeave` to autosave so buffers are clean before the agent's edit lands, and a `FileChangedShell` handler that pins `vim.v.fcs_choice = 'reload'` as a fallback
- Nvim: `:lsp restart roslyn` / `:Roslyn restart` no longer hang or silently fail to re-attach. (1) Roslyn's `on_exit` nils `g:roslyn_nvim_selected_solution` as a side effect, so the restart bailed on the multi-target prompt — a one-shot `LspDetach` autocmd now preserves the solution across detach/re-init. (2) `exit_timeout = 5000` force-kills the old client after 5s instead of waiting for the next LSP request to nudge the pipe
- Tmux: `_lib/alerts.sh`'s `build_alert_icons` now uses literal prefix matching instead of `grep`, so callers don't have to escape `.` in session/window names — the previous form silently dropped alerts on dotted names like `v0.2.67`. `sessions/list.sh` and `windows/list.sh` updated to pass the unescaped prefix
- Installer: `scripts/_lib/common.sh` is now safe to source from zsh — the `${BASH_SOURCE%/*}` idiom expanded to empty under zsh and broke ad-hoc sourcing. Resolves the lib dir once via `BASH_SOURCE` (bash) or `${(%):-%x}` (zsh)

### Removed

- Brew: `postgresql@14` is now uninstalled by migration `0.2.92-uninstall-postgresql-14.sh`. Replaced by `postgresql@17` in the brew preset; v14 became deprecated in homebrew so I dropped support for it
- Ghostty: `shaders/cursor-trail.glsl` deleted — superseded by `cursor-warp.glsl`

### Changed

- Installer: `dotfiles update` now keeps Brewfile packages current — runs `brew bundle install --upgrade` (scoped to Brewfile entries, not system-wide), gated by a `brew bundle check` precheck that no-ops when nothing is missing or outdated. Homebrew and packages steps no longer auto-skip on Brewfile-unchanged updates so upstream releases flow in
- Lazydocker: log timestamps in the project Logs tab and both popped-out viewers (`viewServiceLogs`, `viewAllLogs`) are now reformatted from RFC3339Nano (`2026-05-14T16:16:11.814096093Z`) to `05-14 16:16:11.814` by a sibling `format-logs.awk` symlinked next to `config.yml`. The single-container Logs tab still renders without timestamps because it streams directly from the Docker API and can't be piped — `logs.timestamps` stays `false` to avoid the ugly raw format there. Since `lazydocker/config.yml` is copy-on-install, existing users must apply the new `commandTemplates` block by hand (the `format-logs.awk` symlink is created automatically on next `dotfiles update`)
- gh-dash: `m` squash & merge keybinding moved from `local.yml.template` to `config.yml.template` so it ships as part of the base config. Leaving the binding in both files would have caused yq's `*+` array-merge to duplicate it. Migration `0.2.92-ghdash-squash-promote.sh` strips the entry from existing `local.yml` files (preserving any sibling keybindings the user added) and cleans up empty `keybindings`/`prs` containers it leaves behind
- Tmux: `terminal-features "*:RGB"` (was a hand-rolled `terminal-overrides`) plus `extended-keys-format csi-u` so tmux re-emits Ghostty's kitty u-form sequences instead of xterm form, which was leaking tail bytes like `3~` into zsh
- Tmux: `Ctrl+Enter` / `Ctrl+Shift+Enter` are passed through to the inner program instead of bound to prev/next window. `M-[` / `M-]` (Opt+`[`/`]`) remain the navigation chord — extended-keys consumed both forms and leaked tail bytes when only the navigation form was bound
- Nvim: Telescope clear-prompt moved from `<C-u>` to `<C-l>` — frees `<C-u>` for native delete-to-start-of-line and matches shell behaviour
- Nvim: Oil `-` closes the buffer and `<BS>` walks up a directory (was `q` for close, no `<BS>`). Keeps `-` symmetric with the global open-Oil binding
- Nvim: cheatsheet reflects the new Oil bindings and the corrected `<leader>pP` (was `<leader>pp`) for PR approve
- Scripts: `fzf-theme.sh` caches its baked exports to `$XDG_CACHE_HOME/dotfiles/fzf-env` and source-fasts on subsequent calls (~1ms vs ~10ms). Invalidated by mtime against the active theme, `theme-defaults.sh`, and ghostty config. `TMUX_ACCENT_*` and `NVIM_COLORSCHEME` are now exported so popup-spawned tmux scripts pick them up without re-sourcing
- Zsh: PATH dedupe (`typeset -U path PATH`) moved to the top of `~/.zprofile`; dropped the redundant `~/.local/bin` and `~/.local/launchers` exports — the framework already adds both, and the duplicates were leaking into `$PATH`
- btop: `save_config_on_exit` flipped to `true`. `btop/btop.conf` is copy-on-install, so existing users must apply the flip by hand

## [0.2.91] - 2026-05-08

### Changed

- CLI: theme application now requires an explicit `switch` subcommand — `dotfiles theme switch dracula` instead of `dotfiles theme dracula`. The bare `dotfiles theme <name>` form is gone, so theme names no longer collide with subcommands (`list`, `current`, `generate`, `delete`) in tab completion. `dotfiles theme` with no args still defaults to `list`
- CLI: `dotfiles <cmd> help` now works as an alias for `dotfiles <cmd> --help`, mirroring the existing `dotfiles help <cmd>` form — all three forms reach the same per-command help. Excluded for `theme`, whose subcommand dispatcher delegates `help` down to child scripts (`theme delete help`, `theme generate help`)
- CLI: `dotfiles aliases` cheatsheet now hides aliases without a trailing description comment, so platform-conditional twins (Linux `pbcopy`/`pbpaste`), thin `cl &&` wrappers (`ralph`, `ralf`, `btop`), and shorthand duplicates (`oc`, `dot`, `alerts-clear`) drop out of the rendered cheatsheet rather than appearing twice. The test suite pins the omission set so removing a description by accident re-renders an alias and fails CI
- Tmux: unbound default `z` (zoom-pane) — clashed with `Opt+z` in the existing keymap

### Added

- Nvim: Octo review inline word-change highlights (`OctoReviewDiffDeleteText`/`OctoReviewDiffAddText`) now use the diff red/green tints from the active theme — previously they fell through to Octo's defaults and clashed with the surrounding diff palette
- Themes: generated colourschemes override `@lsp.type.field` to plain `fg_primary` — without this, LSP fields fell through to `@variable.member` (cyan) and rendered identically to properties

### Fixed

- CLI: `dotfiles links` no longer reports `~/.p10k.zsh` as MISSING — `p10k.zsh` was migrated to a user-owned copy in v0.2.57, but the symlink check lingered and flagged MISSING on every install

## [0.2.90] - 2026-05-06

### Added

- Nvim: `<leader>dT` opens a Diffview between the oldest and newest commits on the current branch whose messages match a ticket grep — same combined two-rev view as `<leader>do`, but scoped to a ticket. Prompts for the grep string with a default extracted from the branch name (matches an `ACME-1234`-style prefix), runs `git log --grep=<ticket> --fixed-strings` between `merge-base main HEAD` and `HEAD`, then opens `oldest^...newest`. Caveat: non-matching commits sandwiched between matching ones get folded into the diff
- Brew: `scc` (fast source-code line counter) added to the dev preset

### Fixed

- Nvim: markdown-nvim's `+`/`-` heading bumpers (`MkdnIncreaseHeading`/`MkdnDecreaseHeading`) are disabled — `-` was shadowing Oil's global parent-directory keymap inside markdown buffers. Renumbering still available via `<leader>mn`

## [0.2.89] - 2026-05-03

### Added

- Nvim: tag-pair auto-rename — any edit to a tag name in `markdown`/`html`/`xml`/`svg`/`vue`/`svelte`/`astro`/`jsx`/`tsx`/`php` propagates to the matching opening or closing tag. Motion-agnostic: `c{any motion}` (`ciw`, `cfn`, `c$`, `cit`, ...), `r{char}`, `R`, `s`/`S`, dot-repeat, macros, and multi-cursor edits all flow through. Snapshots on `ModeChanged` (catches the operator the moment it's pressed, before any text is touched) plus `CursorMoved`/`InsertEnter`/`BufEnter`/`FileType` for the cursor-already-on-tag cases; sync runs from `TextChanged`/`TextChangedI`. Regex-based (no treesitter), so it works the same in markdown's html injections as it does in jsx — no parser timing issues, no injection-range fragility. Multi-line tag bodies are supported, so JSX's `<div\n  className="x"\n>` pairs with `</div>`. Lives in `core/tag-rename.lua`, wired from `init.lua`

### Fixed

- Nvim: `]q`/`[q`/`]l`/`[l` no longer oscillate between two entries that share the cursor's `bufnr+lnum` (e.g. multiple diagnostics on one line) — `sync_list_idx_to_cursor` now keeps the current idx when it already points at one of the matching entries instead of snapping to the first match every press
- Nvim: `build.lua`'s qf/loclist auto-clear preserves the list's current-entry idx across the rebuild — `setqflist({}, 'r', ...)` reset idx to 1, so the next `]q` jumped back to the top instead of advancing to the next outstanding issue. The pruner now snaps idx to the nearest surviving predecessor when the entry the user was on is the one resolved
- Nvim: `build.lua`'s auto-clear no longer wipes still-valid qf entries on the LSP's initial `DiagnosticChanged` for a buffer the user hasn't edited yet — pruning is gated on `changedtick` having advanced past a per-buffer baseline recorded the first time we observe diagnostics for the buffer. Without this, a `]q` jump into a fresh buffer fired the initial publish and wiped entries whose source (build output, sonar scan, modified-scan snapshot) didn't overlap with the publish's line set. Baseline is cleared on `BufWipeout`/`BufDelete`
- Nvim: noice's `lsp.hover` now sets `silent = true` so a successful hover popup no longer fires a redundant "No information available" notification alongside the popup itself

## [0.2.88] - 2026-04-30

### Added

- Tmux: `prefix + C` opens a Codex instance switcher with the same picker UX as Claude/OpenCode — list running instances, create new ones, kill existing ones. Codex CLI hooks now wired up (`Stop`/`PermissionRequest` trigger alert, `UserPromptSubmit` clears it); uses `codex-alert.sh` / `codex-alert-clear.sh` wrappers
- Nvim: macOS-style cmdline word-movement keymaps — `<M-Left>` / `<M-Right>` and `<M-b>` / `<M-f>` now work in command-line mode (`c` mode) just like they do in insert mode, jumping by word with Option/Alt arrow keys

### Changed

- Shell: zoxide now initializes via `eval "$(zoxide init --cmd cd zsh)"` instead of plain `zoxide init zsh` — `cd` keeps normal path semantics for real directories while still falling back to zoxide matching for non-path queries;
- Nvim: fidget's `progress.ignore` now drops `sonarlint.nvim` LSP progress unconditionally — sonarlint analyses on every `BufEnter` for one of the 18 supported filetypes, so the per-file progress toast was spammy outside review too. The manual `<leader>ls` / `<leader>lS` scan uses a separate `sonar-scan` client name and stays visible. Errors and the "ready and running" bootup notice still flow through `vim.notify`

### Fixed

- Nvim: quickfix navigation opened empty buffers for projects with a build subdirectory (e.g. a `web/` TypeScript workspace inside a monorepo git root). `setqflist({lines=...})` resolves tsc's relative paths against neovim's CWD (the git root) rather than `build_dir`, producing absolute paths missing the subdirectory prefix. `repair_qf_paths` / `resolve_real_path` now strip the CWD prefix and re-resolve against `build_dir` as a fallback, and `bufnr` is zeroed on unresolvable items so neovim doesn't navigate to a wrong empty buffer. `open_git_modified` now also wipes scan-created buffers in `on_finalise`, mirroring the sonarlint pattern
- Nvim: `gra` code actions and `grf` fix-all now explicitly refresh diagnostics after applying edits, so diagnostics-backed quickfix/location lists prune resolved entries immediately instead of waiting for the LSP to republish on its own
- Nvim: `]q`/`[q` and `]l`/`[l` now work while a `noice` LSP/docs popup is focused — the wrappers in `lists.lua` resolve back to the last non-`noice` window before syncing mini.bracketed's cursor-relative idx, so quickfix/location navigation still follows the underlying editing window
- Nvim: Roslyn diagnostic noise inside XML doc comments — style/suggestion-level diagnostics (`HINT`/`INFO`) whose span lands on a `///` line are now filtered out in `patch_diagnostic_set()`. This removes "Name can be simplified" hints on `<see cref="...">` targets while keeping real warnings/errors for malformed XML docs or compiler issues

## [0.2.87] - 2026-04-29

### Added

- Nvim: octo.nvim review cache — session-local snapshot of `PullRequest.get_changed_files` and per-file `FileEntry.fetch`, keyed by `repo:number:left:right`. Reopening the same PR review (or `<leader>pe` resume) skips the GraphQL roundtrip, so resume is instant on warm cache. `:OctoCacheClear` purges manually; stale entries auto-prune when a fresher fetch lands
- Nvim: octo.nvim review diff buffers now soft-wrap (`wrap` + `linebreak` + `breakindent`) — `:diffthis` forces `wrap=off` with no `diffopt` knob, so an `OptionSet diff` autocmd re-applies the options synchronously for `octo://` buffers. Mirrors diffview's wrap behaviour
- Nvim: tpope plugin set — `vim-fugitive` + `vim-rhubarb` (`:Git`, `:Gdiffsplit`, `:GBrowse`) wired into `plugins/git.lua`. New `plugins/tpope.lua` bundles `vim-abolish` (`:Subvert`, `cr*` coercions), `vim-repeat`, and `vim-sleuth`. Surround/commentary/unimpaired skipped — already covered by `mini.surround`, built-in `gc`, `mini.bracketed`
- Nvim: fugitive keymaps under `<leader>G*` — `Gs` status, `Gb` blame, `Gd` diffsplit, `Gl` file log → qf, `Gw` write/stage buffer, `Go` GBrowse (visual opens with line range). Capital `G` mirrors `<leader>H*` (gitsigns); lowercase `<leader>g` stays the LazyGit shortcut
- Nvim: `cheatsheet.txt` gains `## fugitive @fugitive` and `## coerce @coerce` sections — fugitive maps + abolish `cr*` coercions and `:Subvert` discoverable via `<leader>?`
- Nvim: `astro` added to mason-lspconfig, mason-tool-installer, and the treesitter parser list — Astro files get LSP diagnostics/completion plus syntax highlighting out of the box
- Nvim: conform.nvim formats `.astro` via `prettier` (was falling back to the astro LSP's bundled formatter, which drifted from `bunx prettier . -w`). Sets `prefer_local = 'node_modules/.bin'` on the prettier formatter so all prettier-driven filetypes resolve plugins and version pins from the project's `node_modules`
- Nvim: `<leader>x[` / `<leader>x]` walk the quickfix stack (`:colder`/`:cnewer`) — every `:Cfilter` pushes a new list, so `<leader>x[` undoes the last filter (or any other push). Counts honoured (`3<leader>x[` → `:3colder`); edge cases notify "At oldest/newest quickfix list". Built-in `cfilter` plugin loaded via `packadd cfilter`

### Changed

- Nvim: `<leader>pe` (`Octo review resume`) resumes at the file + cursor line you were editing if it's part of the PR — captures the buffer's relative path + line, then a patched `Review:set_files_and_select_first` selects the matching `FileEntry` and restores the cursor on the right pane. Falls through to first-unviewed-file when the current buffer isn't in the PR
- Nvim: `sonarlint.nvim` auto-suppresses on PR review buffers (`octo`, `DiffviewFiles`, `DiffviewFileHistory`) and restores when leaving — mirrors `roslyn.nvim`'s behaviour. Logic lives in `sonarlint.lua` to keep review-context handling per-plugin
- Nvim: LSP nav (`gd`, `gr`, `gI`, `gT` via `lsp_dedup`) no longer pollutes the quickfix list. Single-result jumps go straight through `vim.lsp.util.show_document` (was `setqflist` + `:cfirst`); multi-result picks use a standalone telescope picker (was `setqflist` + `telescope.builtin.quickfix`). Results also exclude the cursor's current location, so `gd` on a definition no longer lists the cursor itself

### Fixed

- Nvim: sonarlint.nvim's `$MASON` path expansion replaced with `vim.env.MASON or vim.fn.stdpath('data') .. '/mason'` — `vim.env.MASON` is only set after `mason.setup()` runs, and sonarlint.nvim doesn't depend on `mason.nvim`, so lazy-loading via `ft = FILETYPES` could outrun mason's setup. The launch command then became `sonarlint-language-server -stdio -analyzers` with no jar paths and the server exited with code 2 (`Missing required parameter for option '-analyzers'`). Affected `analyzer_jars()`, `extension_dir`, and `csharpOssPath`
- Nvim: conform's `csharpier` formatter args pinned to `{ 'format', '--stdin-path', '$FILENAME' }` (with `stdin = true`). conform's default args switch on `dotnet csharpier --version` and emit `csharpier format --stdin-path $FILENAME` -- correct only when the command is `dotnet`. We override `command` to Mason's standalone binary, so those args get passed directly and csharpier 1.0+ failed with `Unrecognized command or argument 'csharpier'`
- Nvim: cold-start `<leader>do` from a dashboard no longer freezes the editor for ~15s waiting for cs-plugin lazy-loads to finish. Two changes: (1) `mason-lspconfig.setup{}` and `mason-tool-installer.setup{}` are now deferred via `vim.schedule` inside `nvim-lspconfig`'s config — they don't need to block `BufReadPre`, and the cold-path BufReadPre time dropped from ~14s to ~30ms; (2) `roslyn.nvim` lazy-loads on a `User RealDotnetFile` event (fired by `core/autocmds.lua` for `cs`/`razor` buffers only when no diffview/octo review context is active) instead of `ft = 'cs'` — diff buffers no longer trigger its ~1.1s config function. The cost is paid later when the user actually edits a real `.cs` file (feels like normal "opening a code file"), or never if they only review the diff. Total cold `<leader>do` profile: ~360ms instead of the previous ~14s+
- Nvim: `<leader>de` re-attaches treesitter on the destination buffer after `:edit` (diffview and octo paths) — some `:edit` transitions left treesitter unattached so highlights rendered raw. `vim.treesitter.start(0)` runs in `vim.schedule`; skipped when the filetype has no parser or `vim.treesitter.highlighter.active(0)` already reports a live highlighter (unconditional `start` re-parses and flickers on large files)
- Nvim: sonarlint suppression gate actually installs now — `nvim_get_autocmds` splits multi-pattern autocmds into one entry per pattern, so the previous `ac.pattern == table.concat(FILETYPES, ',')` check never matched and JVM still respawned on `<leader>de`'s `:edit` into a `.cs` file from diffview. Replaced with a count-based match that picks the autocmd id whose entries cover the most of FILETYPES. Supersedes the previous "44× speedup" entry — that was a warm-cache artefact
- Nvim: all `vim.notify` filtering for sonarlint/roslyn/dotnet now lives in a single wrap inside `ui.lua`'s fidget config — fidget's `override_vim_notify = true` blew away module-level wraps installed by `sonarlint.lua`/`dotnet.lua`. The consolidated wrap consults `vim.g.{sonarlint,roslyn}_suppressed`, drops chatter (message body and `opts.title`), and keeps the dotnet startup-spam filter
- Nvim: fidget's `progress.ignore` drops sonarlint/roslyn LSP progress while their `vim.g.<name>_suppressed` flags are true — analysis progress used to fire a fidget toast on every `]f`/`[f` inside diffview/Octo review. Filter is conditional so progress still shows outside review
- Nvim: roslyn no longer stops or restarts on review entry/exit — `suppress_roslyn` is now a flag-flip (`vim.g.roslyn_suppressed`). The earlier `vim.lsp.enable('roslyn', false)` stopped clients per its contract, costing a multi-second cold-restart per cycle plus a freeze when `RoslynInitialized` fired `force_refresh` on every loaded `.cs` buffer. Review buffers use `nofile`/`nowrite` so Neovim's `lsp_enable_callback` already skipped them — auto-attach was never the concern. `try_restore_roslyn`/re-enable cycle gone; `maybe_clear_roslyn_flag` (`BufEnter *.cs`, 500ms defer) clears the flag after review tears down
- Nvim: sonarlint/roslyn suppression keep existing LSP clients running on pre-review buffers — `<leader>de` no longer pays a JVM/Roslyn cold-start. Sonarlint relies on its FileType-handler gate to block new attaches; roslyn relies on Neovim's built-in buftype check
- Nvim: local `roslyn_suppressed` flag promoted to `vim.g.roslyn_suppressed` so fidget's progress filter can read it (sibling to the existing `vim.g.sonarlint_suppressed`)
- Nvim: `<leader>xx`/`<leader>xX` now pass explicit `Diagnostics: all`/`Diagnostics: buffer` titles, and `build.lua`'s `setup_auto_clear` extends to loclists. The default `Diagnostics` title (no colon) failed the `^(%w+):` predicate, so resolved entries lingered. `Diagnostics` joins `Build`/`Sonar`/`Modified` in `AUTO_CLEAR_KINDS`; the loclist branch runs `:lclose` per-window when the list empties
- Nvim: built-in `document_color` disabled globally — assertion failures on stale client IDs (`document_color.lua:225: assertion failed!`). The previous `caps.textDocument.colorProvider = nil` was ineffective because `document_color` attaches based on the _server's_ capability advertisement (e.g. `tailwindcss` on TSX), not the client's
- Nvim: `<leader>xm` skips paths that fail `filereadable` — `git ls-files -m` includes deleted-but-unstaged entries, and creating buffers for non-existent C# files triggered `easy-dotnet.nvim`'s `BootstrapFile` to crash with `-32000`
- Nvim: `patch_lsp_start` (the `vim.lsp.start` wrap that blocks attach on non-`file://` buffers) bails when the target bufnr is no longer valid — the wrap runs inside `vim.schedule`, and the buffer can be wiped between queue and fire (e.g. diffview disposing diff buffers), so `nvim_buf_get_name` raised `Invalid buffer id`
- Nvim: `<leader>xm` Roslyn pull gates behind `workspace/projectInitializationComplete` — pulling before init returned `-30099 Failed to get language`. Wraps the LSP method handler (Roslyn protocol contract, not `User RoslynInitialized`) so cold-start scans wait for init and warm-start scans pull immediately
- Nvim: `]q`/`[q`/`]l`/`[l` sync mini.bracketed's idx to the cursor's current file:line before navigating — the qf list's "current entry" idx only updates via `:cc`/`:cnext`/`<CR>`-in-qf, so landing on an entry via LSP jump, search, or a picker left the idx stale and the next `]q` skipped away from where the cursor actually was. Inside the qf window, the idx syncs to the cursor row instead
- Tmux: `windows/move.sh` renumbers the source session after moving a window out — `tmux move-window -r -s "$SOURCE_SESSION"` collapses the gap so `1 2 3` minus `2` becomes `1 2`, not `1 3`. Respects `base-index`
- Tmux: alert hooks no longer return 1 on windows whose names contain spaces — `alerts/clear.sh` and `_lib/alerts.sh`'s `set_window_alert`/`set_exit_alert` now split session vs. window validation: sessions keep `^[a-zA-Z0-9._-]+$`, windows accept any non-colon, non-control characters. Tmux derives window names from running commands so spaces are routine; the previous regex silently dropped alerts and made `after-select-window` hooks return non-zero. Colons stay rejected (alerts file's field delimiter)

## [0.2.86] - 2026-04-27

### Added

- Nvim: `sonarlint.nvim` wraps `sonarlint-language-server` (Mason) as a second LSP for SonarQube-style diagnostics — covers Python, JS/TS, Go, C#, C/C++, PHP, HTML/CSS, IaC, Docker, secrets, XML; lazy-loaded by filetype. Connected mode (SonarCloud, EU) auto-enables when `SONARQUBE_TOKEN` + `SONARQUBE_ORG` are set; per-project binding via `.sonarlint/connectedMode.json` at the project root, JetBrains/VSCode-style. Includes a local patch for an upstream bug in `find_server_url` that crashed on SonarCloud-only setups
- Nvim: Sonar project scan — `<leader>ls` scans changed/untracked files, `<leader>lS` scans the whole project (confirmation prompt above 500 files); both filter to sonarlint-supported extensions, hidden-load each file so sonarlint attaches, then snapshot diagnostics into a `Sonar:`-titled qf on 2 s of `DiagnosticChanged` quiet (5 min hard timeout). Fidget progress handle reports as a virtual `sonar-scan` LSP
- Nvim: `<leader>xm` / `:GitModified` — hidden-loads git-modified files, debounces on `DiagnosticChanged` (5 s / 5 min) and dumps diagnostics into a `Modified:`-titled qf without leaving the current buffer. Pulls `textDocument/diagnostic` explicitly on `LspAttach` for clients (roslyn) that only push for visible documents
- Nvim: `<leader>sm` telescope picker over `git_status` — modified + untracked files with diff previews
- Shell: `lc` alias for `cl && lazycron` — completes the `j`/`lg`/`ld` family of clear-then-launch TUI shortcuts

### Changed

- Nvim: `build.lua`'s qf auto-clear (drops items as their underlying diagnostics resolve) now also fires on `Sonar:`- and `Modified:`-titled lists; only the "all clear" notification text varies
- Nvim: `claude-prompt.lua` `<leader>c*` comment keymaps now activate on every markdown buffer; the `@` file picker and `@@` literal stay scoped to `claude-prompt-*.md` / files under `.claude/` or `.plans/`
- Nvim: `grr`/`gri`/`grd`/`grt` now surface a warning notification when the LSP returns no results — the previous `lsp_dedup` path relied on `vim.lsp.buf.<method>`'s `on_list` callback which Neovim's built-in handlers short-circuit on empty results, so location methods failed silently. Now drives `vim.lsp.buf_request_all` directly. `grr` also flips `includeDeclaration` to `false` so it warns on truly-unused symbols instead of jumping to the declaration
- Nvim: scan helpers unified into `core/scan_runner.lua` (~110 LOC of duplication removed across `sonarlint.lua` and `core/lists.lua`). Single global singleton — triggering `<leader>xm` while `<leader>ls` is running (or vice versa) reports `A scan is already running` instead of letting both write to the qf concurrently

### Fixed

- Shell: zoxide doctor warning silenced by overriding `__zoxide_doctor` with a no-op after `zoxide init zsh` — the check spuriously fires in Claude Code's `!` shell because shell snapshots capture function definitions without the `chpwd_functions` array; env-based `_ZO_DOCTOR=0` doesn't survive snapshotting, overriding the function does
- Tmux: launcher picker and wizard now strip shell-escape backslashes (`\ ` → space, `\~` → `~`) from pasted directory paths — fzf input is literal text, so escaped paths failed `[[ -d ]]` and got baked into the generated launcher's `PROJECT_DIR`. Pre-existing launchers need the backslashes stripped by hand
- Nvim: `lsp_dedup` (`grr`/`gri`/`grd`/`grt`) builds the `textDocument/position` payload per-client instead of broadcasting `clients[1].offset_encoding` to everyone — could land on the wrong byte for non-first clients in mixed-encoding setups (e.g. utf-8 rust-analyzer + utf-16 lua_ls) on lines with multibyte characters
- Nvim: sonarlint connected-mode `notify_connection_result` `tostring`-coerces and clamps `params.reason` to 200 chars — server-supplied field shouldn't bloat the notify log
- Nvim: `<leader>xm` modified-scan wraps `vim.fn.bufload` in `pcall` so a single un-loadable file (broken symlink, permission `000`) skips silently instead of aborting the whole scan

### Refactor

- Nvim: `build.lua`'s qf auto-clear `Build`/`Sonar` predicate collapsed into an `AUTO_CLEAR_KINDS` kind→label table — adding a new kind is a one-line addition. No behaviour change
- Tmux: 3 verbatim copies of the shell-escape strip block (`run.sh`, `new.sh` × 2) extracted into an `unescape_paste` helper. No behaviour change

## [0.2.85] - 2026-04-20

### Added

- Shell: `zoxide` (brewed) wired into zsh via `eval "$(zoxide init zsh)"` — provides `z`/`zi` smart `cd` with frecency-based directory jumping
- Shell: `j` alias for `cl && jiru` (Jira TUI), `lg` for `cl && lazygit`, `ld` for `cl && lazydocker` — quick launchers that clear scrollback first

### Changed

- Shell: `lazydocker` command is no longer pre-aliased to `cl && lazydocker` — use the new `ld` alias instead; the bare binary stays available for scripting

### Removed

- Shell: `h="cd ~"` and `j="jobs"` aliases — `h` was redundant with bare `cd`, and `j` is reclaimed for `jiru`

## [0.2.84] - 2026-04-20

### Added

- Tmux: status bar icons upgraded to Nerd Font glyphs — cpu (``), ram (``), and battery (`` charged / `` charging / `` discharging / `` attached / `` unknown). Layout, theme variables, and the dotfiles sync indicator on the left are untouched
- Nvim: build runner resolves task-runner-prefixed paths in monorepos — efm captures like `@scope/pkg:task: src/foo.ts` are stripped progressively and searched against the build dir (and one level of package subdirs, skipping `node_modules`/`.git`/`dist`/`build`/`.next`/`.turbo`), so quickfix entries from turbo/nx pipelines navigate to real files
- Nvim: build quickfix auto-prunes as diagnostics are resolved — on `DiagnosticChanged` for an LSP-attached buffer, qf items on lines without a diagnostic are dropped from any `Build:`-titled list; when the list empties, qf windows close and a `Build errors resolved` notification fires

## [0.2.83] - 2026-04-17

### Added

- Shell: `carapace` multi-shell completion provider (brewed under `@preset: minimal`) — bridges zsh's native completion system so built-in completers still work, sourced via `_cached_eval` so `carapace _carapace` forks once per day instead of every shell start (~40ms saved); `zstyle ':completion:*' menu select` + `group-name ''` added. Description colouring is applied via `carapace --style 'carapace.Description=cyan'` which persists to `~/Library/Application Support/carapace/styles.json` (macOS) / `~/.config/carapace/styles.json` (Linux)
- Nvim: `obsidian.nvim` vault integration — auto-discovers workspaces under `~/Library/Mobile Documents/iCloud~md~obsidian/Documents`, daily notes (`<leader>oo`/`oy`/`oT` with `DD-MM-YYYY` date format and `daily note.md` template), find/search/tags/backlinks/links (`<leader>of`/`os`/`ot`/`ob`/`ol`), new note/template/rename/extract/workspace (`<leader>on`/`oi`/`oN`/`or`/`oe`/`ow`); markdown rendering stays owned by `mkdnflow` in `markdown-ui.lua`
- Nvim: native quickfix/loclist workflow — `<leader>xq`/`<leader>xl` toggle, `<leader>xx` dumps workspace diagnostics to quickfix, `<leader>xX` dumps buffer diagnostics to loclist, `<leader>xcq`/`<leader>xcl`/`<leader>xcc` clear quickfix/loclist/both; Telescope `<C-q>`/`<M-q>` send all/selected to quickfix and `<C-g>`/`<M-g>` to loclist
- Nvim: gopls code lens auto-enabled on attach — `<leader>ll` runs the lens under cursor, `<leader>lL` refreshes; enabled `generate`, `regenerate_cgo`, `test`, `tidy`, `upgrade_dependency`, `vendor`, `run_govulncheck` lenses (other languages skipped — above-line rendering clashes with nested declarations)
- Nvim: `<leader>Q` pick a Make target (previously only `<leader>q` to run the detected build)
- Nvim: ripgrep wired into `grepprg`/`grepformat` when `rg` is available (`rg --vimgrep --smart-case`)
- Tmux: `` ` \ `` rotates through panes (binds `rotate-window`, the default `C-o` action) — also documented in the help overlay
- Nvim: `gx` override in `custom/core/keymaps.lua` that strips wrapper chars (`<>`, `()`, `[]`, quotes) from URLs before handing off to `vim.ui.open` — fixes markdown autolinks like `<https://example.com>` failing to open in buffers where the `markdown_inline` treesitter query didn't strip the brackets

### Changed

- Nvim: neo-tree hides `.DS_Store` via `never_show` (filesystem source) — macOS finder metadata stays out of the tree even with `hide_dotfiles = false`
- Nvim: `obsidian.nvim` vault root is now overridable via `vim.g.obsidian_vault_root` (settable in `local.lua`); falls back to the default iCloud path, and the plugin spec is returned empty (plugin not loaded) if neither exists — makes the config portable to non-iCloud machines. Override documented in `nvim/local.lua.template`.
- Nvim: build/diagnostics flow switched off Trouble onto native quickfix — build failures now open `botright copen`, and `<leader>x*` bindings target quickfix/loclist directly
- Nvim: build progress now uses a `fidget.progress` handle (reported as LSP client `build`) instead of a replace-based notification; final success/failure still surfaces via `vim.notify`
- Nvim: macro recording state surfaces in the `mini.statusline` mode section (`@reg`), with a guarded redraw on `RecordingEnter`/`RecordingLeave`
- Nvim: `]q`/`[q` and `]l`/`[l` (mini.bracketed quickfix/location nav) now silence the `:cnext`/`:cprev` echo via `:silent!`
- Nvim: `<leader>sl` (go-to-line telescope) removed from the cheatsheet; line-number jump is native

### Removed

- Brewfile: `gotermsql` (superseded by the existing `seanhalberthal/tap/seeql` SQL TUI)

### Refactor

- Nvim: split the monolithic `custom/plugins/editor.lua` into single-concern plugin modules — `buffers`, `completion`, `dial`, `mini`, `multi-cursor`, `navigation`, `paste`, `search`, `treesitter`
- Nvim: extracted focused core modules from `custom/core/keymaps.lua` — `folding`, `lists`, `macos-nav`, `refresh`, `windows`; `keymaps.lua` is now a slim entry point that wires the focused modules together
- Docs: `.claude/rules/neovim.md` updated to reflect the new module layout and the keymaps-ownership rule (each focused module owns its own keymaps)

## [0.2.82] - 2026-04-14

### Added

- Nvim: gopher glyph (`nf-seti-go`) for Go filetype + `.go` extension in `mini.icons`
- Nvim: `csharpier` registered as a conform formatter (uses the Mason-installed binary)
- Tmux: `focus-events on` — forwards terminal focus into panes so nvim `:checktime` autoreload, Claude Code focus tracking, and unfocus-pausing TUIs work inside tmux
- Brewfile: `seanhalberthal/tap/seeql` SQL client TUI

### Changed

- Nvim: enable experimental `vim._core.ui2` — messages appear in a floating window that auto-dismisses after 4 seconds; `cmdheight` set to 0 to reclaim the bottom row; manual cmdline-clearing autocmd removed (superseded by `ui2` timeout)
- Nvim: `shortmess += I` to suppress intro screen flash caused by `cmdheight=0`
- Nvim: lazy-load triggers on `blink.cmp` (`InsertEnter`/`CmdlineEnter`), `nvim-lspconfig` (`BufReadPre`/`BufNewFile` + Mason `cmd`s), `gitsigns.nvim` and `mini.nvim` (`VeryLazy`) to defer plugin work past the initial UI paint
- Nvim: treesitter missing-parser install now blocks up to 120s (`:wait(120000)`) so parsers are ready before highlighting attaches on first open
- Nvim: conform `notify_on_error` flipped to `true` so formatter failures surface instead of silently dropping

## [0.2.81] - 2026-04-12

### Added

- Nvim: `fidget.nvim` for LSP progress + `vim.notify` backend (replaces `nvim-notify` for notifications)
- Nvim: `.luarc.json` generation from `.luarc.json.template` during install — resolves machine-specific VIMRUNTIME path via `nvim --headless`, fixes hover/completion for `vim.*` API across fresh clones
- Nvim: `lazy.nvim` `dev = { path = '~/playground', fallback = true }` for local plugin development
- Nvim: smart `i`/`a` on empty lines — falls back to `"_cc` so the cursor lands at the correct indent level (respects `indentexpr`/treesitter) instead of column 0
- Core: Ghostty transparency detection across nvim theme, tmux status bar, and fzf preview — auto-clears backgrounds when `background-opacity < 1`

### Changed

- Nvim: slimmed down plugin set — removed `flash.nvim`, `nvim-notify`, `lazydev.nvim`, and the dead `discord.lua` module; `noice.nvim` trimmed to LSP hover + signature help only
- Nvim: restored native `s`/`S` (substitute) by dropping `flash.nvim`; navigation now relies on `f`/`t`/`/` + `;`/`,` repeat
- Nvim: `vim.api.nvim_err_writeln` → `vim.api.nvim_echo(..., { err = true })` (deprecated API cleanup in keymaps.lua and pr-review.lua)
- Nvim: `pcall(vim.cmd, 'string')` → `pcall(function() vim.cmd(...) end)` to satisfy lua_ls type checks (keymaps.lua, markdown-ui.lua)
- Nvim: cheatsheet updated to document native `f`/`t`/`/` motions in place of flash keybindings, plus nvim 0.12 visual-mode treesitter node selection (`an`/`in`/`]n`/`[n`)
- Nvim: mkdnflow — section fold/unfold moved to `zc`/`zr` (markdown-buffer-local, overrides global fold keys only in markdown); added table insert/delete keymaps (`<leader>mi*` / `<leader>md*`) and clipboard link (`<leader>ml`)
- Nvim: spellcheck — `zw` ("mark word as misspelled") remapped to `zW` to prevent accidental marking; `zw` is now a no-op

### Fixed

- Nvim: gopls no longer spams `JSON RPC parse error: DocumentURI scheme is not 'file'` when opening Go files inside diffview — `vim.lsp.start` is wrapped to skip attachment on any non-`file://` buffer (covers `diffview://`, `octo://`, `fugitive://`, etc.)
- Nvim: `<leader>de` no longer freezes on the keypress in large C# projects — the `FileType cs` restore path now defers `try_restore_roslyn()` by 500ms so `:edit` returns instantly and the file paints before Roslyn's (unavoidable) solution-load blocks the main loop

## [0.2.80] - 2026-04-09

### Added

- Nvim: `fg_variable` theme colour — variables now render distinctly from Normal text across all 14 themes, derived via 10% blend with palette accent + 4.5:1 contrast check
- Nvim: Roslyn semantic token fixes — built-in C# types (`string`, `int`, `bool`, etc.) remapped to `@type.builtin`; attribute names inside `[brackets]` remapped to `@attribute`
- Nvim: spellcheck module (`custom/core/spellcheck.lua`) — auto-correct word (`<leader>Sc`), line (`<leader>Sl`), and buffer (`<leader>SB`)
- Nvim: undo tree (`<leader>u`), treesitter refresh (`<leader>lt`), harpoon `o` to open
- Nvim: DAP scopes — `<CR>`/`o` to expand, disabled accidental edit/open mappings
- Nvim: treesitter large-file skip (>1MB), query directory cleanup on parser purge
- Nvim: fold aliases — `zr`→open all, `zc`→close recursive, `zm`→close all with silent error handling
- Ghostty: background image support (`ghostty/background-images/`)

### Changed

- Nvim: gitsigns keymaps consolidated under `<leader>H` — blame (`<leader>Hb`/`<leader>HB`), inline diff (`<leader>Hi`) moved from `<leader>d`/`<leader>t`
- Nvim: inlay hints toggle moved to `<leader>lh`; theme reload keymap removed
- Nvim: comment block keymaps (`<leader>c*`) moved from core keymaps to `claude-prompt.lua` (buffer-local to plan/prompt files)
- Nvim: `<leader>lR` refresh — notify wrapper now restores `vim.notify` after 3s instead of leaving wrapper in place
- Nvim: LSP capabilities merge — `blink.cmp` caps merged with Neovim defaults so semantic tokens and document highlights aren't dropped
- Nvim: `@lsp.type.variable` linked to `@variable` so LSP variable tokens inherit treesitter styling
- Nvim: removed diffview treesitter pre-warming on `<leader>de` (was blocking editor on large files)
- Nvim: diffview fold compatibility — fold commands synced across both diff panels; `diffview_ignore` mappings hidden from which-key
- Nvim: command-line auto-clear timer increased from 1s to 4s
- Lazydocker: added `--no-log-prefix` to all log command templates for cleaner output
- Tmux: agent alert icons switched from emoji to Nerd Font glyphs
- Docs: removed per-component READMEs (ghostty, hammerspoon, karabiner, nvim, tmux, zsh) — consolidated into main README

### Fixed

- Nvim: `autocorrect_range` stall guard — loop now breaks if cursor doesn't advance
- Nvim: `<leader>lR` repeated use no longer chains notify wrappers

## [0.2.79] - 2026-04-04

### Added

- Nvim: replaced easy-dotnet LSP with roslyn.nvim for C# diagnostics — real-time inline diagnostics, pull diagnostic support, cross-namespace dedup, false positive filtering (IDE0005, IDE0079, CA1825)
- Nvim: .NET tests now use easy-dotnet.nvim's built-in test runner — gutter signs, run/debug from buffer (`<leader>tr`/`<leader>td`), test explorer (`<leader>te`), peek stacktrace (`<leader>tp`)
- Nvim: roslyn auto-suppression during Octo PR review and diffview — re-enables when opening a real .cs file
- Nvim: replaced fidget.nvim with nvim-notify for LSP progress, build status, and refresh messages
- Nvim: Octo improvements — review thread navigation (`]C`/`[C`), viewed file tracking (`<Tab>`, `]u`/`[u`), file panel `l` keymap, left-side diff highlight fix, `BufModifiedSet` save guard
- Nvim: which-key tiered display — leader popup shows only category groups; context groups gated to relevant filetypes; PR Review always visible; consistent icon colour scheme (blue=navigation, green=tooling, red=editor, purple=AI, yellow=misc)
- Nvim: which-key Claude icon uses custom orange highlight (`#ff9e64`) distinct from yellow `DiagnosticWarn`; `<leader>b` label updated to `[B]reakpoint / Buffer`
- Nvim: neotest-vitest monorepo support — resolves vitest binary from nearest `node_modules` with cached subdirectory fallback
- Nvim: statusline — `~/` relative paths, compact diff (`+N -N`), mini.icons for filetype/git icons, removed LSP server count
- Nvim: editable breakpoint list (`<leader>bl`), `<leader>by` yank buffer path, Flash treesitter (`S`)
- Nvim: VimLeavePre cleanup — stops LSP clients, terminates DAP, closes terminal buffers to prevent orphaned processes
- Nvim: test explorer nav trapping — `<C-h/j/k/l>` blocked in floating windows, `<Esc>` closes peek floats
- Zsh: `nuke-nvim`, `nuke-dotnet` aliases; `MSBUILDDISABLENODEREUSE=1`; `btop`, `lazydocker`, `dash` aliases

### Changed

- Nvim: `dd` deletes without yanking (black hole register); `dy` yanks and deletes (original `dd` via operator-pending `y` = current line motion)
- Nvim: diffview — instant tab close, `]f`/`[f` as buffer-local keymaps, disabled `<leader>` defaults that stole which-key prefix, treesitter pre-warming on `<leader>de` for instant highlighting
- Nvim: which-key `BufEnter` caches visibility state and skips `buftype ~= ''` buffers to avoid trigger removal during rapid transitions
- Nvim: `<leader>lR` refresh noise suppressed via timestamp-based filter
- Nvim: smart-paste, conform, dial.nvim guarded against non-modifiable buffers
- Nvim: neotest — summary keymaps (`o` expand, `p` output), output preview UX, keymaps skip `.cs` files
- Nvim: mini.icons setup with YAML, `.template` icons; `.template` filetype detection
- Nvim: Neo-tree `o` opens immediately (order-by moved to `O` prefix)
- Nvim: markdown-preview — removed `ft` trigger to prevent eager loading
- Nvim: cmdline completion hidden by default, Tab triggers and cycles, Ctrl+Space as alternative
- Nvim: notification history viewer — dynamic height and line wrapping
- Nvim: Mason custom registry (Crashdummyy) for Roslyn LSP auto-install

### Fixed

- Nvim: roslyn semantic tokens flashing/disappearing — Neovim 0.12's `semanticTokens/range` requests caused viewport-only responses to replace full-document tokens; fixed by intercepting `client/registerCapability` to strip range registrations
- Nvim: roslyn semantic tokens on first load — refreshes tokens on `RoslynInitialized` event (project init complete) since roslyn doesn't send `workspace/semanticTokens/refresh` after solution loads
- Nvim: roslyn not restoring after diffview close — uses `diffview.lib.get_current_view()` instead of buffer filetype scanning (lingering buffers blocked restore)
- Nvim: which-key intermittently not showing in diffview panels — permanent `<Space>` keymap bypasses which-key's trigger suspension windows
- Nvim: roslyn diagnostic dedup — ignores message variations across push/pull channels and multi-project contexts
- Nvim: neotest-golang — unpinned from v1.15.1 to v2+ (supports current Go treesitter parser)
- Tmux: alert picker same-session navigation fix

### Removed

- Nvim: neotest-dotnet adapter and monkey-patch workaround
- Nvim: `<leader>ni` add missing imports (roslyn.nvim handles Fix All natively)
- Nvim: fidget.nvim (replaced by nvim-notify)
- Nvim: easy-dotnet.nvim `^M` strip monkey-patch — merged upstream (GustavEikaas/easy-dotnet.nvim#883)

## [0.2.78] - 2026-04-01

### Added

- Nvim: harpoon2 for quick file slot navigation (`<leader>1`–`4` to jump, `<leader>ha` to add, `<leader>hh` to toggle menu)
- Nvim: `<leader>dt` diff-by-branch command — diffs all commits since branching from main using `git merge-base`
- Tmux: alert picker (`prefix+A` / click status-right) with fzf integration — jump to alerting windows, `x` to clear individual alerts, search with `/`
- Ghostty: custom shader collection (bloom, CRT, cursor-trail, galaxy, matrix, retro, starfield) with examples in local template

### Changed

- Nvim: LSP modernised — mason-lspconfig v2 `automatic_enable`, `vim.lsp.config` for global capabilities, cssls Tailwind v4 at-rules support
- Nvim: switched from mini.notify to nvim-notify for notification handling
- Nvim: .NET diagnostics — Roslyn pull diagnostic workaround with workspace diagnostics on save, csharpier/gofumpt formatters added
- Nvim: `C-j`/`C-k` navigation added to Telescope results, completion menu, cmdline completion, and Neo-tree (file browser + fuzzy finder)
- Nvim: git hunk prefix moved from `<leader>h` to `<leader>H` (freeing `h` for harpoon)
- Nvim: pr-review diffview auto-closes existing view before opening a new one
- Nvim: `<C-BS>` mapped to delete-word-back in command mode
- Ghostty: keybindings moved from `theme-switch` into `config.template` using `{{PLATFORM_MOD}}` placeholder
- Ghostty: added `super+backspace` keybind (kill line) and `window-theme = ghostty`
- Tmux: responsive popup sizing for rename and kill windows (fixed size on wide terminals, 95% on narrow)
- Tmux: Claude instance logo colour changed to pink (`#D78787`)
- Lazydocker: fixed YAML structure — `returnImmediately` moved to correct nesting level, added `commandTemplates` with timestamps for log views, added `logs.timestamps` setting

### Fixed

- Lazydocker: migration script (`0.2.78`) to fix broken config nesting for existing installs

## [0.2.77] - 2026-03-30

### Changed

- Nvim: compatibility updates for Neovim 0.12.0 — LSP `execute_command` migrated to `client:exec_cmd`, dropped `supports_method` nvim 0.10 compat shim, bundled treesitter parser cleanup now checks both site and Lazy plugin dirs
- Nvim: LSP hover (`K`) now closes diagnostic float to prevent overlap; diagnostic float suppressed while hover is open
- Nvim: `@` file reference in claude-prompt uses saved cursor position, fixing off-by-one after Telescope closes
- Zsh: `WORDCHARS` set so Opt+Backspace/Ctrl+W deletes one segment at a time for kebab-case, paths, and dotted names
- CLAUDE.md trimmed to essentials; detailed guidance moved to `.claude/rules/`

### Fixed

- Nvim: treesitter swap-parameter guard now checks for nil parser (not just pcall failure)
- Nvim: codecompanion `build = false` to prevent unnecessary build step

## [0.2.76] - 2026-03-29

### Added

- Tmux: `prefix + R` re-sources `~/.zshrc` in all zsh panes across all sessions (with skip count for non-zsh panes)

### Changed

- CLI: `print_logo` gradient is now theme-aware — sources active theme accent colours and interpolates dynamically (sage → forest default fallback)
- Tmux: responsive popup sizing for kill confirmations (Opt+q/s/x) and help (prefix+h) — fixed size on wide terminals, 95% width on narrow/mobile
- Tmux: help template updated to show `prefix + r / R` (reload / re-source) instead of old reload-locals label

## [0.2.75] - 2026-03-27

### Changed

- Nvim: refresh command (`<leader>lR`) now closes Neo-tree, Diffview, and Trouble before wiping buffers; dashboard opens in current window instead of as a float
- Tmux: nvim instance picker uses compact braille-font header with theme-aware colour (matches nvim Keyword highlight); opencode picker colours now derived from theme cyan accent
- Tmux: `hex_fg` / `hex_dim` colour helpers added to tmux scripts library for truecolour theming
- Zsh: `_cached_eval` now validates cache files are non-empty (`-s`) before sourcing; removes empty cache files to prevent stale blanks
- Zsh: fzf ZLE widget wrapping guarded with `zle -l` check to avoid errors when widgets are not yet registered

### Fixed

- Agent alert hooks (`agent-alert.sh`, `agent-alert-clear.sh`) now exit early when not running inside tmux

## [0.2.74] - 2026-03-25

### Added

- Nvim: PR review enhancements — "diff edit" and smart "diff open" actions in `pr-review.lua`
- Tmux: `_lib/process.sh` — shared graceful process termination utilities (recursive PID tree walker, SIGTERM → 2s wait → SIGKILL)
- Zsh: `nuke-node` alias for force-stopping leaked node processes

### Changed

- Nvim: migrated from copilot.vim to copilot.lua (zbirenbaum/copilot.lua) with blink-cmp integration — ghost text with auto-trigger, `blink-cmp-copilot` completion source (score_offset 100), Tab priority, filetype filtering via opts, sensitive file detection via `should_attach` callback
- Nvim: dashboard simplified to single-pane layout with compact smblock font header (removed git log/status terminal sections)
- Tmux: pane, window, and session kill scripts now use graceful process termination via `_lib/process.sh` (previously relied on SIGHUP only)
- Tmux: instances `kill.sh` consolidated to reuse `graceful_kill_pids` instead of inlining signal sequence
- Zsh: `v` alias moved to Editor section; `cl` alias fixed with `|| true` to not fail outside tmux

### Fixed

- Nvim: NVIM logo block character alignment corrected in instance listing (6-row fix)
- Nvim: opencode instance listing now shows full "OPEN CODE" text instead of truncated "O CODE"

### Removed

- Tmux: `prefix+S` (list saved backups) and `prefix+R` (restore session) resurrect keybindings — resurrect is accessed via the session picker

## [0.2.73] - 2026-03-22

### Added

- CLI: `dotfiles sync` command — sync copy-on-install configs from repo on demand (`--force` to overwrite)
- Nvim: snacks.nvim dashboard with single-pane layout (recent files, projects, git log)
- Nvim: .NET debugging support via easy-dotnet + nvim-dap (`<leader>nd`)
- Nvim: testing & debugging documentation in nvim/README.md
- Brewfile: Raycast cask
- Zsh: `secrets`, `config`, `zshrc` quick-edit aliases
- Zsh: `make` wrapper — auto-forwards to repo root Makefile when none in current directory
- Installer: gpk (glazepkg) and gh-bench extension

### Changed

- Karabiner: Caps Lock → Escape is now global (was per-app), added Raycast to Right Option → Control
- Nvim: `<leader>lR` refresh now opens the dashboard instead of reopening the previous file
- CLI: `dotfiles diff` no longer shows zshrc.template (user-owned, differences always expected)
- CLI: extracted shared `_copy_pairs()` helper for diff and sync commands
- Tmux: navigation hint formatting — arrow icons (↓/↑) and top/bottom instead of words
- Tmux: fzf border labels use "search" instead of "srch" abbreviation
- btop: update interval 500ms → 200ms
- lazydocker: `returnImmediately: true` for confirmations
- Nvim: stylua formatting on debug.lua and test.lua

### Removed

- Installer: openapi-tui (removed from install, migration cleans up existing binary)

## [0.2.72] - 2026-03-20

### Added

- Launchers: duplicate launcher action (`D`) in picker — copies launcher to user directory with `-copy` suffix
- Zsh: `ralph` and `ralf` aliases (clear scrollback + launch)
- Ghostty: `Super+Up` / `Super+Down` keybindings mapped to Home/End
- Brewfile: `lazycron` (cron job manager TUI), `jiru` (Jira TUI)

### Changed

- Fzf pickers: use exact substring matching (`--exact`) across all tmux fzf pickers for better search results
- Launcher picker: name matches now rank above description matches via hidden search field and `--tiebreak=begin`
- Brewfile: alignment cleanup, added supplyscan comment
- Nvim: Discord presence uses repo URL from opts instead of hardcoded fallback

## [0.2.71] - 2026-03-19

### Fixed

- CI: stabilise zsh startup benchmark — increase hyperfine runs (30→100), warmup (3→5), pin runner to `macos-15`
- Tmux: random theme picker no longer re-picks the current theme

### Changed

- Nvim: mini.surround keybindings remapped from `s` to `gs` prefix to avoid clash with flash.nvim (`gsa`, `gsd`, `gsr`, etc.)

### Added

- Nvim: `<leader>i` to insert space at cursor without leaving normal mode
- Zsh: `Cmd+Up` / `Cmd+Down` keybindings for beginning/end of line (via Ghostty `super+up/down → Ctrl+Home/End`)

## [0.2.70] - 2026-03-18

### Fixed

- Nvim: diffview/octo diff buffers missing treesitter syntax highlighting — generated colourschemes loaded via `dofile()` didn't fire `ColorScheme` autocmd, so `diff-highlights` never applied bg-only overrides

### Added

- Launchers: `docker` session launcher for lazydocker

## [0.2.69] - 2026-03-17

### Fixed

- Tmux: session/pane kill not clearing alerts — backgrounded `clear_session_alerts` was SIGHUP-killed when popup exited; now runs synchronously
- Tmux: instance picker "n" (new) key silently failing — fzf `become()` is unreliable in pipelines; replaced with `execute-silent()+abort` across all instance pickers

### Added

- Nvim: `grf` keymap — fix all diagnostics in current file (applies quickfix code actions bottom-up, supports `codeAction/resolve`)
- Nvim: `q` keymap to close oil.nvim file explorer
- Tmux: regression tests for synchronous alert cleanup and no-`become()`-in-pipeline guards

### Changed

- Nvim: comment block navigation (`[c`/`]c`) skips closed blocks correctly

## [0.2.68] - 2026-03-17

### Fixed

- Tmux: alerts lost on session/window rename — rename scripts now update the alerts file in-place (`update_session_name_in_alerts`, `update_window_name_in_alerts`) instead of clearing, with rollback on rename failure
- Tmux: dots in session/window names matched as regex wildcards in grep patterns — `my.project` could match `myXproject`; names are now escaped in list scripts and copilot picker
- Tmux: killing the last pane in a window/session now correctly clears alerts for the destroyed resource (previously leaked stale entries)

### Added

- Tmux: `update_window_name_in_alerts` and `update_session_name_in_alerts` functions in alerts library for rename tracking
- Tmux: `alerts/cleanup.sh` — stale alert cleanup script called by `session-closed`, `session-renamed`, and `after-rename-window` hooks
- Tmux: `build_alert_icons` tests including dot-in-name regression coverage
- Tmux: parameterised launcher collision handler — attach/new prompt when target session already exists (fzf picker with suffix input)
- Tmux: `session-renamed` hook for alert cleanup on native tmux renames

### Changed

- Zsh: `bindkey -e` (emacs mode) and `KEYTIMEOUT=1` moved before plugin loading to prevent fzf and ZLE widget bindings from being wiped
- Tmux: dev launcher appends `-dev` suffix to session names and supports `SESSION_NAME` override for collision handler
- Tmux: window move alert tracking simplified to single sed pass (was read-clear-rewrite loop)

## [0.2.67] - 2026-03-17

### Fixed

- Tmux: launcher wizard `tr` error when generating session variable name — `tr '-.'` was interpreted as option flags, silently crashing the wizard (regression from 0.2.64)

## [0.2.66] - 2026-03-15

### Fixed

- Tmux: alerts not clearing when switching sessions via fzf picker — `client-session-changed` hook was missing `clear.sh` call (regression from 0.2.65 performance fix)

### Added

- Tmux: regression test ensuring both `after-select-window` and `client-session-changed` hooks call `clear.sh`
- Zsh: `ac` shorthand alias for `alerts-clear`

### Changed

- Zsh: unbind `Alt+C` (`fzf-cd-widget`) — terminals send the same escape sequence for Esc+c and Alt+C, causing accidental triggers; `Opt+A` directory history picker is the replacement
- Zsh: `font-preview` now passes terminal width to figlet/toilet for proper column wrapping, disables fzf mouse mode

## [0.2.65] - 2026-03-15

### Fixed

- Tmux: fzf picker performance regression — session/window list scripts now read alerts file instead of per-window `tmux show-options` calls (O(1) file read vs O(sessions × windows) tmux round-trips)
- Tmux: removed blocking `clear.sh` calls from all picker pipelines — alert clearing now handled exclusively by the `after-select-window` hook
- Tmux: removed redundant `clear_window_alerts` from `update-timestamp.sh` and `update-timestamp.sh` subprocess from `clear.sh` — eliminated duplicate work on every window switch
- Tmux: simplified instance picker (claude/opencode/copilot) post-selection to direct `tmux switch-client` instead of inline shell with extra tmux lookups

### Added

- Tmux: `build_alert_icons` shared function in alerts library for file-based alert icon rendering
- Tmux: `test-list-performance.sh` regression test to guard against per-window tmux call patterns in list scripts

### Changed

- Nvim: set `tabstop = 4` for consistent indentation display
- Nvim: indent-blankline scope guides brightened relative to base whitespace colour for visual distinction

## [0.2.64] - 2026-03-15

### Added

- Zsh: `font-preview` function — fzf-powered figlet/toilet font browser with live preview
- Brewfile: `figlet` and `toilet` packages for ASCII art text banners

### Changed

- gh-dash: `m` keybinding defaults to squash & merge with branch deletion (`--squash --delete-branch`)
- Tmux: kill session keybinding changed from `Opt+Shift+x` to `Opt+q` for easier access
- Tmux: `kill.sh` defaults to current session when no argument provided
- Zsh: `Opt+A` directory history widget rewritten inline (follows fzf's Alt-C pattern) for better reliability
- Nvim: disable additional which-key mappings for cleaner popup; update markview.nvim `cmp` → `completion` module key

## [0.2.63] - 2026-03-14

### Added

- Tmux: GitHub Copilot instance management — `prefix + a` opens fzf picker to list, create (`n`), and kill (`x`) Copilot CLI instances with alert integration
- Tmux: Copilot agent alerts (✦ blue icon) in status bar and session lists, with hook wrappers for auto-alerting
- Zsh: `copilot` alias clears scrollback before launch
- Nvim: music.nvim plugin for now playing indicator (Apple Music, Spotify)
- Brewfile: `chafa` terminal image renderer (used by music.nvim)

### Changed

- Zsh: `gds` alias changed from `git diff --staged` to `git diff --stat`
- gh-dash: `gh enhance` action uses `--repo` flag for cross-repo support

### Removed

- Zsh: `demo-rec` alias (asciinema recording)

## [0.2.62] - 2026-03-13

### Added

- Zsh: `ff` alias for `fastfetch` (system info); `dash` alias clears scrollback and opens `gh dash`
- Nvim: `<leader>sG` fixed-string grep, `<leader>lR` refresh Neovim, `<leader>Nn`/`<leader>Na` filtered/all notification history, `<leader>c]`/`<leader>c[` next/prev comment block, `<leader>psm` squash-merge PR, `<leader>mp` markdown preview in browser, `<leader>ni` add missing imports, `<leader>ba` delete all other buffers (cheatsheet updated)

### Fixed

- Tmux/Launchers: session names now disallow dots — tmux uses `.` as pane separator in target syntax (`session:window.pane`), causing ambiguous targeting with dotted names (e.g. `music.nvim`)

## [0.2.61] - 2026-03-12

### Added

- Zsh: `claude`, `gemini`, `opencode` aliases clear scrollback before launch; `grmc` (`git rm --cached`) and `gca` (`git commit --amend`) aliases
- Tmux: session kill now captures live state for undo (no longer relies on stale auto-save)
- Tmux: resurrect restore `--file` flag for direct file path
- Nvim: diffview guard prevents opening multiple views simultaneously
- Theme generator: CopilotSuggestion, indent-blankline, neotest, flash, and fidget highlight groups in generated themes

### Changed

- Nvim: diff highlights use theme palette colours (from GitSigns) instead of hardcoded values
- Nvim: Copilot suggestion highlight blends Comment fg towards Normal bg; skips if theme already defines it
- Tmux: fzf picker scroll keys changed from `Ctrl+d`/`Ctrl+u` to `d`/`u`
- Tmux: fzf session/window popups unbind `u` key in search mode (undo key conflict)

### Fixed

- Nvim: BufEnter empty-buffer cleanup deferred via `vim.schedule` to avoid interfering with diffview layout
- Nvim: JSON sort pipeline now uses `set -o pipefail` for proper error detection
- Tmux: session undo race condition — undo backup no longer deleted by split.sh orphan cleanup
- Tmux: undo cleanup only runs on successful restore (preserves backup for retry on failure)
- Tmux: undo cache directory created with mode 700
- Tmux: suppress send-keys errors during restore when pane is already gone

## [0.2.60] - 2026-03-11

### Changed

- Neovim: C# formatting now uses Roslyn LSP instead of CSharpier — respects `.editorconfig` rules with no extra tooling
- Install: global `.editorconfig` symlinked from `formatters/editorconfig` to `~/.editorconfig`
- Install: formatter symlinks grouped under "Formatters" section (was "Prettier")

### Fixed

- Install: `uninstall.sh` missing symlinks for `.prettierrc`, `.editorconfig`, `dash-repo-sync`, `lazygit/config.yml`, and `hammerspoon/init.lua`
- Neovim: vim-visual-multi motion conflicts with markdown keymaps and blink.cmp

### Removed

- CSharpier — no longer installed via Mason; migration auto-removes it

## [0.2.59] - 2026-03-11

### Added

- Neovim: `Space ba` keymap to delete all other buffers (keep current)
- Neovim: disable completion popup in grug-far search buffers

### Changed

- Zsh: `v` alias now clears the terminal before opening nvim
- Zsh: gcloud SDK path uses Homebrew prefix (supports `brew install google-cloud-sdk`)

### Fixed

- Neovim: conform.nvim csharpier formatter mapped to correct `cs` filetype

### Removed

- cronboard and posting — replaced by other tools; migration auto-uninstalls them

## [0.2.58] - 2026-03-09

### Added

- Neovim: layered spell dictionaries — personal (`~/.local/share/nvim/spell/`) and repo-shared (`nvim/spell/`); `zg` adds to personal dictionary
- Neovim: `Space Sd` keymap to edit personal dictionary
- `dotfiles update`: confirmation prompt before applying changes

### Changed

- Neovim: smart Tab in insert mode — accepts Copilot ghost text when visible, falls through to blink.cmp completion otherwise
- CI benchmark: uses median instead of min for startup badge, increased to 30 runs for stability
- Cleaned repo spell dictionary — moved personal words to user dictionary

## [0.2.57] - 2026-03-09

### Added

- Neovim: built-in spellcheck with en_gb, camelCase support, Telescope suggestions, and custom dictionary (`nvim/spell/en.utf-8.add`)
- Neovim: spell keymaps under `Space S` — toggle, suggest, add/remove words
- Neovim: which-key Spell group
- Zsh: `Opt+A` keybinding for directory history picker (replaces `cdl` command)

## [0.2.56] - 2026-03-09

### Added

- Incremental updates: `dotfiles update` now skips unchanged installer steps (use `--force` to re-run all)
- Version-gated migration system: scripts in `scripts/migrations/` run automatically during updates
- `--skip-steps` validation in installer (rejects unknown step names)
- Installer remembers whether project directory prompts have been asked (won't re-ask on updates)
- Brewfile: `monolith`, `gotermsql`, `lazyssh`, `cronboard`, `snitch`
- Installer: `posting` (HTTP client TUI via pipx) and `openapi-tui` (OpenAPI spec browser via GitHub releases)
- Zsh: `$HOME/.cargo/bin` added to PATH for Rust/Cargo binaries

### Changed

- `dotfiles update --dry-run`/`-n` renamed to `--preview`/`-p`
- Installer step labels extracted into variables (shorter verbs in update mode)
- Internal state files moved to `~/.config/dotfiles/.state/` (migrations, prompted)
- Brewfile: replaced `lazysql` with `gotermsql` (database TUI)

## [0.2.55] - 2026-03-08

### Changed

- Ghostty (Linux): replaced `curl | bash` install with deferred next-steps message (pinned commit SHA for review)
- Ghostty (Linux): removed `--nogpgcheck` from dnf Terra install; imports GPG key explicitly
- Ghostty (Linux): removed stderr suppression from pacman/dnf installs so errors are visible
- Ghostty keybindings: deduplicated macOS/Linux blocks using `${mod}` variable (opt vs alt)
- Ghostty config: platform-specific settings now injected via `{{PLATFORM_CONFIG}}` template placeholder
- Tmux config: clipboard command injected via `{{CLIPBOARD_CMD}}` template placeholder

### Fixed

- Temp file handling in theme-switch Ghostty block (uses `mktemp` instead of PID-suffixed files)
- Backup-file check in `test-linux-compat.sh` (was testing empty string, now uses `find`)
- Neo-tree filter popup border cutoff (`popup_border_style = 'rounded'`)
- Theme validation test now skips runtime placeholders (`CLIPBOARD_CMD`, `PLATFORM_CONFIG`)
- `update_zshrc_export` rejects values containing newlines (prevents sed injection)

### Removed

- Speculative snap path from `find_ghostty_themes` (no snap Ghostty packages exist)

## [0.2.54] - 2026-03-07

### Added

- Tmux: cross-platform helpers (`mod_key`, `clipboard_copy_cmd`) in tmux common.sh
- Tmux: dynamic help renderer (`show-help.sh`) replaces static `tmux-help.txt` with platform-aware modifier keys
- Tests for cross-platform helpers and show-help template rendering

### Changed

- Tmux: URL picker rebound from `prefix+y` to `prefix+u`; "no URLs" notification reduced to 1s
- Zsh: moved Homebrew environment setup to `zprofile` (login shell) for correct load order
- Zsh: added `gh` CLI completion fix for compdef conflict
- Tmux: `reverse_lines` removed broken `tail -r` fallback (now `tac` → `awk`)

## [0.2.53] - 2026-03-07

### Added

- Nvim: noice.nvim for enhanced LSP hover and signature help rendering (replaces lsp_signature.nvim and manual hover handler)
- Nvim: suppress diagnostics on decompiled .NET metadata source buffers (MetadataAsSource)
- Installer: `--no-logo` flag to suppress ASCII logo (used by `dotfiles update`)

### Changed

- `dotfiles update` runs installer with `--no-logo` and quiet git pull for cleaner output

## [0.2.52] - 2026-03-07

### Added

- Theme generation: create dotfiles themes from Ghostty's 300+ built-in themes via `dotfiles theme generate <name>`
- Theme deletion: remove generated themes via `dotfiles theme delete <name|all>`
- Lua colour utilities library (`scripts/_lib/colour-utils.lua`) for HSL conversion and contrast calculations
- Lua theme generator (`scripts/_lib/generate-theme.lua`) produces tmux, ghostty, nvim, and fzf configs
- Nvim: generated colourscheme loader in `theme.lua` with path traversal validation
- CI: shellcheck for theme tools, luacheck for Lua modules (now enforced, not advisory)
- Tests for colour utils, theme generation, theme deletion, symlinks, ghdash merge, health check, and uninstall
- Sandbox helpers in test framework for isolated test environments

### Changed

- Theme picker (`tmux/scripts/themes/pick.sh`) shows both hand-crafted and generated themes
- `theme-switch` sources `common.sh` instead of duplicating colour definitions; extended for generated themes
- `fzf-theme.sh` updated for generated theme support with path traversal guard
- Zsh tab completion updated with `generate` and `delete` subcommands
- Hardened input validation: hex colour checks in theme generator, variable name and sed escaping in `update_zshrc_export`, shell-escaped launcher names
- Temp files use `mktemp` instead of predictable PID-based names in alerts
- Deduplicated test boilerplate across tmux tests via shared `_test-helpers.sh`
- Collapsed `paths.sh` undo migration functions into single `_migrate_flat_undo_file()` helper
- Moved `sanitise_launcher_name` to `tmux/scripts/_lib/common.sh` (where it's used)
- Install scripts derive `DOTFILES_DIR` from script location instead of assuming `$HOME/dotfiles`
- Platform-aware `stat` in `paths.sh` for Linux compatibility
- `set-default-shell.sh` uses `tee -a` instead of `sudo bash -c`
- Documentation updates across theme system, installation guide, and component READMEs

### Fixed

- `tls` alias and `tattach` function path corrected to `resurrect/restore.sh`
- Theme picker `get_current_position()` generates list internally instead of reading from stdin
- `sessions/kill.sh` uses `$DOTFILES_ROOT` paths and guards resurrect plugin existence

### Removed

- `tmux/scripts/utils/confirm.sh` (unused)

## [0.2.51] - 2026-03-06

### Added

- keyd: Linux keyboard remapping (Karabiner equivalent) with per-device Apple keyboard support
- Installer: system gcc auto-install on Linux for native builds (tree-sitter, etc.)
- Installer: `cc` symlink prefers system gcc over Homebrew's on Linux
- Installer: `install_system_package` helper in common.sh for cross-distro package installs
- Installer: set-default-shell step ensures zsh is the login shell
- Installer: Ghostty and fnm Linux install hints in prerequisites and post-install
- Installer: dnf support in Homebrew prerequisite installation

### Changed

- Installer: Brewfile filters macOS-only formulas (fnm, swift-format) on Linux
- Installer: Linux prerequisite hints now suggest brew or system package manager
- Installer: full preset description is platform-aware (Karabiner on macOS, keyd on Linux)
- Nvim: CodeCompanion chat window width set to 40%
- Nvim: mkdnflow disabled MkdnNextLink/MkdnPrevLink mappings (frees C-i for jumplist)

## [0.2.50] - 2026-03-05

### Added

- Nvim: window zoom toggle (`<leader>z`) with statusline indicator
- Nvim: mkdnflow table alignment keybindings (`<leader>mA{c,l,r,x}`)

### Changed

- Nvim: blink.cmp Tab key now accepts completion when menu is visible (select_and_accept)
- Nvim: treesitter indentexpr only set when indent queries exist for the language (fixes C# column-0 issue)
- Nvim: discord presence idle timeout set to 10 minutes with hidden status
- gh-dash: removed lazygit universal keybinding (conflicts resolved)

## [0.2.49] - 2026-03-04

### Added

- Nvim: dial.nvim for enhanced increment/decrement (dates, semver, booleans, hex)
- Nvim: tailwindcss-dial.nvim to cycle Tailwind CSS classes with `Ctrl+a`/`Ctrl+x`
- Nvim: smart-paste.nvim for auto-adjusted indentation on paste
- Cheatsheet: increment-decrement section documenting `Ctrl+a`/`Ctrl+x` bindings

### Changed

- Brewfile: moved tmux-fingers from minimal preset to build tools section (requires gcc on Linux)
- CLI: added `ls`, `rg`, and `help` entries to `dotfiles aliases` output
- CLI: converted tmux aliases section from array-based to inline `_2col` for consistency

## [0.2.48] - 2026-03-03

### Changed

- CLI: `dotfiles notes` fetches changelog from remote so users can see unreceived changes above the `★ current` marker

## [0.2.47] - 2026-03-03

### Added

- Nvim: codecompanion.nvim with copilot (default), anthropic, and opencode ACP adapters
- Nvim: markdown-preview.nvim browser preview (`<leader>mp`)
- Health check: environment variable checks for plugin API keys (informational)

### Changed

- Nvim: swap parameter keymaps moved from `<leader>a`/`<leader>A` to `>p`/`<p` (frees `<leader>a` for AI group)
- Nvim: codecompanion default adapter changed from anthropic to copilot (no API key required)
- Nvim: blink.cmp sort config migrated from `sort.comparators` to `fuzzy.sorts`

### Fixed

- Nvim: markdown-preview.nvim build failure (`mkdp#util#install` not available during lazy.nvim build)
- Nvim: treesitter swap crash on buffers without a parser (now shows notification via mini.notify)
- Alerts: opencode hook wrappers skip when running as ACP subprocess inside Neovim

## [0.2.46] - 2026-03-03

### Added

- CLI: `dotfiles version` / `dot -v` command — shows version, preset, theme, branch, and path with gradient logo
- CLI: `dotfiles notes` highlights the current version with a magenta `★ current` marker
- Installer: Step 10 prompts for `DEV_ROOT` and `PROJECTS_ROOT` project directories during installation
- Installer: Smart post-install "next steps" that detect what's already configured and only show relevant items
- Zsh: fzf theme auto-refresh — `Ctrl+R`, `Ctrl+T`, `Alt+C`, and `cdl` pick up theme changes without restarting the shell

## [0.2.45] - 2026-03-02

### Added

- Nvim: mini.bufremove for buffer deletion without closing windows (`<leader>bd`, `<leader>bD`)
- Nvim: mini.pairs replaces nvim-autopairs (consolidated into mini.nvim)
- Nvim: mini.hipatterns for inline hex colour highlighting

### Changed

- Nvim: NeoTree reveal key changed from `\` to `|`
- Nvim: Breakpoint keybindings moved to `<leader>Bt` / `<leader>Bc` to free `<leader>b` for buffer group

## [0.2.44] - 2026-03-02

### Added

- Nvim: Discord Rich Presence via cord.nvim (catppuccin theme, repo link button)
- Health check: generated config validation, TPM plugin checks, alert hook executability, local override status, PATH/tools verification

### Fixed

- Nvim: Deduplicate .NET diagnostics reported from multiple .csproj contexts (Roslyn multi-project)
- Nvim: Diffview `]f`/`[f` navigation uses proper `DiffviewViewOpened`/`DiffviewViewClosed` user events instead of `FileType` autocmds
- Nvim: Guard mini.bracketed file navigation against empty/invalid directories

## [0.2.43] - 2026-03-02

### Added

- CLI: `dotfiles notes` / `dot -n` command — browse the full changelog in a pager (uses `bat` if available, falls back to colorised `less`)
- CLI: Changelog preview during `dotfiles update` and `dotfiles status` — shows incoming release notes when new versions are available
- Zsh: `cl` alias — clears screen, scrollback buffer, and tmux history in one keystroke

### Changed

- Nvim: vim-visual-multi Add Cursor Up/Down remapped to `<M-Up>` / `<M-Down>`
- README: CLI examples use `dotfiles` (full command name) with note that `dot` is a shorthand alias

## [0.2.42] - 2026-02-28

### Added

- Tmux: Browser-style navigation history — `prefix + -` (back) and `prefix + =` (forward) navigate between previously visited windows across sessions
- Tmux: `nav.sh` utility tracks window visits via hooks, prunes stale entries, and truncates forward history on new navigation (browser behaviour)
- Tmux: Navigation history tests (`test-nav-history.sh`)

### Changed

- gh-dash: `dash-repo-sync` detects and removes stale repo entries (paths that no longer exist on disk), with dry-run support
- gh-dash: `ghdash.sh` merge now starts from a clean `config.base.yml` to prevent array duplication from repeated `*+` merges
- gh-dash: `theme-switch` writes to `config.base.yml` instead of `config.yml` directly
- Nvim: Simplified `vim-visual-multi` plugin config (removed custom init, use `lazy = false`)
- Zsh: Swallow Ctrl+-/Ctrl+= escape codes to prevent raw output in terminals with `modifyOtherKeys`

## [0.2.41] - 2026-02-27

### Changed

- Alerts: `show.sh` rewritten to use parallel arrays for bash 3.2 (macOS stock) compatibility — removes `declare -A` dependency
- Alerts: Extracted `_acquire_alerts_lock` / `_release_alerts_lock` helpers with stale-PID recovery; shared by `clear_window_alerts`, `cleanup_stale_alerts`, `clear_session_alerts`, and `update-rename.sh`
- Alerts: `cleanup_stale_alerts` now correctly parses 5-field exit alert lines instead of splitting on 3 fields

### Fixed

- Cmd alerts: Label sanitisation — strip colons (alerts file delimiter), escape `#` (tmux format injection), and cap length at 80 chars
- Cmd alerts: Window-switch guard — only fire alert if user has switched away from the origin pane; commands finishing in the active pane are silently ignored
- Alerts: Agent name whitelist in `set_window_alert` prevents arbitrary values
- Alerts: `grep -vF` (fixed-string) in clear/rename operations prevents regex injection from session or window names
- Tests: Fix `_CMD_ALERT_THRESHOLD` → `_CMD_ALERT_MIN_SECONDS` rename and add `_CMD_ALERT_EXCLUDE=()` for test isolation

## [0.2.40] - 2026-02-26

### Added

- Zsh: Command exit alerts — automatically notifies when a command finishes in another tmux window (✓/✗ icon in status bar + window tab highlight), no wrapping required
- Tmux: `@exit_alert` / `@exit_alert_colour` window options for per-window exit state; `@exit_pass_colour` / `@exit_fail_colour` global options sourced from theme
- Alerts: `set_exit_alert` function in `alerts.sh` library; session and window list pickers show exit alert icons with ANSI colour
- Theme: `TMUX_EXIT_PASS_COLOUR` / `TMUX_EXIT_FAIL_COLOUR` derived variables (green/red) added to `theme-defaults.sh` and `theme-switch`
- Docs: `docs/CMD-ALERTS.md` — detailed guide for the command exit alert system
- Nvim: `<leader>wH/wL/wJ/wK` maximise-direction window resize keymaps (shift variants of small-increment maps)

### Changed

- Alerts: `show.sh` now handles both agent alerts (3-field) and exit alerts (5-field) in the same alerts file
- Alerts: Session and window list pickers handle mixed alert types with correct icons and colours
- Tmux: Zoom indicator uses `TMUX_STATUS_BELL_FG` (theme accent) instead of hardcoded cyan; clock background uses `TMUX_BG_SECONDARY`
- Theme: `TMUX_STATUS_BELL_FG` uses `${VAR:-fallback}` to allow per-theme overrides without clobbering explicit values set in the theme file
- Nvim: `<leader>lR` refresh runs `only` before wiping buffers and `wincmd =` after, resetting the layout cleanly

## [0.2.39] - 2026-02-26

### Added

- Launchers: `github` (gh-dash session) and `btop` (system monitor session)
- gh-dash: `dash-repo-sync` utility syncs local repo paths into gh-dash config (`drs` alias)
- gh-dash: Keybindings — `g` (lazygit), `C` (Octo code review), `D` (diffnav), `A` (actions)
- gh-dash: `local.yml` template for personal overrides (deep-merged via `yq` on theme-switch)
- Hammerspoon: `local.lua` override support via `pcall(require, "local")`
- LazyGit: `local.yml` template for personal overrides (loaded via `LG_CONFIG_FILE`)
- Brewfile: `yq` (YAML processor), `diffnav` (diff navigator), `gh-enhance` extension

### Changed

- Launchers: Renamed `tnew` to `dev` (same 3-window layout: zsh + nvim + claude)
- Install: Extracted `install_local()` and `migrate_to_symlink()` helpers in create-symlinks
- Install: Hammerspoon migrates from directory symlink to owned dir with file symlinks
- Install: LazyGit uses XDG path on all platforms via `LG_CONFIG_FILE` env var
- CLI: Simplified `dotfiles links` — removed stale btop, karabiner, lazydocker sections
- Docs: Expanded config ownership to three patterns (symlinked, layered, copy-on-install)

### Removed

- Install: Claude/OpenCode config symlinks (managed separately)

## [0.2.38] - 2026-02-25

### Changed

- Install: btop, karabiner, lazygit, lazydocker, hammerspoon configs use copy-on-install pattern — personal edits now survive `dotfiles update`
- Install: Uninstall preserves user-owned configs with warning instead of deleting
- Hooks: `nvim --server` commands use `--headless` flag to prevent terminal flicker
- Alerts: Storage path moved from `~/.claude/alerts` to `~/.config/agent-alerts/alerts` (XDG compliant)
- Docs: OpenCode hooks updated to use published `opencode-tmux-alert` plugin
- CLI: Added missing aliases (`alerts-clear`, `oc`, `dot`) to `dotfiles aliases` output

### Removed

- Tmux: Gemini agent support — removed instance picker, alert hooks, status bar integration, and resurrect process

### Added

- Docs: `docs/AGENT-HOOKS.md` — setup guide for agent alert hooks (Claude Code, OpenCode)
- Zsh: `OPENCODE_ALERT_SCRIPT` and `OPENCODE_CLEAR_SCRIPT` env vars for opencode-tmux-alert plugin

## [0.2.37] - 2026-02-24

### Added

- Tmux: `m` / `M` in copy-mode for first non-blank / end of line (matches nvim keymaps)

### Fixed

- Nvim: `<leader>cd` delete comment block preserves spacing when blank lines exist on both sides

## [0.2.36] - 2026-02-24

### Added

- Tmux: `r` rename binding in window switcher (`prefix + f`) — rename windows inline without leaving the picker
- Nvim: `<leader>c]` / `<leader>c[` to navigate between comment blocks
- Nvim: `<leader>cu` inside a `<comment>` block inserts a new exchange before `</comment>`
- Brewfile: `asciinema` terminal recorder, `tmux-fingers` tap fix
- Install: `.prettierrc` symlink for global Prettier config

### Changed

- Tmux: Session rename (`r`) in session switcher now stays in picker instead of switching to renamed session
- Tmux: URL picker (`prefix + y`) improved URL extraction — strips trailing punctuation and balances parens/brackets
- Nvim: Snippet insertion uses smart spacing (blank lines only where needed, no trailing blank)
- Nvim: `<leader>cd` delete comment block now removes surrounding blank lines
- Nvim: `mini.bracketed` `]f`/`[f` file navigation restored when diffview closes (was previously deleted)
- btop: Default process sort changed from threads to memory

## [0.2.35] - 2026-02-23

### Added

- Nvim: `<leader>pq` keymap to quit Octo (closes review layout and all octo buffers)
- Nvim: Octo `runs` mappings to fix workflow runs telescope picker crash

### Changed

- Nvim: Widened telescope ui-select dropdown to 0.9

## [0.2.34] - 2026-02-23

### Added

- Nvim: `m`/`M` keymaps for line start/end (`^`/`$`), marks relocated to `gm`
- Tmux: `` `+[ `` / `` `+] `` for previous/next pane layout cycling

## [0.2.33] - 2026-02-22

### Added

- CLI: `dot links` command — shows all managed symlinks and their status (OK/broken/absent), filtered by preset
- Zsh: `cdl` function — pick from directory history with fzf (browser-style, most recent first)
- Zsh: Tab completion for `dotfiles theme` subcommands (lists available themes)
- CI: Zsh startup benchmark job using hyperfine with benchmark-action trend tracking
- Launchers: `config` and `dotfiles` session launchers for tnew
- Zsh: `fnm` init is now guarded with command check (prevents errors when fnm is absent)

### Changed

- FZF: Collapsed multi-line `FZF_DEFAULT_OPTS` colour string into single-line format (avoids whitespace issues)

## [0.2.32] - 2026-02-22

### Added

- Zsh: `cdb`/`cdf` browser-style directory back/forward navigation
- CLI: `tnew` now shown in `dot aliases` when installed
- gh-dash: Integrated into theme system — `theme-switch` now generates a themed `~/.config/gh-dash/config.yml` with 17 colour keys

### Changed

- CLI: Fixed column overflow in `dot aliases` for FILES, TMUX, and PROFILING sections

### Removed

- Brewfile: Removed unused `oug-t/difi` tap

## [0.2.31] - 2026-02-21

### Added

- Tmux: `tmux-fingers` plugin for quick pattern copy (prefix + Space) — flash.nvim-like hint labels over URLs, paths, SHAs, IPs, Jira keys, emails, and more
- Tmux: Custom finger patterns for file paths, Jira keys, emails, connection strings, hex colours, and shell commands

### Changed

- Tmux: Removed Gemini instance picker (prefix + g)
- Tmux: Search highlight current match now uses pink with underscore for better contrast
- Tmux: `pick-url.sh` captures 50k lines instead of 5k for deeper URL history
- Tmux: `theme-switch` now substitutes `TMUX_ACCENT_GREEN` and `TMUX_BG_SECONDARY` placeholders

### Fixed

- Docs: Updated all three docs files (INSTALLATION-GUIDE, THEME-SYSTEM, TROUBLESHOOTING) with current codebase state — fixed stale paths, step counts, symlink lists, prerequisites, and XDG locations

## [0.2.30] - 2026-02-20

### Added

- Neovim: `http` treesitter parser
- Neovim: Auto-purge compiled treesitter parsers on plugin update to prevent ABI crashes

### Changed

- Neovim: Disable swap files entirely (undo + autoread + git make them redundant)
- Neovim: Removed SwapExists autocommand (no longer needed without swap files)
- Neovim: Gitsigns priority raised to 30 (above easy-dotnet test signs at 20)

### Fixed

- Neovim: dotnet build now uses `--no-incremental` to report errors from the entire solution

## [0.2.29] - 2026-02-19

### Added

- Neovim: SwapExists autocommand to auto-delete stale swap files (fixes E325 prompt spam)
- Installation: TTY detection for confirmation prompt to prevent hang in non-interactive environments
- Installation: Per-file symlink source validation during installation
- Backup directory: Set permissions to 700 to protect old configs containing secrets

### Changed

- Installation: Improved TPM clone error handling with explicit network error messaging
- Installation: Health check failures now display warnings instead of being silently suppressed
- Neovim build detection: Skip special buffers (neo-tree, terminal, etc.) when walking up to find build markers
- Neovim dotnet plugin: Refactored add_missing_imports logic into separate module for maintainability
- Theme switching: XDG_CONFIG_HOME compliance fixes throughout theme-switch
- Test runner: Removed permanently-skipped broken tests (test-kill-undo, test-show-dotfiles-status)

### Fixed

- Installation backup race condition on concurrent installations
- Backup directory creation now uses secure permissions
- Better build detection avoids nonsensical paths from special buffer types
- Various shell script quality improvements (shellcheck, error handling)

### Removed

- CODE_REVIEW.md — detailed code review analysis (addressed issues incorporated into codebase)
- Permanently-skipped broken test files that undermined test suite credibility

## [0.2.28] - 2026-02-19

### Changed

- Neovim: removed vim-fugitive — LazyGit and gitsigns cover all git workflows
- Neovim: `]f`/`[f` file navigation moved from fugitive to diffview
- Neovim: `<leader>dh` file history now falls back to repo history when no file is open
- Neovim: diffview `file_panel` config updated to `win_config` structure
- Neovim: patched diffview `init_layout` to guard against invalid window IDs (upstream bug)
- Neovim: gitsigns blame keybindings moved under `<leader>d` prefix — `<leader>db` toggle inline blame, `<leader>dB` blame popup (aligned with diffview group)
- Neovim: mini.bracketed `comment` and `treesitter` suffixes disabled (reserved for gitsigns `]c`/`[c` and neotest `]t`/`[t`)
- Ghostty: added `Opt+Shift+H/J/K/L/D/0` keybinds for escape sequence passthrough

### Added

- Zsh: `nvim-sync` function for headless Lazy.nvim plugin sync

## [0.2.27] - 2026-02-18

### Fixed

- `prefix+I` now correctly installs TPM plugins (non-interactive) and shows a completion message, instead of incorrectly overriding to config reload
- Added `prefix+r` reload hint to local override templates (tmux, Ghostty, Neovim)

### Changed

- Docs updated to reflect recent changes: new plugins, local override files, removed `Space h` help popup, removed `dana` references, corrected Ghostty setup instructions

## [0.2.26] - 2026-02-18

### Added

- Local override files for personal settings that survive theme changes and `dotfiles update`: `~/.config/tmux/local.conf`, `~/.config/ghostty/local`, `~/.config/nvim/local.lua` — created from templates on install, never overwritten
- `scripts/reload-locals.sh`: reload tmux, Ghostty, and all live Neovim instances after editing local overrides
- Tmux: `prefix + r` reloads all local overrides (tmux + Ghostty + nvim); `prefix + I` reloads tmux config only
- Tmux: `cursor-style block` default (overridable in `local.conf`)
- Ghostty: `shift+backspace` and `shift+space` keybinds for correct terminal passthrough
- ShellCheck: `.shellcheckrc` project-wide config to document and centralise suppressed codes

### Changed

- Ghostty: removed macOS Application Support symlink — Ghostty reads `~/.config/ghostty/config` natively on all platforms; no symlink needed
- Shell scripts: fixed `printf` format strings to use `%s` placeholders instead of inline ANSI colour variables (ShellCheck SC2059)
- Neovim: markdown-ui todo status config updated to new named-table API with `status_order`
- Neovim: diffview file panel positioned at bottom with height 10

## [0.2.25] - 2026-02-18

### Added

- Neovim: vim-visual-multi plugin for multiple cursors (`Ctrl+n` select word, `Alt+Down/Up` add cursor, `\A` select all)
- Neovim: mini.notify for drop-in `vim.notify` replacement with notification history (`<leader>Nn` filtered, `<leader>Na` all)
- Neovim: mini.bracketed for `]`/`[` navigation (buffers, comments, diagnostics, files, jumps, quickfix, treesitter, undo, windows, conflicts, yanks)
- Neovim: mini.splitjoin for splitting/joining code constructs (`gS` to split, `gJ` to join)
- Neovim: `<leader>cd` keymap to delete `<comment>` block under cursor
- Neovim: auto-show diagnostic float on `CursorHold`, suppressing virtual text while float is open
- Ghostty: `Ctrl+Enter` and `Ctrl+Shift+Enter` keybinds (kitty protocol) passed through to terminal apps
- Ghostty: `Opt+Shift+[` / `Opt+Shift+]` keybinds for escape bracket sequences
- Zsh: `Ctrl+Enter` and `Ctrl+Shift+Enter` bound to `accept-line` for correct behaviour in zsh

### Changed

- Neovim: dotnet build now resolves the best target (prefers `.slnx`/`.sln` over `.csproj`, skips build-variant solution files)
- Neovim: simplified `vim.diagnostic` virtual text config (removed redundant format function)
- Ghostty: `Opt+Up`/`Opt+Down` updated to send modifier-qualified cursor sequences
- Tmux: enabled `extended-keys always` for full kitty keyboard protocol support

### Fixed

- Zsh: added `shellcheck shell=zsh` declaration and suppressed SC1009/SC1036/SC1072/SC1073 on zsh glob qualifier syntax

## [0.2.24] - 2026-02-18

### Added

- Neovim: `<leader>cr` keymap to toggle `<comment>` block state between open and resolved

### Changed

- Neovim: claude-prompt `@` file picker now activates for any `.md` file under a `.claude/` directory (not just `claude-prompt-*.md`)
- Neovim: `@@` inserts a literal `@` in claude-prompt files (single `@` opens file picker)
- Neovim: mkdnflow table config updated to `auto_extend_rows`/`auto_extend_cols` API

### Removed

- Neovim: custom claude-diff plugin and associated hook scripts (`nvim-diff-checkpoint.sh`, `nvim-diff-permission.sh`, `nvim-diff-sync.sh`)
- Tmux: `test-claude-diff.sh` integration tests

## [0.2.23] - 2026-02-17

### Added

- Neovim: flash.nvim for jump/motion with search labels (`s`/`S` keys)
- Neovim: nvim-treesitter-textobjects for structural selection (`am`/`im`, `aC`/`iC`), motion (`]m`/`[m`), and parameter swapping (`<leader>a`/`A`)
- Neovim: grug-far.nvim for project-wide search and replace (`<leader>sR`)
- Neovim: oil.nvim for filesystem-as-buffer editing (`-` key)
- Neovim: trouble.nvim for better diagnostics lists (`<leader>xx`, `<leader>xX`, `<leader>xq`, `<leader>xl`)
- Neovim: which-key group icons for all leader key groups
- Neovim: Treesitter parsers for `dockerfile` and `make`
- Brewfile: ollama (local LLM runner), build tools (binutils, gcc, nasm, nano), lazysql, cloudflared, lazydocker
- Tmux: Gemini agent icon and colour support in alerts system
- Zsh: `alerts-clear` alias to clear Claude agent alerts

### Changed

- Neovim: Shortened keymap descriptions across all plugins for cleaner which-key display
- Neovim: Improved Roslyn solution filtering — patches `root_finder.find_solutions_from_file` instead of glob-based approach
- Neovim: Removed `<leader>h` help popup (use `<leader>?` cheatsheet instead)
- Neovim: Removed global fugitive keymaps (`<leader>vs/vb/vd`) — use LazyGit or gitsigns instead
- Neovim: Removed which-key non-Nerd-Font icon fallbacks (Nerd Font assumed)

### Removed

- Brewfile: difi (inline diff TUI)

## [0.2.22] - 2026-02-16

### Added

- Neovim: `JsonSort` command and `json.sort` LSP command for sorting JSON keys (strips trailing commas, sorts with jq, reformats with prettier)
- Neovim: Octo review diff scroll keymaps — `f`/`b` quarter-page, `d`/`u` half-page scrolling in review buffers

### Fixed

- Neovim: `LspRestart` uses `client.name` instead of `client.id` for correct server targeting
- Neovim: Disabled mkdnflow `MkdnEnter` and `MkdnNewListItem` keymaps that were mangling numbered lists and links on `<CR>`
- Tmux: Gemini instance switcher template binding was missing from previous release

## [0.2.21] - 2026-02-12

### Added

- Launcher picker: Settings panel (`s` key) to configure `DEV_ROOT` and `PROJECTS_ROOT` from within the picker
- Neovim: `<leader>pC` to close Octo review, `<leader>pX` to close PR
- Neovim: Expanded Octo PR keybindings — browser, URL yank, CI checks, changed files, checkout, ready/draft, thread resolve, suggest comment, reviewer/label management
- Neovim: Diffview scroll keymaps (`f`/`b`) for quarter-page scrolling in view, file panel, and history panel
- Zsh: `nvim-clear` alias to clear Neovim bytecode cache
- Launcher picker: New directory helper (`new-dir.sh`) with root picker for `DEV_ROOT`, `PROJECTS_ROOT`, or custom path
- `dotfiles set dev|projects <dir>` CLI command with zsh tab completion
- `scripts/_lib/common.sh`: `update_zshrc_export()` helper for safe `~/.zshrc` export updates
- `tmux/scripts/_lib/common.sh`: `list_project_dirs()` shared helper for `PROJECT_DIRS` listing
- Neovim: Telescope `find_files`, `live_grep`, and `grep_string` now search hidden files (excluding `.git/`)
- Gemini instance switcher (`prefix + g`) with fzf picker, alert integration, and inline instance management
- Gemini agent support in alert system (💎 cyan icon and colour)
- Zsh: `alerts-clear` alias to clear agent alerts directory

### Fixed

- Launcher test: corrected sanitisation assertion to match actual hyphen replacement character

### Changed

- `tnew` launcher: 3 separate windows (zsh, nvim, code) instead of 2 windows with split pane; directory argument is now required; offers to create directory if it doesn't exist
- Launcher picker: `n` (new directory) action uses dedicated root picker (`new-dir.sh`) instead of inline fzf path prompt
- `scripts/_lib/common.sh`: `update_zshrc_export()` auto-updates `PROJECT_DIRS` when `DEV_ROOT` or `PROJECTS_ROOT` changes
- Neovim: Cheatsheet updated with expanded PR review keybindings (browser, URL yank, CI checks, checkout, ready/draft, thread resolve)
- Launcher wizard (`new-launcher.sh`) moved from `scripts/` to `tmux/scripts/launchers/new.sh`
- Neovim: Theme setup runs before plugin load (ensures gitsigns, diffview pick up correct highlight groups)
- Neovim: IDE0079 diagnostic filter scoped to C# filetype in `dotnet.lua` (was global in `lsp.lua`)
- Neovim: Roslyn LSP `auto_refresh_codelens` disabled
- Neovim: PR review keybinding `<leader>ps` → `<leader>pf` (Find), added `<leader>psm` (squash merge)
- Neovim: Octo uses standard side-by-side diff (removed custom unified diff mode)
- Neovim: Octo `enable_builtin` disabled, `mappings_disable_default` enabled for cleaner keybinding control
- Neovim: Diff highlights no longer set Octo-specific highlight groups (uses core Vim diff groups)

### Removed

- `scripts/new-launcher.sh` (moved to `tmux/scripts/launchers/new.sh`)
- Health check: Removed `dana` command check
- Neovim: Custom unified review mode (toggle, hunk navigation, patch highlight parsing)
- Neovim: `<localleader>u` unified diff toggle and `]c`/`[c` hunk navigation in Octo reviews

## [0.2.20] - 2026-02-10

### Added

- Neovim: Dynamic diff highlights module (`diff-highlights.lua`) — computes tinted backgrounds from the active theme's Normal bg, consistent across fugitive, diffview, and octo
- Tmux: Window name restoration tests (custom names preserved, automatic-rename race condition covered)
- Brewfile: `luacheck` added as a Homebrew dependency
- Installer: `luacheck` added to core prerequisites check

### Changed

- Neovim: Removed hardcoded `Diff*` and `GitSigns*Ln/Nr` highlights from all 15 colourscheme files (now computed dynamically)
- Neovim: Moved Octo review highlight setup from `pr-review.lua` to shared `diff-highlights.lua`
- Makefile: `luacheck` target adds `--globals vim bit` for Neovim/LuaJIT compatibility
- Zsh: Shell startup performance — cached eval for direnv and fzf hooks, git branch caching for terminal titles, PATH deduplication via `typeset -U`
- Tmux: Status bar performance — inlined agent display function to avoid subshell forks, added 30s result cache for dotfiles sync status
- Neovim: Lazy-loading for guess-indent (`BufReadPost`), cheatsheet (`cmd`/`keys`), and fidget.nvim (`LspAttach`)
- Neovim: Migrated nvim-treesitter from deprecated `master` branch (`require('nvim-treesitter.configs').setup`) to new `main` branch API (`require('nvim-treesitter').install`, `vim.treesitter.start()`)
- Brewfile: Added `tree-sitter-cli` as a dependency (required by new nvim-treesitter for parser compilation)
- Brewfile: Updated Neovim version requirement comment from >= 0.9 to >= 0.11
- Installer: Added `tree-sitter-cli` to core prerequisites check
- Neovim: Markdown ordered list renumbering uses `CursorHold` (debounced) instead of `TextChanged` to avoid interference during edits

### Fixed

- Neovim: Dotnet solution filter now excludes all build variant solutions (`.ci.sln`, `.build.slnx`, `.test.sln`) instead of only `.ci.sln`
- Tmux: Alert show script used unreliable line count for empty check — replaced with `-n` string test
- Tmux: Window names overwritten by `automatic-rename` during resurrect restore — disabled per-window in Pass 1 before names are applied in Pass 2

## [0.2.19] - 2026-02-10

### Added

- Neovim: Custom colourscheme files in `nvim/colors/` for all 16 themes — removes dependency on 12 colourscheme plugins
- Theme contrast checker script (`scripts/theme-contrast-check`) — validates WCAG contrast ratios for theme files
- LazyGit and LazyDocker config files with reverse-video selection styling (works with any theme)
- Neovim: Vite/esbuild build config detection in quickfix build picker (`vite.config.*` marker)
- Launcher wizard: Worktree awareness step — optional worktree directory resolution for session launchers

### Changed

- Neovim: Quickfix Vite/esbuild config runs `check` (eslint + tsc) instead of `build` — finds more errors without producing artifacts
- Theme files: Refined accent colours and secondary foreground values across all themes for better contrast
- Neovim: Removed all colourscheme plugin dependencies from `ui.lua` — themes are now self-contained
- Gitsigns: Simplified highlight configuration to use built-in groups
- Themes README: Streamlined documentation to match simplified theme variable format
- Neovim: Quickfix window uses `botright` with `winfixheight` to prevent layout disruption when opening
- Neovim: Quickfix `<CR>` mapping preserves quickfix height after jumping to error location
- Neovim: Go `vet` errorformat handles `vet:` prefix and module comment lines
- Neovim: Makefile build targets use combined errorformat from all build configs

### Fixed

- `git-prune` alias uses `-D` (force delete) instead of `-d` — squash-merged branches weren't recognised as fully merged, causing "not fully merged" errors
- Neovim: Treesitter injection highlighting for markdown code blocks — use `nvim-treesitter.configs` module for proper language injection support
- Neovim: Treesitter `auto_install` disabled to prevent race condition — concurrent Neovim instances (e.g. neotest subprocess) would race to create the same tmp directory, causing `mkdir: tree-sitter-*-tmp: File exists` errors
- Neovim: C# syntax highlighting in markdown code fences — registered `csharp`/`cs` as aliases for the `c_sharp` treesitter parser
- Neovim: Quickfix build opens empty on success when tool output doesn't match errorformat — now validates parsed entries before opening
- Neovim: `grr` (LSP references) broken on Neovim 0.11 — `on_list` handler was passed as LSP context instead of options, causing "Cannot serialise function" error

## [0.2.18] - 2026-02-10

### Added

- Neovim: Quickfix build picker (`<leader>q`) — run project builds and populate quickfix with errors
  - Detects Go (`go vet`), TypeScript (`tsc`), .NET (`dotnet build`), and Makefile projects
  - TypeScript: Auto-detects package manager (bun/pnpm/yarn/npm) from lockfiles
  - Makefile: Parses build targets, shows numbered picker sorted by complexity
  - Buffer-aware: Walks up from current file to find nearest project marker
  - Progress: Shows fidget spinner during build
  - Only opens quickfix on failure (exit ≠ 0), shows "Succeeded" notification otherwise
  - ANSI codes stripped from output, quickfix height capped at 10 lines
- Neovim: .NET solution auto-selection — skips `.ci.sln`/`.ci.slnx` variants when only one non-CI solution exists
- Makefile: Git worktree management targets (`worktree-create`, `worktree-list`, `worktree-remove`)

## [0.2.17] - 2026-02-09

### Added

- Tmux: Edit launcher from picker (`e` key) — opens wizard pre-filled with existing values
- Shared library: `sanitise_launcher_name()` function in `common.sh` for reusable name validation

### Changed

- Tmux: Rename `agents/` directory to `instances/` for clearer naming (process instance management)
- Tmux: Reorganise all scripts into functional subdirectories (`sessions/`, `windows/`, `panes/`, `instances/`, `alerts/`, `launchers/`, `resurrect/`, `themes/`, `utils/`)
- Tmux: `new.sh` uses `new-window -P` to capture exact window target, avoiding name collisions with duplicate window names
- Tmux: URL picker keybinding changed from `Opt+y` to `prefix + y`
- Tmux: Launcher picker now supports half-page scroll (`Ctrl+d` / `Ctrl+u`)
- Tmux: Launcher picker uses "system launcher" terminology instead of "repo launcher"
- Tmux: Launcher picker (`prefix + p`) now sorts by most recently used (MRU) — last used launcher appears at top
- Tmux: `tmux.conf.template` updated with all new script paths
- Ghostty: Add `Cmd+Left` / `Cmd+Right` keybindings for Home/End
- Neovim: Add macOS-style navigation keybindings (`Opt+arrows`, `Opt+f/b`, `Home/End`) in normal, visual, and insert modes
- Neovim: PR review plugin flushes pending deletes before add lines for correct diff ordering
- Neovim: PR review plugin now uses custom highlight groups immune to gitsigns overrides
- Neovim: PR review plugin navigation (`]c`/`[c`) now jumps by hunks instead of individual lines
- Neovim: PR review plugin adds JetBrains-style gutter bars for modified sections
- Neovim: Gitsigns no longer defines `GitSignsDeleteVirtLn` (moved to PR review plugin as `OctoReviewDeleteVirtLn`)
- CI: ShellCheck glob updated for new subdirectory layout
- Zsh: `trestore` and `tkill` functions updated for new script paths
- CLAUDE.md: Updated directory structure and tmux scripts architecture documentation
- Launcher wizard: `--edit SOURCE` flag for editing existing launchers (rename, re-describe, modify windows)
- Launcher wizard: `ask()` now uses readline `-i` for editable default values instead of `[default]` hints
- Launcher name sanitisation extracted from `new-launcher.sh` into shared `sanitise_launcher_name()` function
- `new-launcher.sh` now sources `common.sh` instead of `colours.sh`
- `tnew` launcher: Minor description and help text cleanup

### Fixed

- Tests: Update Claude/nvim picker test paths for instances/ layout
- Tests: Normalise TMPDIR handling in nvim sync test to avoid invalid socket paths
- Tmux: Launcher picker rewritten for Bash 3.2 compatibility (macOS default bash, no associative arrays)
- Tmux: Launcher picker uses explicit cleanup instead of EXIT trap to avoid scope issues in pipes

## [0.2.16] - 2026-02-09

### Added

- Tmux: Session launcher picker (`prefix + p`) — create, run, and delete session launchers
- Tmux: Launcher wizard (`new-launcher.sh`) — step-based interactive scaffolding for new launchers
- Tmux: Theme-aware dotfiles logo in session, window, and launcher pickers
- Tmux: `require_fzf()` helper in common.sh for fzf dependency checks
- Tmux: Launcher path constants (`USER_LAUNCHERS`, `DOTFILES_LAUNCHERS`) in shared library
- Neovim: Markdown display improvements (wrap, conceallevel, visual line nav)
- Zsh: Ghostty TERMINFO fix for local and SSH sessions
- Tests: `test-launchers.sh` — 50 tests covering launcher management scripts
- Tests: `--pos` flag tests for theme picker
- Tests: Process tree ancestor-walking tests for Claude detection

### Fixed

- Security: Sanitise user input in fzf `become()` commands to prevent command injection
- Security: Escape single quotes in generated `send-keys` commands
- Security: Path traversal protection in `delete-launcher.sh` via basename guard
- DRY: Extracted `find_dotfiles_root()` from 3 scripts into shared `common.sh`
- Shebang: `list-launchers.sh` changed from `#!/bin/bash` to `#!/usr/bin/env bash`

### Changed

- Launcher name validation: length cap (64), strip leading dots/dashes, block reserved words
- Window count capped at 20 in launcher wizard
- `pick-theme.sh` and `list-launchers.sh` refactored to source `common.sh`

### Removed

- `launchers/dana` — use the launcher wizard (`prefix + p` → `n`) to create project launchers
- `launchers/code` — VS Code's `code` command is available via shell integration

## [0.2.15] - 2026-02-08

### Fixed

- Installer: `get_homebrew_prefix()` now returns correct Linux Homebrew path (`/home/linuxbrew/.linuxbrew`) instead of assuming macOS
- Installer: `xcode-select` no longer called on Linux — installs build prerequisites via apt/yum instead
- Installer: `brew bundle` no longer fails on Linux due to cask entries — cask lines filtered out on non-macOS
- Installer: Claude Code install no longer aborts entire installation on failure
- Installer: `brew list --cask` guarded behind `is_macos` (casks don't exist on Linux)
- Installer: Prerequisites checker now shows platform-appropriate install hints (apt on Linux, brew on macOS)
- Installer: macOS-only tools (swift-format, Karabiner, Hammerspoon, Ghostty app check) skipped on Linux

### Added

- `is_linux()` helper in common.sh for platform detection

## [0.2.14] - 2026-02-08

### Added

- Tmux: `new-instance.sh` - create new process window from picker (`n` key in Claude/OpenCode/nvim pickers)
- Tmux: `kill-instance.sh` - kill process in pane from picker with confirmation (`x` key in Claude/OpenCode/nvim pickers)
- Neovim: neotest-golang adapter (gotestsum runner, pinned to v1.15.1 for treesitter compatibility)
- Neovim: neotest-vitest adapter for Bun/TypeScript tests (`bun run test`)

### Changed

- Neovim: Fugitive review mode now shows deleted/old lines inline via gitsigns `show_deleted`
- Neovim: LSP go-to-definition, references, implementations, and type-definition now deduplicate results and display via Telescope
- Neovim: `<leader>q` diagnostic quickfix now filters to warnings and errors (skips hints/info)
- Neovim: Telescope path display changed to filename-first for easier scanning
- Neovim: Octo `]f` (next file) now marks the current file as viewed; `[f` (prev file) does not
- Neovim: Octo unified mode is the default when starting a review (toggle with `<localleader>u`)
- Tmux: list-claude, list-nvim, and list-opencode scripts refactored for performance — batch process detection, pre-fetched window names, and parameter expansion replace per-pane subshells
- Tmux: Claude, OpenCode, and nvim pickers now support `n` (new instance) and `x` (kill instance) inline actions
- Tmux: Removed `f`/`b` copy mode bindings for page navigation (use `Ctrl+f`/`Ctrl+b` instead)
- Installer: Unmigrated `local-aliases.zsh` content is now automatically appended into `~/.zshrc` during symlink creation

### Added

- Neovim: Octo unified review mode — single-pane PR diffs with gitsigns-style added/deleted line highlights and inline deleted lines as virtual text
- Neovim: `]c`/`[c` navigation between individual changed lines in Octo unified review mode
- Neovim: `<localleader>u` toggle between unified and side-by-side diff in Octo reviews
- Neovim: `GitSignsDeleteVirtLn` highlight group for inline deleted lines
- Neovim: Cheatsheet entries for VCS (Fugitive), test runner, .NET, snippets, window resize, and PR review navigation
- Neovim: `q` and `<leader>vc` keybindings to close fugitive status and cleanly exit review mode
- Tmux: Click session name in status bar to open session switcher popup
- Zsh: `git-prune` alias to delete local branches removed from remote
- Tmux: `is_pane_running()` helper in common.sh for checking active foreground processes in a pane (excludes suspended)

### Fixed

- Neovim: Filtered out Roslyn IDE0079 false-positive diagnostic ("Remove unnecessary suppression")

## [0.2.13] - 2026-02-06

### Changed

- Zsh: Inverted config architecture — `~/.zshrc` is now your personal file (not a symlink), sourcing `dotfiles.zsh` as a framework
- Zsh: Removed `local-aliases.zsh` system — personal config goes directly in `~/.zshrc`
- Installer: Migrates existing symlink users automatically, preserving `local-aliases.zsh` content

### Added

- `zsh/dotfiles.zsh` — shared framework extracted from the old `zshrc`
- `zsh/zshrc.template` — template for creating user's personal `~/.zshrc`
- `zsh/zshrc` — backwards-compat wrapper for unmigrated symlink users

### Fixed

- Installer: `DOTFILES_DIR` resolution now always produces absolute paths, preventing broken relative symlinks

## [0.2.12] - 2026-02-05

### Changed

- Installer: Claude Code now installed natively via `claude.ai/install.sh` instead of Homebrew cask — automatically uninstalls brew version if present
- Neovim: Added `<leader>lr` keybinding for LSP restart

### Fixed

- Neovim: mkdnflow to-do config uses correct `marker` field (renamed from `symbol` in upstream API)
- Tmux: list-nvim script no longer exits early when grep/ps/lsof return no matches (`|| true` guards)

## [0.2.11] - 2026-02-05

### Added

- Neovim: Octo PR review keybindings — `<leader>pe` (resume), `<leader>pm` (submit), `<leader>pp` (approve), `<leader>pa` (add comment)

### Fixed

- Neovim: Neo-tree crash on deleted files in git status — runtime patch via `debug.setupvalue` handles missing parent directories gracefully
- Neovim: Markdown list renumbering now uses `undojoin` so renumbering and the preceding edit are a single undo step

## [0.2.1] - 2026-02-05

### Added

- Neovim: Fugitive integration with custom status workflow — `<leader>vs` (status), `<leader>vb` (blame), `<leader>vd` (diff split)
- Neovim: Fugitive review mode with gitsigns line/number highlighting for changed files
- Neovim: .NET development via easy-dotnet.nvim with Roslyn LSP (replaces OmniSharp)
- Neovim: Neotest test runner with .NET adapter and `.slnx` support
- Neovim: Window resize keybindings (`<leader>wh/wl/wj/wk`)
- Neovim: `<leader>v` (VCS) and `<leader>w` (Window resize) which-key groups
- Neovim: Telescope path display shows `parent/file.ext` instead of truncated paths
- Neovim: Statusline branch name truncated to ticket ID (e.g. `DANA-123`)
- Neovim: Octo `]f`/`[f` navigation auto-marks files as viewed
- Karabiner: Right Option → Control scoped to Ghostty and JetBrains IDEs only
- Installer: `gh-dash` extension installed automatically
- Zsh: `.dotnet/tools` added to PATH for .NET global tools

### Changed

- Neovim: Nerd Font enabled by default (`have_nerd_font = true`)
- Neovim: Gitsigns hunk navigation no longer wraps around buffer
- Neovim: Gitsigns `<leader>hu` now correctly calls `undo_stage_hunk` instead of `stage_hunk`
- Neovim: Gitsigns highlight colours explicitly set (resilient to colourscheme changes)
- Neovim: Which-key loads immediately instead of on VimEnter for reliable leader preview
- Neovim: Removed jsonls LSP server
- Neovim: Diffview patched to guard against invalid window IDs (upstream bug workaround)
- Neovim: Octo patched to pass buffer context to mappings (upstream bug workaround)
- Karabiner: Right Option → Control changed from global simple modification to app-scoped complex rule
- Tmux: New sessions now name first window "zsh" instead of default
- Neovim: Disabled swap files for Octo buffers

### Removed

- Neovim: difi.nvim (replaced by fugitive review mode)
- Neovim: OmniSharp LSP (replaced by Roslyn via easy-dotnet.nvim)

## [0.2.0] - 2026-02-03

### Added

- Neovim: PR review workflow — diffview.nvim (side-by-side diffs), octo.nvim (GitHub PRs), difi.nvim (inline overlay)
- Neovim: Markdown editing with mkdnflow.nvim (list continuation, todo toggles, table formatting)
- Neovim: `<leader>d` keybinding group for diff operations, `<leader>p` for PR review
- Neovim: Comprehensive cheatsheet covering all keybindings (git, diff, PR, debug, markdown, theme)
- Brewfile: difi CLI (oug-t/difi tap) for inline diff TUI

### Changed

- Neovim: Cheatsheet now uses `<leader>` notation consistently instead of mixed `Space`/`<leader>`

## [0.1.17] - 2026-01-28

### Added

- Tmux: Nvim instance picker (`prefix + n`) with buffer sync integration
- Tmux: `list-nvim.sh` - Lists all running nvim instances with working directories
- Tmux: `connect-nvim.sh` - Connects nvim to a Claude pane for buffer sync
- Hooks: `nvim-buffer-sync.sh` - Claude Code hook that adds edited files to paired nvim's buffer list
- Neovim: Auto-cleanup of unnamed empty buffers on BufEnter
- Tests: `test-nvim-sync.sh` - E2E tests for nvim buffer sync flow

### Fixed

- Tests: `test-session-management.sh` now uses colours from test helpers (fixes readonly variable error)
- Tests: `test-tmux-libs.sh` shellcheck exclusions now match CI configuration

## [0.1.16] - 2026-01-28

### Added

- Neovim: `Space sl` keymap for "go to line" functionality
- Tests: Session renaming test suite (`test-rename-session.sh`)
- Tests: Assertion helpers in test framework (assert_equals, assert_success, assert_failure)
- README: btop configuration directory documented in Contents section

### Changed

- Neovim: Replaced eslint_d linter with ESLint LSP server for improved integration
- Neovim: Updated cheatsheet keybinding from `Space sk` to `Space ?` in help text
- Tmux: Session rename script now outputs new session name for better script integration

### Fixed

- Scripts: Colours library now guards against multiple sourcing to prevent readonly variable errors
- Tmux: Alert library improved with safer grep operations and ALERTS_FILE guard

## [0.1.15] - 2026-01-26

### Added

- Launchers: Template file (`launcher.template`) for creating new project launchers
- Neovim: Custom gruvbox-dark colourscheme matching terminal theme exactly
- Dana launcher: Now reads `DANA_ROOT` from local aliases (falls back to `~/src/dana`)
- Neovim: Custom cheatsheet.txt for `Space ?` with actual keybindings
- Neovim: Auto-save on text change with auto-reload for external changes
- Neovim: `Space cc` and `Space cu` keymaps for Claude comment snippets
- Neovim: C# syntax highlighting support (treesitter parser alias)
- Neovim: LSP hover and signature help now use bordered windows
- Neovim: 10 new theme plugins (gruvbox, solarized, one-dark, monokai, ayu, everforest, kanagawa, rose-pine, nightfox, synthwave)
- Themes: 10 new theme definitions with full tmux/ghostty/nvim/fzf support
- Themes: README.md documenting theme system architecture and how to add themes
- Themes: `theme-defaults.sh` for automatic derivation of status bar, pane borders, and FZF colours from base colours
- btop: System monitor configuration (htop replacement)

### Changed

- Agent alerts: Aggregates alerts per session instead of per window for cleaner status bar display
- Neovim: Cheatsheet plugin now reads from custom cheatsheet.txt instead of bundled defaults
- Neovim: Improved formatting for `claudecomment` snippet (proper newlines)
- **Theme architecture**: Refactored to use automatic defaults instead of duplicating colours across files
  - Theme files now only define base colours and accents
  - Status bar, pane borders, FZF colours automatically derived via `theme-defaults.sh`
  - Reduced duplication and ensured consistency across all themes
  - Each theme specifies active accent colour (purple, cyan, or green)
- Tmux: Window rename alert updates now use file locking to prevent race conditions
- Tmux: Removed redundant alert clearing from `rename-window.sh` (handled by hook)
- **Directory structure**: Simplified by removing nested dotfile prefixes
  - `zsh/.zshrc` → `zsh/zshrc`, `zsh/.zprofile` → `zsh/zprofile`, etc.
  - `zsh/.zsh/` directory removed (templates now in `zsh/`)
  - `tmux/.tmux/` → `tmux/` (flattened)
  - `tmux/.tmux.conf.template` → `tmux/tmux.conf.template`
- User secrets and local aliases now use XDG location (`~/.config/zsh/`)
  - `~/.zsh/.secrets.zsh` → `~/.config/zsh/secrets.zsh`
  - `~/.zsh/.local-aliases.zsh` → `~/.config/zsh/local-aliases.zsh`
- Ghostty config is now generated (removed from repo, created by `theme-switch`)
- Tmux symlink now points to entire `tmux/` directory instead of nested `.tmux/`

### Fixed

- Agent alerts: Stricter validation for alert entries to prevent malformed data
- Tmux: Window rename alert updates now properly handle concurrent rename operations
- Tmux: Improved session restoration error handling in `restore-resurrect.sh` (suppressed spurious errors, added verification)
- Themes: Fixed colour harmony issues across multiple themes
  - Rose Pine: Corrected green/cyan swap (green was blue `#31748f`, now proper teal `#9ccfd8`)
  - Ayu Dark, Monokai, Nord, One Dark: Differentiated pink and red accent colours (were identical)
  - Gruvbox: Separated pink from red using proper Gruvbox purple/pink distinction
  - Solarized Dark: Fixed autocomplete visibility (palette 8 was same as background)
  - Solarized Dark: Corrected bright palette to match canonical Solarized specification
- Themes: Updated `theme-defaults.sh` to support `pink`, `yellow`, and `red` as active accents
- Themes: Adjusted default active accents for better visual appeal per theme
- Themes: Bell/alert colour now uses theme's active accent instead of hardcoded pink
- Themes: Tmux session name colour now follows theme accent for visual consistency

### Removed

- `ghostty/config` - now generated by theme-switch to XDG location
- `tmux/.tmux.conf` - replaced by template-based generation

### Documentation

- Neovim README: Added snippets directory, LuaSnip, and cheatsheet plugin
- Themes: Comprehensive README.md documenting how to add new themes
- README.md: Added themes directory to repository structure

## [0.1.14] - 2026-01-25

### Added

- Resurrect restore: Pane contents restoration (scrollback history)
- Resurrect restore: Command/process restoration for configured processes
- Resurrect restore: Restore-all functionality for batch session restoration
- Resurrect restore: Field validation and duplicate detection for malformed backups
- Resurrect restore: Pane readiness polling to prevent race conditions
- Theme system: XDG-compliant tmux config location (`~/.config/tmux/tmux.conf`)
- Theme system: Template processing to prevent git conflicts from theme switching
- Theme system: Migration script (`scripts/migrate-tmux-config.sh`) for existing users
- Tests: Comprehensive resurrect restore test suite (14 test functions)
- Tests: Fuzzy process matching tests for tilde prefix patterns
- Zsh: Tab completion for `trestore` CLI options

### Changed

- Tmux config: Now uses XDG location with backwards-compatible symlink
- Test helpers: Consolidated into `_test-helpers.sh` (removed duplication)
- Create-symlinks: TTY check for non-interactive environments (CI)

### Fixed

- Security: Path traversal validation for session names in resurrect-restore
- Security: Command sanitisation before `tmux send-keys` (prevents injection)
- Security: Quote escaping in pane creation commands
- Theme-switch: Quiet mode now suppresses error messages
- Window-move: Input format validation for session:window argument
- Test: Theme-switch ghostty process check (case-insensitive)

## [0.1.13] - 2026-01-22

### Added

- ASCII logo displayed at start/end of installation and in CLI tools
- Local aliases system: Machine-specific project aliases via `.local-aliases.zsh`
- Template file `.local-aliases.zsh.template` for easy customisation
- Installer prompt to create local aliases from template
- Comprehensive local aliases documentation in `zsh/.zsh/README.md`
- Neovim: Custom Copilot suggestion highlighting (italic, subdued colour matching Comment highlight)
- Neovim: `:CopilotHighlightFix` command to manually fix Copilot highlighting if needed

### Changed

- Dotfiles CLI: Prettier status/update output with improved formatting
- All installation scripts now use `printf` for coloured output instead of `echo`
- Installer checks for local aliases configuration during symlink creation
- Theme-switch: Shows informational message when not in tmux
- Tmux: Updated theme colours from Tokyo Night to Catppuccin Mocha for improved visual consistency
- Neovim: Copilot suggestions now use distinct italic styling to differentiate from regular code

### Fixed

- Tmux: FZF label colour updated for Catppuccin theme consistency
- Neovim: Copilot suggestions now properly styled across all colourschemes with fallback grey colour

### Removed

- Brewfile: Removed Docker cask (now managed separately)

## [0.1.12] - 2026-01-22

### Added

- Theme system: Coordinated colour schemes across tmux, ghostty, and neovim
- Themes: Four built-in themes (Dracula, Catppuccin Mocha, Tokyo Night, Nord)
- `theme-switch` CLI tool for switching themes with live reload
- Tmux: Theme picker (`prefix + t`) with fzf interface and vim-style navigation
- Tmux: Template-based configuration (`.tmux.conf.template`) for dynamic theming
- Ghostty: Template-based configuration (`config.template`) for dynamic theming
- Neovim: Theme module (`lua/custom/core/theme.lua`) with file watcher for automatic reload
- Scripts: `colours.sh` library for consistent colour definitions across scripts
- Scripts: `fzf-theme.sh` for applying theme colours to fzf interfaces
- Scripts: `ghostty-reload.sh` for live ghostty config reload on theme change
- Scripts: `fzf-reload.sh` for live fzf theme reload in tmux
- Tmux: OpenCode instance picker (`prefix + o`) matching Claude picker functionality
- Tmux: FZF theme integration across all pickers (sessions, windows, Claude, OpenCode, URLs, themes)
- Tests: Comprehensive theme validation suite (`test-theme-validation.sh`, `test-theme-switch.sh`, `test-fzf-theming.sh`, `test-theme-installation.sh`)
- Tests: Ghostty reload tests (`test-ghostty-reload.sh`)
- Tests: Theme picker tests (`test-theme-picker.sh`)
- `Makefile` with shortcuts for common tasks (test, lint, install, clean)
- Dotfiles CLI: `theme-switch` integration for centralized theme management

### Changed

- Tmux: Unbound `prefix + t` (clock) to make room for theme picker
- Tmux: All fzf popups now source `fzf-theme.sh` for consistent theming
- Tmux: Window/session rename dialogs now source fzf theme
- Common library: Refactored colour definitions to use central `colours.sh`
- Neovim: `auto-dark-mode.nvim` plugin disabled when dotfiles theme is active
- Neovim: TreeSitter configuration updated for new API
- UI library: Updated to use `printf` for coloured output (not `echo`)

### Fixed

- Theme-switch: Function name conflict with tmux `info` command (renamed to `print_info`)
- Theme-switch: Unbound variable error when called with no arguments
- Test suite: GREY colour variable conflict (now sourced from colours.sh)
- Test suite: Theme name expectations made flexible for different active themes

## [0.1.11] - 2026-01-14

### Added

- Tmux: `cleanup-tests.sh` script to clean up orphaned test servers and session backups
- Tmux: `tcleanup` shell alias for test cleanup script
- Tmux: trap handlers in test scripts for automatic cleanup on exit/interrupt
- Scripts: `run-tests.sh` - dynamic test discovery runner with per-suite summaries
- CI: ShellCheck now lints test scripts in `tmux/.tmux/scripts/tests/` and `scripts/tests/`
- CI: Dynamic test discovery automatically finds and runs all test files
- Ghostty: `opt+up` and `opt+down` keybindings for terminal navigation
- Karabiner: Caps Lock → Escape mappings for JetBrains IDEs (Rider, WebStorm, GoLand)
- Tmux: `Opt+=` keybinding to split pane upward (complements `Opt+-` for split down)

### Changed

- CI: Replaced manual test execution with dynamic discovery via `run-tests.sh`
- CI: Renamed "Library Tests" job to "All Tests" to reflect comprehensive coverage
- Tests: Standardised patterns in test runner (boolean comparisons, counter management, skip handling)
- Tmux: Reformatted help popup (`prefix+h`) with cleaner layout and adjusted dimensions (74x41)
- Tmux: Simplified fzf session/window switcher keybindings - removed page navigation (`f`/`b`) and half-page (`d`/`u`) keys, now use only `j`/`k` for navigation
- Tmux: Changed kill/undo keybindings from `alt+x`/`alt+u` to `x`/`u` in fzf switchers for better ergonomics
- Tmux: Updated border labels and keybinding hints in session and window switchers to reflect simplified navigation
- Tmux: Renamed scripts for better organisation and consistency:
  - Session management: `list-sessions.sh` → `session-list.sh`, `new-session.sh` → `session-new.sh`, `rename-session.sh` → `session-rename.sh`
  - Window management: `list-windows.sh` → `window-list.sh`, `rename-window.sh` → `window-rename.sh`, `duplicate-window.sh` → `window-duplicate.sh`, `move-window.sh` → `window-move.sh`
  - Utilities: `timestamp.sh` → `update-timestamp.sh`, `tmux-confirm.sh` → `fzf-confirm.sh`, `agent-alert-clear.sh` → `agent-alerts-clear.sh` (plural)
- Tmux: Deleted `clear-claude-alert.sh` (functionality consolidated into `agent-alerts-clear.sh`)
- Tmux: Renamed test file `test-fzf-confirm-kill.sh` → `test-kill-confirmations.sh` for clarity
- Tmux: Updated all script references in `.tmux.conf` and hooks to use new filenames
- Docs: Updated README file structure listing to reflect renamed scripts

### Fixed

- Tmux: test scripts now properly clean up resources even when interrupted
- CI: Now runs all 12 tests instead of only 4 (discovered 8 previously uncovered tests)
- Tmux: unbind default `prefix+x` keybinding to prevent accidental pane kills (use `Opt+s` for kill-pane, `Opt+x` for kill-window)

### Added

- Tmux: Comprehensive resurrect testing suite covering path discovery, split operations, restore operations, and edge cases
- Scripts: Documentation for SCRIPT_DIR pattern standardization across shell scripts
- CI: Resurrect tests now run automatically via dynamic test discovery

### Changed

- Tmux: Migrated undo file storage from `/tmp/tmux-undo-*` to XDG-compliant `${XDG_CACHE_HOME}/tmux/undo/` with automatic migration
- Tmux: Standardized session validation error handling across `new-session.sh` and `rename-session.sh`
- Scripts: Updated `new-session.sh` to use production SCRIPT_DIR pattern (`${BASH_SOURCE%/*}`)
- Tests: Updated test expectations to match XDG-compliant undo paths
- OpenCode alerts: Fixed `agent-alert.sh` to work reliably when `$TMUX_PANE` environment variable is not set, improving alert delivery from OpenCode plugin hooks
- Tmux: Fixed terminal dimension detection in `ui.sh` to use `LINES`/`COLUMNS` environment variables when available (tmux popups), falling back to `tput` for better compatibility

## [0.1.10] - 2026-01-14

### Added

- Scripts: `scripts/hooks/wrappers/` - subdirectory for agent-specific alert wrappers
- Scripts: `scripts/hooks/wrappers/opencode-alert.sh` - OpenCode alert wrapper (placeholder)
- Tmux: Agent visual identity system (Claude ⚡ yellow, OpenCode 🔮 purple, fallback 🤖 blue)
- Tmux: `get_agent_display()` helper function for agent icons and colours
- Tmux: Dynamic wildcard clearing for all `@*_alert` options (agent-agnostic)
- Tmux: Confirmation dialogs when closing last pane/window in a session

### Changed

- Scripts: Moved `claude-alert.sh` to `scripts/hooks/wrappers/` subdirectory
- Scripts: Renamed `agents-alert-clear.sh` → `agent-alert-clear.sh` for consistency
- Tmux: `agent-alerts.sh` now displays agent-specific icons with colours
- Tmux: `update-alert-on-rename.sh` fixed to handle 3-field format (session:window:agent)
- Tmux: Alert library enhanced with multi-agent icon/colour configuration
- Tests: Updated `test-list-claude.sh` to check for `ALERTS_FILE` instead of `CLAUDE_ALERTS_FILE`

### Removed

- Scripts: `claude-alert-clear.sh` (broken 2-field regex, replaced by library)

## [0.1.9] - 2026-01-12

### Added

- Scripts: `agent-alert.sh` - generic foundation for multi-agent alert support
- Scripts: `agent-alert-clear.sh` - unified alert clearing across agents
- Tmux: `move-window.sh` script for window management

### Changed

- Tmux: refactored alert system with `session:window:agent` format (internal) for future multi-agent support
- Tmux: renamed `claude-alerts.sh` to `agent-alerts.sh` reflecting generic architecture
- Scripts: `claude-alert.sh` simplified to wrapper around `agent-alert.sh`
- Tmux: `list-claude.sh` now sorts by last-viewed timestamp for better recency ordering
- Tmux: alert clearing centralized with `clear_window_alerts()` function

### Fixed

- Scripts: `/dev/tty` unavailable errors in hook scripts
- Tmux: alert display deduplicates windows when multiple agents present
- Tmux: session and window pickers correctly show alerts with new internal format

## [0.1.8] - 2026-01-11

### Added

- Tmux: Claude instance switcher with fzf (`prefix + c`) - shows all running Claude Code instances across sessions with alerts highlighted
- Tmux: automatic alert tracking update when windows are renamed (prevents stale alerts)
- Hammerspoon: Notion app added to auto-centre windows on creation

### Changed

- `list-claude.sh` now outputs fzf-friendly format (use `--verbose` flag for coloured CLI output)
- `prefix + c` keybinding added for interactive Claude instance switcher

### Removed

- `tclaude` shell command (replaced by `prefix + c` fzf picker)

### Fixed

- Tmux: stale Claude alerts persisting after window renames
- Tmux: improved alert file handling with literal string matching

## [0.1.7] - 2026-01-11

### Fixed

- Hammerspoon auto-center: removed invalid `setAlpha()` calls causing errors
- Hammerspoon auto-center: position-based detection prevents window flicker when opening URLs from browser

## [0.1.6] - 2026-01-11

### Added

- `uninstall.sh` script with preset-aware Homebrew package removal
- Inline backup during symlink creation (handles existing files gracefully)
- Rollback now works from backups even after successful installation

### Changed

- Replaced deprecated `neofetch` with `fastfetch` (faster, actively maintained)
- Prerequisites check now uses app paths for casks (Ghostty, Karabiner)
- nvim-treesitter updated to new API (no longer uses deprecated `.configs` module)

### Fixed

- Homebrew PATH not available in step 2 of fresh installations (subshell PATH issue)
- Bun formula not found on fresh installs (now uses `oven-sh/bun` tap)
- Removed deprecated `homebrew/bundle` and `homebrew/cask-fonts` taps
- `sqld` formula not found (now uses `libsql/sqld` tap)
- `speedtest` formula not found (now uses `teamookla/speedtest` tap)
- Removed `turso` (build issues on ARM)
- Invalid Ghostty keybind removed
- Symlinks now created even when files already exist (backed up inline)
- First-time nvim launch no longer errors (pcall fallback for treesitter)

## [0.1.4] - 2026-01-11

### Added

- `tclaude` command to list all running Claude Code instances across tmux sessions
- `tmux/.tmux/scripts/list-claude.sh` script for tracking Claude processes
- `~/.local/launchers` added to PATH for launcher script discovery

## [0.1.3] - 2026-01-11

### Added

- **Dotfiles CLI** (`scripts/dotfiles`): Manage your installation with simple commands
  - `dotfiles update`: Pull latest changes and re-run installer with saved preset
  - `dotfiles status`: Show sync status and local changes
  - `dotfiles sync`: Preview incoming changes without applying
  - `dotfiles health`: Run full health check
  - `dotfiles edit`: Open dotfiles directory in $EDITOR
  - `dotfiles cd`: Print dotfiles path for navigation
- `launchers/code`: VS Code dynamic launcher using macOS Spotlight
- `visual-studio-code` and `docker` casks to Brewfile (Containers & Infrastructure section)
- Tmux status bar sync indicator (↓↑↕) shows when dotfiles are behind/ahead of origin
- Shell startup profiling with `zsh-profile` and `zsh-profile-detailed` functions
- Tab completion for `dotfiles` command in zsh
- **Nvim LSP/Treesitter**: Expanded language support
  - LSP servers: bashls, cssls, html, jsonls, yamlls
  - Treesitter parsers: C#, CSS, Go, JavaScript, JSON, Python, TypeScript/TSX, YAML
  - Formatters: goimports, prettier (JS/TS/JSON/YAML)
  - Linter: golangci-lint

### Changed

- Dotfiles CLI installed to `~/.local/bin/dotfiles` (XDG-compliant)
- Installer saves preset to `~/.config/dotfiles/preset` for future updates
- Nvim Mason tool installer reorganised for clearer LSP server vs formatter/linter separation

### Fixed

- Header centering calculation in `print_header` function
- Nvim LSP cursor position errors when jumping to invalid locations

## [0.1.2] - 2026-01-11

### Added

- **Install presets**: Three installation modes for different use cases
  - `--minimal`: zsh + tmux only (servers, remote machines)
  - `--core`: minimal + nvim, ghostty, AI/CLI tools, session launchers (cross-platform dev)
  - `--full`: core + Hammerspoon, Karabiner, music-presence (macOS power user)
- Brewfile sections with `# @preset:` markers for preset-based filtering
- Preset-aware scripts: backup, symlinks, health-check, prerequisites all respect preset
- Test suite for preset filtering and `should_install` helper function
- Session launchers directory (`launchers/`) added to PATH in .zprofile

### Changed

- **Renamed**: `bin/tm` → `launchers/tnew`, `bin/ta` removed (use `tattach` function)
- **Renamed**: `bin/dana` → `launchers/dana`
- Moved `music-presence` cask to full preset (macOS-only)
- Installation guide updated with preset documentation
- TPM (Tmux Plugin Manager) pinned to v3.1.0 for reproducibility

### Fixed

- Security: command injection vulnerability in zsh preexec function
- Security: hardcoded username paths in .zprofile replaced with $HOME
- Security: path traversal vulnerability in rollback restore
- Security: race condition when creating secrets file (now uses umask)
- Health check exit code now reflects all check failures
- DOTFILES_DIR default derived from script location instead of hardcoded path
- Install preset validation rejects invalid values with clear error
- Backup directory names include PID for uniqueness

## [0.1.1] - 2026-01-11

### Added

- `alerts.sh` library: centralised alert utilities for tmux scripts
- `list-windows.sh`: window listing script with ⚡ indicator for Claude alerts
- Session switcher now shows ⚡ indicator for sessions containing Claude alerts

### Fixed

- Claude alerts now properly cleared when killing windows or sessions (prevents orphaned alerts)
- Window timestamp hook clears alerts as safety net when switching windows
- alerts.sh: prevent errexit from triggering on grep exit code 1

## [0.1.0] - 2026-01-10

Initial public release of the dotfiles configuration.

### Core Configuration

#### Zsh

- Powerlevel10k prompt with custom configuration
- fnm (Fast Node Manager) integration with auto-switching
- fzf integration for fuzzy finding
- Comprehensive aliases for git, docker, and common operations
- Modular structure with secrets file support

#### Tmux

- Custom keybindings with Option-key navigation
- fzf-based window and session switchers
- Undo system for killed windows, panes, and sessions
- Claude Code integration with alert notifications
- Session resurrection with per-session backups
- Custom scripts library with validation and UI helpers

#### Neovim

- Based on kickstart.nvim with modular plugin organisation
- LSP support via Mason (gopls, pyright, ts_ls, lua_ls, clangd, omnisharp)
- Completion with blink.cmp
- GitHub Copilot integration
- LazyGit integration
- Auto dark/light mode following system theme (Dracula/Catppuccin)
- Telescope for fuzzy finding
- Neo-tree file explorer
- Treesitter syntax highlighting

#### macOS Applications

- Hammerspoon: auto-centre windows for Ghostty, Arc, Dia, JetBrains IDEs, Discord, Slack
- Karabiner-Elements: Caps Lock to Escape/Control, UK keyboard layout fixes
- Ghostty terminal configuration

### Project Tooling

- `launchers/tnew`: Generic tmux development session launcher
- `launchers/dana`: Dana project-specific multi-window tmux session
- Automated installation script with rollback support
- Health check and prerequisites verification scripts
- CI workflow with shellcheck, stylua, and library tests

### Documentation

- Comprehensive README with installation guide and keybinding reference
- Troubleshooting guide with common issues and solutions
- Per-component README files (tmux, nvim, hammerspoon, etc.)

### Added

- Help text (`-h`/`--help`) for `launchers/dana`, `launchers/tnew`, and install scripts
- Dana project launcher documentation in README.md
- macOS and Linux compatibility badges in README.md
- `show_error()` helper function in common.sh for popup error display
- UI error messages in undo-window.sh and undo-session.sh
- Discord and Slack to Hammerspoon auto-centre apps
- Extended troubleshooting guide: common error messages table, Linux/macOS platform differences, fnm/Node.js issues, ANDROID_HOME issues, installation failure recovery
- kill-window.sh now supports target argument (`session:window`) for use from fzf picker

### Changed

- **Tmux script naming convention**: renamed session scripts for consistency
  - `session-kill.sh` → `kill-session.sh`
  - `session-new.sh` → `new-session.sh`
  - `session-rename.sh` → `rename-session.sh`
  - `session-undo.sh` removed (consolidated into `undo-session.sh`)
  - `window-kill.sh` removed (consolidated into `kill-window.sh`)
- `session_exists()` now uses exact match (`grep -qxF`) instead of prefix match
- rename-window.sh: improved fzf prompt styling with border and labels
- undo-session.sh: now uses shared library functions and UI helpers
- Neovim README.md: complete rewrite with proper structure and documentation
- Updated LICENSE copyright year to 2026

### Fixed

- ANDROID_HOME PATH issue: conditional check prevents invalid PATH entry when variable is unset
- Alert file operations: use `grep -F` for fixed string matching to prevent regex metacharacter issues
- rename-window.sh: disabled automatic-rename after manual rename to preserve custom names
- undo-window.sh: restores automatic-rename setting correctly
- rename-session.sh: proper error handling with show_error() for popup context
- .tmux.conf: updated script references from `window-kill.sh` to `kill-window.sh`
