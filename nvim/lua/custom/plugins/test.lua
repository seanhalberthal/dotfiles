-- test runner with neotest
-- https://github.com/nvim-neotest/neotest
-- .NET tests handled by easy-dotnet.nvim (see dotnet.lua)

--- find the nearest directory containing node_modules/.bin/<bin>.
--- walks up from the path, then checks immediate subdirectories as fallback (monorepo root).
--- results are cached per (path, bin) since binary locations don't change in a session
local node_bin_root_cache = {} ---@type table<string, string|false>
local function find_node_bin_root(path, bin)
  local start = vim.fn.isdirectory(path) == 1 and path or vim.fn.fnamemodify(path, ':h')
  local key = start .. ':' .. bin
  if node_bin_root_cache[key] ~= nil then
    return node_bin_root_cache[key] or nil
  end
  local dir = start
  while dir and dir ~= '/' do
    if vim.uv.fs_stat(dir .. '/node_modules/.bin/' .. bin) then
      node_bin_root_cache[key] = dir
      return dir
    end
    dir = vim.fn.fnamemodify(dir, ':h')
  end
  -- walk-up failed (e.g. monorepo root); check immediate subdirectories
  for name, type in vim.fs.dir(start) do
    if type == 'directory' and name ~= 'node_modules' then
      if vim.uv.fs_stat(start .. '/' .. name .. '/node_modules/.bin/' .. bin) then
        node_bin_root_cache[key] = start .. '/' .. name
        return node_bin_root_cache[key]
      end
    end
  end
  node_bin_root_cache[key] = false
end

local function find_vitest_root(path)
  return find_node_bin_root(path, 'vitest')
end

local function find_jest_root(path)
  return find_node_bin_root(path, 'jest')
end

--- wrap a neotest function to skip .cs files (handled by easy-dotnet)
local function neotest_fn(fn)
  return function()
    if vim.bo.filetype ~= 'cs' then
      fn()
    end
  end
end

--- neotest parses with nvim's default 256 in-progress tree-sitter match cap, and
--- past it the earliest-starting matches are dropped, so long table-driven tests
--- are silently truncated to their tail (43 cases for a keyed `tt := []struct{}`
--- table, 84 for map and unkeyed shapes). neotest takes a match_limit, but no
--- adapter passes one
local function raise_treesitter_match_limit()
  local ok, ts = pcall(require, 'neotest.lib.treesitter')
  if not ok or ts.match_limit_raised then
    return
  end
  local parse_positions = ts.parse_positions
  ts.parse_positions = function(path, query, opts)
    return parse_positions(path, query, vim.tbl_extend('keep', opts or {}, { match_limit = 100000 }))
  end
  ts.match_limit_raised = true
end

