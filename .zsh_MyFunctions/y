y() {
  if [[ "$1" == "-h" || "$1" == "--help" ]]; then
    cat <<EOF
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

	local tmp="$(mktemp -t "yazi-cwd.XXXXXX")"
	yazi "$@" --cwd-file="$tmp"
	local cwd="$(command cat -- "$tmp")"
	command rm -f -- "$tmp"
	[ -n "$cwd" ] && [ "$cwd" != "$PWD" ] && builtin cd -- "$cwd"
}

