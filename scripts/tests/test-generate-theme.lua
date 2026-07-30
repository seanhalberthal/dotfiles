#!/usr/bin/env lua
-- Unit tests for scripts/_lib/generate-theme.lua

local script_dir = arg[0]:match("(.*/)")
package.path = script_dir .. "../_lib/?.lua;" .. package.path

local gen = require("generate-theme")

local pass_count = 0
local fail_count = 0

local function pass(desc)
    pass_count = pass_count + 1
    io.write(string.format("\027[0;32m✓\027[0m %s\n", desc))
end

local function fail(desc, detail)
    fail_count = fail_count + 1
    io.write(string.format("\027[0;31m✗\027[0m %s", desc))
    if detail then
        io.write(string.format(" (%s)", detail))
    end
    io.write("\n")
end

local function section(name)
    io.write(
        string.format(
            "\n─────────────────────────────────────────\n%s\n─────────────────────────────────────────\n",
            name
        )
    )
end

-- Helper: write a temp file and return its path
local function write_temp(content)
    local path = os.tmpname()
    local f = io.open(path, "w")
    f:write(content)
    f:close()
    return path
end

-- ═══════════════════════════════════════════════
section("kebab_name")

local cases = {
    { "3024 Night", "3024-night" },
    { "Aardvark Blue", "aardvark-blue" },
    { "catppuccin-mocha", "catppuccin-mocha" },
    { "Solarized (Light)", "solarized-light" },
    { "UPPERCASE", "uppercase" },
    { "  leading spaces  ", "leading-spaces" },
}
for _, c in ipairs(cases) do
    local result = gen.kebab_name(c[1])
    if result == c[2] then
        pass('kebab_name("' .. c[1] .. '") = "' .. c[2] .. '"')
    else
        fail('kebab_name("' .. c[1] .. '")', 'got "' .. result .. '"')
    end
end

-- ═══════════════════════════════════════════════
section("display_name")

-- Should sanitise shell metacharacters
local safe = gen.display_name("Normal Theme")
if safe == "Normal Theme" then
    pass("display_name preserves normal names")
else
    fail("display_name normal", safe)
end

local sanitised = gen.display_name("Evil$(rm -rf)Theme")
if not sanitised:find("%$") then
    pass("display_name strips $ characters")
else
    fail("display_name should strip $", sanitised)
end

sanitised = gen.display_name("back`tick`name")
if not sanitised:find("`") then
    pass("display_name strips backticks")
else
    fail("display_name should strip backticks", sanitised)
end

-- ═══════════════════════════════════════════════
section("parse_ghostty_theme")

-- Minimal valid theme
local minimal_theme = [[
background = #282a36
foreground = #f8f8f2
palette = 0=#282a36
palette = 1=#ff5555
palette = 2=#50fa7b
palette = 3=#f1fa8c
palette = 4=#bd93f9
palette = 5=#ff79c6
palette = 6=#8be9fd
palette = 7=#f8f8f2
]]

local path = write_temp(minimal_theme)
local theme, err = gen.parse_ghostty_theme(path)
os.remove(path)

if theme then
    pass("parses minimal valid theme")
else
    fail("parse minimal theme", err)
end

if theme and theme.background == "#282a36" then
    pass("extracts background")
else
    fail("extract background")
end

if theme and theme.foreground == "#f8f8f2" then
    pass("extracts foreground")
else
    fail("extract foreground")
end

if theme and theme.palette[1] == "#ff5555" then
    pass("extracts palette entry")
else
    fail("extract palette")
end

-- Missing background
path = write_temp("foreground = #f8f8f2\npalette = 0=#000000\n")
theme, err = gen.parse_ghostty_theme(path)
os.remove(path)
if not theme and err:find("background") then
    pass("rejects missing background")
else
    fail("should reject missing background")
end

-- Missing palette entry
path = write_temp("background = #000000\nforeground = #ffffff\npalette = 0=#000000\n")
theme, err = gen.parse_ghostty_theme(path)
os.remove(path)
if not theme and err:find("palette") then
    pass("rejects missing palette entries")
