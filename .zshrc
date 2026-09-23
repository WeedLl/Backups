# If you come from bash you might have to change your $PATH.
# export PATH=$HOME/bin:/usr/local/bin:$PATH

# Path to your oh-my-zsh installation.
export ZSH="$HOME/.oh-my-zsh"

# Set name of the theme to load --- if set to "random", it will
# load a random theme each time oh-my-zsh is loaded, in which case,
# to know which specific one was loaded, run: echo $RANDOM_THEME
# See https://github.com/ohmyzsh/ohmyzsh/wiki/Themes
ZSH_THEME="robbyrussell"

# Set list of themes to pick from when loading at random
# Setting this variable when ZSH_THEME=random will cause zsh to load
# a theme from this variable instead of looking in $ZSH/themes/
# If set to an empty array, this variable will have no effect.
# ZSH_THEME_RANDOM_CANDIDATES=( "robbyrussell" "agnoster" )

# Uncomment the following line to use case-sensitive completion.
# CASE_SENSITIVE="true"

# Uncomment the following line to use hyphen-insensitive completion.
# Case-sensitive completion must be off. _ and - will be interchangeable.
# HYPHEN_INSENSITIVE="true"

# Uncomment one of the following lines to change the auto-update behavior
# zstyle ':omz:update' mode disabled  # disable automatic updates
# zstyle ':omz:update' mode auto      # update automatically without asking
# zstyle ':omz:update' mode reminder  # just remind me to update when it's time

# Uncomment the following line to change how often to auto-update (in days).
# zstyle ':omz:update' frequency 13

# Uncomment the following line if pasting URLs and other text is messed up.
# DISABLE_MAGIC_FUNCTIONS="true"

# Uncomment the following line to disable colors in ls.
# DISABLE_LS_COLORS="true"

# Uncomment the following line to disable auto-setting terminal title.
DISABLE_AUTO_TITLE="true"

# Uncomment the following line to enable command auto-correction.
# ENABLE_CORRECTION="true"

# Uncomment the following line to display red dots whilst waiting for completion.
# You can also set it to another string to have that shown instead of the default red dots.
# e.g. COMPLETION_WAITING_DOTS="%F{yellow}waiting...%f"
# Caution: this setting can cause issues with multiline prompts in zsh < 5.7.1 (see #5765)
# COMPLETION_WAITING_DOTS="true"

# Uncomment the following line if you want to disable marking untracked files
# under VCS as dirty. This makes repository status check for large repositories
# much, much faster.
# DISABLE_UNTRACKED_FILES_DIRTY="true"

# Uncomment the following line if you want to change the command execution time
# stamp shown in the history command output.
# You can set one of the optional three formats:
# "mm/dd/yyyy"|"dd.mm.yyyy"|"yyyy-mm-dd"
# or set a custom format using the strftime function format specifications,
# see 'man strftime' for details.
# HIST_STAMPS="mm/dd/yyyy"

# Would you like to use another custom folder than $ZSH/custom?
# ZSH_CUSTOM=/path/to/new-custom-folder

# Which plugins would you like to load?
# Standard plugins can be found in $ZSH/plugins/
# Custom plugins may be added to $ZSH_CUSTOM/plugins/
# Example format: plugins=(rails git textmate ruby lighthouse)
# Add wisely, as too many plugins slow down shell startup.

#!!!! ДЛЯ КОРРЕКТНОЙ РАБОТЫ FZF-TAB И КОМПЛИТА С BREW !!!!
#Некоторые обновления переменных PATH и FPATH необходимо делать до source #ZSH/oh-my-zsh.sh, т.к. это инициализация,
#   в которую входит compinit. Некоторые такие болячки можно прощупать, выполнив source ~/.zshrc в терминале
if [[ ":$FPATH:" != *":/opt/homebrew/share/zsh/site-functions:"* ]] && [[ -d "/opt/homebrew/share/zsh/site-functions" ]]; then
    export FPATH="/opt/homebrew/share/zsh/site-functions:$FPATH"
fi

plugins=(git vi-mode brew) 

source $ZSH/oh-my-zsh.sh
source /opt/homebrew/opt/fzf-tab/share/fzf-tab/fzf-tab.zsh
source /opt/homebrew/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh
source /opt/homebrew/share/zsh-autosuggestions/zsh-autosuggestions.zsh
#Для работы fzf сочетаний клавиш в zsh
source <(fzf --zsh)


