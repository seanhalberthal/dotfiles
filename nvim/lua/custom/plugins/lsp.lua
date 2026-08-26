-- LSP configuration

local lsp_nav = require 'custom.features.lsp-navigation'
local lsp_fix_all = require 'custom.features.lsp-fix-all'
local lsp_patches = require 'custom.features.lsp-patches'

--- true only for ordinary on-disk file buffers. differ/fugitive views and
--- other plugin buffers carry a `scheme://` name and/or a non-empty `buftype`;
--- formatting them is meaningless and crashes formatters like csharpier, which
--- tries to resolve a config directory from the bogus URI path
local function is_real_file(bufnr)
  if vim.bo[bufnr].buftype ~= '' then
    return false
  end
  return vim.api.nvim_buf_get_name(bufnr):match '^%w+://' == nil
end

--- restart all LSP servers attached to the given buffer
local function restart_lsp_clients(bufnr)
  local clients = vim.lsp.get_clients { bufnr = bufnr }

  -- Roslyn's on_exit calls roslyn.store.set(client_id, nil), which nils
  -- vim.g.roslyn_nvim_selected_solution as a side effect. the restarted
  -- client's on_init then misses the lock_target fast path and falls back
  -- to broad search; with multiple candidates it bails on the multi-target
  -- prompt (suppressed by ui.lua), so the LSP silently fails to re-attach.
  -- preserve the solution across the LspDetach window: that fires after
  -- on_exit nils the var but before the scheduled new-client start runs
  -- on_init, so restoring here lets the new client hit the fast path
  local has_roslyn = false
  for _, c in ipairs(clients) do
    if c.name == 'roslyn' then
      has_roslyn = true
      break
    end
  end
  if has_roslyn and vim.g.roslyn_nvim_selected_solution then
    local saved = vim.g.roslyn_nvim_selected_solution
    local id
    id = vim.api.nvim_create_autocmd('LspDetach', {
      callback = function(ev)
        local detached = vim.lsp.get_client_by_id(ev.data.client_id)
        if detached and detached.name == 'roslyn' then
          vim.g.roslyn_nvim_selected_solution = saved
          vim.api.nvim_del_autocmd(id)
        end
      end,
    })
  end

  local count = 0
  for _, client in ipairs(clients) do
    if client.server_capabilities then
      vim.cmd('lsp restart ' .. client.name)
      count = count + 1
    end
  end
  if count > 0 then
    vim.notify(string.format('Restarted %d LSP server(s)', count), vim.log.levels.INFO)
  else
    vim.notify('No LSP servers attached to buffer', vim.log.levels.WARN)
  end
end

--- rename handler that writes the files it touched.
--- the default handler applies the workspace edit to every affected file but
--- leaves the ones that weren't already open as unsaved background buffers.
--- those never fire the autosave (no TextChanged/BufLeave), so renamed symbols
--- in other modules stay off disk: invisible to differ (which diffs disk)
--- and piling up as a "save changes?" cascade on :qa. mirror the default, then
--- flush every touched buffer, consistent with the auto-save autocmd
local function rename_and_save(_, result, ctx)
  if not result then
    vim.notify("Language server couldn't provide rename result", vim.log.levels.INFO)
    return
  end
  local client = assert(vim.lsp.get_client_by_id(ctx.client_id))
  vim.lsp.util.apply_workspace_edit(result, client.offset_encoding)

  -- documentChanges is an array of edits; changes is a map keyed by URI
  local uris = {}
  if result.documentChanges then
    for _, change in ipairs(result.documentChanges) do
      -- skip create/rename/delete resource ops, which have no textDocument
      if change.textDocument and change.textDocument.uri then
        uris[change.textDocument.uri] = true
      end
    end
  elseif result.changes then
    for uri in pairs(result.changes) do
      uris[uri] = true
    end
  end

  for uri in pairs(uris) do
    local buf = vim.uri_to_bufnr(uri)
    if vim.api.nvim_buf_is_loaded(buf) and vim.bo[buf].modified and vim.bo[buf].modifiable and vim.bo[buf].buftype == '' then
      vim.api.nvim_buf_call(buf, function()
        vim.cmd 'silent! write'
      end)
    end
  end
end

