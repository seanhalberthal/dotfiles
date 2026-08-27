-- Roslyn diagnostic post-processing. extracted from plugins/dotnet.lua.
-- wraps vim.diagnostic.set to drop known false positives, silence
-- simplification hints inside XML doc comments, blank out decompiled
-- metadata-source buffers, and dedupe diagnostics reported from multiple
-- .csproj contexts. see .claude/rules/neovim_dotnet.md

local M = {}

--- wrap vim.diagnostic.set to filter Roslyn false positives and deduplicate
--- diagnostics reported from multiple .csproj contexts (cross-namespace)
function M.patch_diagnostic_set()
  local orig = vim.diagnostic.set
  local false_positives = { IDE0005 = true, IDE0079 = true, CA1825 = true }
  local buf_owners = {} ---@type table<integer, table<string, integer>>

  --- suppress Roslyn style/suggestion diagnostics whose span lands inside
  --- XML doc comments. Roslyn can report simplification-style IDE hints on
  --- `<see cref="...">` targets, which is technically analyzable but noisy.
  --- keep warnings/errors so malformed XML docs and compiler diagnostics still
  --- surface normally
  ---@param bufnr integer
  ---@param d vim.Diagnostic
  ---@return boolean
  local function is_doc_comment_style_hint(bufnr, d)
    if d.severity ~= vim.diagnostic.severity.HINT and d.severity ~= vim.diagnostic.severity.INFO then
      return false
    end
    if type(d.lnum) ~= 'number' then
      return false
    end

    local line = vim.api.nvim_buf_get_lines(bufnr, d.lnum, d.lnum + 1, false)[1]
    if not line or not line:match '^%s*///' then
      return false
    end

    local code = d.code and tostring(d.code) or ''
    return code:match '^IDE' or (d.source == 'Style') or ((d.message or ''):match 'simplif')
  end

  vim.diagnostic.set = function(namespace, bufnr, diagnostics, diag_opts)
    if not (bufnr and vim.api.nvim_buf_is_valid(bufnr) and vim.bo[bufnr].filetype == 'cs') then
      return orig(namespace, bufnr, diagnostics, diag_opts)
    end

    -- suppress diagnostics on decompiled metadata source (read-only library code)
    if vim.api.nvim_buf_get_name(bufnr):match 'MetadataAsSource' then
      return orig(namespace, bufnr, {}, diag_opts)
    end

    -- clear this namespace's previous ownership claims
    if not buf_owners[bufnr] then
      buf_owners[bufnr] = {}
    end
    for key, ns in pairs(buf_owners[bufnr]) do
      if ns == namespace then
        buf_owners[bufnr][key] = nil
      end
    end

    -- filter false positives and deduplicate across namespaces
    local deduped = {}
    for _, d in ipairs(diagnostics) do
      if not false_positives[d.code] and not is_doc_comment_style_hint(bufnr, d) then
        -- use lnum:col:code when code is present (ignores message variations
        -- between push/pull channels or multi-project contexts).
        -- fall back to message when code is absent
        local key = d.code and (d.lnum .. ':' .. d.col .. ':' .. d.code) or (d.lnum .. ':' .. d.col .. ':' .. d.message)
        if not buf_owners[bufnr][key] then
          buf_owners[bufnr][key] = namespace
          table.insert(deduped, d)
        end
      end
    end

    return orig(namespace, bufnr, deduped, diag_opts)
  end

  vim.api.nvim_create_autocmd('BufWipeout', {
    callback = function(ev)
      buf_owners[ev.buf] = nil
    end,
  })
end

return M
