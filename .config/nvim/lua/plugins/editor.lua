-- Treesitter: ленивая загрузка при открытии файла
vim.pack.add({
  { src = "https://github.com/nvim-treesitter/nvim-treesitter", version = "main" },
}, { load = function() end })

vim.api.nvim_create_autocmd({ "BufReadPost", "BufNewFile" }, {
  group = vim.api.nvim_create_augroup("TreesitterLazy", { clear = true }),
  once = true,
  callback = function()
    vim.cmd.packadd("nvim-treesitter")
    require("configs.treesitter")
  end,
})

-- Tabular и vim-pdf: лёгкие vimscript-плагины, грузим сразу
vim.pack.add({
  "https://github.com/godlygeek/tabular",
  "https://github.com/makerj/vim-pdf",
})

-- conform.nvim: форматирование кода
-- Ленивая загрузка при открытии файла (форматирование может сработать на сохранении)
vim.pack.add({
  "https://github.com/stevearc/conform.nvim",
}, { load = function() end })

vim.api.nvim_create_autocmd({ "BufReadPre", "BufNewFile" }, {
  group = vim.api.nvim_create_augroup("ConformLazy", { clear = true }),
  once = true,
  callback = function()
    vim.cmd.packadd("conform.nvim")
    require("configs.conform")
  end,
})

