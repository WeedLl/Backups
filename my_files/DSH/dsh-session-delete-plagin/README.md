# dsh-session-delete

Плагин для dsh-TUI 0.18.0: удаление сохранённых сессий через модальный
диалог. Команда `/session-delete` открывает полноэкранную сцену, в которой
можно выбрать одну сохранённую сессию, подтвердить — и безвозвратно удалить
её **вместе с подсессиями**, а затем вычистить все «хвосты» в state-файлах.

Почему этот плагин: dsh-TUI умеет удалять сессии (`channel.deleteSession`),
но у DSH-сессий нет UI-входа для этого (Ctrl+D в браузере сессий работает
только для сторонних backend'ов), а штатное удаление не чистит ряд
state-файлов — после него остаются «призраки» в списках и счётчиках.

## Установка

Из каталога плагина:

```bash
dsh plugin --profile tui add file:/Users/weed/Documents/Ai/DSH/dsh-session-delete-plagin
```

Затем перезапустить TUI:

```bash
dsh --profile tui
```

Проверка, что строка встала:

```bash
dsh --profile tui --dump-config | grep -A6 session-delete
```

Ожидается строка `id: session-delete`, `name: dsh-session-delete`, config
`{sweep: true, backup: true, inboxCleanup: true}`.

Если в профиле стоит `dsh-tui-workspace-sidebar`, проверьте порядок в
`~/.dsh/profiles/tui/package.json`: `dsh-session-delete` должен идти в
`dsh.profile.bundles` **раньше** `dsh-tui-workspace-sidebar`. Иначе стартовый
janitor выполнится после загрузки sidebar и не успеет почистить файл до
чтения. `dsh plugin add` дописывает bundle в конец — после установки порядок
может потребоваться поправить вручную.

Удаление плагина:

```bash
dsh plugin --profile tui remove dsh-session-delete
```

Установка не требует прав, сети и pnpm-peer-политики: пакет — чистый
JavaScript ESM без зависимостей, `peerDependencies` и шага сборки.

## Использование

1. `/session-delete` — открыть диалог (без аргументов).
2. **Список**: `↑↓`/`j k` — выбор, `PgUp/PgDn` — страницами, `Enter` —
   подтверждение удаления, `/` — фильтр, `r` — перечитать список,
   `q`/`Esc` — закрыть.
3. **Фильтр** (регистронезависимый, по заголовку/cwd/id): печатные символы,
   `Backspace`, `Enter`/`Esc` — назад к списку. `Esc` в списке при непустом
   фильтре сначала очищает фильтр, вторым нажатием закрывает сцену.
4. **Подтверждение** в футере: `Удалить «…»?`, при подсессиях —
   `Вместе с ней: N подсессий.`, предупреждение о необратимости,
   `y` — удалить, `n`/`Esc` — отмена.
5. На время операции — `удаляю…`, ввод игнорируется. После — отчёт:
   `Удалено: …`, `вычищено: …`, ошибки красным; любая клавиша возвращает
   к списку.

Бейджи строк: `текущая`, `работает`, `архив`, `пустая`, `подсессии ×N`.
Сортировка — по `updatedAt` убыванию.

**Гарантии:**

- текущая и live-сессии не удаляются: `Enter` даёт сообщение в футере;
- если любая подсессия live/текущая — отказ целиком, ничего не удаляется;
- форки — независимые копии, в дерево удаления не входят;
- удаление необратимо: корзины, архива и восстановления нет.

## Что чистит удаление

1. **Хост** (`channel.deleteSession`): каталог лога сессии, `last-used`,
   agent-view, resume-маркер, MRU.
2. **Плагин (sweep)** — ссылки на id в:
   - `$DSH_HOME/storages/session_projcache/sessions/<id>.json` (файл удаляется);
   - `$DSH_HOME/storages/workspace.json` — `tables.workspaces[*].sessionIds`,
     `global.pinnedSessionIds`, `global.archivedSessionIds`;
   - `$DSH_TUI_HOME/session-index.json` — `entries[id]`;
   - `$DSH_TUI_HOME/session-mounts.json` — `owners[*].sessionIds`;
   - `$DSH_TUI_HOME/session-lists/*.json` — строки `rows[]` с этим id;
   - `$DSH_TUI_HOME/session-pins.json` — массив id (если файл есть);
   - `$DSH_TUI_HOME/last-run.json` — `sessionId` → `""`;
   - `$DSH_TUI_HOME/workspace-sidebar.json` — `sessions[id]` (кэш inbox
     `dsh-tui-workspace-sidebar`, если плагин установлен).
3. **Пустые slug-каталоги** `$DSH_HOME/sessions/<slug>/` — удаляются
   (`rmdir`), только пустые и только внутри `$DSH_HOME/sessions`.

`$DSH_HOME` = `$DSH_HOME` или `~/.dsh`; `$DSH_TUI_HOME` = `$DSH_TUI_HOME`
или `~/.dsh-tui`.

**Не трогает:** `storages/cost-meter/*`, `history.jsonl`, `settings.json`,
логи других сессий, любой чужой state. В `workspace-sidebar.json` меняется
только карта `sessions` и только для удалённых id.

## Inbox sidebar

`dsh-tui-workspace-sidebar` держит собственный кэш строк в
`~/.dsh-tui/workspace-sidebar.json`. Поэтому одной чистки при удалении мало:
живой трекер может перезаписать файл, а строки живут в памяти до 7 дней.

Плагин делает две вещи:

- **при удалении** (sweep) убирает `sessions[id]` из файла;
- **на старте** (`apply`, до загрузки sidebar) вызывает `cleanInboxState()`:
  удаляет из файла только `finished`-строки, для которых больше нет каталога
  `$DSH_HOME/sessions/*/<id>`. `running`-строки не трогаются, при битом JSON
  или нечитаемом `sessions` файл остаётся как есть.

Чтобы стартовая чистка гарантированно шла раньше sidebar, bundle
`dsh-session-delete` должен стоять в `dsh.profile.bundles` **до**
`dsh-tui-workspace-sidebar` (в этом профиле уже переставлен).

Текущая открытая панель всё равно может показывать строку из памяти до
перезапуска. Чтобы обновить её сразу после удаления, выполните `/restart`:
сессия продолжится, sidebar прочитает уже очищенный файл.

## Безопасность sweep

- id — только `^[A-Za-z0-9][A-Za-z0-9_-]*$`, иначе skip;
- перед первой записью файла — бэкап `<file>.bak-sweep-YYYYMMDD-HHMMSS`;
- запись атомарная (tmp + rename, режим 0600); при сбое после бэкапа
  оригинал восстанавливается из бэкапа;
- непарсибельный JSON не трогается, ошибка попадает в отчёт;
- `rm`/`rmdir` — только внутри корней после realpath-проверки;
- ничего не бросается: результат `{removed, pruned, skipped, errors, summary}`.

## Конфигурация

Строка cordis (`cordis.patch.yml` ставится автоматически):

```yaml
- insert:
    - id: session-delete
      name: dsh-session-delete
      config:
        sweep: true         # чистить хвосты после удаления
        backup: true        # бэкапы state-файлов перед записью
        inboxCleanup: true  # чистить workspace-sidebar.json на старте
        # inboxStateFile: /abs/path/workspace-sidebar.json
        #   если stateFile в конфиге sidebar переопределён
```

Переопределение — только по `id` в пользовательском слое профиля
(`~/.dsh/profiles/tui/cordis.patch.yml`), не второй строкой:

```yaml
- insert:
    - id: session-delete
      config:
        backup: false
```

## Откат

- Бэкапы sweep: `<file>.bak-sweep-YYYYMMDD-HHMMSS` рядом с каждым
  изменённым файлом. Восстановление — переименовать обратно.
- Сами логи сессий восстановить нельзя: удаление необратимо.
- Плагин: `dsh plugin --profile tui remove dsh-session-delete`.

## Известные ограничения

- Текущая открытая панель sidebar может держать строку в памяти до
  `/restart`: файл чистится сразу, но трекер не перечитывает его на лету.
  Следующий запуск TUI очищает остатки через `cleanInboxState()`.
- `storages/cost-meter/*` — чужая бухгалтерия, не трогается (записи о
  расходах удалённых сессий остаются).
- Одна сессия за подтверждение: мультивыбор и батч не входят в v1.
- Сцена занимает весь экран (ограничение шва): чат за панелью не виден,
  панель центрируется и читается как модал.
- UI только на русском (i18n не входит в v1).
- Ввод во время операции игнорируется; удаление большой семьи подсессий
  синхронно по шагам (отчёт появляется после завершения).

## Разработка

```bash
node --test test/    # 63 теста: дерево, guards, фильтр, sweep, janitor, регистрация
node --check index.js scene.js session-ops.js sweep.js tree.js strings.js
```

Рендер сцены тестами не покрывается (нет ink-хоста) — проверяется глазами
по чек-листу ниже.

### Ручной чек-лист (в TUI)

1. `/session-delete` открывает модал, список виден, фильтр работает.
2. Текущая сессия: `Enter` → сообщение в футере, удаления нет.
3. Пустая сессия удаляется; после рестарта её нет в `/resume` и счётчиках.
4. Сессия с подсессиями: в подтверждении `N подсессий`; после удаления их
   каталоги и state-записи исчезли.
5. После удаления: в `$DSH_HOME/storages/session_projcache/sessions/` нет
   `<id>.json`; в `workspace.json` нет id; в `session-index.json` /
   `session-mounts.json` / `session-lists/*` / `session-pins.json` /
   `workspace-sidebar.json` нет id; пустые slug-каталоги удалены.
6. `/restart` — в inbox нет удалённых сессий; живые строки и текущая сессия
   на месте.
7. `Esc` возвращает в чат, кадр не сломан, в stdout/stderr ничего не попало.
8. Отказ хоста (занятая сессия) показывается текстом, TUI не падает.

## Лицензия

MIT.
