-- Plugin specifications loader
-- Each file returns a table of plugin specs

return {
  { import = 'custom.plugins.ui' },
  { import = 'custom.plugins.editor' },
  { import = 'custom.plugins.telescope' },
  { import = 'custom.plugins.lsp' },
  { import = 'custom.plugins.completion' },
  { import = 'custom.plugins.git' },
  { import = 'custom.plugins.copilot' },
}
