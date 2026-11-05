# Задача: плагин dsh-session-delete — удаление сессий dsh-TUI через диалог

## Роль и результат
Ты — инженер, который пишет один самодостаточный плагин для dsh-TUI 0.18.0.
Результат — каталог
`/Users/weed/Documents/Ai/DSH/dsh-session-delete-plagin`:
рабочий плагин `dsh-session-delete`, тесты `node --test`, README на русском,
`PROMPT.md` (этот текст). Ставится в профиль `tui`.

Перед началом убедись, что cwd сессии — `/Users/weed/Documents/Ai/DSH`
(или сам каталог плагина). Если нет — остановись и попроси пользователя
перезапустить сессию в этом каталоге: почти вся работа должна идти без
повышения прав.

## Что прочитать до кода (только чтение)
1. Наш предыдущий плагин: `/Users/weed/Documents/Ai/DSH/dsh-session-alerts-plagin`
   (структура, cordis.patch.yml, README, PROMPT.md, стиль отчёта).
2. Гайд: `~/.dsh/profiles/tui/node_modules/@deepseek-harness-tui/dsh-tui/guide/dsh-tui-guide/plugins.en.md`.
3. Типы швов и API (в этом порядке):
   - `.../lib/types/dsh-adapter/scenes.d.ts` — сцена и её props.
   - `.../lib/types/adapter/ports/channel-ui.d.ts` — `listSessions`, `deleteSession`,
     `agentViewRows`, `notify`.
   - `.../lib/types/adapter/ports/channel-session.d.ts` — `SessionSummary`, `SessionKind`.
   - `.../lib/types/adapter/ports/channel-view.d.ts` — `AgentViewRow` (`live`, `current`).
   - `.../lib/types/dsh-adapter/dialogs.d.ts` — почему host-диалоги не подходят.
   - `.../lib/types/dsh-adapter/shortcuts.d.ts`, `.../lib/types/utils/keymap.js` —
     почему шортката нет.
   - `.../lib/types/screens/Chat.js` — сцена это ранний return (≈6048-6075),
     ExtensionDialog в обычном кадре (≈6538).
   - `.../lib/types/screens/SessionSupervisor.js` — Ctrl+D только для
     `!dshBackend` (≈346).
   - `.../lib/types/dsh-adapter/channel/session-metadata.js` (≈250-270) — что
     именно чистит штатное удаление.
4. Эталон (MIT): https://github.com/BoweiDuan/dsh-tui-session-manager —
   `index.js`, `scene.js`, `sweep.js`. Возьми идеи (ctx.inject, сцена, sweep,
   empty-artifact), но не копируй целиком и не повторяй его пробелы:
   нет диалога, нет подсессий, нет пинов, английский UI, нет проверки на 0.18.
   Если сети нет — не блокируйся: фактов и путей из этого промпта достаточно.
5. DSH-пакеты: `@deepseek-ai/dsh-commands` (CommandDefinition),
   `@deepseek-ai/dsh-session` (SessionHeader), `@deepseek-ai/dsh-workspace`
   (`pinnedSessionIds`/`archivedSessionIds`).

## Проверенные факты (сверяйся с кодом, но не перепроверяй с нуля)
- dsh-TUI 0.18.0, Node ^22.19, macOS/kitty.
- Каталог `channel` доступен плагину ТОЛЬКО как `props.channel` сцены;
  сервиса `ctx.tuiChannel` в этой сборке нет.
- `ctx.tuiDialogs` рендерится в обычном кадре чата; открытая сцена — ранний
  return поверх, поэтому host-диалог из сцены не виден. Значит UI — свой
  модал внутри сцены.
- `ctx.tuiShortcuts` не матчатся, пока открыт оверлей (пикер/диалог/сцена/
  браузер), а `ctrl+d` в FIXED_RESERVED_COMBOS. В v1 шортката нет.
- `channel.listSessions(onEnriched?, onPartial?)` → `SessionSummary[]`:
  `id`, `kind {kind:'root'|'fork'|'subagent', parent?, depth?}`,
  `title {text, source}`, `cwd`, `createdAt`, `updatedAt`, `bytes`,
  `hasPrompt`, `childCount`, `archived?`.
- `channel.agentViewRows()` → `{id, title, cwd, status, live, current, ...}`.
- `channel.deleteSession(id)` → boolean: сносит каталог лога, `last-used`,
  agent-view, resume-marker, MRU; отказывает текущей и занятой другим процессом.
