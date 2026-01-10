-- GitHub Copilot configuration

return {
  {
    'github/copilot.vim',
    config = function()
      -- Disable Copilot for sensitive files
      vim.api.nvim_create_autocmd({ 'BufEnter', 'BufNew' }, {
        pattern = {
          '.env*',
          '*.env',
          '*secret*',
          '*credential*',
          '*.key',
          '*.pem',
          '*.secrets.zsh',
        },
        callback = function()
          vim.b.copilot_enabled = false
        end,
      })
    end,
  },
}
