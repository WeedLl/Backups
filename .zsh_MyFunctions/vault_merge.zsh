# =============================================================================
# vault_merge — безопасное слияние двух хранилищ Obsidian в третье.
#
#   Сравнивает «базу» ($1) и «another_base» ($2) и собирает итоговое хранилище ($3),
#   НЕ изменяя исходные хранилища. Вся работа идёт во временной директории,
#   итог подставляется атомарно только после успешного завершения.
#
# Подключение:
#   source /путь/к/vault_merge.zsh          # в текущей сессии
#   или добавьте строку в ~/.zshrc
#
# Использование:
#   vault_merge [-S] [-d] [--ask-new] <база> <another_base> [<итог>]
#   vault_merge -h | --help
#
# Зависимости:
#   zsh, cp, mv, rm, mkdir, mktemp, cmp, head, ln, readlink, file, ls, date,
#   sort, cut (стандартные);
#   diff-редактор: nvim -d, иначе vimdiff, иначе vim -d;
#   опционально: bat (превью), lsd (дерево итога), yq/jq (pretty-просмотр
#   .bases/.canvas).
#
# Переменная окружения VAULT_MERGE_DIFF позволяет переопределить diff-команду
# (разбивается по пробелам); удобно для тестов и нестандартных редакторов.
# =============================================================================

# ---- глобальное состояние для ловушек (trap) и редактора ----
_VM_STAGING=""  # временная директория (для очистки при прерывании)
_vm_diff_cmd=() # diff-редактор в виде массива аргументов
# Лог-массивы (глобальные, чтобы помощники могли дописывать в них).
_VM_LOG_BASE=()     # файлы/каталоги/симлинки, взятые из базы
_VM_LOG_PHONE=()    # файлы/каталоги/симлинки, взятые из another_base
_VM_LOG_MOVED=()    # перемещения/переименования/удаления дубликатов
_VM_LOG_SKIPPED=()  # пропуски (--ask-new «нет», бинарный [s], конфликт файл/каталог)
_VM_LOG_RESOLVED=() # как разрешён каждый конфликт содержимого

# ---- цвета gruvbox dark (256-color). Пустые по умолчанию; включаются в vault_merge. ----
_VM_C_GREEN=""  # база / успех
_VM_C_BLUE=""   # another_base
_VM_C_PURPLE="" # перемещения
_VM_C_YELLOW="" # конфликты / предупреждения
_VM_C_RED=""    # ошибки (жирный)
_VM_C_AQUA=""   # инфо / заголовки / имена файлов
_VM_C_ORANGE="" # «в базе, уже в итоге» (яркий, различимый)
_VM_C_BOLD=""   # вопросы
_VM_C_OFF=""    # сброс

_vm_cleanup() {
	# Вызывается EXIT/INT-ловушкой. Удаляет временную директорию, если осталась.
	# Исходники ($1/$2) и итог ($3) при этом никогда не трогаются.
	if [[ -n "$_VM_STAGING" && -d "$_VM_STAGING" ]]; then
		rm -rf "$_VM_STAGING"
		print -u2 -r -- "vault_merge: ${_VM_C_YELLOW}прервано${_VM_C_OFF} — временный каталог $_VM_STAGING удалён; исходники и итог не изменены."
	fi
}

_vm_err() {
	# Единая точка вывода ошибок на stderr. Возвращает 1 (не завершает оболочку!).
	print -u2 -r -- "vault_merge: ${_VM_C_RED}ошибка${_VM_C_OFF}: $*"
	return 1
}

_vm_warn() {
	# Предупреждение на stderr, не прерывает работу.
	print -u2 -r -- "vault_merge: ${_VM_C_YELLOW}предупреждение${_VM_C_OFF}: $*"
}

_vm_yesno() {
	# Интерактивный вопрос да/нет. $1 = текст вопроса, $2 = ответ по умолчанию
	# (y/n, по умолчанию n). Возвращает 0, если пользователь ответил «да».
	# Пустая строка (или EOF) = ответ по умолчанию; на прочий ввод переспрашивает.
	emulate -L zsh
	local prompt="$1" def="${2:-n}" line suffix
	if [[ "$def" == y ]]; then suffix="[Y/n]"; else suffix="[y/N]"; fi
	while :; do
		print -n -r -- "${_VM_C_BOLD}$prompt $suffix ${_VM_C_OFF}"
		read line || line=""
		line=${(L)line}
		[[ -z "$line" ]] && line="$def"
		case "$line" in
		y | yes) return 0 ;;
		n | no) return 1 ;;
		*) print -u2 -r -- "  ${_VM_C_RED}некорректный ответ (ожидается y/n)${_VM_C_OFF}" ;;
		esac
	done
}

_vm_is_binary() {
	# Определяет, двоичный ли файл. Бинарный, если `file --mime-encoding`
	# сообщает «binary», ИЛИ расширение входит в известный список двоичных.
	# Возвращает 0 (бинарный) / 1 (текстовый). Текстовые .md/.canvas/.bases/.svg
	# и т.п. NUL-байтов не содержат и сюда не попадают.
	emulate -L zsh
	local f="$1" enc ext base
	[[ -f "$f" ]] || return 1
	enc=$(file -b --mime-encoding "$f" 2>/dev/null)
	[[ "$enc" == binary ]] && return 0
	base="${f:t}"
	ext="${base##*.}"
	ext=${(L)ext}
	case "$ext" in
	png | jpg | jpeg | gif | webp | avif | heic | heif | ico | bmp | tif | tiff | psd | raw | cr2 | \
	    pdf | zip | gz | tgz | bz2 | xz | rar | 7z | tar | \
	    mp3 | m4a | wav | flac | aac | ogg | opus | mp4 | mov | mkv | avi | webm | m4v | \
	    docx | xlsx | pptx | odt | ods | epub | dmg | iso | exe | bin) return 0 ;;
	esac
	return 1
}

_vm_is_canvas_base() {
	# .canvas / .base / .bases — текстовые (JSON/YAML), к ним применим pretty-просмотр.
	emulate -L zsh
	local base="${1:t}" ext
	ext="${base##*.}"
	ext=${(L)ext}
	[[ "$ext" == canvas || "$ext" == base || "$ext" == bases ]]
}

_vm_has_pretty() {
	# 0, если доступен yq или jq (для pretty-печати .bases/.canvas).
	command -v yq >/dev/null 2>&1 || command -v jq >/dev/null 2>&1
}

