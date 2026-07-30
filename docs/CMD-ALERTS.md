# Command Exit Alerts

Run a long command in a tmux window, switch away, and get notified automatically when it finishes. Pass/fail results show as icons in the tmux status bar; the same system used for agent alerts.

No wrapping required. Any command that completes while you're in a different window will trigger an alert.

## How It Works

```
You run: make test  (then switch to another window)
  → make test runs normally
  → Command exits (code 0 or non-zero)
    → precmd hook fires
      → Elapsed ≥ threshold (default 1s) AND you've moved away (window or session)?
        → cmd-alert.sh sets exit alert
          → Bell rings + window tab highlights green or red
          → Status bar shows ✓ or ✗ for other sessions

You switch back to the window
  → after-select-window hook fires
    → Alert clears automatically
```

The hooks (`preexec`/`precmd`) are registered in `zsh/dotfiles.zsh` and run transparently; zero overhead on the command itself.

## Alert Display

| Result  | Icon | Colour | Meaning                                      |
| ------- | ---- | ------ | -------------------------------------------- |
| Pass    | ✓    | Green  | Exit code 0                                  |
| Fail    | ✗    | Red    | Exit code non-zero                           |
| Stopped | ⊘    | Grey   | Killed by a signal (exit > 128, e.g. Ctrl-C) |

A process terminated by a signal exits with `128 + signal` (Ctrl-C is 130, SIGTERM 143, SIGKILL 137). Those are interruptions you caused, not run-to-completion failures, so they show neutral grey rather than red.

### Status bar

Icons appear in the right side of the status bar for commands in **other sessions**, showing `session:command` for context:

- `✓ dev:make test`: tests passed in the `dev` session
- `✗ build:npm run lint`: linting failed in the `build` session

Same-session alerts only highlight the window tab (no status bar entry).

### Window tabs

The window tab colour changes:

- Green for pass
- Red for fail

## Conditions for Alerting

An alert fires only when **all** of the following are true:

1. You are inside tmux
2. You moved away before the command finished, to a different window **or** a different session
3. The command is not in the exclude list

If you're still watching the command, no alert fires; it would just be noise. "Still watching" means an attached client is currently viewing the origin pane: the guard checks each client's active pane via `list-clients`, so switching to another session counts as moving away just like switching windows does.

## Excluded Commands

Interactive commands (pagers, editors) never trigger alerts regardless of how long they run. Single-word entries match the first word of the command; multi-word entries match as a command prefix. Matching considers both what you typed and the alias-expanded command, so a short git alias (`gfp` -> `git fetch --prune`) is covered by the `git` entry without listing every alias.

### Launcher convention

Beyond the list, any alias defined as a clear-then-run (`cl && X`, `clear && X`) is treated as an interactive session and excluded automatically. The rule reads the alias definition from zsh's `aliases` map, so launchers you add later (agents, TUIs) are covered with nothing to keep in sync, as long as they follow the convention. This is why `claude`, `ralph`, `opencode`, `lg` (lazygit), and friends never show up as tracked processes.

Defaults:

```
git gdn gh
claude opencode oc codex
btop htop top
docker lazydocker lazygit ssh
less more man
vim nvim v vi nano bat diffnav
psql sqlite3 tmux
jiru lazycron
fg bg
```

`fg`/`bg` are excluded because they resume a suspended job rather than run a process of their own: tracking `fg` would mislabel a resumed session as a running `fg`.

| Exclude entry | Matches                           | Doesn't match |
| ------------- | --------------------------------- | ------------- |
| `git`         | `git diff`, `git push`, `git log` | `gitk`        |
| `gdn`         | `gdn`                             | -             |
| `docker`      | `docker compose up`, `docker run` | `dockerd`     |

**Override** before sourcing:

```zsh
_CMD_ALERT_EXCLUDE=(less man git)
source ~/dotfiles/scripts/hooks/cmd-alert-hook.zsh
```

**Append** after sourcing:

```zsh
_CMD_ALERT_EXCLUDE+=(mytool "docker compose")
```

## Command Label Truncation

The label shown in the status bar is built from the command line:

| Command                                 | Label                    |
| --------------------------------------- | ------------------------ |
| `make test`                             | `make test`              |
| `npm run build`                         | `npm run build`          |
| `./scripts/run-tests.sh --verbose`      | `run-tests.sh --verbose` |
| `docker compose -f prod.yml up --build` | `docker compose…`        |

Rules: basename the first word, use as-is if ≤ 3 words, otherwise first 2 words + `…`.

## Process List

