# Theme System Architecture

## Overview

The dotfiles theme system uses XDG Base Directory standard to prevent git conflicts when users change themes. Themes come in two flavours:

- **Hand-crafted themes**: curated `.theme` files in `themes/` (14 built-in)
- **Generated themes**: auto-generated from any Ghostty built-in theme via `dotfiles theme generate`

Both types produce identical `.theme` files and work seamlessly with `dotfiles theme`.

## Problem Solved

**Before:** Theme colours were stored directly in `tmux/.tmux.conf`, which is tracked in the repository. When users changed themes, it created git conflicts and made updates difficult.

**After:** Themes are generated from templates into XDG-compliant locations (`~/.config/`), keeping user preferences separate from the repository.

## Architecture

### File Locations

```
Repository (tracked in git):
  themes/*.theme                   - Hand-crafted theme definitions (14 themes)
  tmux/tmux.conf.template          - Tmux config template with {{PLACEHOLDERS}}
  ghostty/config.template          - Ghostty config template with {{PLACEHOLDERS}}
  gh-dash/config.yml.template      - gh-dash config template with {{PLACEHOLDERS}}
  scripts/_lib/colour-utils.lua    - Colour conversion, WCAG 2.1 contrast utilities
  scripts/_lib/generate-theme.lua  - Theme generation engine (Lua)
  scripts/generate-theme           - CLI wrapper for the Lua generator (bash)
  scripts/theme-delete             - Remove generated themes
  scripts/theme-switch             - Apply themes to all tools

Generated (gitignored, created by `dotfiles theme generate`):
  themes/generated/*.theme         - Auto-generated themes from Ghostty
  nvim/colors/generated/*.lua      - Auto-generated Neovim colourschemes

User Configuration (outside repo, created by `dotfiles theme`):
  ~/.config/tmux/tmux.conf         - Generated tmux config (XDG standard)
  ~/.tmux.conf                     - Compatibility symlink -> ~/.config/tmux/tmux.conf
  ~/.config/ghostty/config         - Generated ghostty config (XDG, all platforms)
  ~/.config/gh-dash/config.yml     - Generated gh-dash config (XDG standard)
  ~/.config/dotfiles/current-theme - Current theme name

Local Overrides (user-owned, survive theme changes):
  ~/.config/tmux/local.conf   - Personal tmux settings (sourced at end of config)
  ~/.config/ghostty/local     - Personal ghostty settings (included via config-file)
  ~/.config/nvim/local.lua    - Personal neovim settings
```

### Theme Types

#### Hand-Crafted Themes

Located in `themes/*.theme`. These are curated theme files with carefully chosen colour mappings for each tool. Each file is a sourceable shell script exporting colour variables.

#### Generated Themes

Created by `scripts/generate-theme` from Ghostty's ~460 built-in themes. The generator:

