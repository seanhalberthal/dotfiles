-- core nvim options
-- see :help vim.o and :help vim.g

local M = {}

function M.setup()
  -- leader key (must be set before plugins load)
  vim.g.mapleader = ' '
  vim.g.maplocalleader = ' '

  -- Nerd Font availability
  vim.g.have_nerd_font = true

  -- line numbers
  vim.o.number = true
  vim.o.relativenumber = true

  -- mouse support
  vim.o.mouse = 'a'

  -- don't show mode in command line (shown in statusline)
  vim.o.showmode = false

  -- indentation
  vim.o.tabstop = 4
  vim.o.breakindent = true

  -- project-local config: source a trusted .nvim.lua from the working
  -- directory (prompts to trust on first load; see :help 'exrc')
  vim.o.exrc = true

  -- persistent undo
  vim.o.undofile = true

  -- disable swap files (undo + autoread + git make them redundant)
  vim.o.swapfile = false

  -- never write backups alongside the file. the default backupdir starts with
  -- `.`, so a write in a local obsidian vault created a locked file
  -- which got replicated to CouchDB, the mac and the phone as a real document,
  -- then tombstoned a moment later. dropping `.` keeps the state dir as the only backup target.
  vim.o.backupdir = vim.fn.stdpath 'state' .. '/backup//'

  -- search
  vim.o.ignorecase = true
  vim.o.smartcase = true

  -- use ripgrep for :grep / :grepadd (quickfix-based workflow)
  if vim.fn.executable 'rg' == 1 then
    vim.o.grepprg = 'rg --vimgrep --smart-case'
    vim.o.grepformat = '%f:%l:%c:%m'
  end

  -- UI
  vim.o.signcolumn = 'yes'
  vim.o.updatetime = 250
  vim.o.timeoutlen = 200
  vim.o.ttimeoutlen = 10 -- fast key code sequences (responsive escape key)
  vim.opt.shortmess:append 'I' -- suppress intro screen (flashes with cmdheight=0)

  -- window splitting
  vim.o.splitright = true
  vim.o.splitbelow = true

  -- whitespace characters
  vim.o.list = true
  vim.opt.listchars = { tab = '» ', trail = '·', nbsp = '␣' }

  -- live substitution preview
  vim.o.inccommand = 'split'

  -- cursor line
  vim.o.cursorline = true

  -- scroll offset
  vim.o.scrolloff = 10

  -- confirm before closing unsaved buffers
  vim.o.confirm = true

  -- auto-reload files changed outside nvim
  vim.o.autoread = true

  -- use the system clipboard by default so yanks/pastes work across
  -- separate nvim instances, including panes inside tmux.
  vim.o.clipboard = 'unnamedplus'

  -- spellcheck
  vim.o.spell = true
  vim.opt.spelllang = { 'en_gb' }
  vim.opt.spelloptions = { 'camel' }
  vim.opt.spellcapcheck = ''

  -- spellfiles: user dictionary (zg adds here) + repo dictionary (shared terms)
  local user_spell_dir = vim.fn.stdpath 'data' .. '/spell'
  vim.fn.mkdir(user_spell_dir, 'p')
  vim.opt.spellfile = {
    user_spell_dir .. '/en.utf-8.add',
    vim.fn.stdpath 'config' .. '/spell/en.utf-8.add',
  }

  -- cursor style (block in all modes, blinking in insert)
  vim.opt.guicursor = 'n-v-c:block,i-ci-ve:block-blinkwait700-blinkon400-blinkoff250'

  -- reclaim the command line row (ui2 msg window handles messages)
  vim.o.cmdheight = 0

  -- experimental UI2: replaces builtin message + cmdline presentation.
  -- messages appear in a floating window that auto-dismisses; cmdline
  -- appears on-demand. use g< or ENTER after a command to see full messages
  require('vim._core.ui2').enable {
    msg = {
      targets = 'msg',
      msg = {
        timeout = 4000,
      },
    },
  }
end

return M
