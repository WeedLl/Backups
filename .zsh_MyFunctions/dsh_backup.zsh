# dsh_backup — бэкап и разгрузка настроек DSH (все профили + состояние dsh-TUI)
#
#   dsh_backup -b <путь>     сохранить конфиги всех профилей + состояние dsh-TUI
#   dsh_backup -u <путь>     разгрузить (восстановить) из бэкапа
#
# Дополнительно:
#   -n, --dry-run        показать план, ничего не писать
#   -s, --secrets        включить ~/.dsh/.credentials.yaml (при разгрузке — восстановить)
#   -f, --force          при разгрузке не сверять контрольные суммы
#       --with-sessions  вместе с историей диалогов (~/.dsh/sessions)
#
# Зависимости: zsh 5+, shasum, du, date (macOS — всё есть).

dsh_backup() {
	emulate -L zsh
	setopt extended_glob null_glob

	local DSH_DIR="${DSH_HOME:-$HOME/.dsh}"
	local TUI_DIR="${DSH_TUI_HOME:-$HOME/.dsh-tui}"
	local mode='' target='' dry=0 secrets=0 force=0 sessions=0

	while (( $# )); do
		case "$1" in
			-h|--help)
				_dsh_backup_usage
				return 0
				;;
			-n|--dry-run)
				dry=1
				shift
				;;
			-s|--secrets)
				secrets=1
				shift
				;;
			-f|--force)
				force=1
				shift
				;;
			--with-sessions)
				sessions=1
				shift
				;;
			-b|--backup|-u|--unload)
				if [[ -n $mode ]]; then
					print -u2 "dsh_backup: второй режим ($1) — нужен ровно один: -b или -u"
					return 2
				fi
				if [[ $1 == -b || $1 == --backup ]]; then mode=b; else mode=u; fi
				shift
				if [[ -n ${1:-} && ${1:-} != -* ]]; then
					target=$1
					shift
				fi
				;;
			-*)
				print -u2 "dsh_backup: неизвестный флаг: $1"
				print -u2 "подсказка: dsh_backup -h"
				return 2
				;;
			*)
				if [[ -n $target ]]; then
					print -u2 "dsh_backup: лишний аргумент: $1"
					return 2
				fi
				target=$1
				shift
				;;
		esac
	done

	if [[ -z $mode ]]; then
		print -u2 "dsh_backup: нужен -b <путь> или -u <путь>"
		_dsh_backup_usage >&2
		return 2
	fi
	if [[ -z $target ]]; then
		print -u2 "dsh_backup: не указан путь"
		return 2
	fi

	# ~ → $HOME, без полного glob (чтобы не съесть спецсимволы в пути)
	if [[ $target == "~"* ]]; then
		target="${HOME}${target#\~}"
	fi
	target=${target%/}
	[[ -z $target ]] && target=/

	print "DSH: $DSH_DIR"
	print "TUI: $TUI_DIR"

	if [[ ! -d $DSH_DIR ]]; then
		print -u2 "dsh_backup: не найден каталог DSH: $DSH_DIR"
		print -u2 "подсказка: export DSH_HOME=/путь/к/.dsh"
		return 1
	fi

	if [[ $mode == b ]]; then
		_dsh_backup_save "$DSH_DIR" "$TUI_DIR" "$target" "$dry" "$secrets" "$sessions"
	else
		_dsh_backup_load "$DSH_DIR" "$TUI_DIR" "$target" "$dry" "$secrets" "$force" "$sessions"
	fi
}

# ─────────────────────────────────────────────────────────────────────────────

