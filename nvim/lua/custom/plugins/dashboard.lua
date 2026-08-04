-- Dashboard: snacks.nvim startup screen

--- resolved foreground of a highlight group, following links
---@param group string
---@return integer?
local function fg_of(group)
  return vim.api.nvim_get_hl(0, { name = group, link = false }).fg
end

-- snacks only hides the statusline for the dashboard it opens at startup, and
-- restores it the first time another window is entered. a dashboard opened
-- after that (oil_close re-rendering it, say) gets a statusline drawn over it,
-- so mirror the hide on the dashboard's own lifecycle events
local saved_laststatus

local function hide_statusline()
  if vim.o.laststatus ~= 0 then
    saved_laststatus = vim.o.laststatus
    vim.o.laststatus = 0
  end
end

local function restore_statusline()
  if saved_laststatus then
    vim.o.laststatus, saved_laststatus = saved_laststatus, nil
  end
end

--- set dashboard highlight groups by linking to standard vim groups.
--- called on load and on every ColorScheme change so highlights
--- stay in sync with dotfiles theme switching
local function set_dashboard_highlights()
  local links = {
    SnacksDashboardHeader = 'Keyword',
    SnacksDashboardIcon = 'Function',
    SnacksDashboardKey = 'Number',
    SnacksDashboardTitle = 'Title',
    SnacksDashboardFooter = 'Comment',
    SnacksDashboardDir = 'NonText',
    SnacksDashboardNormal = 'Normal',
    SnacksDashboardTerminal = 'Normal',
  }
  for group, target in pairs(links) do
    vim.api.nvim_set_hl(0, group, { link = target })
  end

  -- colour only, never a link: Special is a syntax role, so a theme is free to
  -- attach attributes to it (dracula italicises it) and a link would inherit them
  local special = fg_of 'Special' or fg_of 'Normal'
  for _, group in ipairs { 'SnacksDashboardDesc', 'SnacksDashboardFile', 'SnacksDashboardSpecial' } do
    vim.api.nvim_set_hl(0, group, { fg = special })
  end
end

return {
  {
    'folke/snacks.nvim',
    priority = 1000,
    lazy = false,
    ---@type snacks.Config
    opts = {
      -- only enable the dashboard module
      bigfile = { enabled = false },
      dashboard = {
        enabled = true,
        width = 70,
        preset = {
          header = table.concat({
            '            ▗     ',
            '▛▀▖▞▀▖▞▀▖▌ ▌▄ ▛▚▀▖',
            '▌ ▌▛▀ ▌ ▌▐▐ ▐ ▌▐ ▌',
            '▘ ▘▝▀▘▝▀  ▘ ▀▘▘▝ ▘',
          }, '\n'),
          -- stylua: ignore
          keys = {
            { icon = '', key = 'f', desc = 'Find File',    action = ":lua Snacks.dashboard.pick('files')" },
            { icon = '', key = 'n', desc = 'New File',     action = ':ene | startinsert' },
            { icon = '󰺯', key = 'g', desc = 'Find Text',    action = ":lua Snacks.dashboard.pick('live_grep')" },
            { icon = '', key = 'r', desc = 'Recent Files', action = ":lua Snacks.dashboard.pick('oldfiles')" },
            { icon = '', key = 'p', desc = 'PRs',          action = ":Octo pr list" },
            { icon = '', key = 'c', desc = 'Config',       action = ":lua Snacks.dashboard.pick('files', {cwd = vim.fn.stdpath('config')})" },
            { icon = '󰒲 ', key = 'L', desc = 'Lazy',        action = ':Lazy' },
            { icon = '󰩈', key = 'q', desc = 'Quit',         action = ':qa' },
          },
        },
        sections = {
          { section = 'header', padding = 2 },
          {
            section = 'keys',
            gap = 1,
            padding = 1,
          },
          {
            title = 'Recent Files',
            section = 'recent_files',
            cwd = true,
            indent = 2,
            padding = 1,
          },
          {
            title = 'Projects',
            section = 'projects',
            indent = 2,
            padding = 1,
          },
          { section = 'startup' },
        },
      },
      notifier = { enabled = false },
      quickfile = { enabled = false },
      statuscolumn = { enabled = false },
      styles = {
        dashboard = {
          row = 0,
          height = function()
            return vim.o.lines - vim.o.cmdheight - (vim.o.laststatus >= 2 and 1 or 0)
          end,
        },
      },
      words = { enabled = false },
    },
    config = function(_, opts)
      require('snacks').setup(opts)

      -- apply highlights now and re-apply on every theme change
      set_dashboard_highlights()
      vim.api.nvim_create_autocmd('ColorScheme', {
        group = vim.api.nvim_create_augroup('SnacksDashboardTheme', { clear = true }),
        callback = set_dashboard_highlights,
      })

      local statusline_group = vim.api.nvim_create_augroup('SnacksDashboardStatusline', { clear = true })
      vim.api.nvim_create_autocmd('User', {
        pattern = 'SnacksDashboardOpened',
        group = statusline_group,
        callback = hide_statusline,
      })
      vim.api.nvim_create_autocmd('User', {
        pattern = 'SnacksDashboardClosed',
        group = statusline_group,
        callback = restore_statusline,
      })
    end,
  },
}
