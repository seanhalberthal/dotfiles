-- quickfix and location list keymaps: toggle, navigate, clear, and
-- route diagnostics into the native lists

local M = {}

-- neotest's diagnostic namespace, resolved by name so this doesn't pull
-- neotest in. failed tests are diagnostics but not code problems, and mixing
-- them into the diagnostics lists made a red suite look like a broken build
local neotest_ns = vim.api.nvim_create_namespace 'neotest'

local function toggle_quickfix()
  for _, win in ipairs(vim.fn.getwininfo()) do
    if win.quickfix == 1 and win.loclist == 0 then
      vim.cmd 'cclose'
      return
    end
  end
  vim.cmd 'botright copen'
end

local function toggle_loclist()
  for _, win in ipairs(vim.fn.getwininfo()) do
    if win.loclist == 1 then
      vim.cmd 'lclose'
      return
    end
  end
  local ok = pcall(vim.cmd.lopen)
  if not ok then
    vim.notify('No location list for current window', vim.log.levels.WARN)
  end
end

-- override mini.bracketed's ]q/[q and ]l/[l with empty-list notifications.
-- mini.bracketed silently no-ops when the list is empty, which is confusing.
-- :cnext/:cprev echo "(N of M): ..." which ui2 surfaces as a notification.
-- silence via the :silent! modifier while keeping mini.bracketed's wrap-around.
--
-- mini.bracketed advances from the qf list's "current entry" idx, which only
-- updates via :cc/:cnext/<CR>-in-qf. if the user lands on an entry's location
-- via any other path (LSP jump, search, picker, manual nav), the idx goes
-- stale and ]q/[q skip away from where the cursor actually is. sync the idx
-- to the entry matching the cursor's current file:line first; or, if we're
-- inside the qf window, to the cursor row itself.
--
-- when multiple entries share the cursor's bufnr+lnum (e.g. several
-- diagnostics on one line), keep the existing idx if it already points at
-- one of them. snapping to the first match every press would oscillate
-- between the first and second entry forever
local function sync_list_idx_to_cursor(list, set_idx)
  if vim.bo.buftype == 'quickfix' then
    set_idx(vim.api.nvim_win_get_cursor(0)[1])
    return
  end
  local cur_buf = vim.api.nvim_get_current_buf()
  local cur_line = vim.api.nvim_win_get_cursor(0)[1]

  local cur = list.idx and list.items[list.idx]
  if cur and cur.bufnr == cur_buf and cur.lnum == cur_line then
    return
  end

  for i, entry in ipairs(list.items) do
    if entry.bufnr == cur_buf and entry.lnum == cur_line then
      set_idx(i)
      return
    end
  end
end

-- noice's LSP/docs popups can temporarily take focus, which makes list
-- navigation run against the popup buffer instead of the underlying editing
-- window. resolve back to the last real window first
local function resolve_list_nav_win()
  local current = vim.api.nvim_get_current_win()
  local cur_buf = vim.api.nvim_win_get_buf(current)
  if vim.bo[cur_buf].filetype ~= 'noice' then
    return current
  end

  local function is_source_win(win)
    if not win or win == 0 or win == current or not vim.api.nvim_win_is_valid(win) then
      return false
    end
    local buf = vim.api.nvim_win_get_buf(win)
    return vim.bo[buf].filetype ~= 'noice'
  end

  local prev = vim.fn.win_getid(vim.fn.winnr '#')
  if is_source_win(prev) then
    return prev
  end

  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if is_source_win(win) then
      return win
    end
  end
end

local function with_list_nav_win(fn)
  local win = resolve_list_nav_win()
  if not win then
    vim.notify('No source window for list navigation', vim.log.levels.WARN)
    return
  end
  if win == vim.api.nvim_get_current_win() then
    fn()
    return
  end
  vim.api.nvim_set_current_win(win)
  fn()
end

local function bracketed_qf(direction)
  return function()
    with_list_nav_win(function()
      local list = vim.fn.getqflist { items = 0, idx = 0 }
      if #list.items == 0 then
        vim.notify('Quickfix list is empty', vim.log.levels.WARN)
        return
      end
      sync_list_idx_to_cursor(list, function(idx)
        vim.fn.setqflist({}, 'a', { idx = idx })
      end)
      vim.cmd(string.format([[silent! lua require('mini.bracketed').quickfix(%q)]], direction))
    end)
  end
