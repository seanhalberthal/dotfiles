-- UI plugins: which-key, todo-comments, fidget, noice, cheatsheet.
-- mini.nvim lives in plugins/mini.lua.
-- colourschemes are custom files in nvim/colors/, no plugins needed

return {
  -- file explorer (neo-tree spec lives in custom/plugins/neo-tree.lua)

  -- cheatsheet for keybindings and commands
  {
    'sudormrfbin/cheatsheet.nvim',
    cmd = 'Cheatsheet',
    keys = {
      { '<leader>?', '<cmd>Cheatsheet<CR>', desc = 'Open cheatsheet' },
    },
    dependencies = {
      'nvim-telescope/telescope.nvim',
      'nvim-lua/popup.nvim',
      'nvim-lua/plenary.nvim',
    },
    opts = {
      bundled_cheatsheets = false,
      bundled_plugin_cheatsheets = false,
    },
  },

  -- Which-key for keybinding hints
  -- tiered display: top-level shows category groups only; standalone keys and
  -- context-specific groups are hidden unless the filetype is relevant
  {
    'folke/which-key.nvim',
    lazy = false, -- load immediately to ensure leader preview works reliably
    config = function()
      local wk = require 'which-key'
      local claude_icon = vim.fn.nr2char(0xf06c4) -- nf-md-asterisk, matches the ```claude fence icon

      -- shared Claude icon colour (distinct orange, not DiagnosticWarn yellow);
      -- also used by the ```claude fence glyph in mini.lua
      vim.api.nvim_set_hl(0, 'ClaudeIcon', { fg = '#ff9e64' })
      vim.api.nvim_create_autocmd('ColorScheme', {
        group = vim.api.nvim_create_augroup('claude-icon-hl', { clear = true }),
        callback = function()
          vim.api.nvim_set_hl(0, 'ClaudeIcon', { fg = '#ff9e64' })
        end,
      })

      -- filetype sets for context gating
      local dotnet_fts = { cs = true, fsharp = true, razor = true, xml = true }

      wk.setup {
        delay = 0, -- show immediately for snappy feel
        win = {
          no_overlap = false,
        },
        icons = {
          mappings = vim.g.have_nerd_font,
        },
        spec = {
          -- ── always-visible groups ──
          { '<leader>a', group = '[A]I', icon = { icon = '󰚩 ', color = 'purple' } },
          { '<leader>b', group = '[B]reakpoint / Buffer', icon = { icon = '󰈔 ', color = 'red' } },
          { '<leader>d', group = '[D]iff', icon = { cat = 'filetype', name = 'git' } },
          { '<leader>G', group = '[G]it (Fugitive)', icon = { cat = 'filetype', name = 'git' } },
          { '<leader>H', group = 'Git [H]unk', icon = { cat = 'filetype', name = 'git' } },
          { '<leader>h', group = '[H]arpoon', icon = { icon = '󱡀 ', color = 'blue' } },
          { '<leader>s', group = '[S]earch', icon = { icon = '', color = 'blue' } },
          { '<leader>S', group = '[S]pell', icon = { icon = '󰓆 ', color = 'yellow' } },
          { '<leader>t', group = '[T]est / Toggle', icon = { cat = 'filetype', name = 'neotest-summary' } },
          { '<leader>l', group = '[L]SP', icon = { icon = '', color = 'green' } },
          { '<leader>o', group = '[O]bsidian', icon = { icon = '󱞁 ', color = 'purple' } },
          { '<leader>w', group = '[W]indow', icon = { icon = '', color = 'red' } },

          -- ── always-visible (non-code contexts like Octo, differ) ──
          { '<leader>p', group = '[P]R Review', icon = { cat = 'filetype', name = 'git' } },

          -- ── always-visible (qf/loclist commands work in any buffer) ──
          { '<leader>x', group = 'Diagnostics', icon = { icon = '󱖫 ', color = 'green' } },

          -- ── filetype-gated groups (hidden by default, shown in code files via autocmd) ──
          { '<leader>k', group = 'Musi[K]', icon = { icon = '󰎆 ', color = 'purple' }, hidden = true },
          { '<leader>u', icon = { icon = '󰕌 ', color = 'blue' }, hidden = true },
          { 'gr', group = 'LSP [R]efactor', icon = { icon = '󰅩', color = 'green' }, hidden = true },

          -- ── filetype-gated groups (hidden by default, shown for specific filetypes via autocmd) ──
          { '<leader>c', group = '[C]laude', icon = { icon = claude_icon, hl = 'ClaudeIcon' }, hidden = true },
          { '<leader>m', group = '[M]arkdown', icon = { cat = 'filetype', name = 'markdown' }, hidden = true },
          { '<leader>n', group = '.[N]ET', icon = { cat = 'filetype', name = 'cs' }, hidden = true },
          { '<leader>N', group = '[N]otifications', icon = { icon = '󰈸 ', color = 'yellow' } },

          -- ── always-hidden standalone keys (muscle memory) ──
          { '<leader>1', hidden = true },
          { '<leader>2', hidden = true },
          { '<leader>3', hidden = true },
          { '<leader>4', hidden = true },
          { '<leader>e', hidden = true },
          { '<leader>g', hidden = true },
          { '<leader>i', hidden = true },

          -- ── macOS-style navigation (core/macos-nav.lua), muscle memory, kept out of which-key ──
          { '<M-CR>', hidden = true },
          { '<M-BS>', hidden = true },
          { '<D-BS>', hidden = true },
          { '<M-Right>', hidden = true },
          { '<M-Left>', hidden = true },
          { '<M-f>', hidden = true },
          { '<M-b>', hidden = true },
          { '<Home>', hidden = true },
          { '<End>', hidden = true },

          { '<leader>?', icon = { icon = '', color = 'blue' } },
          { '<leader><leader>', icon = { icon = '', color = 'blue' } },
          { '<leader>z', icon = { icon = '', color = 'red' } },
          -- ── conditionally hidden (shown in code files via autocmd) ──
          { '<leader>q', icon = { icon = '', color = 'green' }, hidden = true },
          { '<leader>Q', icon = { icon = '', color = 'green' }, hidden = true },
          { '<leader>f', hidden = true },
          { '<leader>bb', hidden = true },
          { '<leader>bc', hidden = true },
          { '<leader>bL', hidden = true },
          { '<leader>bl', hidden = true },
        },
      }

      -- show/hide context-specific groups based on current buffer filetype
      local non_code_fts = {
        [''] = true,
        dashboard = true,
        lazy = true,
        mason = true,
        oil = true,
        gitcommit = true,
        gitrebase = true,
        DressingInput = true,
        TelescopePrompt = true,
        ['neotest-summary'] = true,
        ['neotest-output-panel'] = true,
      }

      -- track last visibility state to avoid unnecessary wk.add calls.
      -- each wk.add internally calls Buf.clear() which removes ALL trigger
      -- keymaps from ALL buffers, creating a brief window where which-key
      -- can't intercept <leader>. caching prevents this during rapid buffer
      -- transitions (e.g. differ file navigation)
      local prev_vis = {}

      local function update_filetype_groups()
        -- only update for real file buffers; preserve previous state in
        -- special contexts (differ, telescope, neo-tree, etc.)
        if vim.bo.buftype ~= '' then
          return
        end
        local ft = vim.bo.filetype
        if ft == '' then
          return
        end
        local is_code = not non_code_fts[ft]
        local is_markdown = ft == 'markdown'
        local is_dotnet = dotnet_fts[ft] or false

        if prev_vis.code == is_code and prev_vis.md == is_markdown and prev_vis.dotnet == is_dotnet then
          return
        end
        prev_vis = { code = is_code, md = is_markdown, dotnet = is_dotnet }

        wk.add {
          -- code-file groups (LSP, format, breakpoints)
          { 'gr', group = 'LSP [R]efactor', icon = { icon = '󰅩', color = 'green' }, hidden = not is_code },
          { '<leader>f', hidden = not is_code },
          { '<leader>k', group = 'Musi[K]', icon = { icon = '󰎆 ', color = 'purple' }, hidden = not is_code },
          { '<leader>u', icon = { icon = '󰕌 ', color = 'blue' }, hidden = not is_code },
          { '<leader>q', hidden = not is_code },
          { '<leader>bb', hidden = not is_code },
          { '<leader>bc', hidden = not is_code },
          { '<leader>bL', hidden = not is_code },
          { '<leader>bl', hidden = not is_code },

          -- markdown-only groups
          { '<leader>c', group = '[C]laude', icon = { icon = claude_icon, hl = 'ClaudeIcon' }, hidden = not is_markdown },
          { '<leader>m', group = '[M]arkdown', icon = { cat = 'filetype', name = 'markdown' }, hidden = not is_markdown },

          -- .NET-only group
          { '<leader>n', group = '.[N]ET', icon = { cat = 'filetype', name = 'cs' }, hidden = not is_dotnet },
        }
      end

      vim.api.nvim_create_autocmd({ 'BufEnter', 'FileType' }, {
        group = vim.api.nvim_create_augroup('which-key-filetype', { clear = true }),
        callback = update_filetype_groups,
      })

      vim.schedule(update_filetype_groups)
    end,
  },

  -- todo comments highlighting
  {
    'folke/todo-comments.nvim',
    event = 'VimEnter',
    dependencies = { 'nvim-lua/plenary.nvim' },
    opts = { signs = false },
  },

  -- Fidget: LSP progress spinner and vim.notify backend
  {
    'j-hui/fidget.nvim',
    event = 'VeryLazy',
    opts = {
      progress = {
        -- sonarlint.nvim emits LSP progress on every BufEnter for a supported
        -- filetype, which fidget would otherwise pop up. drop it unconditionally;
        -- the manual `<leader>lm` / `<leader>lS` scan uses a separate
        -- `sonar-scan` client name (see plugins/sonarlint.lua) so its progress
        -- still shows. errors flow via vim.notify, not progress.
        -- Roslyn progress stays gated on `vim.g.roslyn_suppressed` (review only)
        ignore = {
          function(msg)
            if not (msg.lsp_client and msg.lsp_client.name) then
              return false
            end
            local name = msg.lsp_client.name
            if name == 'sonarlint.nvim' then
              return true
            end
            if name == 'roslyn' then
              return vim.g.roslyn_suppressed
            end
            return false
          end,
        },
        display = {
          done_ttl = 2,
          progress_icon = { 'dots' },
          overrides = {
            build = {
              name = false,
            },
          },
        },
      },
      notification = {
        override_vim_notify = true,
        window = {
          winblend = 0,
          align = 'bottom',
        },
      },
    },
    config = function(_, opts)
      opts.notification = opts.notification or {}
      opts.notification.configs = {
        default = vim.tbl_extend('force', require('fidget.notification').default_config, {
          name = false,
          icon = false,
        }),
      }
      require('fidget').setup(opts)

      -- spam filter must install AFTER fidget setup (override_vim_notify wipes
      -- earlier wraps). see features/notify-filter
      require('custom.features.notify-filter').install()

      vim.keymap.set('n', '<leader>Nn', '<cmd>Fidget history<cr>', { desc = 'Notification history' })
    end,
  },

  -- Noice: enhanced LSP hover and signature help rendering
  {
    'folke/noice.nvim',
    event = 'VeryLazy',
    dependencies = { 'MunifTanjim/nui.nvim' },
    opts = {
      cmdline = { enabled = false },
      messages = { enabled = false },
      popupmenu = { enabled = false },
      notify = { enabled = false },
      lsp = {
        hover = { enabled = true, silent = true },
        -- signature help borrows the hover view, whose 120x20 default swamps the
        -- code being typed once a server sends the whole doc body; the call
        -- signature is the part worth seeing, the rest is a scroll away
        signature = {
          enabled = true,
          opts = {
            size = { max_width = 80, max_height = 5 },
            position = { row = 2, col = 0 },
          },
        },
        progress = { enabled = false },
        message = { enabled = false },
        override = {
          ['vim.lsp.util.convert_input_to_markdown_lines'] = true,
          ['vim.lsp.util.stylize_markdown'] = true,
        },
      },
      presets = {
        lsp_doc_border = true,
        bottom_search = true,
        long_message_to_split = true,
      },
    },
  },
}
