-- nightfox colourscheme for nvim
-- matches the dotfiles nightfox.theme exactly

vim.cmd 'highlight clear'
if vim.fn.exists 'syntax_on' then
  vim.cmd 'syntax reset'
end

vim.g.colors_name = 'nightfox'
vim.o.termguicolors = true

-- theme colours (matching themes/nightfox.theme)
local colors = {
  -- base colours
  bg_primary = '#192330',
  fg_primary = '#cdcecf',
  bg_secondary = '#212e3f',
  fg_secondary = '#71839b',
  fg_variable = '#b6bbc2',

  -- accents
  purple = '#c792ea',
  pink = '#d67ad2',
  cyan = '#81b29a',
  green = '#a3be8c',
  yellow = '#dbc074',
  red = '#c94f6d',

  -- additional shades
  selection = '#2b3b51',
  comment = '#71839b',
  line_highlight = '#1e2a38',
  blue = '#719cd6',
  orange = '#f4a261',

  -- syntax roles (mirroring upstream nightfox.nvim)
  magenta = '#9d79d6', -- keywords
  magenta_bright = '#baa1e2', -- conditionals, loops
  blue_bright = '#86abdc', -- functions
  cyan_base = '#63cdcf', -- identifiers, constructors
  cyan_bright = '#7ad5d6', -- builtin types, parameters, modules
  string_green = '#81b29a', -- strings
  orange_bright = '#f6b079', -- constants
  yellow_bright = '#e0c989', -- regex, escapes
  pink_bright = '#dc8ed9', -- preproc
  punct = '#aeafb0', -- operators, punctuation
}

-- set a highlight group
local function hl(group, opts)
  vim.api.nvim_set_hl(0, group, opts)
end

-- editor highlights
hl('Normal', { fg = colors.fg_primary, bg = colors.bg_primary })
hl('NormalFloat', { fg = colors.fg_primary, bg = colors.bg_secondary })
hl('FloatBorder', { fg = colors.cyan, bg = colors.bg_secondary })
hl('ColorColumn', { bg = colors.line_highlight })
hl('Cursor', { fg = colors.bg_primary, bg = colors.fg_primary })
hl('CursorLine', { bg = colors.line_highlight })
hl('CursorLineNr', { fg = '#c792ea', bold = true })
hl('LineNr', { fg = colors.comment })
hl('SignColumn', { bg = colors.bg_primary })
hl('Visual', { bg = colors.selection })
hl('VisualNOS', { bg = colors.selection })
hl('Search', { fg = colors.bg_primary, bg = colors.yellow })
hl('IncSearch', { fg = colors.bg_primary, bg = '#d67ad2' })
hl('MatchParen', { fg = '#d67ad2', bold = true })
hl('Question', { fg = colors.cyan })
hl('ModeMsg', { fg = colors.green, bold = true })
hl('MoreMsg', { fg = colors.green })
hl('ErrorMsg', { fg = colors.red, bold = true })
hl('WarningMsg', { fg = colors.yellow })
hl('VertSplit', { fg = colors.bg_secondary })
hl('WinSeparator', { fg = colors.bg_secondary })
hl('Folded', { fg = colors.comment, bg = colors.line_highlight })
hl('FoldColumn', { fg = colors.comment })
hl('Pmenu', { fg = colors.fg_primary, bg = colors.bg_secondary })
hl('PmenuSel', { fg = colors.bg_primary, bg = '#c792ea' })
hl('PmenuSbar', { bg = colors.bg_secondary })
hl('PmenuThumb', { bg = '#c792ea' })
hl('StatusLine', { fg = '#c792ea', bg = colors.bg_secondary })
hl('StatusLineNC', { fg = colors.comment, bg = colors.bg_secondary })
hl('TabLine', { fg = colors.fg_secondary, bg = colors.bg_secondary })
hl('TabLineFill', { bg = colors.bg_secondary })
hl('TabLineSel', { fg = '#c792ea', bg = colors.bg_primary, bold = true })
hl('Directory', { fg = colors.cyan })
hl('Title', { fg = '#d67ad2', bold = true })
hl('SpecialKey', { fg = colors.comment })
hl('NonText', { fg = colors.comment })
hl('Whitespace', { fg = colors.comment })

