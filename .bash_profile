#_______________________________________________ Утилиты __________________________________________
# Функция: добавить путь в начало PATH, только если его там нет
prepend_path() {
  local dir="$1"
  # Если директория не существует — сразу выходим (ничего не делаем)
  [ -d "$dir" ] || return 0

  # Проверяем, есть ли уже такой путь в PATH (через grep с разделителями)
  if [[ ":$PATH:" == *":$dir:"* ]]; then
    return 0  # Уже есть — ничего не делаем
  fi

  # Добавляем в начало
  export PATH="$dir:$PATH"
}

#_______________________________________________ Дефолтные настройки ______________________________

# Homebrew: расставляет PATH, MANPATH и т.д. (это делает всё правильно само)
if [ -x /opt/homebrew/bin/brew ]; then
  eval "$(/opt/homebrew/bin/brew shellenv)"
elif [ -x /usr/local/bin/brew ]; then
  eval "$(/usr/local/bin/brew shellenv)"
fi

# Global VENV — добавляем в начало PATH только если нет и папка есть
prepend_path "$HOME/.global_venv/bin"

# zoxide для bash
eval "$(zoxide init bash)"

# PostgreSQL: добавляем bin только если нет и папка есть
prepend_path "/opt/homebrew/opt/postgresql@15/bin"

export LDFLAGS="-L/opt/homebrew/opt/postgresql@15/lib"
export CPPFLAGS="-I/opt/homebrew/opt/postgresql@15/include"

export PSQLRC="$HOME/.config/psql/.psqlrc"
export PSQL_EDITOR="/opt/homebrew/bin/nvim"
export EDITOR="/opt/homebrew/bin/nvim"

#_______________________________________________ SysVAR ____________________________________________
# PS1: \T — время, \u — пользователь, \w — текущий каталог (с ~)
PS1="\T\n\u \w ~ "
export PS1

#_______________________________________________ SmartMooving ______________________________________
alias Dpython='cd ~/Documents/For\ Sys/Python'
alias Dbackup='cd ~/Documents/For\ Sys/Backup'

#_______________________________________________ ShortCat __________________________________________
## Vim and nVim
alias default_vim='/usr/bin/vim'
# Осторожно: этот алиас делает vim графическим (MacVim) — в скриптах это может ломать ожидание консольного редактора
alias vim='/Applications/MacVim.app/Contents/MacOS/Vim'
alias mvim='open -a /Applications/MacVim.app'
alias vimtutor='/Applications/MacVim.app/Contents/bin/vimtutor'

## nVim
alias v='/opt/homebrew/bin/nvim'
alias vimdiff='nvim -d'

## FZF
alias fopen='open $(fzf)'
alias nopen='open "$(pwd)"'

## GIT
alias glol='git log --pretty=format:"%h %an %ad %s" --name-only --graph'
alias glog='git log --graph'
alias gbranch='git log --oneline --graph --decorate --all'

## PGCLI
alias psqlc=pgcli

## LSDeluxe
alias ls='lsd'
alias l='lsd -la'
alias la='lsd -a'
alias lt='lsd --tree'

## Bat
alias cat='bat'

## Yazi
alias yy='yazi'
