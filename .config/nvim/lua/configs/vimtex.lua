-- VimTeX: методы просмотра и компиляции различаются по ОС.
-- На macOS был "open"; на Linux используем general + xdg-open.
vim.g.vimtex_view_method = "general"
vim.g.vimtex_view_general_viewer = "xdg-open"

-- latexmk в системе нет; без него VimTeXCompile всё равно не работает.
-- Если поставишь TeX, при следующем запуске компилятор включится сам.
vim.g.vimtex_compiler_enabled = vim.fn.executable("latexmk") == 1 and 1 or 0

vim.g.tex_flavor = "latex"
