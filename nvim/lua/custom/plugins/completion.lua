-- completion configuration (blink.cmp)

return {
  {
    'saghen/blink.cmp',
    event = { 'InsertEnter', 'CmdlineEnter' },
    dependencies = {
      'rafamadriz/friendly-snippets',
      { 'saghen/blink.compat', opts = {} },
      'giuxtaposition/blink-cmp-copilot',
      {
        'L3MON4D3/LuaSnip',
        version = 'v2.*',
        build = 'make install_jsregexp',
        dependencies = { 'rafamadriz/friendly-snippets' },
        keys = {
          {
            '<C-k>',
            function()
              local ls = require 'luasnip'
              if ls.expand_or_jumpable() then
                ls.expand_or_jump()
              end
            end,
            mode = { 'i', 's' },
            desc = 'LuaSnip: Expand or jump to next placeholder',
          },
          {
            '<C-j>',
            function()
              local ls = require 'luasnip'
              if ls.jumpable(-1) then
                ls.jump(-1)
              end
            end,
            mode = { 'i', 's' },
            desc = 'LuaSnip: Jump to previous placeholder',
          },
        },
        config = function()
          require('luasnip.loaders.from_lua').load { paths = '~/.config/nvim/snippets/' }
        end,
      },
    },
    version = '*',
    ---@module 'blink.cmp'
    ---@type blink.cmp.Config
    opts = {
      enabled = function()
        local disabled_filetypes = { ['grug-far'] = true }
        return not disabled_filetypes[vim.bo.filetype]
      end,
      keymap = {
        preset = 'default',
        ['<C-space>'] = { 'show', 'show_documentation', 'hide_documentation' },
        -- cancel rather than hide: auto_insert previews the selected item into
        -- the buffer, and only cancel undoes that, so the typed text survives
        ['<C-e>'] = { 'cancel', 'fallback' },
        ['<CR>'] = { 'select_and_accept', 'fallback' },
        -- Shift+Enter (Ghostty sends ESC+CR = M-CR) inserts a literal newline
        -- without accepting the visible completion item
        ['<M-CR>'] = {
          function(cmp)
            if cmp.is_visible() then
              cmp.cancel()
            end
            vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<CR>', true, false, true), 'n', false)
            return true
          end,
        },
        ['<Tab>'] = {
          function(cmp)
            local ok, suggestion = pcall(require, 'copilot.suggestion')
            if ok and suggestion.is_visible() then
              cmp.hide()
              suggestion.accept()
              return true
            end
            if cmp.snippet_active() then
              return cmp.accept()
            else
              return cmp.select_and_accept()
            end
          end,
          'snippet_forward',
          'fallback',
        },
        ['<S-Tab>'] = { 'snippet_backward', 'fallback' },
        ['<Up>'] = { 'select_prev', 'fallback' },
        ['<Down>'] = { 'select_next', 'fallback' },
        ['<C-p>'] = { 'select_prev', 'fallback' },
        ['<C-n>'] = { 'select_next', 'fallback' },
        ['<C-b>'] = { 'scroll_documentation_up', 'fallback' },
        ['<C-f>'] = { 'scroll_documentation_down', 'fallback' },
        ['<C-j>'] = { 'select_next', 'fallback' },
        ['<C-k>'] = { 'select_prev', 'fallback' },
      },
      appearance = {
        use_nvim_cmp_as_default = true,
        nerd_font_variant = 'mono',
      },
      completion = {
        accept = { auto_brackets = { enabled = true } },
        documentation = { auto_show = true, auto_show_delay_ms = 200 },
        list = {
          selection = { preselect = true, auto_insert = true },
        },
        menu = {
          draw = {
            columns = { { 'kind_icon' }, { 'label', 'label_description', gap = 1 }, { 'source_name' } },
          },
        },
      },
      fuzzy = {
        sorts = {
          'exact',
          'score',
          'sort_text',
          'kind',
          'label',
        },
      },
      sources = {
        default = { 'lazydev', 'lsp', 'path', 'snippets', 'buffer', 'copilot' },
        providers = {
          -- require() paths and plugin module annotations, types served by lazydev
          lazydev = {
            name = 'LazyDev',
            module = 'lazydev.integrations.blink',
            score_offset = 100,
          },
          copilot = {
            name = 'copilot',
            module = 'blink-cmp-copilot',
            async = true,
            score_offset = 100,
          },
          snippets = {
            score_offset = -3,
            -- nvim/snippets is scanned ahead of friendly-snippets, so keeping the
            -- first item for a prefix lets a local json file override one upstream
            -- snippet without taking over the whole filetype
            transform_items = function(_, items)
              local seen, out = {}, {}
              for _, item in ipairs(items) do
                if not seen[item.label] then
                  seen[item.label] = true
                  out[#out + 1] = item
                end
              end
              return out
            end,
          },
          -- short keywords are where buffer words are noisiest: a 3-char query
          -- fuzzy-matches unrelated identifiers and gets preselected
          buffer = { score_offset = -5, min_keyword_length = 4 },
        },
      },
      cmdline = {
        enabled = true,
        keymap = {
          preset = 'inherit',
          ['<CR>'] = {
            function(cmp)
              if cmp.is_visible() then
                return cmp.accept()
              end
            end,
            'fallback',
          },
          ['<Tab>'] = { 'show', 'select_next', 'fallback' },
          ['<S-Tab>'] = { 'select_prev', 'fallback' },
          ['<C-j>'] = { 'select_next', 'fallback' },
          ['<C-k>'] = { 'select_prev', 'fallback' },
          ['<C-space>'] = { 'show' },
        },
        sources = { 'cmdline', 'buffer' },
        completion = {
          menu = {
            auto_show = function()
              return false
            end,
          },
          list = {
            selection = { preselect = true, auto_insert = false },
          },
        },
      },
    },
    opts_extend = { 'sources.default' },
  },
}
