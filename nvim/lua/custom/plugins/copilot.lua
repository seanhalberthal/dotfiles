-- GitHub Copilot configuration (copilot.lua + blink-cmp-copilot)
-- ghost text for inline suggestions, blink.cmp source for menu items.
-- ghost text auto-hides when blink menu is open to avoid visual clutter

return {
  {
    'zbirenbaum/copilot.lua',
    cmd = 'Copilot',
    event = 'InsertEnter',
    opts = {
      -- use the standalone copilot-language-server binary instead of the
      -- bundled Node server. the Node path requires `node` (>= 22) on PATH at
      -- launch; on machines where nvim starts outside an fnm/nvm shell (GUI
      -- app, launcher, bare login shell) that silently yields zero completions.
      -- the binary server auto-downloads from GitHub releases and has no Node
      -- dependency. see lsp/binary.lua in copilot.lua
      server = { type = 'binary' },
      -- force full-document didChange instead of incremental. nvim's incremental
      -- sync (vim/lsp/sync.lua) asserts on a stale line snapshot, so a copilot
      -- changetracking desync crashes the next on_lines: while typing, or when
      -- setqflist re-renders a tracked buffer (:Cfilter, live-diagnostics qf).
      -- full sync never runs compute_diff, so the assert is unreachable. see
      -- neovim/neovim#33224 and the incremental-sync assert family
      -- exit_timeout defaults to false, on which nvim fires an async shutdown,
      -- vim.wait(0), then exits, so a slow server outlives nvim and reparents
      -- to pid 1 still holding its RSS. a number makes the handler wait and
      -- force-stop instead. quitting doesn't reach it: the ExitPre hook in
      -- plugins/lsp.lua stops every client first, so 200 governs runtime
      -- restarts, where an idle copilot answers in ~10ms
      server_opts_overrides = {
        flags = { allow_incremental_sync = false },
        exit_timeout = 200,
      },
      suggestion = {
        enabled = true,
        auto_trigger = true,
        keymap = {
          accept = false, -- full accept handled by Tab in blink.cmp config
          accept_word = '<M-Tab>',
          dismiss = '<C-e>',
        },
      },
      panel = { enabled = false },
      filetypes = {
        markdown = false,
        yaml = true,
        help = false,
        gitcommit = false,
        gitrebase = false,
        TelescopePrompt = false,
        ['grug-far'] = false,
        ['grug-far-help'] = false,
        ['neo-tree'] = false,
        ['neo-tree-popup'] = false,
        DressingInput = false,
        codecompanion = false,
        ['copilot-chat'] = false,
        snacks_input = false,
        snacks_notif = false,
        octo = false,
        hgcommit = false,
        svn = false,
        cvs = false,
      },
      should_attach = function(bufnr, bufname)
        -- preserve default checks: skip unlisted and special buffers (e.g. Telescope prompts)
        if not vim.bo[bufnr].buflisted or vim.bo[bufnr].buftype ~= '' then
          return false
        end
        -- ssh keys/config have no distinguishing filetype, so block by path instead
        local ssh_dir = vim.fn.resolve(vim.fn.expand '~/.ssh') .. '/'
        if bufname:sub(1, #ssh_dir) == ssh_dir then
          return false
        end
        local patterns = { '%.env', 'secret', 'credential', '%.key$', '%.pem$', '%.secrets%.zsh' }
        for _, pat in ipairs(patterns) do
          if bufname:match(pat) then
            return false
          end
        end
        return true
      end,
    },
    config = function(_, opts)
      require('copilot').setup(opts)

      -- hide ghost text when blink menu opens, restore when it closes
      vim.api.nvim_create_autocmd('User', {
        pattern = 'BlinkCmpMenuOpen',
        callback = function()
          vim.b.copilot_suggestion_hidden = true
        end,
      })
      vim.api.nvim_create_autocmd('User', {
        pattern = 'BlinkCmpMenuClose',
        callback = function()
          vim.b.copilot_suggestion_hidden = false
        end,
      })
    end,
  },
}