else
    fail("should reject incomplete palette")
end

-- Comments and blank lines
local commented_theme = [[
# This is a comment
background = #282a36
foreground = #f8f8f2

# Another comment
palette = 0=#282a36
palette = 1=#ff5555
palette = 2=#50fa7b
palette = 3=#f1fa8c
palette = 4=#bd93f9
palette = 5=#ff79c6
palette = 6=#8be9fd
palette = 7=#f8f8f2
]]
path = write_temp(commented_theme)
theme, err = gen.parse_ghostty_theme(path)
os.remove(path)
if theme then
    pass("ignores comments and blank lines")
else
    fail("comments/blanks", err)
end

-- Non-existent file
theme, err = gen.parse_ghostty_theme("/tmp/nonexistent-theme-xyz-12345")
if not theme and err:find("Cannot open") then
    pass("reports error for missing file")
else
    fail("should report missing file error")
end

-- ═══════════════════════════════════════════════
section("extract_colours")

-- Build a parsed theme fixture
local fixture = {
    background = "#282a36",
    foreground = "#f8f8f2",
    palette = {
        [0] = "#44475a",
        [1] = "#ff5555",
        [2] = "#50fa7b",
        [3] = "#f1fa8c",
        [4] = "#bd93f9",
        [5] = "#ff79c6",
        [6] = "#8be9fd",
        [7] = "#f8f8f2",
        [8] = "#6272a4",
    },
}

local colours = gen.extract_colours(fixture)
if colours.bg_primary == "#282a36" then
    pass("bg_primary from background")
else
    fail("bg_primary")
end

if colours.fg_primary == "#f8f8f2" then
    pass("fg_primary from foreground")
else
    fail("fg_primary")
end

if colours.red == "#ff5555" then
    pass("red from palette[1]")
else
    fail("red")
end

if colours.bg_secondary then
    pass("bg_secondary derived")
else
    fail("bg_secondary missing")
end

if colours.fg_secondary then
    pass("fg_secondary derived")
else
    fail("fg_secondary missing")
end

-- ═══════════════════════════════════════════════
section("apply_wcag_corrections")

-- Use colours with known low contrast against dark bg
local test_colours = {
    bg_primary = "#282a36",
    bg_secondary = "#44475a",
    line_highlight = "#2e3042",
    fg_primary = "#f8f8f2",
    fg_secondary = "#555555", -- Low contrast
    red = "#ff5555",
    green = "#50fa7b",
    yellow = "#f1fa8c",
    purple = "#bd93f9",
    pink = "#ff79c6",
    cyan = "#8be9fd",
}

local adjustments = gen.apply_wcag_corrections(test_colours)
-- fg_secondary was low contrast, should have been adjusted
local colour_utils = require("colour-utils")
local fg_sec_ratio = colour_utils.contrast_ratio(test_colours.fg_secondary, test_colours.bg_primary)
if fg_sec_ratio >= 5.0 then
    pass("fg_secondary meets 5.0:1 after correction")
else
    fail("fg_secondary contrast", string.format("ratio=%.2f", fg_sec_ratio))
end

-- ═══════════════════════════════════════════════
section("choose_active_accent")

local accent = gen.choose_active_accent({
    bg_primary = "#282a36",
    purple = "#bd93f9",
    cyan = "#8be9fd",
    green = "#50fa7b",
})
if accent == "purple" or accent == "cyan" or accent == "green" then
    pass("chooses from candidate set: " .. accent)
else
    fail("invalid accent choice", accent)
end

-- ═══════════════════════════════════════════════
section("generate_theme_file")

