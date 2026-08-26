return {

  { -- Linting
    'mfussenegger/nvim-lint',
    event = { 'BufReadPre', 'BufNewFile' },
    config = function()
      local lint = require 'lint'
      lint.linters_by_ft = {
        swift = { 'swiftlint' },
      }

      -- Create autocommand which carries out the actual linting
      -- on the specified events.
      local lint_augroup = vim.api.nvim_create_augroup('lint', { clear = true })
      vim.api.nvim_create_autocmd({ 'BufEnter', 'BufWritePost', 'InsertLeave' }, {
        group = lint_augroup,
        callback = function()
          -- Only run the linter in buffers that you can modify in order to
          -- avoid superfluous noise, notably within the handy LSP pop-ups that
          -- describe the hovered symbol using Markdown.
          if not vim.bo.modifiable then
            return
          end
          local runnable = {}
          for _, name in ipairs(lint.linters_by_ft[vim.bo.filetype] or {}) do
            -- a linter module is either the spec table or a factory returning
            -- one (swiftlint varies its args on whether a .swiftlint.yml is in
            -- play). resolve the factory first or the executable check below
            -- reads `cmd` off a function and silently drops the linter
            local linter = lint.linters[name]
            if type(linter) == 'function' then
              linter = linter()
            end
            local cmd = type(linter) == 'table' and (type(linter.cmd) == 'function' and linter.cmd() or linter.cmd)
            if cmd and vim.fn.executable(cmd) == 1 then
              table.insert(runnable, name)
            end
          end
          if #runnable > 0 then
            lint.try_lint(runnable)
          end
        end,
      })
    end,
  },
}