end

local function bracketed_loc(direction)
  return function()
    with_list_nav_win(function()
      local list = vim.fn.getloclist(0, { items = 0, idx = 0 })
      if #list.items == 0 then
        vim.notify('Location list is empty', vim.log.levels.WARN)
        return
      end
      sync_list_idx_to_cursor(list, function(idx)
        vim.fn.setloclist(0, {}, 'a', { idx = idx })
      end)
      vim.cmd(string.format([[silent! lua require('mini.bracketed').location(%q)]], direction))
    end)
  end
end

-- diagnostics into native lists. explicit titles let `build.lua`'s
-- `setup_auto_clear` predicate (`^(%w+):` against `AUTO_CLEAR_KINDS`)
-- match these lists and prune resolved entries on DiagnosticChanged.
-- we bypass `vim.diagnostic.setqflist` so we can route through
-- `scan_runner.diag_to_item`, which prefixes text with `[source]` (the
-- originating LSP). the same prefix is used by the auto-clear's
-- (lnum, text) match so pruning stays accurate
local function diags_to_items(diagnostics)
  local scan_runner = require 'custom.features.scan-runner'
  local scan_ignored = require('custom.features.diag-scan').scan_ignored
  local items = {}
  -- get(nil) spans every buffer, so the same file open under two bufnrs
  -- (a git-diff/review split, a second-window reopen) yields byte-identical
  -- rows. collapse on (file, lnum, col, text) so a diagnostic surfaces once
  local seen = {}
  for _, d in ipairs(diagnostics) do
    -- drop scan-ignored phantoms from buffers not shown in any window:
    -- hidden buffers only ever got the reduced-pass pull, and with no
    -- window they never get the full pass that self-corrects in-editor;
    -- they'd sit in the live list indefinitely. displayed buffers keep
    -- theirs (the full pass has run; entries are real). the predicate is
    -- shared with diag-scan's batch snapshot
    if d.bufnr and d.lnum and d.namespace ~= neotest_ns and not scan_runner.in_library(d) and not scan_runner.is_generated(d) then
      local hidden_phantom = scan_ignored(d) and #vim.fn.win_findbuf(d.bufnr) == 0
      if not hidden_phantom then
        local item = scan_runner.diag_to_item(d)
        local key = table.concat({ vim.api.nvim_buf_get_name(d.bufnr), item.lnum, item.col or 0, item.text or '' }, ':')
        if not seen[key] then
          seen[key] = true
          table.insert(items, item)
        end
      end
    end
  end
  table.sort(items, function(a, b)
    if a.bufnr ~= b.bufnr then
      return (a.bufnr or 0) < (b.bufnr or 0)
    end
    if a.lnum ~= b.lnum then
      return a.lnum < b.lnum
    end
    return (a.col or 0) < (b.col or 0)
  end)
  return items
end

local DIAG_QF_TITLE = 'Diagnostics: all'

