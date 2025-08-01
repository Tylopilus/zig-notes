-- Manual didOpen command for testing LSP server
-- Run this in Neovim with: :luafile manual_didopen.lua

vim.lsp.buf_notify(0, "textDocument/didOpen", {
  textDocument = {
    uri = vim.uri_from_bufnr(0),
    languageId = "markdown",
    version = 1,
    text = table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), "\n")
  }
})

print("Sent didOpen notification to LSP server")