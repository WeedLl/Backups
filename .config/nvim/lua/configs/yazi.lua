local ok, yazi = pcall(require, "yazi")
if not ok then
	return
end

yazi.setup({
	-- Ключевой параметр: false, чтобы не конфликтовать с neo-tree
	open_for_directories = false,
	-- Остальные настройки по вашему вкусу (размер окна, прозрачность)
	floating_window_scaling_factor = 0.9,
	yazi_floating_window_border = "rounded",
})
