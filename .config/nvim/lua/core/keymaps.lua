local map = vim.keymap.set

-- Enter не переопределяем: fold остаётся на za

-- LSP signature help: C-k в insert/select вместо C-S.
-- В normal C-k по-прежнему переходит в окно вверх.
map({ "i", "s" }, "<C-k>", vim.lsp.buf.signature_help, { silent = true, desc = "LSP: Signature help" })
pcall(vim.keymap.del, { "i", "s" }, "<C-S>")

-- Ctrl+C в Insert при русской раскладке.
-- Терминал с kitty keyboard protocol присылает <C-с> (U+0441 + Ctrl),
-- а не <C-c>, поэтому встроенный i_CTRL-C не срабатывает. Ведём на
-- <Esc>: он выходит в Normal и запускает InsertLeave, на котором
-- держится вся логика раскладки (и cursorline в core/autocmds.lua).
map({ "i", "s" }, "<C-с>", "<Esc>", { desc = "Insert: exit to Normal (RU layout)" })

-- Выключение подсветки для данного поиска через /
vim.keymap.set("n", "<esc>", ":nohlsearch<CR>", { noremap = true, silent = true, desc = "Clear search highlight" })

-- Перемещение по окнам с авто-созданием split
--  временно выключил split
map("n", "<C-h>", function()
	local winnr = vim.fn.winnr()
	vim.cmd("wincmd h")
	if vim.fn.winnr() == winnr then
		--vim.cmd("wincmd v")
		vim.cmd("wincmd h")
	end
end, { silent = true, desc = "Window left" })

map("n", "<C-j>", function()
	local winnr = vim.fn.winnr()
	vim.cmd("wincmd j")
	if vim.fn.winnr() == winnr then
		--vim.cmd("wincmd s")
		vim.cmd("wincmd j")
	end
end, { silent = true, desc = "Window down" })

map("n", "<C-k>", function()
	local winnr = vim.fn.winnr()
	vim.cmd("wincmd k")
	if vim.fn.winnr() == winnr then
		--vim.cmd("wincmd s")
		vim.cmd("wincmd k")
	end
end, { silent = true, desc = "Window up" })

map("n", "<C-l>", function()
	local winnr = vim.fn.winnr()
	vim.cmd("wincmd l")
	if vim.fn.winnr() == winnr then
		--vim.cmd("wincmd v")
		vim.cmd("wincmd l")
	end
end, { silent = true, desc = "Window right" })