- `ctx.commands.register({name, description, handler})`; имя по
  `/^[a-z][a-z0-9_-]*$/`; `/session-delete` валидно.
- `apply` обязан ждать швы через `ctx.inject(['tuiScenes','commands'], cb)`:
  строки TUI монтируются позже, soft-probe проигрывает гонку.

## Объём v1
Один плагин, одна команда, один экран:
`/session-delete` → модальный диалог → выбрать сохранённую сессию → подтвердить
→ безвозвратно удалить её и её подсессии → вычистить «хвосты» → показать отчёт.

## Non-goals (не делать)
- Корзины, архива и восстановления нет: удаление необратимо.
- Нет шорткатов, нет входа из `/resume` (шва нет), нет `dsh-plugin.json`.
- Нет мультивыбора и батча: одна сессия за подтверждение.
- Нет i18n: только русские строки.
- Нет патчей `node_modules` и импорта React/`@deepseek-harness-tui/*` в рантайме.
- Никаких записей в stdout/stderr.

## Технология
- JavaScript ESM, ноль зависимостей и peerDependencies, без сборки.
  Причина: установка через `dsh plugin add` не должна упираться в pnpm/peer-
  политику и сеть; `node --test` работает сразу.
- Файлы: `index.js`, `scene.js`, `session-ops.js`, `sweep.js`, `tree.js`,
  `strings.js`, `cordis.patch.yml`, `README.md`, `PROMPT.md`, `test/*.mjs`.
- `package.json`: name `dsh-session-delete`, version 0.1.0, type module,
  main/exports, `dsh.bundle.patch`, files, engines, scripts.test.
  Никаких `peerDependencies` на `@deepseek-ai/*`.

## UX (модал)
- Сцена `session-delete`, открывается командой `/session-delete` без аргументов.
- Сцена занимает весь экран: чат за панелью не виден — это ограничение шва.
  Визуально панель центрируется и читается как модальный диалог.
- Корень: `Box` на весь экран, по центру панель шириной
  `Math.max(40, Math.min(columns - 6, 78))`, высотой не больше `rows - 4`.
- Шапка: `Удаление сессии` и `N сессий`; при фильтре — `фильтр: …`.
- Список: курсор `❯`, заголовок (truncate), короткий cwd (`~/…`), возраст;
  бейджи: `текущая`, `работает`, `архив`, `пустая`, `подсессии ×N`.
- Сортировка: `updatedAt` по убыванию. Фильтр регистронезависимый по
  title/cwd/id.
- Два режима ввода, как в родных пикерах: «список» и «фильтр».
  В списке: `↑↓`/`j k`, `PgUp/PgDn`, `Enter` — подтверждение, `/` — войти
  в фильтр, `r` — перечитать, `q`/`Esc` — закрыть.
  В фильтре: печатные символы, `Backspace`, `Enter`/`Esc` — выйти из фильтра
  (сцена не закрывается).
- `Esc` в списке при непустом фильтре — сначала очистить фильтр, вторым
  нажатием закрыть.
- Текущая/живая: строка видима, но `Enter` даёт сообщение в футере, без удаления.
- Подтверждение в футере: `Удалить «title»?` + `Вместе с ней: N подсессий.` +
  `Логи будут стёрты безвозвратно. y — удалить · n — отмена`.
- На время операции — `удаляю…`, ввод игнорируется.
- После: строка исчезает, футер `Удалено: title · вычищено: …` или ошибки красным.
- Никаких `ctx.tuiDialogs`: их не видно поверх сцены.

## Дерево подсессий
- `collectDescendants(sessions, rootId)`: по `kind.kind === 'subagent'` и
  `kind.parent`, рекурсивно, с защитой от циклов; возвращает листья → корень.
- Форки (`kind.kind === 'fork'`) не трогаем: это независимые копии.
- Если любой потомок `live` — отказ целиком, ничего не удалять.
- Порядок удаления: потомки (от листьев), затем корень.

## Удаление
1. Проверить всё ДО первого удаления: id по whitelist, `current`, `live`,
   наличие в списке.
2. Найти каталоги сессий (`$DSH_HOME/sessions/*/<id>`) и запомнить их
   slug-родителей: после удаления каталога сессии они могут опустеть.
