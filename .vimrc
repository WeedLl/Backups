""#### Основные параметы
""Установка языка
set langmenu=en_US.UTF-8    " sets the language of the menu (gvim)
language en_US                 " sets the language of the messages / ui (vim)

set number "" Нумерация строк на полях
set ruler ""Статус в правом нижнем углу
set autoindent ""Автоотступ

" Настройки табов для Python, согласно рекоммендациям
set tabstop=4 
set shiftwidth=4
set smarttab
set expandtab "Ставим табы пробелами
set softtabstop=4 "4 пробела в табе
"
set mousehide "Спрятать курсор мыши когда набираем текст
set mouse=a "Включить поддержку мыши
set termencoding=utf-8 "Кодировка терминала
" Вырубаем .swp и ~ (резервные) файлы
set nobackup
set noswapfile
set encoding=utf-8 " Кодировка файлов по умолчанию
set fileencodings=utf8,cp1251

" Переносим на другую строчку, разрываем строки
set wrap
set linebreak

" Удобное поведение backspace
set backspace=indent,eol,start whichwrap+=<,>,[,]
" Вырубаем черточки на табах
set showtabline=1

""Поиск
set hlsearch ""Подсвета найденных слов
set incsearch ""Инкрементальный поиск (предварительное отображение)



""####Питонячие фишки
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
"" Отображение скрытых файлов и папок в NTree по умолчанию
let NERDTreeShowHidden=1


""Цветовые схемы colorscheme
Plug 'morhetz/gruvbox'
set background=dark 

call plug#end()

""Включение цветовой темы
colorscheme gruvbox




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