local theme_content = gen.generate_theme_file("test-theme", "Test Theme", {
    bg_primary = "#282a36",
    fg_primary = "#f8f8f2",
    bg_secondary = "#44475a",
    fg_secondary = "#6272a4",
    fg_variable = "#eeeee0",
    line_highlight = "#303340",
    red = "#ff5555",
    green = "#50fa7b",
    yellow = "#f1fa8c",
    purple = "#bd93f9",
    pink = "#ff79c6",
    cyan = "#8be9fd",
    cursor_colour = "#f8f8f2",
    cursor_text = "#282a36",
    selection = "#44475a",
    selection_fg = "#ffffff",
    palette = {
        [0] = "#282a36",
        [1] = "#ff5555",
        [2] = "#50fa7b",
        [3] = "#f1fa8c",
        [4] = "#bd93f9",
        [5] = "#ff79c6",
        [6] = "#8be9fd",
        [7] = "#f8f8f2",
    },
}, {
    cpu_low_bg = "#2a3040",
    cpu_medium_bg = "#2a3040",
    cpu_high_bg = "#2a3040",
    ram_low_bg = "#2a3040",
    ram_medium_bg = "#2a3040",
    ram_high_bg = "#2a3040",
    battery_normal_bg = "#2a3040",
    battery_low_bg = "#2a3040",
}, "purple", {})

if theme_content:find('THEME_NAME="Test Theme"') then
    pass("theme file has THEME_NAME")
else
    fail("theme file THEME_NAME")
end

if theme_content:find('TMUX_BG_PRIMARY="#282a36"') then
    pass("theme file has bg_primary")
else
    fail("theme file bg_primary")
end

if theme_content:find("GHOSTTY_BACKGROUND") then
    pass("theme file has Ghostty section")
else
    fail("theme file Ghostty section")
end

-- ═══════════════════════════════════════════════
section("apply_wcag_corrections: bright variant preference")

-- Bluloco Dark-style palette: dim normal row, identity colours in bright row
local bluloco_colours = {
    bg_primary = "#282c34",
    bg_secondary = "#41444d",
    line_highlight = "#343943",
    fg_primary = "#b9c0cb",
    fg_secondary = "#8f9aae",
    red = "#fc2f52",
    green = "#25a45c",
    yellow = "#ff936a",
    purple = "#3476ff",
    pink = "#7a82da",
    cyan = "#4483aa",
    palette = {
        [9] = "#ff6480",
        [10] = "#3fc56b",
        [11] = "#f9c859",
        [12] = "#10b1fe",
        [13] = "#ff78f8",
        [14] = "#5fb9bc",
    },
}

local bright_adjustments = gen.apply_wcag_corrections(bluloco_colours)

-- yellow's bright variant passes all surfaces outright, so it should be
-- adopted verbatim rather than lightening the dim orange
if bluloco_colours.yellow == "#f9c859" then
    pass("yellow swapped to bright variant verbatim")
else
    fail("yellow bright swap", "got " .. bluloco_colours.yellow)
end

local purple_swapped = false
for _, adj in ipairs(bright_adjustments) do
    if adj.name == "purple" and adj.swapped then
        purple_swapped = true
    end
end
if purple_swapped then
    pass("purple swap recorded in adjustments")
else
    fail("purple swap not recorded")
end

-- All accents must still meet 4.5:1 against the hardest surface
local all_pass = true
for _, name in ipairs({ "red", "green", "yellow", "purple", "pink", "cyan" }) do
    if colour_utils.contrast_ratio(bluloco_colours[name], bluloco_colours.bg_secondary) < 4.5 then
        all_pass = false
        fail("accent below 4.5:1 after correction", name)
    end
end
if all_pass then
    pass("all accents meet 4.5:1 on bg_secondary after correction")
end

-- ═══════════════════════════════════════════════
section("apply_wcag_corrections: dull theme fidelity")

