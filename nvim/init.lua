--[[
  nvim configuration

  structure:
    lua/custom/core/      - core settings (options, keymaps, autocmds)
    lua/custom/plugins/   - plugin configurations
    lua/kickstart/        - kickstart-provided plugins

  see lua/custom/core/keymaps.lua for keybindings
  press <Space>h for quick reference
--]]

-- load core configuration
require('custom.core.options').setup()
require('custom.core.keymaps').setup()
require('custom.core.autocmds').setup()
require('custom.features.tag-rename').setup()

-- bootstrap and load plugins
require('custom.lazy-bootstrap').setup()

-- apply colourscheme before plugins load so gitsigns, differ, etc.
-- pick up the correct highlight groups during their own setup
require('custom.core.theme').setup()

-- user overrides (not managed by dotfiles, survives dotfiles update).
-- loaded BEFORE lazy.setup so plugin specs can read user-set `vim.g.*`
-- (e.g. `vim.g.obsidian_vault_root`). things that depend on a plugin being
-- loaded (`require('plugin')...`) should be wrapped in `vim.schedule(...)`
-- or a `VimEnter` autocmd inside local.lua
local local_config = vim.fn.stdpath 'config' .. '/local.lua'
if vim.uv.fs_stat(local_config) then
  dofile(local_config)
end

require('lazy').setup({
  -- custom plugins
  { import = 'custom.plugins' },

  -- kickstart plugins (neo-tree, autopairs, gitsigns, indent guides)
  { import = 'kickstart.plugins' },
}, {
  ui = {
    icons = vim.g.have_nerd_font and {} or {
      cmd = '⌘',
      config = '🛠',
      event = '📅',
      ft = '📂',
      init = '⚙',
      keys = '🗝',
      plugin = '🔌',
      runtime = '💻',
      require = '🌙',
      source = '📄',
      start = '🚀',
      task = '📌',
      lazy = '💤 ',
    },
  },
})
