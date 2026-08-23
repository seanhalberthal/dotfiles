-- date-ordered listing and navigation for note directories whose filenames carry
-- a DD-MM-YYYY stamp.
--
-- the ordering key is the filename, not the directory: oil's sort columns are
-- handed one entry at a time with no bufnr and no parent path (see
-- oil/view.lua render_buffer -> get_sort_function), so a per-directory sort spec
-- isn't expressible. keying off the name gets the same effect emergently, a
-- directory of dated names orders newest-first, one with none ties on the
-- undated sentinel and falls through to oil's existing name sort untouched.
--
-- the stamp can sit anywhere in the basename: some notes are prefixed with an
-- emoji, others are bare

local M = {}

-- undated siblings are a directory's index and topic notes; under `desc` this
-- floats them above the dated stream instead of burying them beneath a hundred
-- dated files
local UNDATED = math.huge

---@param name string
---@return integer|nil -- YYYYMMDD, sortable as a plain number
function M.date_value(name)
  local d, m, y = name:match '(%d%d)%-(%d%d)%-(%d%d%d%d)'
  if not d then
    return nil
  end
  d, m, y = tonumber(d), tonumber(m), tonumber(y)
  if m < 1 or m > 12 or d < 1 or d > 31 then
    return nil
  end
  return y * 10000 + m * 100 + d
end

-- `type` first keeps directories pinned above files regardless of the date key
M.oil_sort = { { 'type', 'asc' }, { 'notedate', 'desc' }, { 'name', 'asc' } }

-- register the sort key oil.view_options.sort refers to. sort-only, same shape
-- as oil's own `name` column: never listed in `columns`, so render/parse are
-- unreachable and error rather than pretend
function M.setup_oil()
  local columns = require 'oil.columns'
  local FIELD_NAME = require('oil.constants').FIELD_NAME
  columns.register('notedate', {
    render = function()
      error 'notedate is a sort-only column'
    end,
    parse = function()
      error 'notedate is a sort-only column'
    end,
    get_sort_value = function(entry)
      return M.date_value(entry[FIELD_NAME]) or UNDATED
    end,
  })
end

-- dated files alongside `path`, oldest first
---@param path string
---@return string|nil dir, string[]|nil basenames
local function dated_siblings(path)
  local dir = vim.fn.fnamemodify(path, ':p:h')
  local handle = vim.uv.fs_scandir(dir)
  if not handle then
    return nil, nil
  end
  local files = {}
  while true do
    local name, fs_type = vim.uv.fs_scandir_next(handle)
    if not name then
      break
    end
    if fs_type ~= 'directory' and M.date_value(name) then
      table.insert(files, name)
    end
  end
  table.sort(files, function(a, b)
    local da, db = M.date_value(a), M.date_value(b)
    if da ~= db then
      return da < db
    end
    return a < b
  end)
  return dir, files
end

-- mini.bracketed's own ]f/[f walks the directory lexicographically
-- (H.get_file_data sorts basenames with `x:lower() < y:lower()` and offers no
-- comparator hook), which for DD-MM-YYYY names orders by day-of-month. walk the
-- dates instead: ]f is a newer note, [f an older one. undated siblings are
-- skipped, they aren't part of the timeline
---@param direction 'forward'|'backward'|'first'|'last'
local function jump(direction)
  local bufname = vim.api.nvim_buf_get_name(0)
  local dir, files = dated_siblings(bufname)
  if not files or #files == 0 then
    return
  end

  local cur = vim.fn.fnamemodify(bufname, ':t')
  local cur_idx
  for i, name in ipairs(files) do
    if name == cur then
      cur_idx = i
      break
    end
  end

  local n = #files
  local iterator = {
    next = function(i)
      if i == nil then
        return 1
      end
      if i >= n then
        return nil
      end
      return i + 1
    end,
    prev = function(i)
      if i == nil then
        return n
      end
      if i <= 1 then
        return nil
      end
      return i - 1
    end,
    state = cur_idx,
    start_edge = 0,
    end_edge = n + 1,
  }

  local res_idx = MiniBracketed.advance(iterator, direction, { n_times = vim.v.count1, wrap = true })
  if res_idx == nil or res_idx == cur_idx then
    return
  end
  vim.cmd.edit(vim.fn.fnameescape(dir .. '/' .. files[res_idx]))
end

-- shadow ]f/[f only on buffers that are themselves dated, so index and topic
-- notes keep mini.bracketed's directory walk
function M.setup_bracketed()
  vim.api.nvim_create_autocmd({ 'BufReadPost', 'BufNewFile' }, {
    group = vim.api.nvim_create_augroup('DatedNotesBracketed', { clear = true }),
    callback = function(ev)
      if not M.date_value(vim.fn.fnamemodify(vim.api.nvim_buf_get_name(ev.buf), ':t')) then
        return
      end
      vim.keymap.set('n', ']f', function()
        jump 'forward'
      end, { buffer = ev.buf, desc = 'Next note by date' })
      vim.keymap.set('n', '[f', function()
        jump 'backward'
      end, { buffer = ev.buf, desc = 'Previous note by date' })
    end,
  })
end

return M
