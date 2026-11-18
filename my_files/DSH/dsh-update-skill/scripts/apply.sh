#!/usr/bin/env bash
# apply.sh — выполнить обновление по выбранному плану.
#
#   apply.sh --official [--yes]                     # как /update, но без перезапуска TUI
#   apply.sh [--tui VER] [--core VER] [--plugin P:NAME@VER]... [--yes]
#   apply.sh ... --dry-run | --snapshot DIR | --no-verify
#
# Без --yes ничего не делает: только печатает план команд.
# Перед установкой всегда создаётся и проверяется снимок; при провале снимка
# обновление не начинается. По завершении запускается verify.sh.
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

usage() { sed -n '2,12p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; }

TUI_VER=''; CORE_VER=''; OFFICIAL=0; YES=0; DRY=0; NO_VERIFY=0; SNAP=''
PLUGINS=()
while [ $# -gt 0 ]; do
  case "$1" in
    --official) OFFICIAL=1; shift ;;
    --tui) TUI_VER="${2:?}"; shift 2 ;;
    --core) CORE_VER="${2:?}"; shift 2 ;;
    --plugin) PLUGINS+=("${2:?--plugin требует profile:name@version}"); shift 2 ;;
    --yes|-y) YES=1; shift ;;
    --dry-run) DRY=1; shift ;;
    --no-verify) NO_VERIFY=1; shift ;;
    --snapshot) SNAP="${2:?}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) die "apply: неизвестный аргумент $1" ;;
  esac
done
[ "$DRY" -eq 1 ] && YES=0

need_base
state_init
METHOD="$(node "$LIB_DIR/collect.mjs" | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{try{process.stdout.write(JSON.parse(s).core.installMethod)}catch{}})')"
METHOD="${METHOD:-unknown}"

tui_profile() {
  local p
  for p in $(profiles); do
    if node -e 'const j=require(process.argv[1]);const d={...j.dependencies,...j.devDependencies};process.exit(d["@deepseek-harness-tui/dsh-tui"]?0:1)' \
      "$(profile_dir "$p")/package.json" 2>/dev/null; then
      printf '%s' "$p"
      return 0
    fi
  done
  return 1
}

TP="$(tui_profile || true)"
if [ -n "$TUI_VER" ] && [ -z "$TP" ]; then die "в профилях нет @deepseek-harness-tui/dsh-tui"; fi
if [ "$OFFICIAL" -eq 1 ] && [ -z "$TP" ]; then die "--official: TUI не установлен ни в одном профиле"; fi

plan=()
if [ "$OFFICIAL" -eq 1 ]; then
  plan+=("official|$TP")
else
  [ -n "$TUI_VER" ] && plan+=("tui|$TP|$TUI_VER")
  [ -n "$CORE_VER" ] && plan+=("core||$CORE_VER")
  if [ ${#PLUGINS[@]} -gt 0 ]; then
    for item in "${PLUGINS[@]}"; do plan+=("plugin|$item"); done
  fi
fi

if [ ${#plan[@]} -eq 0 ]; then
  usage
  die "нечего делать: укажите --official, --tui, --core или --plugin"
fi

log "План:"
for step in "${plan[@]}"; do
  IFS='|' read -r kind a b <<<"$step"
  case "$kind" in
    official) log "  1) официальный апдейт TUI+ядра: dsh-tui update (без рестарта)" ;;
    tui) log "  • TUI → $b:  dsh plugin --profile $a add @deepseek-harness-tui/dsh-tui@$b" ;;
    core) log "  • ядро → $b: установка способом $METHOD (npm-global → npm i -g)" ;;
    plugin) log "  • плагин:    dsh plugin --profile ${a%%:*} add ${a#*:}" ;;
  esac
done

if [ "$YES" -ne 1 ]; then
  log ""
  log "Это dry-run. Для выполнения повторите с --yes."
  exit 0
fi

