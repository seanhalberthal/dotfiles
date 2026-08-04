-- Solarized Dark colourscheme for nvim
-- matches the dotfiles solarized-dark theme exactly
-- based on Ethan Schoonover's Solarized colour palette

vim.cmd 'highlight clear'
if vim.fn.exists 'syntax_on' then
  vim.cmd 'syntax reset'
end

vim.g.colors_name = 'solarized-dark'
vim.o.termguicolors = true

-- theme colours (matching themes/solarized-dark.theme)
local colors = {
  -- base colours
  bg_primary = '#002b36',
  fg_primary = '#93a1a1',
  bg_secondary = '#073642',
  fg_secondary = '#657b83',
  fg_variable = '#88989a',

  -- accents
  purple = '#6c71c4',
  pink = '#d33682',
  cyan = '#2aa198',
  green = '#859900',
  yellow = '#b58900',
  red = '#dc322f',

  -- additional solarized colours
  blue = '#268bd2',
  orange = '#cb4b16',
  base01 = '#586e75',
  base00 = '#657b83',
  base0 = '#839496',
  base1 = '#93a1a1',
  base2 = '#eee8d5',
  base3 = '#fdf6e3',

  -- additional shades
  selection = '#073642',
  comment = '#586e75',
  line_highlight = '#073642',
}

-- helper to set highlight groups
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
hl('IncSearch', { fg = colors.bg_primary, bg = colors.orange })
hl('MatchParen', { fg = colors.red, bold = true })
hl('Question', { fg = colors.cyan })
hl('ModeMsg', { fg = colors.blue, bold = true })
hl('MoreMsg', { fg = colors.blue })
hl('ErrorMsg', { fg = colors.red, bold = true })
hl('WarningMsg', { fg = colors.orange })
hl('VertSplit', { fg = colors.bg_secondary })
hl('WinSeparator', { fg = colors.bg_secondary })
hl('Folded', { fg = colors.comment, bg = colors.line_highlight })
hl('FoldColumn', { fg = colors.comment })
hl('Pmenu', { fg = colors.fg_primary, bg = colors.bg_secondary })
hl('PmenuSel', { fg = colors.bg_primary, bg = colors.cyan })
hl('PmenuSbar', { bg = colors.bg_secondary })
hl('PmenuThumb', { bg = colors.cyan })
hl('StatusLine', { fg = colors.base1, bg = colors.bg_secondary })
hl('StatusLineNC', { fg = colors.comment, bg = colors.bg_secondary })
hl('TabLine', { fg = colors.fg_secondary, bg = colors.bg_secondary })
hl('TabLineFill', { bg = colors.bg_secondary })
hl('TabLineSel', { fg = colors.base1, bg = colors.bg_primary, bold = true })
hl('Directory', { fg = colors.blue })
hl('Title', { fg = colors.orange, bold = true })
hl('SpecialKey', { fg = colors.comment })
hl('NonText', { fg = colors.comment })
hl('Whitespace', { fg = colors.comment })

-- syntax highlighting
hl('Comment', { fg = colors.comment, italic = true })
hl('Constant', { fg = colors.cyan })
hl('String', { fg = colors.cyan })
hl('Character', { fg = colors.cyan })
hl('Number', { fg = colors.cyan })
hl('Boolean', { fg = colors.cyan })
hl('Float', { fg = colors.cyan })
hl('Identifier', { fg = colors.blue })
hl('Function', { fg = colors.blue })
hl('Statement', { fg = colors.green })
hl('Conditional', { fg = colors.green })
hl('Repeat', { fg = colors.green })
hl('Label', { fg = colors.green })
hl('Operator', { fg = colors.green })
hl('Keyword', { fg = colors.green })
hl('Exception', { fg = colors.green })
hl('PreProc', { fg = colors.orange })
hl('Include', { fg = colors.orange })
hl('Define', { fg = colors.orange })
hl('Macro', { fg = colors.orange })
hl('PreCondit', { fg = colors.orange })
hl('Type', { fg = colors.yellow })
hl('StorageClass', { fg = colors.yellow })
hl('Structure', { fg = colors.yellow })
hl('Typedef', { fg = colors.yellow })
hl('Special', { fg = colors.red })
hl('SpecialChar', { fg = colors.red })
hl('Tag', { fg = colors.red }) -- special family upstream
hl('Delimiter', { fg = colors.base0 }) -- subtle, just below normal text
hl('SpecialComment', { fg = colors.comment, italic = true })
hl('Debug', { fg = colors.red })
hl('Underlined', { fg = colors.purple, underline = true })
hl('Ignore', { fg = colors.comment })
hl('Error', { fg = colors.red, bold = true })
hl('Todo', { fg = colors.pink, bold = true })

-- git signs
hl('GitSignsAdd', { fg = colors.green })
hl('GitSignsChange', { fg = colors.yellow })
hl('GitSignsDelete', { fg = colors.red })
hl('GitSignsTopdelete', { fg = colors.red })
hl('GitSignsChangedelete', { fg = colors.orange or colors.yellow })

-- diagnostics
hl('DiagnosticError', { fg = colors.red })
hl('DiagnosticWarn', { fg = colors.orange })
hl('DiagnosticInfo', { fg = colors.blue })
hl('DiagnosticHint', { fg = colors.cyan })
hl('DiagnosticUnderlineError', { undercurl = true, sp = colors.red })
hl('DiagnosticUnderlineWarn', { undercurl = true, sp = colors.orange })
hl('DiagnosticUnderlineInfo', { undercurl = true, sp = colors.blue })
hl('DiagnosticUnderlineHint', { undercurl = true, sp = colors.cyan })

