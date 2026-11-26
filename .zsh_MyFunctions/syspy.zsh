# syspy — запуск системных Python-утилит системным интерпретатором.
#
# Зачем: в PATH первым идёт ~/.global_venv/bin (Python 3.15 без системных
# site-packages), а скрипты в /usr/bin начинаются с "#!/usr/bin/env python3"
# и рассчитывают на /usr/bin/python3 (3.14) с его пакетами (gi, dbus и т.п.).
# Без обёртки такие утилиты падают с ModuleNotFoundError, хотя пакет стоит.
#
# Использование:
#   syspy <команда> [аргументы...]    # системный скрипт по имени из PATH
#   syspy <путь/к/скрипту.py> [...]   # конкретный файл
#   syspy -m <модуль> [аргументы...]  # модуль системным python
#   syspy                             # просто системный REPL
#
# Ограничения и подводные камни — в справке (syspy -h).

syspy() {
	if [[ "$1" == "-h" || "$1" == "--help" ]]; then
		command cat <<'EOF'
syspy — запустить системную Python-утилиту системным интерпретатором

Зачем:
  В PATH первым стоит venv (~/.global_venv, Python 3.15), а системные скрипты
  в /usr/bin используют "#!/usr/bin/env python3" и рассчитывают на системный
  Python 3.14 с его site-packages. syspy запускает такой скрипт явно через
  /usr/bin/python3, не меняя ни PATH, ни shebang, ни сам venv.

Когда работает:
  - цель — Python-скрипт (обычно из /usr/bin), которому нужны системные
    пакеты: gi, dbus, хуки пакетного менеджера и т.п.;
  - нужен именно системный Python, а не venv-овый.

Когда НЕ работает и не подходит:
  - цель — бинарник или shell-скрипт: syspy запустит его питоном и получит
    синтаксическую ошибку;
  - утилите наоборот нужны пакеты из venv (Python 3.15), а не системные;
  - утилита ставится в собственный venv/pipx со своим интерпретатором.

Подводные камни:
  - syspy ничего не «чинит»: обычный python3 остаётся venv-овым, это выбор
    интерпретатора на один запуск;
  - разбор -m работает только первым аргументом;
  - если имя команды совпадает с функцией или алиасом, syspy откажется
    (проверяет, что найден именно файл) — используй полный путь;
  - код возврата целевого скрипта пробрасывается как есть, свои ошибки
    печатаются в stderr с кодами 2 (использование), 126 (не файл),
    127 (команда не найдена);
  - путь к системному питону зашит: /usr/bin/python3;
  - переменные окружения (включая PYTHONPATH) наследуются, поэтому
    PYTHONPATH из venv может помешать — при странностях запускай через
    "env -u PYTHONPATH syspy ...".

Примеры:
  syspy powerprofilesctl get
  syspy powerprofilesctl set balanced
  syspy -m platform
  syspy ./script.py --help
EOF
		return 0
	fi

	emulate -L zsh
	local sys=/usr/bin/python3

	if (( $# == 0 )); then
		"$sys"
		return
	fi

	if [[ "$1" == "-m" ]]; then
		shift
		if (( $# == 0 )); then
			print -u2 "syspy: после -m нужен модуль"
			return 2
		fi
		"$sys" -m "$@"
		return
	fi

	local target=$1 script
	shift

	if [[ -f "$target" ]]; then
		script=$target
	else
		script=$(command -v -- "$target") || {
			print -u2 "syspy: команда не найдена: $target"
			return 127
		}
		if [[ ! -f "$script" ]]; then
			print -u2 "syspy: не файл: $script"
			return 126
		fi
	fi

	"$sys" "$script" "$@"
}
