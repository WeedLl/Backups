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


#FPATH моих функций
if [[ ":$FPATH:" != *"$HOME/.zsh_MyFunctions:"* ]] && [[ -d "$HOME/.zsh_MyFunctions" ]]; then
    export FPATH="$HOME/.zsh_MyFunctions:$FPATH"
    autoload -Uz ~/.zsh_MyFunctions/*(.:t)
fi

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
#________________________________________________ Другое главное __________________________________

#Страховка от всех дубликатов PATH и FPATH (оставляет только первые вхождения)
typeset -U PATH
typeset -U FPATH
