-- highlight go format verbs (`%s`, `%d`, `%t`) inside printf-family calls.
--
-- treesitter captures whole nodes, so no query can pick verbs out of a string
-- literal, and the printf grammar nvim-treesitter injects for that job is a c
-- grammar: go's `%t` and `%w` are c length modifiers rather than conversions,
-- so its format node runs on past them to the next conversion character and
-- swallows the text between. this walks the go tree instead and marks go's own
-- verb set directly

local M = {}

local ns = vim.api.nvim_create_namespace 'go-format-verbs'

-- above semantic tokens (125) so a server's string token can't cover a verb
local PRIORITY = 126

local VERBS = {}
for ch in ('vTtbcdoOqxXUeEfFgGspw'):gmatch '.' do
  VERBS[ch] = true
end

-- split by where the format string sits: the first argument for most, the
-- second for the ones that take a writer, reader or buffer first.
--
-- the names are vet's printf list plus the structured loggers vet knows
-- nothing about (logrus, zap's sugar, klog, glog, zerolog's Msgf), so a
-- `Warnf` next to an `Errorf` doesn't come out a different colour. it stays an
-- explicit list rather than matching any method ending in `f`: the scanner
-- would then read strings that are not format strings, and `Conf("100% off")`
-- has a space flag and an `o` verb in it
local QUERY = [[
  ((call_expression
    function: (selector_expression
      field: (field_identifier) @_method)
    arguments: (argument_list
      .
      [
        (interpreted_string_literal
          (interpreted_string_literal_content) @content)
        (raw_string_literal
          (raw_string_literal_content) @content)
      ]))
    (#any-of? @_method
      "Printf" "Sprintf" "Errorf" "Fatalf" "Panicf" "Logf" "Skipf" "Scanf"
      "Infof" "Warnf" "Warningf" "Debugf" "Tracef" "Noticef" "Criticalf" "Msgf"))

  ((call_expression
    function: (selector_expression
      field: (field_identifier) @_method)
    arguments: (argument_list
      (_)
      .
      [
        (interpreted_string_literal
          (interpreted_string_literal_content) @content)
        (raw_string_literal
          (raw_string_literal_content) @content)
      ]))
    (#any-of? @_method "Fprintf" "Fscanf" "Appendf" "Sscanf"))
]]

local query

--- byte ranges of every format verb in `s`, 0-based and end-exclusive.
--- a verb is `%`, flags, an optional `[n]` argument index, width, precision,
--- then the verb letter; `%%` is a literal percent and is skipped
---@param s string
---@return integer[][]
local function verb_ranges(s)
  local out, i = {}, 1
  while true do
    local pct = s:find('%%', i)
    if not pct then
      return out
    end
    local j = pct + 1
    if s:sub(j, j) == '%' then
      i = j + 1
    else
      while s:sub(j, j):match '[-+# 0]' do
        j = j + 1
      end
      local index = s:match('^%[%d+%]', j)
      if index then
        j = j + #index
      end
      if s:sub(j, j) == '*' then
        j = j + 1
      else
        while s:sub(j, j):match '%d' do
          j = j + 1
        end
      end
      if s:sub(j, j) == '.' then
        j = j + 1
        if s:sub(j, j) == '*' then
          j = j + 1
        else
          while s:sub(j, j):match '%d' do
            j = j + 1
          end
        end
      end
      if VERBS[s:sub(j, j)] then
        out[#out + 1] = { pct - 1, j }
        i = j + 1
      else
        i = pct + 1
      end
    end
  end
end

--- mark every verb in one string-content node. a raw string can hold newlines,
--- so each of its lines is scanned against its own buffer row
---@param buf integer
---@param node TSNode
local function mark(buf, node)
  local srow, scol = node:start()
  local text = vim.treesitter.get_node_text(node, buf)
  for k, line in ipairs(vim.split(text, '\n', { plain = true })) do
    local base = k == 1 and scol or 0
    for _, range in ipairs(verb_ranges(line)) do
      pcall(vim.api.nvim_buf_set_extmark, buf, ns, srow + k - 1, base + range[1], {
        end_col = base + range[2],
        hl_group = '@string.special',
        priority = PRIORITY,
      })
    end
  end
end

-- match the ceiling plugins/treesitter.lua puts on `vim.treesitter.start`: past
-- it there is no highlighting to decorate, and parsing a generated file the
-- config deliberately skipped would be the expensive half of what it avoided.
-- measured from the buffer rather than fs_stat, which would miss unsaved edits
-- and touch disk on every debounce
local MAX_BYTES = 1024 * 1024

---@param buf integer
local function refresh(buf)
  if not vim.api.nvim_buf_is_valid(buf) or vim.bo[buf].filetype ~= 'go' then
    return
  end
  if vim.api.nvim_buf_get_offset(buf, vim.api.nvim_buf_line_count(buf)) > MAX_BYTES then
    return
  end
  vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)

  local ok, parser = pcall(vim.treesitter.get_parser, buf, 'go')
  if not ok or not parser then
    return
  end
  local tree = parser:parse()[1]
  if not tree then
    return
  end
  if not query then
    local parsed
    ok, parsed = pcall(vim.treesitter.query.parse, 'go', QUERY)
    if not ok then
      return
    end
    query = parsed
  end

  for id, node in query:iter_captures(tree:root(), buf) do
    if query.captures[id] == 'content' then
      mark(buf, node)
    end
  end
end

local timers = {}

--- coalesce redraws while typing; a keystroke-rate full-buffer pass is wasted
--- work when only the line under the cursor can have changed
---@param buf integer
local function schedule(buf)
  local timer = timers[buf]
  if not timer then
    timer = vim.uv.new_timer()
    timers[buf] = timer
  end
  timer:stop()
  timer:start(
    120,
    0,
    vim.schedule_wrap(function()
      refresh(buf)
    end)
  )
end

---@param buf integer
local function release(buf)
  local timer = timers[buf]
  if timer then
    timer:stop()
    timer:close()
    timers[buf] = nil
  end
end

function M.setup()
  local group = vim.api.nvim_create_augroup('go-format-verbs', { clear = true })

  vim.api.nvim_create_autocmd('FileType', {
    desc = 'Highlight Go format verbs',
    group = group,
    pattern = 'go',
    callback = function(ev)
      refresh(ev.buf)
    end,
  })

  vim.api.nvim_create_autocmd({ 'TextChanged', 'TextChangedI', 'InsertLeave' }, {
    desc = 'Refresh Go format verb highlights',
    group = group,
    pattern = '*.go',
    callback = function(ev)
      schedule(ev.buf)
    end,
  })

  vim.api.nvim_create_autocmd({ 'BufUnload', 'BufDelete' }, {
    desc = 'Drop the Go format verb debounce timer',
    group = group,
    pattern = '*.go',
    callback = function(ev)
      release(ev.buf)
    end,
  })
end

return M
