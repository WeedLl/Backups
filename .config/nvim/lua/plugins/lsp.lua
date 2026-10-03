-- mason: грузим сразу (нужен для установки LSP-серверов)
vim.pack.add({
  "https://github.com/williamboman/mason.nvim",
  "https://github.com/williamboman/mason-lspconfig.nvim",
})
require("mason").setup()
require("mason-lspconfig").setup({
  -- ruff — линтер+форматер Python на Rust
  ensure_installed = { "pyright", "clangd", "ruff" },
})

-- lspconfig: ленивая загрузка при открытии файла
vim.pack.add({
  "https://github.com/neovim/nvim-lspconfig",
}, { load = function() end })

vim.api.nvim_create_autocmd({ "BufReadPre", "BufNewFile" }, {
  group = vim.api.nvim_create_augroup("LspLazy", { clear = true }),
  once = true,
  callback = function()
    vim.cmd.packadd("nvim-lspconfig")
    require("configs.lsp")
  end,
})

