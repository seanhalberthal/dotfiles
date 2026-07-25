-- git-scoped diagnostics → quickfix scanner. hidden-loads a changeset in
-- bounded batches so LSPs attach, snapshots the resulting diagnostics, and
-- merges them into a titled quickfix without switching the current buffer.
-- sibling of sonarlint's project scan and build.lua. extracted from lists.lua

local M = {}

local scan_runner = require 'custom.features.scan-runner'

-- hidden-load all git-modified (unstaged) and untracked files so LSPs attach,
-- then debounce on DiagnosticChanged and dump the resulting diagnostics into
-- the quickfix list, without switching the current buffer. falls through
-- after a hard timeout if nothing publishes.
--
-- the 5s debounce / 5min timeout is generous enough for sonarlint's java
-- analyzers (which auto-attach via the plugin's `ft` lazy-load when the
-- scan sets the hidden buffer's filetype; bufload alone doesn't reliably
-- fire detection, see scan_files).
--
-- Roslyn (and other LSPs that only push diagnostics for visible documents)
-- need an explicit pull via `textDocument/diagnostic`. pulling before
-- Roslyn's workspace finishes initialising returns -30099, so we wrap its
-- `workspace/projectInitializationComplete` handler (an LSP protocol
-- contract) and pull from inside the wrap. coupling is to the method name,
-- not to roslyn.nvim's `User RoslynInitialized` autocmd (private API)

local ROSLYN_FTS = { cs = true, razor = true, cshtml = true }

local function pull_diagnostics(bufnr)
  if not vim.api.nvim_buf_is_valid(bufnr) or not vim.api.nvim_buf_is_loaded(bufnr) then
    return
  end
  if not next(vim.lsp.get_clients { bufnr = bufnr, method = 'textDocument/diagnostic' }) then
    return
  end
  pcall(vim.lsp.diagnostic._enable, bufnr)
  pcall(vim.lsp.diagnostic._refresh, bufnr)
end

-- idempotently install a wrap around roslyn's
-- `workspace/projectInitializationComplete` handler. installed eagerly via a
-- global LspAttach autocmd in setup() so the wrap is always in place before
-- the notification fires; this lets us trust `__git_modified_init_done` for
-- warm-start scans (where init already happened in a prior xm or earlier in
-- the session)
local function wrap_roslyn(client)
  if client.__git_modified_wrapped then
    return
  end
  client.handlers = client.handlers or {}
  local original = client.handlers['workspace/projectInitializationComplete']
  client.handlers['workspace/projectInitializationComplete'] = function(err, res, ctx)
    if original then
      pcall(original, err, res, ctx)
    end
    client.__git_modified_init_done = true
    local cbs = client.__git_modified_init_cbs or {}
    client.__git_modified_init_cbs = {}
    for _, cb in ipairs(cbs) do
      pcall(cb)
    end
  end
  client.__git_modified_wrapped = true
  client.__git_modified_init_cbs = {}
end

-- run `on_ready` once Roslyn's workspace is initialised. fires immediately
-- on warm starts where the wrap has already observed init; queues otherwise
local function on_roslyn_ready(client, on_ready)
  wrap_roslyn(client)
  if client.__git_modified_init_done then
    pcall(on_ready)
  else
    table.insert(client.__git_modified_init_cbs, on_ready)
  end
end

-- pull diagnostics, gating C#-family files behind Roslyn's project-init
-- notification. non-C# buffers pull immediately. if Roslyn hasn't attached
-- yet, the LspAttach handler picks it up.
--
-- the validity guard matters: the LspAttach handler defers this by 500ms,
-- and the scan can finalise (deleting its created buffers) in that window,
-- e.g. via the 500ms settled debounce. vim.bo on a deleted buffer throws
local function pull_gated(bufnr)
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end
  if ROSLYN_FTS[vim.bo[bufnr].filetype] then
    local roslyn = vim.lsp.get_clients({ bufnr = bufnr, name = 'roslyn' })[1]
    if roslyn then
      on_roslyn_ready(roslyn, function()
        pull_diagnostics(bufnr)
      end)
    end
    return
  end
  pull_diagnostics(bufnr)
end

