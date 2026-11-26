#!/usr/bin/env bash
# rollback.sh — откат конфигурации DSH из снимка.
#
#   rollback.sh [--snapshot DIR] [--yes] [--dry-run] [--reinstall] [--core]
#
# Возвращает файлы профилей, домашний слой, скиллы и состояние TUI.
# --reinstall  после откaта файлов прогоняет `dsh plugin install` в профилях
#              (возвращает node_modules к версиям из восстановленного lockfile).
# --core       дополнительно откатывает глобальное ядро (npm/pnpm).
# Без --yes показывает, что будет восстановлено, и выходит.
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

usage() { sed -n '2,10p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; }

SNAP=''; YES=0; DRY=0; REINSTALL=0; CORE=0
while [ $# -gt 0 ]; do
  case "$1" in
    --snapshot) SNAP="${2:?}"; shift 2 ;;
    --yes|-y) YES=1; shift ;;
    --dry-run) DRY=1; shift ;;
    --reinstall) REINSTALL=1; shift ;;
    --core) CORE=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) die "rollback: неизвестный аргумент $1" ;;
  esac
done
[ "$DRY" -eq 1 ] && YES=0

need_base
state_init
[ -z "$SNAP" ] && SNAP="$(latest_snapshot)"
[ -n "$SNAP" ] && [ -d "$SNAP" ] || die "снимок не найден (укажите --snapshot DIR)"
[ -f "$SNAP/manifest.json" ] || die "в снимке нет manifest.json"

info "снимок: $SNAP"
"$LIB_DIR/snapshot.sh" verify "$SNAP" || die "снимок повреждён — откат невозможен"

target_core="$(json_field "$SNAP/manifest.json" core.version)"
current_core="$(core_version)"
log "ядро в снимке: ${target_core:-?}, сейчас: ${current_core:-?}"

list_files() { find "$1" -type f 2>/dev/null | sed "s#^$1/##" | sort; }

count=0
for area in profiles home skills tui-state; do
  src="$SNAP/files/$area"
  [ -d "$src" ] || continue
  n=$(find "$src" -type f 2>/dev/null | wc -l | tr -d ' ')
  count=$((count + n))
done
log "файлов к восстановлению: $count"

if [ "$YES" -ne 1 ]; then
  log ""
  log "Будет восстановлено (dry-run):"
  for area in profiles home skills tui-state; do
    src="$SNAP/files/$area"
    [ -d "$src" ] || continue
    list_files "$src" | sed "s#^#  $area/#"
  done
  [ "$REINSTALL" -eq 1 ] && log "  + dsh plugin install во всех профилях"
  [ "$CORE" -eq 1 ] && log "  + ядро → ${target_core:-?}"
  log ""
  log "Текущие файлы будут перезаписаны; перед этим создаётся снимок pre-rollback."
  log "Для выполнения повторите с --yes."
  exit 0
fi

info "создаю страховочный снимок текущего состояния…"
"$LIB_DIR/snapshot.sh" create --label "pre-rollback-$(date +%H%M%S)" >/dev/null 2>&1 || warn "страховочный снимок не создан (продолжаю)"

restore_tree() {
  local src=$1 dst=$2 rel
  [ -d "$src" ] || return 0
  mkdir -p "$dst" || return 1
  ( cd "$src" && find . -type f -print0 ) | while IFS= read -r -d '' rel; do
    mkdir -p "$dst/$(dirname "$rel")" 2>/dev/null
    cp -p "$src/$rel" "$dst/$rel" || warn "не удалось восстановить $rel"
  done
}

info "восстанавливаю файлы профилей…"
restore_tree "$SNAP/files/profiles" "$DSH_HOME/profiles"
info "восстанавливаю домашний слой…"
restore_tree "$SNAP/files/home" "$DSH_HOME"
info "восстанавливаю скиллы…"
restore_tree "$SNAP/files/skills" "$DSH_HOME/skills"
info "восстанавливаю состояние TUI…"
restore_tree "$SNAP/files/tui-state" "$TUI_HOME"
ok "файлы восстановлены"

if [ "$REINSTALL" -eq 1 ]; then
  info "переустанавливаю зависимости профилей по восстановленным lockfile…"
  for p in $(profiles); do
    if [ -f "$DSH_HOME/profiles/$p/pnpm-lock.yaml" ]; then
      log "  • $p"
      dsh plugin --profile "$p" install || warn "профиль $p: install завершился ошибкой"
    fi
  done
fi

if [ "$CORE" -eq 1 ] && [ -n "$target_core" ] && [ "$target_core" != "$current_core" ]; then
  method="$(node "$LIB_DIR/collect.mjs" | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{try{process.stdout.write(JSON.parse(s).core.installMethod)}catch{}})')"
  case "$method" in
    npm-global) info "npm i -g @deepseek-ai/dsh@$target_core"; npm i -g "@deepseek-ai/dsh@$target_core" || warn "ядро не откатилось" ;;
    pnpm-global) info "pnpm add -g @deepseek-ai/dsh@$target_core"; pnpm add -g "@deepseek-ai/dsh@$target_core" || warn "ядро не откатилось" ;;
    *) warn "способ установки ядра не распознан — откатите вручную до $target_core" ;;
  esac
fi

info "обновляю журнал версий…"
"$LIB_DIR/doc.sh" write --kind rollback --snapshot "$SNAP" || warn "журнал версий не обновлён (см. doc.sh выше)"

log ""
warn "если TUI сейчас запущен, он может перезаписать восстановленное состояние — закройте его перед откатом"
warn "перезапустите TUI/web, чтобы сессия поднялась на восстановленных файлах"
log "проверка: $SKILL_DIR/scripts/verify.sh"