-- live sync for the <leader>xx list: while the *current* qf list's title is
-- DIAG_QF_TITLE, a debounced DiagnosticChanged rebuild keeps it current in
-- both directions: fixed entries drop out (auto-clear already did that) and
-- new diagnostics flow in, so re-pressing <leader>xx after each round of
-- fixes is no longer needed. any list push with a different title (:Cfilter,
-- a build, a scan) pauses the sync; <leader>x[ back to the live list resumes
local function rebuild_live_qf()
  local qf = vim.fn.getqflist { title = 0, idx = 0, items = 0 }
  if qf.title ~= DIAG_QF_TITLE then
    return
  end
  local items = diags_to_items(vim.diagnostic.get(nil))

  if #items == 0 then
    if #qf.items == 0 then
      return
    end
    vim.fn.setqflist({}, 'r', { title = DIAG_QF_TITLE, items = {} })
    -- this live list owns its own close + notify: build.lua's auto-clear no
    -- longer prunes the DIAG_QF_TITLE list (its `Diagnostics` kind was retired
    -- in favour of `Buffer`/`Branch`/`Project`), so nothing else empties it
    for _, win in ipairs(vim.fn.getwininfo()) do
      if win.quickfix == 1 and win.loclist == 0 then
        vim.api.nvim_win_close(win.winid, true)
        vim.notify('Diagnostics: clean', vim.log.levels.INFO)
        break
      end
    end
    return
  end

  -- preserve the current entry across the rebuild (same idea as build.lua's
  -- prune-idx logic): if the entry the user is pointed at survives, it stays
  -- current; if it was the one just resolved, snap to the nearest surviving
  -- predecessor so the next ]q advances forward rather than jumping to
  -- entry 1 (setqflist's default after replace). items are sorted by
  -- (bufnr, lnum, col) on both sides, so "predecessor" is positional
  local new_idx
  local cur = qf.idx and qf.idx > 0 and qf.items[qf.idx] or nil
  if cur then
    for i, item in ipairs(items) do
      if item.bufnr == cur.bufnr and item.lnum == cur.lnum and item.text == cur.text then
        new_idx = i
        break
      end
    end
    if not new_idx then
      for i, item in ipairs(items) do
        local before = (item.bufnr or 0) < (cur.bufnr or 0)
          or (item.bufnr == cur.bufnr and (item.lnum < cur.lnum or (item.lnum == cur.lnum and (item.col or 0) <= (cur.col or 0))))
        if before then
          new_idx = i
        else
          break
        end
      end
    end
  end
  vim.fn.setqflist({}, 'r', { title = DIAG_QF_TITLE, items = items, idx = new_idx })
end

local live_timer

local function schedule_live_rebuild()
  if not live_timer then
    live_timer = assert(vim.uv.new_timer())
  end
  live_timer:stop()
  live_timer:start(300, 0, vim.schedule_wrap(rebuild_live_qf))
end

-- :Cfilter / :Lfilter replacements that keep the source list's "Kind:" prefix
-- in the filtered list's title. stock cfilter.vim retitles the new list
-- ":Cfilter /pat/", which drops the prefix build.lua's auto-clear keys on, so a
-- filtered diagnostics list stops pruning as issues are fixed. we reproduce
-- cfilter's matching (optional /"' delimiters, empty pat = last search, ! to
-- invert, case-sensitive against text + filename) and only change the title:
-- keep the original and append the filter when it carries a kind, else fall
-- back to cfilter's own title so grep/other lists read naturally
local function filter_list(is_qf, searchpat, bang)
  local pat = searchpat
  local first, last = searchpat:sub(1, 1), searchpat:sub(-1)
  if first == last and (first == '/' or first == '"' or first == "'") then
    pat = searchpat:sub(2, -2)
    if pat == '' then
      pat = vim.fn.getreg '/'
    end
  end
  if pat == '' then
    return
  end

  local cur = is_qf and vim.fn.getqflist { title = 0, items = 0 } or vim.fn.getloclist(0, { title = 0, items = 0 })

  -- \C forces case-sensitive matching to mirror cfilter's =~# / !~#
  local mpat = '\\C' .. pat
  local invert = bang == '!'
  local kept = {}
  for _, item in ipairs(cur.items) do
    local name = (item.bufnr and item.bufnr > 0) and vim.fn.bufname(item.bufnr) or ''
    local matched = vim.fn.match(item.text or '', mpat) >= 0 or vim.fn.match(name, mpat) >= 0
    if matched ~= invert then
      table.insert(kept, item)
    end
  end

  local title
  if cur.title and cur.title:match '^%w+:' then
    title = cur.title .. ' (filtered /' .. pat .. '/)'
  else
    title = (is_qf and ':Cfilter' or ':Lfilter') .. bang .. ' /' .. pat .. '/'
  end

  if is_qf then
    vim.fn.setqflist({}, ' ', { title = title, items = kept })
  else
    vim.fn.setloclist(0, {}, ' ', { title = title, items = kept })
  end
end

