-- obsidian vault integration: daily notes, backlinks, tags, templates.
-- markdown rendering and list/link editing stay in markdown-ui.lua
-- (render-markdown + mkdnflow + conceallevel); obsidian.nvim is kept to
-- vault-aware features.
--
-- vault root resolution (in order):
--   1. `vim.g.obsidian_vault_root`: set in ~/.config/nvim/local.lua to override
--   2. ~/obsidian: default path
--   3. neither exists: plugin spec is empty, obsidian.nvim is not loaded
--
-- the resolved root can either be a vault itself (has `.obsidian/` directly
-- inside, e.g. `~/notes/.obsidian`) or a parent directory containing one or
-- more vaults (e.g. `~/vaults/work/.obsidian`, `~/vaults/personal/.obsidian`).

local function resolve_vault_root()
  local override = vim.g.obsidian_vault_root
  if override and override ~= '' then
    local path = vim.fn.expand(override)
    if vim.fn.isdirectory(path) == 1 then
      return path
    end
    vim.notify(('obsidian.nvim: vim.g.obsidian_vault_root=%q not found, skipping'):format(override), vim.log.levels.WARN)
    return nil
  end

  local default = vim.fn.expand '~/obsidian'
  if vim.fn.isdirectory(default) == 1 then
    return default
  end
  return nil
end

local vault_root = resolve_vault_root()
if not vault_root then
  return {}
end

-- `vault_root` can either be a vault itself (has `.obsidian/` directly inside)
-- or a parent directory containing one or more vaults. handle both.
local function discover_workspaces()
  local workspaces = {}
  if vim.fn.isdirectory(vault_root .. '/.obsidian') == 1 then
    table.insert(workspaces, { name = vim.fn.fnamemodify(vault_root, ':t'), path = vault_root })
    return workspaces
  end
  for _, dir in ipairs(vim.fn.glob(vault_root .. '/*', false, true)) do
    local name = vim.fn.fnamemodify(dir, ':t')
    if vim.fn.isdirectory(dir) == 1 and vim.fn.isdirectory(dir .. '/.obsidian') == 1 and not name:match '%.backup' then
      table.insert(workspaces, { name = name, path = dir })
    end
  end
  return workspaces
end

local workspaces = discover_workspaces()
if #workspaces == 0 then
  vim.notify(
    ('obsidian.nvim: no vaults found under %q (expected `.obsidian/` directly inside, or in an immediate subdirectory) — skipping'):format(vault_root),
    vim.log.levels.WARN
  )
  return {}
end

