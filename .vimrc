""#### Основные параметы
""Установка языка
set langmenu=en_US.UTF-8    " sets the language of the menu (gvim)
language en_US                 " sets the language of the messages / ui (vim)
set termencoding=utf-8 "Кодировка терминала
set encoding=utf-8 " Кодировка файлов по умолчанию
set fileencodings=utf8,cp1251
""Меню
set number relativenumber "" Нумерация строк на полях
set ruler ""Статус в правом нижнем углу
set showcmd "Отображение вводимой комманды
set colorcolumn=120 ""Вертикальная линия
set mousehide "Спрятать курсор мыши когда набираем текст
set mouse=a "Включить поддержку мыши
set laststatus=2 "Постоянное отображение статуса
set scrolloff=5 "Всегда иметь визульные отступы от верхнего и нижнего края
set cursorline "Подсвечивать строку, на которой находится курсор
autocmd InsertEnter,InsertLeave * set cursorline! "Прекратить подсвечивать строку в режиме INSERT

""Строки
" Переносим на другую строчку, разрываем строки
set wrap
set linebreak
set autoindent "Автоотступ
"Вырубаем черточки на табах
set showtabline=1
"Удобное поведение backspace
set backspace=indent,eol,start whichwrap+=<,>,[,]

""Поиск
set hlsearch "Подсвета найденных слов
set incsearch "Инкрементальный поиск (предварительное отображение)
"При вводе только маленьких букв регистронезависимый поиск, а если есть болшая- зависимый
set ignorecase
set smartcase

""Размер истории для undo/redo 1000
set undolevels=1000
set history=1000

" Вырубаем .swp и ~ (резервные) файлы
set nobackup
set noswapfile

""Запоминание вкладок (сворачиваний текста / vim folding)
augroup remember_folds
  autocmd!
  autocmd BufWinLeave * mkview
  autocmd BufWinEnter * silent! loadview
augroup END


""####Markdown
""Folding
set foldenable
set foldmethod=indent
set foldminlines=4
set foldnestmax=4
let g:markdown_folding=1

""Правописание
set spell spelllang=ru_ru,en_us

""####Питонячие фишки
" Настройки табов для Python, согласно рекомендациям
set tabstop=4 
set shiftwidth=4
set smarttab
set expandtab "Ставим табы пробелами
set softtabstop=4 "4 пробела в табе
" Перед сохранением вырезаем пробелы на концах (только в .py файлах)
autocmd BufWritePre *.py normal m`:%s/\s\+$//e ``
" В .py файлах включаем умные отступы после ключевых слов
autocmd BufRead *.py set smartindent cinwords=if,elif,else,for,while,try,except,finally,def,class

""Подсветка синтаксиса
syntax on 
let python_highlight_all = 1 
" Включаем 256 цветов в терминале, мы ведь работаем из иксов?
" Нужно во многих терминалах, например в gnome-terminal
set t_Co=256


""####Плагины
call plug#begin()

Plug 'scrooloose/nerdtree', { 'on':  'NERDTreeToggle' }
""Показывает статут гит файлов
Plug 'Xuyuanp/nerdtree-git-plugin'
""Подсветка SQL
Plug 'shmup/vim-sql-syntax'
""Возможность читать PDF в вим
Plug 'makerj/vim-pdf'

""Цветовые схемы colorscheme
Plug 'morhetz/gruvbox'
set background=dark 

""MarkDown
Plug 'godlygeek/tabular'
Plug 'preservim/vim-markdown'

""UltiSnips
" Track the engine.
Plug 'SirVer/ultisnips'
" Snippets are separated from the engine. Add this if you want them:
"Plugin 'honza/vim-snippets'

"VimTex
Plug 'lervag/vimtex'


call plug#end()

""MarkDown
let g:UltiSnipsExpandTrigger="<tab>"
let g:UltiSnipsJumpForwardTrigger="<c-b>"
let g:UltiSnipsJumpBackwardTrigger="<c-z>"
" If you want :UltiSnipsEdit to split your window.
let g:UltiSnipsEditSplit="vertical"

""Включение цветовой темы
colorscheme gruvbox

"" Отображение скрытых файлов и папок в NTree по умолчанию
let NERDTreeShowHidden=1
""Отображение количества строк
let g:NERDTreeFileLines = 1 
""Автоматическое закрытие Vim, если NerdTree является последним окном
autocmd BufEnter * if tabpagenr('$') == 1 && winnr('$') == 1 && exists('b:NERDTree') && b:NERDTree.isTabTree() | call feedkeys(":quit\<CR>:\<BS>") | endif

""####Mappings

map <C-n> :NERDTreeToggle<CR>

""Перемещение по окнам Ctrl+клв-а:
map <silent> <C-h> :call WinMove('h')<CR>
map <silent> <C-j> :call WinMove('j')<CR>
map <silent> <C-k> :call WinMove('k')<CR>
map <silent> <C-l> :call WinMove('l')<CR>

function! WinMove(key)
  let t:curwin = winnr()
  exec "wincmd ".a:key
  if (t:curwin == winnr())
    if(match(a:key,'[jk]'))
     wincmd v
    else
     wincmd s
    endif
     exec "wincmd ".a:key
   endif
endfunction
