-- debug.lua
--
-- Debug Adapter Protocol client with UI and inline variable display.
-- Go debugging via Delve, extensible to other languages

-- stepping while the top frame is runtime.goexit ends the goroutine mid-step.
-- delve conditions its stepping breakpoints on that goroutine id, so they can
-- never fire again, and every later step fails with "next while nexting" until
-- a halt cancels it. refuse the step and leave continue as the way out
local function step(cmd)
  return function()
    local dap = require 'dap'
    local session = dap.session()
    local frame = session and session.current_frame
    if frame and frame.name == 'runtime.goexit' then
      vim.notify('dap: goroutine has finished, continue (F5) instead of stepping', vim.log.levels.WARN)
      return
    end
    dap[cmd]()
  end
end

return {
  'mfussenegger/nvim-dap',
  dependencies = {
    'igorlfs/nvim-dap-view',
    'mason-org/mason.nvim',
    'jay-babu/mason-nvim-dap.nvim',
    'leoluz/nvim-dap-go',
    'mfussenegger/nvim-dap-python',
  },
  keys = {
    {
      '<F5>',
      function()
        require('dap').continue()
      end,
      desc = 'Debug: Start/Continue',
    },
    {
      '<F6>',
      function()
        require('dap').pause()
      end,
      desc = 'Debug: Pause (cancels an interrupted step)',
    },
    {
      '<F1>',
      step 'step_into',
      desc = 'Debug: Step Into',
    },
    {
      '<F2>',
      step 'step_over',
      desc = 'Debug: Step Over',
    },
    {
      '<F3>',
      step 'step_out',
      desc = 'Debug: Step Out',
    },
    {
      '<F7>',
      function()
        require('dap-view').toggle()
      end,
      desc = 'Debug: Toggle UI',
    },
    {
      '<leader>bb',
      function()
        require('dap').toggle_breakpoint()
      end,
      desc = 'Toggle [B]reakpoint',
    },
    {
      '<leader>bc',
      function()
        require('dap').set_breakpoint(vim.fn.input 'Breakpoint condition: ')
      end,
      desc = '[C]onditional breakpoint',
    },
    {
      '<leader>bL',
      function()
        require('dap').set_breakpoint(nil, nil, vim.fn.input 'Log message: ')
      end,
      desc = 'Breakpoint [L]ogpoint',
    },
    {
      '<leader>bl',
      function()
        require('custom.features.dap-breakpoints').open()
      end,
      desc = '[B]reakpoint [L]ist',
    },
    {
      '<leader>bw',
      '<Cmd>DapViewWatch<CR>',
      desc = '[W]atch expression',
    },
    {
      '<leader>bw',
      ':DapViewWatch<CR>',
      mode = 'v',
      desc = '[W]atch selection',
    },
  },
  config = function()
    local dap = require 'dap'
    local dapview = require 'dap-view'

    require('mason-nvim-dap').setup {
      -- ensure_installed handles upfront install; automatic_installation races
      -- with it whenever an adapter is registered via dap.adapters[...] in the
      -- same session, leaving installs stuck mid-flight (lockfile collision)
      automatic_installation = false,
      handlers = {},
      -- respect the per-machine Mason opt-out (see custom/plugins/lsp.lua):
      -- lightweight boxes without go/dotnet/node can't build these adapters.
      ensure_installed = vim.g.disable_mason_auto_install and {} or { 'delve', 'coreclr', 'debugpy', 'js', 'codelldb' },
    }

    -- single bottom panel with a winbar to switch sections (scopes is the
    -- landing view, matching the old scopes-heavy sidebar). the debuggee
    -- terminal/console sits in its own split alongside. `auto_toggle` opens
    -- the panel on session start and closes it when all sessions finish,
    -- replacing the manual event listeners dap-ui needed
    dapview.setup {
      winbar = {
        show = true,
        sections = { 'watches', 'scopes', 'threads', 'breakpoints', 'exceptions', 'repl' },
        default_section = 'scopes',
        controls = {
          enabled = true,
          position = 'right',
        },
      },
      windows = {
        size = 0.3,
        position = 'below',
        terminal = {
          size = 0.5,
          position = 'left',
          -- Go's delve uses an external terminal; no point reserving a split
          hide = { 'go' },
        },
      },
      -- `o` alongside `<CR>` for expand/jump in every view; threads' default
      -- `o` (invert_filter) moves to `O`
      keymaps = {
        scopes = { toggle = { '<CR>', 'o', '<2-LeftMouse>' } },
        watches = { toggle = { '<CR>', 'o', '<2-LeftMouse>' } },
        hover = { toggle = { '<CR>', 'o', '<2-LeftMouse>' } },
        threads = { invert_filter = 'O', jump_to_frame = { '<CR>', 'o', '<2-LeftMouse>' } },
        exceptions = { toggle_filter = { '<CR>', 'o', '<2-LeftMouse>' } },
        sessions = { switch_session = { '<CR>', 'o', '<2-LeftMouse>' } },
        breakpoints = { jump_to_breakpoint = { '<CR>', 'o', '<2-LeftMouse>' } },
      },
      -- inline variable values next to code (like Rider/GoLand). dap-view's
      -- own implementation, registered against dap's `variables` event, so it
      -- replaces the separate nvim-dap-virtual-text plugin. requires nvim 0.12+
      -- and auto-clears when the session terminates
      virtual_text = {
        enabled = true,
      },
      auto_toggle = true,
    }

    -- breakpoint icons
    vim.api.nvim_set_hl(0, 'DapBreak', { fg = '#e51400' })
    vim.api.nvim_set_hl(0, 'DapStop', { fg = '#ffcc00' })
    local breakpoint_icons = vim.g.have_nerd_font and { Breakpoint = '', BreakpointCondition = '', BreakpointRejected = '', LogPoint = '', Stopped = '' }
      or { Breakpoint = '●', BreakpointCondition = '⊜', BreakpointRejected = '⊘', LogPoint = '◆', Stopped = '⭔' }
    for type, icon in pairs(breakpoint_icons) do
      local tp = 'Dap' .. type
      local hl = (type == 'Stopped') and 'DapStop' or 'DapBreak'
      vim.fn.sign_define(tp, { text = icon, texthl = hl, numhl = hl })
    end

    require('dap-go').setup {
      delve = {
        detached = vim.fn.has 'win32' == 0,
      },
    }

    -- attach to an already-running process via a headless delve. start it
    -- yourself with one of:
    --   dlv attach <pid> --headless --listen=127.0.0.1:38697 --api-version=2
    --   dlv exec ./binary --headless --listen=127.0.0.1:38697 --api-version=2
    -- this is the only working path for TUI binaries: delve's DAP server
    -- ignores `console: integratedTerminal` when actually debugging (only
    -- honoured for noDebug runs), and `dlv dap` has no `--tty` flag, so a
    -- pure-launch flow always gives the debuggee pipe-based stdio. using
    -- `dlv debug --tty=<pty>` in headless mode + this attach config is the
    -- workaround if you want delve to launch the binary against a real PTY
    dap.configurations.go = dap.configurations.go or {}
    table.insert(dap.configurations.go, {
      type = 'go',
      name = 'Attach (remote dlv)',
      request = 'attach',
      mode = 'remote',
      host = '127.0.0.1',
      port = function()
        return tonumber(vim.fn.input 'dlv headless port: ' or '') or 38697
      end,
    })

    -- point dap-python at Mason's debugpy venv so it doesn't depend on a
    -- project-local venv being active. nvim-dap-python falls back to the
    -- project venv automatically when one is detected
    require('dap-python').setup(vim.fn.stdpath 'data' .. '/mason/packages/debugpy/venv/bin/python')

    -- JS/TS debugger (vscode-js-debug via Mason). `${port}` makes nvim-dap
    -- pick a free port per session and spawn the adapter as a child, so a
    -- crashed session can't leave an orphan squatting on a fixed port.
    -- neotest-vitest's `strategy = 'dap'` picks this up automatically
    local js_debug_server = vim.fn.stdpath 'data' .. '/mason/packages/js-debug-adapter/js-debug/src/dapDebugServer.js'
    for _, adapter in ipairs { 'pwa-node', 'pwa-chrome', 'pwa-msedge', 'node-terminal', 'pwa-extensionHost' } do
      dap.adapters[adapter] = {
        type = 'server',
        host = 'localhost',
        port = '${port}',
        executable = {
          command = 'node',
          args = { js_debug_server, '${port}' },
        },
      }
    end

    -- codelldb (via Mason) debugs the native C family and Swift. `${port}` lets
    -- nvim-dap pick a free port per session and spawn the adapter as a child, so
    -- a crashed session can't leave an orphan squatting on a fixed port (same
    -- pattern as the JS adapters above)
    dap.adapters.codelldb = {
      type = 'server',
      port = '${port}',
      executable = {
        command = vim.fn.stdpath 'data' .. '/mason/packages/codelldb/extension/adapter/codelldb',
        args = { '--port', '${port}' },
      },
    }

    -- shared launch config: prompt for the compiled binary. point this at the
    -- product of your build (e.g. `.build/debug/<target>` for SwiftPM, or the
    -- binary clang/cmake emits). compile with debug symbols (`-g`)
    local codelldb_launch = {
      {
        name = 'Launch (codelldb)',
        type = 'codelldb',
        request = 'launch',
        program = function()
          return vim.fn.input('Path to executable: ', vim.fn.getcwd() .. '/', 'file')
        end,
        cwd = '${workspaceFolder}',
        stopOnEntry = false,
        args = {},
      },
    }
    dap.configurations.c = codelldb_launch
    dap.configurations.cpp = codelldb_launch
    dap.configurations.objc = codelldb_launch
    dap.configurations.swift = codelldb_launch
  end,
}