--- neotest-golang keys its per-file discovery cache on whole-second mtime, so a
--- second write inside the same second is served the stale tree, and nothing
--- expires it afterwards. autosave writes on every normal-mode edit (see
--- core/autocmds.lua), so deleting table test cases strands them in the summary.
--- re-key on the full stat signature, captured before the parse: a write landing
--- mid-parse then leaves the entry stamped stale rather than fresh, costing a
--- re-parse instead of serving stale positions
local function fix_golang_discovery_cache()
  local ok, cache = pcall(require, 'neotest-golang.lib.discovery_cache')
  if not ok or type(cache.get) ~= 'function' or type(cache.set) ~= 'function' then
    return
  end
  local store = {} ---@type table<string, {tree: neotest.Tree|nil, sig: string|nil}>
  local pending = {} ---@type table<string, string|nil>
  local function signature(path)
    local stat = vim.uv.fs_stat(path)
    return stat and string.format('%d:%d:%d', stat.mtime.sec, stat.mtime.nsec, stat.size) or nil
  end
  cache.get = function(path)
    local sig = signature(path)
    pending[path] = sig
    local entry = store[path]
    if entry and sig and entry.sig == sig then
      return entry.tree
    end
    return nil
  end
  cache.set = function(path, tree)
    store[path] = { tree = tree, sig = pending[path] }
  end
  cache.invalidate = function(path)
    store[path] = nil
  end
  cache.clear = function()
    store, pending = {}, {}
  end
  cache.stats = function()
    local files = vim.tbl_keys(store)
    return { size = #files, files = files }
  end
end

return {
  'nvim-neotest/neotest',
  dependencies = {
    'nvim-neotest/nvim-nio',
    'nvim-lua/plenary.nvim',
    'antoinemadec/FixCursorHold.nvim',
    'nvim-treesitter/nvim-treesitter',
    -- adapters
    'fredrikaverpil/neotest-golang', -- Go
    'marilari88/neotest-vitest', -- Vitest/Bun test runner
    'haydenmeade/neotest-jest', -- Jest (React Native, RTL, plain JS/TS)
    'nvim-neotest/neotest-python', -- pytest/unittest
  },
  keys = {
    { '<leader>tt', neotest_fn(function()
      require('neotest').run.run()
    end), desc = 'Run neares[T]' },
    { '<leader>tf', neotest_fn(function()
      require('neotest').run.run(vim.fn.expand '%')
    end), desc = 'Run [F]ile' },
    { '<leader>ta', neotest_fn(function()
      require('neotest').run.run { suite = true }
    end), desc = 'Run [A]ll' },
    { '<leader>tl', neotest_fn(function()
      require('neotest').run.run_last()
    end), desc = 'Run [L]ast' },
    { '<leader>ts', neotest_fn(function()
      require('neotest').summary.toggle()
    end), desc = 'Toggle [S]ummary' },
    { '<leader>to', neotest_fn(function()
      require('neotest').output.open { enter = true, auto_close = true }
    end), desc = 'Show [O]utput' },
    { '<leader>tO', neotest_fn(function()
      require('neotest').output_panel.toggle()
    end), desc = 'Toggle [O]utput panel' },
    { '<leader>tS', neotest_fn(function()
      require('neotest').run.stop()
    end), desc = '[S]top' },
    { '<leader>tw', neotest_fn(function()
      require('neotest').watch.toggle(vim.fn.expand '%')
    end), desc = 'Toggle [W]atch' },
    { '<leader>td', neotest_fn(function()
      require('neotest').run.run { strategy = 'dap' }
    end), desc = '[D]ebug nearest' },
    {
      '[t',
      function()
        require('neotest').jump.prev { status = 'failed' }
      end,
      desc = 'Test: Prev failed',
    },
    {
      ']t',
      function()
        require('neotest').jump.next { status = 'failed' }
      end,
      desc = 'Test: Next failed',
    },
  },
  config = function()
    raise_treesitter_match_limit()
    fix_golang_discovery_cache()

    require('neotest').setup {
      adapters = {
        require 'neotest-golang' {
          go_test_args = { '-v', '-count=1' },
          warn_test_name_dupes = false,
        },
        require 'neotest-vitest' {
          vitestCommand = function(path)
            local dir = find_vitest_root(path)
            if not dir then
              return 'vitest'
            end
            -- return `node <vitest.mjs>` rather than the .bin/vitest wrapper:
            -- neotest-vitest passes command[1] as DAP's `runtimeExecutable`,
            -- which must be a node-equivalent runtime. using `.bin/vitest`
            -- directly breaks package.json resolution under js-debug-adapter
            local vitest_mjs = dir .. '/node_modules/vitest/vitest.mjs'
            if vim.uv.fs_stat(vitest_mjs) then
              return 'node ' .. vitest_mjs
            end
            return dir .. '/node_modules/.bin/vitest'
          end,
          -- don't override cwd: neotest-vitest defaults to the dir of the
          -- nearest vitest.config.*, which is the per-project root in a
          -- monorepo. forcing the hoisted-node_modules root here causes
          -- vitest's per-project `include` globs to miss the test file
          filter_dir = function(name)
            return name ~= 'node_modules' and name ~= 'dist' and name ~= '.git' and name ~= 'coverage'
          end,
        },
        require 'neotest-jest' {
          jestCommand = function(path)
            local dir = find_jest_root(path)
            return dir and (dir .. '/node_modules/.bin/jest') or 'jest'
          end,
          cwd = find_jest_root,
          -- only claim files when a jest binary is reachable, so this adapter stays
          -- out of vitest projects (which use the same .test./.spec. naming)
          is_test_file = function(path)
            if not path:match '%.test%.[jt]sx?$' and not path:match '%.spec%.[jt]sx?$' then
              return false
            end
            return find_jest_root(path) ~= nil
          end,
        },
        require 'neotest-python' {
          runner = 'pytest',
          args = { '-v' },
          dap = { justMyCode = false },
        },
      },
      summary = {
        animated = true,
        open = 'botright vsplit | vertical resize 50',
        mappings = {
          expand = { 'o', '<2-LeftMouse>' },
          output = 'p',
        },
      },
      output = {
        open_on_run = false,
      },
      -- neotest's quickfix consumer is on by default and pushes a fresh
      -- untitled list on every failing run, which drops the forward half of
      -- the qf stack and pauses the live <leader>xx diagnostics sync (it only
      -- rebuilds while the current list is titled `Diagnostics: all`). the
      -- summary, signs and ]t/[t jump-to-failed cover the same ground
      quickfix = { enabled = false },
      floating = {
        border = 'rounded',
        max_height = 0.7,
        max_width = 0.7,
      },
      status = {
        virtual_text = false,
        signs = true,
      },
      icons = {
        passed = '✓',
        failed = '✗',
        running = '⟳',
        skipped = '○',
        unknown = '?',
      },
    }

    -- the diagnostic consumer publishes failures as real ERROR diagnostics, so
    -- a failing test drew an error squiggle and an error sign and read as a
    -- file that doesn't compile. keep the message (virtual_lines still puts it
    -- on the failing assertion) but drop both markers: neotest's own ✗ status
    -- sign already owns the gutter cell (priority 1000 against the diagnostic
    -- sign's 10). the statusline counts this namespace separately, as ✗N rather
    -- than EN, and the <leader>xx list filters it out; see features/statusline.lua
    -- and features/lists.lua. neotest-golang sets severity per error, so
    -- `diagnostic.severity` above wouldn't reach these
    vim.diagnostic.config({ underline = false, signs = false }, vim.api.nvim_create_namespace 'neotest')

    -- close output preview on any keypress for a transient popup feel
    vim.api.nvim_create_autocmd('FileType', {
      pattern = 'neotest-output',
      callback = function(args)
        local function close()
          pcall(vim.api.nvim_buf_delete, args.buf, { force = true })
        end
        for _, key in ipairs { '<Esc>', '<CR>', 'q' } do
          vim.keymap.set('n', key, close, { buffer = args.buf, nowait = true })
        end
      end,
    })
  end,
}
