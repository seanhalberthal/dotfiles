--[[
  theme integration module

  reads the current theme from ${XDG_CONFIG_HOME:-~/.config}/dotfiles/current-theme
  and applies the corresponding nvim colourscheme.

  uses vim.uv file watcher for live reload when theme changes
--]]

local M = {}

-- configuration
-- respect XDG_CONFIG_HOME to match shell tooling
local xdg_config = os.getenv 'XDG_CONFIG_HOME' or vim.fn.expand '~/.config'
local config_dir = xdg_config .. '/dotfiles'
local theme_file = config_dir .. '/current-theme'

-- map dotfiles theme names to nvim colourschemes
local theme_map = {
  ['dracula'] = 'dracula',
  ['catppuccin-mocha'] = 'catppuccin-mocha',
  ['tokyo-night'] = 'tokyonight-night',
  ['nord'] = 'nord',
  ['gruvbox-dark'] = 'gruvbox-dark',
  ['solarized-dark'] = 'solarized-dark',
  ['one-dark'] = 'onedark',
  ['monokai'] = 'monokai',
  ['ayu-dark'] = 'ayu-dark',
  ['everforest'] = 'everforest',
  ['kanagawa'] = 'kanagawa',
  ['rose-pine'] = 'rose-pine',
  ['nightfox'] = 'nightfox',
  ['synthwave'] = 'synthwave',
}

-- default fallback
local default_scheme = 'dracula'

--- check whether Ghostty has background transparency enabled.
--- reads both config and local (last-value-wins, matching Ghostty behaviour).
---@return boolean
local function ghostty_transparent()
  local opacity = 1
  local ghostty_dir = (os.getenv 'XDG_CONFIG_HOME' or vim.fn.expand '~/.config') .. '/ghostty'
  for _, path in ipairs { ghostty_dir .. '/config', ghostty_dir .. '/local' } do
    local f = io.open(path, 'r')
    if f then
      for line in f:lines() do
        local val = line:match '^%s*background%-opacity%s*=%s*([%d%.]+)'
        if val then
          opacity = tonumber(val)
        end
      end
      f:close()
    end
  end
  return opacity < 1
end

--- clear background on key highlight groups for terminal transparency
local function apply_transparency()
  local groups = {
    'Normal',
    'NormalNC',
    'SignColumn',
    'EndOfBuffer',
    'StatusLine',
    'StatusLineNC',
    'TabLine',
    'TabLineFill',
    'MiniStatuslineDevinfo',
    'MiniStatuslineFilename',
    'MiniStatuslineFileinfo',
    'MiniStatuslineInactive',
    'NeoTreeNormal',
    'NeoTreeNormalNC',
  }
  for _, group in ipairs(groups) do
    local existing = vim.api.nvim_get_hl(0, { name = group })
    existing.bg = nil
    vim.api.nvim_set_hl(0, group, existing)
  end
end

-- track current theme to avoid unnecessary reloads
local current_theme = nil

-- file watcher handle
local watcher = nil

--- read the current theme from the dotfiles config
---@return string|nil theme name or nil if file doesn't exist
local function read_theme_file()
  local f = io.open(theme_file, 'r')
  if not f then
    return nil
  end
  local theme = f:read '*l'
  f:close()
  return theme and theme:match '^%s*(.-)%s*$' -- trim whitespace
end

--- apply a colourscheme safely
--- all colourschemes are custom files in nvim/colors/, no plugin loading needed
---@param scheme string colourscheme name
---@return boolean success
local function apply_colourscheme(scheme)
  local ok = pcall(vim.cmd.colorscheme, scheme)
  if ok then
    return true
  end

  -- validate scheme name to prevent path traversal
  if not scheme:match '^[a-z0-9%-]+$' then
    vim.notify(string.format('Invalid colourscheme name: "%s"', scheme), vim.log.levels.WARN)
    return false
  end

  -- try generated colourscheme
  local generated = vim.fn.stdpath 'config' .. '/colors/generated/' .. scheme .. '.lua'
  if vim.fn.filereadable(generated) == 1 then
    local load_ok, load_err = pcall(dofile, generated)
    if load_ok then
      -- dofile() doesn't trigger ColorScheme autocmd (unlike :colorscheme),
      -- so fire it manually so diff-highlights and other autocmds respond
      vim.api.nvim_exec_autocmds('ColorScheme', { pattern = scheme })
      return true
    end
    vim.notify(string.format('Failed to load generated colourscheme "%s": %s', scheme, load_err), vim.log.levels.WARN)
    return false
  end

  vim.notify(string.format('Colourscheme "%s" not found', scheme), vim.log.levels.WARN)
  return false
end

--- reload theme from config file
---@param force boolean|nil force reload even if theme unchanged
function M.reload(force)
  local theme = read_theme_file()

  -- skip if theme hasn't changed (unless forced)
  if not force and theme == current_theme then
    return
  end

  -- use theme_map for hand-crafted themes, fall through to raw name for generated
  local scheme = theme_map[theme] or theme or default_scheme

  local previous = current_theme

  if apply_colourscheme(scheme) then
    current_theme = theme
    -- clear backgrounds when Ghostty transparency is active
    if ghostty_transparent() then
      apply_transparency()
    end
    -- notify on a forced reload or a real change, but not the startup apply
    if force or previous ~= nil then
      vim.notify(string.format('Theme: %s', theme or 'default'), vim.log.levels.INFO)
    end
  end
end

--- get current theme name
---@return string theme name
function M.current()
  return current_theme or read_theme_file() or 'dracula'
end

--- start file watcher for live reload
local function start_watcher()
  -- ensure config directory exists
  if vim.fn.isdirectory(config_dir) == 0 then
    return
  end

  -- create file watcher
  watcher = vim.uv.new_fs_event()
  if not watcher then
    vim.notify('Failed to create theme file watcher', vim.log.levels.WARN)
    return
  end

  -- watch the theme file
  local ok = pcall(function()
    watcher:start(
      theme_file,
      {},
      vim.schedule_wrap(function(watch_err, _, _)
        if watch_err then
          return
        end
        -- small delay to ensure file write is complete.
        -- force the reload: the file only changes on an explicit theme apply,
        -- and a regenerated scheme keeps the same name, so the
        -- skip-if-unchanged guard would otherwise leave stale highlights
        vim.defer_fn(function()
          M.reload(true)
        end, 50)
      end)
    )
  end)

  if not ok then
    -- file might not exist yet, watch directory instead
    watcher:start(
      config_dir,
      {},
      vim.schedule_wrap(function(watch_err, filename, _)
        if watch_err then
          return
        end
        if filename == 'current-theme' then
          vim.defer_fn(function()
            M.reload(true)
          end, 50)
        end
      end)
    )
  end
end

--- stop file watcher
local function stop_watcher()
  if watcher then
    watcher:stop()
    watcher = nil
  end
end

--- setup theme integration
function M.setup()
  -- apply theme on startup
  M.reload()

  -- start file watcher for live reload
  start_watcher()

  -- also reload on FocusGained as backup
  vim.api.nvim_create_autocmd('FocusGained', {
    group = vim.api.nvim_create_augroup('DotfilesTheme', { clear = true }),
    callback = function()
      M.reload()
    end,
  })

  -- create user command for manual reload
  vim.api.nvim_create_user_command('ThemeReload', function()
    M.reload(true)
  end, { desc = 'Reload theme from dotfiles config' })

  -- clean up watcher on exit
  vim.api.nvim_create_autocmd('VimLeavePre', {
    group = 'DotfilesTheme',
    callback = stop_watcher,
  })
end

return M
