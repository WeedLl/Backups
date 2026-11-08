#compdef gdbranch

_gdbranch_branches() {
  local -a branches
  branches=(
    ${(f)"$(git branch -a --format='%(refname:short)' 2>/dev/null \
      | grep -vE '^(HEAD|.*/HEAD)$' \
      | sort -u)"}
  )
  _describe -t branches 'branch' branches
}

_gdbranch() {
  _arguments -s \
    '(-h --help)'{-h,--help}'[Показать справку]' \
    '(-f --filter)'{-f,--filter}'[Фильтр по типу изменения]:filter:(A D M R C T U X B)' \
    '1:base branch:_gdbranch_branches' \
    '2:target branch:_gdbranch_branches'
}

_gdbranch "$@"
