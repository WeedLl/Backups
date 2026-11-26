#!/usr/bin/env bash
# install.sh — поставить скилл в ~/.dsh/skills (симлинк или копия).
#
#   install.sh [--link | --copy] [--dest DIR] [--uninstall]
#
# По умолчанию создаёт симлинк ~/.dsh/skills/dsh-update → этот каталог:
# правки в каталоге скилла сразу видны агенту. --copy делает независимую копию
# (для релиза/другой машины). --uninstall удаляет только ссылку/каталог скилла.
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

MODE=link
DEST="$DSH_HOME/skills"
UNINSTALL=0
while [ $# -gt 0 ]; do
  case "$1" in
    --link) MODE=link; shift ;;
    --copy) MODE=copy; shift ;;
    --dest) DEST="${2:?}"; shift 2 ;;
    --uninstall) UNINSTALL=1; shift ;;
    -h|--help) sed -n '2,8p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) die "install: неизвестный аргумент $1" ;;
  esac
done

[ -f "$SKILL_DIR/SKILL.md" ] || die "нет SKILL.md в $SKILL_DIR"
target="$DEST/dsh-update"

if [ "$UNINSTALL" -eq 1 ]; then
  if [ -L "$target" ]; then
    rm -f "$target" && ok "симлинк удалён: $target"
  elif [ -d "$target" ]; then
    rm -rf "$target" && ok "каталог удалён: $target"
  else
    warn "нечего удалять: $target"
  fi
  exit 0
fi

node "$UTIL" skill "$SKILL_DIR/SKILL.md" | node -e '
  let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{
    const j=JSON.parse(s);
    if(!j.ok){console.error("SKILL.md невалиден: "+j.problem);process.exit(1)}
    console.log("frontmatter: "+j.name+" — ok")
  })' || die "SKILL.md не прошёл проверку фронтматтера"

mkdir -p "$DEST" || die "не удалось создать $DEST"

if [ "$MODE" = "link" ]; then
  if [ -L "$target" ]; then
    current="$(readlink "$target")"
    if [ "$current" = "$SKILL_DIR" ]; then
      ok "симлинк уже указывает на $SKILL_DIR"
      exit 0
    fi
  fi
  if [ -e "$target" ] && [ ! -L "$target" ]; then
    backup="$target.bak-$(stamp)"
    mv "$target" "$backup" || die "не удалось отодвинуть старую копию"
    warn "старая копия сохранена: $backup"
  fi
  ln -sfn "$SKILL_DIR" "$target" || die "не удалось создать симлинк"
  ok "$target → $SKILL_DIR"
else
  if [ -L "$target" ]; then
    rm -f "$target"
  elif [ -d "$target" ] && [ ! -f "$target/SKILL.md" ]; then
    die "$target существует и не похож на скилл — уберите вручную"
  fi
  mkdir -p "$target"
  cp -R "$SKILL_DIR/." "$target/" || die "копирование не удалось"
  ok "скопировано в $target"
fi

log ""
log "Скилл появится в следующей сессии (или при следующем поиске скиллов)."
log "Проверка: $SKILL_DIR/scripts/check.sh"