_vm_preview() {
	# Печатает первые N строк ТЕКСТОВОГО файла: bat при наличии, иначе head.
	emulate -L zsh
	local f="$1" n="${2:-10}"
	if command -v bat >/dev/null 2>&1; then
		bat --style=plain --pager=never --line-range ":$n" "$f" 2>/dev/null || head -n "$n" "$f"
	else
		head -n "$n" "$f"
	fi
}

_vm_pretty_temp() {
	# Печатает путь ко временному файлу с «красивой» версией $1 (yq eval '.' или
	# jq '.'). Если утилиты нет или форматирование не удалось — копия оригинала.
	emulate -L zsh
	local src="$1" tmp
	tmp=$(mktemp "${TMPDIR:-/tmp}/vault_merge_pretty.XXXXXX") || {
		_vm_err "mktemp не удался"
		return 1
	}
	if command -v yq >/dev/null 2>&1; then
		if yq eval '.' "$src" >"$tmp" 2>/dev/null; then
			:
		else
			cp -p "$src" "$tmp"
			_vm_warn "yq не смог отформатировать $src — показываю оригинал"
		fi
	elif command -v jq >/dev/null 2>&1; then
		if jq '.' "$src" >"$tmp" 2>/dev/null; then
			:
		else
			cp -p "$src" "$tmp"
			_vm_warn "jq не смог отформатировать $src (возможно, не JSON) — показываю оригинал"
		fi
	else
		cp -p "$src" "$tmp"
	fi
	print -r -- "$tmp"
}

_vm_preview_member() {
	# Превью файла в конфликте имён. Бинарные показываем через ls -lh (размер +
	# дата, без дампа байтов); .bases/.canvas (при наличии yq/jq) — отформатированно;
	# прочие текстовые — bat/head.
	emulate -L zsh
	local f="$1" tmp
	if _vm_is_binary "$f"; then
		print -r -- "  (двоичный файл — размер и дата изменения)"
		command ls -lh "$f"
		return
	fi
	if _vm_is_canvas_base "$f" && _vm_has_pretty; then
		tmp=$(_vm_pretty_temp "$f") || return
		_vm_preview "$tmp" 20
		rm -f "$tmp"
		return
	fi
	_vm_preview "$f" 10
}

_vm_ensure_diff() {
	# Выбирает diff-редактор и кладёт его в глобальный массив _vm_diff_cmd.
	# Приоритет: VAULT_MERGE_DIFF → nvim -d → vimdiff → vim -d. Возвращает 0 при успехе.
	emulate -L zsh
	if [[ -n "${VAULT_MERGE_DIFF:-}" ]]; then
		_vm_diff_cmd=(${=VAULT_MERGE_DIFF})
		print -r -- "diff-редактор (VAULT_MERGE_DIFF): ${_vm_diff_cmd[*]}"
		return 0
	fi
	if command -v nvim >/dev/null 2>&1; then
		_vm_diff_cmd=(nvim -d)
	elif command -v vimdiff >/dev/null 2>&1; then
		_vm_diff_cmd=(vimdiff)
	elif command -v vim >/dev/null 2>&1; then
		_vm_diff_cmd=(vim -d)
	else
		_vm_err "не найден diff-редактор (нужен nvim, vimdiff или vim)"
		return 1
	fi
	print -r -- "diff-редактор: ${_vm_diff_cmd[*]}"
	return 0
}

_vm_merge_into() {
	# Открывает diff-редактор для двух ТЕКСТОВЫХ файлов, сохраняет результат в левый.
	#   $1 = левый файл (в итоговом хранилище — можно редактировать; :wq сохраняет правки),
	#   $2 = правый файл (исходник; НЕ редактируется — копируется во временный буфер),
	#   $3 = необязательная метка (относительный путь) для лога.
	# Исходные хранилища никогда не открываются на запись.
	emulate -L zsh
	local dstfile="$1" srcfile="$2" label="${3:-}" tmp
	tmp=$(mktemp "${TMPDIR:-/tmp}/vault_merge_diff.XXXXXX") ||
		{
			_vm_err "mktemp не удался"
			return 1
		}
	cp -p "$srcfile" "$tmp" ||
		{
			rm -f "$tmp"
			_vm_err "не удалось скопировать $srcfile во временный буфер"
			return 1
		}
	print -r -- "  diff: итоговый (слева)  vs  $srcfile (справа, read-only копия)"
	"${_vm_diff_cmd[@]}" "$dstfile" "$tmp"
	rm -f "$tmp"
	[[ -n "$label" ]] && _VM_LOG_RESOLVED+=("$label: разрешено в редакторе (nvim)")
}

_vm_merge_pretty() {
	# Для .bases/.canvas: открывает nvim -d на отформатированных (yq/jq) копиях,
	# затем спрашивает, какую версию сохранить. В итог ВСЕГДА попадает оригинал
	# (структура не меняется; правки в отформатированном виде НЕ сохраняются).
	# Без yq/jq — предупреждение и обычный nvim -d. $3 = метка для лога.
	emulate -L zsh
	local dstfile="$1" srcfile="$2" label="${3:-}" l r
	if _vm_has_pretty; then
		l=$(_vm_pretty_temp "$dstfile") || return 1
		r=$(_vm_pretty_temp "$srcfile") || {
			rm -f "$l"
			return 1
		}
		print -r -- "  diff (отформатировано yq/jq, только просмотр — правки не сохраняются):"
		"${_vm_diff_cmd[@]}" "$l" "$r"
		rm -f "$l" "$r"
		if _vm_yesno "Сохранить версию another_base? (иначе — база; сохраняется оригинал)" n; then
			cp -p "$srcfile" "$dstfile" || {
				_vm_err "не удалось сохранить версию another_base"
				return 1
			}
			print -r -- "  → сохранена версия another_base (оригинал, без yq/jq)"
			_VM_LOG_RESOLVED+=("$label: сохранена версия another_base (оригинал)")
		else
			print -r -- "  → сохранена версия базы (оригинал)"
			_VM_LOG_RESOLVED+=("$label: сохранена версия базы (оригинал)")
		fi
	else
		_vm_warn "yq/jq не найдены: .bases/.canvas может быть в одну строку — открываю оригинал"
		_vm_merge_into "$dstfile" "$srcfile" "$label" || return 1
	fi
}