-- syntax highlighting
hl('Comment', { fg = colors.comment, italic = true })
hl('Constant', { fg = colors.orange_bright })
hl('String', { fg = colors.string_green })
hl('Character', { fg = colors.string_green })
hl('Number', { fg = colors.orange })
hl('Boolean', { fg = colors.orange })
hl('Float', { fg = colors.orange })
hl('Identifier', { fg = colors.cyan_base })
hl('Function', { fg = colors.blue_bright })
hl('Statement', { fg = colors.magenta })
hl('Conditional', { fg = colors.magenta_bright })
hl('Repeat', { fg = colors.magenta_bright })
hl('Label', { fg = colors.magenta_bright })
hl('Operator', { fg = colors.punct })
hl('Keyword', { fg = colors.magenta })
hl('Exception', { fg = colors.magenta })
hl('PreProc', { fg = colors.pink_bright })
hl('Include', { fg = colors.pink_bright })
hl('Define', { fg = colors.pink_bright })
hl('Macro', { fg = colors.pink_bright })
hl('PreCondit', { fg = colors.pink_bright })
hl('Type', { fg = colors.yellow })
hl('StorageClass', { fg = colors.yellow })
hl('Structure', { fg = colors.yellow })
hl('Typedef', { fg = colors.yellow })
hl('Special', { fg = colors.blue_bright })
hl('SpecialChar', { fg = colors.blue_bright })
hl('Tag', { fg = colors.blue_bright })
hl('Delimiter', { fg = colors.punct })
hl('SpecialComment', { fg = colors.comment, italic = true })
hl('Debug', { fg = colors.red })
hl('Underlined', { fg = colors.cyan, underline = true })
hl('Ignore', { fg = colors.comment })
hl('Error', { fg = colors.red, bold = true })
hl('Todo', { fg = '#d67ad2', bold = true })

-- git signs
hl('GitSignsAdd', { fg = colors.green })
hl('GitSignsChange', { fg = colors.yellow })
hl('GitSignsDelete', { fg = colors.red })
hl('GitSignsTopdelete', { fg = colors.red })
hl('GitSignsChangedelete', { fg = colors.orange or colors.yellow })

-- diagnostics
hl('DiagnosticError', { fg = colors.red })
hl('DiagnosticWarn', { fg = colors.yellow })
hl('DiagnosticInfo', { fg = colors.cyan })
hl('DiagnosticHint', { fg = colors.purple })
hl('DiagnosticUnderlineError', { undercurl = true, sp = colors.red })
hl('DiagnosticUnderlineWarn', { undercurl = true, sp = colors.yellow })
hl('DiagnosticUnderlineInfo', { undercurl = true, sp = colors.cyan })
hl('DiagnosticUnderlineHint', { undercurl = true, sp = colors.purple })

-- LSP
hl('LspReferenceText', { bg = colors.selection })
hl('LspReferenceRead', { bg = colors.selection })
hl('LspReferenceWrite', { bg = colors.selection })

