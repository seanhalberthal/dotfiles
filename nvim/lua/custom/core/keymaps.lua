-- core keymaps: basic editing tweaks plus delegation to focused modules.
-- plugin-specific keymaps are defined with their plugins

local M = {}

function M.setup()
  -- clear search highlight
  vim.keymap.set('n', '<Esc>', '<cmd>nohlsearch<CR>')

  -- registers: only yanks sync to the system clipboard (see autocmds.lua), so
  -- d/c/x never clobber it. "0 (the yank register) is never touched by deletes,
  -- so <leader>v pastes the last yank no matter what was deleted since
  vim.keymap.set({ 'n', 'x' }, '<leader>v', '"0p', { desc = 'Paste last yank' })
  vim.keymap.set({ 'n', 'x' }, '<leader>V', '"0P', { desc = 'Paste last yank (above)' })

  -- smart i/a on empty lines: reindent via cc (which respects indentexpr)
  -- rather than dropping the cursor at column 0. uses the black hole register
  -- so the empty line contents don't clobber the unnamed register
  local function smart_insert(fallback)
    return function()
      return #vim.api.nvim_get_current_line() == 0 and '"_cc' or fallback
    end
  end
  vim.keymap.set('n', 'i', smart_insert 'i', { expr = true, desc = 'Insert (smart indent on empty line)' })
  vim.keymap.set('n', 'a', smart_insert 'a', { expr = true, desc = 'Append (smart indent on empty line)' })

  -- line navigation: m/M for beginning/end of line, gm for marks
  vim.keymap.set({ 'n', 'v', 'o' }, 'm', '^', { desc = 'First non-blank character' })
  vim.keymap.set({ 'n', 'v', 'o' }, 'M', '$', { desc = 'End of line' })
  vim.keymap.set('n', 'gm', 'm', { desc = 'Set mark' })

  -- insert space at cursor without leaving normal mode
  vim.keymap.set('n', '<leader>i', 'i<Space><Esc>', { desc = '[I]nsert space' })

  -- terminal mode escape
  vim.keymap.set('t', '<Esc><Esc>', '<C-\\><C-n>', { desc = 'Exit terminal mode' })

  -- gx: open URL under cursor, stripping wrapper chars (<>, (), [], quotes)
  -- that leak through when the TS highlighter isn't active or the fallback
  -- <cfile> path is used (e.g. markdown autolinks <https://...> in buffers
  -- without markdown_inline parsed)
  vim.keymap.set('n', 'gx', function()
    local urls = require('vim.ui')._get_urls()
    for _, url in ipairs(urls) do
      local cleaned = url:gsub('^[%<%(%[%"\']+', ''):gsub('[%>%)%]%"\']+$', '')
      vim.ui.open(cleaned)
    end
  end, { desc = 'Open URL/file under cursor (strip wrappers)' })

  -- copy buffer path to clipboard
  vim.keymap.set('n', '<leader>by', function()
    local path = vim.fn.expand '%:p'
    vim.fn.setreg('+', path)
    vim.notify(path, vim.log.levels.INFO)
  end, { desc = '[Y]ank file path' })

  -- file explorer
  vim.keymap.set('n', '<leader>e', ':Neotree toggle<CR>', { desc = 'File [E]xplorer' })

  -- git UI
  vim.keymap.set('n', '<leader>g', '<cmd>LazyGit<CR>', { desc = 'Lazy[G]it' })

  -- undo tree
  vim.keymap.set('n', '<leader>u', function()
    vim.cmd 'packadd nvim.undotree'
    require('undotree').open { command = '60vnew' }
  end, { desc = '[U]ndo tree' })

  -- focused modules own their own keymaps
  require('custom.core.folding').setup()
  require('custom.features.lists').setup()
  require('custom.features.diag-scan').setup()
  require('custom.core.windows').setup()
  require('custom.core.macos-nav').setup()
  require('custom.core.refresh').setup()
  require('custom.core.spellcheck').setup()
  require('custom.features.build').setup()
  require('custom.features.binary-view').setup()
  require('custom.features.go').setup()
  require('custom.features.snippets').setup()
end

return M
