local ok, conform = pcall(require, "conform")
if not ok then
  return
end

conform.setup({
  formatters_by_ft = {
    python = { "ruff_format" },  -- форматер из ruff (аналог black, но быстрее)
    -- lua = { "stylua" },      -- если хотите форматировать и Lua
  },
  format_on_save = {
    timeout_ms = 1000,    -- ждать форматер максимум 1 секунду
    lsp_fallback = true,  -- если conform не нашёл форматер — попробовать через LSP
  },
})

-- Маппинг: <leader>f для форматирования всего файла
vim.keymap.set("n", "<leader>f", function()
  conform.format({ async = true, lsp_fallback = true })
end, { desc = "Format file" })

-- Маппинг: форматирование выделенного фрагмента в visual-режиме
vim.keymap.set("v", "<leader>f", function()
  conform.format({ async = true, lsp_fallback = true })
end, { desc = "Format selection" })