-- diagnostic codes excluded from scan snapshots (not from in-editor
-- diagnostics). Roslyn's pull for hidden-loaded buffers reports false
-- positives for rules that need a full compilation/analyzer pass, while
-- the scan-time pull analyses with a reduced one; a long-standing roslyn
-- defect (dotnet/roslyn#47288, #75887):
--   IDE0079 ("Remove unnecessary suppression"): judging a suppression
--     needs the suppressed analyzer (e.g. Sonar's S-rules) to run.
--   IDE0005 ("Using directive is unnecessary"): needs full reference
--     resolution to know what each using actually binds.
-- opening the file for real runs the full pass and these vanish, so
-- in-editor they self-correct; in a scan snapshot they'd sit in the
-- quickfix as phantom entries until each file is visited. the live
-- <leader>xx list applies the same filter to buffers hidden from every
-- window (diags_to_items in lists.lua), where that self-correction can
-- never happen
local SCAN_IGNORED_CODES = { IDE0079 = true, IDE0005 = true }

-- `code` can land as a string, a number, or only inside the raw LSP
-- diagnostic (`user_data.lsp.code`) depending on the producing path;
-- normalise before the lookup. exposed so the live <leader>xx list
-- (lists.lua) can apply the same filter to hidden-buffer phantoms
function M.scan_ignored(d)
  local code = d.code
  if code == nil and d.user_data and d.user_data.lsp then
    code = d.user_data.lsp.code
  end
  return code ~= nil and SCAN_IGNORED_CODES[tostring(code)] == true
end

-- drop scan-ignored phantoms and library/dependency code (node_modules,
-- vendored deps, stdlib jumped into) so a scan of a changeset that touches a
-- vendored file doesn't dump its diagnostics into the qf. mirrors the live
-- <leader>xx list's filtering (diags_to_items in lists.lua)
local function scan_diagnostics(bufnr)
  return vim.tbl_filter(function(d)
    return not M.scan_ignored(d) and not scan_runner.in_library(d) and not scan_runner.is_generated(d)
  end, vim.diagnostic.get(bufnr))
end

-- peak roslyn memory during a scan scales with how many .cs files are open
-- at once: its analyzer scope is `openFiles`, and on Sonar-enabled branches
-- every compilation hosts the full SonarAnalyzer.CSharp ruleset. hidden-loading
-- a whole 100-file diff in one go pushed roslyn to ~4GB, so we process files in
-- bounded chunks: load a chunk, snapshot its diagnostics, tear that chunk's
-- created buffers down (the buffer delete sends `didClose`, dropping them from
-- roslyn's open-doc analyzer set) before the next chunk loads. peak open-file
-- count, and therefore analyzer memory, stays bounded regardless of diff size.
-- the solution itself stays loaded across chunks, so only the per-file analyzer
-- cost is re-paid, not a full workspace reload. raise this to trade peak memory
-- for fewer chunks (less wall-clock); lower it if scans still balloon
local SCAN_BATCH_SIZE = 12

-- a multi-batch scan leaves scan_runner momentarily inactive between chunks, so
-- scan_runner.is_active() alone can't guard re-entry; this owns the
-- whole-operation lock
local scanning = false

--- true while any scan is running, including the gaps between batches
local function scan_in_progress()
  return scanning or require('custom.features.scan-runner').is_active()
end

--- hidden-load one chunk of (already filtered-readable) absolute paths so LSPs
--- attach. returns the loaded bufnrs, the subset we created (to tear down after
--- snapshotting), and a target lookup for the per-batch pull autocmd
--- @param paths string[]
--- @return integer[] bufnrs, integer[] created, table<integer, boolean> target
local function load_batch(paths)
  local bufnrs = {}
  local created = {}
  local target = {}
  for _, abs in ipairs(paths) do
    local existed = vim.fn.bufnr(abs) ~= -1
    local bufnr = vim.fn.bufadd(abs)
    pcall(vim.fn.bufload, bufnr)
    -- bufload doesn't reliably run filetype detection for hidden buffers
    -- (scanned buffers were observed with ft = ""). without a filetype,
    -- sonarlint's FileType attach never fires (so scans silently miss
    -- sonar findings), pull_gated misses the ROSLYN_FTS init gate, and
    -- the qf [source] filetype fallback label is lost. detect and set it
    -- explicitly, mirroring the sonar project scan in sonarlint.lua
    if vim.bo[bufnr].filetype == '' then
      local ft = vim.filetype.match { buf = bufnr, filename = abs }
      if ft then
        vim.bo[bufnr].filetype = ft
      end
    end
    table.insert(bufnrs, bufnr)
    target[bufnr] = true
    if not existed then
      table.insert(created, bufnr)
    end
  end
  return bufnrs, created, target
end

--- shared scan driver behind <leader>xm and <leader>xT: hidden-load the given
--- absolute paths in bounded batches so LSPs attach, pull/await diagnostics,
--- snapshot each batch via scan_runner and merge the lot into a titled
--- quickfix. batching bounds peak roslyn memory (see SCAN_BATCH_SIZE)
--- @param paths string[] absolute paths
--- @param opts { qf_title: string, qf_label: string, augroup_name: string, empty_message: string }
local function scan_files(paths, opts)
  if scan_in_progress() then
    vim.notify('A scan is already running', vim.log.levels.WARN)
    return
  end

  -- skip paths that don't exist on disk: the sources include deleted files
  -- (`git ls-files -m` lists deleted-but-unstaged entries; ticket commits
  -- may touch since-deleted files), and creating buffers for missing files
  -- triggers easy-dotnet's BootstrapFile to walk a missing directory and
  -- crash with -32000
  local readable = {}
  for _, abs in ipairs(paths) do
    if vim.fn.filereadable(abs) == 1 then
      table.insert(readable, abs)
    end
  end
  if #readable == 0 then
    vim.notify(opts.empty_message, vim.log.levels.INFO)
    return
  end

  -- partition into chunks of SCAN_BATCH_SIZE, processed strictly sequentially
  local batches = {}
  for i = 1, #readable, SCAN_BATCH_SIZE do
    local chunk = {}
    for j = i, math.min(i + SCAN_BATCH_SIZE - 1, #readable) do
      table.insert(chunk, readable[j])
    end
    table.insert(batches, chunk)
  end

  -- fidget progress (same shape as the sonarlint scan): counts up across the
  -- whole run, not reset per batch, so a slow scan is visibly working rather
  -- than a black box. falls back to a plain notify
  local fidget_ok, fidget = pcall(require, 'fidget.progress')
  local progress = fidget_ok
      and fidget.handle.create {
        title = opts.qf_label,
        message = 'scanning ' .. #readable .. ' file(s) in ' .. #batches .. ' batch(es)',
        lsp_client = { name = opts.qf_label:lower() .. '-scan' },
      }
    or nil
  if not progress then
    vim.notify('Scanning ' .. #readable .. ' file(s) in ' .. #batches .. ' batch(es)…', vim.log.levels.INFO)
  end

  scanning = true
  local all_items = {}
  local scanned = 0

  local function finish_all()
    scanning = false
    if progress then
      pcall(function()
        progress:finish()
      end)
    end
    vim.fn.setqflist({}, 'r', { title = opts.qf_title, items = all_items })
    if #all_items > 0 then
      vim.notify(opts.qf_label .. ': ' .. #all_items .. ' issue(s)', vim.log.levels.WARN)
      vim.cmd 'botright copen'
    else
      vim.notify(opts.qf_label .. ': clean', vim.log.levels.INFO)
    end
  end

  local run_batch
  run_batch = function(idx)
    local chunk = batches[idx]
    if not chunk then
      finish_all()
      return
    end

    local bufnrs, created, target = load_batch(chunk)

    -- already-attached clients (roslyn stays attached across batches; a buffer
    -- the user had visited earlier; sonarlint from a prior batch)
    for _, bufnr in ipairs(bufnrs) do
      pull_gated(bufnr)
    end

    -- late-attaching clients for this batch: sonarlint via filetype lazy-load,
    -- roslyn via file-association autostart on the first batch. Roslyn pulls go
    -- through the init-gate; other clients get a small defer so dynamic
    -- capability registration can settle
    local pull_group = vim.api.nvim_create_augroup(opts.augroup_name .. 'Pull', { clear = true })
    vim.api.nvim_create_autocmd('LspAttach', {
      group = pull_group,
      callback = function(args)
        if not target[args.buf] then
          return
        end
        local client = vim.lsp.get_client_by_id(args.data.client_id)
        if client and client.name == 'roslyn' then
          local b = args.buf
          on_roslyn_ready(client, function()
            pull_diagnostics(b)
          end)
        else
          vim.defer_fn(function()
            pull_gated(args.buf)
          end, 500)
        end
      end,
    })

    local started = scan_runner.start {
      bufnrs = bufnrs,
      get_diagnostics = scan_diagnostics,
      debounce_ms = 5000,
      -- once every watched buffer has reported, the long debounce is dead
      -- air; finalise after a short settle instead
      settled_debounce_ms = 500,
      -- ...unless a sonarlint client is attached to a scanned buffer: a
      -- buffer's *first* report comes from its fastest LSP, while sonarlint's
      -- java analyzers publish seconds later; the 5s debounce exists for
      -- exactly that gap, so keep it. a cold sonarlint JVM isn't attached by
      -- settle time, but its results arrive long after the old 5s window too,
      -- so the fast path loses nothing there
      settle_check = function()
        for _, client in ipairs(vim.lsp.get_clients { name = 'sonarlint.nvim' }) do
          for _, b in ipairs(bufnrs) do
            if (client.attached_buffers or {})[b] then
              return false
            end
          end
        end
        return true
      end,
      hard_timeout_ms = 5 * 60 * 1000,
      qf_title = opts.qf_title,
      qf_label = opts.qf_label,
      augroup_name = opts.augroup_name,
      on_report = progress and function(reported)
        progress:report { message = (scanned + reported) .. '/' .. #readable .. ' file(s) reported' }
      end or nil,
      -- batched tail: accumulate this chunk's items, tear its created buffers
      -- down (releasing them from roslyn's open-doc set), then start the next
      on_complete = function(items)
        pcall(vim.api.nvim_del_augroup_by_id, pull_group)
        for _, item in ipairs(items) do
          table.insert(all_items, item)
        end
        for _, b in ipairs(created) do
          if vim.api.nvim_buf_is_valid(b) then
            pcall(vim.api.nvim_buf_delete, b, { force = true })
          end
        end
        scanned = scanned + #chunk
        if progress then
          pcall(function()
            progress:report { message = scanned .. '/' .. #readable .. ' file(s) scanned' }
          end)
        end
        -- defer so the buffer-delete didClose round-trips and roslyn drops the
        -- chunk before the next chunk's didOpen lands; otherwise the open sets
        -- briefly overlap and peak memory creeps back up
        vim.schedule(function()
          run_batch(idx + 1)
        end)
      end,
    }

    -- sequential batching always starts from a clean scan_runner, so this
    -- should never fire; if it ever does, don't wedge the lock or leak the
    -- chunk's buffers; clean up and finish with what we have
    if not started then
      pcall(vim.api.nvim_del_augroup_by_id, pull_group)
      for _, b in ipairs(created) do
        if vim.api.nvim_buf_is_valid(b) then
          pcall(vim.api.nvim_buf_delete, b, { force = true })
        end
      end
      vim.notify('Scan aborted: runner busy', vim.log.levels.WARN)
      finish_all()
    end
  end

  run_batch(1)
end

-- modified-file discovery shared with <leader>lm and <leader>sm
-- (features/ticket.lua), so scan and picker operate on the same set
local function open_git_modified()
  local paths = require('custom.features.ticket').modified_files()
  if not paths then
    return
  end
  if #paths == 0 then
    vim.notify('No modified files', vim.log.levels.INFO)
    return
  end
  scan_files(paths, {
    qf_title = 'Modified: diagnostics',
    qf_label = 'Modified',
    augroup_name = 'GitModifiedScan',
    empty_message = 'No readable modified files',
  })
end

-- branch-total scan: the diagnostic-scan analogue of <leader>dt. same
-- merge-base discovery (shared via features/ticket.lua) but instead of opening a
-- diff it scans every file changed on the branch vs main and dumps their
-- diagnostics into the quickfix
local function open_branch_scan()
  local paths = require('custom.features.ticket').branch_files()
  if not paths then
    return
  end
  if #paths == 0 then
    vim.notify('No files changed vs main', vim.log.levels.INFO)
    return
  end
  scan_files(paths, {
    qf_title = 'Branch: diagnostics',
    qf_label = 'Branch',
    augroup_name = 'GitBranchScan',
    empty_message = 'No readable files changed vs main',
  })
end

-- whole-project scan: the all-LSP analogue of sonar's <leader>lS. hidden-loads
-- every tracked-or-untracked file so every LSP attaches, in the same bounded
-- batches as the git-scoped scans. unlike those, the file set is unbounded, so
-- a confirm guards runs above PROJECT_SCAN_CAP (roslyn et al. are heavy and the
-- repo-wide finding set is noisy)
local PROJECT_SCAN_CAP = 500

local function project_files()
  local cwd = vim.fn.getcwd()
  local result = vim.system({ 'git', 'ls-files', '-co', '--exclude-standard' }, { text = true, cwd = cwd }):wait()
  if result.code ~= 0 then
    return nil
  end
  local paths = {}
  for line in (result.stdout or ''):gmatch '[^\r\n]+' do
    table.insert(paths, cwd .. '/' .. line)
  end
  return paths
end

local function open_project_scan()
  local paths = project_files()
  if not paths then
    vim.notify('Not a git repository', vim.log.levels.WARN)
    return
  end
  if #paths == 0 then
    vim.notify('No files in project', vim.log.levels.INFO)
    return
  end

  local function go()
    scan_files(paths, {
      qf_title = 'Project: diagnostics',
      qf_label = 'Project',
      augroup_name = 'GitProjectScan',
      empty_message = 'No readable project files',
    })
  end

  if #paths > PROJECT_SCAN_CAP then
    vim.ui.select({ 'Yes', 'No' }, {
      prompt = 'Scan ' .. #paths .. ' files (>' .. PROJECT_SCAN_CAP .. ')?',
    }, function(choice)
      if choice == 'Yes' then
        go()
      end
    end)
  else
    go()
  end
end

-- ticket-scoped scan: same commit discovery as <leader>dT and <leader>lT
-- (shared via features/ticket.lua) but instead of opening a diff it scans
-- the union of files touched by exactly the matched commits and dumps their
-- diagnostics into the quickfix
local function open_ticket_scan()
  if scan_in_progress() then
    vim.notify('A scan is already running', vim.log.levels.WARN)
    return
  end

  local ticket = require 'custom.features.ticket'
  ticket.prompt_commits(function(ctx)
    local paths = ticket.commit_files(ctx)
    if not paths then
      return
    end

    vim.notify(#ctx.commits .. ' commit(s) matching "' .. ctx.input .. '", ' .. #paths .. ' file(s)', vim.log.levels.INFO)
    scan_files(paths, {
      qf_title = 'Ticket: diagnostics',
      qf_label = 'Ticket',
      augroup_name = 'GitTicketScan',
      empty_message = 'No readable files in matching commits',
    })
  end)
end

function M.setup()
  vim.keymap.set('n', '<leader>xm', open_git_modified, { desc = 'Git [M]odified → diagnostics qf' })
  vim.keymap.set('n', '<leader>xb', open_branch_scan, { desc = '[B]ranch vs main → diagnostics qf' })
  vim.keymap.set('n', '<leader>xT', open_ticket_scan, { desc = 'Git [T]icket commits → diagnostics qf' })
  vim.keymap.set('n', '<leader>xS', open_project_scan, { desc = 'Whole project [S]can → diagnostics qf' })

  vim.api.nvim_create_user_command('GitModified', open_git_modified, { desc = 'Open git-modified files and dump diagnostics to quickfix' })
  vim.api.nvim_create_user_command('BranchScan', open_branch_scan, { desc = 'Scan all files changed vs main and dump diagnostics to quickfix' })
  vim.api.nvim_create_user_command('TicketScan', open_ticket_scan, { desc = 'Scan files from ticket-matching commits and dump diagnostics to quickfix' })
  vim.api.nvim_create_user_command('ProjectScan', open_project_scan, { desc = 'Scan every project file and dump diagnostics to quickfix' })

  -- wrap every roslyn client at attach so `workspace/projectInitializationComplete`
  -- is observed even on warm-start scans (the notification only fires once per
  -- client lifetime; by the time the user runs <leader>xm later, the wrap
  -- needs to already exist for `__git_modified_init_done` to be trustworthy)
  vim.api.nvim_create_autocmd('LspAttach', {
    group = vim.api.nvim_create_augroup('GitModifiedRoslynWrap', { clear = true }),
    callback = function(args)
      local client = vim.lsp.get_client_by_id(args.data.client_id)
      if client and client.name == 'roslyn' then
        wrap_roslyn(client)
      end
    end,
  })
end

return M
