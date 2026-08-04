-- synthwave colourscheme for nvim
-- matches the dotfiles synthwave theme exactly
-- cyberpunk vaporwave aesthetic

vim.cmd 'highlight clear'
if vim.fn.exists 'syntax_on' then
  vim.cmd 'syntax reset'
end

vim.g.colors_name = 'synthwave'
vim.o.termguicolors = true

-- theme colours (matching themes/synthwave.theme)
local colors = {
  -- base colours
  bg_primary = '#1a1226',
  fg_primary = '#e4dfed',
  bg_secondary = '#2a1f3d',
  fg_secondary = '#9d8ec7',
  fg_variable = '#d2cbe4',

  -- accents
  purple = '#b794f6',
  pink = '#ff2e97',
  cyan = '#00d9ff',
  green = '#39ff14',
  yellow = '#ffd700',
  red = '#ff003c',

  -- additional shades
  selection = '#3d2861',
  comment = '#6b5a82',
  line_highlight = '#241735',

  -- bright variants
  bright_cyan = '#5cefff',
  bright_pink = '#ff5ac8',
  bright_green = '#6bff59',
  bright_purple = '#d6acff',

  -- syntax roles (mirroring upstream synthwave-vscode)
  neon_cyan = '#36f9f6', -- functions, escapes
  neon_yellow = '#fede5d', -- keywords, operators, attributes
  neon_red = '#fe4450', -- types, modules, builtins
  neon_orange = '#ff8b39', -- strings
  salmon = '#f97e72', -- constants, numbers
  neon_pink = '#ff7edb', -- variables, properties
  neon_green = '#72f1b8', -- tags, preproc
  punct = '#b6b1b1', -- punctuation
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
hl('Cursor', { fg = colors.bg_primary, bg = colors.cyan })
hl('CursorLine', { bg = colors.line_highlight })
hl('CursorLineNr', { fg = colors.cyan, bold = true })
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
hl('StatusLine', { fg = colors.cyan, bg = colors.bg_secondary })
hl('StatusLineNC', { fg = colors.comment, bg = colors.bg_secondary })
hl('TabLine', { fg = colors.fg_secondary, bg = colors.bg_secondary })
hl('TabLineFill', { bg = colors.bg_secondary })
hl('TabLineSel', { fg = colors.cyan, bg = colors.bg_primary, bold = true })
hl('Directory', { fg = colors.cyan })
hl('Title', { fg = colors.pink, bold = true })
hl('SpecialKey', { fg = colors.comment })
hl('NonText', { fg = colors.comment })
hl('Whitespace', { fg = colors.comment })

-- syntax highlighting
hl('Comment', { fg = colors.comment, italic = true })
hl('Constant', { fg = colors.salmon })
hl('String', { fg = colors.neon_orange })
hl('Character', { fg = colors.neon_orange })
hl('Number', { fg = colors.salmon })
hl('Boolean', { fg = colors.salmon })
hl('Float', { fg = colors.salmon })
hl('Identifier', { fg = colors.neon_pink })
hl('Function', { fg = colors.neon_cyan })
hl('Statement', { fg = colors.neon_yellow })
hl('Conditional', { fg = colors.neon_yellow })
hl('Repeat', { fg = colors.neon_yellow })
hl('Label', { fg = colors.neon_yellow })
hl('Operator', { fg = colors.neon_yellow })
hl('Keyword', { fg = colors.neon_yellow })
hl('Exception', { fg = colors.neon_yellow })
hl('PreProc', { fg = colors.neon_green })
hl('Include', { fg = colors.neon_green })
hl('Define', { fg = colors.neon_green })
hl('Macro', { fg = colors.neon_green })
hl('PreCondit', { fg = colors.neon_green })
hl('Type', { fg = colors.neon_red })
hl('StorageClass', { fg = colors.neon_yellow })
hl('Structure', { fg = colors.neon_red })
hl('Typedef', { fg = colors.neon_red })
hl('Special', { fg = colors.neon_cyan })
hl('SpecialChar', { fg = colors.neon_cyan })
hl('Tag', { fg = colors.neon_green })
hl('Delimiter', { fg = colors.punct })
hl('SpecialComment', { fg = colors.comment, italic = true })
hl('Debug', { fg = colors.red })
hl('Underlined', { fg = colors.cyan, underline = true })
hl('Ignore', { fg = colors.comment })
hl('Error', { fg = colors.red, bold = true })
hl('Todo', { fg = colors.pink, bold = true })

-- Git signs
hl('GitSignsAdd', { fg = colors.green })
hl('GitSignsChange', { fg = colors.yellow })
hl('GitSignsDelete', { fg = colors.red })
hl('GitSignsTopdelete', { fg = colors.red })
hl('GitSignsChangedelete', { fg = colors.orange or colors.yellow })

-- Diagnostics
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

-- Treesitter
hl('@variable', { fg = colors.fg_variable })
hl('@variable.builtin', { fg = colors.neon_red, bold = true })
hl('@variable.parameter', { fg = colors.neon_pink })
hl('@variable.member', { fg = colors.neon_pink })
hl('@constant', { fg = colors.salmon })
hl('@constant.builtin', { fg = colors.salmon })
hl('@module', { fg = colors.neon_red })
hl('@string', { fg = colors.neon_orange })
hl('@string.escape', { fg = colors.neon_cyan })
hl('@string.special', { fg = colors.salmon })
hl('@character', { fg = colors.neon_orange })
hl('@number', { fg = colors.salmon })
hl('@boolean', { fg = colors.salmon })
hl('@function', { fg = colors.neon_cyan })
hl('@function.builtin', { fg = colors.neon_cyan })
hl('@function.call', { fg = colors.neon_cyan })
hl('@function.macro', { fg = colors.neon_green })
hl('@method', { fg = colors.neon_cyan })
hl('@method.call', { fg = colors.neon_cyan })
hl('@constructor', { fg = colors.neon_red })
hl('@keyword', { fg = colors.neon_yellow })
hl('@keyword.function', { fg = colors.neon_yellow })
hl('@keyword.operator', { fg = colors.neon_yellow })
hl('@keyword.return', { fg = colors.neon_yellow })
hl('@conditional', { fg = colors.neon_yellow })
hl('@repeat', { fg = colors.neon_yellow })
hl('@label', { fg = colors.neon_yellow })
hl('@operator', { fg = colors.neon_yellow })
hl('@exception', { fg = colors.neon_yellow })
hl('@type', { fg = colors.neon_red })
hl('@type.builtin', { fg = colors.neon_red })
hl('@type.qualifier', { fg = colors.neon_yellow })
hl('@property', { fg = colors.neon_pink })
hl('@attribute', { fg = colors.neon_yellow })
hl('@tag', { fg = colors.neon_green })
hl('@tag.attribute', { fg = colors.neon_yellow })
hl('@tag.delimiter', { fg = colors.neon_cyan })
hl('@punctuation.delimiter', { fg = colors.punct })
hl('@punctuation.bracket', { fg = colors.punct })
hl('@punctuation.special', { fg = colors.neon_green })
hl('@comment', { link = 'Comment' })
hl('@markup.strong', { bold = true })
hl('@markup.italic', { italic = true })
hl('@markup.underline', { underline = true })
hl('@markup.heading', { fg = colors.pink, bold = true })
hl('@markup.link', { fg = colors.cyan, underline = true })
hl('@markup.link.url', { fg = colors.purple, underline = true })
hl('@markup.list', { fg = colors.cyan })
hl('@markup.raw', { fg = colors.yellow })

-- Telescope
hl('TelescopeBorder', { fg = colors.cyan, bg = colors.bg_secondary })
hl('TelescopePromptBorder', { fg = colors.pink, bg = colors.bg_secondary })
hl('TelescopePromptTitle', { fg = colors.pink, bold = true })
hl('TelescopePreviewTitle', { fg = colors.cyan, bold = true })
hl('TelescopeResultsTitle', { fg = colors.cyan, bold = true })
hl('TelescopeSelection', { fg = colors.cyan, bg = colors.selection, bold = true })
hl('TelescopeMatching', { fg = colors.pink, bold = true })

-- Neo-tree
hl('NeoTreeNormal', { fg = colors.fg_primary, bg = colors.bg_secondary })
hl('NeoTreeNormalNC', { fg = colors.fg_primary, bg = colors.bg_secondary })
hl('NeoTreeCursorLine', { bg = '#49405a' })
hl('NeoTreeDirectoryIcon', { fg = colors.cyan })
hl('NeoTreeDirectoryName', { fg = colors.cyan })
hl('NeoTreeFileName', { fg = colors.fg_primary })
hl('NeoTreeFileNameOpened', { fg = colors.pink })
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

-- Mini.nvim statusline
hl('MiniStatuslineModeNormal', { fg = colors.bg_primary, bg = colors.cyan, bold = true })
hl('MiniStatuslineModeInsert', { fg = colors.bg_primary, bg = colors.green, bold = true })
hl('MiniStatuslineModeVisual', { fg = colors.bg_primary, bg = colors.purple, bold = true })
hl('MiniStatuslineModeReplace', { fg = colors.bg_primary, bg = colors.red, bold = true })
hl('MiniStatuslineModeCommand', { fg = colors.bg_primary, bg = colors.yellow, bold = true })
hl('MiniStatuslineDevinfo', { fg = colors.fg_primary, bg = colors.bg_secondary })
hl('MiniStatuslineFilename', { fg = colors.fg_primary, bg = colors.bg_secondary })
hl('MiniStatuslineFileinfo', { fg = colors.fg_primary, bg = colors.bg_secondary })
hl('MiniStatuslineInactive', { fg = colors.comment, bg = colors.bg_secondary })
