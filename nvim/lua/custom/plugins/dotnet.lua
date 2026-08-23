-- .NET development: roslyn.nvim for LSP, easy-dotnet.nvim for build/run/debug
-- https://github.com/seblyng/roslyn.nvim
-- https://github.com/GustavEikaas/easy-dotnet.nvim

--- @param path string
--- @return boolean
local function is_build_variant(path)
  return vim.fs.basename(path):match '%.[%l][%w]*%.slnx?$' ~= nil
end

--- find and set the target solution before roslyn.nvim loads, so that
--- lock_target can skip the multi-target picker entirely
local function resolve_solution_target()
  if vim.g.roslyn_nvim_selected_solution then
    return
  end
  local buf_path = vim.api.nvim_buf_get_name(0)
  if buf_path == '' then
    return
  end
  local sln_files = vim.fs.find(function(name)
    return (name:match '%.sln$' or name:match '%.slnx$') and not is_build_variant(name)
  end, { upward = true, path = vim.fs.dirname(buf_path), limit = math.huge })
  if #sln_files > 0 then
    table.sort(sln_files, function(a, b)
      return #vim.fs.basename(a) < #vim.fs.basename(b)
    end)
    vim.g.roslyn_nvim_selected_solution = sln_files[1]
  end
end

-- Roslyn during an Octo review context.
-- strategy: do NOTHING to the LSP client. nvim's `lsp_enable_callback`
-- skips buffers with `buftype` other than '' or 'help', and octo review
-- buffers have buftype=nofile, so roslyn never auto-attaches to them anyway.
-- we previously called `vim.lsp.enable('roslyn', false)` to "block new
-- attaches", but that ALSO stops every running roslyn client (per the
-- vim.lsp.enable contract: "stops related LSP clients and servers"),
-- which paid a multi-second cold-restart on every review entry/exit cycle.
--
-- vim.g.roslyn_suppressed remains as a flag so the notify wrap in ui.lua
-- and fidget's progress.ignore can still drop residual chatter while in
-- review (e.g. messages emitted by an unrelated client startup)
vim.g.roslyn_suppressed = false

--- source roslyn.nvim's plugin file after our config is applied. we block
--- it in init (vim.g.loaded_roslyn_plugin) to prevent vim.lsp.enable
--- firing before lock_target + ignore_target are set
local function source_deferred_plugin()
  vim.g.loaded_roslyn_plugin = nil
  local plugin_file = vim.api.nvim_get_runtime_file('plugin/roslyn.lua', false)[1]
  if plugin_file then
    dofile(plugin_file)
  end
end

vim.api.nvim_create_autocmd('FileType', {
  pattern = 'octo',
  callback = function()
    vim.g.roslyn_suppressed = true
  end,
})

-- clear the flag once the review context is fully torn down (no octo
-- buffers remain)
local function maybe_clear_roslyn_flag()
  if not vim.g.roslyn_suppressed then
    return
  end
  if require('custom.core.review-context').is_active() then
    return
  end
  vim.g.roslyn_suppressed = false
end

vim.api.nvim_create_autocmd('BufEnter', {
  pattern = '*.cs',
  callback = function()
    if vim.g.roslyn_suppressed then
      vim.defer_fn(maybe_clear_roslyn_flag, 500)
    end
  end,
})

