#compdef dsh_backup

_dsh_backup() {
	_arguments \
		{-b,--backup}'[сохранить бэкап]:каталог:_files -/' \
		{-u,--unload}'[разгрузить бэкап]:каталог:_files -/' \
		'-n[dry-run: показать план, ничего не писать]' \
		'-s[включить секреты (~/.dsh/.credentials.yaml)]' \
		'-f[не сверять контрольные суммы при разгрузке]' \
		'--with-sessions[вместе с историей диалогов (~/.dsh/sessions)]' \
		'-h[справка]'
}

_dsh_backup "$@"
