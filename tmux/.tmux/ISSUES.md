# Known Issues

## Session Switcher Not Switching Sessions

**Status:** Unresolved
**Discovered:** 2026-01-07

### Symptom

When using the session switcher (`prefix + s`), the fzf list appears correctly and sessions can be navigated, but pressing `Enter` or `Space` to select a session does not switch to it. The popup closes but the user remains in the current session.

### Expected Behaviour

Selecting a session should switch the tmux client to that session.

### Investigation

The issue was discovered while adding rename functionality to the session switcher. Initially suspected the new changes caused the problem, but after fully reverting to the original configuration, the issue persisted.

#### What Was Tested

1. **Removed `r:become(...)` binding** - No effect
2. **Removed `r` from unbind/rebind lists** - No effect
3. **Removed `ctrl-w:unix-line-discard` binding** - No effect
4. **Full revert to original session switcher config** - Issue still present

This confirms the bug existed before any changes were made.

#### Relevant Code

The session switcher command (in `~/.tmux.conf`):

```bash
bind s display-popup -w 95% -h 95% -E "\
  tmux list-sessions -F '#{session_activity} #{session_name}' | \
  sort -rn | cut -d' ' -f2- | \
  fzf ... | \
  xargs -r tmux switch-client -t"
```

The pipeline:
1. `tmux list-sessions` - Lists sessions with activity timestamp
2. `sort -rn | cut -d' ' -f2-` - Sorts by recent activity, removes timestamp
3. `fzf` - User selects a session
4. `xargs -r tmux switch-client -t` - Should switch to selected session

#### Potential Causes to Investigate

1. **fzf output** - Is fzf actually outputting the session name when Enter is pressed?
   - Test: Run the fzf command manually and check output

2. **xargs behaviour** - Is xargs receiving and processing the input correctly?
   - Test: Replace `xargs -r tmux switch-client -t` with `xargs -r echo` to see what's passed

3. **switch-client context** - Does `switch-client` work differently inside a `display-popup`?
   - Test: Try `tmux switch-client -t <session>` manually from within the popup

4. **Client targeting** - May need to explicitly specify the client with `-c`
   - Test: `xargs -r tmux switch-client -c $TMUX_PANE -t`

#### Debugging Commands

```bash
# Test fzf output directly
tmux list-sessions -F '#{session_activity} #{session_name}' | \
  sort -rn | cut -d' ' -f2- | \
  fzf --reverse

# Test if switch-client works in isolation
tmux switch-client -t <session_name>

# Check current client
tmux display-message -p '#{client_name}'
```

### Workaround

Currently, sessions can be switched using:
- `tmux switch-client -t <session_name>` from command line
- The built-in tmux session switcher (`prefix + (` and `prefix + )`)
- Detach and reattach: `tmux detach` then `tmux attach -t <session>`

### Notes

- The **window switcher** (`prefix + f`) works correctly
- The window switcher uses nearly identical code structure
- Main difference: window switcher pipes through `cut -d' ' -f1` before xargs
