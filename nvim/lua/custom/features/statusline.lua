-- bespoke mini.statusline content + section overrides. extracted from
-- plugins/mini.lua; setup() requires the mini.statusline singleton itself so
-- lua_ls keeps the library's section_* signatures, then overrides them.

local M = {}

-- neotest's diagnostic consumer namespace, resolved by name so it doesn't
-- pull neotest in. nvim_create_namespace returns the existing id when one is
-- already registered, and an empty namespace when it isn't
local neotest_ns = vim.api.nvim_create_namespace 'neotest'

-- modified/readonly flag suffix, shared by the active content closure and the
-- inactive section_filename override.
local function flags()
  return (vim.bo.modified and ' [+]' or '') .. (vim.bo.readonly and ' [RO]' or '')
end

-- wrap a section's text in its highlight group as a padded run.
-- empty sections collapse to nothing so they leave no stray gap
local function block(text, group)
  if text == '' then
    return ''
  end
  return string.format('%%#%s# %s ', group, text)
end

-- display width of a statusline-formatted string: strip highlight
-- escapes (%#Name#) and structural items (%<, %=, %*) so only the
-- visible glyphs are counted. used to budget the filename section
local function sl_width(s)
  s = s:gsub('%%#[^#]*#', ''):gsub('%%[<=*]', ''):gsub('%%%%', '%%')
  return vim.fn.strdisplaywidth(s)
end

-- path to the current file relative to its git/project root, so long
-- worktree directory names don't dominate the statusline. falls back to
-- a ~-relative path outside a repo. the resolved root is cached per
-- buffer (false = looked up, none found) so redraws don't walk the
-- filesystem on every event
local function project_relative_path()
  local full = vim.fn.expand '%:p'
  if full == '' then
    return vim.fn.expand '%:t'
  end
  local root = vim.b._sl_git_root
  if root == nil then
    root = vim.fs.root(full, '.git') or false
    vim.b._sl_git_root = root
  end
  if root and full:sub(1, #root + 1) == root .. '/' then
    return full:sub(#root + 2)
  end
  local home = vim.uv.os_homedir()
  if home and full:sub(1, #home) == home then
    return '~' .. full:sub(#home + 1)
  end
  return full
end

-- colour the informational middle sections from groups the active theme
-- already defines, so all 14 hand-crafted themes and the generated ones
-- stay consistent. the git branch keeps a solid coloured background
-- block; diff counts and diagnostics are foreground only, so they sit on
-- the neutral middle and follow terminal transparency automatically
-- (StatusLine.bg == Devinfo.bg in every theme). filename and fileinfo
-- keep their neutral defaults
local function derive_statusline_hl()
  local function get(name)
    return vim.api.nvim_get_hl(0, { name = name, link = false })
  end
  local function fg(name)
    return get(name).fg
  end

  -- branch block: theme accent background, dark text. the mode block's fg
  -- is bg_primary in every theme and survives transparency stripping
  local accent = fg 'Type' or fg 'Function'
  local dark = get('MiniStatuslineModeNormal').fg
  vim.api.nvim_set_hl(0, 'MiniStatuslineBranch', { fg = dark, bg = accent, bold = true })

  -- diff / diagnostics: foreground only (no bg), blend with the middle
  local groups = {
    MiniStatuslineDiffAdd = fg 'GitSignsAdd' or fg 'DiffAdd',
    MiniStatuslineDiffChange = fg 'GitSignsChange' or fg 'DiffChange',
    MiniStatuslineDiffDelete = fg 'GitSignsDelete' or fg 'DiffDelete',
    MiniStatuslineDiagError = fg 'DiagnosticError',
    MiniStatuslineDiagWarn = fg 'DiagnosticWarn',
    MiniStatuslineDiagInfo = fg 'DiagnosticInfo',
    MiniStatuslineDiagHint = fg 'DiagnosticHint',
    MiniStatuslineTestFail = fg 'NeotestFailed' or fg 'DiagnosticError',
  }
  for name, colour in pairs(groups) do
    vim.api.nvim_set_hl(0, name, { fg = colour })
  end
end

function M.setup()
  local statusline = require 'mini.statusline'

  statusline.setup {
    use_icons = vim.g.have_nerd_font,
    content = {
      -- mirrors the default active content plus a macro recording
      -- indicator. cmdheight=0 and ui2 swallow the native
      -- "recording @a" message, so surface the register here
      active = function()
        local mode, mode_hl = statusline.section_mode { trunc_width = 120 }
        local macro = vim.fn.reg_recording()
        local git = statusline.section_git { trunc_width = 40 }
        local diff = statusline.section_diff { trunc_width = 75 }
        local diagnostics = statusline.section_diagnostics { trunc_width = 75 }
        local fileinfo = statusline.section_fileinfo { trunc_width = 120 }
        local location = statusline.section_location { trunc_width = 75 }
        local search = statusline.section_searchcount { trunc_width = 75 }

        -- diff and diagnostics share the neutral middle section; only the
        -- counts themselves are colour-coded
        local changes = table.concat(
          vim.tbl_filter(function(s)
            return s ~= ''
          end, { diff, diagnostics }),
          ' '
        )

        local loc = table.concat(
          vim.tbl_filter(function(s)
            return s ~= ''
          end, { search, location }),
          ' '
        )

        local left = table.concat {
          block(mode, mode_hl),
          macro ~= '' and block('● @' .. macro, 'MiniStatuslineModeReplace') or '',
          block(git, 'MiniStatuslineBranch'),
          block(changes, 'MiniStatuslineDevinfo'),
        }
        local right = table.concat {
          block(fileinfo, 'MiniStatuslineFileinfo'),
          block(loc, mode_hl),
        }

        -- adaptive filename: relative to the project root, shown in full
        -- while it fits. only when the rest of the line leaves no room do
        -- parent dirs collapse to initials (the filename is kept intact),
        -- which avoids mini's mid-word left-cut on deep paths. the budget
        -- is the window width (laststatus=2) minus every other section,
        -- this block's padding, and the modified/readonly flags
        local filename
        if vim.bo.buftype == 'terminal' then
          filename = '%t'
        else
          local fl = flags()
          local path = project_relative_path()
          local width = vim.api.nvim_win_get_width(vim.g.statusline_winid or 0)
          local budget = math.max(12, width - sl_width(left) - sl_width(right) - sl_width(fl) - 2)
          if vim.fn.strdisplaywidth(path) > budget then
            path = vim.fn.pathshorten(path)
          end
          filename = path .. fl
        end

        -- pin the neutral filename group right before %= so the expanding
        -- gap always fills neutral. without it, an empty filename section
        -- (qf, [No Name], terminal) leaves the previous block's highlight
        -- (the orange mode colour) active at %=, flooding the whole bar
        return left .. '%<' .. block(filename, 'MiniStatuslineFilename') .. '%#MiniStatuslineFilename#%=' .. right
      end,
    },
  }

  -- re-derive the section colours on every theme change so all themes
  -- (including generated ones) stay consistent
  vim.api.nvim_create_autocmd('ColorScheme', {
    group = vim.api.nvim_create_augroup('mini-statusline-colours', { clear = true }),
    callback = derive_statusline_hl,
  })
  derive_statusline_hl()

  -- redraw statusline on record start/stop so the indicator updates
  -- immediately rather than on the next unrelated event
  vim.api.nvim_create_autocmd({ 'RecordingEnter', 'RecordingLeave' }, {
    group = vim.api.nvim_create_augroup('mini-statusline-macro', { clear = true }),
    callback = function()
      vim.cmd.redrawstatus()
    end,
  })

  ---@diagnostic disable-next-line: duplicate-set-field
  statusline.section_location = function()
    local loc = '%2l:%-2v'
    if vim.t.zoomed then
      loc = loc .. ' Z'
    end
    return loc
  end

  -- project-relative filename (git root when inside a repo, else
  -- ~-relative). used for inactive windows; the active line builds its
  -- own adaptively-shortened path. see project_relative_path above
  ---@diagnostic disable-next-line: duplicate-set-field, unused-local
  statusline.section_filename = function(args)
    if vim.bo.buftype == 'terminal' then
      return '%t'
    end
    return project_relative_path() .. flags()
  end

  -- compact diff (+N green, ~N yellow, -N red), text coloured inline so the
  -- counts read by meaning regardless of statusline style
  ---@diagnostic disable-next-line: duplicate-set-field
  statusline.section_diff = function(args)
    if statusline.is_truncated(args.trunc_width) then
      return ''
    end
    local s = vim.b.gitsigns_status_dict
    if not s then
      return ''
    end
    local parts = {}
    if (s.added or 0) > 0 then
      table.insert(parts, '%#MiniStatuslineDiffAdd#+' .. s.added)
    end
    if (s.changed or 0) > 0 then
      table.insert(parts, '%#MiniStatuslineDiffChange#~' .. s.changed)
    end
    if (s.removed or 0) > 0 then
      table.insert(parts, '%#MiniStatuslineDiffDelete#-' .. s.removed)
    end
    if #parts == 0 then
      return ''
    end
    return table.concat(parts, ' ') .. '%#MiniStatuslineDevinfo#'
  end

  -- per-severity diagnostic counts (E/W/I/H), each coloured inline
  local diag_specs = {
    { vim.diagnostic.severity.ERROR, 'MiniStatuslineDiagError', 'E' },
    { vim.diagnostic.severity.WARN, 'MiniStatuslineDiagWarn', 'W' },
    { vim.diagnostic.severity.INFO, 'MiniStatuslineDiagInfo', 'I' },
    { vim.diagnostic.severity.HINT, 'MiniStatuslineDiagHint', 'H' },
  }
  ---@diagnostic disable-next-line: duplicate-set-field
  statusline.section_diagnostics = function(args)
    if statusline.is_truncated(args.trunc_width) or vim.diagnostic.count == nil then
      return ''
    end
    local counts = vim.diagnostic.count(0)
    -- neotest publishes failed tests into its own namespace as real ERROR
    -- diagnostics. subtract them from E/W/I/H and give them a ✗ of their own,
    -- so a red test never reads as a file that doesn't compile
    local tests = vim.diagnostic.count(0, { namespace = neotest_ns })
    local parts = {}
    for _, spec in ipairs(diag_specs) do
      local n = (counts[spec[1]] or 0) - (tests[spec[1]] or 0)
      if n > 0 then
        table.insert(parts, string.format('%%#%s#%s%d', spec[2], spec[3], n))
      end
    end
    local failed = 0
    for _, n in pairs(tests) do
      failed = failed + n
    end
    if failed > 0 then
      table.insert(parts, string.format('%%#MiniStatuslineTestFail#✗%d', failed))
    end
    if #parts == 0 then
      return ''
    end
    return table.concat(parts, ' ') .. '%#MiniStatuslineDevinfo#'
  end

  -- deliberately disabled: the LSP-client section is stubbed to empty so it
  -- never renders (diagnostics already convey LSP state)
  ---@diagnostic disable-next-line: duplicate-set-field
  statusline.section_lsp = function()
    return ''
  end

  -- friendlier display names for filetypes whose short code reads poorly
  -- in the statusline. the icon is still looked up by the real filetype
  local ft_display = { cs = 'csharp' }

  -- file info with the filetype icon tinted by its mini.icons highlight
  -- group (e.g. C# green), matching how the buffer and render-markdown
  -- colour language glyphs. only the glyph is coloured; the filetype,
  -- encoding and size stay neutral. mirrors mini's default format
  ---@diagnostic disable-next-line: duplicate-set-field
  statusline.section_fileinfo = function(args)
    -- differ diff buffers carry a private `differdiff` &filetype (so foreign
    -- `FileType <lang>` consumers, e.g. lsp, don't attach to a throwaway differ://
    -- buffer); the real source filetype is stashed in b:differ_filetype. surface
    -- that so the language and its icon still show while diffing. read the var, not
    -- a require('differ...'), which would force the lazy cmd-loaded plugin to load
    local differ_ft = vim.b.differ_filetype
    local ft = (type(differ_ft) == 'string' and differ_ft ~= '') and differ_ft or vim.bo.filetype
    if ft == '' then
      return ''
    end
    local label = ft_display[ft] or ft
    -- colour the glyph via its icon highlight group, then reset to the
    -- neutral fileinfo group for the trailing space and the rest
    local icon = ''
    if vim.g.have_nerd_font and _G.MiniIcons ~= nil then
      local glyph, hl = MiniIcons.get('filetype', ft)
      if glyph and glyph ~= '' then
        icon = string.format('%%#%s#%s%%#MiniStatuslineFileinfo# ', hl, glyph)
      end
    end
    if statusline.is_truncated(args.trunc_width) or vim.bo.buftype ~= '' then
      return icon .. label
    end
    -- encoding and line-ending are shown only when they deviate from the
    -- utf-8/unix default, so normal files stay clean and the unusual
    -- cases (CRLF, non-utf-8) surface exactly when they matter
    local parts = { label }
    local encoding = vim.bo.fileencoding ~= '' and vim.bo.fileencoding or vim.o.encoding
    if encoding ~= '' and encoding ~= 'utf-8' then
      table.insert(parts, encoding)
    end
    local format = vim.bo.fileformat
    if format ~= '' and format ~= 'unix' then
      table.insert(parts, '[' .. format .. ']')
    end
    local bytes = math.max(vim.fn.line2byte(vim.fn.line '$' + 1) - 1, 0)
    if bytes < 1024 then
      table.insert(parts, string.format('%dB', bytes))
    elseif bytes < 1048576 then
      table.insert(parts, string.format('%.2fKiB', bytes / 1024))
    else
      table.insert(parts, string.format('%.2fMiB', bytes / 1048576))
    end
    return icon .. table.concat(parts, ' ')
  end

  -- truncate branch name to ticket ID (e.g. "feature/ACME-123-some-desc" -> "ACME-123")
  ---@diagnostic disable-next-line: duplicate-set-field
  statusline.section_git = function(args)
    if statusline.is_truncated(args.trunc_width) then
      return ''
    end
    local head = vim.b.gitsigns_head or ''
    if head == '' then
      return ''
    end
    -- extract ticket ID pattern (e.g. ACME-123, JIRA-456)
    local ticket = head:match '[A-Z]+-[0-9]+'
    local branch = ticket or head
    local icon = vim.g.have_nerd_font and (MiniIcons.get('os', 'git') .. ' ') or 'Git: '
    return icon .. branch
  end
end

return M
