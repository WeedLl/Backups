#!/usr/bin/env bash
# verify.sh — проверка, что после обновления всё живо.
#
#   verify.sh [--all | --profile NAME]... [--baseline DIR] [--smoke] [--json]
#
# Без --profile проверяются все профили. Базовая линия по умолчанию — последний снимок.
# --smoke добавляет живые проверки: web (HTTP + активация плагинов), tui (boot в PTY),
# headless (один короткий прогон; пропускается без ключа в окружении).
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

usage() { sed -n '2,10p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; }

SEL=()
BASELINE=''
SMOKE=0
AS_JSON=0
while [ $# -gt 0 ]; do
  case "$1" in
    --all) SEL=(); shift ;;
    --profile) SEL+=("${2:?--profile требует имя}"); shift 2 ;;
    --baseline) BASELINE="${2:?}"; shift 2 ;;
    --smoke) SMOKE=1; shift ;;
    --json) AS_JSON=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) die "verify: неизвестный аргумент $1" ;;
  esac
done

need_base
state_init
ts="$(stamp)"
outdir="$REPORT_DIR/verify-$ts"
mkdir -p "$outdir" || die "не удалось создать $outdir"
tsv="$outdir/findings.tsv"
: >"$tsv"

emit() { printf '%s\t%s\t%s\t%s\n' "$1" "$2" "$3" "$4" >>"$tsv"; }

in_scope() {
  [ ${#SEL[@]} -eq 0 ] && return 0
  local s
  for s in "${SEL[@]}"; do [ "$s" = "$1" ] && return 0; done
  return 1
}

info "сбор состояния профилей…"
current="$outdir/current.json"
node "$LIB_DIR/collect.mjs" --dumps >"$current" 2>"$outdir/collect.err" || die "collect.mjs упал: см. $outdir/collect.err"

[ -z "$BASELINE" ] && BASELINE="$(latest_snapshot)"
if [ -n "$BASELINE" ] && [ -f "$BASELINE/manifest.json" ]; then
  baseline_file="$BASELINE/manifest.json"
  ok "базовая линия: $(basename "$BASELINE")"
else
  baseline_file=''
  warn "базовой линии нет — сравнение «до/после» недоступно"
fi

findings="$outdir/checks.json"
if [ -n "$baseline_file" ]; then
  node "$LIB_DIR/checks.mjs" "$current" "$baseline_file" >"$findings" || die "checks.mjs упал"
else
  node "$LIB_DIR/checks.mjs" "$current" >"$findings" || die "checks.mjs упал"
fi
node -e '
  const f = JSON.parse(require("fs").readFileSync(process.argv[1], "utf8"))
  for (const x of f) console.log([x.level, x.scope, x.check, x.message].join("\t"))
' "$findings" >>"$tsv"

if [ -n "$baseline_file" ]; then
  node "$LIB_DIR/compare.mjs" "$baseline_file" "$current" >"$outdir/changes.txt" 2>/dev/null || : >"$outdir/changes.txt"
else
  : >"$outdir/changes.txt"
fi

smoke_web() {
  local p=$1 port out err pid url code i
  port=$((21000 + RANDOM % 15000))
  out="$outdir/smoke-$p.out"
  err="$outdir/smoke-$p.err"
  dsh --profile "$p" --port "$port" --no-open >"$out" 2>"$err" &
  pid=$!
  url=''
  for i in $(seq 1 60); do
    url=$(grep -oE "http://127\.0\.0\.1:${port}/[^ ]*" "$out" 2>/dev/null | head -1)
    [ -n "$url" ] && break
    kill -0 "$pid" 2>/dev/null || break
    sleep 0.5
  done
  if [ -z "$url" ]; then
    kill "$pid" 2>/dev/null
    wait "$pid" 2>/dev/null
    emit fail "$p" smoke "web не поднялся за 30 с (см. $out)"
    return
  fi
  code=$(curl -sL -c "$outdir/cookies.txt" -b "$outdir/cookies.txt" -o /dev/null -w '%{http_code}' --max-time 8 "$url" 2>/dev/null)
  kill "$pid" 2>/dev/null
  wait "$pid" 2>/dev/null
  if [ "$code" = "200" ]; then
    emit ok "$p" smoke "web отвечает 200"
  else
    emit fail "$p" smoke "web поднялся, но HTTP $code"
  fi
  local broken
  broken=$(grep -E "did not activate|failed to import|Cannot find module" "$err" 2>/dev/null | head -3 | tr '\n' ' ')
  if [ -n "$broken" ]; then
    emit fail "$p" smoke "плагины не активировались: $broken"
  else
    emit ok "$p" smoke "все плагины активировались"
  fi
}

smoke_tui() {
  local p=$1 out err pid alive broken
  out="$outdir/smoke-$p.out"
  err="$outdir/smoke-$p.err"
  script -q /dev/null dsh --profile "$p" >"$out" 2>"$err" &
  pid=$!
  sleep 10
  if kill -0 "$pid" 2>/dev/null; then alive=1; else alive=0; fi
  pkill -P "$pid" 2>/dev/null
  kill "$pid" 2>/dev/null
  wait "$pid" 2>/dev/null
  if [ "$alive" -eq 1 ]; then
    emit ok "$p" smoke "TUI прожил 10 с без падения"
  else
    emit fail "$p" smoke "TUI завершился сразу (см. $err)"
  fi
  broken=$(grep -E "did not activate|failed to import|Cannot find module" "$err" "$out" 2>/dev/null | head -3 | tr '\n' ' ')
  if [ -n "$broken" ]; then
    emit fail "$p" smoke "плагины не активировались: $broken"
  fi
}

smoke_headless() {
  local out code
  if ! api_key_present; then
    emit skip headless smoke "нет DEEPSEEK_API_KEY в окружении — живой прогон пропущен"
    return
  fi
  out="$outdir/smoke-headless.out"
  timeout 180 dsh headless "$SMOKE_PROMPT" >"$out" 2>&1
  code=$?
  if [ "$code" -eq 0 ] && grep -q "$SMOKE_MARKER" "$out"; then
    emit ok headless smoke "живой прогон ответил $SMOKE_MARKER"
  else
    emit fail headless smoke "живой прогон: exit $code (см. $out)"
  fi
}

if [ "$SMOKE" -eq 1 ]; then
  info "живые проверки…"
  for p in $(profiles); do
    in_scope "$p" || continue
    case "$p" in
      web) smoke_web "$p" ;;
      tui|dsh-tui) smoke_tui "$p" ;;
      headless) smoke_headless ;;
      *) warn "профиль $p: живая проверка не определена, пропуск" ;;
    esac
  done
