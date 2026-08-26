-- shared diagnostic-scan state machine. wraps the common pattern of:
--   open a set of buffers, debounce on DiagnosticChanged, snapshot
--   diagnostics into a titled quickfix, finalise.
-- used by the sonarlint project-scan (features/sonar-scan.lua) and the
-- git-scoped scans (features/diag-scan.lua).
--
-- single global singleton: only one scan can be active at a time. callers
-- check `is_active()` and reject (or merge) if a scan is already running;
-- this is the desired mutual exclusion since both flows write to the same
-- quickfix list

local M = {}

-- vim.diagnostic.severity values (1=ERROR, 2=WARN, 3=INFO, 4=HINT) → qf type letters
local SEVERITY_TYPE = { 'E', 'W', 'I', 'N' }

-- map raw `d.source` strings (what each LSP reports) to short labels used
-- as the `[label]` prefix in qf text. unmapped sources fall through to the
-- raw value, so new LSPs degrade gracefully; add an entry here if a fresh
-- one shows up with a noisy label
local SOURCE_LABEL = {
  sonarlint = 'sonar',
  sonarqube = 'sonar',
  typescript = 'ts',
  tsserver = 'ts',
  ['typescript-eslint'] = 'eslint',
  eslint = 'eslint',
  ['Lua Diagnostics.'] = 'lua',
  ['Lua Syntax Check.'] = 'lua',
  ['Lua Type Check.'] = 'lua',
  lua_ls = 'lua',
  luacheck = 'lua',
  roslyn = 'cs',
  omnisharp = 'cs',
  rust_analyzer = 'rust',
  rustc = 'rust',
  basedpyright = 'py',
  pyright = 'py',
  pylsp = 'py',
  ruff = 'py',
  pylint = 'py',
  gopls = 'go',
  golangci_lint = 'go',
  clangd = 'c',
  ['clang-tidy'] = 'c',
}

--- short label for a diagnostic's source. explicit SOURCE_LABEL mapping wins;
--- otherwise we fall back to the buffer's filetype so subanalyzer sources
--- (e.g. gopls modernize: stringscut, minmax, stringsseq) collapse under the
--- language label rather than leaking their internal analyzer names. the raw
--- source is the last resort
function M.source_label(d)
  local src = d.source
  if not src or src == '' then
    return nil
  end
  local mapped = SOURCE_LABEL[src]
  if mapped then
    return mapped
  end
  if d.bufnr and vim.api.nvim_buf_is_valid(d.bufnr) then
    local ft = vim.bo[d.bufnr].filetype
    if ft and ft ~= '' then
      return ft
    end
  end
  return src
end

--- render a diagnostic's text with a `[label] ` prefix when the source is
--- known, so qf entries surface which LSP each warning came from
--- (sonar, ts, roslyn, …). build.lua's auto-clear keys its live-diagnostic
--- lookups by this same function so prune matches stay consistent with
--- what's displayed
function M.qf_text(d)
  local label = M.source_label(d)
  if label then
    return '[' .. label .. '] ' .. (d.message or '')
  end
  return d.message or ''
end

--- convert a vim.Diagnostic into a qf item. used in place of
--- vim.diagnostic.toqflist so we can inject the source prefix into `text`
function M.diag_to_item(d)
  return {
    bufnr = d.bufnr,
    lnum = (d.lnum or 0) + 1,
    end_lnum = (d.end_lnum or d.lnum or 0) + 1,
    col = d.col and (d.col + 1) or nil,
    end_col = d.end_col and (d.end_col + 1) or nil,
    text = M.qf_text(d),
    type = SEVERITY_TYPE[d.severity] or 'E',
  }
end

