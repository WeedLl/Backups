#!/usr/bin/env bash
# check.sh — отчёт «что можно обновить и чем это грозит». Ничего не меняет.
#
#   check.sh [--json] [--offline]
#
# --json     машинный отчёт (для агента)
# --offline  не ходить в реестр npm (только локальное состояние)
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

have node || die "нужен node в PATH"
have dsh || die "не найден dsh в PATH"
exec node "$LIB_DIR/check.mjs" "$@"