3. Для каждого id (потомки от листьев, затем корень):
   `await channel.deleteSession(id)`; `false` — отказ хоста, записать в отчёт;
   если отказал потомок — родителя не удалять. После успешного удаления —
   `sweepSessions([id])`.
4. После всех: `rmdir` опустевших slug-каталогов (только пустых, только
   внутри `$DSH_HOME/sessions`).
5. Перечитать список (или убрать строки локально) и показать отчёт.

## Sweep: что чистить (проверено grep'ом по id на этой машине)
Штатное `channel.deleteSession` чистит: каталог лога, `last-used.json`,
`agent-view-sessions.json`, `resume.txt`, MRU. Остаётся:
1. `$DSH_HOME/storages/session_projcache/sessions/<id>.json` — удалить.
2. `$DSH_HOME/storages/workspace.json` — `tables.workspaces[*].sessionIds`,
   `global.pinnedSessionIds`, `global.archivedSessionIds` — вычистить id.
3. `$DSH_TUI_HOME/session-index.json` — `entries[id]`.
4. `$DSH_TUI_HOME/session-mounts.json` — `owners[*].sessionIds`.
5. `$DSH_TUI_HOME/session-lists/*.json` — `rows[]` с этим id.
6. `$DSH_TUI_HOME/session-pins.json` — массив id (если файл есть).
7. `$DSH_TUI_HOME/last-run.json` — `sessionId === id` → `""`.

Пустые `$DSH_HOME/sessions/<slug>/` — отдельный шаг
`removeEmptySessionDirs(slugs)` после удаления, не внутри sweep: `rmdir`
только пустого каталога и только внутри `$DSH_HOME/sessions`.

`$DSH_HOME = process.env.DSH_HOME?.trim() || join(homedir(), '.dsh')`.
`$DSH_TUI_HOME = process.env.DSH_TUI_HOME?.trim() || join(homedir(), '.dsh-tui')`
(сам TUI переменную не читает — это тестовый шов и переносимость).

Не трогать: `storages/cost-meter/*` (чужая бухгалтерия), `history.jsonl`,
`settings.json`, `workspace-sidebar.json` и прочий state сторонних плагинов,
логи других сессий. В README — известное ограничение: сайдбар
`dsh-tui-workspace-sidebar` может держать строку удалённой сессии до перезагрузки.

Правила безопасности sweep:
- id только `^[A-Za-z0-9][A-Za-z0-9_-]*$`; иначе skip.
- перед первой записью файла — бэкап `<file>.bak-sweep-YYYYMMDD-HHMMSS`.
- запись атомарная: tmp + rename, режим 0600.
- непарсибельный JSON — не трогать, записать в errors.
- ничего не бросать: `{removed, pruned, skipped, errors, summary}`.
- `dryRun` для тестов; `backup` можно выключить конфигом.
- rm/rmdir — только внутри `$DSH_HOME/sessions` после realpath-проверки.

## Конфиг (cordis row)
`{ sweep: true, backup: true }`, нормализация вручную (`normalizeConfig`),
без schemastery. `cordis.patch.yml` — top-level массив:

- insert:
    - id: session-delete
      name: dsh-session-delete
      config:
        sweep: true
        backup: true

Неизвестные ключи игнорировать. Переопределять значения — в пользовательском
слое профиля (`~/.dsh/profiles/tui/cordis.patch.yml`) по `id`, не второй строкой.

## Структура и контракты
- `index.js`: `export const name = 'session-delete'`,
  `export function apply(ctx, config)`,
  `ctx.inject(['tuiScenes','commands'], host => { register scene + command; host.effect(...) })`.
  Никакого `export default` (cordis `unwrapExports` схлопнет namespace).
- Регистрация команды — только `ctx.commands.register`. НЕ `host.registerCommand`:
  медиация требует `dsh-plugin.json` и объявленных прав, которых в v1 нет.
- Компонент сцены создаётся ОДИН раз при регистрации
  (`const component = createSessionDeleteScene(...)`); новая функция на каждый
  рендер перемонтирует сцену и теряет состояние.
- `apply` не возвращает fiber: cordis принимает возвращённый fiber за effect
  и падает с «Invalid effect».