return {
  -- main LSP configuration
  {
    'neovim/nvim-lspconfig',
    event = { 'BufReadPre', 'BufNewFile' },
    cmd = { 'Mason', 'MasonInstall', 'MasonUninstall', 'MasonUninstallAll', 'MasonLog', 'MasonUpdate', 'MasonToolsInstall', 'MasonToolsUpdate' },
    dependencies = {
      {
        'mason-org/mason.nvim',
        opts = {
          registries = {
            'github:mason-org/mason-registry',
            'github:Crashdummyy/mason-registry', -- roslyn LSP server
          },
        },
      },
      'mason-org/mason-lspconfig.nvim',
      'WhoIsSethDaniel/mason-tool-installer.nvim',
      'saghen/blink.cmp',
    },
    config = function()
      -- LSP attach autocmd
      vim.api.nvim_create_autocmd('LspAttach', {
        group = vim.api.nvim_create_augroup('kickstart-lsp-attach', { clear = true }),
        callback = function(event)
          local map = function(keys, func, desc, mode)
            mode = mode or 'n'
            vim.keymap.set(mode, keys, func, { buffer = event.buf, desc = 'LSP: ' .. desc })
          end

          -- LSP keymaps
          map('K', vim.lsp.buf.hover, 'Hover')
          map('grn', vim.lsp.buf.rename, 'Re[n]ame')
          map('gra', lsp_fix_all.code_action_with_refresh, 'Code [A]ction', { 'n', 'x' })
          map('grf', lsp_fix_all.fix_all_in_file, '[F]ix all in file')
          map('grr', lsp_nav.dedup 'references', '[R]eferences')
          map('gri', lsp_nav.dedup 'implementation', '[I]mplementation')
          map('grd', lsp_nav.dedup 'definition', '[D]efinition')
          map('gd', lsp_nav.dedup 'definition', '[D]efinition')
          map('grD', vim.lsp.buf.declaration, '[D]eclaration')
          map('gO', require('telescope.builtin').lsp_document_symbols, 'Document symbols')
          map('gW', require('telescope.builtin').lsp_dynamic_workspace_symbols, 'Workspace symbols')
          map('grt', lsp_nav.dedup 'type_definition', '[T]ype definition')
          map('<leader>lr', function()
            restart_lsp_clients(event.buf)
          end, '[R]estart')

          -- document highlight on cursor hold
          local client = vim.lsp.get_client_by_id(event.data.client_id)
          if client and client:supports_method(vim.lsp.protocol.Methods.textDocument_documentHighlight, event.buf) then
            local highlight_augroup = vim.api.nvim_create_augroup('kickstart-lsp-highlight', { clear = false })
            vim.api.nvim_create_autocmd({ 'CursorHold', 'CursorHoldI' }, {
              buffer = event.buf,
              group = highlight_augroup,
              callback = vim.lsp.buf.document_highlight,
            })

            vim.api.nvim_create_autocmd({ 'CursorMoved', 'CursorMovedI' }, {
              buffer = event.buf,
              group = highlight_augroup,
              callback = vim.lsp.buf.clear_references,
            })

            vim.api.nvim_create_autocmd('LspDetach', {
              group = vim.api.nvim_create_augroup('kickstart-lsp-detach', { clear = true }),
              callback = function(event2)
                vim.lsp.buf.clear_references()
                vim.api.nvim_clear_autocmds { group = 'kickstart-lsp-highlight', buffer = event2.buf }
              end,
            })
          end

          -- inlay hints toggle
          if client and client:supports_method(vim.lsp.protocol.Methods.textDocument_inlayHint, event.buf) then
            map('<leader>lh', function()
              vim.lsp.inlay_hint.enable(not vim.lsp.inlay_hint.is_enabled { bufnr = event.buf })
            end, 'Inlay [H]ints')
          end

          -- code lens (gopls only; other languages render above-line which clashes
          -- with deeply-nested declarations and adds noise)
          if client and client.name == 'gopls' and client:supports_method(vim.lsp.protocol.Methods.textDocument_codeLens, event.buf) then
            vim.lsp.codelens.enable(true, { bufnr = event.buf })
            map('<leader>ll', vim.lsp.codelens.run, 'Code [L]ens run')
            map('<leader>lL', function()
              vim.lsp.codelens.enable(true, { bufnr = event.buf })
            end, 'Code [L]ens refresh')
          end
        end,
      })

      -- diagnostic config
      vim.diagnostic.config {
        severity_sort = true,
        float = { border = 'rounded', source = 'if_many' },
        underline = { severity = vim.diagnostic.severity.ERROR },
        signs = vim.g.have_nerd_font and {
          text = {
            [vim.diagnostic.severity.ERROR] = '󰅚 ',
            [vim.diagnostic.severity.WARN] = '󰀪 ',
            [vim.diagnostic.severity.INFO] = '󰋽 ',
            [vim.diagnostic.severity.HINT] = '󰌶 ',
          },
        } or {},
        -- signs mark the affected lines; the message itself renders as virtual
        -- lines under the cursor line only. end-of-line virtual text ran off
        -- the right edge on long messages and only ever drew the *last*
        -- diagnostic on a line, hiding the rest
        virtual_text = false,
        virtual_lines = {
          current_line = true,
          -- the built-in formatter prefixes `code`, which is worth showing for
          -- real rule ids (sonar's S1234, eslint rule names) but not for gopls,
          -- which labels every analyzer finding with the placeholder "default"
          format = function(d)
            if d.code and d.code ~= 'default' then
              return string.format('%s: %s', d.code, d.message)
            end
            return d.message
          end,
        },
      }

      -- hover, signature help, and markdown rendering are handled by noice.nvim (see ui.lua)

      -- write files touched by an LSP rename so they land on disk (see above)
      vim.lsp.handlers['textDocument/rename'] = rename_and_save

      -- merge blink.cmp completion capabilities with nvim defaults so that
      -- semantic tokens, document highlights, and other standard capabilities
      -- aren't dropped (blink only provides completion-related caps)
      local caps = vim.tbl_deep_extend('force', vim.lsp.protocol.make_client_capabilities(), require('blink.cmp').get_lsp_capabilities())
      -- disable built-in document_color to avoid assertion failures on stale client IDs
      -- (neovim/neovim#38404)
      vim.lsp.document_color.enable(false)
      vim.lsp.config('*', { capabilities = caps })

      lsp_patches.patch_lsp_start()
      lsp_patches.patch_show_document()

      vim.lsp.config('cssls', {
        settings = {
          css = { lint = { unknownAtRules = 'ignore' } },
        },
      })

      vim.lsp.config('lua_ls', {
        settings = {
          Lua = {
            completion = { callSnippet = 'Replace' },
          },
        },
      })

      -- Roslyn is sluggish to acknowledge `shutdown`, so `:lsp restart roslyn`
      -- (and `:Roslyn restart`, which delegates to it) hangs indefinitely with
      -- the default `exit_timeout = false`: the old client only actually
      -- dies once some subsequent LSP request nudges traffic on the pipe.
      -- force-terminate after 5s so restarts are reliable. roslyn.nvim's own
      -- `:Roslyn target` command documents the same quirk in commands.lua
      vim.lsp.config('roslyn', {
        exit_timeout = 5000,
      })

      -- kill every server outright on actual nvim exit, so closing the editor
      -- never waits on one. nvim's own VimLeavePre handler takes the max
      -- `exit_timeout` across all clients and `vim.wait`s for them to close
      -- (with a deferred "Waiting Ns for LSP exit" warning above 100), and a
      -- server busy enough not to answer burns the whole budget: roslyn's 5s,
      -- copilot's under a loaded solution. ExitPre runs before that handler,
      -- and `stop(true)` terminates the process synchronously (SIGTERM via
      -- rpc.terminate) rather than asking politely and waiting, so nothing is
      -- left to wait for and nothing is left orphaned either. runtime restarts
      -- (`:lsp restart roslyn`) still get the per-client timeouts above
      vim.api.nvim_create_autocmd('ExitPre', {
        desc = 'force-kill LSP servers so nvim does not wait on exit',
        callback = function()
          for _, c in pairs(vim.lsp.get_clients()) do
            c.exit_timeout = 0
            c:stop(true)
          end
        end,
      })

      vim.lsp.config('gopls', {
        settings = {
          gopls = {
            -- restrict workspace/symbol to our own modules, not deps in ~/go/pkg/mod
            symbolScope = 'workspace',
            -- gopls sends one `string` token per literal at semantic-token
            -- priority 125, burying treesitter's @string.escape and
            -- @string.regexp at 100. all it carries that treesitter does not is
            -- a `format` modifier on printf verbs, which no theme here styles,
            -- and custom.features.go-format-verbs marks those anyway
            semanticTokenTypes = { string = false },
            codelenses = {
              generate = true,
              regenerate_cgo = true,
              test = true,
              tidy = true,
              upgrade_dependency = true,
              vendor = true,
              run_govulncheck = true,
            },
          },
        },
      })

      -- golangci-lint's default linter set (govet, staticcheck, ineffassign,
      -- unused) re-reports what gopls already runs, and both servers draw their
      -- own extmark, so every finding rendered twice. lspconfig roots it at
      -- `go.work`/`go.mod`/`.git`, i.e. every Go project; gate it on an explicit
      -- golangci config instead so gopls owns vet everywhere else. a `root_dir`
      -- function that skips `on_dir` is the documented way to decide activation
      -- dynamically (`:h lsp-root_dir()`); overriding `root_markers` would not
      -- work, since vim.lsp.config deep-merges lists by index and the shorter
      -- list would leave lspconfig's `go.mod`/`.git` entries trailing.
      --
      -- `-nolintername` stops the server baking the linter name into the message
      -- text as well as the `source` field, which rendered as "errcheck:
      -- errcheck: ..." wherever we prefix by source (diagnostic float, lists)
      vim.lsp.config('golangci_lint_ls', {
        cmd = { 'golangci-lint-langserver', '-nolintername' },
        root_dir = function(bufnr, on_dir)
          local root = vim.fs.root(bufnr, { '.golangci.yml', '.golangci.yaml', '.golangci.toml', '.golangci.json' })
          if root then
            on_dir(root)
          end
        end,
      })

      -- sourcekit-lsp (Swift) ships with the Xcode/Swift toolchain, not Mason,
      -- so it can't ride the mason-lspconfig ensure_installed/automatic_enable
      -- flow below: configure and enable it directly. launch via `xcrun` on
      -- macOS so it resolves against the active toolchain; fall back to the
      -- PATH binary on Linux. restrict filetypes to `swift`: lspconfig's
      -- default sourcekit config also claims c/cpp/objc/objcpp, which would
      -- double-attach alongside clangd and duplicate diagnostics. clangd keeps
      -- ownership of the C family (including Objective-C)
      local sourcekit_cmd = vim.fn.has 'mac' == 1 and { 'xcrun', 'sourcekit-lsp' } or { 'sourcekit-lsp' }
      if vim.fn.executable(sourcekit_cmd[1]) == 1 then
        vim.lsp.config('sourcekit', {
          cmd = sourcekit_cmd,
          filetypes = { 'swift' },
        })
        vim.lsp.enable 'sourcekit'
      end

      -- server configurations
      local servers = {
        astro = {},
        bashls = {},
        clangd = {},
        cssls = {},
        eslint = {},
        gopls = {},
        html = {},
        lua_ls = {},
        pyright = {},
        tailwindcss = {},
        ts_ls = {},
        yamlls = {},
      }

      -- defer mason setups: their `setup{}` calls do tool-install verification
      -- and per-server enable iteration that can take many seconds on cold
      -- start. running them in vim.schedule lets the triggering buffer
      -- (BufReadPre, including differ/octo diff buffers) finish opening
      -- first. servers register/attach a few ms later, invisible in practice
      vim.schedule(function()
        -- per-machine opt-out for lightweight boxes (e.g. a Raspberry Pi) that
        -- lack the language runtimes (node/go/dotnet) Mason needs to build most
        -- servers. set `vim.g.disable_mason_auto_install = true` in
        -- ~/.config/nvim/local.lua to skip auto-install; servers that are
        -- already installed still enable and attach normally.
        local mason_auto_install = not vim.g.disable_mason_auto_install

        require('mason-lspconfig').setup {
          ensure_installed = mason_auto_install and vim.tbl_keys(servers or {}) or {},
          automatic_installation = false,
          automatic_enable = {
            exclude = { 'omnisharp' }, -- using roslyn.nvim instead
          },
        }

        require('mason-tool-installer').setup {
          ensure_installed = mason_auto_install and {
            -- LSP servers
            'astro',
            'bashls',
            'clangd',
            'cssls',
            'eslint',
            'gopls',
            'html',
            'lua_ls',
            'pyright',
            'tailwindcss',
            'ts_ls',
            'yamlls',
            -- Roslyn (C# LSP, from Crashdummyy/mason-registry)
            'roslyn',
            -- SonarLint LSP (analyzers + bundled omnisharp for C#); driven by sonarlint.lua
            'sonarlint-language-server',
            -- formatters
            'clang-format', -- c / cpp / objc
            'csharpier',
            'gofumpt',
            'goimports',
            'prettier',
            'stylua',
            -- linters
            'golangci-lint-langserver',
            'ruff', -- Python lint + format
            -- go codegen helpers (struct tags, iferr); wired in features/go.lua
            'gomodifytags',
            'iferr',
          } or {},
        }
      end)
    end,
  },

  -- formatting
  {
    'stevearc/conform.nvim',
    event = { 'BufWritePre' },
    cmd = { 'ConformInfo' },
    keys = {
      {
        '<leader>f',
        function()
          if not vim.bo.modifiable then
            vim.notify('Buffer is not modifiable', vim.log.levels.WARN)
            return
          end
          if not is_real_file(0) then
            vim.notify('Not a file buffer; nothing to format', vim.log.levels.WARN)
            return
          end
          require('conform').format { async = true, lsp_format = 'fallback' }
        end,
        mode = '',
        desc = '[F]ormat buffer',
      },
    },
    opts = {
      notify_on_error = true,
      format_on_save = function(bufnr)
        if not is_real_file(bufnr) then
          return
        end
        -- per-buffer / global opt-out (conform's convention); differ's merge tool
        -- sets the buffer flag so :w doesn't format over conflict markers
        if vim.g.disable_autoformat or vim.b[bufnr].disable_autoformat then
          return
        end
        -- prettier (esp. with prettier-plugin-astro) and other node-based
        -- formatters pay ~1.5s of startup per run; native binaries are fast
        local slow_ft = {
          astro = true,
          javascript = true,
          javascriptreact = true,
          json = true,
          typescript = true,
          typescriptreact = true,
          yaml = true,
          cs = true,
          swift = true,
        }
        return {
          timeout_ms = slow_ft[vim.bo[bufnr].filetype] and 3000 or 500,
          lsp_format = 'fallback',
        }
      end,
      formatters_by_ft = {
        astro = { 'prettier' },
        c = { 'clang_format' },
        cpp = { 'clang_format' },
        cs = { 'csharpier' },
        objc = { 'clang_format' },
        objcpp = { 'clang_format' },
        swift = { 'swift_format' },
        go = { 'goimports', 'gofumpt' },
        javascript = { 'prettier' },
        javascriptreact = { 'prettier' },
        json = { 'prettier' },
        lua = { 'stylua' },
        python = { 'ruff_organize_imports', 'ruff_format' },
        typescript = { 'prettier' },
        typescriptreact = { 'prettier' },
        yaml = { 'prettier' },
      },
      formatters = {
        goimports = {
          command = vim.fn.stdpath 'data' .. '/mason/bin/goimports',
        },
        csharpier = {
          -- conform's default args switch on `dotnet csharpier --version` and
          -- pass `csharpier format --stdin-path $FILENAME` (i.e. as a dotnet
          -- subcommand). when we override `command` to Mason's standalone
          -- binary, those args get passed to it directly and csharpier 1.0+
          -- bails with "Unrecognized command or argument 'csharpier'". pin
          -- args to the format subcommand the standalone binary understands
          command = vim.fn.stdpath 'data' .. '/mason/bin/csharpier',
          args = { 'format', '--stdin-path', '$FILENAME' },
          stdin = true,
        },
        prettier = {
          -- prefer the project's local prettier so plugins declared in
          -- the project's .prettierrc (e.g. prettier-plugin-astro) are
          -- resolved against the project's node_modules. falls back to
          -- Mason's prettier when there's no local install
          prefer_local = 'node_modules/.bin',
        },
      },
    },
  },
}
