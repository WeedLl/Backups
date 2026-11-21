#compdef dsh_backup

_dsh_backup() {
	_arguments \
		{-b,--backup}'[сохранить бэкап]:каталог:_files -/' \
		{-u,--unload}'[разгрузить бэкап]:каталог:_files -/' \
		'-n[dry-run: показать план, ничего не писать]' \
		'-s[включить секреты (~/.dsh/.credentials.yaml)]' \
		'-f[не сверять контрольные суммы при разгрузке]' \
		'-L[не восстанавливать pnpm-lock.yaml]' \
		'--skip-locks[не восстанавливать pnpm-lock.yaml]' \
		'--with-sessions[вместе с историей диалогов (~/.dsh/sessions)]' \
		{-h,--help}'[справка]'
}

_dsh_backup "$@"