# ── снимок ──────────────────────────────────────────────────────────────
if [ -n "$SNAP" ]; then
  snapshot_dir="$SNAP"
  [ -d "$snapshot_dir" ] || die "снимок не найден: $snapshot_dir"
  info "проверяю указанный снимок…"
  "$LIB_DIR/snapshot.sh" verify "$snapshot_dir" || die "снимок повреждён — обновление отменено"
else
  info "создаю снимок перед обновлением…"
  snapshot_dir="$("$LIB_DIR/snapshot.sh" create --label "pre-apply-$(date +%H%M%S)" 2>&1 | awk '/снимок: /{print $NF}' | head -1)"
  [ -n "$snapshot_dir" ] && [ -d "$snapshot_dir" ] || die "не удалось создать снимок — обновление отменено"
  "$LIB_DIR/snapshot.sh" verify "$snapshot_dir" || die "снимок не прошёл проверку — обновление отменено"
fi
ok "снимок: $snapshot_dir"

rollback_hint() {
  log ""
  warn "откат: $SKILL_DIR/scripts/rollback.sh --snapshot \"$snapshot_dir\" --yes"
  warn "или вручную: $SKILL_DIR/scripts/rollback.sh --snapshot \"$snapshot_dir\""
}

apply_official() {
  local profile=$1 bin
  bin="$(profile_dir "$profile")/node_modules/@deepseek-harness-tui/dsh-tui/bin/dsh-tui.js"
  [ -f "$bin" ] || { err "не найден $bin"; return 1; }
  info "запускаю официальный апдейтер (TUI → ядро → лаунчер), без рестарта…"
  node "$bin" update
  return $?
}

apply_tui() {
  local profile=$1 version=$2 before
  before="$(tui_version "$profile")"
  info "TUI $before → $version"
  dsh plugin --profile "$profile" add "@deepseek-harness-tui/dsh-tui@$version" || return 1
  local now
  now="$(tui_version "$profile")"
  if [ "$now" != "$version" ]; then
    err "TUI не обновился: установлено ${now:-?}, ожидалось $version"
    return 1
  fi
  ok "TUI $now"
  return 0
}

apply_core() {
  local version=$1
  case "$METHOD" in
    npm-global) info "npm i -g @deepseek-ai/dsh@$version"; npm i -g "@deepseek-ai/dsh@$version" || return 1 ;;
    pnpm-global) info "pnpm add -g @deepseek-ai/dsh@$version"; pnpm add -g "@deepseek-ai/dsh@$version" || return 1 ;;
    *) err "способ установки ядра не распознан — обновите вручную"; return 1 ;;
  esac
  local now
  now="$(core_version)"
  if [ "$now" != "$version" ]; then
    err "ядро не обновилось: dsh --version = ${now:-?}, ожидалось $version"
    return 1
  fi
  ok "ядро $now"
  return 0
}

apply_plugin() {
  local spec=$1 profile=${1%%:*} pkg=${1#*:}
  info "плагин $pkg → профиль $profile"
  dsh plugin --profile "$profile" add "$pkg" || return 1
  ok "плагин $pkg установлен в $profile"
  return 0
}

failed=0
for step in "${plan[@]}"; do
  IFS='|' read -r kind a b <<<"$step"
  case "$kind" in
    official) apply_official "$a" || failed=1 ;;
    tui) apply_tui "$a" "$b" || failed=1 ;;
    core) apply_core "$b" || failed=1 ;;
    plugin) apply_plugin "$a" || failed=1 ;;
  esac
  [ "$failed" -eq 1 ] && break
done

if [ "$failed" -eq 1 ]; then
  err "шаг не выполнен — остальные пропущены."
  rollback_hint
  exit 1
fi

ok "установка завершена."
log ""
warn "Текущая сессия работает на старом коде: перезапустите TUI (или web) вручную, я этого не делаю."

if [ "$NO_VERIFY" -ne 1 ]; then
  log ""
  info "проверка после обновления…"
  "$LIB_DIR/verify.sh" || warn "проверка нашла проблемы — см. отчёт выше"
fi

log ""
log "Снимок для отката: $snapshot_dir"
prune_snapshots "$KEEP_SNAPSHOTS" 0 >/dev/null 2>&1
