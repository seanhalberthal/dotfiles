-- Core Neovim options
-- See :help vim.o and :help vim.g

local M = {}

function M.setup()
  -- Leader key (must be set before plugins load)
  vim.g.mapleader = ' '
  vim.g.maplocalleader = ' '

  -- Nerd Font availability
  vim.g.have_nerd_font = false

  -- Line numbers
  vim.o.number = true
  vim.o.relativenumber = true

  -- Mouse support
  vim.o.mouse = 'a'

  -- Don't show mode in command line (shown in statusline)
  vim.o.showmode = false

  -- Sync clipboard between OS and Neovim
  -- Schedule after UiEnter to avoid increasing startup time
  vim.schedule(function()
    vim.o.clipboard = 'unnamedplus'
  end)

  -- Indentation
  vim.o.breakindent = true

  -- Persistent undo
  vim.o.undofile = true

  -- Search
  vim.o.ignorecase = true
  vim.o.smartcase = true

  -- UI
  vim.o.signcolumn = 'yes'
  vim.o.updatetime = 250
  vim.o.timeoutlen = 300

  -- Window splitting
  vim.o.splitright = true
  vim.o.splitbelow = true

  -- Whitespace characters
  vim.o.list = true
  vim.opt.listchars = { tab = '» ', trail = '·', nbsp = '␣' }

  -- Live substitution preview
  vim.o.inccommand = 'split'

  -- Cursor line
  vim.o.cursorline = true

  -- Scroll offset
  vim.o.scrolloff = 10

  -- Confirm before closing unsaved buffers
  vim.o.confirm = true

  -- Cursor style (block in all modes, blinking in insert)
  vim.opt.guicursor = 'n-v-c:block,i-ci-ve:block-blinkwait700-blinkon400-blinkoff250'
end

return M