-- Spacegray Eighties Dull-style palette: muted dim row that passes the
-- real backgrounds but not 4.5:1 against line_highlight. The relaxed
-- 3:1 line_highlight minimum must leave those colours untouched so the
-- nvim scheme matches Ghostty's rendering of the theme.
local dull_colours = {
    bg_primary = "#222222",
    bg_secondary = "#15171c",
    line_highlight = "#343434",
    fg_primary = "#c9c6bc",
    fg_secondary = "#94928b",
    red = "#b24a56",
    green = "#92b477",
    yellow = "#c6735a",
    purple = "#7c8fa5",
    pink = "#a5789e",
    cyan = "#80cdcb",
    palette = {
        [9] = "#ec5f67",
        [10] = "#89e986",
        [11] = "#fec254",
        [12] = "#5486c0",
        [13] = "#bf83c1",
        [14] = "#58c2c1",
    },
}

gen.apply_wcag_corrections(dull_colours)

-- yellow passes bg (4.55:1) and line_highlight at the 3:1 bar (3.56:1):
-- it must stay the designer's dull orange, not swap to the bright gold
if dull_colours.yellow == "#c6735a" then
    pass("passing dull yellow left verbatim")
else
    fail("dull yellow changed", "got " .. dull_colours.yellow)
end

if dull_colours.purple == "#7c8fa5" then
    pass("passing dull purple left verbatim")
else
    fail("dull purple changed", "got " .. dull_colours.purple)
end

-- red genuinely fails on bg_primary (3.04:1), so it should adopt the
-- bright variant verbatim with no synthetic lightening on top
if dull_colours.red == "#ec5f67" then
    pass("failing dull red swapped to bright variant verbatim")
else
    fail("dull red correction", "got " .. dull_colours.red)
end

-- ═══════════════════════════════════════════════
section("apply_saturation_preference: near-grey accent rescue")

-- Kanagawa Dragon-style palette: normal-row pink/cyan sit within a few
-- percent of grey; the theme's identity colours live in the bright row
local dragon_colours = {
    bg_primary = "#181616",
    bg_secondary = "#332e2e",
    line_highlight = "#2b2727",
    fg_primary = "#c5c9c5",
    fg_secondary = "#a6a69c",
    red = "#c4746e",
    green = "#8a9a7b",
    yellow = "#c4b28a",
    purple = "#8ba4b0",
    pink = "#a292a3",
    cyan = "#8ea4a2",
    palette = {
        [9] = "#e46876",
        [10] = "#87a987",
        [11] = "#e6c384",
        [12] = "#7fb4ca",
        [13] = "#938aa9",
        [14] = "#7aa89f",
    },
}

local sat_adjustments = gen.apply_saturation_preference(dragon_colours)

-- pink (chroma 17) and cyan (chroma 22) are near-grey: both swap to the
-- bright row
if dragon_colours.pink == "#938aa9" then
    pass("near-grey pink promoted to bright variant")
else
    fail("near-grey pink promotion", "got " .. dragon_colours.pink)
end

if dragon_colours.cyan == "#7aa89f" then
    pass("near-grey cyan promoted to bright variant")
else
    fail("near-grey cyan promotion", "got " .. dragon_colours.cyan)
end

-- purple (37), yellow (58) and red (86) carry visible chroma: the designer's
-- muted colours stay
if dragon_colours.purple == "#8ba4b0" and dragon_colours.yellow == "#c4b28a" and dragon_colours.red == "#c4746e" then
    pass("chromatic accents left verbatim")
else
    fail(
        "chromatic accents changed",
        dragon_colours.purple .. " " .. dragon_colours.yellow .. " " .. dragon_colours.red
    )
end

if #sat_adjustments == 2 then
    pass("promotions recorded in adjustments")