fi

# ── отчёт ───────────────────────────────────────────────────────────────
if [ "$AS_JSON" -eq 1 ]; then
  node -e '
    const fs = require("fs")
    const rows = fs.readFileSync(process.argv[1], "utf8").split(/\r?\n/).filter(Boolean)
    const findings = rows.map(r => { const [level, scope, check, message] = r.split("\t"); return { level, scope, check, message } })
    const count = l => findings.filter(f => f.level === l).length
    const out = { format: "dsh-update-verify/1", summary: { fail: count("fail"), warn: count("warn"), ok: count("ok"), skip: count("skip") }, findings }
    process.stdout.write(JSON.stringify(out, null, 2) + "\n")
  ' "$tsv"
  exit "$(awk -F'\t' '$1=="fail"' "$tsv" | wc -l | tr -d ' ' | awk '{print ($1>0)?1:0}')"
fi

corev="$(json_field "$current" core.version)"
fails=$(awk -F'\t' '$1=="fail"' "$tsv" | wc -l | tr -d ' ')
warns=$(awk -F'\t' '$1=="warn"' "$tsv" | wc -l | tr -d ' ')
oks=$(awk -F'\t' '$1=="ok"' "$tsv" | wc -l | tr -d ' ')
skips=$(awk -F'\t' '$1=="skip" && $3!="smoke"' "$tsv" | wc -l | tr -d ' ')
nonsmoke_fails=$(awk -F'\t' '$1=="fail" && $3!="smoke"' "$tsv" | wc -l | tr -d ' ')
nonsmoke_warns=$(awk -F'\t' '$1=="warn" && $3!="smoke"' "$tsv" | wc -l | tr -d ' ')

report="$outdir/report.txt"
{
  hr
  log "Проверка DSH — $(date '+%d.%m %H:%M')"
  blabel='нет'
  [ -n "$BASELINE" ] && blabel="$(basename "$BASELINE")"
  log "ядро $corev · базовая линия: $blabel"
  hr
  if [ -s "$outdir/changes.txt" ] && [ -n "$baseline_file" ]; then
    log ""
    log "Что изменилось:"
    sed 's/^/  /' "$outdir/changes.txt"
  fi
  if [ "$SMOKE" -eq 1 ]; then
    log ""
    log "Живые проверки:"
    awk -F'\t' '$3=="smoke"{s=($1=="fail"?"✗":($1=="warn"?"!":($1=="skip"?"–":"✓")));printf "  %s [%s] %s\n", s, $2, $4}' "$tsv"
  fi
  if [ "$nonsmoke_fails" -gt 0 ]; then
    log ""
    log "Ошибки:"
    awk -F'\t' '$1=="fail" && $3!="smoke"{printf "  ✗ [%s] %s — %s\n", $2, $3, $4}' "$tsv"
  fi
  if [ "$nonsmoke_warns" -gt 0 ]; then
    log ""
    log "Предупреждения:"
    awk -F'\t' '$1=="warn" && $3!="smoke"{printf "  ! [%s] %s — %s\n", $2, $3, $4}' "$tsv"
  fi
  if [ "$skips" -gt 0 ]; then
    log ""
    log "Пропущено:"
    awk -F'\t' '$1=="skip" && $3!="smoke"{printf "  – [%s] %s\n", $2, $4}' "$tsv"
  fi
  if [ "$fails" -eq 0 ]; then
    log ""
    log "В порядке ($oks):"
    awk -F'\t' '$1=="ok" && $3!="smoke"{printf "  ✓ [%s] %s\n", $2, $4}' "$tsv"
  fi
  log ""
  hr
  if [ "$fails" -gt 0 ]; then
    log "ИТОГ: есть ошибки ($fails). Разбирать до перезапуска сессии."
  else
    log "ИТОГ: ошибок нет ($warns предупреждений)."
  fi
  log "Отчёт: $outdir"
  log "Детали: current.json, checks.json, smoke-*.out"
} | tee "$report"

prune_reports "$KEEP_REPORTS" 0 >/dev/null 2>&1

[ "$fails" -gt 0 ] && exit 1
exit 0
