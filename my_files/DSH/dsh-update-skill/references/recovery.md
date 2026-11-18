# Рецепты восстановления

Ниже — что делать после `verify.sh` с ошибками. Перед любым восстановлением
убедитесь, что снимок цел:

```bash
~/.dsh/skills/dsh-update/scripts/snapshot.sh verify <снимок>
```

## Профиль не собирается (`dump: exit N`)

1. Посмотрите `~/.dsh/updates/reports/verify-*/current.json` → `profiles.<p>.dump`.
2. Запустите вручную, чтобы увидеть полный стек:
   ```bash
   dsh --profile tui --dump-config
   ```
3. Типовые причины:
   - `Cannot find module` — пакет удалён/не установлен:
     `dsh plugin --profile tui install`;
   - `does not provide an export named ...` — версия плагина не совместима с
     ядром: откатите плагин или ядро;
   - `patch: entry "..." not found` — предупреждение, не ошибка; проверьте, не
     переименован ли id в вашем `cordis.patch.yml`.
4. Если не помогает — откат:
   `scripts/rollback.sh --yes --reinstall`.

## Плагин не активировался (`smoke: failed to import`)

Симптом в stderr: `failed to import: ...` + стек.

```bash
# 1. какая версия стоит и какая ожидается
node ~/.dsh/skills/dsh-update/scripts/collect.mjs | \
  node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{const j=JSON.parse(s);console.log(j.profiles.tui.deps["dsh-at-file"])})'

# 2. исходник локального форка
ls -la /Users/weed/Documents/Ai/DSH/<форк>

# 3. переустановка из исходника
dsh plugin --profile tui add "file:/Users/weed/Documents/Ai/DSH/<форк>"
```

Если ошибка про отсутствующий экспорт — плагин отстал от ядра. Варианты:
обновить плагин, откатить ядро, или поправить форк под новый API (правка в
исходнике, не в `node_modules`).

## Форк заменён версией из npm

Признак: `dsh-tui-pkg` вдруг отвечает по-английски / потерял русскую локализацию.

```bash
dsh plugin --profile tui add "file:/Users/weed/Documents/Ai/DSH/dsh-tui-pkg-ru"
```

После этого `check.sh` снова покажет его как `file:`.

## pnpm отказывается ставить

- `ERR_PNPM_IGNORED_BUILDS` — в дереве есть build-скрипты. Используйте
  `apply.sh --official` (официальный апдейтер pre-seed'ит `allowBuilds`) или
  `/update` в TUI. Вручную:
  допишите в `~/.dsh/profiles/<p>/pnpm-workspace.yaml`:
  ```yaml
  allowBuilds:
    '@google/genai': false
    esbuild: false
    koffi: false
    protobufjs: false
  ```
- `MINIMUM_RELEASE_AGE` / ошибка про свежий релиз — подождите 24 часа либо
  добавьте исключение:
  ```yaml
  minimumReleaseAgeExclude:
    - '@deepseek-harness-tui/dsh-tui@0.20.1'
  ```
- `EEXIST` / tmp-rename — удалите недописанный каталог пакета и повторите:
  ```bash
  rm -rf ~/.dsh/profiles/tui/node_modules/@deepseek-harness-tui/dsh-tui
  dsh plugin --profile tui add @deepseek-harness-tui/dsh-tui@<версия>
  ```

## Ядро обновилось, TUI — нет

Проверьте матрицу: `check.sh`. Если TUI не поддерживает ядро — откат ядра:

```bash
npm i -g @deepseek-ai/dsh@<прежняя-версия>
# или
scripts/rollback.sh --yes --core
```

Ядро из снимка: `snapshot.sh show <снимок>` → поле «ядро».

## Скиллы пропали или не видны

1. `ls ~/.dsh/skills` — на месте ли каталоги.
2. `node scripts/util.mjs skill ~/.dsh/skills/<имя>/SKILL.md` — валиден ли
   фронтматтер.
3. Если скилл был внутри плагина — он вернулся вместе с версией пакета; правки
   внутри `node_modules` не переживают обновление.
4. Скилл стал доступен только после перезапуска сессии — это нормально.

## `dsh_backup` не покрывает новые файлы

`check.sh` печатает готовую строку:

```zsh
tui_files+=('agent-view-sessions.json' 'last-run.json' ...)
```

Вставьте её в `dsh_backup.zsh` рядом с объявлением `tui_files`. Скилл сам файл не
правит — это ваше решение.

## Web поднимается, но HTTP не 200

- `401` — нет токена: используйте URL из stdout (`?token=...`), а не корень.
- `303` — редирект на `/` с cookie; `verify.sh` ходит с `curl -L`.
- Порт занят — проверка берёт случайный порт; при конфликте повторите.

## Всё сломалось, нужен полный откат

```bash
scripts/rollback.sh --snapshot <снимок> --yes --reinstall --core
# затем перезапустите TUI/web вручную
scripts/verify.sh --all --smoke
```

Если и это не помогло — восстановите `~/.dsh` из `dsh_backup`:

```bash
zsh -ic 'source ~/.zsh_MyFunctions/dsh_backup.zsh; dsh_backup -u <каталог-бэкапа>'
```
