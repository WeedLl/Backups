local opt = vim.opt
-- Кодировка (Neovim использует UTF-8 по умолчанию, но явно не повредит)
opt.fileencoding = "utf-8"
opt.fileencodings = { "utf-8", "cp1251" }

-- Резервные файлы
opt.backup = false
opt.swapfile = false

-- Нумерация строк
opt.number = true
opt.relativenumber = true

-- Статус-строка
-- В Neovim laststatus=2 работает, но есть laststatus=3 (глобальная строка)
opt.laststatus = 2

-- Отображение вводимой команды
-- В Neovim 0.12+ showcmd заменён на showcmdloc, но showcmd всё ещё работает
opt.showcmdloc = "last"

-- Вертикальная линия
opt.colorcolumn = "120"

-- Всегда иметь визуальный отступ от верхнего и нижнего края.
opt.scrolloff = 15

-- Подсветка строки курсора
opt.cursorline = true

-- Перенос строк
opt.wrap = true
opt.linebreak = true
opt.autoindent = true

-- Табы
opt.showtabline = 1
opt.backspace = { "indent", "eol", "start" }
opt.whichwrap:append("<,>,[,]")

-- Поиск
opt.hlsearch = true
opt.incsearch = true
opt.ignorecase = true
opt.smartcase = true

-- Undo/redo
opt.undolevels = 1000
opt.history = 1000

-- Folding
-- В Neovim 0.10+ есть опция foldmethod="expr" с foldexpr=vim.treesitter.foldexpr()
-- Но для начала оставим indent, как у вас
opt.foldenable = true
opt.foldmethod = "expr"
opt.foldexpr = "v:lua.vim.treesitter.foldexpr()"
opt.foldminlines = 4
opt.foldnestmax = 6
opt.foldcolumn = "2"  -- В Neovim foldcolumn — строка, а не число (поддерживает "auto")

-- Правописание
opt.spell = true
opt.spelllang = { "ru", "en" }

-- Python: отступы
opt.tabstop = 4
opt.shiftwidth = 4
opt.smarttab = true
opt.expandtab = true
opt.softtabstop = 4
