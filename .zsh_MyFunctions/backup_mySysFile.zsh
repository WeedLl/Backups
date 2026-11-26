backup_mySysFile() {
	if [[ "$1" == "-h" || "$1" == "--help" ]]; then
		command cat <<EOF
backup_mySysFile — обновить бэкап

Доступные компоненты:
  all           - все компоненты
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
  niri          - .config/niri/ (в cfg/display.kdl — машинные output/mode/scale)
  noctalia      - .config/noctalia/ (все *.toml сливаются по алфавиту; full_config перекрывает config.toml)
  noctalia-state - .local/state/noctalia/settings.toml (настройки GUI, перекрывают .config/noctalia)
  mimeapps      - .config/mimeapps.list (ассоциации приложений)
  xdg           - .config/user-dirs.dirs
  xdg-locale    - .config/user-dirs.locale

Машинно-зависимое: niri (cfg/display.kdl: имя выхода, режим, scale) и
noctalia-state (бар, размещение панелей по мониторам). На другой машине эти
строки ожидаемо различаются — восстанавливать осознанно, а не заливать вслепую.

Пример:
  backup_mySysFile zsh bash or backup_mySysFile all
EOF
		return 0
	fi

	local dest="~/Documents/ForSys/Backup"
	dest=${~dest}
	mkdir -p "$dest"

	typeset -A items
	items=(
		bash "~/.bash_profile:$dest/.bash_profile"
		zsh "~/.zshrc:$dest/.zshrc"
		zshf "~/.zsh_MyFunctions/:$dest/.zsh_MyFunctions"
		vim "~/.vimrc:$dest/.vimrc"
		nvim "~/.config/nvim/:$dest/.config/nvim"
		neovide "~/.config/neovide/config.toml:$dest/.config/neovide/config.toml"
		ideavim "~/.ideavimrc:$dest/.ideavimrc"
		git "~/.gitconfig:$dest/.gitconfig"
		lazygit "~/.config/lazygit/config.yml:$dest/.config/lazygit/config.yml"
		psql "~/.config/psql/.psqlrc:$dest/.config/psql/.psqlrc"
		pgcli "~/.config/pgcli/config:$dest/.config/pgcli/config"
		mycli "~/.config/mycli/.myclirc:$dest/.config/mycli/.myclirc"
		ultisnips "~/.vim/UltiSnips/:$dest/.vim/UltiSnips"
		omz "~/.oh-my-zsh/custom/:$dest/.oh-my-zsh/custom"
		btop "~/.config/btop/btop.conf:$dest/.config/btop/btop.conf"
		kitty "~/.config/kitty/:$dest/.config/kitty"
		alacritty "~/.config/alacritty/:$dest/.config/alacritty"
		yazi "~/.config/yazi/:$dest/.config/yazi"
		tmux "~/.config/tmux/tmux.conf:$dest/.config/tmux/tmux.conf"
		treemd "~/.config/treemd/config.toml:$dest/.config/treemd/config.toml"
		niri "~/.config/niri/:$dest/.config/niri"
		noctalia "~/.config/noctalia/:$dest/.config/noctalia"
		noctalia-state "~/.local/state/noctalia/settings.toml:$dest/.local/state/noctalia/settings.toml"
		mimeapps "~/.config/mimeapps.list:$dest/.config/mimeapps.list"
		xdg "~/.config/user-dirs.dirs:$dest/.config/user-dirs.dirs"
		xdg-locale "~/.config/user-dirs.locale:$dest/.config/user-dirs.locale"
	)

	if [[ $# -eq 0 ]]; then
		echo "Использование: backup_mySysFile [bash|zsh|vim|nvim|ideavim|psql|git|pgcli|ultisnips|omz|btop|kitty|alacritty|yazi|tmux|treemd|niri|noctalia|noctalia-state|mimeapps|xdg|xdg-locale|all]"
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

	if [[ -d "$src_display" ]]; then
		mkdir -p "$dst" 2>/dev/null || {
			echo "Не удалось создать каталог: $dst"
			return 1
		}
		if ! cp -Rf "$src_display/." "$dst/" 2>/dev/null; then
			echo "Ошибка копирования: $src_display -> $dst"
			return 1
		fi
		echo "Скопировано: $src_display -> $dst"
	else
		mkdir -p "${dst%/*}" 2>/dev/null
		if ! cp -f "$src_display" "$dst" 2>/dev/null; then
			echo "Ошибка копирования: $src_display -> $dst"
			return 1
		fi
		echo "Скопировано: $src_display -> $dst"
	fi
}
