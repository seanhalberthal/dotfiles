-- monokai colorscheme for nvim, matching the dotfiles monokai theme exactly

vim.cmd 'highlight clear'
if vim.fn.exists 'syntax_on' then
  vim.cmd 'syntax reset'
end

vim.g.colors_name = 'monokai'
vim.o.termguicolors = true

-- theme colours (matching themes/monokai.theme)
local colors = {
  -- base colours
  bg_primary = '#272822',
  fg_primary = '#f8f8f2',
  bg_secondary = '#3e3d32',
  fg_secondary = '#75715e',
  fg_variable = '#d7d6cd',

  -- accents
  purple = '#ae81ff',
  pink = '#f92672',
  cyan = '#66d9ef',
  green = '#a6e22e',
  yellow = '#e6db74',
  red = '#ff5555',

  -- additional shades
  selection = '#49483e',
  comment = '#75715e',
  line_highlight = '#3e3d32',

  -- bright variants
  bright_green = '#a6e22e',
  bright_yellow = '#f4bf75',
  bright_cyan = '#a1efe4',

  -- syntax roles (mirroring upstream monokai.nvim classic)
  orange = '#fd971f', -- parameters, builtin variables
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
hl('CursorLineNr', { fg = colors.yellow, bold = true })
hl('LineNr', { fg = colors.comment })
hl('SignColumn', { bg = colors.bg_primary })
hl('Visual', { bg = colors.selection })
hl('VisualNOS', { bg = colors.selection })
hl('Search', { fg = colors.bg_primary, bg = colors.yellow })
hl('IncSearch', { fg = colors.bg_primary, bg = colors.pink })
hl('MatchParen', { fg = colors.pink, bold = true })
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
hl('PmenuSel', { fg = colors.bg_primary, bg = colors.cyan })
hl('PmenuSbar', { bg = colors.bg_secondary })
hl('PmenuThumb', { bg = colors.cyan })
hl('StatusLine', { fg = colors.fg_primary, bg = colors.bg_secondary })
hl('StatusLineNC', { fg = colors.comment, bg = colors.bg_secondary })
hl('TabLine', { fg = colors.fg_secondary, bg = colors.bg_secondary })
hl('TabLineFill', { bg = colors.bg_secondary })
hl('TabLineSel', { fg = colors.fg_primary, bg = colors.bg_primary, bold = true })
hl('Directory', { fg = colors.cyan })
hl('Title', { fg = colors.yellow, bold = true })
hl('SpecialKey', { fg = colors.comment })
hl('NonText', { fg = colors.comment })
hl('Whitespace', { fg = colors.comment })

-- syntax highlighting
hl('Comment', { fg = colors.comment, italic = true })
hl('Constant', { fg = colors.purple })
hl('String', { fg = colors.yellow })
hl('Character', { fg = colors.yellow })
hl('Number', { fg = colors.purple })
hl('Boolean', { fg = colors.purple })
hl('Float', { fg = colors.purple })
hl('Identifier', { fg = colors.fg_primary })
hl('Function', { fg = colors.green })
hl('Statement', { fg = colors.pink })
hl('Conditional', { fg = colors.pink })
hl('Repeat', { fg = colors.pink })
hl('Label', { fg = colors.pink })
hl('Operator', { fg = colors.pink })
hl('Keyword', { fg = colors.pink })
hl('Exception', { fg = colors.pink })
hl('PreProc', { fg = colors.green })
hl('Include', { fg = colors.cyan })
hl('Define', { fg = colors.pink })
hl('Macro', { fg = colors.pink })
hl('PreCondit', { fg = colors.pink })
hl('Type', { fg = colors.cyan })
hl('StorageClass', { fg = colors.cyan })
hl('Structure', { fg = colors.cyan })
hl('Typedef', { fg = colors.cyan })
hl('Special', { fg = colors.fg_primary })
hl('SpecialChar', { fg = colors.pink })
hl('Tag', { fg = colors.orange })
hl('Delimiter', { fg = colors.fg_primary })
hl('SpecialComment', { fg = colors.comment, italic = true })
hl('Debug', { fg = colors.red })
hl('Underlined', { fg = colors.cyan, underline = true })
hl('Ignore', { fg = colors.comment })
hl('Error', { fg = colors.red, bold = true })
hl('Todo', { fg = colors.purple, bold = true })

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
hl('@variable.builtin', { fg = colors.orange })
hl('@variable.parameter', { fg = colors.orange })
hl('@variable.member', { fg = colors.fg_primary })
hl('@constant', { fg = colors.purple })
hl('@constant.builtin', { fg = colors.purple })
hl('@module', { fg = colors.purple })
hl('@string', { fg = colors.yellow })
hl('@string.escape', { fg = colors.purple })
hl('@string.special', { fg = colors.purple })
hl('@character', { fg = colors.yellow })
hl('@number', { fg = colors.purple })
hl('@boolean', { fg = colors.purple })
hl('@function', { fg = colors.green })
hl('@function.builtin', { fg = colors.cyan })
hl('@function.call', { fg = colors.green })
hl('@function.macro', { fg = colors.green })
hl('@method', { fg = colors.green })
hl('@method.call', { fg = colors.green })
hl('@constructor', { fg = colors.cyan })
hl('@keyword', { fg = colors.pink })
hl('@keyword.function', { fg = colors.cyan })
hl('@keyword.operator', { fg = colors.pink })
hl('@keyword.return', { fg = colors.pink })
hl('@conditional', { fg = colors.pink })
hl('@repeat', { fg = colors.pink })
hl('@label', { fg = colors.pink })
hl('@operator', { fg = colors.pink })
hl('@exception', { fg = colors.pink })
hl('@type', { fg = colors.cyan })
hl('@type.builtin', { fg = colors.cyan })
hl('@type.qualifier', { fg = colors.pink })
hl('@property', { fg = colors.fg_primary })
hl('@attribute', { fg = colors.green })
hl('@tag', { fg = colors.pink })
hl('@tag.attribute', { fg = colors.green })
hl('@tag.delimiter', { fg = colors.fg_primary })
hl('@punctuation.delimiter', { fg = colors.fg_primary })
hl('@punctuation.bracket', { fg = colors.fg_primary })
hl('@punctuation.special', { fg = colors.pink })
hl('@comment', { link = 'Comment' })
hl('@markup.strong', { bold = true })
hl('@markup.italic', { italic = true })
hl('@markup.underline', { underline = true })
hl('@markup.heading', { fg = colors.green, bold = true })
hl('@markup.link', { fg = colors.cyan, underline = true })
hl('@markup.link.url', { fg = colors.purple, underline = true })
hl('@markup.list', { fg = colors.pink })
hl('@markup.raw', { fg = colors.yellow })

-- Telescope
hl('TelescopeBorder', { fg = colors.cyan, bg = colors.bg_secondary })
hl('TelescopePromptBorder', { fg = colors.pink, bg = colors.bg_secondary })
hl('TelescopePromptTitle', { fg = colors.pink, bold = true })
hl('TelescopePreviewTitle', { fg = colors.cyan, bold = true })
hl('TelescopeResultsTitle', { fg = colors.cyan, bold = true })
hl('TelescopeSelection', { fg = colors.yellow, bg = colors.selection, bold = true })
hl('TelescopeMatching', { fg = colors.pink, bold = true })

-- Neo-tree
hl('NeoTreeNormal', { fg = colors.fg_primary, bg = colors.bg_secondary })
hl('NeoTreeNormalNC', { fg = colors.fg_primary, bg = colors.bg_secondary })
hl('NeoTreeCursorLine', { bg = '#5a5a50' })
hl('NeoTreeDirectoryIcon', { fg = colors.cyan })
hl('NeoTreeDirectoryName', { fg = colors.cyan })
hl('NeoTreeFileName', { fg = colors.fg_primary })
hl('NeoTreeFileNameOpened', { fg = colors.green })
hl('NeoTreeGitModified', { fg = colors.yellow })
hl('NeoTreeGitAdded', { fg = colors.green })
hl('NeoTreeGitDeleted', { fg = colors.red })
hl('NeoTreeIndentMarker', { fg = colors.comment })
hl('NeoTreeRootName', { fg = colors.pink, bold = true })

-- Which-key
hl('WhichKey', { fg = colors.cyan })
hl('WhichKeyGroup', { fg = colors.pink })
hl('WhichKeyDesc', { fg = colors.fg_primary })
hl('WhichKeySeparator', { fg = colors.comment })

-- mini.nvim statusline
hl('MiniStatuslineModeNormal', { fg = colors.bg_primary, bg = colors.cyan, bold = true })
hl('MiniStatuslineModeInsert', { fg = colors.bg_primary, bg = colors.green, bold = true })
hl('MiniStatuslineModeVisual', { fg = colors.bg_primary, bg = colors.purple, bold = true })
hl('MiniStatuslineModeReplace', { fg = colors.bg_primary, bg = colors.red, bold = true })
hl('MiniStatuslineModeCommand', { fg = colors.bg_primary, bg = colors.yellow, bold = true })
hl('MiniStatuslineDevinfo', { fg = colors.fg_primary, bg = colors.bg_secondary })
hl('MiniStatuslineFilename', { fg = colors.fg_primary, bg = colors.bg_secondary })
hl('MiniStatuslineFileinfo', { fg = colors.fg_primary, bg = colors.bg_secondary })
hl('MiniStatuslineInactive', { fg = colors.comment, bg = colors.bg_secondary })
