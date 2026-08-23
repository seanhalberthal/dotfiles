-- Telescope fuzzy finder configuration

return {
  {
    'nvim-telescope/telescope.nvim',
    event = 'VimEnter',
    dependencies = {
      'nvim-lua/plenary.nvim',
      {
        'nvim-telescope/telescope-fzf-native.nvim',
        build = 'make',
        cond = function()
          return vim.fn.executable 'make' == 1
        end,
      },
      'nvim-telescope/telescope-ui-select.nvim',
      { 'nvim-tree/nvim-web-devicons', enabled = vim.g.have_nerd_font },
    },
    config = function()
      -- helper to format path as parent/parent/filename (2 dirs up)
      local function short_path(path)
        local tail = require('telescope.utils').path_tail(path)
        local parent = vim.fn.fnamemodify(path, ':h:t')
        local grandparent = vim.fn.fnamemodify(path, ':h:h:t')
        if grandparent == '.' or grandparent == '' then
          if parent == '.' or parent == '' then
            return tail
          end
          return parent .. '/' .. tail
        end
        return grandparent .. '/' .. parent .. '/' .. tail
      end

      local actions = require 'telescope.actions'

      -- when a picker is launched from the quickfix/loclist window, telescope
      -- opens the selection in that window by default, replacing the list with
      -- the file. route into a real editing window instead: prefer the previous
      -- window, else the first normal (buftype='') window in the tabpage. return
      -- 0 (telescope's default = current window) for the common, non-qf case
      local function get_selection_window(picker)
        local origin = picker and picker.original_win_id
        if not origin or not vim.api.nvim_win_is_valid(origin) then
          return 0
        end
        if vim.bo[vim.api.nvim_win_get_buf(origin)].buftype ~= 'quickfix' then
          return 0
        end
        local prev = vim.fn.win_getid(vim.fn.winnr '#')
        if prev ~= 0 and prev ~= origin and vim.api.nvim_win_is_valid(prev) and vim.bo[vim.api.nvim_win_get_buf(prev)].buftype == '' then
          return prev
        end
        for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
          if win ~= origin and vim.bo[vim.api.nvim_win_get_buf(win)].buftype == '' then
            return win
          end
        end
        -- qf is the only window: open a fresh split above it to hold the file
        -- so the list survives. telescope edits the selection into this window,
        -- abandoning its empty [No Name] buffer
        vim.cmd 'aboveleft new'
        return vim.api.nvim_get_current_win()
      end

      require('telescope').setup {
        defaults = {
          get_selection_window = get_selection_window,
          -- results show full relative path (default behaviour)
          path_display = { 'filename_first' },
          file_ignore_patterns = {
            '%.git/',
            '%.DS_Store',
          },
          mappings = {
            i = {
              ['<C-j>'] = actions.move_selection_next,
              ['<C-k>'] = actions.move_selection_previous,
              ['<C-f>'] = function(bufnr)
                for _ = 1, 10 do
                  actions.move_selection_next(bufnr)
                end
              end,
              ['<C-b>'] = function(bufnr)
                for _ = 1, 10 do
                  actions.move_selection_previous(bufnr)
                end
              end,
              ['<M-BS>'] = function()
                vim.api.nvim_input '<C-w>'
              end,
              ['<C-l>'] = function(prompt_bufnr)
                require('telescope.actions.state').get_current_picker(prompt_bufnr):set_prompt ''
              end,
              ['<C-g>'] = function(prompt_bufnr)
                actions.send_to_loclist(prompt_bufnr)
                actions.open_loclist(prompt_bufnr)
              end,
              ['<M-g>'] = function(prompt_bufnr)
                actions.send_selected_to_loclist(prompt_bufnr)
                actions.open_loclist(prompt_bufnr)
              end,
            },
          },
        },
        pickers = {
          find_files = {
            hidden = true,
          },
          -- --hidden makes rg descend into .git; file_ignore_patterns only
          -- discards those results afterwards, so exclude the dir up front
          live_grep = {
            additional_args = { '--hidden', '--glob=!.git/' },
          },
          grep_string = {
            additional_args = { '--hidden', '--glob=!.git/' },
          },
        },
        extensions = {
          ['ui-select'] = {
            require('telescope.themes').get_dropdown {
              width = 0.9,
            },
          },
        },
      }

      -- override previewer to show short path in title
      local conf = require('telescope.config').values

      local original_file_previewer = conf.file_previewer
      conf.file_previewer = function(opts)
        opts = opts or {}
        local previewer = original_file_previewer(opts)
        local original_title = previewer.title
        previewer.title = function(self, entry)
          if entry and entry.path then
            return short_path(entry.path)
          elseif entry and entry.filename then
            return short_path(entry.filename)
          end
          return original_title and original_title(self, entry) or 'Preview'
        end
        return previewer
      end

      local original_grep_previewer = conf.grep_previewer
      conf.grep_previewer = function(opts)
        opts = opts or {}
        local previewer = original_grep_previewer(opts)
        local original_title = previewer.title
        previewer.title = function(self, entry)
          if entry and entry.path then
            return short_path(entry.path)
          elseif entry and entry.filename then
            return short_path(entry.filename)
          end
          return original_title and original_title(self, entry) or 'Preview'
        end
        return previewer
      end

      pcall(require('telescope').load_extension, 'fzf')
      pcall(require('telescope').load_extension, 'ui-select')
      pcall(require('telescope').load_extension, 'harpoon')

      local builtin = require 'telescope.builtin'
      vim.keymap.set('n', '<leader>sh', builtin.help_tags, { desc = 'Search [H]elp' })
      vim.keymap.set('n', '<leader>sk', builtin.keymaps, { desc = 'Search [K]eymaps' })
      vim.keymap.set('n', '<leader>sf', builtin.find_files, { desc = 'Search [F]iles' })
      vim.keymap.set('n', '<leader>sF', function()
        -- live regex find: re-run `fd --regex <prompt>` on every keystroke.
        -- the fuzzy sorter would re-filter rg/fd output and reject regex
        -- metacharacters like `.*`, so use highlighter_only to preserve order
        local pickers = require 'telescope.pickers'
        local finders = require 'telescope.finders'
        local make_entry = require 'telescope.make_entry'
        local sorters = require 'telescope.sorters'
        local values = require('telescope.config').values
        pickers
          .new({}, {
            prompt_title = 'Find Files (regex)',
            finder = finders.new_job(function(prompt)
              if not prompt or prompt == '' then
                return nil
              end
              return { 'fd', '--type', 'f', '--hidden', '--exclude', '.git', '--regex', prompt }
            end, make_entry.gen_from_file {}, nil, vim.uv.cwd()),
            sorter = sorters.highlighter_only {},
            previewer = values.file_previewer {},
          })
          :find()
      end, { desc = 'Search [F]iles (regex)' })
      vim.keymap.set('n', '<leader>ss', builtin.builtin, { desc = 'Telescope built-in[S]' })
      vim.keymap.set('n', '<leader>sw', builtin.grep_string, { desc = 'Search [W]ord' })
      vim.keymap.set('n', '<leader>sg', builtin.live_grep, { desc = 'Search [G]rep' })
      vim.keymap.set('n', '<leader>sG', function()
        -- call-site additional_args replaces the picker default outright
        -- (shallow tbl_extend), so the .git exclusion has to be repeated here
        builtin.live_grep { additional_args = { '--hidden', '--glob=!.git/', '--fixed-strings' } }
      end, { desc = 'Search [G]rep (literal)' })
      vim.keymap.set('n', '<leader>sm', function()
        -- same file set as the <leader>xm / <leader>lm scans (features/ticket.lua):
        -- staged or unstaged changes vs HEAD plus untracked files. a plain
        -- file picker rather than builtin.git_status, so no status letters or
        -- <Tab> staging; in exchange the three always agree on "modified"
        local files = require('custom.features.ticket').modified_files()
        if not files then
          return
        end
        if #files == 0 then
          vim.notify('No modified files', vim.log.levels.INFO)
          return
        end
        local pickers = require 'telescope.pickers'
        local finders = require 'telescope.finders'
        local make_entry = require 'telescope.make_entry'
        local values = require('telescope.config').values
        pickers
          .new({}, {
            prompt_title = 'Git Modified Files',
            finder = finders.new_table { results = files, entry_maker = make_entry.gen_from_file {} },
            sorter = values.file_sorter {},
            previewer = values.file_previewer {},
          })
          :find()
      end, { desc = 'Search git [M]odified files' })
      vim.keymap.set('n', '<leader>sd', builtin.diagnostics, { desc = 'Search [D]iagnostics' })
      vim.keymap.set('n', '<leader>sr', function()
        -- resume re-uses cached entries from the previous picker; we want a
        -- fresh run against the current state of the workspace, so trigger a
        -- finder refresh once the resumed picker is ready
        vim.api.nvim_create_autocmd('User', {
          pattern = 'TelescopeResumePost',
          once = true,
          callback = function()
            vim.schedule(function()
              local ok_state, action_state = pcall(require, 'telescope.actions.state')
              if not ok_state then
                return
              end
              local picker = action_state.get_current_picker(vim.api.nvim_get_current_buf())
              if picker and picker.finder then
                picker:refresh(nil, { reset_prompt = false })
              end
            end)
          end,
        })
        builtin.resume()
      end, { desc = 'Search [R]esume (fresh)' })
      vim.keymap.set('n', '<leader>s.', builtin.oldfiles, { desc = 'Recent files [.]' })
      vim.keymap.set('n', '<leader><leader>', builtin.buffers, { desc = 'Buffers' })

      -- fuzzy search in current buffer
      vim.keymap.set('n', '<leader>s/', function()
        builtin.current_buffer_fuzzy_find(require('telescope.themes').get_dropdown {
          winblend = 10,
          previewer = false,
        })
      end, { desc = 'Fuzzy search buffer' })

      -- search nvim config files
      vim.keymap.set('n', '<leader>sn', function()
        builtin.find_files { cwd = vim.fn.stdpath 'config' }
      end, { desc = 'Search [N]eovim files' })
    end,
  },
}
