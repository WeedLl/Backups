y() {
  if [[ "$1" == "-h" || "$1" == "--help" ]]; then
    command cat <<EOF
y - запуск Yazi с переходом в директорию при выходе

Доступные компоненты:
    y | запустить Yazi в текущей директории
    y <путь> | запустить Yazi  в указанной директории
    y -h, --help | показать эту справку
    yy | просто запустить Yazi

    При выходе из Yazi (q) shell переключится в директорию, в которой вы находились на момент выхода.

EOF
    return 0
  fi

	if ! command -v yazi >/dev/null 2>&1; then
		print -u2 "y: yazi не найден в PATH"
		return 1
	fi

	local tmp cwd
	tmp=$(mktemp "${TMPDIR:-/tmp}/yazi-cwd.XXXXXX") || {
		print -u2 "y: не удалось создать временный файл"
		return 1
	}
	yazi "$@" --cwd-file="$tmp"
	cwd=$(command cat -- "$tmp")
	command rm -f -- "$tmp"
	[[ -n "$cwd" && "$cwd" != "$PWD" ]] && builtin cd -- "$cwd"
}

