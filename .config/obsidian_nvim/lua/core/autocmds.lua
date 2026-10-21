local augroup = vim.api.nvim_create_augroup("UserAutocmds", { clear = true })

-- Отключение подсветки строки в режиме Insert
vim.api.nvim_create_autocmd("InsertEnter", {
	group = augroup,
	callback = function()
		vim.opt.cursorline = false
	end,
})
vim.api.nvim_create_autocmd("InsertLeave", {
	group = augroup,
	callback = function()
		vim.opt.cursorline = true
	end,
})

-- Fallback на indent-folding для файлов без Treesitter-парсера (режим fold)
vim.api.nvim_create_autocmd("FileType", {
	group = augroup,
	callback = function()
		local ft = vim.bo.filetype
		if ft == "" or ft == "text" or ft == "plaintext" then
			vim.opt_local.foldmethod = "indent"
		end
	end,
})

-- Python: обрезка пробелов перед сохранением
vim.api.nvim_create_autocmd("BufWritePre", {
	group = augroup,
	pattern = "*.py",
	callback = function()
		local save = vim.fn.winsaveview()
		vim.cmd([[%s/\s\+$//e]])
		vim.fn.winrestview(save)
	end,
})
