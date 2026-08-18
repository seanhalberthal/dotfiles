-- spell autocorrect utilities and keymaps.
-- single-word, line, and buffer-wide autocorrect via vim's spellsuggest

local M = {}

--- shift spelling "mark bad word" from zw to zW to prevent accidents
local function setup_mark_swap()
  vim.keymap.set('n', 'zW', 'zw', { desc = 'Mark word as misspelled', silent = true })
  vim.keymap.set('n', 'zw', '<Nop>', { silent = true })
end

--- apply the first spell suggestion to the misspelled word nearest the cursor
---@return boolean true if a word was corrected
function M.apply_first_suggestion()
  local bad_word = vim.fn.spellbadword()[1]
  if bad_word == nil or bad_word == '' then
    return false
  end

  local suggestions = vim.fn.spellsuggest(bad_word, 1)
  local replacement = suggestions[1]
  if replacement == nil or replacement == '' then
    return false
  end

  local row, col = unpack(vim.api.nvim_win_get_cursor(0))
  local line = vim.api.nvim_get_current_line()
  local start_col = col + 1
  local finish_col = start_col + #bad_word - 1

  while start_col > 1 and line:sub(start_col, finish_col) ~= bad_word do
    start_col = start_col - 1
    finish_col = start_col + #bad_word - 1
  end

  if line:sub(start_col, finish_col) ~= bad_word then
    start_col = col + 1
    finish_col = start_col + #bad_word - 1
    while finish_col <= #line and line:sub(start_col, finish_col) ~= bad_word do
      start_col = start_col + 1
      finish_col = start_col + #bad_word - 1
    end
  end

  if line:sub(start_col, finish_col) ~= bad_word then
    return false
  end

  vim.api.nvim_buf_set_text(0, row - 1, start_col - 1, row - 1, finish_col, { replacement })
  vim.api.nvim_win_set_cursor(0, { row, start_col - 1 })
  return true
end

--- walk the range applying the first suggestion to each misspelling. assumes the
--- caller has already cleared wrapscan, so `]s` can't wrap past the range
---@param start_line integer
---@param end_line integer
---@return integer fixed
local function correct_in_range(start_line, end_line)
  local fixed = 0
  vim.api.nvim_win_set_cursor(0, { start_line, 0 })

  local prev_row, prev_col = -1, -1
  while true do
    local bad_word = vim.fn.spellbadword()[1]
    if bad_word == nil or bad_word == '' then
      vim.cmd 'keepjumps normal! ]s'
    end

    local row, col = unpack(vim.api.nvim_win_get_cursor(0))
    if row < start_line or row > end_line then
      break
    end

    -- guard against cursor not advancing (no more misspellings in range)
    if row == prev_row and col == prev_col then
      break
    end
    prev_row, prev_col = row, col

    bad_word = vim.fn.spellbadword()[1]
    if bad_word ~= nil and bad_word ~= '' then
      if M.apply_first_suggestion() then
        fixed = fixed + 1
      else
        local line = vim.api.nvim_get_current_line()
        local next_col = math.min(#line, col + math.max(#bad_word, 1))
        vim.api.nvim_win_set_cursor(0, { row, next_col })
      end
    else
      break
    end
  end

  return fixed
end

--- autocorrect all misspelled words in a line range
---@param start_line integer 1-indexed start line
---@param end_line integer 1-indexed end line (inclusive)
---@return integer fixed number of words corrected
function M.autocorrect_range(start_line, end_line)
  local view = vim.fn.winsaveview()
  local wrapscan = vim.o.wrapscan

  -- wrapscan is global, so the walk runs under pcall: a throw mid-range (an
  -- out-of-range cursor set, say) would otherwise leave the whole session
  -- without search wrapping and skip the view restore
  vim.o.wrapscan = false
  local ok, result = pcall(correct_in_range, start_line, end_line)
  vim.fn.winrestview(view)
  vim.o.wrapscan = wrapscan

  if not ok then
    error(result, 0)
  end
  return result
end

function M.setup()
  setup_mark_swap()

  vim.keymap.set('n', '<leader>St', '<cmd>set spell!<CR>', { desc = '[T]oggle spellcheck' })
  vim.keymap.set('n', '<leader>Sc', function()
    if not M.apply_first_suggestion() then
      vim.notify('No misspelled word under cursor', vim.log.levels.WARN)
    end
  end, { desc = 'Auto-[C]orrect word' })
  vim.keymap.set('n', '<leader>Sl', function()
    local row = vim.api.nvim_win_get_cursor(0)[1]
    local fixed = M.autocorrect_range(row, row)
    vim.notify(('Autocorrected %d word%s on this line'):format(fixed, fixed == 1 and '' or 's'))
  end, { desc = 'Auto-correct current [L]ine' })
  vim.keymap.set('n', '<leader>SB', function()
    local fixed = M.autocorrect_range(1, vim.api.nvim_buf_line_count(0))
    vim.notify(('Autocorrected %d word%s in buffer'):format(fixed, fixed == 1 and '' or 's'))
  end, { desc = 'Auto-correct [B]uffer' })
  vim.keymap.set('n', '<leader>Ss', function()
    require('telescope.builtin').spell_suggest(require('telescope.themes').get_cursor())
  end, { desc = '[S]uggest corrections' })
  vim.keymap.set('n', '<leader>Sa', 'zg', { desc = '[A]dd word to dictionary' })
  vim.keymap.set('n', '<leader>Sr', function()
    local word = vim.fn.expand '<cword>'
    if word == nil or word == '' then
      vim.notify('No word under cursor', vim.log.levels.WARN)
      return
    end

    local choice = vim.fn.confirm(('Mark "%s" as misspelled?'):format(word), '&Yes\n&No', 2)
    if choice == 1 then
      vim.cmd 'normal! zw'
    end
  end, { desc = '[R]emove word from dictionary' })
  vim.keymap.set('n', '<leader>S?', 'z=', { desc = 'Full suggestion list' })
  vim.keymap.set('n', '<leader>Sd', function()
    vim.cmd('edit ' .. vim.fn.stdpath 'data' .. '/spell/en.utf-8.add')
  end, { desc = '[D]ictionary (personal)' })
end

return M