Exit alerts only fire once a command has finished. The process list (prefix + Shift+P) adds the other half: a single fzf switcher over everything you're watching, both running and done.

```
● make test     dev:2   1m12s        ← still executing (live, from the registry)
● npm run dev   web:1   8m            ← a server that keeps running
✓ cargo build   api:3   (30s ago)     ← finished, exit 0
✗ bun test      api:3   (2m ago)      ← finished, non-zero (a real failure)
⊘ make dev      web:1   (1m ago)      ← stopped with Ctrl-C, not a failure
```

Running rows come from a per-pane registry the `preexec` hook writes while a tracked command is in flight, and the `precmd` hook removes on completion. Finished rows come from a separate history the `precmd` hook appends on **every** tracked completion, regardless of whether you switched away: that is what lets a command you watched finish in place still leave a ✓/✗/⊘ entry (the switch-away-gated alerts file only drives the status bar). History keeps the most recent 20 entries within the last hour. The same exclude list governs both halves, so they agree on what counts as a process.

| Key                                                  | Action                                                                                                                       |
| ---------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------- |
| <kbd>j</kbd>/<kbd>k</kbd>, <kbd>g</kbd>/<kbd>G</kbd> | move / jump to top or bottom                                                                                                 |
| <kbd>Space</kbd>/<kbd>Enter</kbd>                    | switch to the selected process's window                                                                                      |
| <kbd>r</kbd>                                         | rerun a finished command: stage it on its origin window's prompt and jump there, no Enter, ready to edit                     |
| <kbd>R</kbd>                                         | stage the command and run it straight away                                                                                   |
| <kbd>x</kbd>                                         | interrupt a running process (sends Ctrl-C, silently: no alert or finished row for it) or dismiss a finished one from history |
| <kbd>/</kbd>                                         | search; <kbd>Esc</kbd> returns to navigation                                                                                 |

Rerun reads the full command (stored as typed, so `$VAR` references stay references and are re-expanded by the shell on rerun) from the finished history by key, so the raw text never crosses the fzf/shell boundary. `R` types into whatever the target pane's foreground is, so it is safest at an idle prompt; `r` is the safe default when in doubt.

Running entries are self-cleaning: the `precmd` hook removes them on completion, and the reader prunes any whose owning shell has died or whose pane has closed. Finished entries roll off once they age past an hour or fall outside the most recent 20, and they also clear when you view their window (the same window-switch clear that dismisses exit and agent alerts).

## Clearing Alerts

Alerts clear automatically when you switch to the window. You can also manually clear:

```bash
alerts-clear    # Alias for rm -rf ~/.config/tmux-alerts
```

## Technical Details

- `preexec` hook: records `$SECONDS` and current tmux window at command start
- `precmd` hook: on completion, checks elapsed time and whether window changed
- Alert file: `~/.config/tmux-alerts/alerts` (format: `session:window:exit:<code>:<label>`)
- Running registry: `~/.config/tmux-alerts/running` (one file per pane, named by pane number; fields `pane_id<tab>start_epoch<tab>shell_pid<tab>label`)
- Finished history: `~/.config/tmux-alerts/finished` (one line per completion; fields `finish_epoch<tab>exit_code<tab>session<tab>window_id<tab>window<tab>label<tab>cmd`, where `cmd` is the full command as typed for rerun and is absent on rows written before rerun shipped; reader keeps last 20 within the hour)
- Kill-suppress markers: `~/.config/tmux-alerts/suppress` (one file per pane, touched by proclist's `x` binding right before it interrupts a tracked command; precmd deletes it on that completion and skips the finished row + alert; orphans older than 10s are pruned by the reader)
- Agent-state registry: `~/.config/tmux-alerts/agent-state` (one file per pane, named by pane id; fields `agent<tab>state<tab>epoch<tab>event<tab>session_id<tab>cwd`, written by Claude Code hooks via `scripts/hooks/agent-state.sh` and read by the prefix+c instance switcher; see [AGENT-HOOKS.md](AGENT-HOOKS.md))
- Hook script: `scripts/hooks/cmd-alert.sh`
- Process list: `tmux/scripts/alerts/proclist.sh` (reader), `tmux/scripts/alerts/proclist-action.sh` (the `x` binding), and `tmux/scripts/alerts/proclist-rerun.sh` (the `r`/`R` bindings)
- Bell + status bar rendering: `tmux/scripts/alerts/show.sh`
- Auto-clear on window switch: `after-select-window` hook in `tmux.conf.template`, via `clear.sh`, which clears both the alerts file and any finished-history rows for the window
