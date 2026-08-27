-- monkeypatches to vim.lsp internals. extracted from plugins/lsp.lua.
-- patch_lsp_start blocks LSP attach to non-file:// scheme buffers;
-- patch_show_document recovers from servers reporting invalid cursor ranges.

local M = {}

--- prevent LSP servers from attaching to non-file:// buffers (differ://,
--- octo://, fugitive://, etc.). without this, servers like gopls log JSON-RPC
--- parse errors when nvim sends didOpen with a non-file URI
function M.patch_lsp_start()
  local orig_start = vim.lsp.start
  vim.lsp.start = function(config, opts)
    opts = opts or {}
    local bufnr = opts.bufnr or vim.api.nvim_get_current_buf()
    -- buffer can be wiped between when lsp_enable_callback queues the start
    -- and when this scheduled callback fires (e.g. differ disposing diff
    -- buffers); abort silently in that case
    if not vim.api.nvim_buf_is_valid(bufnr) then
      return nil
    end
    local name = vim.api.nvim_buf_get_name(bufnr)
    if name:match '^%w[%w+.-]*://' and not name:match '^file://' then
      return nil
    end
    return orig_start(config, opts)
  end
end

--- override show_document to handle cursor-position-outside-buffer errors
--- from LSP servers that report invalid ranges
function M.patch_show_document()
  local orig = vim.lsp.util.show_document
  vim.lsp.util.show_document = function(location, offset_encoding, opts)
    local ok, ret = pcall(orig, location, offset_encoding, opts)
    if ok then
      return ret
    end
    if ret:match 'Cursor position outside buffer' then
      local uri = location.uri or location.targetUri
      if uri then
        vim.cmd('edit ' .. vim.uri_to_fname(uri))
        vim.notify('Jumped to file (cursor position was invalid)', vim.log.levels.WARN)
        return true
      end
    end
    error(ret)
  end
end

return M
