-- Ghostty theme generator
-- Parses a Ghostty theme file and generates:
--   themes/generated/<name>.theme
--   nvim/colors/generated/<name>.lua

---@diagnostic disable: redundant-return-value

local colour = require("colour-utils")

local M = {}

--- Validate a hex colour string
--- @param val string The value to validate
--- @param field string Field name for error messages
--- @return string The validated hex colour
local function assert_hex(val, field)
    if
        type(val) ~= "string" or not val:match("^#[0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F]$")
    then
        error(string.format("Invalid colour for %s: %s", field, tostring(val)))
    end
    return val
end

--- Format a WCAG adjustment entry for reporting
--- @param adj table adjustment entry {name, delta, surface}, {name, swapped} or {name, saturated}
--- @return string human-readable description
local function format_adjustment(adj)
    if adj.swapped then
        return string.format("%s swapped to bright palette variant", adj.name)
    end
    if adj.saturated then
        return string.format("%s promoted to bright variant (near-grey normal row)", adj.name)
    end
    return string.format("%s lightened +%.0f%% (against %s)", adj.name, adj.delta, adj.surface)
end

-- ══════════════════════════════════════════════════════════════
-- Ghostty Theme Parsing
-- ══════════════════════════════════════════════════════════════

--- Parse a Ghostty theme file into a table of key-value pairs
--- Format: "key = value" with "palette = N=#RRGGBB" for palette entries
---@param path string path to Ghostty theme file
---@return table|nil parsed theme, string|nil error
function M.parse_ghostty_theme(path)
    local f = io.open(path, "r")
    if not f then
        return nil, "Cannot open file: " .. path
    end

    local theme = { palette = {} }
    for raw_line in f:lines() do
        -- Skip comments and empty lines
        local line = raw_line:match("^%s*(.-)%s*$") -- trim
        if line ~= "" and not line:match("^#") then
            local key, value = line:match("^([%w_-]+)%s*=%s*(.+)$")
            if key and value then
                if key == "palette" then
                    local index, hex = value:match("^(%d+)=(.+)$")
                    if index and hex then
                        theme.palette[tonumber(index)] = hex
                    end
                else
                    theme[key] = value
                end
            end
        end
    end
    f:close()

    -- Validate minimum required fields
    if not theme.background or not theme.foreground then
        return nil, "Theme missing background or foreground"
    end
    -- Need at least palette 0-7
    for i = 0, 7 do
        if not theme.palette[i] then
            return nil, string.format("Theme missing palette colour %d", i)
        end
    end

    return theme, nil
end

-- ══════════════════════════════════════════════════════════════
-- Colour Extraction (Ghostty ANSI -> Semantic Palette)
-- ══════════════════════════════════════════════════════════════

--- Extract semantic colour palette from parsed Ghostty theme
---@param ghostty table parsed Ghostty theme
---@return table colours semantic colour palette
function M.extract_colours(ghostty)
    local p = ghostty.palette
    local bg = ghostty.background
    local fg = ghostty.foreground

    -- Derive bg_secondary: use palette 0 if it's a good sidebar/float background
    -- Requirements: distinct enough from bg, not too far, and not pure black when bg is coloured
    local bg_secondary
    local bg_lum = colour.luminance(bg)
    local p0_lum = colour.luminance(p[0])
    local p0_ratio = colour.contrast_ratio(p[0], bg)

    -- Reject p[0] as bg_secondary if it's pure/near-black and bg has colour character,
    -- since pure black strips the theme's hue from sidebars and floating windows
    local p0_usable = p0_ratio >= 1.1 and p0_ratio <= 2.5 and p0_lum >= 0.005

    if p0_usable then
        bg_secondary = p[0]
    elseif bg_lum < 0.03 then
        -- Very dark bg: lighten more aggressively to ensure visible distinction
        bg_secondary = colour.lighten(bg, 10)
    else
        bg_secondary = colour.lighten(bg, 8)
    end

    -- Derive fg_secondary: use palette 8 (bright black) if readable, else derive
    local fg_secondary
    local p8_ratio = p[8] and colour.contrast_ratio(p[8], bg) or 0
    if p8_ratio >= 4.0 then
        fg_secondary = p[8]
    else
        -- Blend closer to fg (0.35 = 65% fg, 35% bg) for better baseline readability
        fg_secondary = colour.blend(fg, bg, 0.35)
    end

    -- Derive fg_variable: keep variable identifiers distinct from Normal text
    -- without making them read like another accent class.
    local fg_variable = colour.blend(fg, p[6], 0.10)
    fg_variable = colour.ensure_contrast(fg_variable, bg, 4.5)

    -- Line highlight (CursorLine/ColorColumn): a subtle lift of bg, kept below
    -- bg_secondary so the cursor line reads as a band rather than a panel. Very
    -- dark backgrounds need a larger lightness delta to register the same visual
    -- step (e.g. near-black greys), so lift those a touch more.
    local line_highlight
    if bg_lum < 0.03 then
        line_highlight = colour.lighten(bg, 7)
    else
        line_highlight = colour.lighten(bg, 5)
    end

    -- Selection: use Ghostty's selection_bg if present, else bg_secondary
    local selection = ghostty["selection-background"] or bg_secondary

    return {
        bg_primary = bg,
        fg_primary = fg,
        bg_secondary = bg_secondary,
        fg_secondary = fg_secondary,
        fg_variable = fg_variable,
        line_highlight = line_highlight,
        selection = selection,
        selection_fg = ghostty["selection-foreground"] or "#ffffff",
        cursor_colour = ghostty["cursor-color"] or fg,
        cursor_text = ghostty["cursor-text"] or bg,

        -- Accent colours mapped from ANSI palette
        red = p[1], -- ANSI red
        green = p[2], -- ANSI green
        yellow = p[3], -- ANSI yellow
        purple = p[4], -- ANSI blue -> "purple" role
        pink = p[5], -- ANSI magenta -> "pink" role
        cyan = p[6], -- ANSI cyan

        -- Full 16-colour palette for Ghostty config passthrough
        palette = p,
    }
