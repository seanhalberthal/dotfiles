-- treesitter: syntax highlighting, textobjects, indent detection

return {
  -- treesitter for syntax highlighting
  {
    'nvim-treesitter/nvim-treesitter',
    branch = 'main',
    lazy = false, -- treesitter doesn't support lazy loading
    build = ':TSUpdate',
    config = function()
      local parsers = {
        'astro',
        'bash',
        'c',
        'c_sharp',
        'cpp',
        'css',
        'diff',
        'dockerfile',
        'go',
        'html',
        'http',
        'javascript',
        'jsdoc',
        'json',
        'json5',
        'make',
        'objc',
        'python',
        -- lua, luadoc, vim, vimdoc, query, markdown, markdown_inline are bundled
        -- with nvim 0.11+; let nvim manage them to avoid query/parser mismatches
        'swift',
        'tsx',
        'typescript',
        'xml',
        'yaml',
        'zig',
        'awk',
        'toml',
        'razor',
        -- injection-only: go's injections.scm pulls regex into
        -- regexp.MustCompile args. printf is deliberately absent from this
        -- list: that grammar is c-shaped, and go's %t and %w are c length
        -- modifiers rather than conversions, so the parser reads them as
        -- incomplete specifiers and runs the node on to the next conversion
        -- character, swallowing the text in between
        'regex',
      }

      -- purge stale/bundled parsers before installing (ABI-mismatch guard)
      require('custom.features.treesitter-parsers').purge_if_updated()

      -- the go grammar hardcodes new/make's first argument as a type, so go
      -- 1.26's new(expr) is a syntax error to the parser. the errors cascade:
      -- past the first few the file collapses into ERROR nodes, taking
      -- highlighting, folds and neotest's test discovery with it. this is the
      -- open upstream pr for it (tree-sitter-go#193), one commit on top of the
      -- revision nvim-treesitter already pins; drop the entry once it merges.
      -- it costs `new[i]` on a variable shadowing the builtin, which the
      -- grammar mis-parses in the other direction (tree-sitter-go#189)
      require('custom.features.treesitter-parsers').sync_pins {
        go = {
          -- the commit lives on a fork, but it is the head of an open pr, so
          -- upstream holds a ref to it and serves it too; fetching from there
          -- keeps the pin working if the fork is ever deleted or renamed
          url = 'https://github.com/tree-sitter/tree-sitter-go',
          revision = '5a6af13a0a5b45bc76cac289c783b315b2b74e13',
        },
      }

      -- install any parsers from the list that aren't already on disk, or whose
      -- highlights query file isn't on runtimepath (a stray/legacy parser binary
      -- can satisfy `language.inspect` while shipping no query). a file existence
      -- check, not query.get: compiling every query here costs ~800ms of startup
      local missing = vim.tbl_filter(function(lang)
        local ok = pcall(vim.treesitter.language.inspect, lang)
        return not ok or #vim.api.nvim_get_runtime_file('queries/' .. lang .. '/highlights.scm', false) == 0
      end, parsers)
      if #missing > 0 then
        -- force: the plugin counts a language as installed if its query dir
        -- exists, so a stale query dir would make a plain install() a no-op
        -- for exactly the parsers the probe above found broken
        require('nvim-treesitter').install(missing, { force = true }):wait(120000)
      end

      -- enable treesitter highlighting and indentation for all supported filetypes
      vim.api.nvim_create_autocmd('FileType', {
        callback = function()
          -- skip treesitter for large files to avoid blocking the editor
          local ok, stats = pcall(vim.uv.fs_stat, vim.api.nvim_buf_get_name(0))
          if ok and stats and stats.size > 1024 * 1024 then
            return
          end

          if pcall(vim.treesitter.start) then
            -- only set treesitter indentexpr when indent queries exist for this
            -- language, otherwise fall back to vim's native indent (autoindent,
            -- cindent, or filetype-specific indentexpr). without this check,
            -- languages like C# that lack indent queries get forced to column 0
            local lang = vim.treesitter.language.get_lang(vim.bo.filetype) or vim.bo.filetype
            if vim.treesitter.query.get(lang, 'indents') then
              vim.bo.indentexpr = "v:lua.require'nvim-treesitter'.indentexpr()"
            end
          end
        end,
      })

      -- go format verbs, which no query can reach: see the module header
      require('custom.features.go-format-verbs').setup()

      -- register language aliases for markdown code fence highlighting
      vim.treesitter.language.register('c_sharp', { 'csharp', 'cs' })

      -- force the astro injections override. upstream astro/injections.scm
      -- inherits html_tags (bare `<script>` -> javascript) then adds an
      -- unconditional typescript rule, so every astro `<script>` is injected
      -- twice and the javascript parse errors over the typescript highlights.
      -- a file override can't fix this: query.get reads the `; inherits:`
      -- modeline from every matching file in rtp, so the plugin's inherit
      -- still fires. query.set bypasses the file/modeline merge entirely
      local astro_inj = vim.fn.stdpath 'config' .. '/queries/astro/injections.scm'
      local f = io.open(astro_inj, 'r')
      if f then
        local scm = f:read '*a'
        f:close()
        pcall(vim.treesitter.query.set, 'astro', 'injections', scm)
      end
    end,
  },

  -- detect tabstop and shiftwidth automatically
  { 'NMAC427/guess-indent.nvim', event = 'BufReadPost', opts = {} },

  -- treesitter textobjects: structural selection and motion
  {
    'nvim-treesitter/nvim-treesitter-textobjects',
    branch = 'main',
    dependencies = { 'nvim-treesitter/nvim-treesitter' },
    event = 'VeryLazy',
    config = function()
      local ts_select = require 'nvim-treesitter-textobjects.select'
      local ts_move = require 'nvim-treesitter-textobjects.move'
      local ts_swap = require 'nvim-treesitter-textobjects.swap'

      require('nvim-treesitter-textobjects').setup {
        select = { lookahead = true },
        move = { set_jumps = true },
      }

      -- select textobjects
      local select_maps = {
        { 'am', '@function.outer', 'Around method/function' },
        { 'im', '@function.inner', 'Inside method/function' },
        { 'aC', '@class.outer', 'Around class' },
        { 'iC', '@class.inner', 'Inside class' },
      }
      for _, map in ipairs(select_maps) do
        vim.keymap.set({ 'x', 'o' }, map[1], function()
          ts_select.select_textobject(map[2])
        end, { desc = map[3] })
      end

      -- move to next/previous function
      vim.keymap.set({ 'n', 'x', 'o' }, ']m', function()
        ts_move.goto_next_start '@function.outer'
      end, { desc = 'Next function start' })
      vim.keymap.set({ 'n', 'x', 'o' }, '[m', function()
        ts_move.goto_previous_start '@function.outer'
      end, { desc = 'Previous function start' })
      vim.keymap.set({ 'n', 'x', 'o' }, ']M', function()
        ts_move.goto_next_end '@function.outer'
      end, { desc = 'Next function end' })
      vim.keymap.set({ 'n', 'x', 'o' }, '[M', function()
        ts_move.goto_previous_end '@function.outer'
      end, { desc = 'Previous function end' })

      -- swap parameters (guarded: bail with a notify when the buffer has no parser)
      local function with_parser(fn)
        return function()
          local ok, parser = pcall(vim.treesitter.get_parser)
          if not ok or not parser then
            vim.notify('No treesitter parser for this buffer', vim.log.levels.WARN)
            return
          end
          fn()
        end
      end
      vim.keymap.set(
        'n',
        '>p',
        with_parser(function()
          ts_swap.swap_next '@parameter.inner'
        end),
        { desc = 'Swap parameter right' }
      )
      vim.keymap.set(
        'n',
        '<p',
        with_parser(function()
          ts_swap.swap_previous '@parameter.inner'
        end),
        { desc = 'Swap parameter left' }
      )
    end,
  },
}
