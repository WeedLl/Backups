unload_mySysFile() {
	if [[ "$1" == "-h" || "$1" == "--help" ]]; then
		command cat <<EOF
unload_mySysFile — восстановить конфиги из бэкапа

Доступные компоненты:
  bash          - .bash_profile
  zsh           - .zshrc
  zshf          - .zsh_MyFunctions/
  omz           - .oh-my-zsh/custom/
  ultisnips     - .vim/UltiSnips/
  vim           - .vimrc
  nvim          - .config/nvim/
  neovide       - .config/neovide/config.toml
  ideavim       - .ideavimrc
  git           - .gitconfig
  lazygit       - .config/lazygit/config.yml
  psql          - .config/psql/.psqlrc
  pgcli         - .config/pgcli/config
  mycli         - .config/mycli/.myclirc
  btop          - .config/btop/btop.conf
  kitty         - .config/kitty/
  alacritty     - .config/alacritty/
  yazi          - .config/yazi/
  tmux          - .config/tmux/tmux.conf
  treemd        - .config/treemd/config.toml
  niri          - .config/niri/
  noctalia      - .config/noctalia/ (config.toml активный; full_config.toml применять вручную)

Пример:
  unload_mySysFile zsh bash или unload_mySysFile all
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
		bash "$src/.bash_profile:~/.bash_profile"
		zsh "$src/.zshrc:~/.zshrc"
		zshf "$src/.zsh_MyFunctions/:~/.zsh_MyFunctions"
		vim "$src/.vimrc:~/.vimrc"
		nvim "$src/.config/nvim/:~/.config/nvim"
		neovide "$src/.config/neovide/config.toml:~/.config/neovide/config.toml"
		ideavim "$src/.ideavimrc:~/.ideavimrc"
		git "$src/.gitconfig:~/.gitconfig"
		lazygit "$src/.config/lazygit/config.yml:~/.config/lazygit/config.yml"
		psql "$src/.config/psql/.psqlrc:~/.config/psql/.psqlrc"
		pgcli "$src/.config/pgcli/config:~/.config/pgcli/config"
		mycli "$src/.config/mycli/.myclirc:~/.config/mycli/.myclirc"
		ultisnips "$src/.vim/UltiSnips/:~/.vim/UltiSnips"
		omz "$src/.oh-my-zsh/custom/:~/.oh-my-zsh/custom"
		btop "$src/.config/btop/btop.conf:~/.config/btop/btop.conf"
		kitty "$src/.config/kitty/:~/.config/kitty"
		alacritty "$src/.config/alacritty/:~/.config/alacritty"
		yazi "$src/.config/yazi/:~/.config/yazi"
		tmux "$src/.config/tmux/tmux.conf:~/.config/tmux/tmux.conf"
		treemd "$src/.config/treemd/config.toml:~/.config/treemd/config.toml"
		niri "$src/.config/niri/:~/.config/niri"
		noctalia "$src/.config/noctalia/:~/.config/noctalia"
	)

	if [[ $# -eq 0 ]]; then
		echo "Использование: unload_mySysFile [bash|zsh|vim|nvim|ideavim|psql|git|pgcli|ultisnips|omz|btop|kitty|alacritty|yazi|tmux|treemd|niri|noctalia|all]"
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

	if [[ -d "$src_display" ]]; then
		mkdir -p "$dst" 2>/dev/null || {
			echo "Не удалось создать каталог: $dst"
			return 1
		}
		if ! cp -Rf "$src_display/." "$dst/" 2>/dev/null; then
			echo "Ошибка восстановления: $src_display -> $dst"
			return 1
		fi
		echo "Восстановлено: $src_display -> $dst"
	else
		mkdir -p "${dst%/*}" 2>/dev/null
		if ! cp -f "$src_display" "$dst" 2>/dev/null; then
			echo "Ошибка восстановления: $src_display -> $dst"
			return 1
		fi
		echo "Восстановлено: $src_display -> $dst"
	fi
}
