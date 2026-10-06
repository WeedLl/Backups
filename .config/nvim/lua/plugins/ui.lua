-- gruvbox: грузим сразу, нужна до отрисовки UI
vim.pack.add({
	"https://github.com/ellisonleao/gruvbox.nvim",
})
require("configs.gruvbox")

-- lualine: откладываем через vim.schedule, чтобы не тормозить старт
-- Регистрируем (установим если нет), но не загружаем
vim.pack.add({
	"https://github.com/nvim-lualine/lualine.nvim",
	"https://github.com/nvim-tree/nvim-web-devicons", -- зависимость
}, { load = function() end })

-- Загружаем после старта (аналог event = "VeryLazy" из lazy.nvim)
vim.schedule(function()
	vim.cmd.packadd("lualine.nvim")
	vim.cmd.packadd("nvim-web-devicons")
	require("configs.lualine")
end)

-- Which-key.nvim - показывает подсказки для клавиш по типу операторов в nVim и тп.
vim.pack.add({ "https://github.com/folke/which-key.nvim" })
