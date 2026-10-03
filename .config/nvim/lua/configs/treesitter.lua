-- ============================================================
-- nvim-treesitter (ветка main, Neovim 0.12)
-- ============================================================

-- Установка парсеров (аналог ensure_installed)
require("nvim-treesitter").install({
  "python", "sql", "markdown", "markdown_inline",
  "lua", "vim", "vimdoc", "bash", "json", "yaml",
})

-- Подсветка и отступы через нативный API Neovim 0.12
-- (аналог highlight = { enable = true } и indent = { enable = true })
local ts_group = vim.api.nvim_create_augroup("TreesitterSetup", { clear = true })
vim.api.nvim_create_autocmd("FileType", {
  group = ts_group,
  callback = function(args)
    -- Включаем treesitter-подсветку (заменяет highlight = { enable = true })
    pcall(vim.treesitter.start, args.buf)
    -- Включаем treesitter-отступы (заменяет indent = { enable = true })
    vim.bo[args.buf].indentexpr = "v:lua.require'nvim-treesitter'.indentexpr()"
  end,
})

