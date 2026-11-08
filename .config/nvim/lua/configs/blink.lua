local ok, blink = pcall(require, "blink.cmp")
if not ok then
	return
end

blink.setup({
	keymap = {
		preset = "default",
		["<CR>"] = { "accept", "fallback" },
	},
	sources = {
		default = { "lsp", "path", "snippets", "buffer" },
	},
	completion = {
		menu = { auto_show = true },
		documentation = {
			auto_show = true, -- аналог ycm_add_preview_to_completeopt
			auto_show_delay_ms = 0,
		},
	},
})
