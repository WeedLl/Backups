local map = vim.keymap.set

-- Folding
map("n", "<C-m>", "za", { silent = true, desc = "Toggle fold" })

-- Выключение подсветки для данного поиска через /
vim.keymap.set("n", "<esc>", ":nohlsearch<CR>", { noremap = true, silent = true })

-- Перемещение по окнам с авто-созданием split
--  временно выключил split
map("n", "<C-h>", function()
	local winnr = vim.fn.winnr()
	vim.cmd("wincmd h")
	if vim.fn.winnr() == winnr then
		--vim.cmd("wincmd v")
		vim.cmd("wincmd h")
	end
end, { silent = true })

map("n", "<C-j>", function()
	local winnr = vim.fn.winnr()
	vim.cmd("wincmd j")
	if vim.fn.winnr() == winnr then
		--vim.cmd("wincmd s")
		vim.cmd("wincmd j")
	end
end, { silent = true })

map("n", "<C-k>", function()
	local winnr = vim.fn.winnr()
	vim.cmd("wincmd k")
	if vim.fn.winnr() == winnr then
		--vim.cmd("wincmd s")
		vim.cmd("wincmd k")
	end
end, { silent = true })

map("n", "<C-l>", function()
	local winnr = vim.fn.winnr()
	vim.cmd("wincmd l")
	if vim.fn.winnr() == winnr then
		--vim.cmd("wincmd v")
		vim.cmd("wincmd l")
	end
end, { silent = true })
