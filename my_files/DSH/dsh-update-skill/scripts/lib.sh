#!/usr/bin/env bash
# lib.sh — общие функции скилла /dsh-update. Подключается через `source`.
# shellcheck shell=bash disable=SC2317
set -u

LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(cd "$LIB_DIR/.." && pwd)"
UTIL="$LIB_DIR/util.mjs"

DSH_HOME="${DSH_HOME:-$HOME/.dsh}"
TUI_HOME="${DSH_TUI_HOME:-$HOME/.dsh-tui}"
STATE_DIR="${DSH_UPDATE_STATE:-$DSH_HOME/updates}"
SNAP_DIR="$STATE_DIR/snapshots"
REPORT_DIR="$STATE_DIR/reports"
# Порядок поиска: явная переменная → живой ~/.zsh_MyFunctions → старый путь → бэкап.
resolve_backup_script() {
  local c
  for c in "${DSH_BACKUP_SCRIPT:-}" "$HOME/.zsh_MyFunctions/dsh_backup.zsh" \
           "$HOME/Documents/Ai/DSH/dsh_backup/dsh_backup.zsh" \
           "$HOME/Documents/ForSys/Backup/.zsh_MyFunctions/dsh_backup.zsh"; do
    [ -n "$c" ] && [ -f "$c" ] && { printf '%s' "$c"; return 0; }
  done
  printf '%s' "${DSH_BACKUP_SCRIPT:-$HOME/.zsh_MyFunctions/dsh_backup.zsh}"
}
BACKUP_SCRIPT="$(resolve_backup_script)"
SMOKE_PROMPT="${DSH_UPDATE_SMOKE_PROMPT:-Reply with exactly: DSH_SMOKE_OK}"
SMOKE_MARKER="${DSH_UPDATE_SMOKE_MARKER:-DSH_SMOKE_OK}"
KEEP_SNAPSHOTS="${DSH_UPDATE_KEEP_SNAPSHOTS:-5}"
KEEP_REPORTS="${DSH_UPDATE_KEEP_REPORTS:-20}"
FORMAT="text"

if [ -t 1 ] && [ "${NO_COLOR:-}" = "" ]; then
  C_RED=$'\033[31m'; C_GRN=$'\033[32m'; C_YEL=$'\033[33m'; C_BLU=$'\033[34m'; C_DIM=$'\033[2m'; C_RST=$'\033[0m'
else
  C_RED=''; C_GRN=''; C_YEL=''; C_BLU=''; C_DIM=''; C_RST=''
fi

log()  { printf '%s\n' "$*"; }
info() { printf '%s•%s %s\n' "$C_BLU" "$C_RST" "$*"; }
ok()   { printf '%s✓%s %s\n' "$C_GRN" "$C_RST" "$*"; }
warn() { printf '%s!%s %s\n' "$C_YEL" "$C_RST" "$*" >&2; }
err()  { printf '%s✗%s %s\n' "$C_RED" "$C_RST" "$*" >&2; }
hr()   { printf '%s\n' "────────────────────────────────────────────────────────" ; }
die()  { err "$*"; exit 1; }

have() { command -v "$1" >/dev/null 2>&1; }

# ── sha256 и timeout (Linux) ────────────────────────────────────────────
sha256_check_from() {
  # sha256_check_from <рабочий-каталог> <checksums.txt>
  local cwd=$1 sums=$2
  ( cd "$cwd" && sha256sum -c "$sums" )
}

sha256_emit_dir() {
  # sha256_emit_dir <каталог> <checksums.txt>; хеширует только files/...
  local dir=$1 out=$2 file
  (
    cd "$dir" || return 1
    find files -type f -print0 | while IFS= read -r -d '' file; do
      sha256sum "$file"
    done >"$out" 2>/dev/null
  )
  return 0
}

run_timeout() {
  # run_timeout <секунды> <команда...>
  local secs=$1
  shift
  timeout "$secs" "$@"
}

need_base() {
  have node || die "нужен node в PATH"
  have dsh  || die "не найден dsh в PATH"
  [ -d "$DSH_HOME/profiles" ] || die "не найден каталог профилей: $DSH_HOME/profiles"
}

core_version() {
  dsh --version 2>/dev/null | head -1 | tr -d '[:space:]'
}

profiles() {
  local d
  for d in "$DSH_HOME"/profiles/*/; do
    [ -d "$d" ] || continue
    [ -f "$d/package.json" ] || continue
    basename "$d"
  done
}

profile_dir() { printf '%s/profiles/%s' "$DSH_HOME" "$1"; }

pkg_bundles() {
  node "$UTIL" bundles "$(profile_dir "$1")/package.json" 2>/dev/null
}

pkg_deps() {
  node "$UTIL" deps "$(profile_dir "$1")/package.json" 2>/dev/null
}

dep_spec() {
  node -e 'const j=require(process.argv[1]);const d={...j.dependencies,...j.devDependencies};process.stdout.write(d[process.argv[2]]??"")' \
    "$(profile_dir "$1")/package.json" "$2" 2>/dev/null
}

installed_version() {
  local f
  f="$(profile_dir "$1")/node_modules/$2/package.json"
  [ -f "$f" ] || { printf ''; return 0; }
  node "$UTIL" pkg "$f" 2>/dev/null | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{try{process.stdout.write(JSON.parse(s).version??"")}catch{}})'
}

host_dsh_dir() {
  local bin real
  bin="$(command -v dsh 2>/dev/null)" || return 1
  real="$(cd "$(dirname "$bin")" && pwd)/$(basename "$bin")"
  if have realpath; then real="$(realpath "$bin" 2>/dev/null || printf '%s' "$real")"; fi
  case "$real" in
    */lib/bin.js) dirname "$(dirname "$real")" ;;
    *) printf '%s' "$(npm root -g 2>/dev/null)/@deepseek-ai/dsh" ;;
  esac
}

