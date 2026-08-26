-- lazydev.nvim: feed lua_ls the type definitions for plugins we use, loaded
-- on demand. without this, plugin globals like `Snacks`/`Mini*` are only listed
-- in .luarc.json's `diagnostics.globals` (which silences the undefined-global
-- warning but gives them no type), so `K` hover and completion show nothing.
-- each `words` pattern triggers loading that plugin's library when the pattern
-- appears in the buffer, keeping the workspace index lean

return {
  {
    'folke/lazydev.nvim',
    ft = 'lua',
    opts = {
      library = {
        { path = 'snacks.nvim', words = { 'Snacks' } },
        { path = 'mini.nvim', words = { 'Mini' } },
        -- luvit types when `vim.uv` is used
        { path = '${3rd}/luv/library', words = { 'vim%.uv' } },
        -- busted/luassert types in spec files. `words` are lua patterns, run
        -- through line:find with no plain flag, so there is no `it%s*%(`
        -- trigger: it would match inside `split(`/`edit(`/`wait(`. busted's
        -- library declares `it` alongside `describe`, so one trigger covers
        -- a whole spec file
        { path = '${3rd}/busted/library', words = { 'describe%s*%(' } },
        { path = '${3rd}/luassert/library', words = { 'assert%.' } },
      },
    },
  },
}
