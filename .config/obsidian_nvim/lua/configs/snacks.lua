local ok, Snacks = pcall(require, "snacks")
if not ok then
	return
end

Snacks.setup({
	-- Включаем только нужные модули
	picker = { enabled = true },
	terminal = { enabled = true },
	image = { enabled = true },
	-- Отключаем всё остальное, чтобы не потреблять ресурсы
	notifier = { enabled = false },
	dashboard = { enabled = false },
	explorer = { enabled = false },
	input = { enabled = false },
	lazygit = { enabled = false },
})

local map = vim.keymap.set

-- ============================================================
-- Picker: поиск файлов и содержимого (префикс <leader>p)
-- ============================================================
map("n", "<leader>pf", function()
	Snacks.picker.files()
end, { desc = "Picker: Find Files" })
map("n", "<leader>pg", function()
	Snacks.picker.grep()
end, { desc = "Picker: Live Grep" })
map("n", "<leader>pb", function()
	Snacks.picker.buffers()
end, { desc = "Picker: Buffers" })
map("n", "<leader>pr", function()
	Snacks.picker.recent()
end, { desc = "Picker: Recent Files" })
map("n", "<leader>ps", function()
	Snacks.picker.lsp_symbols()
end, { desc = "Picker: Document Symbols" })
map("n", "<leader>pS", function()
	Snacks.picker.lsp_workspace_symbols()
end, { desc = "Picker: Workspace Symbols" })
map("n", "<leader>pd", function()
	Snacks.picker.diagnostics_buffer()
end, { desc = "Picker: Buffer Diagnostics" })
map("n", "<leader>pD", function()
	Snacks.picker.diagnostics()
end, { desc = "Picker: All Diagnostics" })
map("n", "<leader>ph", function()
	Snacks.picker.help()
end, { desc = "Picker: Help Tags" })
map("n", "<leader>pk", function()
	Snacks.picker.keymaps()
end, { desc = "Picker: Keymaps" })
map("n", "<leader>pm", function()
	Snacks.picker.marks()
end, { desc = "Picker: Marks" })
map("n", "<leader>pj", function()
	Snacks.picker.jumps()
end, { desc = "Picker: Jumplist" })
map("n", "<leader>pu", function()
	Snacks.picker.undo()
end, { desc = "Picker: Undo History" })
map("n", "<leader>pc", function()
	Snacks.picker.commands()
end, { desc = "Picker: Commands" })
map("n", "<leader>p/", function()
	Snacks.picker.grep_buffers()
end, { desc = "Picker: Grep in Open Buffers" })

-- ============================================================
-- Terminal: всплывающее окно
-- ============================================================
map({ "n", "t" }, "<C-\\>", function()
	Snacks.terminal.toggle()
end, { desc = "Terminal: Toggle" })
