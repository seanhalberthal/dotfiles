-- Mini.nvim modules: icons, surround, pairs, hipatterns, bracketed,
-- splitjoin, statusline.
-- loads eagerly so mini.icons custom glyphs are available for the
-- dashboard. all modules are lightweight (keymaps/tables)

return {
  {
    'echasnovski/mini.nvim',
    lazy = false,
    config = function()
      -- icons provider (used by mini.statusline for filetype icons)
      local template_icon = vim.fn.nr2char(0xf05c0) -- nf-md-file_code_outline
      local gopher_icon = vim.fn.nr2char(0xe627) -- nf-seti-go (gopher)
      local yaml_icon = vim.fn.nr2char(0xf013) -- nf-fa-cog
      local csharp_icon = vim.fn.nr2char(0xf031b) -- nf-md-language_csharp (matches `cs` extension)
      local shell_icon = vim.fn.nr2char(0xe691) -- nf-seti-shell (matches mini's `sh` filetype glyph)
      local claude_icon = vim.fn.nr2char(0xf06c4) -- nf-md-asterisk (anthropic-style sunburst)
      local me_icon = vim.fn.nr2char(0xf007) -- nf-fa-user
      require('mini.icons').setup {
        filetype = {
          yaml = { glyph = yaml_icon },
          template = { glyph = template_icon },
          go = { glyph = gopher_icon },
          -- render-markdown looks up code-block languages as filetypes; without
          -- this `csharp` falls back to the generic file glyph instead of the
          -- C# icon that mini.icons ships for the `cs` extension.
          cs = { glyph = csharp_icon, hl = 'MiniIconsGreen' },
          csharp = { glyph = csharp_icon, hl = 'MiniIconsGreen' },
          -- transcript speaker fences (```claude / ```me) in vault notes.
          -- render-markdown resolves the fence word through vim.filetype.match
          -- before mini: 'claude' matches nothing so keys straight through, but
          -- 'me' resolves to nroff (`.me` groff macros), so the `me` speaker
          -- glyph is pinned on nroff instead
          claude = { glyph = claude_icon, hl = 'ClaudeIcon' }, -- ClaudeIcon defined in plugins/ui.lua
          nroff = { glyph = me_icon, hl = 'MiniIconsBlue' },
        },
        os = {
          git = { glyph = '' }, -- nf-oct-git_branch
        },
        extension = {
          template = { glyph = template_icon },
          go = { glyph = gopher_icon },
          yml = { glyph = yaml_icon },
          yaml = { glyph = yaml_icon },
          -- mini.icons has no built-in `extension` entry for sh/bash/zsh; it
          -- resolves them through vim.filetype.match(), which returns nil for
          -- these function-detected extensions during the dashboard's first
          -- paint at startup. mini then caches the generic glyph for the
          -- session. pin explicit extension glyphs so resolution never depends
          -- on filetype-match timing (hl mirrors mini's own routing: sh/bash
          -- grey, zsh green)
          sh = { glyph = shell_icon, hl = 'MiniIconsGrey' },
          bash = { glyph = shell_icon, hl = 'MiniIconsGrey' },
          zsh = { glyph = shell_icon, hl = 'MiniIconsGreen' },
        },
      }

      -- add/delete/replace surroundings (brackets, quotes, etc.)
      -- uses 'gs' prefix to avoid delay on native 's' (substitute char)
      require('mini.surround').setup {
        mappings = {
          add = 'gsa',
          delete = 'gsd',
          find = 'gsf',
          find_left = 'gsF',
          highlight = 'gsh',
          replace = 'gsr',
          update_n_lines = 'gsn',
        },
      }

      -- auto-close brackets, quotes, etc. (replaces nvim-autopairs)
      require('mini.pairs').setup()

      -- highlight hex colour codes inline
      require('mini.hipatterns').setup {
        highlighters = {
          hex_color = require('mini.hipatterns').gen_highlighter.hex_color(),
        },
      }

      -- extended ]/[ navigation; disable suffixes that conflict with other plugins
      require('mini.bracketed').setup {
        comment = { suffix = '' }, -- ]c/[c reserved for gitsigns (git changes)
        file = { suffix = 'f' }, -- differ overrides ]f/[f when open; features/dated-notes shadows it on dated notes
        treesitter = { suffix = '' }, -- ]t/[t reserved for neotest (failed tests)
        quickfix = { suffix = '' }, -- ]q/[q wrapped in custom.features.lists (empty-list notify + cursor-relative idx)
        location = { suffix = '' }, -- ]l/[l wrapped in custom.features.lists (empty-list notify + cursor-relative idx)
      }

      -- ]f/[f walk DD-MM-YYYY note directories by date rather than lexically
      require('custom.features.dated-notes').setup_bracketed()

      -- redirect ]f/[f from neo-tree to the first normal editing window
      vim.api.nvim_create_autocmd('FileType', {
        pattern = 'neo-tree',
        callback = function(ev)
          for key, dir in pairs { [']f'] = 'forward', ['[f'] = 'backward' } do
            vim.keymap.set('n', key, function()
              for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
                if vim.bo[vim.api.nvim_win_get_buf(win)].buftype == '' then
                  vim.api.nvim_set_current_win(win)
                  MiniBracketed.file(dir)
                  return
                end
              end
            end, { buffer = ev.buf })
          end
        end,
      })

      -- split/join code constructs (gS to split, gJ to join)
      require('mini.splitjoin').setup()

      -- bespoke statusline content + section overrides live in features/
      require('custom.features.statusline').setup()
    end,
  },
}