_vm_keep_both() {
	# $1 = dstfile (база, остаётся на месте), $2 = srcfile (another_base; сохраняется
	# рядом с суффиксом _from_another_base перед расширением), $3 = метка для лога.
	# Не перезаписывает существующее.
	emulate -L zsh
	local dstfile="$1" srcfile="$2" label="${3:-}"
	local dir="${dstfile:h}" base="${dstfile:t}" stem ext cand n=1
	if [[ "$base" == *.* && "$base" != .* ]]; then
		stem="${base%.*}"
		ext=".${base##*.}"
	else
		stem="$base"
		ext=""
	fi
	cand="${dir}/${stem}_from_another_base${ext}"
	while [[ -e "$cand" ]]; do
		((n++))
		cand="${dir}/${stem}_from_another_base.${n}${ext}"
	done
	cp -p "$srcfile" "$cand" || {
		_vm_err "не удалось сохранить второй вариант"
		return 1
	}
	print -r -- "    → база оставлена, another_baseный вариант: ${cand:t}"
	# Лог: новый файл (второй вариант из another_base).
	local reldir="${label:h}"
	[[ "$reldir" == "." ]] && reldir=""
	_VM_LOG_PHONE+=("${reldir}${reldir:+/}${cand:t} (второй вариант из another_base)")
}

_vm_binary_menu() {
	# Разрешение конфликта для ДВОИЧНЫХ файлов (вместо nvim -d). Возврат:
	#   0 — разрешено ([1]/[2]/[b]), 2 — пропущено ([s]), 1 — ошибка.
	emulate -L zsh
	local dstfile="$1" srcfile="$2" label="$3" choice
	print -r -- "  (двоичный файл: $label)"
	while :; do
		print -n -r -- "  [1] оставить базу, [2] заменить another_baseом, [b] сохранить оба, [s] пропустить (1): "
		read choice || choice="1"
		choice=${(L)choice}
		case "$choice" in
		1 | "")
			print -r -- "    → оставлена версия базы"
			_VM_LOG_RESOLVED+=("$label: оставлена версия базы (двоичный)")
			return 0
			;;
		2)
			cp -p "$srcfile" "$dstfile" || {
				_vm_err "не удалось заменить $label"
				return 1
			}
			print -r -- "    → заменено версией another_base"
			_VM_LOG_RESOLVED+=("$label: заменено версией another_base (двоичный)")
			return 0
			;;
		b)
			_vm_keep_both "$dstfile" "$srcfile" "$label" || return 1
			_VM_LOG_RESOLVED+=("$label: сохранены оба (двоичный)")
			return 0
			;;
		s)
			print -r -- "    → пропущено (оставлено в неразрешённых)"
			_VM_LOG_SKIPPED+=("$label (двоичный, пропущен)")
			return 2
			;;
		*) print -u2 -r -- "    некорректный ответ (1/2/b/s)" ;;
		esac
	done
}

_vm_resolve_pair() {
	# Единая точка разрешения «лево vs право». Диспетчеризует по типу файла:
	#   двоичный → _vm_binary_menu, .bases/.canvas → _vm_merge_pretty,
	#   иначе → _vm_merge_into (nvim -d).
	# Возврат транслируется из вызванного помощника (2 = бинарный [s]).
	emulate -L zsh
	local left="$1" right="$2" label="$3"
	if _vm_is_binary "$left" || _vm_is_binary "$right"; then
		_vm_binary_menu "$left" "$right" "$label"
	elif _vm_is_canvas_base "$left" || _vm_is_canvas_base "$right"; then
		_vm_merge_pretty "$left" "$right" "$label"
	else
		_vm_merge_into "$left" "$right" "$label"
	fi
}

_vm_copy_file() {
	# Копирует обычный файл, создавая при необходимости родительские каталоги.
	emulate -L zsh
	local src="$1" dstfile="$2"
	mkdir -p "${dstfile:h}" || {
		_vm_err "mkdir -p ${dstfile:h} не удался"
		return 1
	}
	cp -p "$src" "$dstfile" || {
		_vm_err "cp $src -> $dstfile не удался"
		return 1
	}
}

_vm_copy_symlink() {
	# Копирует симлинк. $3 = режим разыменования:
	#   0 — воссоздать как ссылку (ln -s с тем же целевым путём, что и в источнике);
	#   1 — разыменовать: скопировать содержимое цели (cp -pL для файла, cp -RpL для каталога).
	emulate -L zsh
	local src="$1" dstfile="$2" deref="$3"
	mkdir -p "${dstfile:h}" || {
		_vm_err "mkdir -p ${dstfile:h} не удался"
		return 1
	}
	if ((deref == 1)); then
		if [[ -e "$src" ]]; then
			if [[ -d "$src" ]]; then
				cp -RpL "$src" "$dstfile" || {
					_vm_err "не удалось разыменовать каталог $src"
					return 1
				}
			else
				cp -pL "$src" "$dstfile" || {
					_vm_err "не удалось разыменовать $src"
					return 1
				}
			fi
		else
			_vm_warn "симлинк $src указывает на несуществующую цель — сохраняю как ссылку"
			ln -s "$(readlink "$src")" "$dstfile" || {
				_vm_err "не удалось скопировать симлинк $src"
				return 1
			}
		fi
	else
		ln -s "$(readlink "$src")" "$dstfile" || {
			_vm_err "не удалось скопировать симлинк $src"
			return 1
		}
	fi
}

