#!/usr/bin/env bash
# selftest.sh — проверка, что скрипты скилла ещё соответствуют этой версии DSH.
#
#   selftest.sh
#
# Скилл опирается на конкретные команды и пути. Если DSH их поменял, скрипты
# устарели: этот тест скажет об этом прямо, вместо того чтобы агент гадал,
# почему проверка «не видит» профиль.
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

fails=0
warns=0
ok()   { printf '  ✓ %s\n' "$*"; }
bad()  { printf '  ✗ %s\n' "$*"; fails=$((fails + 1)); }
soft() { printf '  ! %s\n' "$*"; warns=$((warns + 1)); }

log "Проверка допущений скилла (DSH $(core_version 2>/dev/null || printf '?'))"
log ""

command -v node >/dev/null 2>&1 && ok "node $(node --version)" || bad "нет node"
node -e 'process.exit(Number(process.versions.node.split(".")[0]) >= 18 ? 0 : 1)' 2>/dev/null \
  && ok "node ≥ 18" || bad "нужен node ≥ 18"

command -v dsh >/dev/null 2>&1 && ok "dsh в PATH: $(command -v dsh)" || bad "нет dsh в PATH"
command -v npm >/dev/null 2>&1 && ok "npm $(npm --version 2>/dev/null)" || soft "нет npm — обновление ядра будет только вручную"
command -v pnpm >/dev/null 2>&1 && ok "pnpm $(pnpm --version 2>/dev/null)" || soft "нет pnpm — плагины профилей не обновить"

if dsh --help 2>&1 | grep -q -- "--dump-config"; then
  ok "dsh поддерживает --dump-config"
else
  bad "dsh больше не поддерживает --dump-config — проверка конфига устарела"
fi
if dsh --help 2>&1 | grep -q -- "--profile"; then
  ok "dsh поддерживает --profile"
else
  bad "dsh больше не поддерживает --profile"
fi
if dsh plugin --help 2>&1 | grep -q -- "--profile"; then
  ok "dsh plugin поддерживает --profile"
else
  bad "dsh plugin изменился — установка плагинов устарела"
fi

[ -d "$DSH_HOME/profiles" ] && ok "профили: $DSH_HOME/profiles" || bad "нет каталога профилей $DSH_HOME/profiles"
[ -d "$TUI_HOME" ] && ok "состояние TUI: $TUI_HOME" || soft "нет $TUI_HOME — проверка состояния TUI пропускается"

for f in util.mjs collect.mjs check.mjs checks.mjs compare.mjs doc.mjs; do
  [ -f "$LIB_DIR/$f" ] && ok "есть scripts/$f" || bad "нет scripts/$f"
done
[ -x "$LIB_DIR/doc.sh" ] && ok "есть scripts/doc.sh" || bad "нет исполняемого scripts/doc.sh"

if have sha256sum; then
  ok "sha256sum есть"
else
  bad "нет sha256sum — снимок не проверить"
fi

if have script; then
  ok "script есть — smoke TUI возможен"
else
  soft "нет script — smoke TUI будет пропущен"
fi

if node "$UTIL" cmp 1.0.0 1.0.1 >/dev/null 2>&1; then
  ok "util.mjs работает"
else
  bad "util.mjs не запускается"
fi

if node "$LIB_DIR/collect.mjs" >/dev/null 2>&1; then
  ok "collect.mjs собирает состояние"
else
  bad "collect.mjs падает — скилл не сможет прочитать профили"
fi

# Профиль без package.json или с пустым bundles — сигнал смены формата.
for p in $(profiles); do
  b="$(pkg_bundles "$p")"
  case "$b" in
    []|'') soft "профиль $p: пустой список bundles — формат мог измениться" ;;
    *) ok "профиль $p: bundles читаются" ;;
  esac
done

if [ -f "$BACKUP_SCRIPT" ]; then
  ok "dsh_backup найден: $BACKUP_SCRIPT"
else
  soft "dsh_backup не найден ($BACKUP_SCRIPT) — проверка покрытия будет пропущена"
fi

log ""
if [ "$fails" -gt 0 ]; then
  log "ИТОГ: $fails критичных расхождений, $warns замечаний."
  log "Скрипты скилла устарели относительно этой версии DSH. Не импровизируйте"
  log "разрушительные команды: обновите скилл (SKILL.md → раздел «Если скрипты устарели»)."
  exit 1
fi
log "ИТОГ: допущения в порядке ($warns замечаний)."
exit 0
