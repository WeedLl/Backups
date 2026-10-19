gdbranch() {
  # 0. Справка.
  case "$1" in
    -h|--help)
      cat <<'EOF'
gdbranch — сравнение веток и коммитов с наглядным выводом.

ИСПОЛЬЗОВАНИЕ
    gdbranch [base] [target] [-f <фильтр>]

АРГУМЕНТЫ
    base        Базовая ревизия для сравнения. Если не указана —
                открывается интерактивный выбор (fzf), либо берётся
                ветка по умолчанию основного remote.
    target      Ревизия, с которой сравниваем. Если не указана —
                сравнивается рабочее дерево (включая staged и
                unstaged изменения) с base. Если указана — сравниваются
                два ref'а, рабочее дерево игнорируется.
ОПЦИИ
    -f, --filter <типы>
                Фильтр по типу изменения (--diff-filter). Строка из букв:
                  A  добавлен        C  скопирован
                  D  удалён          M  изменён
                  R  переименован    T  сменился тип
                  U  неслит          X  неизвестно
                  B  битый
                По умолчанию — все типы: ACDMRTUXB.
    -h, --help  Показать эту справку.

СЦЕНАРИИ
    Текущая ветка vs другая ветка:
        gdbranch develop

    Текущая ветка vs прошлый коммит этой же ветки:
        gdbranch HEAD~5
        gdbranch develop~3

    Указанная ветка vs указанная ветка:
        gdbranch main develop
        gdbranch upstream/main feature/login

    Указанная ветка vs коммит этой же ветки:
        gdbranch develop develop~10

    Только удалённые файлы между main и develop:
        gdbranch main develop -f D

    Интерактивный выбор базовой ветки:
        gdbranch

ВЫВОД
    Первая строка — какие ревизии сравниваются, в каком remote и с
    каким фильтром. Затем список файлов со статусами (A/M/D/R/C/T/U/X/B),
    затем сводка --stat с количеством добавленных и удалённых строк.

    Если установлен bat — вывод подсвечивается и нумеруется.
    Если нет — используется cat, в stderr печатается рекомендация
    установить bat.

    Если установлен fzf — при отсутствии base открывается интерактивный
    выбор ветки среди всех веток всех remote.
    Если нет — берётся ветка по умолчанию основного remote, в stderr
    печатается рекомендация установить fzf.

ЗАВИСИМОСТИ
    git         обязательно
    bat         опционально — для подсветки
    fzf         опционально — для интерактивного выбора base
EOF
      return 0
      ;;
  esac

  # 1. Проверка, что мы внутри git-репозитория.
  if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    print -u2 "✗ Не git-репозиторий"
    return 1
  fi

  # 2. Разбор аргументов.
  #    Позиционные: [base] [target]. Флаг -f задаёт фильтр.
  local base="" target="" filter="ACDMRTUXB"
  local -a positional
  while (( $# )); do
    case "$1" in
      -f|--filter)
        filter="$2"; shift 2 ;;
      -*)
        print -u2 "✗ Неизвестный флаг: $1"; return 1 ;;
      *)
        positional+=("$1"); shift ;;
    esac
  done
  base="${positional[1]}"
  target="${positional[2]}"

  # 3. Определяем основной remote.
  #    Приоритет: upstream текущей ветки → origin → первый из списка.
  local cur_branch="$(git branch --show-current)"
  local remote=""
  if [[ -n "$cur_branch" ]]; then
    remote="$(git config --get "branch.$cur_branch.remote" 2>/dev/null)"
  fi
  if [[ -z "$remote" ]]; then
    if git remote | grep -qx origin; then
      remote="origin"
    else
      remote="$(git remote | head -1)"
    fi
  fi

  # 4. Определяем ветку по умолчанию этого remote.
  #    Приоритет: $remote/HEAD → init.defaultBranch → перебор кандидатов.
  local default_branch=""
  if [[ -n "$remote" ]]; then
    default_branch="$(git symbolic-ref --short "refs/remotes/$remote/HEAD" 2>/dev/null | sed "s|^$remote/||")"
  fi
  if [[ -z "$default_branch" ]]; then
    default_branch="$(git config --get init.defaultBranch 2>/dev/null)"
  fi
  if [[ -z "$default_branch" ]]; then
    local candidate
    for candidate in main master develop trunk; do
      if [[ -n "$remote" ]] && git show-ref --verify --quiet "refs/remotes/$remote/$candidate"; then
        default_branch="$candidate"; break
      fi
      if git show-ref --verify --quiet "refs/heads/$candidate"; then
        default_branch="$candidate"; break
      fi
    done
  fi
  default_branch="${default_branch:-main}"

  # 5. Если base не задан — fzf-выбор или дефолт.
  if [[ -z "$base" ]]; then
    if (( $+commands[fzf] )); then
      base="$(git branch -a --format='%(refname:short)' \
        | grep -vE '^(HEAD|.*/HEAD)$' \
        | sort -u \
        | fzf --prompt='base branch> ' --height=40% --reverse)"
      if [[ -z "$base" ]]; then
        print -r -- "Отменено"
        return 0
      fi
    else
      print -u2 "💡 Установите fzf для интерактивного выбора ветки — используется '$default_branch'"
      base="$default_branch"
    fi
  fi

  # 6. Если target не задан — HEAD (текущий коммит).
  [[ -z "$target" ]] && target="HEAD"

  # 7. Выбор пейджера: bat или cat.
  local -a pager
  if (( $+commands[bat] )); then
    pager=(bat --paging=never)
  else
    print -u2 "💡 Установите bat для подсветки — используется cat"
    pager=(cat)
  fi

  # 8. Человекочитаемая метка для target, если это HEAD.
  local target_label="$target"
  if [[ "$target" == "HEAD" ]]; then
    target_label="${cur_branch:-HEAD} (HEAD)"
  fi

# 9. Определяем, что с чем сравнивать.
local -a diff_args
if (( target_given )); then
  diff_args=("$base" "$target")       # два ref'а
else
  diff_args=("$base")                 # рабочий каталог vs base
fi

# 10. Шапка (уточняем, что сравнивается).
local target_label="$target"
if (( ! target_given )); then
  target_label="рабочее дерево (включая staged/unstaged)"
fi

print -r -- "🔀 $base → $target_label"
print -r -- "   remote: ${remote:-—}   filter: $filter"
print -r -- "────────────────────────────────────────────────────────────────────────────────"

# 11. Список файлов.
git diff --name-status --diff-filter="$filter" "${diff_args[@]}" | "${pager[@]}"

# 13. Сводка.
print -r -- ""
git diff --stat --diff-filter="$filter" "${diff_args[@]}" | "${pager[@]}"
}