else
    fail("adjustment count", "got " .. #sat_adjustments)
end

-- Dull-but-chromatic palette (Spacegray Eighties Dull-style): every accent
-- sits above the near-grey threshold, so nothing is promoted even though
-- the bright row is more saturated
local dull_sat_colours = {
    bg_primary = "#222222",
    bg_secondary = "#15171c",
    line_highlight = "#343434",
    fg_primary = "#c9c6bc",
    fg_secondary = "#94928b",
    red = "#b24a56",
    green = "#92b477",
    yellow = "#c6735a",
    purple = "#7c8fa5",
    pink = "#a5789e",
    cyan = "#80cdcb",
    palette = {
        [9] = "#ec5f67",
        [10] = "#89e986",
        [11] = "#fec254",
        [12] = "#5486c0",
        [13] = "#bf83c1",
        [14] = "#58c2c1",
    },
}

local dull_sat_adjustments = gen.apply_saturation_preference(dull_sat_colours)

if #dull_sat_adjustments == 0 and dull_sat_colours.purple == "#7c8fa5" and dull_sat_colours.pink == "#a5789e" then
    pass("dull-but-chromatic palette untouched")
else
    fail("dull palette promoted", #dull_sat_adjustments .. " adjustments")
end

-- ═══════════════════════════════════════════════
section("generate_nvim_colourscheme: inverted selection")

local function nvim_fixture(overrides)
    local base = {
        bg_primary = "#282c34",
        fg_primary = "#b9c0cb",
        bg_secondary = "#41444d",
        fg_secondary = "#8f9aae",
        fg_variable = "#adbac8",
        line_highlight = "#343943",
        red = "#ff6480",
        green = "#3fc56b",
        yellow = "#f9c859",
        purple = "#10b1fe",
        pink = "#ff78f8",
        cyan = "#5fb9bc",
        selection = "#41444d",
        selection_fg = "#ffffff",
    }
    for k, v in pairs(overrides or {}) do
        base[k] = v
    end
    return base
end

-- Inverted: light selection bg with dark selection fg (Bluloco Dark)
local inverted =
    gen.generate_nvim_colourscheme("test-inverted", nvim_fixture({ selection = "#b9c0ca", selection_fg = "#272b33" }))

if inverted:find("hl('Visual', { fg = colors.selection_fg, bg = colors.selection })", 1, true) then
    pass("Visual gets selection_fg when selection is inverted")
else
    fail("Visual missing selection_fg on inverted selection")
end

if inverted:find("selection_fg = '#272b33'", 1, true) then
    pass("selection_fg passes through when readable")
else
    fail("selection_fg not passed through")
end

local ref = inverted:match("reference = '(#%x%x%x%x%x%x)'")
if ref and ref ~= "#b9c0ca" and colour_utils.luminance(ref) < 0.2 then
    pass("reference bg derived dark instead of inverted selection")
else
    fail("reference bg", tostring(ref))
end

if inverted:find("hl('LspReferenceText', { bg = colors.reference })", 1, true) then
    pass("LspReference uses reference bg")
else
    fail("LspReference should use reference bg")
end

-- Inverted with unreadable selection_fg: falls back to bg_primary
local fallback =
    gen.generate_nvim_colourscheme("test-fallback", nvim_fixture({ selection = "#b9c0ca", selection_fg = "#ffffff" }))
if fallback:find("selection_fg = '#282c34'", 1, true) then
    pass("unreadable selection_fg falls back to bg_primary")
else
    fail("selection_fg fallback")
end

-- Normal dark selection: Visual stays bg-only, reference equals selection
local normal = gen.generate_nvim_colourscheme("test-normal", nvim_fixture())
if normal:find("hl('Visual', { bg = colors.selection })", 1, true) then
    pass("Visual stays bg-only for normal selection")
else
    fail("Visual should stay bg-only for normal selection")
end

if normal:find("reference = '#41444d'", 1, true) then
    pass("reference equals selection for normal selection")
else
    fail("reference should equal selection for normal selection")
end

-- ═══════════════════════════════════════════════
section("Module can be required without CLI side effects")

-- The module guards CLI execution with pcall(debug.getlocal, 4, 1)
-- If we got this far without errors, the guard works
pass("module loads without executing CLI entry point")

-- ═══════════════════════════════════════════════
-- Summary
io.write(string.format("\n===========================================\n"))
io.write(
    string.format("Test Results: \027[0;32m%d passed\027[0m, \027[0;31m%d failed\027[0m\n", pass_count, fail_count)
)
io.write(string.format("===========================================\n"))

os.exit(fail_count > 0 and 1 or 0)
