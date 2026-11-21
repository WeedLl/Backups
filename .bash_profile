# ~/.bash_profile
# Для login-shell: интерактивные настройки живут в ~/.bashrc
[[ -f ~/.bashrc ]] && . ~/.bashrc

#_______________________________________________ Утилиты __________________________________________
# Добавить каталог в начало PATH, убрав его прежние вхождения
prepend_path() {
  local dir="$1"
  [ -d "$dir" ] || return 0

  local new=":$PATH:"
  new=${new//":$dir:"/:}
  new=${new#:}
  new=${new%:}
  PATH="$dir${new:+:$new}"
  export PATH
}

#_______________________________________________ Дефолтные настройки ______________________________
# Порядок: venv -> brew -> local -> system.
# local поднимаем до brew shellenv, затем brew, затем venv — так venv остаётся первым.
prepend_path "$HOME/.local/bin"

# Homebrew Linux: расставляет свои bin/sbin и manpath
if [ -x /home/linuxbrew/.linuxbrew/bin/brew ]; then
  eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"
fi

# zoxide для bash
eval "$(zoxide init bash)"

# Global VENV — последним, чтобы оказаться первым
prepend_path "$HOME/.global_venv/bin"

export EDITOR="/usr/bin/nvim"

#_______________________________________________ SysVAR ____________________________________________
# PS1: \T — время, \u — пользователь, \w — текущий каталог (с ~)
PS1="\T\n\u \w ~ "
export PS1

#_______________________________________________ SmartMooving ______________________________________
alias Dpython='cd ~/Documents/ForSys/Python'
alias Dbackup='cd ~/Documents/ForSys/Backup'

#_______________________________________________ ShortCat __________________________________________
## nVim
alias v='/usr/bin/nvim'
alias vimdiff='nvim -d'

## FZF
alias fopen='xdg-open $(fzf)'
alias nopen='xdg-open "$(pwd)"'

## GIT
alias glol='git log --pretty=format:"%h %an %ad %s" --name-only --graph'
alias glog='git log --graph'
alias gbranch='git log --oneline --graph --decorate --all'
#LazyGit
alias lg='lazygit'

## LSDeluxe
alias ls='lsd'
alias l='lsd -la'
alias la='lsd -a'
alias lt='lsd --tree'

## Bat
alias cat='bat'

## Yazi
alias yy='yazi'

## Treemd
alias tmd='treemd'
