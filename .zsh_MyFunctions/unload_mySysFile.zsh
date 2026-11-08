unload_mySysFile() {
	if [[ "$1" == "-h" || "$1" == "--help" ]]; then
		cat <<EOF
unload_mySysFile — восстановить конфиги из бэкапа

Доступные компоненты:
  zsh           - .zshrc
  zshf          - .zsh_MyFunctions/
  omz           - .oh-my-zsh/custom/
  nvim          - .config/nvim/
  git           - .gitconfig
  btop          - .config/btop/btop.conf
  kitty         - .config/kitty/
  yazi          - .config/yazi/
  treemd        - .config/treemd/config.toml

Пример:
  unload_mySysFile zsh git или unload_mySysFile all
EOF
		return 0
	fi

	local src="~/Documents/ForSys/Backup"
	src=${~src}

	if [[ ! -d "$src" ]]; then
		echo "Папка бэкапа не найдена: $src"
		return 1
	fi
	typeset -A items
	items=(
		zsh "$src/.zshrc:~/.zshrc"
		zshf "$src/.zsh_MyFunctions/:~/.zsh_MyFunctions"
		nvim "$src/.config/nvim/:~/.config/nvim"
		git "$src/.gitconfig:~/.gitconfig"
		omz "$src/.oh-my-zsh/custom/:~/.oh-my-zsh/custom"
		btop "$src/.config/btop/btop.conf:~/.config/btop/btop.conf"
		kitty "$src/.config/kitty/:~/.config/kitty"
		yazi "$src/.config/yazi/:~/.config/yazi"
		treemd "$src/.config/treemd/config.toml"
	)

	if [[ $# -eq 0 ]]; then
		echo "Использование: unload_mySysFile [zsh|nvim|git|omz|btop|kitty|yazi|treemd|all]"
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
