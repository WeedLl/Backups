#compdef backup_mySysFile unload_mySysFile diff_mySysFile

_DiffBackupUnload() {
	local cmd=$words[1]

	local -a components=(
		-h
		--Help
		all
		zsh
		zshf
		omz
		nvim
		git
		btop
		kitty
		yazi
		treemd
	)

	local -a diff_components=()
	for c in $components; do
		[[ $c != 'all' ]] && diff_components+=($c)
	done

	case $cmd in
	backup_mySysFile)
		_arguments '*:компонент:_values "компонент" $components[@]'
		;;
	unload_mySysFile)
		_arguments '*:компонент:_values "компонент" $components[@]'
		;;
	diff_mySysFile)
		# compadd -V сохраняет порядок: diff первым, потом остальные
		_arguments \
			'1:выбор:compadd -V items diff $diff_components[@]' \
			'*:компонент:_values "компонент" $diff_components[@]'
		;;
	*)
		return 1
		;;
	esac
}

_DiffBackupUnload
