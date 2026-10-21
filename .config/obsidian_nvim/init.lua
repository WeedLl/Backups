-- Для корректной работы поиска внешнего nvim в обсидиан
vim.cmd("cd /Users/weed/Documents/Obsidian/")
-- Обязательно первая строка: байткеш для быстрого старта
vim.loader.enable()

vim.g.mapleader = " "
vim.g.maplocalleader = " "

--В ручную добавляем path для nvim Obsidian
-- Гарантируем, что Homebrew-бинарники доступны внутри Neovim, запущенного из GUI
local homebrew_bin = "/opt/homebrew/bin"
local current_path = vim.env.PATH or ""
if not string.find(current_path, homebrew_bin, 1, true) then
	vim.env.PATH = homebrew_bin .. ":" .. current_path
end

require("core.options")
require("core.autocmds")
require("core.keymaps")

-- Хук для TSUpdate: должен быть ДО vim.pack.add
vim.api.nvim_create_autocmd("PackChanged", {
	callback = function(ev)
		local name, kind = ev.data.spec.name, ev.data.kind
		if name == "nvim-treesitter" and kind == "update" then
			if not ev.data.active then
				vim.cmd.packadd("nvim-treesitter")
			end
			vim.cmd("TSUpdate")
		end
	end,
})
require("plugins")
