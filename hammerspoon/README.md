# Hammerspoon

macOS automation using Lua scripting.

## Features

- **Auto-centre windows** - Specified apps automatically centre their windows on creation
- **CLI enabled** - Use `hs` command from terminal via IPC

### Centred Apps

Windows from these apps are automatically centred when created:

- Ghostty
- Arc
- Dia
- JetBrains IDEs (GoLand, WebStorm, PyCharm, Rider)

## Installation

```bash
brew install --cask hammerspoon
```

## Setup

```bash
# Remove existing config directory (back up first if needed)
rm -rf ~/.hammerspoon

# Symlink config directory
ln -sf ~/dotfiles/hammerspoon ~/.hammerspoon
```

## CLI Setup

To enable the `hs` command-line tool:

1. Open Hammerspoon preferences
2. Check "Enable Accessibility"
3. Run in Hammerspoon console: `hs.ipc.cliInstall()`

Or from terminal after config is loaded:
```bash
hs -c "hs.ipc.cliInstall()"
```

## Usage

| Action | Method |
|--------|--------|
| Reload config | Click menubar icon > Reload Config |
| Open console | Click menubar icon > Console |
| CLI reload | `hs -c "hs.reload()"` |

## Adding Apps to Auto-Centre

Edit `init.lua` and add the app name to the `centredApps` table:

```lua
local centredApps = {
  'Ghostty',
  'Arc',
  'YourApp',  -- Add here
}
```

## Resources

- [Hammerspoon Docs](https://www.hammerspoon.org/docs/)
- [Getting Started Guide](https://www.hammerspoon.org/go/)
- [Spoons](https://www.hammerspoon.org/Spoons/) - Plugin repository
