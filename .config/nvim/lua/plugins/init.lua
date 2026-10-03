-- ============================================================
-- Загрузка плагинов через vim.pack
-- Порядок важен: сначала базовые, потом зависящие от них
-- ============================================================

-- gruvbox.nvim — цветовая схема, замена morhetz/gruvbox
--   Поддержка Tree-sitter и LSP semantic highlights
-- lualine.nvim — статусная строка, замена ручной set statusline + YcmStatus()
-- nvim-web-devicons — иконки файлов (нужен NerdFont)
require("plugins.ui")

-- nvim-treesitter — подсветка синтаксиса через AST
--   Замена vim-python/python-syntax и shmup/vim-sql-syntax
--   Парсеры: python, sql, markdown, lua, vim, bash, json, yaml
-- tabular — выравнивание текста по разделителю (работает из Vim)
-- vim-pdf — открытие PDF в буфере (работает из Vim)
require("plugins.editor")

-- neo-tree.nvim — файловое дерево, замена NERDTree + nerdtree-git-plugin
--   Асинхронное, Lua-native, git-статус встроен
-- plenary.nvim — Lua-библиотека-зависимость для neo-tree
-- nui.nvim — UI-компоненты-зависимость для neo-tree
-- nvim-web-devicons — иконки (зарегистрирован тут, загружается по demand)
require("plugins.tree")

-- mason.nvim — установщик LSP-серверов, linters, formatters
--   Замена ручной компиляции YCM (./install.py --clang-completer)
-- mason-lspconfig.nvim — мост между mason и lspconfig
--   Автоустановка pyright (Python) и clangd (C/C++)
-- nvim-lspconfig — конфигурация встроенного LSP-клиента Neovim
--   Замена YouCompleteMe: go-to-definition, hover, rename, diagnostics
require("plugins.lsp")

-- blink.cmp — движок автодополнения на Rust
--   Замена YCM: источники LSP, path, snippets, buffer
--   Превью документации, автооткрытие меню
-- LuaSnip — движок сниппетов на Lua
--   Замена UltiSnips: нативный Lua, быстрее Python-интерфейса
-- friendly-snippets — готовые сниппеты для популярных языков
require("plugins.cmp")

-- vimtex — LaTeX-плагин (без изменений из Vim)
--   Компиляция, просмотр, подсветка, фолдинг, сниппеты
-- render-markdown.nvim — рендеринг markdown в буфере
--   Замена preservim/vim-markdown: заголовки, чекбоксы, таблицы
require("plugins.lang")

