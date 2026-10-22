-- ============================================================
-- grug-far.nvim: конфигурация и кеймапы
-- ============================================================

local ok, grug_far = pcall(require, "grug-far")
if not ok then
	return
end

grug_far.setup({
	-- Открывать окно в горизонтальном сплите (по умолчанию — float)
	-- Можно раскомментировать, если предпочитаете сплит:
	-- window = { open = "split" },
	-- Убрать лишние отступы вокруг полей ввода — интерфейс станет компактнее
	-- Более компактный вид полей ввода
	showCompactInputs = true,
	-- Подсветка через Treesitter (если парсеры установлены)
	resultsHighlight = true,
	inputsHighlight = true,
	-- Подсветка текущего совпадения в исходном буфере
	highlightCurrentMatch = true,
})

-- <leader>sr — открыть grug-far (мнемоника: Search & Replace)
-- Та же клавиша, что в LazyVim, — если решите перейти, привычка сохранится.
vim.keymap.set("n", "<leader>sr", "<cmd>GrugFar<cr>", { desc = "GrugFar: Search & Replace" })

-- <leader>sw — открыть grug-far с уже введённым словом под курсором
-- (аналог LazyVim <leader>sw)
vim.keymap.set("n", "<leader>sw", function()
	local word = vim.fn.expand("<cword>")
	vim.cmd("GrugFar")
	-- Небольшая задержка: grug-far должен успеть создать буфер
	vim.defer_fn(function()
		-- Поле Search — первая строка в буфере grug-far
		vim.api.nvim_buf_set_lines(0, 1, 2, false, { word })
	end, 50)
end, { desc = "GrugFar: Search word under cursor" })
