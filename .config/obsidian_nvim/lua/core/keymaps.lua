local map = vim.keymap.set

-- Folding
map("n", "<C-m>", "za", { silent = true, desc = "Toggle fold" })

-- Выключение подсветки для данного поиска через /
vim.keymap.set("n", "<esc>", ":nohlsearch<CR>", { noremap = true, silent = true })
