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
			runtime = { version = "LuaJIT" }, -- проверка lua кода по стандартку LuaJIT, а не Lua 5.4
			completion = { callSnippet = "Replace" },
			diagnostics = { globals = { "vim", "require", "pcall" } },
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
-- Shell (Bash + Zsh) через shuck
-- ============================================================
-- Единый LSP для Bash, sh и Zsh. Написан на Rust, поддерживает
-- оба диалекта как first-class: диагностика (встроенный линтер),
-- быстрые исправления, навигация, hover, автодополнение, символы
-- документа и форматирование — всё в одном бинарнике.
-- Заменяет связку bashls + shellcheck + zshcs: устраняет внешние
-- зависимости (shellcheck, shfmt) и дублирование диагностики.
-- Устанавливается через Mason: :LspInstall shuck
-- (или попадает автоматически из ensure_installed в plugins/lsp.lua).

vim.lsp.config("shuck", {
	filetypes = { "bash", "sh", "zsh" },
})
vim.lsp.enable("shuck")
-- ============================================================
-- Markdown (marksman)
-- ============================================================
-- LSP для Markdown: автодополнение ссылок (включая wiki-ссылки),
-- переход к заголовкам, поиск всех ссылок, рефакторинг переименования,
-- диагностика битых ссылок и дублирующихся заголовков.
-- Не конфликтует с render-markdown.nvim — они решают разные задачи:
-- marksman отвечает за навигацию и ссылки, render-markdown — за внешний вид

vim.lsp.config("marksman", {
	filetypes = { "markdown" },
})
vim.lsp.enable("marksman")

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
--  c привязкой к моменту подключения LSP
vim.api.nvim_create_autocmd("LspAttach", {
	group = vim.api.nvim_create_augroup("LspKeymaps", { clear = true }),
	callback = function(event)
		local map = function(keys, fn, desc)
			vim.keymap.set("n", keys, fn, { buffer = event.buf, desc = "LSP: " .. desc })
		end

		map("gd", vim.lsp.buf.definition, "Go to definition")
		map("K", vim.lsp.buf.hover, "Hover docs")
		map("gr", vim.lsp.buf.references, "References")
		map("<leader>rn", vim.lsp.buf.rename, "Rename")
		map("<leader>ca", vim.lsp.buf.code_action, "Code action")
	end,
})