return {
  {
    'obsidian-nvim/obsidian.nvim',
    version = '*',
    ft = { 'markdown' },
    cmd = { 'Obsidian' },
    keys = {
      { '<leader>oo', '<cmd>Obsidian today<cr>', desc = '[O]pen daily note' },
      { '<leader>oy', '<cmd>Obsidian yesterday<cr>', desc = '[Y]esterday daily note' },
      { '<leader>oT', '<cmd>Obsidian tomorrow<cr>', desc = '[T]omorrow daily note' },
      {
        '<leader>on',
        function()
          local ok, api = pcall(require, 'obsidian.api')
          if ok and api.templates_dir() then
            vim.cmd 'Obsidian new_from_template'
          else
            vim.ui.input({ prompt = 'New note title: ' }, function(title)
              if title and title ~= '' then
                vim.cmd('Obsidian new ' .. vim.fn.fnameescape(title))
              end
            end)
          end
        end,
        desc = '[N]ew note (from template if available)',
      },
      {
        '<leader>oN',
        function()
          vim.ui.input({ prompt = 'New note title: ' }, function(title)
            if title and title ~= '' then
              vim.cmd('Obsidian new ' .. vim.fn.fnameescape(title))
            end
          end)
        end,
        desc = '[N]ew blank note (no template)',
      },
      { '<leader>of', '<cmd>Obsidian quick_switch<cr>', desc = '[F]ind note' },
      { '<leader>og', '<cmd>Obsidian search<cr>', desc = '[G]rep vault' },
      { '<leader>ot', '<cmd>Obsidian tags<cr>', desc = '[T]ags' },
      { '<leader>ob', '<cmd>Obsidian backlinks<cr>', desc = '[B]acklinks' },
      { '<leader>ol', '<cmd>Obsidian links<cr>', desc = '[L]inks in note' },
      { '<leader>oi', '<cmd>Obsidian template<cr>', desc = '[I]nsert template into note' },
      { '<leader>ow', '<cmd>Obsidian workspace<cr>', desc = '[W]orkspace switch' },
      { '<leader>or', '<cmd>Obsidian rename<cr>', desc = '[R]ename note' },
      { '<leader>oe', '<cmd>Obsidian extract_note<cr>', mode = { 'n', 'v' }, desc = '[E]xtract to new note' },
    },
    dependencies = {
      'nvim-lua/plenary.nvim',
      'nvim-telescope/telescope.nvim',
    },
    ---@module 'obsidian'
    ---@type obsidian.config
    opts = {
      legacy_commands = false,
      workspaces = workspaces,

      -- matches .obsidian/daily-notes.json (folder, format, template)
      daily_notes = {
        folder = 'daily',
        date_format = 'DD-MM-YYYY',
        template = 'daily note.md',
        default_tags = { 'daily' },
      },

      templates = {
        folder = 'templates',
        date_format = 'YYYY-MM-DD',
        time_format = 'HH:mm',
      },

      -- completion is served by obsidian.nvim's built-in `obsidian-ls` LSP
      -- server (since v3.16); the old `nvim_cmp`/`blink` switches are
      -- deprecated and removed in 4.0. blink.cmp's `lsp` source picks it up.
      completion = {
        min_chars = 2,
      },

      picker = { name = 'telescope.nvim' },

      -- vault uses [[title]] and ![[embed]] (see templates/daily note.md)
      link = {
        style = 'wiki',
        format = 'shortest',
      },

      -- random/quick notes land in scratchpad; daily_notes override folder
      new_notes_location = 'notes_subdir',
      notes_subdir = 'scratchpad',

      -- filename already is the title for this vault (human-readable names,
      -- wiki+shortest links), so the builtin's `id` field is pure noise,
      -- strip it. aliases are kept only when the note actually has them in
      -- its frontmatter; otherwise the builtin would emit an empty `aliases:`
      -- line on every save.
      frontmatter = {
        sort = false,
        func = function(note)
          local out = require('obsidian.builtin').frontmatter(note)
          out.id = nil
          if not note.aliases or #note.aliases == 0 then
            out.aliases = nil
          end
          return out
        end,
      },

      -- vault uses human-readable titles (e.g. "UI Redesign Ideas.md"),
      -- not Zettel IDs. preserve the title as-is when given; fall back to
      -- a timestamp only if `:Obsidian new` is called with no title.
      note_id_func = function(title)
        if title ~= nil and title ~= '' then
          return title
        end
        return os.date '%Y-%m-%d-%H%M%S'
      end,

      -- render-markdown + mkdnflow + conceallevel already handle display
      ui = { enable = false },

      attachments = { folder = 'attachments' },

      -- for vault notes only: rebind `gf` to obsidian.nvim's link-follow
      -- action, matching what `<CR>` does. two non-obvious things about
      -- the call:
      --   1. `follow_link` doesn't grab the cursor link itself; it
      --      requires the raw link string, otherwise its internal
      --      `parse_link` crashes on a nil.
      --   2. `open_strategy` is used as a literal vim command, not as a
      --      strategy enum (despite what some docs imply), so pass
      --      'edit' / 'vsplit' / 'split', not 'current'.
      callbacks = {
        enter_note = function(note)
          vim.keymap.set('n', 'gf', function()
            local link = require('obsidian.api').cursor_link()
            if not link then
              vim.notify('No link under cursor', vim.log.levels.INFO)
              return
            end
            require('obsidian.actions').follow_link(link, { open_strategy = 'edit' })
          end, { buffer = note.bufnr or 0, desc = 'Follow link (in nvim)' })
        end,
      },
    },
  },
}
