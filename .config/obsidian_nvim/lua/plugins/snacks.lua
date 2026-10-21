vim.pack.add({
	{ src = "https://github.com/folke/snacks.nvim", version = vim.version.range("2") },
}, { load = function() end })

-- Загружаем после старта, как lualine в plugins/ui.lua.
-- Это гарантирует, что configs/snacks.lua выполнится и все маппинги
-- <leader>p* будут доступны ДО первого нажатия.
vim.schedule(function()
	vim.cmd.packadd("snacks.nvim")
	require("configs.snacks")
end)
