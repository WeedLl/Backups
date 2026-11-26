#!/usr/bin/env bash
# snapshot.sh — снимок конфигурации DSH перед обновлением.
#
#   snapshot.sh create [--label NAME] [--no-dumps] [--with-secrets]
#   snapshot.sh verify <каталог-снимка>
#   snapshot.sh list
#   snapshot.sh show <каталог-снимка>
#   snapshot.sh prune [--keep N] [--keep-reports M] [--dry-run]
#
# Снимок включает: конфиги всех профилей, домашний слой, скиллы, состояние TUI,
# манифест с версиями/зависимостями/базовой линией загрузчика и контрольные суммы.
# Каждый созданный снимок сразу проверяется: суммы + пробное восстановление.
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

usage() {
  sed -n '2,12p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
}

cmd="${1:-}"
[ $# -gt 0 ] && shift

profile_files() { printf '%s\n' package.json cordis.patch.yml cordis.yml pnpm-lock.yaml pnpm-workspace.yaml; }

tui_state_copy() {
  local dest=$1 f name size
  [ -d "$TUI_HOME" ] || return 0
  mkdir -p "$dest"
  for f in "$TUI_HOME"/*; do
    [ -f "$f" ] || continue
    name="$(basename "$f")"
    case "$name" in
      *.lock|crash.log|restart.log|history.jsonl|effect-ledger.jsonl|*.bak-*) continue ;;
    esac
    size=$(wc -c <"$f" 2>/dev/null | tr -d ' ')
    [ -n "$size" ] && [ "$size" -gt 1048576 ] && continue
    cp -p "$f" "$dest/$name" 2>/dev/null || warn "не удалось скопировать $f"
  done
}

snapshot_create() {
  local label='manual' dumps=1 with_secrets=0
  while [ $# -gt 0 ]; do
    case "$1" in
      --label) label="${2:-manual}"; shift 2 ;;
      --no-dumps) dumps=0; shift ;;
      --with-secrets) with_secrets=1; shift ;;
      *) die "create: неизвестный флаг $1" ;;
    esac
  done
  need_base
  state_init
  label="${label//[^A-Za-z0-9_.-]/_}"
  local root="$SNAP_DIR/$(stamp)-$label"
  [ -e "$root" ] && root="$root-$$"
  mkdir -p "$root/files/profiles" "$root/files/home" "$root/files/skills" "$root/files/tui-state" || die "не удалось создать $root"

  info "снимок: $root"
  local p f copied=0
  for p in $(profiles); do
    mkdir -p "$root/files/profiles/$p"
    while IFS= read -r f; do
      [ -f "$DSH_HOME/profiles/$p/$f" ] || continue
      cp -p "$DSH_HOME/profiles/$p/$f" "$root/files/profiles/$p/$f" && copied=$((copied + 1))
    done < <(profile_files)
  done
  for f in settings.yaml cordis.patch.yml; do
    [ -f "$DSH_HOME/$f" ] || continue
    cp -p "$DSH_HOME/$f" "$root/files/home/$f" && copied=$((copied + 1))
  done
  if [ -d "$DSH_HOME/skills" ]; then
    cp -R "$DSH_HOME/skills/." "$root/files/skills/" 2>/dev/null || warn "скиллы скопированы не полностью"
    copied=$((copied + $(find "$root/files/skills" -type f 2>/dev/null | wc -l | tr -d ' ')))
  fi
  tui_state_copy "$root/files/tui-state"
  copied=$((copied + $(find "$root/files/tui-state" -type f 2>/dev/null | wc -l | tr -d ' ')))

  if [ "$with_secrets" -eq 1 ] && [ -f "$DSH_HOME/.credentials.yaml" ]; then
    cp -p "$DSH_HOME/.credentials.yaml" "$root/files/home/.credentials.yaml" && chmod 600 "$root/files/home/.credentials.yaml"
    ok "секреты включены (.credentials.yaml, режим 600)"
  fi

  local dump_flag=''
  [ "$dumps" -eq 1 ] && dump_flag='--dumps'
  node "$LIB_DIR/collect.mjs" $dump_flag >"$root/manifest.json" 2>"$root/collect.err" || die "не удалось собрать манифест"
  node -e '
    const fs = require("fs")
    const [file, root, label] = process.argv.slice(1)
    const j = JSON.parse(fs.readFileSync(file, "utf8"))
    j.format = "dsh-update-snapshot/1"
    j.label = label
    j.snapshotRoot = root
    fs.writeFileSync(file, JSON.stringify(j, null, 2) + "\n")
  ' "$root/manifest.json" "$root" "$label"

  sha256_emit_dir "$root" "$root/checksums.txt"
  [ -f "$root/checksums.txt" ] || : >"$root/checksums.txt"

  printf '%s\n' "$root" >"$SNAP_DIR/.latest"
  ok "файлов в снимке: $copied"
  prune_snapshots "$KEEP_SNAPSHOTS" 0 >/dev/null 2>&1
  snapshot_verify "$root" || die "снимок не прошёл проверку — обновление запускать нельзя"
  ok "снимок готов: $root"
}

snapshot_verify() {
  local dir="${1:-}"
  [ -n "$dir" ] || dir="$(latest_snapshot)"
  [ -n "$dir" ] && [ -d "$dir" ] || die "verify: снимок не найден"
  [ -f "$dir/manifest.json" ] || die "verify: нет manifest.json в $dir"
  [ -f "$dir/checksums.txt" ] || die "verify: нет checksums.txt в $dir"
  local bad=0
  if ! sha256_check_from "$dir" "$dir/checksums.txt" >/tmp/dsh-update-shasum.$$ 2>&1; then
    bad=$(grep -c 'FAILED' /tmp/dsh-update-shasum.$$ 2>/dev/null || printf '1')
    rm -f /tmp/dsh-update-shasum.$$
    err "контрольные суммы не сходятся (файлов с ошибкой: $bad)"
    return 1
  fi
  rm -f /tmp/dsh-update-shasum.$$

  # Пробное восстановление в temp: доказывает, что снимок реально разворачивается.
  local tmp
  tmp="$(mktemp -d "${TMPDIR:-/tmp}/dsh-snap-test.XXXXXX")" || return 1
  mkdir -p "$tmp/files"
  cp -R "$dir/files/." "$tmp/files/" 2>/dev/null || { rm -rf "$tmp"; err "не удалось скопировать файлы снимка"; return 1; }
  local restored=0
  if ! sha256_check_from "$tmp" "$dir/checksums.txt" >/dev/null 2>&1; then
    rm -rf "$tmp"
    err "пробное восстановление дало другие контрольные суммы"
    return 1
  fi
  restored=$(find "$tmp/files" -type f 2>/dev/null | wc -l | tr -d ' ')
  rm -rf "$tmp"
  ok "снимок проверен: суммы сходятся, восстановление воспроизводит $restored файлов"
  return 0
}

snapshot_prune() {
  local keep=$KEEP_SNAPSHOTS keep_reports=$KEEP_REPORTS dry=0
  while [ $# -gt 0 ]; do
    case "$1" in
      --keep) keep="${2:?}"; shift 2 ;;
      --keep-reports) keep_reports="${2:?}"; shift 2 ;;
      --dry-run) dry=1; shift ;;
      *) die "prune: неизвестный флаг $1" ;;
    esac
  done
  log "Снимки (оставить $keep):"
  prune_snapshots "$keep" "$dry"
  log "Отчёты (оставить $keep_reports):"
  prune_reports "$keep_reports" "$dry"
}

snapshot_list() {
  [ -d "$SNAP_DIR" ] || { log "снимков нет"; return 0; }
  local d
  for d in "$SNAP_DIR"/*/; do
    [ -d "$d" ] || continue
    printf '%s  ядро=%s tui=%s файлов=%s  %s\n' \
      "$(basename "$d")" \
      "$(json_field "$d/manifest.json" core.version)" \
      "$(node -e 'const j=require(process.argv[1]);const t=Object.values(j.profiles||{}).map(p=>p.tui&&p.tui.version).filter(Boolean);console.log(t[0]||"—")' "$d/manifest.json" 2>/dev/null)" \
      "$(find "$d/files" -type f 2>/dev/null | wc -l | tr -d ' ')" \
      "$(du -sh "$d" 2>/dev/null | awk '{print $1}')"
  done
  printf 'итого: %s снимков, %s\n' \
    "$(find "$SNAP_DIR" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l | tr -d ' ')" \
    "$(du -sh "$SNAP_DIR" 2>/dev/null | awk '{print $1}')"
}

snapshot_show() {
  local dir="${1:-$(latest_snapshot)}"
  [ -n "$dir" ] && [ -d "$dir" ] || die "show: снимок не найден"
  log "снимок:   $dir"
  log "метка:    $(json_field "$dir/manifest.json" label)"
  log "создан:   $(json_field "$dir/manifest.json" generatedAt)"
  log "ядро:     $(json_field "$dir/manifest.json" core.version)"
  log "node:     $(json_field "$dir/manifest.json" env.node)"
  log "профили:  $(node -e 'console.log(Object.keys(require(process.argv[1]).profiles||{}).join(", "))' "$dir/manifest.json" 2>/dev/null)"
  log "скиллы:   $(node -e 'console.log((require(process.argv[1]).skills||[]).map(s=>s.name).join(", "))' "$dir/manifest.json" 2>/dev/null)"
  log "файлов:   $(find "$dir/files" -type f 2>/dev/null | wc -l | tr -d ' ')"
  log "размер:   $(du -sh "$dir" 2>/dev/null | awk '{print $1}')"
}

case "$cmd" in
  create) snapshot_create "$@" ;;
  verify) snapshot_verify "${1:-}" ;;
  list) snapshot_list ;;
  prune) snapshot_prune "$@" ;;
  show) snapshot_show "${1:-}" ;;
  ''|-h|--help|help) usage; exit 0 ;;
  *) die "неизвестная команда: $cmd (create|verify|list|show|prune)" ;;
esac