_dsh_backup_usage() {
	cat <<'EOF'
dsh_backup — бэкап и разгрузка настроек DeepSeek Harness

  dsh_backup -b <путь>     забэкапить настройки всех профилей (+ состояние dsh-TUI)
  dsh_backup -u <путь>     разгрузить бэкап обратно
  dsh_backup -n <режим> …  dry-run: только показать план
  dsh_backup -s <режим> …  вместе с секретами (~/.dsh/.credentials.yaml)
  dsh_backup -f -u …       не проверять контрольные суммы (бэкап правился руками)
  dsh_backup … --with-sessions   вместе с историей диалогов

Бэкап кладётся деревом в <путь>/dsh-backup-<ГГГГММДД-ЧЧММСС>/:
  profiles/<имя>/{package.json, cordis.patch.yml, cordis.yml,
                  pnpm-lock.yaml, pnpm-workspace.yaml}
  tui-state/{settings.json, theme.json, lang.json, permission.json,
             history.jsonl, model-recents.json, resume.txt, …}
  home/{settings.yaml, cordis.patch.yml}     (если есть)
  sessions/                                  (только с --with-sessions)
  credentials.yaml                           (только с -s, режим 600)
  manifest.txt, checksums.txt

НЕ входит: node_modules/ (ставится заново), session-index.json и
session-mounts.json (кэш и чужие pid'ы), inject/ (unix-сокеты),
~/.dsh/skills/ — личные скиллы (SKILL.md), их восстанавливай отдельно.

Скиллы (~/.dsh/skills/<имя>/SKILL.md) в бэкап не попадают: это обычные
каталоги с текстом, их немного и они маленькие.

  # 1) скилл из своего репозитория/рабочей папки
  mkdir -p ~/.dsh/skills
  rsync -a <путь>/md-answer_skill/ ~/.dsh/skills/md-answer_skill/

  # 2) скилл, поставленный плагином (например fact-check), — вместе с плагином
  dsh plugin --profile <имя> install

  # 3) если сохранил каталог ~/.dsh/skills руками — просто верни его целиком
  rsync -a <резервная-копия>/skills/ ~/.dsh/skills/

После разгрузки на новой машине:
  dsh plugin --profile <имя> install     # вернуть плагины из package.json
  dsh tui
  /skills                                # проверить, что скиллы видны

Плагины из package.json вернутся, только если доступны их источники:
для записей вида file:/Users/... каталог-источник должен существовать,
иначе pnpm install упадёт. Такие плагины копируй вместе с исходниками.

Примеры:
  dsh_backup -b ~/Documents/Backups/DSH
  dsh_backup -b /Volumes/usb/DSH --with-sessions
  dsh_backup -u ~/Documents/Backups/DSH/dsh-backup-20261102-224500
  dsh_backup -n -b /tmp/test
EOF
}

# ─────────────────────────────────────────────────────────────────────────────

_dsh_backup_save() {
	local dsh=$1 tui=$2 target=$3 dry=$4 secrets=$5 sessions=$6
	local stamp root name f src out n total_prof=0 total_tui=0 total_home=0
	local -a profiles
	local -a tui_files=(
		settings.json theme.json lang.json permission.json
		history.jsonl model-recents.json onboarding.json migrations.json
		resume.txt home.json trajectory.json usage.json
		session-pins.json extension-grants.json model.json effort.json
	)

	stamp=$(date +%Y%m%d-%H%M%S) || return 1
	root="$target/dsh-backup-$stamp"

	if (( dry )); then
		print "[dry-run] бэкап был бы здесь: $root"
	else
		if ! mkdir -p "$target" 2>/dev/null; then
			print -u2 "dsh_backup: не удалось создать каталог: $target"
			return 1
		fi
		if [[ ! -w $target ]]; then
			print -u2 "dsh_backup: нет прав на запись: $target"
			return 1
		fi
		[[ -e $root ]] && root="${root}-$$"
		if ! mkdir -p "$root/profiles"; then
			print -u2 "dsh_backup: не удалось создать: $root/profiles"
			return 1
		fi
	fi

	# ── профили ──────────────────────────────────────────────────────────
	for src in "$dsh"/profiles/*(N/); do
		profiles+=("${src:t}")
	done

	if (( ${#profiles} == 0 )); then
		print "dsh_backup: профилей не найдено в $dsh/profiles"
	else
		print "профили ($(( ${#profiles} ))): ${(j:, :)profiles}"
		for name in "${profiles[@]}"; do
			src="$dsh/profiles/$name"
			out="$root/profiles/$name"
			(( dry )) || mkdir -p "$out"

			n=0
			for f in package.json cordis.patch.yml cordis.yml pnpm-lock.yaml pnpm-workspace.yaml; do
				[[ -f "$src/$f" ]] || continue
				_dsh_backup_copy "$src/$f" "$out/$f" "$dry" || continue
				(( ++n ))
			done
			(( total_prof += n ))
			print "  ✓ $name — файлов: $n"

			if [[ $name == tui || $name == dsh-tui ]] && [[ -d "$src/node_modules" ]]; then
				print "    (node_modules есть — в бэкап не входит, ставится заново)"
			fi
		done
	fi

	# ── состояние dsh-TUI ────────────────────────────────────────────────
	if [[ -d $tui ]]; then
		(( dry )) || mkdir -p "$root/tui-state"
		for f in "${tui_files[@]}"; do
			[[ -f "$tui/$f" ]] || continue
			_dsh_backup_copy "$tui/$f" "$root/tui-state/$f" "$dry" || continue
			(( ++total_tui ))
		done
		print "dsh-TUI ($tui): файлов — $total_tui"
	else
		print "dsh-TUI не найден ($tui) — пропускаю"
	fi

	# ── история диалогов (опционально) ───────────────────────────────────
	if (( sessions )); then
		if [[ -d "$dsh/sessions" ]]; then
			local size
			size=$(du -sh "$dsh/sessions" 2>/dev/null | awk '{print $1}')
			print "сессии: ${size:-?} — копирую (это может занять время)"
			if _dsh_backup_copy_tree "$dsh/sessions" "$root/sessions" "$dry"; then
				if (( ! dry )); then
					find "$root/sessions" -name '*.lock' -delete 2>/dev/null
					local cnt
					cnt=$(find "$root/sessions" -name 'session.v4.jsonl.zstd' 2>/dev/null | wc -l | tr -d ' ')
					print "  ✓ сессий: ${cnt:-0}"
				fi
			else
				print -u2 "  ✗ сессии скопировать не удалось"
			fi
		else
			print "сессии: каталог не найден — пропускаю"
		fi
	else
		print "сессии: не включены (добавь --with-sessions)"
	fi

	# ── секреты ──────────────────────────────────────────────────────────
	if (( secrets )); then
		if [[ -f "$dsh/.credentials.yaml" ]]; then
			if _dsh_backup_copy "$dsh/.credentials.yaml" "$root/credentials.yaml" "$dry"; then
				(( dry )) || chmod 600 "$root/credentials.yaml" 2>/dev/null
				print "секреты: .credentials.yaml (режим 600)"
			fi
		else
			print "секреты: .credentials.yaml не найден"
		fi
	else
		print "секреты: не включены (добавь -s, если нужны ключи)"
	fi

	# ── домашний слой DSH ────────────────────────────────────────────────
	for f in settings.yaml cordis.patch.yml; do
		[[ -f "$dsh/$f" ]] || continue
		(( dry )) || mkdir -p "$root/home"
		_dsh_backup_copy "$dsh/$f" "$root/home/$f" "$dry" && (( ++total_home ))
	done
	if (( total_home )); then
		print "домашний слой: файлов — $total_home"
	fi

	# ── манифест и контрольные суммы ─────────────────────────────────────
	if (( dry )); then
		print "[dry-run] манифест: $root/manifest.txt"
		print "[dry-run] готово, ничего не записано"
		return 0
	fi

	if ! _dsh_backup_manifest "$root" "$dsh" "$tui" "$secrets" "$sessions" \
		"${(j: :)profiles}" "$total_prof" "$total_tui"; then
		print -u2 "dsh_backup: не удалось записать манифест"
		return 1
	fi

	print ""
	print "готово: $root"
	print "восстановить: dsh_backup -u \"$root\""
	return 0
}

# ─────────────────────────────────────────────────────────────────────────────

_dsh_backup_manifest() {
	local root=$1 dsh=$2 tui=$3 secrets=$4 sessions=$5 profiles=$6 pn=$7 tn=$8
	local dsh_ver tui_ver when tui_present pj

	when=$(date -u +%Y-%m-%dT%H:%M:%SZ)
	dsh_ver=$(command dsh --version 2>/dev/null | head -1)
	[[ -z $dsh_ver ]] && dsh_ver='unknown'

	tui_ver='none'
	for pj in "$dsh"/profiles/*/node_modules/@deepseek-harness-tui/dsh-tui/package.json(N); do
		tui_ver=$(grep -o '"version"[[:space:]]*:[[:space:]]*"[^"]*"' "$pj" 2>/dev/null \
			| head -1 | sed 's/.*"\([^"]*\)"$/\1/')
		break
	done
	[[ -z $tui_ver ]] && tui_ver='unknown'

	tui_present=absent
	[[ -d $tui ]] && tui_present=present

	{
		print "format: dsh-backup/1"
		print "created: $when"
		print "host: $(hostname 2>/dev/null)"
		print "user: ${USER:-unknown}"
		print "dsh: $dsh_ver"
		print "dsh-tui: $tui_ver"
		print "profiles: $profiles"
		print "profile-files: $pn"
		print "tui-state-files: $tn"
		print "tui-dir: $tui_present"
		print "sessions: $(( sessions ? 1 : 0 ))"
		print "secrets: $(( secrets ? 1 : 0 ))"
	} > "$root/manifest.txt" || return 1

	# контрольные суммы: без сессий (гигабайты) и без самого манифеста
	(
		cd "$root" || return 1
		find . -type f ! -name manifest.txt ! -name checksums.txt ! -path './sessions/*' -print0 \
			| xargs -0 shasum -a 256 > checksums.txt 2>/dev/null
	) || return 1

	return 0
}

# ─────────────────────────────────────────────────────────────────────────────

_dsh_backup_load() {
	local dsh=$1 tui=$2 target=$3 dry=$4 secrets=$5 force=$6 sessions=$7
	local root='' name f src out p safety s sn n skip extra
	local -a found restored to_install

	# ── 1. найти каталог бэкапа ──────────────────────────────────────────
	if [[ -f "$target/manifest.txt" ]]; then
		root=$target
	elif [[ -d $target ]]; then
		found=("$target"/dsh-backup-*(N/))
		if (( ${#found} == 1 )); then
			root=$found[1]
		elif (( ${#found} > 1 )); then
			print -u2 "dsh_backup: в $target несколько бэкапов:"
			for p in "${found[@]}"; do
				print -u2 "  ${p:t}"
			done
			print -u2 "укажи конкретный каталог (тот, где лежит manifest.txt)"
			return 1
		fi
	fi

	if [[ -z $root ]]; then
		print -u2 "dsh_backup: бэкап не найден: $target"
		print -u2 "ожидался каталог с manifest.txt или <путь>/dsh-backup-*"
		return 1
	fi
	if [[ ! -d "$root/profiles" ]]; then
		print -u2 "dsh_backup: в бэкапе нет каталога profiles/ — это не бэкап dsh_backup"
		return 1
	fi

	print "бэкап: $root"
	[[ -f "$root/manifest.txt" ]] && sed 's/^/  /' "$root/manifest.txt"

	# ── 2. контрольные суммы ─────────────────────────────────────────────
	if [[ -f "$root/checksums.txt" ]] && (( force == 0 )); then
		local bad=0 sum file cur
		while read -r sum file; do
			[[ -n $file ]] || continue
			cur=$(shasum -a 256 "$root/$file" 2>/dev/null | awk '{print $1}')
			if [[ $cur != $sum ]]; then
				print -u2 "  ✗ контрольная сумма: $file"
				bad=1
			fi
		done < "$root/checksums.txt"
		if (( bad )); then
			print -u2 "dsh_backup: бэкап повреждён. Если правил файлы руками — повтори с -f"
			return 1
		fi
		print "контрольные суммы: ок"
	fi

	# ── 3. страховочная копия текущего состояния ─────────────────────────
	safety="$dsh/.dsh-backup-pre-restore-$(date +%Y%m%d-%H%M%S)"
	if (( dry )); then
		print "[dry-run] страховка была бы здесь: $safety"
	else
		if ! mkdir -p "$safety/profiles" 2>/dev/null; then
			print -u2 "dsh_backup: не удалось создать страховочную копию: $safety"
			print -u2 "dsh_backup: отказываюсь разгружать без страховки"
			return 1
		fi
		for s in "$dsh"/profiles/*(N/); do
			sn=${s:t}
			mkdir -p "$safety/profiles/$sn" 2>/dev/null
			for f in package.json cordis.patch.yml cordis.yml pnpm-lock.yaml pnpm-workspace.yaml; do
				[[ -f "$s/$f" ]] && cp -p "$s/$f" "$safety/profiles/$sn/$f" 2>/dev/null
			done
		done
		if [[ -d $tui ]]; then
			mkdir -p "$safety/tui-state" 2>/dev/null
			for f in settings.json theme.json lang.json permission.json history.jsonl \
				model-recents.json onboarding.json migrations.json resume.txt home.json \
				trajectory.json usage.json session-pins.json extension-grants.json model.json effort.json; do
				[[ -f "$tui/$f" ]] && cp -p "$tui/$f" "$safety/tui-state/$f" 2>/dev/null
			done
		fi
		print "страховка текущего состояния: $safety"
	fi

	# ── 4. профили ───────────────────────────────────────────────────────
	for src in "$root"/profiles/*(N/); do
		name=${src:t}
		out="$dsh/profiles/$name"
		if [[ -d $out ]]; then
			print "профиль $name: обновляю"
		else
			print "профиль $name: создаю"
			(( dry )) || mkdir -p "$out"
		fi
		n=0
		for f in "$src"/*(.N); do
			_dsh_backup_copy "$f" "$out/${f:t}" "$dry" || continue
			(( ++n ))
		done
		restored+=("$name")
		if (( n )); then
			print "  файлов: $n"
		fi
		[[ -f "$out/package.json" ]] && to_install+=("$name")
	done

	# ── 5. состояние dsh-TUI ─────────────────────────────────────────────
	if [[ -d "$root/tui-state" ]]; then
		(( dry )) || mkdir -p "$tui"
		n=0
		skip=0
		for f in "$root/tui-state"/*(.N); do
			case "${f:t}" in
				session-index.json|session-mounts.json|last-run.json|last-used.json|agent-view-sessions.json|effect-ledger.jsonl|restart.log)
					(( ++skip ))
					continue
					;;
			esac
			_dsh_backup_copy "$f" "$tui/${f:t}" "$dry" || continue
			(( ++n ))
		done
		extra=''
		if (( skip )); then
			extra=", пропущено служебных — $skip"
		fi
		print "dsh-TUI ($tui): восстановлено файлов — $n$extra"
	else
		print "dsh-TUI: в бэкапе нет tui-state — пропускаю"
	fi

	# ── 6. история диалогов (merge, без затирания) ───────────────────────
	if [[ -d "$root/sessions" ]]; then
		if (( sessions )); then
			local before=0 after=0 added=0
			(( dry )) || mkdir -p "$dsh/sessions"
			before=$(find "$dsh/sessions" -name 'session.v4.jsonl.zstd' 2>/dev/null | wc -l | tr -d ' ')
			_dsh_backup_copy_tree_merge "$root/sessions" "$dsh/sessions" "$dry"
			after=$(find "$dsh/sessions" -name 'session.v4.jsonl.zstd' 2>/dev/null | wc -l | tr -d ' ')
			added=$(( ${after:-0} - ${before:-0} ))
			(( dry )) || print "сессии: добавлено ${added}, было ${before:-0} (существующие не тронуты)"
		else
			print "сессии: в бэкапе есть история — чтобы восстановить, повтори с --with-sessions"
		fi
	fi

	# ── 7. домашний слой и секреты ───────────────────────────────────────
	if [[ -d "$root/home" ]]; then
		for f in "$root/home"/*(.N); do
			_dsh_backup_copy "$f" "$dsh/${f:t}" "$dry" || continue
		done
		print "домашний слой DSH: восстановлен"
	fi

	if [[ -f "$root/credentials.yaml" ]]; then
		if (( secrets )); then
			if _dsh_backup_copy "$root/credentials.yaml" "$dsh/.credentials.yaml" "$dry"; then
				(( dry )) || chmod 600 "$dsh/.credentials.yaml" 2>/dev/null
				print "секреты: .credentials.yaml восстановлен (режим 600)"
			fi
		else
			print "секреты: в бэкапе есть ключи — чтобы восстановить, повтори с -s"
		fi
	fi

	# ── 8. что делать дальше ─────────────────────────────────────────────
	print ""
	if (( dry )); then
		print "[dry-run] готово, ничего не записано"
		return 0
	fi

	print "готово. Профили: ${(j:, :)restored}"
	if (( ${#to_install} )); then
		print "плагины в бэкап не входят — доустанови их:"
		for p in "${to_install[@]}"; do
			print "  dsh plugin --profile $p install"
		done
	fi
	print "скиллы (~/.dsh/skills) в бэкап не входят — восстанови их отдельно:"
	print "  rsync -a <источник>/<скилл>/ ~/.dsh/skills/<скилл>/"
	print "  или dsh plugin --profile <имя> install (для скиллов из плагинов)"
	print "перезапусти TUI: dsh tui   (страховка: $safety)"
	return 0
}

# ─────────────────────────────────────────────────────────────────────────────

_dsh_backup_copy() {
	local src=$1 dst=$2 dry=$3
	if (( dry )); then
		print "  [dry-run] ${src} -> ${dst}"
		return 0
	fi
	if ! cp -p "$src" "$dst" 2>/dev/null; then
		print -u2 "  ✗ не скопировано: $src -> $dst"
		return 1
	fi
	return 0
}

_dsh_backup_copy_tree() {
	local src=$1 dst=$2 dry=$3
	if (( dry )); then
		print "  [dry-run] дерево ${src}/ -> ${dst}/"
		return 0
	fi
	mkdir -p "$dst" 2>/dev/null || return 1
	cp -R "$src/." "$dst/" 2>/dev/null || return 1
	return 0
}

_dsh_backup_copy_tree_merge() {
	local src=$1 dst=$2 dry=$3
	if (( dry )); then
		print "  [dry-run] дерево (merge) ${src}/ -> ${dst}/"
		return 0
	fi
	mkdir -p "$dst" 2>/dev/null || return 1
	# BSD cp -n возвращает 1, когда пропускает существующие файлы — это норма для merge
	cp -Rn "$src/." "$dst/" 2>/dev/null
	return 0
}
