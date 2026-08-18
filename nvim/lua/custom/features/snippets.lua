-- snippet browser. telescope picker over everything that can expand in the
-- current buffer: the vscode-format sets blink's default preset serves
-- (friendly-snippets plus ~/.config/nvim/snippets/*.json) and the lua
-- snippets loaded into luasnip, which the completion menu never shows

local M = {}

--- blink's snippet registry, built from the live source opts so search paths
--- and friendly_snippets match what the completion menu actually reads
local function blink_registry()
  local ok, reg = pcall(function()
    local providers = require('blink.cmp.config').sources.providers
    local opts = providers.snippets and providers.snippets.opts or {}
    return require('blink.cmp.sources.snippets.default.registry').new(opts)
  end)
  return ok and reg or nil
end

---@param items table[]
---@param ft string
local function add_blink(items, ft)
  local reg = blink_registry()
  if not reg then
    return
  end
  local seen = {}
  for _, set in ipairs { reg:get_global_snippets(), reg:get_extended_snippets(ft), reg:get_snippets_for_ft(ft) } do
    for _, snip in ipairs(set) do
      local body = type(snip.body) == 'table' and table.concat(snip.body, '\n') or snip.body
      local key = snip.prefix .. '\0' .. body
      if not seen[key] then
        seen[key] = true
        items[#items + 1] = { prefix = snip.prefix, body = body, description = snip.description, source = 'json' }
      end
    end
  end
end

---@param items table[]
---@param ft string
local function add_luasnip(items, ft)
  local ok, ls = pcall(require, 'luasnip')
  if not ok then
    return
  end
  local keys = ft == 'all' and { 'all' } or { 'all', ft }
  for _, key in ipairs(keys) do
    for _, snip in ipairs(ls.get_snippets(key) or {}) do
      local doc = snip:get_docstring()
      -- luasnip defaults dscr to the trigger; drop it rather than print it twice
      local dscr = type(snip.dscr) == 'table' and table.concat(snip.dscr, ' ') or snip.dscr
      items[#items + 1] = {
        prefix = snip.trigger,
        body = type(doc) == 'table' and table.concat(doc, '\n') or tostring(doc),
        description = dscr ~= snip.trigger and dscr or nil,
        source = 'luasnip',
        snip = snip,
      }
    end
  end
end

--- every snippet expandable in a buffer of this filetype, sorted by prefix
---@param ft string
---@return table[]
function M.collect(ft)
  local items = {}
  add_blink(items, ft)
  add_luasnip(items, ft)
  table.sort(items, function(a, b)
    if a.prefix == b.prefix then
      return a.source < b.source
    end
    return a.prefix < b.prefix
  end)
  return items
end

---@param item table
local function expand(item)
  if item.source == 'luasnip' and item.snip then
    require('luasnip').snip_expand(item.snip)
  else
    vim.snippet.expand(item.body)
  end
end

--- open the picker for the current buffer's filetype
function M.pick()
  local ft = vim.bo.filetype
  local items = M.collect(ft)
  if #items == 0 then
    vim.notify('No snippets for filetype ' .. (ft == '' and '(none)' or ft), vim.log.levels.INFO)
    return
  end

  local pickers = require 'telescope.pickers'
  local finders = require 'telescope.finders'
  local previewers = require 'telescope.previewers'
  local actions = require 'telescope.actions'
  local action_state = require 'telescope.actions.state'
  local values = require('telescope.config').values

  local width = 0
  for _, item in ipairs(items) do
    width = math.max(width, vim.fn.strdisplaywidth(item.prefix))
  end

  local displayer = require('telescope.pickers.entry_display').create {
    separator = '  ',
    items = { { width = width }, { width = 8 }, { remaining = true } },
  }

  pickers
    .new({}, {
      prompt_title = 'Snippets (' .. (ft == '' and 'no filetype' or ft) .. ')',
      finder = finders.new_table {
        results = items,
        entry_maker = function(item)
          return {
            value = item,
            ordinal = item.prefix .. ' ' .. (item.description or ''),
            display = function(entry)
              return displayer {
                { entry.value.prefix, 'TelescopeResultsIdentifier' },
                { entry.value.source, 'TelescopeResultsComment' },
                { entry.value.description or '', 'TelescopeResultsComment' },
              }
            end,
          }
        end,
      },
      sorter = values.generic_sorter {},
      previewer = previewers.new_buffer_previewer {
        title = 'Snippet Body',
        define_preview = function(self, entry)
          vim.api.nvim_buf_set_lines(self.state.bufnr, 0, -1, false, vim.split(entry.value.body, '\n', { plain = true }))
          -- highlighter rather than setting filetype: no FileType chain, so
          -- nothing attaches an lsp client to a throwaway preview buffer
          if ft ~= '' then
            require('telescope.previewers.utils').highlighter(self.state.bufnr, ft)
          end
        end,
      },
      attach_mappings = function(bufnr)
        actions.select_default:replace(function()
          local entry = action_state.get_selected_entry()
          actions.close(bufnr)
          if not entry then
            return
          end
          -- deferred so telescope has restored the original window first
          vim.schedule(function()
            vim.cmd.startinsert()
            expand(entry.value)
          end)
        end)
        return true
      end,
    })
    :find()
end

function M.setup()
  vim.api.nvim_create_user_command('Snippets', M.pick, { desc = 'Browse snippets for the current filetype' })
  vim.keymap.set('n', '<leader>sS', M.pick, { desc = '[S]earch [S]nippets' })
end

return M
