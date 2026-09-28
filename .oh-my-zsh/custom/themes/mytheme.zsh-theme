# Включаем подстановку переменных и функций внутри PROMPT
setopt prompt_subst
# Загружаем встроенный модуль zsh для работы с VCS
autoload -Uz vcs_info

# Включаем только git
zstyle ':vcs_info:*' enable git
# Включаем проверку staged/unstaged
zstyle ':vcs_info:*:*' check-for-changes true
# Unstaged — жёлтый !
zstyle ':vcs_info:*:*' unstagedstr '%F{yellow}!'
# Staged — зелёный +
zstyle ':vcs_info:*:*' stagedstr '%F{green}+'
# Формат: только ветка + staged/unstaged (без обёртки)
# msg_0 — ветка+статус, msg_1 — действие (rebase/merge)
zstyle ':vcs_info:*:*' formats '%b%u%c' ''
zstyle ':vcs_info:*:*' actionformats '%b%u%c' '%a'

# Untracked: ? если есть неотслеживаемые файлы
function _git_untracked() {
  command git rev-parse --is-inside-work-tree &>/dev/null || return
  local count=$(command git ls-files --others --exclude-standard 2>/dev/null | wc -l)
  (( count > 0 )) && echo '%F{yellow}?%f'
}

# Dirty: ✗ если есть отличия от HEAD (выводится за скобками)
function _git_dirty() {
  command git rev-parse --is-inside-work-tree &>/dev/null || return
  command git diff --quiet --ignore-submodules HEAD &>/dev/null
  [ $? -eq 1 ] && echo '%B%F{red} ✗%b%f'
}

# Путь + git: внутри скобок ветка + staged + unstaged + untracked, ✗ снаружи
function _prompt_path_git() {
  if [[ -n "$vcs_info_msg_0_" ]]; then
    local inside="%F{red}${vcs_info_msg_0_}$(_git_untracked)"
    local git_str="%B%F{blue}git:($inside%F{blue})%b%f"
    echo "%{$fg_bold[cyan]%}%c%{$reset_color%} $git_str$(_git_dirty)"
  else
    echo "%{$fg_bold[cyan]%}%~%{$reset_color%}"
  fi
}

# Время выполнения команды > 5 сек
function _cmd_exec_time() {
  local stop=$EPOCHSECONDS
  local start=${_cmd_timestamp:-$stop}
  local elapsed=$((stop - start))
  (( elapsed > 5 )) && echo "%F{yellow}${elapsed}s%f"
}

# Хук перед выполнением команды
preexec() { _cmd_timestamp=$EPOCHSECONDS }

# Хук перед отрисовкой промпта
precmd() {
  vcs_info
  unset _cmd_timestamp
  vcs_info_msg_1_=''
}

# Первая строка: ➜ + путь/git + время
PROMPT='%(?:%{$fg_bold[green]%}%1{➜%} :%{$fg_bold[red]%}%1{➜%} ) $(_prompt_path_git) $(_cmd_exec_time)'
# Перенос строки
PROMPT+=$'\n'
# Вторая строка: >>>
PROMPT+='%(?:%F{magenta}>>>%f :%F{red}>>>%f) '
# Правый промпт: SSH user@host
RPROMPT='%F{8}${SSH_TTY:+%n@%m}%f'