_vm_norm_relpath() {
	# Нормализует введённый пользователем относительный путь и печатает его.
	# Возвращает 1, если путь пустой или пытается выйти выше корня («..» компонентом).
	emulate -L zsh
	local p="$1"
	p=${p#${p%%[![:space:]]*}}
	p=${p%${p##*[![:space:]]}}
	[[ -n "$p" ]] || return 1
	p=${p#/}
	p=${p#./}
	while [[ "$p" == *//* ]]; do p=${p//\/\//\/}; done
	while [[ "$p" == */ ]]; do p=${p%/}; done # убрать завершающий слэш
	[[ "$p" == "." || -z "$p" ]] && return 1
	[[ "$p" == ".." || "$p" == ../* || "$p" == */../* || "$p" == */.. ]] && return 1
	print -r -- "$p"
}

_vm_sortkey() {
	# Строит ключ сортировки для относительного пути так, чтобы при лексикографической
	# сортировке файлы шли раньше подкаталогов на каждом уровне (0=файл, 1=каталог).
	#   «note.md»  -> 0note.md
	#   «notes/»   -> 1notes
	#   «a/b.md»   -> 1a/0b.md
	#   «a/sub/»   -> 1a/1sub
	emulate -L zsh
	local p="$1" key="" comp rest type
	if [[ "$p" == */ ]]; then
		type=1
		p=${p%/}
	else type=0; fi
	while [[ -n "$p" ]]; do
		comp="${p%%/*}"
		rest="${p#*/}"
		if [[ "$rest" == "$p" ]]; then # последняя компонента
			key+="${type}${comp}"
			break
		else
			key+="1${comp}/"
			p="$rest"
		fi
	done
	print -r -- "$key"
}

_vm_sort_by_dir() {
	# Печатает переданные пути ($@) в порядке «по каталогам»:
	# файлы корня, затем каталоги и их файлы, затем подкаталоги и их файлы.
	# Сортировка побайтовая (LC_ALL=C), чтобы не зависеть от локальной collation.
	emulate -L zsh
	local e key
	local -a lines=()
	for e in "$@"; do
		key=$(_vm_sortkey "$e")
		lines+=("${key}"$'\t'"${e}")
	done
	for e in "${lines[@]}"; do
		print -r -- "$e"
	done | LC_ALL=C command sort | command cut -f2-
}

_vm_group_by_first() {
	# Читает пути из stdin (уже отсортированные по каталогам) и печатает их,
	# сгруппированными по первой папке от корня: «### Корень», «### папка/».
	emulate -L zsh
	local line group prev=""
	while IFS= read -r line; do
		if [[ "$line" == */* ]]; then
			group="${line%%/*}"
		else
			group="Корень"
		fi
		if [[ "$group" != "$prev" ]]; then
			if [[ "$group" == "Корень" ]]; then
				print -r -- "### Корень"
			else
				print -r -- "### ${group}/"
			fi
			prev="$group"
		fi
		print -r -- "- $line"
	done
}

_vm_usage() {
	cat <<'EOF'
vault_merge — слияние двух хранилищ Obsidian в третье (исходники не изменяются)

Использование:
  vault_merge [-S] [-d] [--ask-new] <база> <another_base> [<итог>]
  vault_merge -h | --help

Аргументы:
  <база>     Первое хранилище (например, с ноутбука). Копируется в итог как есть.
  <another_base>  Второе хранилище (например, с another_base). Сравнивается с базой.
  <итог>     Путь к итоговому хранилищу. Если не указан — предлагается
             «<база>_merged» с подтверждением.

Флаги:
  -h, --help       Показать эту справку.
  -S, --dereference
                   Разыменовывать симлинки: копировать их как файлы/каталоги,
                   а не как ссылки. По умолчанию симлинки копируются как ссылки.
  -d, --no-obsidian
                   Игнорировать папки, начинающиеся с .obsidian, в корне хранилища.
  --ask-new        Подтверждать копирование каждого нового файла из <another_base>.

Поведение:
  1. Валидация путей: оба исходника существуют и являются каталогами, не
     совпадают друг с другом и с итогом; итог не внутри исходника и наоборот.
  2. Работа идёт во временной директории рядом с итогом; итог создаётся только
     после успешного завершения (Ctrl+C не оставляет «полуготовую» базу).
  3. Инициализация: в итог копируется всё содержимое <база> — обычные файлы,
     скрытые файлы, каталоги (включая пустые) и симлинки.
  4. Сравнение по относительным путям: новые файлы из <another_base>, конфликты
     содержимого, конфликты имён (одинаковый basename, разные пути).
  5. Итоговый отчёт.
  6. Лог-файл: создаётся «<итог>.merge.md» рядом с итоговым хранилищем
     (markdown для Obsidian: YAML-фронтматтер, «Содержание» с якорями, «Сводка»,
     секции с файлами, отсортированными по директориям).

Конфликт имён («один и тот же файл?» → да):
  На вопрос «Куда сохранить?» можно ответить:
  • каталог (например «.trash/» или «.trash») — файл кладётся туда с исходным именем;
  • полный путь («13-Movies/00-WatchList.base») — как есть;
  • номер варианта (1/2/…) — взять этот вариант целиком (путь + содержимое).

Форматы файлов:
  • Все файлы копируются байт-в-байт независимо от расширения (.md, .png, .pdf,
    .docx, .canvas, .bases и т.д.).
  • Двоичные (file --mime-encoding=binary или расширения png/jpg/pdf/zip/mp3…):
    конфликт содержимого разрешается меню [1]/[2]/[b]/[s]; в конфликте имён
    вместо дампа байтов показываются размер и дата (ls -lh).
  • .bases/.canvas (JSON/YAML): если есть yq или jq — конфликт открывается в
    nvim -d на отформатированной версии, но в итог сохраняется ОРИГИНАЛ. Если
    утилит нет — предупреждение и открытие оригинала.

Решения по спорным местам:
  • .obsidian — копируется из <база> как есть (настройки/плагины сохраняются).
  • Скрытые файлы — копируются все без исключений (включая .git).
  • Пустые каталоги — переносятся (из базы и новые из another_base).
  • Симлинки — по умолчанию копируются как ссылки; с флагом -S разыменовываются.
  • Симлинк из <another_base> с тем же путём, что уже есть в <база>, не копируется
    (приоритет базы); симлинки не участвуют в разрешении конфликтов содержимого.

Зависимости:
  zsh, cp, mv, rm, mkdir, mktemp, cmp, head, ln, readlink, file, ls, date, sort,
  cut (стандартные).
  Diff-редактор: nvim -d, иначе vimdiff, иначе vim -d.
  Опционально: bat (превью), lsd (дерево итога), yq/jq (pretty-просмотр .bases/.canvas).
  Переопределение редактора: переменная окружения VAULT_MERGE_DIFF.

Безопасность:
  Исходные хранилища никогда не открываются на запись: сторона <another_base> и
  дополнительные копии <база> попадают в редактор только как временные копии,
  сохранение происходит только внутри итогового хранилища.
EOF
}

vault_merge() {
	emulate -L zsh
	setopt localoptions extendedglob globdots nonomatch localtraps noxtrace

	_VM_STAGING=""
	_VM_LOG_BASE=()
	_VM_LOG_PHONE=()
	_VM_LOG_MOVED=()
	_VM_LOG_SKIPPED=()
	_VM_LOG_RESOLVED=()
	# Цвета включаем только в терминале (и без NO_COLOR).
	if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
		_VM_C_GREEN=$'\e[38;5;142m'
		_VM_C_BLUE=$'\e[38;5;109m'
		_VM_C_PURPLE=$'\e[38;5;175m'
		_VM_C_YELLOW=$'\e[38;5;214m'
		_VM_C_RED=$'\e[1;38;5;167m'
		_VM_C_AQUA=$'\e[38;5;108m'
		_VM_C_ORANGE=$'\e[1;38;5;208m'
		_VM_C_BOLD=$'\e[1m'
		_VM_C_OFF=$'\e[0m'
	fi
	trap '_vm_cleanup; return 1' INT TERM HUP
	trap '_vm_cleanup' EXIT

	# ---- разбор аргументов ----
	local -a args=()
	local ask_new=0 deref=0 skip_obsidian=0 a
	for a in "$@"; do
		case "$a" in
		-h | --help)
			_vm_usage
			return 0
			;;
		-S | --dereference) deref=1 ;;
		-d | --no-obsidian) skip_obsidian=1 ;;
		--ask-new) ask_new=1 ;;
		-*)
			print -u2 -r -- "vault_merge: неизвестный флаг: $a"
			_vm_usage >&2
			return 2
			;;
		*) args+=("$a") ;;
		esac
	done

	local base="${args[1]}" another_base="${args[2]}" out="${args[3]}"
	if [[ -z "$base" || -z "$another_base" ]]; then
		_vm_usage >&2
		return 2
	fi

	# ---- валидация исходников ----
	[[ -d "$base" ]] || {
		_vm_err "база не существует или не каталог: $base"
		return 1
	}
	[[ -d "$another_base" ]] || {
		_vm_err "another_base не существует или не каталог: $another_base"
		return 1
	}

	local base_abs another_base_abs out_abs
	base_abs=${base:A}
	another_base_abs=${another_base:A}
	[[ "$base_abs" != "$another_base_abs" ]] || {
		_vm_err "база и another_base — один и тот же путь"
		return 1
	}

	# ---- определение итогового пути ----
	if [[ -z "$out" ]]; then
		local default="${base_abs}_merged"
		if _vm_yesno "Итоговое хранилище не указано. Предлагаю: $default. Использовать?" y; then
			out="$default"
		else
			print -r -- "Отменено. Задайте третий аргумент явно."
			return 1
		fi
	fi
	out_abs=${out:A}

	# ---- проверки итогового пути ----
	[[ "$out_abs" != "/" ]] || {
		_vm_err "отказываюсь использовать / как итог"
		return 1
	}
	[[ "$out_abs" != "$base_abs" && "$out_abs" != "$another_base_abs" ]] ||
		{
			_vm_err "итог совпадает с исходным хранилищем"
			return 1
		}
	[[ "$out_abs" != "$base_abs"/* && "$out_abs" != "$another_base_abs"/* ]] ||
		{
			_vm_err "итог не должен находиться внутри исходного хранилища"
			return 1
		}
	[[ "$base_abs" != "$out_abs"/* && "$another_base_abs" != "$out_abs"/* ]] ||
		{
			_vm_err "исходное хранилище не должно находиться внутри итога"
			return 1
		}

	local clear_existing=0
	if [[ -e "$out_abs" || -L "$out_abs" ]]; then
		if _vm_yesno "Итоговое хранилище уже существует: $out_abs. Очистить его?" n; then
			clear_existing=1
		else
			return 1
		fi
	fi

	# ---- родительский каталог и очистка «забытых» временных каталогов ----
	mkdir -p "${out_abs:h}" || {
		_vm_err "не удалось создать каталог ${out_abs:h}"
		return 1
	}
	local stale
	for stale in "${out_abs:h}"/.vault_merge_staging.*(N/); do
		_vm_warn "найден оставшийся временный каталог $stale — удаляю"
		rm -rf "$stale"
	done

	# ---- обход деревьев ----
	# zsh-глоббы ** не заходят в симлинкованные каталоги (проверено), поэтому
	# (.) = обычные файлы, (/) = каталоги (в т.ч. пустые), (@) = симлинки.
	# Квалификаторы: N = nullglob, D = включать скрытые.
	local -a f1 f2 d1 d2 s1 s2
	f1=("${base_abs}"/**/*(ND.))         # обычные файлы базы
	f2=("${another_base_abs}"/**/*(ND.)) # обычные файлы another_base
	d1=("${base_abs}"/**/*(ND/))         # каталоги базы (включая пустые)
	d2=("${another_base_abs}"/**/*(ND/)) # каталоги another_base
	s1=("${base_abs}"/**/*(ND@))         # симлинки базы
	s2=("${another_base_abs}"/**/*(ND@)) # симлинки another_base
	# -d: игнорировать папки, начинающиеся с .obsidian, в корне хранилища.
	if ((skip_obsidian == 1)); then
		f1=(${f1:#${base_abs}/.obsidian*})
		f2=(${f2:#${another_base_abs}/.obsidian*})
		d1=(${d1:#${base_abs}/.obsidian*})
		d2=(${d2:#${another_base_abs}/.obsidian*})
		s1=(${s1:#${base_abs}/.obsidian*})
		s2=(${s2:#${another_base_abs}/.obsidian*})
	fi
	local bp=$((${#base_abs} + 1)) pp=$((${#another_base_abs} + 1))

	typeset -A in1 in2 s1map d1map
	local f rel
	for f in "${f1[@]}"; do in1[${f:$bp}]=1; done
	for f in "${f2[@]}"; do in2[${f:$pp}]=1; done
	for f in "${s1[@]}"; do s1map[${f:$bp}]=1; done
	for f in "${d1[@]}"; do d1map[${f:$bp}]=1; done

	# ---- временная директория и инициализация из базы ----
	_VM_STAGING=$(mktemp -d "${out_abs:h}/.vault_merge_staging.XXXXXX") ||
		{
			_vm_err "mktemp -d не удался"
			return 1
		}
	local dst="${_VM_STAGING}/vault"
	mkdir -p "$dst" || {
		_vm_err "не удалось создать $dst"
		return 1
	}

	# Лог: что откуда взято и что перемещено (глобальные массивы сброшены выше).

	# 1) каталоги (чтобы сохранить и пустые)
	local dir_count=0
	for f in "${d1[@]}"; do
		rel=${f:$bp}
		mkdir -p "$dst/$rel" || {
			_vm_err "mkdir -p $dst/$rel не удался"
			return 1
		}
		_VM_LOG_BASE+=("$rel/")
		((dir_count++))
	done
	# 2) обычные файлы
	local init_count=0
	for f in "${f1[@]}"; do
		rel=${f:$bp}
		_vm_copy_file "$f" "$dst/$rel" || return 1
		_VM_LOG_BASE+=("$rel")
		((init_count++))
	done
	# 3) симлинки
	local symlink_base_count=0
	for f in "${s1[@]}"; do
		rel=${f:$bp}
		_vm_copy_symlink "$f" "$dst/$rel" "$deref" || return 1
		_VM_LOG_BASE+=("$rel (симлинк)")
		((symlink_base_count++))
	done
	print -r -- "${_VM_C_AQUA}Инициализация${_VM_C_OFF}: файлов из ${_VM_C_GREEN}базы${_VM_C_OFF} ($base): $init_count; каталогов (вкл. пустые): $dir_count; симлинков: $symlink_base_count"

	_vm_ensure_diff || return 1

	# ---- конфликты содержимого (одинаковый путь, разное содержимое) ----
	local -a content_paths=()
	for rel in ${(ko)in1}; do
		[[ -n "${in2[$rel]}" ]] || continue
		cmp -s "$base_abs/$rel" "$another_base_abs/$rel" || content_paths+=("$rel")
	done
	local content_total=${#content_paths} content_done=0
	local -a content_skipped_log=()
	if ((content_total > 0)); then
		print -r -- "${_VM_C_YELLOW}Конфликты содержимого: $content_total${_VM_C_OFF}"
		local prc
		for rel in "${content_paths[@]}"; do
			print -r -- ""
			print -r -- "${_VM_C_YELLOW}⚡ Конфликт содержимого: $rel${_VM_C_OFF}"
			_vm_resolve_pair "$dst/$rel" "$another_base_abs/$rel" "$rel"
			prc=$?
			if ((prc == 2)); then
				content_skipped_log+=("≠ $rel   (двоичный, пропущен)")
			else
				((content_done++))
			fi
		done
	fi

	# ---- подготовка к конфликтам имён (только обычные файлы) ----
	typeset -A only1 only2
	for rel in ${(k)in1}; do [[ -n "${in2[$rel]}" ]] || only1[$rel]=1; done
	for rel in ${(k)in2}; do [[ -n "${in1[$rel]}" ]] || only2[$rel]=1; done

	local new_count=0 skipped_count=0 name_renamed=0 name_different=0
	local symlink_new_count=0 new_dir_count=0
	local -a new_log=() rename_log=() different_log=() symlink_log=() skipped_log=()
	typeset -A handled

	local sep=$'\x1f'
	local -a cand=()
	for rel in ${(k)only1}; do cand+=("${rel:t}${sep}${rel}"); done
	for rel in ${(k)only2}; do cand+=("${rel:t}${sep}${rel}"); done
	cand=(${(o)cand})

	# ---- конфликты имён (одинаковый basename, разные пути) ----
	local i=0 total=${#cand} entry curb nxt
	local -a members
	while ((i < total)); do
		i=$((i + 1))
		entry=${cand[i]}
		curb=${entry%%$sep*}
		members=()
		while :; do
			members+=("${entry#*$sep}")
			if ((i < total)); then
				nxt=${cand[$((i + 1))]}
				if [[ ${nxt%%$sep*} == "$curb" ]]; then
					i=$((i + 1))
					entry=${cand[i]}
				else
					break
				fi
			else
				break
			fi
		done

		((${#members} >= 2)) || continue

		print -r -- ""
		print -r -- "${_VM_C_YELLOW}🧩 Конфликт имён: basename «$curb» — ${#members} файл(а), пути не совпадают${_VM_C_OFF}"
		local m idx=0
		for m in "${members[@]}"; do
			idx=$((idx + 1))
			if [[ -n "${only1[$m]}" ]]; then
				print -r -- "  [$idx] ${_VM_C_AQUA}$m${_VM_C_OFF}   (${_VM_C_ORANGE}в базе, уже в итоге${_VM_C_OFF})"
				_vm_preview_member "$base_abs/$m"
			else
				print -r -- "  [$idx] ${_VM_C_AQUA}$m${_VM_C_OFF}   (${_VM_C_BLUE}в another_baseе${_VM_C_OFF})"
				_vm_preview_member "$another_base_abs/$m"
			fi
			print -r -- ""
			print -r -- "  ────────────────────────"
		done

		if _vm_yesno "Это один и тот же файл?" n; then
			# ---- выбрать: номер варианта ИЛИ каталог/путь ----
			local finalp="" line ok chosen_ndx=0
			local nm=${#members}
			while :; do
				print -n -r -- "Куда сохранить? (каталог/путь, или номер варианта 1-${nm}): "
				read line || {
					_vm_err "ввод прерван"
					return 1
				}
				line=${line#${line%%[![:space:]]*}}
				line=${line%${line##*[![:space:]]}}
				if [[ "$line" == <-> ]] && ((line >= 1 && line <= nm)); then
					chosen_ndx=$line
					break
				fi
				finalp=$(_vm_norm_relpath "$line") || finalp=""
				[[ -n "$finalp" ]] || {
					print -u2 -r -- "  некорректный ввод, попробуйте ещё"
					continue
				}
				# Каталог без имени файла → добавляем исходное имя (basename группы).
				[[ "${finalp:t}" == "$curb" ]] || finalp="${finalp}/${curb}"
				ok=0
				for m in "${members[@]}"; do
					[[ "$m" == "$finalp" && -n "${only1[$m]}" ]] && ok=1
				done
				if [[ -e "$dst/$finalp" && $ok -eq 0 ]]; then
					print -u2 -r -- "  путь уже занят в итоге: $finalp"
					continue
				fi
				break
			done

			# Разбиваем группу на файлы базы (уже в итоге) и файлы another_base.
			local -a m1=() m2=()
			for m in "${members[@]}"; do
				[[ -n "${only1[$m]}" ]] && m1+=("$m") || m2+=("$m")
			done

			local k
			if ((chosen_ndx > 0)); then
				# Выбран конкретный вариант — берём его целиком (путь + содержимое), без редактора.
				local chosen="${members[$chosen_ndx]}"
				if [[ -n "${only1[$chosen]}" ]]; then
					print -r -- "  ${_VM_C_PURPLE}выбран вариант${_VM_C_OFF} [$chosen_ndx] «$chosen» (${_VM_C_GREEN}база${_VM_C_OFF}) — оставлен как есть"
					for ((k = 1; k <= ${#m1}; k++)); do
						if [[ "${m1[$k]}" != "$chosen" ]]; then
							rm -f "$dst/${m1[$k]}"
							_VM_LOG_MOVED+=("удалён дубликат: ${m1[$k]}")
						fi
					done
					_VM_LOG_MOVED+=("выбран вариант [$chosen_ndx] «$chosen» (из базы) — без переименования")
				else
					_vm_copy_file "$another_base_abs/$chosen" "$dst/$chosen" || return 1
					print -r -- "  ${_VM_C_PURPLE}выбран вариант${_VM_C_OFF} [$chosen_ndx] «$chosen» (${_VM_C_BLUE}another_base${_VM_C_OFF}) — скопирован"
					for ((k = 1; k <= ${#m1}; k++)); do
						rm -f "$dst/${m1[$k]}"
						_VM_LOG_MOVED+=("удалён дубликат: ${m1[$k]}")
					done
					_VM_LOG_PHONE+=("$chosen")
					_VM_LOG_MOVED+=("выбран вариант [$chosen_ndx] «$chosen» (из another_base) — без переименования")
				fi
				rename_log+=("• выбран вариант [$chosen_ndx] «$chosen»  ←  ${(j:, :)members}")
			else
				# ---- каталог/путь: переместить и слить содержимое ----
				# Есть ли в группе двоичные файлы?
				local grp_binary=0 srcp
				for m in "${members[@]}"; do
					[[ -n "${only1[$m]}" ]] && srcp="$base_abs/$m" || srcp="$another_base_abs/$m"
					if _vm_is_binary "$srcp"; then
						grp_binary=1
						break
					fi
				done

				if ((grp_binary == 1)); then
					# Двоичные «то же самое»: без nvim — просто переносим файл.
					if ((${#m1} > 0)); then
						if [[ "${m1[1]}" == "$finalp" ]]; then
							if ((${#m2} > 0)); then
								_vm_binary_menu "$dst/$finalp" "$another_base_abs/${m2[1]}" "$finalp"
								local bprc=$?
								((bprc == 1)) && return 1
							fi
						else
							mkdir -p "$dst/${finalp:h}"
							mv "$dst/${m1[1]}" "$dst/$finalp" || {
								_vm_err "mv не удался"
								return 1
							}
							_VM_LOG_MOVED+=("переименование: ${m1[1]} → $finalp")
						fi
						for ((k = 2; k <= ${#m1}; k++)); do
							rm -f "$dst/${m1[$k]}"
							_VM_LOG_MOVED+=("удалён дубликат: ${m1[$k]}")
						done
					else
						mkdir -p "$dst/${finalp:h}"
						_vm_copy_file "$another_base_abs/${m2[1]}" "$dst/$finalp" || return 1
						_VM_LOG_MOVED+=("переименование: ${m2[1]} → $finalp")
					fi
					print -r -- "  ${_VM_C_PURPLE}двоичный файл объединён${_VM_C_OFF} в «$finalp» (без diff)"
				else
					# Текстовые (включая .bases/.canvas): обычное слияние через редактор.
					if ((${#m1} > 0)); then
						if [[ "${m1[1]}" != "$finalp" ]]; then
							mkdir -p "$dst/${finalp:h}"
							mv "$dst/${m1[1]}" "$dst/$finalp" || {
								_vm_err "mv не удался"
								return 1
							}
							print -r -- "  ${_VM_C_PURPLE}переименовано${_VM_C_OFF}: ${m1[1]} -> $finalp"
							_VM_LOG_MOVED+=("переименование: ${m1[1]} → $finalp")
						else
							print -r -- "  файл остаётся по пути: $finalp"
						fi
						for ((k = 2; k <= ${#m1}; k++)); do
							_vm_resolve_pair "$dst/$finalp" "$dst/${m1[$k]}" "$finalp" || return 1
							rm -f "$dst/${m1[$k]}"
							_VM_LOG_MOVED+=("объединение: ${m1[$k]} → $finalp")
						done
						for ((k = 1; k <= ${#m2}; k++)); do
							_vm_resolve_pair "$dst/$finalp" "$another_base_abs/${m2[$k]}" "$finalp" || return 1
						done
					else
						mkdir -p "$dst/${finalp:h}"
						_vm_copy_file "$another_base_abs/${m2[1]}" "$dst/$finalp" || return 1
						print -r -- "  ${_VM_C_PURPLE}создано из${_VM_C_OFF} ${_VM_C_BLUE}another_base${_VM_C_OFF}: $finalp"
						_VM_LOG_MOVED+=("переименование: ${m2[1]} → $finalp")
						for ((k = 2; k <= ${#m2}; k++)); do
							_vm_resolve_pair "$dst/$finalp" "$another_base_abs/${m2[$k]}" "$finalp" || return 1
						done
					fi
				fi
				rename_log+=("• объединено в «$finalp»  ←  ${(j:, :)members}")
			fi

			for m in "${members[@]}"; do handled[$m]=1; done
			((name_renamed++))
		else
			# ---- оставить как разные (не терять ни один файл) ----
			for m in "${members[@]}"; do
				if [[ -n "${only2[$m]}" ]]; then
					_vm_copy_file "$another_base_abs/$m" "$dst/$m" || return 1
					new_log+=("+ $m   (из another_base, оставлен как «разный» файл)")
					different_log+=("≠ $m")
					_VM_LOG_PHONE+=("$m")
					((new_count++))
					((name_different++))
					handled[$m]=1
				fi
			done
		fi
	done

	# ---- новые обычные файлы из another_base (не затронутые конфликтами имён) ----
	for rel in ${(ko)only2}; do
		[[ -n "${handled[$rel]}" ]] && continue
		if [[ -d "$dst/$rel" ]]; then
			_vm_warn "путь $rel в итоге занят каталогом — файл из another_base пропущен"
			_VM_LOG_SKIPPED+=("$rel (путь занят каталогом, файл из another_base пропущен)")
			continue
		fi
		if ((ask_new == 1)); then
			if _vm_yesno "Копировать новый файл из another_base: $rel ?" n; then
				_vm_copy_file "$another_base_abs/$rel" "$dst/$rel" || return 1
				new_log+=("+ $rel   (новый из another_base)")
				_VM_LOG_PHONE+=("$rel")
				((new_count++))
			else
				skipped_log+=("- $rel   (пропущен)")
				_VM_LOG_SKIPPED+=("$rel (пропущен по --ask-new)")
				((skipped_count++))
			fi
		else
			_vm_copy_file "$another_base_abs/$rel" "$dst/$rel" || return 1
			new_log+=("+ $rel   (новый из another_base)")
			_VM_LOG_PHONE+=("$rel")
			((new_count++))
		fi
	done

	# ---- новые симлинки из another_base ----
	for f in "${s2[@]}"; do
		rel=${f:$pp}
		[[ -n "${in1[$rel]}" || -n "${s1map[$rel]}" ]] && continue
		_vm_copy_symlink "$f" "$dst/$rel" "$deref" || return 1
		symlink_log+=("+ $rel   (симлинк из another_base)")
		_VM_LOG_PHONE+=("$rel (симлинк)")
		((symlink_new_count++))
	done

	# ---- новые каталоги из another_base (включая пустые) ----
	for f in "${d2[@]}"; do
		rel=${f:$pp}
		[[ -n "${d1map[$rel]}" ]] && continue
		if [[ -e "$dst/$rel" && ! -d "$dst/$rel" ]]; then
			_vm_warn "путь $rel в итоге занят файлом — каталог из another_base пропущен"
			_VM_LOG_SKIPPED+=("$rel/ (путь занят файлом, каталог из another_base пропущен)")
			continue
		fi
		mkdir -p "$dst/$rel" || {
			_vm_err "mkdir -p $dst/$rel не удался"
			return 1
		}
		_VM_LOG_PHONE+=("$rel/")
		((new_dir_count++))
	done

	# ---- финализация: атомарная подстановка итога ----
	if ((clear_existing == 1)); then
		rm -rf "$out_abs" || {
			_vm_err "не удалось очистить $out_abs"
			return 1
		}
	fi
	mv "$dst" "$out_abs" || {
		_vm_err "не удалось переместить итог в $out_abs"
		return 1
	}
	rmdir "$_VM_STAGING" 2>/dev/null
	_VM_STAGING=""

	# ---- отчёт ----
	local symlink_copied=$((symlink_base_count + symlink_new_count))
	print -r -- ""
	print -r -- "${_VM_C_AQUA}════════════════════════════════════════════════════${_VM_C_OFF}"
	print -r -- " ${_VM_C_GREEN}vault_merge: готово${_VM_C_OFF}"
	print -r -- " Итог: $out_abs"
	print -r -- "${_VM_C_AQUA}════════════════════════════════════════════════════${_VM_C_OFF}"
	print -r -- " Скопировано из ${_VM_C_GREEN}базы${_VM_C_OFF} (инициализация): файлов $init_count, каталогов (вкл. пустые) $dir_count"
	print -r -- " Новых файлов из ${_VM_C_BLUE}another_base${_VM_C_OFF}: $new_count"
	if ((${#new_log} > 0)); then
		print -r -- "   Новые/добавленные файлы:"
		for m in "${new_log[@]}"; do print -r -- "     $m"; done
	fi
	print -r -- " Новых каталогов из another_base: $new_dir_count"
	if ((deref == 1)); then
		print -r -- " Симлинков разыменовано в файлы: $symlink_copied"
	else
		print -r -- " Симлинков скопировано как ссылки: $symlink_copied"
	fi
	if ((${#symlink_log} > 0)); then
		for m in "${symlink_log[@]}"; do print -r -- "     $m"; done
	fi
	print -r -- " ${_VM_C_YELLOW}Конфликты содержимого${_VM_C_OFF}: разрешено $content_done, осталось $((content_total - content_done))"
	if ((${#content_skipped_log} > 0)); then
		print -r -- "   Пропущено (двоичные, не разрешены):"
		for m in "${content_skipped_log[@]}"; do print -r -- "     $m"; done
	fi
	print -r -- " ${_VM_C_YELLOW}Конфликты имён${_VM_C_OFF}: объединено (переименовано) $name_renamed, оставлено как «разные» файлов: $name_different"
	if ((${#rename_log} > 0)); then
		print -r -- "   Переименования/объединения:"
		for m in "${rename_log[@]}"; do print -r -- "     $m"; done
	fi
	if ((${#different_log} > 0)); then
		print -r -- "   Оставлены как разные:"
		for m in "${different_log[@]}"; do print -r -- "     $m"; done
	fi
	if ((skipped_count > 0)); then
		print -r -- " Пропущено по --ask-new: $skipped_count"
		for m in "${skipped_log[@]}"; do print -r -- "     $m"; done
	fi
	if command -v lsd >/dev/null 2>&1; then
		print -r -- " Дерево итога (lsd):"
		lsd --tree "$out_abs"
	fi

	# ---- лог-файл (.md для Obsidian) ----
	local logfile="${out_abs:h}/${out_abs:t}.merge.md"
	local base_name="${base:t}" another_name="${another_base:t}"
	local t_iso=$(date '+%Y-%m-%dT%H:%M:%S')
	local t_h=$(date '+%Y-%m-%d %H:%M:%S')
	{
		# фронтматтер (YAML для Obsidian)
		print -r -- "---"
		print -r -- "tags:"
		print -r -- "- merge_log"
		print -r -- "time: $t_iso"
		print -r -- "merge_bases:"
		print -r -- "  - $base_name"
		print -r -- "  - $another_name"
		print -r -- "where: \"$out_abs\""
		print -r -- "---"
		print -r -- ""
		print -r -- "# vault_merge_log_$t_h"
		print -r -- ""
		# Содержание (якорные ссылки)
		print -r -- "## Содержание"
		print -r -- "- [[#Сводка]]"
		print -r -- "- [[#Взято из базы]]"
		print -r -- "- [[#Взято из another_base]]"
		print -r -- "- [[#Перемещения и переименования]]"
		print -r -- "- [[#Разрешения конфликтов]]"
		print -r -- "- [[#Пропущено и не разрешено]]"
		print -r -- ""
		# Сводка
		print -r -- "## Сводка"
		print -r -- "| Секция | Кол-во |"
		print -r -- "|---|---|"
		print -r -- "| Взято из базы | ${#_VM_LOG_BASE} |"
		print -r -- "| Взято из another_base | ${#_VM_LOG_PHONE} |"
		print -r -- "| Перемещения и переименования | ${#_VM_LOG_MOVED} |"
		print -r -- "| Разрешения конфликтов | ${#_VM_LOG_RESOLVED} |"
		print -r -- "| Пропущено и не разрешено | ${#_VM_LOG_SKIPPED} |"
		print -r -- ""
		# Секции
		print -r -- "## Взято из базы"
		_vm_sort_by_dir "${_VM_LOG_BASE[@]}" | _vm_group_by_first
		print -r -- ""
		print -r -- "## Взято из another_base"
		_vm_sort_by_dir "${_VM_LOG_PHONE[@]}" | _vm_group_by_first
		print -r -- ""
		print -r -- "## Перемещения и переименования"
		if ((${#_VM_LOG_MOVED} > 0)); then
			for m in "${_VM_LOG_MOVED[@]}"; do print -r -- "- $m"; done
		else
			print -r -- "- (нет)"
		fi
		print -r -- ""
		print -r -- "## Разрешения конфликтов"
		if ((${#_VM_LOG_RESOLVED} > 0)); then
			for m in ${(o)_VM_LOG_RESOLVED}; do print -r -- "- $m"; done
		else
			print -r -- "- (нет)"
		fi
		print -r -- ""
		print -r -- "## Пропущено и не разрешено"
		if ((${#_VM_LOG_SKIPPED} > 0)); then
			for m in ${(o)_VM_LOG_SKIPPED}; do print -r -- "- $m"; done
		else
			print -r -- "- (нет)"
		fi
	} >"$logfile" || _vm_warn "не удалось записать лог-файл $logfile"
	print -r -- " ${_VM_C_GREEN}Лог${_VM_C_OFF}: $logfile"
}
