# Path to your oh-my-zsh installation.
export ZSH="$HOME/.oh-my-zsh"

# Set name of the theme to load --- if set to "random", it will
#По умолчанию
#ZSH_THEME="robbyrussell"
#Прикольная
#ZSH_THEME="refined"
ZSH_THEME="mytheme"

# Uncomment the following line to disable auto-setting terminal title.
DISABLE_AUTO_TITLE="true"
#___________________________________________________________ PATH FPATH до CompInit ____________________________________
## Позволяет попасть автодополнениям в пул, если они типа (мы файлы в папке, отсканируй нас в FPATH)
# Позволяем brew самому расставить пути в path для себя
if [[ -x /opt/homebrew/bin/brew ]]; then
	eval "$(/opt/homebrew/bin/brew shellenv)"
elif [[ -x /usr/local/bin/brew ]]; then
	eval "$(/usr/local/bin/brew shellenv)"
fi
#!!!! ДЛЯ КОРРЕКТНОЙ РАБОТЫ FZF-TAB И КОМПЛИТА С BREW !!!!
#Некоторые обновления переменных PATH и FPATH необходимо делать до source #ZSH/oh-my-zsh.sh, т.к. это инициализация,
#   в которую входит compinit. Некоторые такие болячки можно прощупать, выполнив source ~/.zshrc в терминале
if [[ ":$FPATH:" != *":/opt/homebrew/share/zsh/site-functions:"* ]] && [[ -d "/opt/homebrew/share/zsh/site-functions" ]]; then
	export FPATH="/opt/homebrew/share/zsh/site-functions:$FPATH"
fi
#Добавление моих функций
if [[ -d "$HOME/.zsh_MyFunctions" ]]; then
	# Добавляем папку в FPATH только если её там ещё нет
	if [[ ":$FPATH:" != *":$HOME/.zsh_MyFunctions:"* ]]; then
		export FPATH="$HOME/.zsh_MyFunctions:$FPATH"
	fi
	# Функции (всё, кроме _*) — загружаем через source
	for f in ~/.zsh_MyFunctions/*(N); do
		[[ "$(basename "$f")" == _* ]] && continue
		source "$f"
	done
fi
##Рекомендации HomeBrew для PostgreSQL после установки
if [[ ":$PATH:" != *":/opt/homebrew/opt/postgresql@15/bin:"* ]] && [[ -d "/opt/homebrew/opt/postgresql@15/bin" ]]; then
	export PATH="/opt/homebrew/opt/postgresql@15/bin:$PATH"
fi
#Global VENV - Python, который должен везде использоваться и его pip
if [[ ":$PATH:" != *":$HOME/.global_venv/bin:"* ]] && [[ -d "$HOME/.global_venv/bin" ]]; then
	export PATH="$HOME/.global_venv/bin:$PATH"
fi
#_______________________________________________________________________________________________________________________
plugins=(git vi-mode)

source $ZSH/oh-my-zsh.sh #COMPINIT для автодополнений (все автодополнения до - не будут работать)
source /opt/homebrew/opt/fzf-tab/share/fzf-tab/fzf-tab.zsh
source /opt/homebrew/share/zsh-autosuggestions/zsh-autosuggestions.zsh
#Для работы fzf сочетаний клавиш в zsh
source <(fzf --zsh)
#По документации должен стоять крайним?
source /opt/homebrew/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh

#___________________________________________________________ PATH FPATH после CompInit _________________________________
## Для приоритетности добавленных в начало PATH или FPATH
## Уже без проверки. Это необходимо, чтобы при повторных source .zshrc произвольно не менялся порядок.
eval "$(zoxide init zsh)"
#Global VENV - Python, который должен везде использоваться и его pip
export PATH="$HOME/.global_venv/bin:$PATH"
#!!!! ДЛЯ КОРРЕКТНОЙ РАБОТЫ FZF-TAB И КОМПЛИТА С BREW !!!!
export FPATH="/opt/homebrew/share/zsh/site-functions:$FPATH"
#Добавление моих функций
export FPATH="$HOME/.zsh_MyFunctions:$FPATH"
#_______________________________________________________________________________________________________________________
#_______________________________________________ Дефолтные настройки ______________________________
#Необходимо для приложений, поддерживающих кастомное расположение конфигов, когда дефолтное не в .config
export XDG_CONFIG_HOME="$HOME/.config"

export EDITOR="/opt/homebrew/bin/nvim"

#_______________________________________________ SysVAR ____________________________________________
RPS1="%T"
export RPS1

#_______________________________________________ SmartMooving ______________________________________
alias Dbackup='cd ~/Documents/ForSys/Backup'

#_______________________________________________ ShortCat __________________________________________
## Vim and nVim
#nVim
alias vim='/opt/homebrew/bin/nvim'
alias vimdiff='nvim -d'

## FZF
alias fopen='open $(fzf)'
alias nopen='open "$(PWD)"'

## GIT
alias glol='git log --pretty=format:"%h %an %ad %s" --name-only --graph'
alias glog='git log --graph'
alias gbranch='git log --oneline --graph --decorate --all'

### Пока не знаю как назвать
#LSDeluxe
alias ls='lsd'
alias l='lsd -la'
alias la='lsd -a'
alias lt='lsd --tree'
#Bat
alias cat='bat'
#Yazi
alias yy='yazi'
#Treemd
alias tmd='treemd'

#_______________________________________________ ZSH-vim-status ____________________________________
###Рекомендация из видео https://www.youtube.com/watch?v=hIJh-KlQ7io
# Настройки vi-mode
VI_MODE_RESET_PROMPT_ON_MODE_CHANGE=true
VI_MODE_SET_CURSOR=true
MODE_INDICATOR="%F{red}--NORMAL--%f "
INSERT_MODE_INDICATOR="%F{green}--INSERT--%f "

stty intr undef
# Ctrl+C → Normal
function _ctrl-c-smart() {
	if [[ -z "$BUFFER" ]]; then
		zle send-break
	else
		zle vi-cmd-mode
	fi
}
zle -N _ctrl-c-smart
bindkey -M viins '^C' _ctrl-c-smart

# Навигация в меню автодополнения
bindkey -M menuselect 'h' vi-backward-char
bindkey -M menuselect 'j' vi-down-line-or-history
bindkey -M menuselect 'k' vi-up-line-or-history
bindkey -M menuselect 'l' vi-forward-char

function _visual-mode {
	typeset -g VI_KEYMAP=visual
	_vi-mode-set-cursor-shape-for-keymap "$VI_KEYMAP"
	zle .visual-mode
	zle reset-prompt
	zle -R
}
zle -N visual-mode _visual-mode

function vi_mode_prompt_info() {
	case "${VI_KEYMAP:-$KEYMAP}" in
	vicmd) echo "%F{red}--NORMAL--%f " ;;
	visual) echo "%F{white}--VISUAL--%f " ;;
	viopp) echo "%F{black}--BLINKING--%f " ;;
	isearch) echo "%F{green}--INSERT--%f " ;;
	command) echo "%F{yellow}----%f " ;;
	*) echo "%F{green}--INSERT--%f " ;;
	esac
}
# Индикатор режима в промпт
PS1+='$(vi_mode_prompt_info)'
export PS1
#________________________________________________ Другое главное __________________________________
#Страховка от всех дубликатов PATH и FPATH (оставляет только первые вхождения)
typeset -U PATH
typeset -U FPATH