tui_version() {
  local v
  v="$(installed_version "$1" "@deepseek-harness-tui/dsh-tui")"
  printf '%s' "$v"
}

semver_cmp() { node "$UTIL" cmp "$1" "$2"; }
semver_peer() { node "$UTIL" peer "$1" "$2"; }

is_file_dep() {
  case "$1" in
    file:*|link:*|portal:*) return 0 ;;
    *) return 1 ;;
  esac
}

bump_kind() {
  # patch | minor | major | prerelease | same | unknown
  node -e '
    const [a,b]=process.argv.slice(2);
    const p=v=>{const m=String(v).match(/^v?(\d+)\.(\d+)\.(\d+)(?:-([^+]+))?/);return m?{M:+m[1],m:+m[2],p:+m[3],pre:m[4]||""}:null};
    const x=p(a),y=p(b); if(!x||!y){console.log("unknown");process.exit(0)}
    if(x.M!==y.M) console.log("major");
    else if(x.m!==y.m) console.log("minor");
    else if(x.p!==y.p) console.log("patch");
    else if(x.pre!==y.pre) console.log("prerelease");
    else console.log("same");
  ' "$1" "$2" 2>/dev/null
}

state_init() {
  mkdir -p "$SNAP_DIR" "$REPORT_DIR" 2>/dev/null || die "не удалось создать $STATE_DIR"
}

stamp() { date +%Y%m%d-%H%M%S; }

latest_snapshot() {
  local f="$SNAP_DIR/.latest"
  [ -f "$f" ] && cat "$f"
}

set_latest_snapshot() { printf '%s\n' "$1" > "$SNAP_DIR/.latest"; }

json_field() {
  # json_field <file> <dot.path>
  node -e '
    const fs=require("fs");const [f,p]=process.argv.slice(1);
    let v;try{v=JSON.parse(fs.readFileSync(f,"utf8"))}catch{process.exit(3)}
    for(const k of p.split(".")){ if(v==null){v=undefined;break} v=v[k] }
    if(v===undefined||v===null)process.stdout.write("");
    else if(typeof v==="object")process.stdout.write(JSON.stringify(v));
    else process.stdout.write(String(v));
  ' "$1" "$2" 2>/dev/null
}

json_escape() { node -e 'process.stdout.write(JSON.stringify(process.argv[1]))' "$1"; }

eperm_hint() {
  grep -qiE "EPERM|operation not permitted|EACCES" "$1" 2>/dev/null || return 1
  warn "похоже на запрет записи (EPERM/EACCES). Запустите шаг в своём терминале или выдайте сессии полный доступ к $DSH_HOME."
  return 0
}

api_key_present() { [ -n "${DEEPSEEK_API_KEY:-}" ]; }

host_node_versions() {
  printf 'node=%s npm=%s pnpm=%s' \
    "$(node --version 2>/dev/null)" \
    "$(npm --version 2>/dev/null || printf '?')" \
    "$(pnpm --version 2>/dev/null || printf '?')"
}

# ── политика хранения ───────────────────────────────────────────────────
# Снимки: последние KEEP_SNAPSHOTS (точка отката всегда сохраняется).
# Отчёты:  последние KEEP_REPORTS каталогов verify-*.
# Удаляются только каталоги внутри $STATE_DIR — с проверкой префикса пути.

_prune_dirs() {
  # _prune_dirs <родитель> <шаблон> <сколько оставить> <dry-run 0|1> [защищённый путь]
  local parent=$1 pattern=$2 keep=$3 dry=$4 protected=${5:-}
  [ -d "$parent" ] || return 0
  local dirs=() d total remove
  while IFS= read -r d; do
    [ -n "$d" ] && dirs+=("$d")
  done < <(find "$parent" -mindepth 1 -maxdepth 1 -type d -name "$pattern" 2>/dev/null | sort)
  total=${#dirs[@]}
  [ "$total" -le "$keep" ] && return 0
  remove=$((total - keep))
  local i=0
  while [ "$i" -lt "$remove" ]; do
    d="${dirs[$i]}"
    i=$((i + 1))
    [ -n "$protected" ] && [ "$d" = "$protected" ] && continue
    case "$d" in
      "$STATE_DIR"/*) ;;
      *) warn "пропускаю удаление вне $STATE_DIR: $d"; continue ;;
    esac
    if [ "$dry" = "1" ]; then
      log "  (dry-run) удалил бы: $d"
    else
      rm -rf "$d" && log "  удалено: $(basename "$d")"
    fi
  done
}

prune_snapshots() {
  local keep=${1:-$KEEP_SNAPSHOTS} dry=${2:-0} latest=''
  latest="$(latest_snapshot 2>/dev/null || true)"
  _prune_dirs "$SNAP_DIR" '*' "$keep" "$dry" "$latest"
}

prune_reports() {
  local keep=${1:-$KEEP_REPORTS} dry=${2:-0}
  _prune_dirs "$REPORT_DIR" 'verify-*' "$keep" "$dry"
}
