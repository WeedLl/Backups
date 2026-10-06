-- mason: грузим сразу (нужен для установки LSP-серверов)
vim.pack.add({
	"https://github.com/williamboman/mason.nvim",
	"https://github.com/williamboman/mason-lspconfig.nvim",
	"https://github.com/WhoIsSethDaniel/mason-tool-installer.nvim",
	"https://github.com/folke/lazydev.nvim",
})

require("mason").setup()
-- LSP-серверы — автоустановка через mason-lspconfig
require("mason-lspconfig").setup({
	-- ruff — линтер+форматер Python на Rust
	ensure_installed = { "pyright", "clangd", "ruff", "lua_ls" },
})
-- Форматеры, линтеры и прочие non-LSP инструменты
require("mason-tool-installer").setup({
	ensure_installed = { "stylua" },
	auto_update = true,
})
-- lazydev: настраивает lua_ls для понимания Neovim API
-- должен быть загружен до старта lua_ls
require("lazydev").setup({
	library = {
		{ path = "${3rd}/luv/library", words = { "vim%.uv" } },
	},
	integrations = {
		cmp = false, -- нет nvim-cmp, используем blink.cmp
		lspconfig = false, -- используем vim.lsp.config, не lspconfig.setup()
	},
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