return {
  -- Roslyn LSP via roslyn.nvim (diagnostics, go-to-def, hover, completions)
  -- loads on `User RealDotnetFile` (fired by core/autocmds.lua only for
  -- buftype='' cs/razor buffers). differ and octo diff/review buffers are
  -- buftype=nofile, so they don't trigger this and roslyn.nvim's ~1.8s
  -- config cost stays off the cold-`<leader>do` critical path
  {
    'seblyng/roslyn.nvim',
    event = 'User RealDotnetFile',
    dependencies = { 'mason-org/mason.nvim' },
    ---@module 'roslyn.config'
    ---@type RoslynNvimConfig
    opts = {
      ignore_target = function(target)
        return is_build_variant(target)
      end,
      broad_search = true,
      lock_target = true,
      -- let the server watch files instead of nvim. on `auto`, roslyn registers
      -- ~500 didChangeWatchedFiles watchers for a solution, and on macOS each is
      -- an FSEvents handle that costs ~1.2ms to tear down: `Client:stop` cancels
      -- them all before it can exit, so every `:q` in a .NET repo paid ~560ms.
      -- `roslyn` advertises dynamicRegistration=false, so nvim registers none and
      -- the server keeps its own watch (unlike `off`, which watches nothing)
      filewatching = 'roslyn',
    },
    init = function()
      vim.g.loaded_roslyn_plugin = true
    end,
    config = function(_, opts)
      resolve_solution_target()
      require('custom.features.roslyn-diagnostics').patch_diagnostic_set()
      require('custom.features.roslyn-semantic-tokens').setup()

      vim.lsp.config('roslyn', {
        -- Roslyn's runtimeconfig.json pins System.GC.Server=true, which gives
        -- the .NET runtime ~one GC heap per core: a heavy idle footprint on
        -- many-core machines (and a big chunk of roslyn's thread count). the
        -- language server targets net10.0, and on .NET 9+ environment variables
        -- override runtimeconfig settings, so DOTNET_gcServer=0 forces
        -- workstation GC: far fewer heaps and lower memory, at a modest
        -- throughput cost on background full-solution analysis (kept off the hot
        -- path by the batched scans in features/diag-scan.lua). scoped to the roslyn
        -- process via cmd_env, which roslyn.nvim's lsp/roslyn.lua passes through
        -- as the spawn env (merging with its own Configuration/TMPDIR), so
        -- easy-dotnet's builds/tests/BuildHost are unaffected
        cmd_env = {
          DOTNET_gcServer = '0',
        },
        settings = {
          ['csharp|background_analysis'] = {
            dotnet_analyzer_diagnostics_scope = 'openFiles',
            dotnet_compiler_diagnostics_scope = 'openFiles',
          },
          ['csharp|completion'] = {
            dotnet_show_completion_items_from_unimported_namespaces = true,
            dotnet_show_name_completion_suggestions = true,
          },
          ['csharp|code_lens'] = {
            dotnet_enable_references_code_lens = false,
            dotnet_enable_tests_code_lens = false,
          },
        },
      })

      require('roslyn').setup(opts)
      source_deferred_plugin()
    end,
  },

  -- easy-dotnet.nvim for build, run, debug, test (LSP handled by roslyn.nvim)
  {
    'GustavEikaas/easy-dotnet.nvim',
    dependencies = {
      'nvim-lua/plenary.nvim',
      'nvim-telescope/telescope.nvim',
      'mfussenegger/nvim-dap',
    },
    ft = { 'cs', 'fsharp', 'vb' },
    config = function()
      -- sync roslyn.nvim's solution target into easy-dotnet's cache so the
      -- test runner and build commands use the same solution. force-overwrite
      -- if the cached solution is a build variant (e.g. .ci.slnx)
      local roslyn_sln = vim.g.roslyn_nvim_selected_solution
      if roslyn_sln then
        local current_solution = require 'easy-dotnet.current_solution'
        local cached = current_solution.try_get_selected_solution()
        if not cached or is_build_variant(cached) then
          current_solution.set_solution(roslyn_sln)
        end
      end

      require('easy-dotnet').setup {
        debugger = {
          auto_register_dap = true,
          console = 'integratedTerminal',
        },
        lsp = {
          enabled = false,
        },
        test_runner = {
          auto_start_testrunner = false,
          viewmode = 'float',
          mappings = {
            -- buffer keymaps (active in .cs files with tests)
            run_test_from_buffer = { lhs = '<leader>tr', desc = '[R]un test' },
            -- run_all_tests_from_buffer overridden below (upstream runs whole project)
            debug_test_from_buffer = { lhs = '<leader>td', desc = '[D]ebug test' },
            peek_stack_trace_from_buffer = { lhs = '<leader>tp', desc = '[P]eek stacktrace' },
            -- explorer window keymaps (single keys, non-editable buffer)
            run = { lhs = 'r', desc = 'run test' },
            run_all = { lhs = 'R', desc = 'run all tests' },
            debug_test = { lhs = 'd', desc = 'debug test' },
            peek_stacktrace = { lhs = 'p', desc = 'peek stacktrace' },
            go_to_file = { lhs = 'gf', desc = 'go to file' },
            get_build_errors = { lhs = 'ge', desc = 'build errors' },
            refresh_testrunner = { lhs = '<C-r>', desc = 'refresh' },
            cancel = { lhs = '<C-c>', desc = 'cancel' },
            close = { lhs = 'q', desc = 'close' },
            expand = { lhs = 'o', desc = 'expand' },
            expand_node = { lhs = 'E', desc = 'expand all' },
            collapse_all = { lhs = 'W', desc = 'collapse all' },
          },
        },
      }

      vim.keymap.set('n', '<leader>nd', '<cmd>Dotnet debug<cr>', { desc = '[D]ebug project' })
      vim.keymap.set('n', '<leader>na', '<cmd>Dotnet debug attach<cr>', { desc = '[A]ttach to running .NET process' })
      vim.keymap.set('n', '<leader>nr', '<cmd>Dotnet run<cr>', { desc = '[R]un project' })
      vim.keymap.set('n', '<leader>nb', '<cmd>Dotnet build<cr>', { desc = '[B]uild project' })
      vim.keymap.set('n', '<leader>nc', '<cmd>Dotnet clean<cr>', { desc = '[C]lean project' })
      vim.keymap.set('n', '<leader>ns', '<cmd>Dotnet secrets<cr>', { desc = 'Manage [S]ecrets' })
      vim.keymap.set('n', '<leader>nw', '<cmd>Dotnet watch<cr>', { desc = '[W]atch project' })
      vim.keymap.set('n', '<leader>nn', '<cmd>Dotnet new<cr>', { desc = '[N]ew item' })
      vim.keymap.set('n', '<leader>no', '<cmd>Dotnet outdated<cr>', { desc = '[O]utdated packages' })

      vim.keymap.set('n', '<leader>te', function()
        require('easy-dotnet.test-runner').open()
      end, { desc = 'Test [E]xplorer (.NET)' })

      -- float nav-blocking + run-current-file tests live in features/
      require('custom.features.dotnet-test').setup()
    end,
  },
}