-- LSP
hl('LspReferenceText', { bg = colors.selection })
hl('LspReferenceRead', { bg = colors.selection })
hl('LspReferenceWrite', { bg = colors.selection })

-- treesitter
hl('@variable', { fg = colors.fg_variable })
hl('@variable.builtin', { fg = colors.cyan })
hl('@variable.parameter', { fg = colors.blue }) -- upstream parameter role
hl('@variable.member', { fg = colors.blue })
hl('@constant', { fg = colors.cyan })
hl('@constant.builtin', { fg = colors.cyan })
hl('@module', { fg = colors.yellow }) -- links to Type upstream
hl('@string', { fg = colors.cyan })
hl('@string.escape', { fg = colors.red })
hl('@string.special', { fg = colors.red })
hl('@character', { fg = colors.cyan })
hl('@number', { fg = colors.cyan })
hl('@boolean', { fg = colors.cyan })
hl('@function', { fg = colors.blue })
hl('@function.builtin', { fg = colors.blue })
hl('@function.call', { fg = colors.blue })
hl('@function.macro', { fg = colors.orange })
hl('@method', { fg = colors.blue })
hl('@method.call', { fg = colors.blue })
hl('@constructor', { fg = colors.yellow })
hl('@keyword', { fg = colors.green })
hl('@keyword.function', { fg = colors.green })
hl('@keyword.operator', { fg = colors.green })
hl('@keyword.return', { fg = colors.green })
hl('@conditional', { fg = colors.green })
hl('@repeat', { fg = colors.green })
hl('@label', { fg = colors.green })
hl('@operator', { fg = colors.green })
hl('@exception', { fg = colors.green })
hl('@type', { fg = colors.yellow })
hl('@type.builtin', { fg = colors.yellow })
hl('@type.qualifier', { fg = colors.yellow }) -- type family upstream
hl('@property', { fg = colors.blue })
hl('@attribute', { fg = colors.orange })
hl('@tag', { fg = colors.blue }) -- htmlTagName upstream
hl('@tag.attribute', { fg = colors.base00 }) -- htmlArg upstream
hl('@tag.delimiter', { fg = colors.base01 }) -- htmlTag upstream
hl('@punctuation.delimiter', { fg = colors.base0 })
hl('@punctuation.bracket', { fg = colors.base0 })
hl('@punctuation.special', { fg = colors.red })
hl('@comment', { link = 'Comment' })
hl('@markup.strong', { bold = true })
hl('@markup.italic', { italic = true })
hl('@markup.underline', { underline = true })
hl('@markup.heading', { fg = colors.yellow, bold = true })
hl('@markup.link', { fg = colors.blue, underline = true })
hl('@markup.link.url', { fg = colors.cyan, underline = true })
hl('@markup.list', { fg = colors.green })
hl('@markup.raw', { fg = colors.cyan })

-- Telescope
hl('TelescopeBorder', { fg = colors.cyan, bg = colors.bg_secondary })
hl('TelescopePromptBorder', { fg = colors.blue, bg = colors.bg_secondary })
hl('TelescopePromptTitle', { fg = colors.blue, bold = true })
hl('TelescopePreviewTitle', { fg = colors.cyan, bold = true })
hl('TelescopeResultsTitle', { fg = colors.cyan, bold = true })
hl('TelescopeSelection', { fg = colors.yellow, bg = colors.selection, bold = true })
hl('TelescopeMatching', { fg = colors.orange, bold = true })

-- neo-tree
hl('NeoTreeNormal', { fg = colors.fg_primary, bg = colors.bg_secondary })
hl('NeoTreeNormalNC', { fg = colors.fg_primary, bg = colors.bg_secondary })
hl('NeoTreeCursorLine', { bg = '#2c545e' })
hl('NeoTreeDirectoryIcon', { fg = colors.blue })
hl('NeoTreeDirectoryName', { fg = colors.blue })
hl('NeoTreeFileName', { fg = colors.fg_primary })
hl('NeoTreeFileNameOpened', { fg = colors.yellow })
hl('NeoTreeGitModified', { fg = colors.yellow })
hl('NeoTreeGitAdded', { fg = colors.green })
hl('NeoTreeGitDeleted', { fg = colors.red })
hl('NeoTreeIndentMarker', { fg = colors.comment })
hl('NeoTreeRootName', { fg = colors.orange, bold = true })

-- which-key
hl('WhichKey', { fg = colors.blue })
hl('WhichKeyGroup', { fg = colors.green })
hl('WhichKeyDesc', { fg = colors.fg_primary })
hl('WhichKeySeparator', { fg = colors.comment })

-- Mini.nvim statusline
hl('MiniStatuslineModeNormal', { fg = colors.bg_primary, bg = colors.blue, bold = true })
hl('MiniStatuslineModeInsert', { fg = colors.bg_primary, bg = colors.green, bold = true })
hl('MiniStatuslineModeVisual', { fg = colors.bg_primary, bg = colors.pink, bold = true })
hl('MiniStatuslineModeReplace', { fg = colors.bg_primary, bg = colors.red, bold = true })
hl('MiniStatuslineModeCommand', { fg = colors.bg_primary, bg = colors.yellow, bold = true })
hl('MiniStatuslineDevinfo', { fg = colors.fg_primary, bg = colors.bg_secondary })
hl('MiniStatuslineFilename', { fg = colors.fg_primary, bg = colors.bg_secondary })
hl('MiniStatuslineFileinfo', { fg = colors.fg_primary, bg = colors.bg_secondary })
hl('MiniStatuslineInactive', { fg = colors.comment, bg = colors.bg_secondary })
