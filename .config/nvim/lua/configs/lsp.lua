-- Унификация кодировки позиций для всех LSP-клиентов
vim.lsp.config("*", {
	capabilities = {
		general = {
			positionEncodings = { "utf-16" },
		},
	},
})
-- ============================================================
-- Python
-- ============================================================

-- Pyright: проверка типов, автодополнение, go-to-definition
vim.lsp.config("pyright", {
	settings = {
		python = {
			-- Путь к виртуальному окружению (если есть)
			-- analysis = {
			--   extraPaths = { "./src", "./lib" },
			-- },
		},
	},
})
vim.lsp.enable("pyright")

-- Ruff: линтинг + форматирование через LSP
-- Заменяет flake8 + isort + black
vim.lsp.config("ruff", {
	init_options = {
		settings = {
			args = {
				"--select=E,F,W,I", -- E/W = pycodestyle, F = pyflakes, I = isort
				"--line-length=120", -- как ваш colorcolumn
				"--ignore=E501", -- не ругаться на длину строк
			},
		},
	},
})
vim.lsp.enable("ruff")

-- ============================================================
-- Lua (для редактирования конфига Neovim)
-- ============================================================

vim.lsp.config("lua_ls", {
	settings = {
		Lua = {
			completion = { callSnippet = "Replace" },
			diagnostics = { globals = { "vim" } },
			workspace = {
				checkThirdParty = false,
			},
		},
	},
})
vim.lsp.enable("lua_ls")

-- ============================================================
-- C/C++ (замена YCM --clang-completer)
-- ============================================================

vim.lsp.config("clangd", {})
vim.lsp.enable("clangd")

-- ============================================================
-- Семантическая подсветка (semantic tokens)
-- ============================================================

-- Включаем обработку semantic tokens от LSP
-- Pyright отдаёт токены: variable, function, class, parameter и т.д.
-- Цвета связываются в gruvbox.nvim (см. configs/gruvbox.lua)
vim.lsp.semantic_tokens.enable(true)

-- ============================================================
-- Диагностика
-- ============================================================

vim.diagnostic.config({
	virtual_text = true, -- текст ошибок прямо в строке
	signs = true, -- значки в gutter
	underline = true, -- подчёркивание ошибок
	update_in_insert = false, -- не обновлять диагностику в insert-режиме
})

-- Клавиши (замена <leader>d, <leader>e из YCM)
vim.keymap.set("n", "<leader>d", vim.diagnostic.setloclist, { desc = "Open diagnostic list" })
vim.keymap.set("n", "<leader>e", vim.diagnostic.open_float, { desc = "Show diagnostic under cursor" })

-- LSP-маппинги (замена YCM)
vim.keymap.set("n", "gd", vim.lsp.buf.definition, { desc = "Go to definition" })
vim.keymap.set("n", "K", vim.lsp.buf.hover, { desc = "Hover docs" })
vim.keymap.set("n", "gr", vim.lsp.buf.references, { desc = "References" })
vim.keymap.set("n", "<leader>rn", vim.lsp.buf.rename, { desc = "Rename" })
vim.keymap.set("n", "<leader>ca", vim.lsp.buf.code_action, { desc = "Code action" })
