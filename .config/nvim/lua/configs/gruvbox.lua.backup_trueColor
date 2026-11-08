local ok, gruvbox = pcall(require, "gruvbox")
if not ok then
  return
end

gruvbox.setup({
  terminal_colors = true,
  undercurl = true,
  underline = true,
  italic = {
    strings = true,
    emphasis = true,
    comments = true,
    folds = true,
  },
  overrides = {
    -- Семантические токены от LSP (pyright)
    -- Связываем с цветами gruvbox, чтобы функции/классы/переменные
    -- подсвечивались по-разному, а не только по синтаксису
    ["@lsp.type.variable"]   = { link = "GruvboxBlue" },
    ["@lsp.type.function"]    = { link = "GruvboxGreen" },
    ["@lsp.type.class"]      = { link = "GruvboxYellow" },
    ["@lsp.type.parameter"]  = { link = "GruvboxAqua" },
    ["@lsp.type.method"]    = { link = "GruvboxGreen" },
    ["@lsp.type.decorator"]  = { link = "GruvboxOrange" },
  },
})

vim.o.background = "dark"
vim.cmd("colorscheme gruvbox")

-- Аналог hi SpellBad из .vimrc
vim.api.nvim_set_hl(0, "SpellBad", {
  cterm = { underline = true },
  ctermfg = "Red",
  sp = "Red",
  undercurl = true,
})