-- treesitter
hl('@variable', { fg = colors.fg_variable })
hl('@variable.builtin', { fg = colors.red })
hl('@variable.parameter', { fg = colors.cyan_bright })
hl('@variable.member', { fg = colors.blue })
hl('@constant', { fg = colors.orange_bright })
hl('@constant.builtin', { fg = colors.orange_bright })
hl('@module', { fg = colors.cyan_bright })
hl('@string', { fg = colors.string_green })
hl('@string.escape', { fg = colors.yellow_bright, bold = true })
hl('@string.special', { fg = colors.blue_bright })
hl('@character', { fg = colors.string_green })
hl('@number', { fg = colors.orange })
hl('@boolean', { fg = colors.orange })
hl('@function', { fg = colors.blue_bright })
hl('@function.builtin', { fg = colors.red })
hl('@function.call', { fg = colors.blue_bright })
hl('@function.macro', { fg = colors.red })
hl('@method', { fg = colors.blue_bright })
hl('@method.call', { fg = colors.blue_bright })
hl('@constructor', { fg = colors.cyan_base })
hl('@keyword', { fg = colors.magenta })
hl('@keyword.function', { fg = colors.magenta })
hl('@keyword.operator', { fg = colors.punct })
hl('@keyword.return', { fg = colors.red })
hl('@conditional', { fg = colors.magenta_bright })
hl('@repeat', { fg = colors.magenta_bright })
hl('@label', { fg = colors.magenta_bright })
hl('@operator', { fg = colors.punct })
hl('@exception', { fg = colors.magenta })
hl('@type', { fg = colors.yellow })
hl('@type.builtin', { fg = colors.cyan_bright })
hl('@type.qualifier', { fg = colors.magenta })
hl('@property', { fg = colors.blue })
hl('@attribute', { fg = colors.orange_bright })
hl('@tag', { fg = colors.magenta })
hl('@tag.attribute', { fg = colors.blue_bright })
hl('@tag.delimiter', { fg = colors.cyan_bright })
hl('@punctuation.delimiter', { fg = colors.punct })
hl('@punctuation.bracket', { fg = colors.punct })
hl('@punctuation.special', { fg = colors.cyan_bright })
hl('@comment', { link = 'Comment' })
hl('@markup.strong', { bold = true })
hl('@markup.italic', { italic = true })
hl('@markup.underline', { underline = true })
hl('@markup.heading', { fg = '#d67ad2', bold = true })
hl('@markup.link', { fg = colors.cyan, underline = true })
hl('@markup.link.url', { fg = colors.purple, underline = true })
hl('@markup.list', { fg = '#81b29a' })
hl('@markup.raw', { fg = '#a3be8c' })

-- Telescope
hl('TelescopeBorder', { fg = '#c792ea', bg = colors.bg_secondary })
hl('TelescopePromptBorder', { fg = '#d67ad2', bg = colors.bg_secondary })
hl('TelescopePromptTitle', { fg = '#d67ad2', bold = true })
hl('TelescopePreviewTitle', { fg = '#c792ea', bold = true })
hl('TelescopeResultsTitle', { fg = '#c792ea', bold = true })
hl('TelescopeSelection', { fg = '#c792ea', bg = colors.selection, bold = true })
hl('TelescopeMatching', { fg = '#d67ad2', bold = true })

-- neo-tree
hl('NeoTreeNormal', { fg = colors.fg_primary, bg = colors.bg_secondary })
hl('NeoTreeNormalNC', { fg = colors.fg_primary, bg = colors.bg_secondary })
hl('NeoTreeCursorLine', { bg = '#424d5b' })
hl('NeoTreeDirectoryIcon', { fg = colors.cyan })
hl('NeoTreeDirectoryName', { fg = colors.cyan })
hl('NeoTreeFileName', { fg = colors.fg_primary })
hl('NeoTreeFileNameOpened', { fg = '#d67ad2' })
hl('NeoTreeGitModified', { fg = colors.yellow })
hl('NeoTreeGitAdded', { fg = colors.green })
hl('NeoTreeGitDeleted', { fg = colors.red })
hl('NeoTreeIndentMarker', { fg = colors.comment })
hl('NeoTreeRootName', { fg = '#d67ad2', bold = true })

-- which-key
hl('WhichKey', { fg = '#c792ea' })
hl('WhichKeyGroup', { fg = '#d67ad2' })
hl('WhichKeyDesc', { fg = colors.fg_primary })
hl('WhichKeySeparator', { fg = colors.comment })

-- mini.nvim statusline
hl('MiniStatuslineModeNormal', { fg = colors.bg_primary, bg = '#c792ea', bold = true })
hl('MiniStatuslineModeInsert', { fg = colors.bg_primary, bg = colors.green, bold = true })
hl('MiniStatuslineModeVisual', { fg = colors.bg_primary, bg = colors.purple, bold = true })
hl('MiniStatuslineModeReplace', { fg = colors.bg_primary, bg = colors.red, bold = true })
hl('MiniStatuslineModeCommand', { fg = colors.bg_primary, bg = colors.yellow, bold = true })
hl('MiniStatuslineDevinfo', { fg = colors.fg_primary, bg = colors.bg_secondary })
hl('MiniStatuslineFilename', { fg = colors.fg_primary, bg = colors.bg_secondary })
hl('MiniStatuslineFileinfo', { fg = colors.fg_primary, bg = colors.bg_secondary })
hl('MiniStatuslineInactive', { fg = colors.comment, bg = colors.bg_secondary })
