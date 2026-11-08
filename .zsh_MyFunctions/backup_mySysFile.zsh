backup_mySysFile() {
	if [[ "$1" == "-h" || "$1" == "--help" ]]; then
		cat <<EOF
backup_mySysFile — обновить бэкапа

Доступные компоненты:
  all           - все компоненты
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
  backup_mySysFile zsh git or backup_mySysFile all
EOF
		return 0
	fi

	local dest="~/Documents/ForSys/Backup"
	dest=${~dest}
	mkdir -p "$dest"

	typeset -A items
	items=(
		zsh "~/.zshrc:$dest/.zshrc"
		zshf "~/.zsh_MyFunctions/:$dest/.zsh_MyFunctions"
		neovide "~/.config/neovide/config.toml:$dest/.config/neovide/config.toml"
		git "~/.gitconfig:$dest/.gitconfig"
		omz "~/.oh-my-zsh/custom/:$dest/.oh-my-zsh/custom"
		btop "~/.config/btop/btop.conf:$dest/.config/btop/btop.conf"
		kitty "~/.config/kitty/:$dest/.config/kitty"
		yazi "~/.config/yazi/:$dest/.config/yazi"
		treemd "~/.config/treemd/config.toml:$dest/.config/treemd/config.toml"
	)

	if [[ $# -eq 0 ]]; then
		echo "Использование: backup_mySysFile [zsh|nvim|git|omz|btop|kitty|yazi|treemd|all]"
		return 1
	fi

	for arg in "$@"; do
		if [[ $arg = "all" ]]; then
			for key in "${(k)items[@]}"; do
				_backup_item "$key" "$dest" "$items[$key]"
			done
			return
		fi

		if [[ -z "${items[$arg]+x}" ]]; then
			echo "Неизвестный компонент: $arg"
			continue
		fi
		_backup_item "$arg" "$dest" "${items[$arg]}"
	done
}

function _backup_item() {
	local key=$1 dest=$2 spec=$3
	local src dst

	if [[ "$spec" = *":"* ]]; then
		src=${spec%:*}
		dst=${spec#*:}
	else
		src=$spec
		dst=$dest
	fi

	src=${~src}
	dst=${~dst}

	if [[ ! -e "$src" && ! -L "$src" ]]; then
		echo "Пропущено (не найдено): $src"
		return
	fi

	local src_display="$src"

	if [[ -d "$src" ]]; then
		src="$src/"
	fi

	mkdir -p "${dst%/*}" 2>/dev/null
	cp -Rf "$src" "$dst"

	if [[ -d "$dst" && -f "$src_display" ]]; then
		echo "Скопировано: $src_display -> $dst/${src_display:t}"
	else
		echo "Скопировано: $src_display -> $dst"
	fi
}