function M.setup()
  -- :Cfilter /pat/ keeps matching qf entries, :Cfilter! /pat/ drops them; same
  -- for :Lfilter on loclists. these shadow the stock cfilter.vim commands to
  -- preserve the kind prefix in the filtered title (see filter_list)
  vim.api.nvim_create_user_command('Cfilter', function(o)
    filter_list(true, o.args, o.bang and '!' or '')
  end, { nargs = '+', bang = true, desc = 'Filter quickfix (keeps kind for auto-clear)' })
  vim.api.nvim_create_user_command('Lfilter', function(o)
    filter_list(false, o.args, o.bang and '!' or '')
  end, { nargs = '+', bang = true, desc = 'Filter location list (keeps kind for auto-clear)' })

  -- dashboard escape is handled globally in autocmds.lua (FileType qf autocmd)
  vim.keymap.set('n', '<leader>xq', toggle_quickfix, { desc = '[Q]uickfix list toggle' })
  vim.keymap.set('n', '<leader>xl', toggle_loclist, { desc = '[L]ocation list toggle' })

  vim.api.nvim_create_autocmd('DiagnosticChanged', {
    group = vim.api.nvim_create_augroup('DiagnosticsLiveQf', { clear = true }),
    callback = schedule_live_rebuild,
  })

  -- <leader>xx toggles a *live* list: if the qf window is already showing
  -- the live diagnostics list, close it; otherwise (re)build and open. while
  -- the list is current, the DiagnosticChanged sync above keeps it fresh,
  -- including diagnostics republished after `checktime` reloads buffers an
  -- external writer (Claude Code, another nvim instance, a script) changed,
  -- which previously needed a second press
  vim.keymap.set('n', '<leader>xx', function()
    local qf = vim.fn.getqflist { title = 0 }
    if qf.title == DIAG_QF_TITLE then
      for _, win in ipairs(vim.fn.getwininfo()) do
        if win.quickfix == 1 and win.loclist == 0 then
          vim.cmd 'cclose'
          return
        end
      end
    end
    pcall(vim.cmd, 'checktime')
    local items = diags_to_items(vim.diagnostic.get(nil))
    -- replace in place when the live list is already current, so repeated
    -- presses don't push duplicate lists onto the qf stack
    local action = qf.title == DIAG_QF_TITLE and 'r' or ' '
    vim.fn.setqflist({}, action, { title = DIAG_QF_TITLE, items = items })
    if #items == 0 then
      vim.notify('Diagnostics: clean', vim.log.levels.INFO)
    end
    vim.cmd 'botright cwindow'
  end, { desc = 'All [D]iagnostics to quickfix (live)' })
  vim.keymap.set('n', '<leader>xX', function()
    local items = diags_to_items(vim.diagnostic.get(0))
    vim.fn.setloclist(0, {}, ' ', { title = 'Buffer: diagnostics', items = items })
    if #items == 0 then
      vim.notify('Buffer diagnostics: clean', vim.log.levels.INFO)
    end
    vim.cmd 'lwindow'
  end, { desc = 'Buffer diagnostics to loclist' })

  -- grep the yank register (0 = last yank, untouched by deletes) as a literal
  -- string into the quickfix list. -F keeps regex metacharacters in the yanked
  -- text literal; grep! fills the list without jumping. flows through grepprg
  -- (rg --vimgrep --smart-case), so ]q/[q navigate the result
  vim.keymap.set('n', '<leader>x/', function()
    local pat = vim.fn.getreg '0'
    -- rg matches per-line, so collapse a multiline yank to its first line
    pat = pat:gsub('\n.*', ''):gsub('^%s+', ''):gsub('%s+$', '')
    if pat == '' then
      vim.notify('Yank register empty', vim.log.levels.WARN)
      return
    end
    -- shellescape for the shell; escape %/# so vim's cmdline doesn't expand
    -- them, and | so :grep doesn't split the command at the bar
    local arg = vim.fn.shellescape(pat):gsub('[%%#|]', '\\%0')
    vim.cmd('silent grep! -F ' .. arg)
    vim.cmd 'botright copen'
  end, { desc = 'Grep [/] yanked text → quickfix' })

  -- :grep shells grepprg out through :!, so nvim echoes the command line (tmpfile
  -- path and all), every raw match, then the jump message, and ends on a
  -- hit-enter prompt. with cmdheight=0 that balloons the cmdline area open and
  -- collapses it again. rewrite the typed command to its silent form; the
  -- QuickFixCmdPost hook below puts the list on screen instead.
  --
  -- guarded on the cmdline being nothing but the command, so an explicit
  -- `:silent grep`, a range, or a `:Ggrep` is left alone
  for _, cmd in ipairs { 'grep', 'grepadd', 'lgrep', 'lgrepadd' } do
    local abbrev = "cnoreabbrev <expr> %s (getcmdtype() == ':' && getcmdline() ==# '%s') ? 'silent %s' : '%s'"
    vim.cmd(abbrev:format(cmd, cmd, cmd, cmd))
  end

  -- :grep fills a list without showing it. cwindow opens the window only when
  -- there are entries and closes a stale one when there aren't, so it doubles as
  -- the "open it if it isn't already" the abbreviation above needs. silencing
  -- swallows the zero-match case whole (grepprg-based :grep emits no E480), so
  -- that gets its own notify
  vim.api.nvim_create_autocmd('QuickFixCmdPost', {
    group = vim.api.nvim_create_augroup('GrepShowList', { clear = true }),
    pattern = { 'grep', 'grepadd', 'lgrep', 'lgrepadd' },
    callback = function(ev)
      local loclist = ev.match:sub(1, 1) == 'l'
      local count = loclist and #vim.fn.getloclist(0) or #vim.fn.getqflist()
      vim.cmd(loclist and 'lwindow' or 'botright cwindow')
      if count == 0 then
        vim.notify('No matches', vim.log.levels.WARN)
      end
    end,
  })

  vim.keymap.set('n', ']q', bracketed_qf 'forward', { desc = 'Next quickfix entry' })
  vim.keymap.set('n', '[q', bracketed_qf 'backward', { desc = 'Previous quickfix entry' })
  vim.keymap.set('n', ']l', bracketed_loc 'forward', { desc = 'Next location entry' })
  vim.keymap.set('n', '[l', bracketed_loc 'backward', { desc = 'Previous location entry' })

  -- shadow mini.bracketed (]b/[b ]f/[f ]d/[d ...) inside qf/loclist buffers;
  -- those target the underlying editing window but fire against the list
  -- buffer when it's focused, which is confusing. ]q/[q and ]l/[l stay live.
  -- qf/loclist buffers are buflisted=1 by default while their window is open,
  -- so they surface in telescope's buffers picker and mini.bracketed's ]b/[b
  -- (both filter on buflisted); unlist them so neither can stumble onto them
  vim.api.nvim_create_autocmd('FileType', {
    group = vim.api.nvim_create_augroup('QfDisableBracketed', { clear = true }),
    pattern = 'qf',
    callback = function(ev)
      vim.bo[ev.buf].buflisted = false
      for _, s in ipairs { 'b', 'd', 'f', 'i', 'j', 'o', 'u', 'w', 'x', 'y' } do
        vim.keymap.set('n', ']' .. s, '<Nop>', { buffer = ev.buf, silent = true })
        vim.keymap.set('n', '[' .. s, '<Nop>', { buffer = ev.buf, silent = true })
      end
      -- qf buffers are nomodifiable, so bare `o` (open line) only errors; reuse
      -- it to jump to the entry under the cursor, same as <CR>
      vim.keymap.set('n', 'o', '<CR>', { buffer = ev.buf, silent = true, remap = true, desc = 'Open entry under cursor' })
    end,
  })

  -- walk the qf stack: each :Cfilter pushes a new list, so <leader>x[ undoes
  -- the last filter (or any other push). counts honoured: 3<leader>x[ → :3colder
  local function qf_history(cmd, edge_msg)
    return function()
      local ok = pcall(vim.cmd, vim.v.count1 .. cmd)
      if not ok then
        vim.notify(edge_msg, vim.log.levels.WARN)
      end
    end
  end
  vim.keymap.set('n', '<leader>x[', qf_history('colder', 'At oldest quickfix list'), { desc = 'Quickfix stack older (undo Cfilter)' })
  vim.keymap.set('n', '<leader>x]', qf_history('cnewer', 'At newest quickfix list'), { desc = 'Quickfix stack newer' })

  vim.keymap.set('n', '<leader>xcq', function()
    vim.fn.setqflist({}, 'r')
    vim.cmd 'cclose'
  end, { desc = '[C]lear [Q]uickfix list' })

  vim.keymap.set('n', '<leader>xcl', function()
    vim.fn.setloclist(0, {}, 'r')
    vim.cmd 'lclose'
  end, { desc = '[C]lear [L]ocation list' })

  vim.keymap.set('n', '<leader>xcc', function()
    vim.fn.setqflist({}, 'r')
    vim.fn.setloclist(0, {}, 'r')
    vim.cmd 'cclose'
    vim.cmd 'lclose'
  end, { desc = '[C]lear both quickfix and location lists' })

  -- <leader>xm / xt / xT (git-scoped diagnostics scans) live in
  -- features/diag-scan.lua, wired separately from core/keymaps.lua
end

return M