end

-- ══════════════════════════════════════════════════════════════
-- WCAG Auto-Correction
-- ══════════════════════════════════════════════════════════════

--- Apply WCAG contrast corrections to all accent colours
--- Adjusts against bg_primary, bg_secondary, and line_highlight
---@param colours table semantic colour palette (mutated in place)
---@return table adjustments list of {name, delta} adjustments made
function M.apply_wcag_corrections(colours)
    local adjustments = {}
    local accents = { "red", "green", "yellow", "purple", "pink", "cyan" }

    -- ANSI palette index for each accent role; bright variant = index + 8
    local accent_index = { red = 1, green = 2, yellow = 3, purple = 4, pink = 5, cyan = 6 }

    -- Surfaces that accents must be readable on (ordered hardest-first).
    -- line_highlight only needs WCAG's 3:1 large-text/UI minimum: CursorLine
    -- is a transient emphasis surface, not body text, and demanding 4.5:1
    -- there brightens every dim-row colour in deliberately dull themes
    -- (e.g. Spacegray Eighties Dull) away from the designer's palette.
    local accent_surfaces = {
        { name = "bg_secondary", colour = colours.bg_secondary, min = 4.5 },
        { name = "line_highlight", colour = colours.line_highlight, min = 3.0 },
        { name = "bg_primary", colour = colours.bg_primary, min = 4.5 },
    }

    -- Worst-case contrast margin of a colour across all accent surfaces,
    -- normalised by each surface's required minimum (1.0 = exactly passing)
    local function worst_margin(hex)
        local worst = math.huge
        for _, surface in ipairs(accent_surfaces) do
            local margin = colour.contrast_ratio(hex, surface.colour) / surface.min
            if margin < worst then
                worst = margin
            end
        end
        return worst
    end

    for _, accent_name in ipairs(accents) do
        -- Prefer the theme's own bright variant over synthetic lightening:
        -- themes that keep dim normal-row colours (e.g. Bluloco Dark's
        -- #3476ff blue) usually carry their real identity colours in the
        -- bright row. Lightening the dim row invents pastels the designer
        -- never chose, so swap to the bright variant first when it reads
        -- better, then let ensure_contrast top up any remaining shortfall.
        if worst_margin(colours[accent_name]) < 1 then
            local bright = colours.palette and colours.palette[accent_index[accent_name] + 8]
            if
                bright
                and bright:match("^#%x%x%x%x%x%x$")
                and worst_margin(bright) > worst_margin(colours[accent_name])
            then
                colours[accent_name] = bright
                table.insert(adjustments, { name = accent_name, swapped = true })
            end
        end

        for _, surface in ipairs(accent_surfaces) do
            local corrected, delta = colour.ensure_contrast(colours[accent_name], surface.colour, surface.min)
            if delta > 0 then
                colours[accent_name] = corrected
                table.insert(adjustments, { name = accent_name, delta = delta, surface = surface.name })
            end
        end
    end

    -- Fix fg_secondary contrast — must be readable on all bg surfaces
    -- Use a higher threshold (5.0) since comments/line numbers need to be clearly legible
    local fg_sec_surfaces = {
        { name = "bg_secondary", colour = colours.bg_secondary },
        { name = "bg_primary", colour = colours.bg_primary },
    }

    for _, surface in ipairs(fg_sec_surfaces) do
        local corrected, delta = colour.ensure_contrast(colours.fg_secondary, surface.colour, 5.0)
        if delta > 0 then
            colours.fg_secondary = corrected
            table.insert(adjustments, { name = "fg_secondary", delta = delta, surface = surface.name })
        end
    end

    return adjustments
end

-- ══════════════════════════════════════════════════════════════
-- Saturation Preference
-- ══════════════════════════════════════════════════════════════

-- An accent below this chroma (RGB max-min) reads as tinted grey and cannot
-- differentiate syntax roles. Deliberately dull-but-chromatic accents sit
-- well above it (Spacegray Eighties Dull's dimmest is ~41), so those themes
-- keep their designer palette untouched.
local NEAR_GREY_CHROMA = 30

--- Chroma of a hex colour (RGB max-min, 0-255)
--- Used instead of HSL saturation, which over-rates pale pastels and would
--- wrongly rank e.g. Dracula's bright lavender above its identity purple
---@param hex string
---@return number chroma
local function chroma(hex)
    local r, g, b = colour.hex_to_rgb(hex)
    return math.max(r, g, b) - math.min(r, g, b)
end

--- Swap near-grey accents for the theme's own bright-row variant
--- Muted themes (e.g. Kanagawa Dragon) keep normal-row accents within a few
--- percent of grey but carry their identity colours in the bright row; syntax
--- highlighting built on the near-grey row reads as monochrome. Only accents
--- below NEAR_GREY_CHROMA are eligible, and only when the bright variant is
--- meaningfully more chromatic. Runs before WCAG correction so contrast
--- enforcement stays in one place.
---@param colours table semantic colour palette (mutated in place)
---@return table adjustments list of {name, saturated} adjustments made
function M.apply_saturation_preference(colours)
    local adjustments = {}
    local accents = { "red", "green", "yellow", "purple", "pink", "cyan" }
    local accent_index = { red = 1, green = 2, yellow = 3, purple = 4, pink = 5, cyan = 6 }

    for _, accent_name in ipairs(accents) do
        local current = colours[accent_name]
        local bright = colours.palette and colours.palette[accent_index[accent_name] + 8]
        if
            bright
            and bright:match("^#%x%x%x%x%x%x$")
            and bright ~= current
            and chroma(current) < NEAR_GREY_CHROMA
            and chroma(bright) >= chroma(current) * 1.4
        then
            colours[accent_name] = bright
            table.insert(adjustments, { name = accent_name, saturated = true })
        end
    end

    return adjustments
end

-- ══════════════════════════════════════════════════════════════
-- Active Accent Selection
-- ══════════════════════════════════════════════════════════════

--- Choose the best active accent based on the palette characteristics
--- Picks the accent with the highest contrast against bg_primary from {purple, cyan, green}
---@param colours table semantic colour palette
---@return string accent name ("purple", "cyan", "green", etc.)
function M.choose_active_accent(colours)
    local candidates = { "purple", "cyan", "green" }
    local best_name = "purple"
    local best_ratio = 0

    for _, name in ipairs(candidates) do
        local ratio = colour.contrast_ratio(colours[name], colours.bg_primary)
        if ratio > best_ratio then
            best_ratio = ratio
            best_name = name
        end
    end

    return best_name
end

-- ══════════════════════════════════════════════════════════════
-- Plugin Status Indicator Colours
-- ══════════════════════════════════════════════════════════════

--- Derive CPU/RAM/Battery status indicator backgrounds
---@param colours table semantic colour palette
---@return table status_colours 8 status bg colours
function M.derive_status_colours(colours)
    local bg = colours.bg_primary
    return {
        cpu_low_bg = colour.blend(bg, colours.cyan, 0.15),
        cpu_medium_bg = colour.blend(bg, colours.purple, 0.15),
        cpu_high_bg = colour.blend(bg, colours.pink, 0.15),
        ram_low_bg = colour.blend(bg, colours.green, 0.15),
        ram_medium_bg = colour.blend(bg, colours.cyan, 0.15),
        ram_high_bg = colour.blend(bg, colours.purple, 0.15),
        battery_normal_bg = colour.blend(bg, colours.green, 0.12),
        battery_low_bg = colour.blend(bg, colours.red, 0.15),
    }
end

-- ══════════════════════════════════════════════════════════════
-- .theme File Generation
-- ══════════════════════════════════════════════════════════════

--- Generate .theme file content
---@param name string theme name (kebab-case)
---@param display_name string display name (Title Case)
---@param colours table semantic colour palette
---@param status table status indicator colours
---@param active_accent string chosen active accent
---@param adjustments table WCAG adjustments made
---@return string theme file content
function M.generate_theme_file(name, display_name, colours, status, active_accent, adjustments)
    -- Validate all colours before writing
    assert_hex(colours.bg_primary, "bg_primary")
    assert_hex(colours.fg_primary, "fg_primary")
    assert_hex(colours.bg_secondary, "bg_secondary")
    assert_hex(colours.fg_secondary, "fg_secondary")
    assert_hex(colours.fg_variable, "fg_variable")
    assert_hex(colours.line_highlight, "line_highlight")
    assert_hex(colours.selection, "selection")
    assert_hex(colours.selection_fg, "selection_fg")
    assert_hex(colours.cursor_colour, "cursor_colour")
    assert_hex(colours.red, "red")
    assert_hex(colours.green, "green")
    assert_hex(colours.yellow, "yellow")
    assert_hex(colours.purple, "purple")
    assert_hex(colours.pink, "pink")
    assert_hex(colours.cyan, "cyan")
    -- Validate palette entries
    for i = 0, 15 do
        if colours.palette[i] then
            assert_hex(colours.palette[i], string.format("palette_%d", i))
        end
    end

    local lines = {}
    local function add(line)
        table.insert(lines, line)
    end

    add("# shellcheck shell=bash")
    add(string.format("# Generated from Ghostty theme: %s", display_name))
    add("# Auto-generated by scripts/generate-theme — do not edit manually")
    if #adjustments > 0 then
        add("# WCAG adjustments applied:")
        for _, adj in ipairs(adjustments) do
            add("#   " .. format_adjustment(adj))
        end
    end
    add("")
    add(string.format('THEME_NAME="%s"', display_name))
    add(string.format('THEME_ACTIVE_ACCENT="%s"', active_accent))
    add("")
    add("# " .. string.rep("=", 62))
    add("# Base Colours")
    add("# " .. string.rep("=", 62))
    add("")
    add(string.format('TMUX_BG_PRIMARY="%s"', colours.bg_primary))
    add(string.format('TMUX_FG_PRIMARY="%s"', colours.fg_primary))
    add(string.format('TMUX_BG_SECONDARY="%s"', colours.bg_secondary))
    add(string.format('TMUX_FG_SECONDARY="%s"', colours.fg_secondary))
    add("")
    add("# " .. string.rep("=", 62))
    add("# Accent Colours")
    add("# " .. string.rep("=", 62))
    add("")
    add(string.format('TMUX_ACCENT_PURPLE="%s"', colours.purple))
    add(string.format('TMUX_ACCENT_PINK="%s"', colours.pink))
    add(string.format('TMUX_ACCENT_CYAN="%s"', colours.cyan))
    add(string.format('TMUX_ACCENT_GREEN="%s"', colours.green))
    add(string.format('TMUX_ACCENT_YELLOW="%s"', colours.yellow))
    add(string.format('TMUX_ACCENT_RED="%s"', colours.red))
    add("")
    add("# " .. string.rep("=", 62))
    add("# Plugin Status Indicators")
    add("# " .. string.rep("=", 62))
    add("")
    add(string.format('TMUX_CPU_LOW_BG="%s"', status.cpu_low_bg))
    add(string.format('TMUX_CPU_MEDIUM_BG="%s"', status.cpu_medium_bg))
    add(string.format('TMUX_CPU_HIGH_BG="%s"', status.cpu_high_bg))
    add(string.format('TMUX_RAM_LOW_BG="%s"', status.ram_low_bg))
    add(string.format('TMUX_RAM_MEDIUM_BG="%s"', status.ram_medium_bg))
    add(string.format('TMUX_RAM_HIGH_BG="%s"', status.ram_high_bg))
    add(string.format('TMUX_BATTERY_NORMAL_BG="%s"', status.battery_normal_bg))
    add(string.format('TMUX_BATTERY_LOW_BG="%s"', status.battery_low_bg))
    add("")
    add("# " .. string.rep("=", 62))
    add("# Ghostty Colours")
    add("# " .. string.rep("=", 62))
    add("")
    add(string.format('GHOSTTY_BACKGROUND="%s"', colours.bg_primary))
    add(string.format('GHOSTTY_FOREGROUND="%s"', colours.fg_primary))
    add(string.format('GHOSTTY_CURSOR_COLOR="%s"', colours.cursor_colour))
    add(string.format('GHOSTTY_CURSOR_TEXT="%s"', colours.cursor_text))
    add(string.format('GHOSTTY_SELECTION_BG="%s"', colours.selection))
    add(string.format('GHOSTTY_SELECTION_FG="%s"', colours.selection_fg))
    add("")
    add("# Terminal palette")
    for i = 0, 15 do
        local val = colours.palette[i]
        if val then
            add(string.format('GHOSTTY_PALETTE_%d="%s"', i, val))
        end
    end
    add("")
    add("# " .. string.rep("=", 62))
    add("# Neovim Colours")
    add("# " .. string.rep("=", 62))
    add("")
    add(string.format('NVIM_COLORSCHEME="%s"', name))
    add(string.format('NVIM_FG_VARIABLE="%s"', colours.fg_variable))
    add("")

    return table.concat(lines, "\n")
end

-- ══════════════════════════════════════════════════════════════
-- Neovim Colourscheme Generation
-- ══════════════════════════════════════════════════════════════

--- Generate nvim/colors/*.lua file content
---@param name string colourscheme name (kebab-case)
---@param colours table semantic colour palette
---@return string lua file content
function M.generate_nvim_colourscheme(name, colours)
    local neotree_cursor = colour.lighten(colours.bg_secondary, 12)

    -- Inverted selections: some Ghostty themes (e.g. Bluloco Dark) pair a
    -- light selection background with a dark selection foreground. In nvim,
    -- syntax colours would sit on that light bg at ~1:1 contrast and vanish,
    -- so mirror Ghostty's behaviour by forcing the selection fg on Visual.
    -- Reference-style highlights (LspReference*, TelescopeSelection) must
    -- preserve per-token syntax colours, so they get a derived dark band
    -- instead of the inverted selection colour.
    local selection_inverted = colour.contrast_ratio(colours.fg_primary, colours.selection) < 2.5
    local visual_fg = colours.selection_fg
    if colour.contrast_ratio(visual_fg, colours.selection) < 4.5 then
        visual_fg = colours.bg_primary
    end
    local reference_bg = selection_inverted and colour.lighten(colours.bg_primary, 12) or colours.selection

    -- Comments sit dimmer than fg_secondary (which @variable.parameter, LineNr and
    -- the UI chrome use) so doc comments don't read as loud as parameter names —
    -- previously both shared fg_secondary verbatim and became indistinguishable.
    -- Blend toward the background for the dim, with a contrast floor so comments
    -- stay legible against the editor background across all generated themes.
    local comment = colour.blend(colours.fg_secondary, colours.bg_primary, 0.30)
    comment = colour.ensure_contrast(comment, colours.bg_primary, 4.0)

    -- Punctuation gets a subtle tint toward the purple accent (mirroring the
    -- hand-crafted schemes' muted-violet punctuation) instead of plain fg.
    local punct =
        colour.ensure_contrast(colour.blend(colours.fg_primary, colours.purple, 0.35), colours.bg_primary, 4.5)

    -- Semantic role mapping mirroring the hand-crafted schemes: strings=green,
    -- functions=purple (the ANSI blue role), types/modules=cyan, literal data
    -- and properties=yellow, keywords/control-flow=pink. Symbolic operators
    -- share the keyword pink so they no longer flatten into plain fg; builtin
    -- functions use cyan to read apart from user-defined ones. This gives
    -- functions, types, and data three distinct hue families where they
    -- previously crowded onto cyan/yellow.
    local c = {
        constant = "colors.yellow",
        string = "colors.green",
        character = "colors.green",
        number = "colors.yellow",
        boolean = "colors.yellow",
        float = "colors.yellow",
        func = "colors.purple",
        statement = "colors.pink",
        conditional = "colors.pink",
        ["repeat"] = "colors.pink",
        label = "colors.pink",
        operator = "colors.pink",
        keyword = "colors.pink",
        exception = "colors.pink",
        preproc = "colors.pink",
        include = "colors.pink",
        define = "colors.pink",
        macro = "colors.cyan",
        precondit = "colors.pink",
        type = "colors.cyan",
        storageclass = "colors.pink",
        structure = "colors.cyan",
        typedef = "colors.cyan",
        special = "colors.cyan",
        specialchar = "colors.pink",
        tag = "colors.pink",
    }

    local lines = {}
    local function add(line)
        table.insert(lines, line)
    end

    -- Header
    add(string.format("-- %s colourscheme for Neovim", name))
    add("-- Generated from Ghostty theme by scripts/generate-theme")
    add("")
    add("vim.cmd 'highlight clear'")
    add("if vim.fn.exists 'syntax_on' then")
    add("  vim.cmd 'syntax reset'")
    add("end")
    add("")
    add(string.format("vim.g.colors_name = '%s'", name))
    add("vim.o.termguicolors = true")
    add("")

    -- Colors table
    add("local colors = {")
    add(string.format("  bg_primary = '%s',", colours.bg_primary))
    add(string.format("  fg_primary = '%s',", colours.fg_primary))
    add(string.format("  bg_secondary = '%s',", colours.bg_secondary))
    add(string.format("  fg_secondary = '%s',", colours.fg_secondary))
    add(string.format("  fg_variable = '%s',", colours.fg_variable))
    add(string.format("  purple = '%s',", colours.purple))
    add(string.format("  pink = '%s',", colours.pink))
    add(string.format("  cyan = '%s',", colours.cyan))
    add(string.format("  green = '%s',", colours.green))
    add(string.format("  yellow = '%s',", colours.yellow))
    add(string.format("  red = '%s',", colours.red))
    add("")
    add(string.format("  selection = '%s',", colours.selection))
    add(string.format("  selection_fg = '%s',", visual_fg))
    add(string.format("  reference = '%s',", reference_bg))
    add(string.format("  comment = '%s',", comment))
    add(string.format("  ghost = '%s',", colour.blend(colours.fg_secondary, colours.bg_primary, 0.40)))
    add(string.format("  punct = '%s',", punct))
    add(string.format("  line_highlight = '%s',", colours.line_highlight))
    add("}")
    add("")

    -- Helper function
    add("local function hl(group, opts)")
    add("  vim.api.nvim_set_hl(0, group, opts)")
    add("end")
    add("")

    -- Editor highlights (fixed mappings — not worth parameterising)
    local editor = {
        { "Normal", "fg = colors.fg_primary, bg = colors.bg_primary" },
        { "NormalFloat", "fg = colors.fg_primary, bg = colors.bg_secondary" },
        { "FloatBorder", "fg = colors.purple, bg = colors.bg_secondary" },
        { "ColorColumn", "bg = colors.line_highlight" },
        { "Cursor", "fg = colors.bg_primary, bg = colors.fg_primary" },
        { "CursorLine", "bg = colors.line_highlight" },
        { "CursorLineNr", "fg = colors.purple, bold = true" },
        { "LineNr", "fg = colors.comment" },
        { "SignColumn", "bg = colors.bg_primary" },
        {
            "Visual",
            selection_inverted and "fg = colors.selection_fg, bg = colors.selection" or "bg = colors.selection",
        },
        {
            "VisualNOS",
            selection_inverted and "fg = colors.selection_fg, bg = colors.selection" or "bg = colors.selection",
        },
        { "Search", "fg = colors.bg_primary, bg = colors.yellow" },
        { "IncSearch", "fg = colors.bg_primary, bg = colors.pink" },
        { "MatchParen", "fg = colors.green, bold = true" },
        { "Question", "fg = colors.cyan" },
        { "ModeMsg", "fg = colors.green, bold = true" },
        { "MoreMsg", "fg = colors.green" },
        { "ErrorMsg", "fg = colors.red, bold = true" },
        { "WarningMsg", "fg = colors.yellow" },
        { "VertSplit", "fg = colors.bg_secondary" },
        { "WinSeparator", "fg = colors.bg_secondary" },
        { "Folded", "fg = colors.comment, bg = colors.line_highlight" },
        { "FoldColumn", "fg = colors.comment" },
        { "Pmenu", "fg = colors.fg_primary, bg = colors.bg_secondary" },
        { "PmenuSel", "fg = colors.bg_primary, bg = colors.purple" },
        { "PmenuSbar", "bg = colors.bg_secondary" },
        { "PmenuThumb", "bg = colors.purple" },
        { "StatusLine", "fg = colors.purple, bg = colors.bg_secondary" },
        { "StatusLineNC", "fg = colors.comment, bg = colors.bg_secondary" },
        { "TabLine", "fg = colors.fg_secondary, bg = colors.bg_secondary" },
        { "TabLineFill", "bg = colors.bg_secondary" },
        { "TabLineSel", "fg = colors.purple, bg = colors.bg_primary, bold = true" },
        { "Directory", "fg = colors.cyan" },
        { "Title", "fg = colors.pink, bold = true" },
        { "SpecialKey", "fg = colors.comment" },
        { "NonText", "fg = colors.comment" },
        { "Whitespace", "fg = colors.comment" },
    }

    add("-- Editor highlights")
    for _, e in ipairs(editor) do
        add(string.format("hl('%s', { %s })", e[1], e[2]))
    end
    add("")

    -- Vim syntax groups (use role mapping)
    local syntax = {
        { "Comment", "fg = colors.comment, italic = true" },
        { "Constant", "fg = " .. c.constant },
        { "String", "fg = " .. c.string },
        { "Character", "fg = " .. c.character },
        { "Number", "fg = " .. c.number },
        { "Boolean", "fg = " .. c.boolean },
        { "Float", "fg = " .. c.float },
        { "Identifier", "fg = colors.fg_primary" },
        { "Function", "fg = " .. c.func },
        { "Statement", "fg = " .. c.statement },
        { "Conditional", "fg = " .. c.conditional },
        { "Repeat", "fg = " .. c["repeat"] },
        { "Label", "fg = " .. c.label },
        { "Operator", "fg = " .. c.operator },
        { "Keyword", "fg = " .. c.keyword },
        { "Exception", "fg = " .. c.exception },
        { "PreProc", "fg = " .. c.preproc },
        { "Include", "fg = " .. c.include },
        { "Define", "fg = " .. c.define },
        { "Macro", "fg = " .. c.macro },
        { "PreCondit", "fg = " .. c.precondit },
        { "Type", "fg = " .. c.type },
        { "StorageClass", "fg = " .. c.storageclass },
        { "Structure", "fg = " .. c.structure },
        { "Typedef", "fg = " .. c.typedef },
        { "Special", "fg = " .. c.special },
        { "SpecialChar", "fg = " .. c.specialchar },
        { "Tag", "fg = " .. c.tag },
        { "Delimiter", "fg = colors.punct" },
        { "SpecialComment", "fg = colors.comment, italic = true" },
        { "Debug", "fg = colors.red" },
        { "Underlined", "fg = colors.cyan, underline = true" },
        { "Ignore", "fg = colors.comment" },
        { "Error", "fg = colors.red, bold = true" },
        { "Todo", "fg = colors.pink, bold = true" },
    }

    add("-- Syntax highlighting")
    for _, s in ipairs(syntax) do
        add(string.format("hl('%s', { %s })", s[1], s[2]))
    end
    add("")

    -- Git signs, diagnostics, LSP (fixed — same for all themes)
    add("-- Git signs")
    add("hl('GitSignsAdd', { fg = colors.green })")
    add("hl('GitSignsChange', { fg = colors.yellow })")
    add("hl('GitSignsDelete', { fg = colors.red })")
    add("hl('GitSignsTopdelete', { fg = colors.red })")
    add("hl('GitSignsChangedelete', { fg = colors.yellow })")
    add("")
    add("-- Diagnostics")
    add("hl('DiagnosticError', { fg = colors.red })")
    add("hl('DiagnosticWarn', { fg = colors.yellow })")
    add("hl('DiagnosticInfo', { fg = colors.cyan })")
    add("hl('DiagnosticHint', { fg = colors.purple })")
    add("hl('DiagnosticUnderlineError', { undercurl = true, sp = colors.red })")
    add("hl('DiagnosticUnderlineWarn', { undercurl = true, sp = colors.yellow })")
    add("hl('DiagnosticUnderlineInfo', { undercurl = true, sp = colors.cyan })")
    add("hl('DiagnosticUnderlineHint', { undercurl = true, sp = colors.purple })")
    add("")
    add("-- LSP")
    add("hl('LspReferenceText', { bg = colors.reference })")
    add("hl('LspReferenceRead', { bg = colors.reference })")
    add("hl('LspReferenceWrite', { bg = colors.reference })")
    add("")

    -- Treesitter groups (use role mapping)
    local ts = {
        { "@variable", "fg = colors.fg_primary" }, -- plain text; swap to colors.fg_variable for a subtle tint
        { "@variable.builtin", "fg = colors.red" },
        { "@variable.parameter", "fg = colors.fg_secondary" },
        { "@variable.member", "fg = colors.yellow" },
        { "@constant", "fg = " .. c.constant },
        { "@constant.builtin", "fg = " .. c.constant },
        { "@module", "fg = colors.cyan" },
        { "@string", "fg = " .. c.string },
        { "@string.escape", "fg = " .. c.specialchar },
        { "@string.special", "fg = " .. c.specialchar },
        { "@character", "fg = " .. c.character },
        { "@number", "fg = " .. c.number },
        { "@boolean", "fg = " .. c.boolean },
        { "@function", "fg = " .. c.func },
        { "@function.builtin", "fg = colors.cyan" },
        { "@function.call", "fg = " .. c.func },
        { "@function.macro", "fg = " .. c.macro },
        { "@method", "fg = " .. c.func },
        { "@method.call", "fg = " .. c.func },
        { "@constructor", "fg = " .. c.type },
        { "@keyword", "fg = " .. c.keyword },
        { "@keyword.function", "fg = " .. c.keyword },
        { "@keyword.operator", "fg = " .. c.keyword },
        { "@keyword.return", "fg = " .. c.keyword },
        { "@conditional", "fg = " .. c.conditional },
        { "@repeat", "fg = " .. c["repeat"] },
        { "@label", "fg = " .. c.label },
        { "@operator", "fg = " .. c.operator },
        { "@exception", "fg = " .. c.exception },
        { "@type", "fg = " .. c.type },
        { "@type.builtin", "fg = " .. c.type },
        { "@type.qualifier", "fg = " .. c.keyword },
        { "@property", "fg = colors.yellow" },
        { "@attribute", "fg = colors.red" },
        { "@tag", "fg = " .. c.tag },
        { "@tag.attribute", "fg = colors.yellow" },
        { "@tag.delimiter", "fg = colors.punct" },
        { "@punctuation.delimiter", "fg = colors.punct" },
        { "@punctuation.bracket", "fg = colors.punct" },
        { "@punctuation.special", "fg = " .. c.specialchar },
        { "@comment", nil }, -- link to Comment
        { "@markup.strong", "bold = true" },
        { "@markup.italic", "italic = true" },
        { "@markup.underline", "underline = true" },
        { "@markup.heading", "fg = colors.pink, bold = true" },
        { "@markup.link", "fg = colors.cyan, underline = true" },
        { "@markup.link.url", "fg = colors.purple, underline = true" },
        { "@markup.list", "fg = colors.cyan" },
        { "@markup.raw", "fg = " .. c.string },
    }

    add("-- Treesitter")
    for _, t in ipairs(ts) do
        if t[2] == nil then
            add(string.format("hl('%s', { link = 'Comment' })", t[1]))
        else
            add(string.format("hl('%s', { %s })", t[1], t[2]))
        end
    end
    add("")

    -- Plugin highlights (Telescope, Neo-tree, Which-key, Mini)
    add("-- Telescope")
    add("hl('TelescopeBorder', { fg = colors.purple, bg = colors.bg_secondary })")
    add("hl('TelescopePromptBorder', { fg = colors.pink, bg = colors.bg_secondary })")
    add("hl('TelescopePromptTitle', { fg = colors.pink, bold = true })")
    add("hl('TelescopePreviewTitle', { fg = colors.purple, bold = true })")
    add("hl('TelescopeResultsTitle', { fg = colors.purple, bold = true })")
    add("hl('TelescopeSelection', { fg = colors.purple, bg = colors.reference, bold = true })")
    add("hl('TelescopeMatching', { fg = colors.green, bold = true })")
    add("")
    add("-- Neo-tree")
    add("hl('NeoTreeNormal', { fg = colors.fg_primary, bg = colors.bg_secondary })")
    add("hl('NeoTreeNormalNC', { fg = colors.fg_primary, bg = colors.bg_secondary })")
    add(string.format("hl('NeoTreeCursorLine', { bg = '%s' })", neotree_cursor))
    add("hl('NeoTreeDirectoryIcon', { fg = colors.cyan })")
    add("hl('NeoTreeDirectoryName', { fg = colors.cyan })")
    add("hl('NeoTreeFileName', { fg = colors.fg_primary })")
    add("hl('NeoTreeFileNameOpened', { fg = colors.pink })")
    add("hl('NeoTreeGitModified', { fg = colors.yellow })")
    add("hl('NeoTreeGitAdded', { fg = colors.green })")
    add("hl('NeoTreeGitDeleted', { fg = colors.red })")
    add("hl('NeoTreeIndentMarker', { fg = colors.comment })")
    add("hl('NeoTreeRootName', { fg = colors.pink, bold = true })")
    add("")
    add("-- Which-key")
    add("hl('WhichKey', { fg = colors.cyan })")
    add("hl('WhichKeyGroup', { fg = colors.pink })")
    add("hl('WhichKeyDesc', { fg = colors.fg_primary })")
    add("hl('WhichKeySeparator', { fg = colors.comment })")
    add("")
    add("-- Mini.nvim statusline")
    add("hl('MiniStatuslineModeNormal', { fg = colors.bg_primary, bg = colors.purple, bold = true })")
    add("hl('MiniStatuslineModeInsert', { fg = colors.bg_primary, bg = colors.green, bold = true })")
    add("hl('MiniStatuslineModeVisual', { fg = colors.bg_primary, bg = colors.pink, bold = true })")
    add("hl('MiniStatuslineModeReplace', { fg = colors.bg_primary, bg = colors.red, bold = true })")
    add("hl('MiniStatuslineModeCommand', { fg = colors.bg_primary, bg = colors.yellow, bold = true })")
    add("hl('MiniStatuslineDevinfo', { fg = colors.fg_primary, bg = colors.bg_secondary })")
    add("hl('MiniStatuslineFilename', { fg = colors.fg_primary, bg = colors.bg_secondary })")
    add("hl('MiniStatuslineFileinfo', { fg = colors.fg_primary, bg = colors.bg_secondary })")
    add("hl('MiniStatuslineInactive', { fg = colors.comment, bg = colors.bg_secondary })")
    add("")
    add("-- Copilot")
    add("hl('CopilotSuggestion', { fg = colors.ghost, italic = true })")
    add("")
    add("-- Indent-blankline")
    add("hl('IblIndent', { fg = colors.line_highlight })")
    add("hl('IblScope', { fg = colors.purple })")
    add("")
    add("-- Neotest")
    add("hl('NeotestPassed', { fg = colors.green })")
    add("hl('NeotestFailed', { fg = colors.red })")
    add("hl('NeotestRunning', { fg = colors.yellow })")
    add("hl('NeotestSkipped', { fg = colors.comment })")
    add("hl('NeotestTest', { fg = colors.fg_primary })")
    add("hl('NeotestNamespace', { fg = colors.cyan })")
    add("hl('NeotestFile', { fg = colors.cyan })")
    add("hl('NeotestDir', { fg = colors.cyan })")
    add("hl('NeotestAdapterName', { fg = colors.purple, bold = true })")
    add("hl('NeotestBorder', { fg = colors.purple })")
    add("hl('NeotestIndent', { fg = colors.comment })")
    add("hl('NeotestFocused', { bold = true, underline = true })")
    add("hl('NeotestMarked', { fg = colors.pink, bold = true })")
    add("hl('NeotestWinSelect', { fg = colors.purple, bold = true })")
    add("")
    add("-- Flash")
    add("hl('FlashBackdrop', { fg = colors.comment })")
    add("hl('FlashLabel', { fg = colors.bg_primary, bg = colors.pink, bold = true })")
    add("hl('FlashMatch', { fg = colors.bg_primary, bg = colors.yellow })")
    add("hl('FlashCurrent', { fg = colors.bg_primary, bg = colors.green })")
    add("")
    add("-- Fidget")
    add("hl('FidgetTitle', { fg = colors.purple, bold = true })")
    add("hl('FidgetTask', { fg = colors.comment })")

    return table.concat(lines, "\n") .. "\n"
end

-- ══════════════════════════════════════════════════════════════
-- Display Name Derivation
-- ══════════════════════════════════════════════════════════════

--- Convert a Ghostty theme filename to a display name
--- Sanitises to prevent shell injection when sourced
---@param filename string Ghostty theme filename (no path)
---@return string display_name
function M.display_name(filename)
    -- Strip anything outside safe display characters
    local safe = filename:gsub("[^%w%s%-%_%(%)%.%,]", "")
    -- Strip double quotes to prevent breaking out of shell assignment
    safe = safe:gsub('"', "")
    if safe == "" then
        safe = "Unknown Theme"
    end
    return safe
end

--- Convert a Ghostty theme filename to a kebab-case name for file paths
--- e.g. "3024 Night" -> "3024-night", "Aardvark Blue" -> "aardvark-blue"
---@param filename string Ghostty theme filename
---@return string kebab name
function M.kebab_name(filename)
    local name = filename:lower()
    name = name:gsub("[^%w]+", "-") -- replace non-alphanumeric runs with hyphen
    name = name:gsub("^-+", ""):gsub("-+$", "") -- trim leading/trailing hyphens
    return name
end

-- ══════════════════════════════════════════════════════════════
-- Main Generation Entry Point
-- ══════════════════════════════════════════════════════════════

--- Generate theme files from a Ghostty theme
---@param ghostty_path string path to Ghostty theme file
---@param themes_dir string path to themes/generated/ output directory
---@param nvim_dir string path to nvim/colors/generated/ output directory
---@param opts table|nil options: { quiet = bool }
---@return boolean success
---@return string|nil error message
function M.generate(ghostty_path, themes_dir, nvim_dir, opts)
    opts = opts or {}
    local quiet = opts.quiet or false

    -- Determine names from the Ghostty theme filename
    local filename = ghostty_path:match("[/\\]([^/\\]+)$") or ghostty_path
    local display = M.display_name(filename)
    local name = M.kebab_name(filename)

    -- Parse Ghostty theme
    local ghostty, err = M.parse_ghostty_theme(ghostty_path)
    if not ghostty then
        return false, err
    end

    -- Extract semantic colours
    local colours = M.extract_colours(ghostty)

    -- Rescue near-grey accents, then apply WCAG corrections
    local adjustments = M.apply_saturation_preference(colours)
    for _, adj in ipairs(M.apply_wcag_corrections(colours)) do
        table.insert(adjustments, adj)
    end

    -- Choose active accent
    local active_accent = M.choose_active_accent(colours)

    -- Derive status indicator colours
    local status = M.derive_status_colours(colours)

    -- Generate .theme file
    local theme_content = M.generate_theme_file(name, display, colours, status, active_accent, adjustments)
    local theme_path = themes_dir .. "/" .. name .. ".theme"
    local f = io.open(theme_path, "w")
    if not f then
        return false, "Cannot write: " .. theme_path
    end
    f:write(theme_content)
    f:close()

    -- Generate nvim colourscheme
    local nvim_content = M.generate_nvim_colourscheme(name, colours)
    local nvim_path = nvim_dir .. "/" .. name .. ".lua"
    f = io.open(nvim_path, "w")
    if not f then
        return false, "Cannot write: " .. nvim_path
    end
    f:write(nvim_content)
    f:close()

    if not quiet then
        io.stderr:write(string.format("Generated: %s\n", theme_path))
        io.stderr:write(string.format("Generated: %s\n", nvim_path))
        if #adjustments > 0 then
            io.stderr:write("WCAG adjustments:\n")
            for _, adj in ipairs(adjustments) do
                io.stderr:write("  " .. format_adjustment(adj) .. "\n")
            end
        end
    end

    -- Output the theme name for callers
    io.write(name)

    return true, nil
end

-- ══════════════════════════════════════════════════════════════
-- CLI Entry Point (when run as script)
-- ══════════════════════════════════════════════════════════════

-- Only run CLI when executed directly (not required as module)
if not pcall(debug.getlocal, 4, 1) then
    local ghostty_path = arg[1]
    local themes_dir = arg[2]
    local nvim_dir = arg[3]
    local quiet = arg[4] == "--quiet"

    if not ghostty_path or not themes_dir or not nvim_dir then
        io.stderr:write(
            "Usage: lua generate-theme.lua <ghostty-theme-path> <themes-generated-dir> <nvim-colors-generated-dir> [--quiet]\n"
        )
        os.exit(1)
    end

    local ok, err = M.generate(ghostty_path, themes_dir, nvim_dir, { quiet = quiet })
    if not ok then
        io.stderr:write("Error: " .. (err or "unknown") .. "\n")
        os.exit(1)
    end
end

return M
