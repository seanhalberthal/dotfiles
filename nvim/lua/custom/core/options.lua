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
  -- blank tab: indent-blankline draws leading indentation, so a glyph here only
  -- shows up where ibl doesn't paint. two spaces, not omitted; omitting it with
  -- `list` on falls back to `^I`
  vim.opt.listchars = { tab = '  ', trail = '·', nbsp = '␣' }

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

  -- on a headless box (bare ssh, no display server, no tmux) nvim finds no
  -- clipboard tool at all: xsel/xclip are only considered when $DISPLAY is set,
  -- and nvim's own OSC 52 fallback is deliberately skipped whenever 'clipboard'
  -- is non-empty (see provider/clipboard.vim). inside tmux the tmux provider
  -- already covers this, so only standalone nvim needs a provider declared.
  --
  -- copy goes out over OSC 52, which reaches the real clipboard on whichever
  -- machine the terminal is running on. paste reads a local cache file instead
  -- of OSC 52: a clipboard *read* blocks for up to 10s waiting on a response
  -- most terminals never send, and with `unnamedplus` that would stall every
  -- `p`. the cache is what keeps yanks shared across instances here.
  local has_clipboard = vim.env.DISPLAY or vim.env.WAYLAND_DISPLAY or vim.env.TMUX or vim.fn.has 'mac' == 1
  if not has_clipboard then
    local osc52 = require 'vim.ui.clipboard.osc52'
    local cache = vim.fn.stdpath 'cache' .. '/clipboard'

    local function copy(reg)
      local send = osc52.copy(reg)
      return function(lines, regtype)
        send(lines)
        -- regtype rides along as the first line so blockwise/linewise yanks
        -- paste back with the shape they were yanked with
        pcall(vim.fn.writefile, vim.list_extend({ regtype or 'v' }, lines), cache)
      end
    end

    local function paste()
      local ok, lines = pcall(vim.fn.readfile, cache)
      if not ok or type(lines) ~= 'table' or #lines == 0 then
        return { {}, 'v' }
      end
      local regtype = table.remove(lines, 1)
      return { lines, regtype }
    end

    vim.g.clipboard = {
      name = 'osc52+cache',
      copy = { ['+'] = copy '+', ['*'] = copy '*' },
      paste = { ['+'] = paste, ['*'] = paste },
    }
  end

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
