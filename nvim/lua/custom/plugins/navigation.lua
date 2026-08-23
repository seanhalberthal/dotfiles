-- file navigation: Harpoon2 for quick marks, Oil for filesystem-as-buffer

-- close oil, restoring the dashboard if oil was opened from it. oil.close()
-- restores `oil_original_buffer`, but the snacks dashboard is bufhidden=wipe,
-- so launching oil over it wipes it; oil then falls back to a blank `enew`
-- buffer. detect that empty landing buffer and re-render the dashboard,
-- matching snacks' own "empty buffer on startup" behaviour
local function oil_close()
  require('oil').close()
  local buf = vim.api.nvim_get_current_buf()
  local empty = vim.api.nvim_buf_get_name(buf) == ''
    and vim.bo[buf].buftype == ''
    and vim.api.nvim_buf_line_count(buf) == 1
    and vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1] == ''
  if empty and Snacks and Snacks.dashboard then
    -- open() merges partial opts with the configured dashboard defaults, so the
    -- "missing sections/formats" check on snacks.dashboard.Opts is a false positive
    ---@diagnostic disable-next-line: missing-fields
    Snacks.dashboard.open { win = vim.api.nvim_get_current_win() }
  end
end

-- re-assert oil's conceal window options whenever an oil buffer becomes visible.
-- oil hides its per-line entry IDs (the `/006 ` prefix) with a buffer-local
-- `oilId` syntax match plus the window-local `conceallevel`/`concealcursor` it
-- sets when rendering. because conceal is window-scoped, showing an existing oil
-- buffer in a window that never ran oil's set_win_options (a split, a reused
-- window) leaves conceallevel at 0 and the IDs leak.
--
-- oil's own set_win_options reads `nvim_get_current_win()` from inside an
-- `nvim_buf_call`, which switches the buffer context but NOT the window, so on a
-- fresh open it can apply conceallevel to the wrong window and the IDs leak from
-- the very first render. a synchronous reassert on entry hits the same race. so
-- defer one tick (past oil's render and any competing FileType handlers) and set
-- the option on the resolved oil window explicitly rather than "current window"
vim.api.nvim_create_autocmd({ 'BufWinEnter', 'WinEnter' }, {
  pattern = 'oil://*',
  callback = function()
    local win = vim.api.nvim_get_current_win()
    vim.schedule(function()
      if not vim.api.nvim_win_is_valid(win) then
        return
      end
      local buf = vim.api.nvim_win_get_buf(win)
      if vim.bo[buf].filetype ~= 'oil' then
        return
      end
      vim.api.nvim_set_option_value('conceallevel', 3, { scope = 'local', win = win })
      vim.api.nvim_set_option_value('concealcursor', 'nvic', { scope = 'local', win = win })
    end)
  end,
})

return {
  -- oil: filesystem-as-buffer
  {
    'stevearc/oil.nvim',
    dependencies = { 'nvim-tree/nvim-web-devicons' },
    -- load at startup so oil's directory-hijack autocmd is registered before a
    -- directory buffer (e.g. `nvim ~/.config`) is processed. lazy-loading on the
    -- `-` key would miss command-line directory arguments
    lazy = false,
    keys = {
      { '-', '<cmd>Oil<CR>', desc = 'Oil: Open parent directory' },
    },
    -- opts as a function so vim.g.oil_opts (set in local.lua, which loads before
    -- plugin specs) deep-merges over these defaults, same local-override pattern
    -- as differ.lua. keymaps merge per key, so a local override can add or
    -- replace one binding without restating the rest
    opts = function()
      return vim.tbl_deep_extend('force', {
        default_file_explorer = true,
        columns = { 'icon' },
        -- `sort` names the `notedate` column registered in config below; oil
        -- resolves sort columns lazily at render time, so registration order
        -- against this table doesn't matter
        view_options = { show_hidden = true, sort = require('custom.features.dated-notes').oil_sort },
        keymaps = {
          ['-'] = { mode = 'n', callback = oil_close },
          ['<BS>'] = { 'actions.parent', mode = 'n' },
          ['gi'] = { 'actions.select', mode = 'n' },
          ['go'] = { 'actions.parent', mode = 'n' },
        },
      }, vim.g.oil_opts or {})
    end,
    config = function(_, opts)
      require('oil').setup(opts)
      require('custom.features.dated-notes').setup_oil()
    end,
  },

  -- Harpoon2: quick file navigation
  {
    'ThePrimeagen/harpoon',
    branch = 'harpoon2',
    dependencies = { 'nvim-lua/plenary.nvim' },
    event = 'VeryLazy',
    config = function()
      local harpoon = require 'harpoon'
      harpoon:setup {
        settings = {
          save_on_toggle = true,
          sync_on_ui_close = true,
        },
      }
      harpoon:extend {
        UI_CREATE = function(cx)
          vim.keymap.set('n', 'o', '<CR>', { buffer = cx.bufnr, remap = true, silent = true })
        end,
      }

      -- keymaps
      vim.keymap.set('n', '<leader>ha', function()
        harpoon:list():add()
      end, { desc = '[H]arpoon: [a]dd file' })

      vim.keymap.set('n', '<leader>hl', function()
        harpoon.ui:toggle_quick_menu(harpoon:list())
      end, { desc = '[H]arpoon: [l]ist files' })

      -- quick access to files 1-4 (easier than <leader>h1-4)
      local function select_harpoon_file(index)
        local list = harpoon:list()
        local item = list:get(index)
        if item then
          list:select(index)
        else
          vim.notify('Harpoon: slot ' .. index .. ' is empty', vim.log.levels.INFO)
        end
      end

      vim.keymap.set('n', '<leader>1', function()
        select_harpoon_file(1)
      end, { desc = 'Harpoon: file 1' })

      vim.keymap.set('n', '<leader>2', function()
        select_harpoon_file(2)
      end, { desc = 'Harpoon: file 2' })

      vim.keymap.set('n', '<leader>3', function()
        select_harpoon_file(3)
      end, { desc = 'Harpoon: file 3' })

      vim.keymap.set('n', '<leader>4', function()
        select_harpoon_file(4)
      end, { desc = 'Harpoon: file 4' })

      -- remove current file from harpoon list
      vim.keymap.set('n', '<leader>hd', function()
        harpoon:list():remove()
      end, { desc = '[H]arpoon: [d]elete current file' })

      -- clear all harpoon marks (capital X = harder to accidentally press)
      vim.keymap.set('n', '<leader>hX', function()
        harpoon:list():clear()
      end, { desc = '[H]arpoon: clear all (X marks the spot)' })

      -- Telescope integration for harpoon
      local has_telescope, _ = pcall(require, 'telescope')
      if has_telescope then
        vim.keymap.set('n', '<leader>hs', function()
          require('telescope').extensions.harpoon.marks(require('telescope.themes').get_dropdown {})
        end, { desc = '[H]arpoon: [s]earch in Telescope' })
      end
    end,
  },
}