-- library / dependency code we never want in a diagnostics list. these are
-- read-only files surfaced when an LSP attaches after a go-to-definition jump
-- (e.g. gopls emitting modernization notes on the Go stdlib under the Homebrew
-- Cellar). two signals: the file lives outside the project root (cwd), which
-- catches stdlib and global module caches; or it sits under an in-tree vendored
-- dependency directory, which a cwd check alone would miss. shared by the live
-- <leader>xx list (lists.lua) and the git-scoped scans (diag-scan.lua)
local LIBRARY_SEGMENTS = {
  '/node_modules/',
  '/vendor/',
  '/site%-packages/',
  '/dist%-packages/',
  '/pkg/mod/',
  '/%.venv/',
  '/%.cargo/',
}

function M.in_library(d)
  if not d.bufnr or not vim.api.nvim_buf_is_valid(d.bufnr) then
    return false
  end
  local name = vim.api.nvim_buf_get_name(d.bufnr)
  if name == '' then
    return false
  end
  local path = vim.fs.normalize(name)
  for _, seg in ipairs(LIBRARY_SEGMENTS) do
    if path:find(seg) then
      return true
    end
  end
  -- outside the project root: stdlib, global caches, anything jumped into
  local root = vim.fs.normalize(vim.fn.getcwd())
  return path:sub(1, #root + 1) ~= root .. '/'
end

-- generated code (sqlc, protoc-gen-go, mockgen, stringer, …) carries the Go
-- canonical sentinel on an early line: `// Code generated … DO NOT EDIT.`.
-- it's regenerated wholesale and never hand-edited, so diagnostics on it are
-- noise; drop it from the live list and the git-scoped scans alike. cache per
-- bufnr keyed by changedtick so the lines are read once per edit
local generated_cache = {}

function M.is_generated(d)
  if not d.bufnr or not vim.api.nvim_buf_is_valid(d.bufnr) then
    return false
  end
  local tick = vim.b[d.bufnr].changedtick
  local cached = generated_cache[d.bufnr]
  if cached and cached.tick == tick then
    return cached.value
  end
  local value = false
  for _, l in ipairs(vim.api.nvim_buf_get_lines(d.bufnr, 0, 10, false)) do
    if l:match 'Code generated .* DO NOT EDIT%.' then
      value = true
      break
    end
  end
  generated_cache[d.bufnr] = { tick = tick, value = value }
  return value
end

local state = nil

local function clear_timer(t)
  if t then
    pcall(function()
      t:stop()
      t:close()
    end)
  end
end

--- @class ScanOpts
--- @field bufnrs integer[]                                       buffers whose diagnostics drive the debounce
--- @field collect_bufnrs? integer[]                              extra buffers to fold into the final qf (default = bufnrs)
--- @field get_diagnostics? fun(integer): vim.Diagnostic[]        defaults to vim.diagnostic.get
--- @field debounce_ms integer
--- @field hard_timeout_ms integer
--- @field qf_title string
--- @field qf_label string                                        shown in finalise notify ("X: clean" / "X: N issue(s)")
--- @field augroup_name string                                    unique per caller (e.g. "SonarlintScan")
--- @field on_finalise? fun(items: table[])                       post-collection hook (e.g. unload created buffers)
--- @field on_complete? fun(items: table[])                        when set, replaces the qf-write/notify/copen/progress-finish tail and hands the collected items back instead (caller owns the final list — used to merge batched scans into one quickfix)
--- @field on_report? fun(reported: integer, total: integer)      fired the first time each watched buffer reports a DiagnosticChanged
--- @field settled_debounce_ms? integer                           shorter debounce once every watched buffer has reported at least once
--- @field settle_check? fun(): boolean                           extra gate on the settled fast path, re-evaluated at every debounce reset (e.g. "no slow analyzer attached")
--- @field progress? { finish: fun() }                            optional fidget-shaped handle (must expose :finish())
--- @field hard_timeout_message? string                           shown on hard-timeout fire (default: no notify)

--- @param opts ScanOpts
--- @return boolean started — false if another scan is already active
function M.start(opts)
  if state then
    return false
  end
  local get_diagnostics = opts.get_diagnostics or vim.diagnostic.get
  local watched = {}
  local total = 0
  for _, bufnr in ipairs(opts.bufnrs) do
    if not watched[bufnr] then
      total = total + 1
    end
    watched[bufnr] = true
  end

  -- convert bufnr -> filename so qf entries survive any buffer-unload the
  -- caller does in on_finalise. items keyed only by bufnr would crash
  -- setqflist ("E92: Buffer N not found") once the underlying buffer is gone
  local function collect()
    local items = {}
    local seen_bufnr = {}
    local function pull(bufnr)
      if seen_bufnr[bufnr] or not vim.api.nvim_buf_is_valid(bufnr) then
        return
      end
      seen_bufnr[bufnr] = true
      local fname = vim.api.nvim_buf_get_name(bufnr)
      for _, d in ipairs(get_diagnostics(bufnr)) do
        if d.lnum then
          local item = M.diag_to_item(d)
          if fname ~= '' then
            item.filename = fname
          end
          item.bufnr = nil
          table.insert(items, item)
        end
      end
    end
    for _, bufnr in ipairs(opts.collect_bufnrs or opts.bufnrs) do
      pull(bufnr)
    end
    return items
  end

  local function finalise()
    if not state then
      return
    end
    clear_timer(state.debounce)
    clear_timer(state.hard_timeout)
    pcall(vim.api.nvim_del_augroup_by_id, state.augroup)

    local items = collect()
    if opts.on_finalise then
      pcall(opts.on_finalise, items)
    end

    -- batched mode: the caller drives buffer teardown and the final quickfix
    -- across multiple sequential runs, so skip the qf-write/notify/copen tail
    -- and hand this batch's items back. clear state first so the caller can
    -- start the next batch's scan from inside the callback
    if opts.on_complete then
      state = nil
      pcall(opts.on_complete, items)
      return
    end

    vim.fn.setqflist({}, 'r', { title = opts.qf_title, items = items })

    if opts.progress then
      pcall(function()
        opts.progress:finish()
      end)
    end

    state = nil

    if #items > 0 then
      vim.notify(opts.qf_label .. ': ' .. #items .. ' issue(s)', vim.log.levels.WARN)
      vim.cmd 'botright copen'
    else
      vim.notify(opts.qf_label .. ': clean', vim.log.levels.INFO)
    end
  end

  -- adaptive debounce: the full debounce_ms covers slow analyzers that
  -- haven't published anything yet, but once *every* watched buffer has
  -- reported at least one DiagnosticChanged, the remaining quiet time is
  -- usually dead air; drop to settled_debounce_ms (when set) so small,
  -- fast changesets finalise quickly
  local function reset_debounce()
    clear_timer(state.debounce)
    local ms = opts.debounce_ms
    if opts.settled_debounce_ms and state.reported_count >= total and (not opts.settle_check or opts.settle_check()) then
      ms = opts.settled_debounce_ms
    end
    state.debounce = vim.uv.new_timer()
    state.debounce:start(ms, 0, vim.schedule_wrap(finalise))
  end

  state = {
    augroup = vim.api.nvim_create_augroup(opts.augroup_name, { clear = true }),
    debounce = nil,
    hard_timeout = nil,
    reported = {},
    reported_count = 0,
  }

  vim.api.nvim_create_autocmd('DiagnosticChanged', {
    group = state.augroup,
    callback = function(args)
      if state and watched[args.buf] then
        if not state.reported[args.buf] then
          state.reported[args.buf] = true
          state.reported_count = state.reported_count + 1
          if opts.on_report then
            pcall(opts.on_report, state.reported_count, total)
          end
        end
        reset_debounce()
      end
    end,
  })

  reset_debounce()

  state.hard_timeout = vim.uv.new_timer()
  state.hard_timeout:start(
    opts.hard_timeout_ms,
    0,
    vim.schedule_wrap(function()
      if state then
        if opts.hard_timeout_message then
          vim.notify(opts.hard_timeout_message, vim.log.levels.WARN)
        end
        finalise()
      end
    end)
  )

  return true
end

function M.is_active()
  return state ~= nil
end

return M
