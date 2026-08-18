-- core autocommands

-- custom filetype detection
vim.filetype.add {
  extension = {
    template = 'template',
  },
}

local M = {}

function M.setup()
  -- highlight on yank, and mirror only yanks (not deletes/changes) to the
  -- system clipboard. clipboard is otherwise decoupled (see options.lua), so
  -- d/c/x leave the clipboard untouched while y still syncs it. tmux also
  -- needs `set-clipboard on` so the clipboard reaches the outer terminal.
  vim.api.nvim_create_autocmd('TextYankPost', {
    desc = 'Highlight on yank; sync yanks to the system clipboard',
    group = vim.api.nvim_create_augroup('kickstart-highlight-yank', { clear = true }),
    callback = function()
      vim.hl.on_yank()
      if vim.v.event.operator == 'y' then
        vim.fn.setreg('+', vim.v.event.regcontents, vim.v.event.regtype)
      end
    end,
  })

  -- auto-reload: check for external changes on focus/cursor events.
  -- BufEnter is deliberately omitted: it cascades :checktime across every
  -- loaded buffer each time a plugin (e.g. differ) spawns buffers, which
  -- can race with the autosave below and surface a `(L)oad File` prompt
  -- when `autoread` is bypassed by a transiently modified buffer.
  local reload_group = vim.api.nvim_create_augroup('auto-reload', { clear = true })
  vim.api.nvim_create_autocmd({ 'FocusGained', 'CursorHold' }, {
    desc = 'Check for external file changes',
    group = reload_group,
    callback = function()
      if vim.fn.getcmdwintype() == '' then
        vim.cmd.checktime()
      end
    end,
  })

  -- force reload on external change. `autoread` is silently bypassed when a
  -- buffer is `modified` (e.g. a plugin's transient mid-layout buffers), which
  -- surfaces the `(L)oad File` prompt. auto-save below flushes local edits to
  -- disk on focus/buffer leave, so discarding the in-memory copy is safe.
  vim.api.nvim_create_autocmd('FileChangedShell', {
    desc = 'Always reload externally-changed files without prompting',
    group = reload_group,
    callback = function()
      vim.v.fcs_choice = 'reload'
    end,
  })

  -- restore the cursor to the `"` mark, centred. the deferred zz has to
  -- re-check the window: a background bufload runs this in a throwaway autocmd
  -- window that is gone by the time the schedule fires, and an unguarded zz
  -- would recentre whichever window happens to be current instead. git reuses
  -- one path for commit messages, so its mark points into the previous one
  vim.api.nvim_create_autocmd('BufReadPost', {
    callback = function(args)
      if vim.tbl_contains({ 'gitcommit', 'gitrebase' }, vim.bo[args.buf].filetype) then
        return
      end
      local mark = vim.api.nvim_buf_get_mark(args.buf, '"')
      if mark[1] < 1 or mark[1] > vim.api.nvim_buf_line_count(args.buf) then
        return
      end
      local win = vim.api.nvim_get_current_win()
      vim.api.nvim_win_set_cursor(win, mark)
      vim.schedule(function()
        if vim.api.nvim_win_is_valid(win) and vim.api.nvim_win_get_buf(win) == args.buf then
          vim.api.nvim_win_call(win, function()
            vim.cmd 'normal! zz'
          end)
        end
      end)
    end,
  })

  -- auto-save: write buffer on text change and on focus/buffer leave.
  -- FocusLost/BufLeave guarantee the buffer is clean before an external
  -- agent edits the file, so the FocusGained checktime above can silently
  -- reload via `autoread` instead of prompting.
  local autosave_group = vim.api.nvim_create_augroup('auto-save', { clear = true })
  vim.api.nvim_create_autocmd({ 'InsertLeave', 'TextChanged', 'FocusLost', 'BufLeave' }, {
    desc = 'Auto-save on text change or focus loss',
    group = autosave_group,
    callback = function(ev)
      local buf = ev.buf
      -- only save if: buffer is modifiable, has a file, is modified, and not a special buffer
      if vim.bo[buf].modifiable and vim.bo[buf].modified and vim.fn.bufname(buf) ~= '' and vim.bo[buf].buftype == '' then
        vim.api.nvim_buf_call(buf, function()
          vim.cmd 'silent! write'
        end)
      end
    end,
  })

  -- write vault notes IN PLACE, never rename-and-replace.
  --
  -- with the default `backupcopy=auto`, vim is free to implement a write by
  -- renaming the original out of the way and creating a new file at the same
  -- path. that is invisible locally, but if ~/obsidian is watched by
  -- livesync-bridge, it sees the rename as an `unlink` and replicates a
  -- genuine DELETE of the note to CouchDB, which propagates to every device,
  -- immediately followed by a re-create
  --
  -- `backupcopy=yes` forces copy-then-overwrite, so the original inode survives
  -- and the watcher reports a plain `change`. buffer-local because it is only
  -- correct where something is watching; elsewhere `auto` is faster.
  -- (services/mirror-notes.sh in ~/nextcloud avoids the same trap by copying in
  -- place rather than temp+rename - same reasoning, different tool.)
  local vault_group = vim.api.nvim_create_augroup('vault-inplace-write', { clear = true })
  vim.api.nvim_create_autocmd({ 'BufReadPre', 'BufNewFile' }, {
    desc = 'Write vault notes in place so the sync watcher sees no delete',
    group = vault_group,
    pattern = vim.env.HOME .. '/obsidian/*',
    callback = function()
      vim.bo.backupcopy = 'yes'
    end,
  })

  -- auto-show diagnostic float on cursor hold; hide virtual_text while float is open
  local diag_float_group = vim.api.nvim_create_augroup('diagnostic-float', { clear = true })
  local vtext_hidden = false

  -- close any diagnostic float we previously opened. open_float's own
  -- close_events are racy (they miss window/buffer switches and can orphan the
  -- window if a new CursorHold re-opens before the one-shot close fires), so we
  -- track the handle ourselves and close it deterministically.
  local function close_diag_float()
    local win = vim.b._diag_float_win
    if win and vim.api.nvim_win_is_valid(win) then
      pcall(vim.api.nvim_win_close, win, true)
    end
    vim.b._diag_float_win = nil
  end

  vim.api.nvim_create_autocmd('CursorHold', {
    desc = 'Show diagnostic float and suppress virtual text',
    group = diag_float_group,
    callback = function()
      -- skip diagnostic float while LSP hover is open
      if vim.b._hover_open then
        return
      end
      close_diag_float()
      local _, win = vim.diagnostic.open_float(nil, { focusable = false, scope = 'cursor' })
      if win then
        vim.b._diag_float_win = win
        vtext_hidden = true
        vim.diagnostic.config { virtual_text = false }
      end
    end,
  })

  vim.api.nvim_create_autocmd({ 'CursorMoved', 'CursorMovedI', 'InsertEnter', 'BufLeave', 'WinLeave' }, {
    desc = 'Close diagnostic float and restore virtual text',
    group = diag_float_group,
    callback = function()
      vim.b._hover_open = nil
      close_diag_float()
      if vtext_hidden then
        vtext_hidden = false
        vim.diagnostic.config { virtual_text = { source = 'if_many', spacing = 2 } }
      end
    end,
  })

  -- link LSP variable tokens to TreeSitter's @variable styling. leaving the
  -- group empty does not let lower-priority TreeSitter captures show through;
  -- the semantic token still wins, just with Normal-like styling.
  vim.api.nvim_create_autocmd('ColorScheme', {
    desc = 'Use TreeSitter variable styling for LSP variable tokens',
    group = vim.api.nvim_create_augroup('lsp-semantic-token-overrides', { clear = true }),
    callback = function()
      vim.api.nvim_set_hl(0, '@lsp.type.variable', { link = '@variable' })
    end,
  })
  -- apply immediately for the current colourscheme
  vim.api.nvim_set_hl(0, '@lsp.type.variable', { link = '@variable' })

  -- Lazy.nvim links `LazyDimmed` to `Conceal` for low-value commits
  -- (chore/deps bumps). Conceal is built for hiding chars, so on most dark
  -- themes the dimmed lines are effectively invisible. re-link to Comment,
  -- which is tuned for legible-but-subdued text.
  vim.api.nvim_create_autocmd('ColorScheme', {
    desc = 'Make Lazy.nvim dimmed commit lines legible',
    group = vim.api.nvim_create_augroup('lazy-dimmed-readable', { clear = true }),
    callback = function()
      vim.api.nvim_set_hl(0, 'LazyDimmed', { link = 'Comment' })
    end,
  })
  vim.api.nvim_set_hl(0, 'LazyDimmed', { link = 'Comment' })

  -- vim.snippet paints the active tabstop with SnippetTabstop, which defaults
  -- to Visual: a bright block over the argument just typed after accepting an
  -- LSP call snippet (e.g. gopls). re-link to the subtle LspReference band
  -- every theme defines. SnippetTabstopActive links here by default
  local snippet_group = vim.api.nvim_create_augroup('snippet-tabstop', { clear = true })
  vim.api.nvim_create_autocmd('ColorScheme', {
    desc = 'Subtle snippet tabstop highlight',
    group = snippet_group,
    callback = function()
      vim.api.nvim_set_hl(0, 'SnippetTabstop', { link = 'LspReferenceText' })
    end,
  })
  vim.api.nvim_set_hl(0, 'SnippetTabstop', { link = 'LspReferenceText' })

  -- the built-in session only ends on cursor moves in insert/select mode, so
  -- Esc leaves the tabstop extmark (and its highlight) alive indefinitely.
  -- end it on return to normal mode; `*:n` (not InsertLeave) so tabstop jumps
  -- via select mode survive
  vim.api.nvim_create_autocmd('ModeChanged', {
    desc = 'Stop snippet session on return to normal mode',
    group = snippet_group,
    pattern = '*:n',
    callback = function()
      if vim.snippet.active() then
        vim.snippet.stop()
      end
    end,
  })

  -- dynamic diff highlights (differ, octo)
  local diff_highlights = require 'custom.core.diff-highlights'
  diff_highlights.setup()

  -- render-markdown links code blocks to ColorColumn by default, which
  -- collides with our CursorLine tint. give markdown code its own subtle
  -- background derived from the active theme palette.
  local function apply_markdown_code_highlights()
    local function get(group, fallback)
      local hl = vim.api.nvim_get_hl(0, { name = group, link = false })
      return hl.bg or hl.fg or fallback
    end

    local cursorline_bg = get('CursorLine', 0x2a2a2a)
    local colorcolumn_bg = get('ColorColumn', cursorline_bg)
    local normal_fg = get('Normal', 0xd4d4d4)
    local code_bg = diff_highlights.tint_bg(colorcolumn_bg, 0.35)
    local inline_bg = diff_highlights.tint_bg(normal_fg, 0.10)

    vim.api.nvim_set_hl(0, 'RenderMarkdownCode', { bg = code_bg })
    vim.api.nvim_set_hl(0, 'RenderMarkdownCodeBorder', { bg = code_bg })
    vim.api.nvim_set_hl(0, 'RenderMarkdownCodeInline', { bg = inline_bg })
    vim.api.nvim_set_hl(0, 'RenderMarkdownInlineHighlight', { bg = inline_bg })
  end

  vim.api.nvim_create_autocmd('ColorScheme', {
    desc = 'Make render-markdown code blocks distinct from CursorLine',
    group = vim.api.nvim_create_augroup('render-markdown-highlights', { clear = true }),
    callback = apply_markdown_code_highlights,
  })
  apply_markdown_code_highlights()

  -- disable swap file for Octo buffers (not needed and causes warnings)
  vim.api.nvim_create_autocmd('FileType', {
    pattern = 'octo',
    callback = function()
      vim.bo.swapfile = false
    end,
  })

  -- fire `User RealDotnetFile` only for cs/razor outside a review context.
  -- lets heavy dotnet plugins (roslyn.nvim) lazy-load on this event instead
  -- of `ft = 'cs'`, so cold-start `<leader>do` from a dashboard doesn't pay
  -- their config cost just to render diff buffers. buftype alone isn't
  -- checked in isolation, so also gate on any loaded octo buffer.
  local review_context = require 'custom.core.review-context'

  vim.api.nvim_create_autocmd('FileType', {
    pattern = { 'cs', 'razor' },
    callback = function(args)
      if vim.bo[args.buf].buftype ~= '' then
        return
      end
      if review_context.is_active() then
        return
      end
      vim.api.nvim_exec_autocmds('User', { pattern = 'RealDotnetFile' })
    end,
  })

  -- sort JSON keys (strip trailing commas, sort with jq, reformat with prettier)
  local function sort_json_keys(buf)
    local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    local content = table.concat(lines, '\n')
    local result = vim.fn.system([[set -o pipefail; perl -0777 -pe 's/,(\s*[\]}])/$1/g' | jq -S . | prettier --parser json]], content)
    if vim.v.shell_error == 0 then
      local new_lines = vim.split(result, '\n', { trimempty = true })
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, new_lines)
    else
      vim.notify('JsonSort failed: ' .. result, vim.log.levels.ERROR)
    end
  end

  vim.api.nvim_create_user_command('JsonSort', function()
    sort_json_keys(vim.api.nvim_get_current_buf())
  end, { desc = 'Sort JSON keys' })

  vim.lsp.commands['json.sort'] = function(_, ctx)
    sort_json_keys(ctx.bufnr)
  end

  -- graceful process cleanup on exit
  -- explicitly stops LSP servers and terminal jobs so they don't orphan
  -- (dotnet Roslyn, OmniSharp, EasyDotnet build servers, etc.)
  vim.api.nvim_create_autocmd('VimLeavePre', {
    desc = 'Stop LSP clients, DAP, and terminal jobs on exit',
    group = vim.api.nvim_create_augroup('cleanup-on-exit', { clear = true }),
    callback = function()
      -- stop all LSP clients (Roslyn, OmniSharp, etc.)
      for _, client in ipairs(vim.lsp.get_clients()) do
        client:stop(true)
      end

      -- terminate debug adapter if running. only when dap is already loaded:
      -- requiring it here pulls the whole plugin in at exit (~18ms) just to
      -- terminate a session that cannot exist if it was never loaded
      if package.loaded['dap'] then
        pcall(function()
          require('dap').terminate()
        end)
      end

      -- close all terminal buffers (forces child process termination)
      for _, buf in ipairs(vim.api.nvim_list_bufs()) do
        if vim.api.nvim_buf_is_valid(buf) and vim.bo[buf].buftype == 'terminal' then
          pcall(vim.api.nvim_buf_delete, buf, { force = true })
        end
      end
    end,
  })

  -- clean up unnamed empty buffers when opening a file
  -- removes the default [No Name] buffer that nvim creates at startup
  -- deferred via vim.schedule to avoid interfering with plugin layout creation
  -- (a plugin's window-splitting during layout setup can trigger BufEnter mid-layout)
  local cleanup_group = vim.api.nvim_create_augroup('cleanup-empty-buffers', { clear = true })
  vim.api.nvim_create_autocmd('BufEnter', {
    desc = 'Delete unnamed empty buffers',
    group = cleanup_group,
    callback = function()
      vim.schedule(function()
        for _, buf in ipairs(vim.api.nvim_list_bufs()) do
          if
            vim.api.nvim_buf_is_valid(buf)
            and vim.fn.bufname(buf) == ''
            and vim.api.nvim_buf_line_count(buf) == 1
            and vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1] == ''
            and not vim.bo[buf].modified
            and buf ~= vim.api.nvim_get_current_buf()
            and vim.bo[buf].buftype == ''
          then
            vim.api.nvim_buf_delete(buf, { force = true })
          end
        end
      end)
    end,
  })
end

return M