1. Parses a Ghostty theme file (key-value format with ANSI palette)
2. Extracts a semantic colour palette (bg, fg, accents mapped from ANSI roles)
3. Rescues near-grey accents: an accent with chroma below 30 (RGB max minus min) reads as tinted grey and cannot differentiate syntax roles, so it swaps to the theme's own bright palette variant when that is meaningfully more chromatic (e.g. Kanagawa Dragon's normal-row pink and cyan). Dull-but-chromatic accents stay untouched so deliberately muted themes keep their designer palette
4. Applies WCAG 2.1 contrast corrections: 4.5:1 minimum against the background surfaces, 3:1 against the cursor-line highlight (a transient emphasis surface where the large-text minimum applies; demanding 4.5:1 there would brighten deliberately muted themes away from the designer's palette). Accents that fail prefer the theme's own bright palette variant before falling back to synthetic lightening
5. Chooses the best active accent (highest contrast from purple/cyan/green)
6. Derives plugin status indicator colours (CPU, RAM, battery blends)
7. Outputs a `.theme` file to `themes/generated/`
8. Outputs a Neovim colourscheme to `nvim/colors/generated/`

Themes with an inverted selection (a light `selection-background` paired with a dark `selection-foreground`, e.g. Bluloco Dark) get special handling in the Neovim output: `Visual` forces the selection foreground so selected text flips dark, matching Ghostty, and reference-style highlights (`LspReference*`, `TelescopeSelection`) use a derived dark band so syntax colours stay readable.

Generated themes integrate transparently. `dotfiles theme` resolves themes with a tiered lookup: hand-crafted first, then generated.

### Theme Switching Flow

1. User runs `dotfiles theme switch catppuccin-mocha`
2. Script sources `themes/catppuccin-mocha.theme` for colour variables
3. Script processes templates, replacing `{{PLACEHOLDERS}}` with actual values
4. Generated configs are written to XDG locations
5. Current theme name is saved to `~/.config/dotfiles/current-theme`
6. Running applications are reloaded (tmux, ghostty, fzf); gh-dash reads config at launch time

### Neovim Theme Integration

The Neovim theme loader (`nvim/lua/custom/core/theme.lua`) reads `~/.config/dotfiles/current-theme` and applies the corresponding colourscheme:

1. **Hand-crafted themes** are mapped via a lookup table (e.g. `tokyo-night` -> `tokyonight-night`)
2. **Generated themes** fall through to `nvim/colors/generated/<name>.lua` via `dofile()`
3. A `vim.uv` file watcher monitors `current-theme` for live reload
4. Scheme names are validated (`^[a-z0-9%-]+$`) before path construction to prevent traversal

### Highlight Attributes

Italic marks text that is not literal code. Three groups carry it, in every theme:

- `Comment`: prose, not code
- `SpecialComment`: prose, not code; it also tracks `Comment`'s colour
- `@markup.italic`: markdown emphasis, where italic is the literal meaning

No other group is italic. Syntax roles are separated by colour alone, so italic
means the same thing in every theme and every language, and switching theme
changes the palette rather than the shape of the text. `scripts/_lib/generate-theme.lua`
emits only these three plus `CopilotSuggestion`, so generated themes conform
without extra work.

`bold` is a separate axis and is not covered by this: several themes bold a
syntax group as part of their own character (gruvbox-dark's functions,
rose-pine's builtins).

Because syntax groups carry no italic, plugin highlights can link to them
safely. Where a plugin points a UI element at a syntax role and only the colour
is wanted, copy the resolved foreground rather than linking, since a link
inherits attributes and cannot cancel them:
`nvim/lua/custom/plugins/dashboard.lua` does this for the snacks dashboard,
whose upstream defaults link `Desc` and `File` to `Special`.

### Statusline Integration

`scripts/_lib/statusline-theme.sh` lets an AI CLI coding agent's statusline
colour itself from the active theme. It targets agents that render their
statusline by running a script: currently Claude Code, GitHub Copilot CLI, and
Antigravity CLI. It is symlinked to `~/.config/dotfiles/statusline-theme.sh` on
install (core preset). Sourcing it reads `current-theme`, parses the matching
`.theme` file, and sets `SL_*` variables holding ANSI 24-bit foreground escapes
mapped from the theme palette:

| Variable                      | Theme source          | Role                       |
| ----------------------------- | --------------------- | -------------------------- |
| `SL_MODEL`                    | pink                  | model name                 |
| `SL_DIR` / `SL_REMAINING`     | fg_primary            | directory, remaining %     |
| `SL_BRANCH`                   | cyan                  | git branch                 |
| `SL_TIME`                     | yellow                | duration                   |
| `SL_CONTEXT`                  | purple                | context metrics            |
| `SL_STAGED` / `SL_LINES_ADD`  | green †               | staged files, additions    |
| `SL_MODIFIED`                 | yellow → orange †     | modified files             |
| `SL_DELETED` / `SL_LINES_DEL` | red †                 | deleted files, removals    |
| `SL_WARNING`                  | yellow → amber †      | warnings, context pressure |
| `SL_UNTRACKED` / `SL_BRACKET` | fg_secondary          | untracked files, brackets  |
| `SL_SEP`                      | fg_secondary→bg blend | separators                 |

**† Hue-locked.** Additions/deletions/modifications and warnings carry universal
meaning (add = green, delete = red, modify/warn = amber), so these roles keep the
theme accent's brightness and saturation but are pinned to a green/red/amber hue.
A theme whose "green" slot is actually teal (Rosé Pine) or grey (n0tch2k), or
whose "red" is a washed-out pink (Catppuccin Frappé), still renders the git `+/-`
diff and status markers with the correct add/delete cue. The remaining roles
follow the palette directly so the statusline still reflects the active theme.

Raw hexes are also exposed as `SL_HEX_*` for custom mapping. It is opt-in: a
statusline enables it by sourcing the resolver and reading the `SL_*` values
behind its own defaults, so it stays safe when no theme is active or the file
is absent:

```bash
# In the statusline script, before its colour definitions:
. "${XDG_CONFIG_HOME:-$HOME/.config}/dotfiles/statusline-theme.sh"

COL_BRANCH="${SL_BRANCH:-$'\033[38;2;139;233;253m'}"   # falls back to a default
```

The resolver parses the theme file by pattern (it never executes it) and reads
`current-theme` live, so the statusline follows `dotfiles theme switch` on the
next render with no regeneration step.

## Benefits

1. **No Git Conflicts**: User theme changes don't affect the repository
2. **XDG Compliance**: Follows modern standards (`~/.config/`)
3. **Clean Templates**: Repository templates remain readable and portable
4. **Backwards Compatible**: Symlink at `~/.tmux.conf` for legacy tools
5. **Multi-User Friendly**: Each user can have different themes
6. **~460 Themes Available**: Any Ghostty built-in theme can be generated instantly
7. **WCAG Accessible**: Generated themes auto-correct for 4.5:1 contrast ratio

## Theme Commands

```bash
# Switch to a theme (hand-crafted or generated)
dotfiles theme switch dracula
dotfiles theme switch catppuccin-mocha
dotfiles theme switch zenburn    # generated theme

# List available themes
dotfiles theme list

# Show current theme
dotfiles theme current

# Switch without reloading (for scripting)
dotfiles theme switch <theme> --no-reload

# Switch quietly (for automation)
dotfiles theme switch <theme> --quiet
```

### Theme Generation

```bash
# Generate a theme from a Ghostty built-in theme
dotfiles theme generate zenburn
dotfiles theme generate "Tomorrow Night"

# List all Ghostty themes
dotfiles theme generate list

# Generate quietly (for scripting)
dotfiles theme generate zenburn --quiet
```

### Theme Deletion

```bash
# Remove a specific generated theme
dotfiles theme delete zenburn

# Remove all generated themes (interactive confirmation)
dotfiles theme delete all

# Remove all generated themes (non-interactive)
dotfiles theme delete all --yes

# List generated themes
dotfiles theme delete list
```

## Creating New Themes

### Hand-Crafted

1. Create `themes/my-theme.theme`:

```bash
# My Theme
THEME_NAME="My Theme"

# Tmux colours
TMUX_BG_PRIMARY="#1e1e2e"
TMUX_FG_PRIMARY="#cdd6f4"
# ... more colour variables
```

2. Add all required colour variables (see existing themes for reference)
3. Test: `dotfiles theme switch my-theme`

### Generated from Ghostty

```bash
# Generate and immediately switch to it
dotfiles theme generate zenburn && dotfiles theme switch zenburn
```

The generator handles everything: parsing, colour extraction, WCAG corrections, and file output. Generated `.theme` files follow the same format as hand-crafted ones.

## Technical Details

### Theme Generation Pipeline

```
Ghostty theme file (key=value)
        |
        v
parse_ghostty_theme()     -- Parse background, foreground, palette 0-15
        |
        v
extract_colours()         -- Soften ANSI black on dark themes (darken bg 3%)
        |                    Map ANSI palette to semantic roles
        |                    (red, green, yellow, purple, pink, cyan)
        |                    Derive bg_secondary, fg_secondary, selection
        v
apply_saturation_preference()  -- Swap near-grey accents (chroma < 30) for the
        |                         theme's own more-chromatic bright variant
        v
apply_wcag_corrections()  -- Ensure 4.5:1 contrast against bg surfaces
        |                    (3:1 against the cursor-line highlight)
        |                    Lighten/darken in HSL space preserving hue
        v
choose_active_accent()    -- Pick highest-contrast accent for UI elements
        |
        v
generate_theme_file()     -- Output themes/generated/<name>.theme
generate_nvim_colourscheme()  -- Output nvim/colors/generated/<name>.lua
```

### Lua Libraries

**`scripts/_lib/colour-utils.lua`**: Core colour manipulation

- `hex_to_rgb` / `rgb_to_hex`: Hex string <-> RGB conversion (validates input)
- `rgb_to_hsl` / `hsl_to_rgb`: HSL colour space conversion
- `luminance()`: WCAG 2.1 relative luminance
- `contrast_ratio()`: WCAG 2.1 contrast ratio between two colours
- `ensure_contrast()`: Adjust lightness to meet minimum contrast ratio
- `lighten()` / `darken()`: HSL lightness adjustment
- `blend()`: Linear interpolation between two colours

**`scripts/_lib/generate-theme.lua`**: Theme generation engine

- `parse_ghostty_theme()`: Parse Ghostty theme files
- `extract_colours()`: Soften ANSI black, map palette to semantic colour roles
- `apply_wcag_corrections()`: Auto-correct for accessibility
- `generate_theme_file()`: Produce `.theme` shell variable files
- `generate_nvim_colourscheme()`: Produce Neovim `colors/*.lua` files
- `display_name()`: Sanitise filenames for safe shell sourcing
- `kebab_name()`: Convert filenames to kebab-case identifiers

### Security

- **Display name sanitisation**: `display_name()` strips shell metacharacters (`$`, backticks, quotes, pipes) from Ghostty filenames before embedding in `.theme` files
- **Scheme name validation**: Neovim theme loader validates names against `^[a-z0-9%-]+$` before `dofile()` to prevent path traversal
- **Hex input validation**: `hex_to_rgb()` rejects malformed hex strings

### Template Processing

The theme switcher (`scripts/theme-switch`) uses `sed` for fast template processing:

```bash
sed -e "s|{{THEME_NAME}}|$THEME_NAME|g" \
    -e "s|{{TMUX_BG_PRIMARY}}|$TMUX_BG_PRIMARY|g" \
    # ... more replacements
    "$TMUX_TEMPLATE" > "$TMUX_OUTPUT"
```

### XDG Directory Creation

The theme switcher ensures XDG directories exist:

```bash
mkdir -p "${XDG_CONFIG_HOME:-$HOME/.config}/tmux"
```

This respects the `XDG_CONFIG_HOME` environment variable if set.

### Git Configuration

`.gitignore` excludes generated configs and local overrides (they live in `~/.config/`, outside the repo). Generated theme files in `themes/generated/` and `nvim/colors/generated/` are also gitignored.

## Testing

### Lua Unit Tests

```bash
# Run all Lua tests via the bash wrapper
scripts/tests/test-lua-libs.sh

# Run directly with luajit/lua
luajit scripts/tests/test-colour-utils.lua
luajit scripts/tests/test-generate-theme.lua
```

**colour-utils tests** (35 tests): hex parsing, RGB/HSL round-trips, WCAG luminance, contrast ratios, ensure_contrast adjustment, lighten/darken/blend.

**generate-theme tests** (46 tests): kebab_name conversion, display_name sanitisation, Ghostty theme parsing (valid, missing fields, comments), colour extraction, WCAG corrections, saturation preference (near-grey rescue, dull-theme fidelity), accent selection, theme file generation, inverted-selection handling.

### Theme Delete Tests

```bash
scripts/tests/test-theme-delete.sh
```

Tests: script existence, shellcheck validation, help output, custom theme protection, non-existent theme handling, generation + deletion cycle, list output.

## Troubleshooting

### Theme not applying after switch

1. Check if you're in tmux: `echo $TMUX`
2. Manually reload: `tmux source ~/.config/tmux/tmux.conf`
3. Check for errors: `tmux source ~/.config/tmux/tmux.conf` (will show errors)

### Generated theme has low contrast

The generator applies WCAG 4.5:1 corrections automatically. If a specific colour still feels low-contrast, the source Ghostty theme may have inherently similar foreground/background values. Try a different Ghostty theme or create a hand-crafted theme.

### Migration script fails

1. Backup your current config: `cp ~/.tmux.conf ~/.tmux.conf.backup`
2. Run migration script with verbose output
3. Check file permissions on `~/.config/tmux/`

### Git shows tmux config as modified

Tmux config is generated to `~/.config/tmux/tmux.conf` and should not affect the repository. If you see git changes, check that `~/.tmux.conf` is a symlink to the XDG location.

## See Also

- `CLAUDE.md`: Full architecture documentation
- `themes/`: Hand-crafted theme definitions
- `themes/generated/`: Auto-generated themes (gitignored)
- `scripts/generate-theme`: Theme generation CLI
- `scripts/theme-switch`: Theme switching implementation
- `scripts/theme-delete`: Generated theme removal
- `scripts/_lib/colour-utils.lua`: Colour utility library
- `scripts/_lib/generate-theme.lua`: Generation engine
