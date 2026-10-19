-- Маппинг здесь, чтобы он был доступен до загрузки (и для загрузки) плагина
vim.pack.add({
	"https://github.com/mikavilpas/yazi.nvim",
}, { load = function() end })

local function ensure_yazi()
	if not package.loaded["yazi"] then
		vim.cmd.packadd("yazi.nvim")
		require("configs.yazi")
	end
end

vim.keymap.set("n", "<C-y>", function()
	ensure_yazi()
	vim.defer_fn(function()
		if pcall(require, "yazi") then
			vim.cmd("Yazi")
		else
			vim.notify("Yazi не загрузился", vim.log.levels.ERROR)
		end
	end, 50)
end, { desc = "Yazi: Open file manager" })