# User configuration

# export MANPATH="/usr/local/man:$MANPATH"

# You may need to manually set your language environment
# export LANG=en_US.UTF-8

# Preferred editor for local and remote sessions
# if [[ -n $SSH_CONNECTION ]]; then
#   export EDITOR='vim'
# else
#   export EDITOR='mvim'
# fi

# Compilation flags
# export ARCHFLAGS="-arch x86_64"

# Set personal aliases, overriding those provided by oh-my-zsh libs,
# plugins, and themes. Aliases can be placed here, though oh-my-zsh
# users are encouraged to define aliases within the ZSH_CUSTOM folder.
# For a full list of active aliases, run `alias`.
#
# Example aliases
# alias zshconfig="mate ~/.zshrc"
# alias ohmyzsh="mate ~/.oh-my-zsh"


#_______________________________________________ Дефолтные настройки ______________________________
if [[ ":$PATH:" != *":/Library/Frameworks/Python.framework/Versions/3.12/bin:"* ]] && [[ -d "/Library/Frameworks/Python.framework/Versions/3.12/bin" ]]; then
    export PATH="/Library/Frameworks/Python.framework/Versions/3.12/bin:$PATH"
fi

alias python=python3
alias python3="/Library/Frameworks/Python.framework/Versions/3.12/bin/python3"
alias pip="/Library/Frameworks/Python.framework/Versions/3.12/bin/pip3"

if [[ ":$PATH:" != *":/opt/homebrew/bin:"* ]] && [[ -d "/opt/homebrew/bin" ]]; then
    export PATH="/opt/homebrew/bin:$PATH"
fi
if [[ ":$PATH:" != *":/opt/homebrew/sbin:"* ]] && [[ -d "/opt/homebrew/sbin" ]]; then
    export PATH="/opt/homebrew/sbin:$PATH"
fi


##Рекомендации HomeBrew для PostgreSQL после установки
if [[ ":$PATH:" != *":/opt/homebrew/opt/postgresql@15/bin:"* ]] && [[ -d "/opt/homebrew/opt/postgresql@15/bin" ]]; then
    export PATH="/opt/homebrew/opt/postgresql@15/bin:$PATH"
fi


export LDFLAGS="-L/opt/homebrew/opt/postgresql@15/lib" #For compilers to find postgresql@15 you may need to set:
export CPPFLAGS="-I/opt/homebrew/opt/postgresql@15/include"


export PSQL_EDITOR="/Applications/MacVim.app/Contents/MacOS/Vim"
export EDITOR="/Applications/MacVim.app/Contents/MacOS/Vim"


#_______________________________________________ SysVAR ____________________________________________
RPS1="%T"
export RPS1


#_______________________________________________ SmartMooving ______________________________________
alias Dpython='cd ~/Documents/Python'
alias Dpycharm='cd ~/PycharmProjects'
alias Dbackup='cd ~/Documents/For\ Sys/Backup'


#_______________________________________________ ShortCat __________________________________________
## Vim
alias default_vim='/usr/bin/vim'
alias vim='/Applications/MacVim.app/Contents/MacOS/Vim'
alias mvim='open -a /Applications/MacVim.app'
alias vimdiff="/Applications/MacVim.app/Contents/bin/vimdiff"
alias vimtutor="/Applications/MacVim.app/Contents/bin/vimtutor"

## FZF
alias fopen='open $(fzf)'
alias nopen='open "$(PWD)"'

## GIT
alias glol='git log --pretty=format:"%h %an %ad %s" --name-only --graph'
alias glog='git log --graph'

## PGCLI
alias psqlc=pgcli