- `scene.js`: `createSessionDeleteScene({ settings })` → компонент; только
  `props.React.createElement`, `props.ui`, `props.channel`, `props.close`.
  Хуки — на верхнем уровне; ошибки ловить, не бросать в рендер.
- `session-ops.js`: чистые функции (сортировка, фильтр, guard-вердикты, план
  удаления, форматирование) — тестируются без TUI.
- `sweep.js`: fs-операции с инъекцией root'ов для тестов.
- `strings.js`: все тексты. `tree.js`: сбор потомков.
- Логирование: только `ctx.logger?.warn?.`; флаг `DSH_SESSION_DELETE_DEBUG=1`
  может добавлять подробности в лог, но не в stdout.

## Тесты (`node --test`)
- `registration.test.mjs`: фейковый ctx с `inject`, `effect`, `logger`;
  фейковые `tuiScenes`/`commands`; проверка регистрации, dispose, ответа
  команды, idle при отсутствии швов, идемпотентности.
- `tree.test.mjs`: потомки, глубина, циклы, форки не потомки.
- `guards.test.mjs`: current/live/archived/unsafe id.
- `filter.test.mjs`: сортировка, регистронезависимый поиск, пустой фильтр.
- `sweep.test.mjs`: временные `$DSH_HOME`/`$DSH_TUI_HOME`; все 7 файловых
  целей + пустой slug; бэкапы; битый JSON не тронут; whitelist; dryRun;
  чужие файлы целы.
- Рендер не тестируем: ink-хост недоступен; UI проверяется глазами.

## Фазы (сначала всё без повышения прав)
Фаза 0 — чтение исходников и фиксация фактов в `NOTES.md` (внутри workspace).
Фаза 1 — каркас пакета, `strings`, `session-ops`, `tree`, `sweep`, тесты;
`node --test` зелёный. Никаких записей вне workspace.
Фаза 2 — `scene.js`, `index.js`, регистрация; тесты регистрации.
Фаза 3 — статическая проверка: `node --check` по файлам, `npm pack --dry-run`,
ревью `cordis.patch.yml`.
Фаза 4 — ТОЛЬКО в конце, одним запросом: установка в профиль `tui`
(`dsh plugin --profile tui add file:<abs path>`),
`dsh --profile tui --dump-config | grep -A6 session-delete`,
просьба перезапустить TUI и пройти чек-лист. Перед запросом перечисли ровно
то, что будешь делать и зачем, и не проси прав на большее.

Если прав не дали — оставь точные команды и чек-лист в README и отчёте.

## Ручной чек-лист (после установки, в TUI)
1. `/session-delete` открывает модал, список виден, фильтр работает.
2. Текущая сессия: `Enter` → сообщение, удаления нет.
3. Пустая сессия удаляется; после рестарта её нет в `/resume` и в счётчиках.
4. Сессия с подсессиями: в подтверждении видно `N подсессий`; после удаления
   их каталоги и state-записи исчезли.
5. После удаления в `$DSH_HOME/storages/session_projcache/sessions/` нет
   `<id>.json`, в `workspace.json` нет id, в `session-index.json` /
   `session-mounts.json` / `session-lists/*` / `session-pins.json` нет id;
   пустые slug-каталоги удалены.
6. `Esc` возвращает в чат, кадр не сломан, в stdout/stderr ничего не попало.
7. Отказ хоста (занятая сессия) показывается текстом, TUI не падает.

## Приёмка
- [ ] `/session-delete` работает; текущая/live не удаляются.
- [ ] Подсессии удаляются деревом; live-потомок блокирует всё.
- [ ] Sweep покрывает 7 файловых целей + пустые slug-каталоги; бэкапы,
      атомарная запись, dryRun и тесты.
- [ ] Установка в `tui` без ERR_PNPM и без «incompatible» (нет peer'ов).
- [ ] Нет вывода в stdout/stderr; нет импортов React/`@deepseek-harness-tui/*`.
- [ ] README: установка, UX, что чистится, что остаётся, откат.
- [ ] Отчёт по-русски: что проверено и как, что нет и почему.

## Отчёт в конце
1. Что сделано (файлы, решения).
2. Что проверено: тесты (сколько), `node --check`, установка, ручные пункты.
3. Что осталось: известные ограничения (workspace-sidebar, cost-meter,
   мультивыбор).
4. Какие операции потребовали прав и почему.

Взможно, что DSH обновлен, так что держи это в голове
