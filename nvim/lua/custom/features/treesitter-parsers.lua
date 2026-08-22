-- nvim-treesitter parser maintenance. extracted from plugins/treesitter.lua.
-- purge_if_updated() runs before install(): it drops compiled parsers (and their
-- orphaned query dirs) when the plugin rev changes to avoid ABI crashes, and
-- removes nvim-treesitter copies of parsers bundled with nvim so nvim's own
-- always-compatible versions win, and clears stale binaries from the legacy
-- plugin-dir parser location

local M = {}

--- purge stale compiled parsers on a plugin update, then strip nvim-bundled
--- parser copies. idempotent; safe to call on every startup
function M.purge_if_updated()
  -- purge compiled parsers when nvim-treesitter updates to prevent ABI crashes.
  -- old .so files compiled against a previous treesitter ABI can crash nvim
  -- when opened (e.g. markdown, c_sharp after breaking updates). remove the
  -- matching query directories too, otherwise health checks report orphaned
  -- queries for parsers that no longer exist on disk
  local parser_dir = vim.fn.stdpath 'data' .. '/site/parser'
  local query_dir = vim.fn.stdpath 'data' .. '/site/queries'
  local marker_path = vim.fn.stdpath 'data' .. '/nvim-treesitter-rev'
  local plugin_dir = vim.fn.stdpath 'data' .. '/lazy/nvim-treesitter'
  -- argv form, no shell: shell diagnostics once leaked into the captured rev
  -- and poisoned the marker file. --git-dir neutralises any inherited GIT_DIR
  -- (an empty env override makes git fail outright). only trust a hex rev
  local res = vim.system({ 'git', '-C', plugin_dir, '--git-dir', '.git', 'rev-parse', '--short', 'HEAD' }):wait()
  local out = res.code == 0 and vim.trim(res.stdout or '') or ''
  local current_rev = out:match '^%x+$' and out or ''
  if current_rev ~= '' then
    local stored_rev = ''
    local f = io.open(marker_path, 'r')
    if f then
      stored_rev = f:read '*a' or ''
      f:close()
      stored_rev = stored_rev:gsub('%s+', '')
    end
    if stored_rev ~= current_rev then
      -- plugin updated, purge all compiled parsers so they reinstall cleanly
      local stat = vim.uv.fs_stat(parser_dir)
      if stat and stat.type == 'directory' then
        local handle = vim.uv.fs_scandir(parser_dir)
        if handle then
          while true do
            local name, typ = vim.uv.fs_scandir_next(handle)
            if not name then
              break
            end
            if typ == 'file' and name:match '%.so$' then
              os.remove(parser_dir .. '/' .. name)
              local lang = name:gsub('%.so$', '')
              local qdir = query_dir .. '/' .. lang
              if vim.uv.fs_stat(qdir) then
                vim.fn.delete(qdir, 'rf')
              end
            end
          end
        end
        vim.notify('nvim-treesitter updated — reinstalling parsers', vim.log.levels.INFO)
      end
      -- write new marker
      f = io.open(marker_path, 'w')
      if f then
        f:write(current_rev)
        f:close()
      end
    end
  end

  -- remove any nvim-treesitter-managed copies of parsers bundled with nvim
  -- so that nvim's own (always-compatible) versions take precedence
  local nvim_bundled = { 'lua', 'luadoc', 'vim', 'vimdoc', 'query', 'markdown', 'markdown_inline' }
  for _, lang in ipairs(nvim_bundled) do
    local so = parser_dir .. '/' .. lang .. '.so'
    if vim.uv.fs_stat(so) then
      os.remove(so)
    end
  end

  -- the plugin dir is a legacy parser location (main installs to site). stale
  -- binaries there shadow the install dir, satisfy the missing-parser probe,
  -- and are invisible to the rev purge above, so drop every .so found
  local legacy_dir = plugin_dir .. '/parser'
  local scan = vim.uv.fs_scandir(legacy_dir)
  if scan then
    while true do
      local name, typ = vim.uv.fs_scandir_next(scan)
      if not name then
        break
      end
      if typ == 'file' and name:match '%.so$' then
        os.remove(legacy_dir .. '/' .. name)
      end
    end
  end
end

--- point a parser at a source other than nvim-treesitter's default and keep the
--- compiled binary in step with it. the install probe in plugins/treesitter.lua
--- only reinstalls a parser it can't find, so a changed revision has to drop the
--- .so itself; dropping a pin restores the upstream parser the same way.
--- markers are written before the install runs, but a failed install leaves no
--- parser for the probe to find, so it retries on the next start
--- @param pins table<string, {url: string, revision: string}>
function M.sync_pins(pins)
  local parser_dir = vim.fn.stdpath 'data' .. '/site/parser'
  local query_dir = vim.fn.stdpath 'data' .. '/site/queries'
  local marker_dir = vim.fn.stdpath 'data' .. '/nvim-treesitter-pins'
  vim.fn.mkdir(marker_dir, 'p')

  local function purge(lang)
    os.remove(parser_dir .. '/' .. lang .. '.so')
    if vim.uv.fs_stat(query_dir .. '/' .. lang) then
      vim.fn.delete(query_dir .. '/' .. lang, 'rf')
    end
  end

  local function marker(lang)
    return marker_dir .. '/' .. lang
  end

  local function read_marker(lang)
    local f = io.open(marker(lang), 'r')
    if not f then
      return nil
    end
    local rev = f:read '*a' or ''
    f:close()
    return vim.trim(rev)
  end

  -- install() clears the parser table from package.loaded and re-requires it
  -- before resolving a source, which drops a plain mutation. package.preload is
  -- checked ahead of the path searchers, so handing the pinned table back from
  -- there survives every reload
  local parsers = require 'nvim-treesitter.parsers'
  for lang, pin in pairs(pins) do
    if parsers[lang] then
      parsers[lang].install_info = { url = pin.url, revision = pin.revision }
    end
  end
  package.preload['nvim-treesitter.parsers'] = function()
    return parsers
  end

  for lang, pin in pairs(pins) do
    if read_marker(lang) ~= pin.revision then
      purge(lang)
      local f = io.open(marker(lang), 'w')
      if f then
        f:write(pin.revision)
        f:close()
      end
    end
  end

  -- a marker with no matching pin is a parser that was pinned and isn't any
  -- more, so it still holds the pinned build; purge it back to upstream
  local scan = vim.uv.fs_scandir(marker_dir)
  while scan do
    local name = vim.uv.fs_scandir_next(scan)
    if not name then
      break
    end
    if not pins[name] then
      purge(name)
      os.remove(marker(name))
    end
  end
end

return M