#_______________________________________________ Function __________________________________________
## Backup
function backup_mySysFile() {
  local dest="~/Documents/For Sys/Backup"
  dest=${~dest}
  mkdir -p "$dest"

  typeset -A items
  items=(
    bash      "~/.bash_profile"
    zsh       "~/.zshrc"
    vim       "~/.vimrc"
    ideavim   "~/.ideavimrc"
    psql      "~/.psqlrc"
    git       "~/.gitconfig"
    pgcli     "~/.config/pgcli/config:$dest/config_pgcli"
    ultisnips "~/.vim/UltiSnips/:$dest/.vim/UltiSnips"
    omz       "~/.oh-my-zsh/custom/:$dest/.oh-my-zsh/custom"
  )

  if [[ $# -eq 0 ]]; then
    echo "Использование: backup_mySysFile [bash|zsh|vim|ideavim|psql|git|pgcli|ultisnips|omz|all]"
    return 1
  fi

  for arg in "$@"; do
    if [[ $arg = "all" ]]; then
      for key in "${(k)items[@]}"; do
        _backup_item "$key" "$dest" "$items[$key]"
      done
      return
    fi

    if [[ -z "${items[$arg]+x}" ]]; then
      echo "Неизвестный компонент: $arg"
      continue
    fi
    _backup_item "$arg" "$dest" "${items[$arg]}"
  done
}

function _backup_item() {
  local key=$1 dest=$2 spec=$3
  local src dst

  if [[ "$spec" = *":"* ]]; then
    src=${spec%:*}
    dst=${spec#*:}
  else
    src=$spec
    dst=$dest
  fi

  src=${~src}
  dst=${~dst}

  if [[ ! -e "$src" && ! -L "$src" ]]; then
    echo "Пропущено (не найдено): $src"
    return
  fi

  local src_display="$src"

  if [[ -d "$src" ]]; then
    src="$src/"
  fi

  mkdir -p "${dst%/*}" 2>/dev/null
  cp -Rf "$src" "$dst"

  if [[ -d "$dst" && -f "$src_display" ]]; then
    echo "Скопировано: $src_display -> $dst/${src_display:t}"
  else
    echo "Скопировано: $src_display -> $dst"
  fi
}

function unload_mySysFile() {
  local src="~/Documents/For Sys/Backup"
  src=${~src}

  if [[ ! -d "$src" ]]; then
    echo "Папка бэкапа не найдена: $src"
    return 1
  fi
  typeset -A items
  items=(
    bash      "$src/.bash_profile:~/"
    zsh       "$src/.zshrc:~/"
    vim       "$src/.vimrc:~/"
    ideavim   "$src/.ideavimrc:~/"
    psql      "$src/.psqlrc:~/"
    git       "$src/.gitconfig:~/"
    pgcli     "$src/config_pgcli:~/.config/pgcli/config"
    ultisnips "$src/.vim/UltiSnips/:~/.vim/UltiSnips"
    omz       "$src/.oh-my-zsh/custom/:~/.oh-my-zsh/custom"
  )

  if [[ $# -eq 0 ]]; then
    echo "Использование: unload_mySysFile [bash|zsh|vim|ideavim|psql|git|pgcli|ultisnips|omz|all]"
    return 1
  fi

  for arg in "$@"; do
    if [[ $arg = "all" ]]; then
      for key in "${(k)items[@]}"; do
        _unload_item "$key" "${items[$key]}"
      done
      return
    fi

    if [[ -z "${items[$arg]+x}" ]]; then
      echo "Неизвестный компонент: $arg"
      continue
    fi
    _unload_item "$arg" "${items[$arg]}"
  done
}

function _unload_item() {
  local key=$1 spec=$2
  local src dst

  src=${spec%:*}
  dst=${spec#*:}

  src=${~src}
  dst=${~dst}

  if [[ ! -e "$src" && ! -L "$src" ]]; then
    echo "Пропущено (нет в бэкапе): $src"
    return
  fi

  local src_display="$src"

  if [[ -d "$src" ]]; then
    src="$src/"
  fi

  mkdir -p "${dst%/*}" 2>/dev/null
  cp -Rf "$src" "$dst"

  if [[ -d "$dst" && -f "$src_display" ]]; then
    echo "Восстановлено: $src_display -> ${dst%/}/${src_display:t}"
  else
    echo "Восстановлено: $src_display -> $dst"
  fi
}
#Сравнивает различия. Без аргументов - только отчёт по всем файлам.
#diff_bzvp                  # проверить всё, только отчёт
#diff_bzvp zsh git          # проверить только zsh и git
#diff_bzvp diff             # проверить всё + vimdiff для отличающихся
#diff_bzvp diff zsh vim     # vimdiff только для zsh и vim (если они отличаются)
function diff_mySysFile() {
  local dest="~/Documents/For Sys/Backup"
  dest=${~dest}

  if [[ ! -d "$dest" ]]; then
    echo "Папка бэкапа не найдена: $dest"
    return 1
  fi

  local use_vimdiff=false
  local components=()

  for arg in "$@"; do
    if [[ $arg = "diff" ]]; then
      use_vimdiff=true
    else
      components+=$arg
    fi
  done

  # Маппинг: ключ => "текущий_файл:файл_в_бэкапе"
  typeset -A items
  items=(
    bash      "~/.bash_profile:$dest/.bash_profile"
    zsh       "~/.zshrc:$dest/.zshrc"
    vim       "~/.vimrc:$dest/.vimrc"
    ideavim   "~/.ideavimrc:$dest/.ideavimrc"
    psql      "~/.psqlrc:$dest/.psqlrc"
    git       "~/.gitconfig:$dest/.gitconfig"
    pgcli     "~/.config/pgcli/config:$dest/config_pgcli"
    ultisnips "~/.vim/UltiSnips:$dest/.vim/UltiSnips"
    omz       "~/.oh-my-zsh/custom:$dest/.oh-my-zsh/custom"
  )
  typeset -A diff_details

  # Если компоненты не указаны — проверяем все
  if [[ ${#components} -eq 0 ]]; then
    components=("${(k)items[@]}")
  fi

  local found_diff=false
  local missing_home=()
  local missing_backup=()
  local different=()
  local identical=()
  local diff_output

  for key in "${components[@]}"; do
    if [[ -z "${items[$key]+x}" ]]; then
      echo "Неизвестный компонент: $key"
      continue
    fi

    local spec="${items[$key]}"
    local current="${spec%:*}"
    local backup="${spec#*:}"
    current=${~current}
    backup=${~backup}

    local home_exists=true
    local backup_exists=true

    [[ ! -e "$current" && ! -L "$current" ]] && home_exists=false
    [[ ! -e "$backup" && ! -L "$backup" ]] && backup_exists=false

    if [[ $home_exists = false && $backup_exists = false ]]; then
      missing_home+=$key
      missing_backup+=$key
      continue
    fi

    if [[ $home_exists = false ]]; then
      missing_home+=$key
      continue
    fi

    if [[ $backup_exists = false ]]; then
      missing_backup+=$key
      continue
    fi
    # Сравнение
    diff_output=$(command diff -rq "$current" "$backup" 2>/dev/null)
    if [[ $? -eq 0 ]]; then
      identical+=$key
    else
      different+=$key
      found_diff=true
      # Для директорий собираем детали
      if [[ -d "$current" && -d "$backup" ]]; then
        local details=()
        while IFS= read -r line; do
          [[ -z "$line" ]] && continue
          if [[ "$line" = *" differ" ]]; then
            local f="$line"
            f="${f#Files }"
            f="${f#Binary files }"
            f="${f% differ}"
            f="${f%% and *}"
            f="${f#"$current"/}"
            details+="    отличается: $f"
          elif [[ "$line" = "Only in "* ]]; then
            details+="    $line"
          fi
        done <<< "$diff_output"
        diff_details[$key]="${(F)details}"
      else
        diff_details[$key]="    $diff_output"
      fi
    fi

  done

  # Отчёт
  echo "=== Проверка конфигов ==="
  echo ""

  if [[ ${#identical} -gt 0 ]]; then
    echo "Без изменений:"
    for k in "${identical[@]}"; do
      echo "  $k"
    done
    echo ""
  fi

  if [[ ${#different} -gt 0 ]]; then
    echo "Отличаются:"
    for k in "${different[@]}"; do
      echo "  $k"
      [[ -n "${diff_details[$k]}" ]] && echo "${diff_details[$k]}"
    done
    echo ""
  fi

  if [[ ${#missing_home} -gt 0 ]]; then
    echo "Нет текущего файла (только в бэкапе):"
    for k in "${missing_home[@]}"; do
      echo "  $k"
    done
    echo ""
  fi

  if [[ ${#missing_backup} -gt 0 ]]; then
    echo "Нет в бэкапе (только текущий):"
    for k in "${missing_backup[@]}"; do
      echo "  $k"
    done
    echo ""
  fi

  if [[ $found_diff = false ]]; then
    echo "Различий нет."
  fi

# vimdiff для отличающихся
  if [[ $use_vimdiff = true && ${#different} -gt 0 ]]; then
    echo ""
    echo "Открытие vimdiff для отличающихся файлов..."
    for key in "${different[@]}"; do
      local spec="${items[$key]}"
      local current="${spec%:*}"
      local backup="${spec#*:}"
      current=${~current}
      backup=${~backup}
      if [[ -d "$current" && -d "$backup" ]]; then
        # Для директорий — находим отличающиеся файлы
        local diff_files=()
        local only_in=()
        while IFS= read -r line; do
          [[ -z "$line" ]] && continue
          if [[ "$line" = *" differ" ]]; then
            # "Files A and B differ" или "Binary files A and B differ"
            local f="$line"
            f="${f#Files }"
            f="${f#Binary files }"
            f="${f% differ}"
            f="${f%% and *}"
            f="${f#"$current"/}"
            diff_files+="$f"
          elif [[ "$line" = "Only in "* ]]; then
            only_in+="$line"
          fi
        done < <(command diff -rq "$current" "$backup" 2>/dev/null)
        if [[ ${#diff_files} -eq 0 && ${#only_in} -eq 0 ]]; then
          echo ">>> $key: различий не найдено"
        else
          if [[ ${#only_in} -gt 0 ]]; then
            echo ">>> $key: файлы только с одной стороны:"
            for line in "${only_in[@]}"; do
              echo "    $line"
            done
          fi
          for f in "${diff_files[@]}"; do
            echo ""
            echo ">>> $key/$f"
            vimdiff "$current/$f" "$backup/$f"
          done
        fi
      else
        echo ""
        echo ">>> $key: $current <-> $backup"
        vimdiff "$current" "$backup"
      fi
    done
  elif [[ $use_vimdiff = true && ${#different} -eq 0 ]]; then
    echo ""
    echo "Отличий нет — vimdiff не нужен."
  fi
}

#_______________________________________________ ZSH-vim-status ____________________________________
###Рекомендация из видео https://www.youtube.com/watch?v=hIJh-KlQ7io
bindkey -v          #Нахуя эти две строки не ясно
export KEYTIMEOUT=1
#Переключение по списку предложенных к автозаполнению через TAB клавишами vim
bindkey -M menuselect 'h' vi-backward-char
bindkey -M menuselect 'j' vi-down-line-or-history
bindkey -M menuselect 'k' vi-up-line-or-history
bindkey -M menuselect 'l' vi-forward-char

###
VI_MODE_RESET_PROMPT_ON_MODE_CHANGE=true
VI_MODE_SET_CURSOR=true
MODE_INDICATOR="%F{red}+%f"
INSERT_MODE_INDICATOR="%F{green}+%f"

## Моя функция для обновления PS1
function _vi-mode-set-cursor-shape-for-keymap() {
  [[ "$VI_MODE_SET_CURSOR" = true ]] || return
  local _shape=0
  case "${1:-${VI_KEYMAP:-main}}" in
    main)    _shape="%F{red}--NORMAL--%f " ;; # vi insert: line
    viins)   _shape="%F{green}--INSERT--%f " ;; # vi insert: line
    isearch) _shape="%F{green}--INSERT--%f " ;; # inc search: line
    command) _shape="%F{yellow}----%f " ;; # read a command name
    vicmd)   _shape="%F{green}--INSERT--%f " ;; # vi cmd: block
    visual)  _shape="%F{white}--VISUAL--%f " ;; # vi visual mode: block
    viopp)   _shape="%F{black}--BLINKING--%f " ;; # vi operation pending: blinking block
    *)       _shape="%F{blue}>>>%f " ;;
  esac
  ZVIMMODE=${_shape}
  export ZVIMMODE
}
# Бывают случаи, что для интерактивной переменной необходимо прописывать \$ вначале, но иногда,
# достаточно просто значка $. Не знаю, с чем это связанно.
PS1+="\${ZVIMMODE}"
export PS1

#Страховка от всех дубликатов PATH и FPATH (оставляет только первые вхождения)
typeset -U PATH
typeset -U FPATH
