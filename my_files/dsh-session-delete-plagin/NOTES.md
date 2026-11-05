# NOTES — проверенные факты (фаза 0)

Все пути — от установленного `@deepseek-harness-tui/dsh-tui@0.18.0`
(`~/.dsh/profiles/tui/node_modules/...`) и реальных файлов состояния на этой
машине, если не указано иное. dsh CLI: 0.2.1-rc.5 (`/opt/homebrew/bin/dsh`),
Node: проверено `node --version` (>= 22).

## Эмпирическая проверка владения сценой (фаза 3)

Собрал скретч-хост с НАСТОЯЩИМИ модулями `dsh-tui 0.18.0` (lib/types) и
cordis 4 из бандла dsh CLI: корень + ряд, предоставляющий `tuiScenes`
(`new TuiSceneRuntime(ctx)` — Service сам делает provide) + плагин с
`ctx.inject(['tuiScenes'], host => …)`. Результат:

- `host.tuiScenes.register({id, component}, host)` из инъектированного
  fiber'а — **OK** (без «stale activation»);
- `host.tuiScenes.open(id)` из async-контекста ВНЕ активации (как вызов из
  обработчика dsh-commands по нажатию Enter) — **true**, сцена открылась.

Паттерн регистрации сцены и команды из ОДНОГО инъектированного fiber'а
рабочий на этой сборке. Скретч удалён после проверки.

## Швы (подтверждено кодом)

1. `ctx.inject(['tuiScenes','commands'], cb)` — верный способ дождаться швов;
   строки TUI монтируются позже, soft-probe проигрывает гонку (факт из
   README эталона, подтверждён структурой профиля: плагин-строки идут
   отдельными bundle'ами).
2. `TuiSceneRuntime.register({id, title, component}, identity?)` → dispose.
   - id: `/^[a-z][a-z0-9_-]*$/u`, lowercase; `session-delete` валиден.
   - требует «live activation»: регистрировать из инъектированного
     контекста (тот же `ready`, что и команда), иначе
     `requires a live activation`.
   - `open(id)` проверяет владельца активации: сцена и команда должны быть
     зарегистрированы из ОДНОГО и того же инъектированного fiber'а.
   - `bindCallerEffect` уже привязывает dispose к caller'у; дополнительный
     `host.effect(() => dispose)` — страховка (как в эталоне), не обязателен.
3. Пропсы компонента сцены (channel-scene-outlet.js):
   `{ React, ui, channel, close }` — только это. `close()` →
   `channel.closePluginScene()`.
4. `ctx.tuiDialogs` рендерится в обычном кадре чата (Chat.js ≈6538,
   ExtensionDialog); открытая сцена — ранний return поверх (Chat.js
   ≈6048-6077). Host-диалог из сцены не виден → UI — собственный модал.
5. `ctx.tuiShortcuts`: не матчатся, пока открыт оверлей (пикер/диалог/сцена);
   `ctrl+d` в FIXED_RESERVED_COMBOS (keymap.js ≈311-332). В v1 шортката нет.
6. Сцена не должна пересоздавать компонент на каждый рендер: компонент
   создаётся один раз при регистрации, иначе состояние теряется
   (identity в реестре стабилен).

## Канал (props.channel)

- `listSessions(onEnriched?, onPartial?)` → `Promise<SessionSummary[]>`:
  `{id, kind: {kind:'root'} | {kind:'fork', parent} | {kind:'subagent', parent?, depth}, title: {text, source}, cwd, createdAt, updatedAt, bytes?, hasPrompt, childCount, archived?}`.
- `agentViewRows()` → `AgentViewRow[]`: `{id, title, cwd, summary, status, live, current, createdAt, updatedAt}`.
- `deleteSession(id)` → `Promise<boolean>`: см. session-metadata.js ≈254-266 —
  отказ при `id === текущая`; `deleteSessionLog(id) !== 'deleted'` → false;
  чистит: каталог лога, cachedSessions, last-used (`forgetSession`),
  agent-view (`deps.forgetAgentView`), resume-маркер. Это НЕ чистит:
  projcache, workspace.json, session-index/mounts/lists/pins, last-run.
- `notify(text, {color, timeoutMs})` → dismiss-хэндл; в сцене не виден
  (рендерится в кадре чата) — не полагаемся.
- `deleteSession` в dsh-TUI 0.18: `false` для live-сессии и занятой другим
  процессом; обещание типа: «False for the live session or a missing /
  unwritable log».

## Команды

- `@deepseek-ai/dsh-commands` CommandDefinition: `{name, description, handler}`;
  handler(invocation) → `CommandResult` = `{kind:'success', text?}` |
  `{kind:'error', text}`. Имя без слэша, lowercase; `/^[a-z][a-z0-9_-]*$/`
  (в prompt; `session-delete` валиден). `commands.register(definition)` →
  dispose. Регистрация ТОЛЬКО через `ctx.commands.register` (не
  `tuiPluginHost.registerCommand` — нужен dsh-plugin.json и гранты).
- Тихое открытие сцены: handler возвращает `{kind:'success'}` (эталон),
  ошибка — `{kind:'error', text}`.

## Файлы состояния (реальные формы на машине)

- `$DSH_HOME/sessions/<slug>/<id>` — slug вида `--Users-weed-Documents-DSH--`;
  после удаления каталога сессии slug может опустеть.
- `$DSH_HOME/storages/workspace.json`: `{unit, global: {initialized, workspaceIds,
  archivedSessionIds, pinnedSessionIds}, tables: {workspaces: {<wsId>: {path,
  title, sessionIds, createdAt, updatedAt}}}}`.
- `$DSH_HOME/storages/session_projcache/sessions/<id>.json` — по одному файлу.
- `$DSH_TUI_HOME/session-index.json`: `{version, entries: {<id>: {...}}}`.
- `$DSH_TUI_HOME/session-mounts.json`: `{version, owners: [{pid, startedAt,
  sessionIds: [...]}]}`.
- `$DSH_TUI_HOME/session-lists/<hash>.json`: `{version, source, rows:
  [{id, kind, title, cwd, createdAt, updatedAt, hasPrompt, ...}]}`.
- `$DSH_TUI_HOME/session-pins.json` — на этой машине НЕТ (пины в
  workspace.json `global.pinnedSessionIds`); чистим «если файл есть» (массив id).
- `$DSH_TUI_HOME/last-run.json`: `{backendId, sessionId, cwd, attemptId, pid,
  updatedAt}` — `sessionId` → `''`, если равен id.
- `$DSH_TUI_HOME/last-used.json` / `agent-view-sessions.json` — карты id→ts,
  штатно чистит сам хост; в sweep не трогаем (idempotent-страховка эталона
  опущена сознательно: не наша зона).
- Не трогаем: `storages/cost-meter/*`, `history.jsonl`, `settings.json`,
  `workspace-sidebar.json`, логи других сессий.

## Environment

- `$DSH_HOME = process.env.DSH_HOME?.trim() || ~/.dsh`.
- `$DSH_TUI_HOME = process.env.DSH_TUI_HOME?.trim() || ~/.dsh-tui` (TUI сам
  переменную не читает — тестовый шов).

## Эталон (BoweiDuan/dsh-tui-session-manager, MIT)

Взято как идея: ctx.inject-паттерн, сцена с полным экраном, sweep с бэкапами,
empty-artifact (`hasPrompt===false && bytes<4096 && title.source==='fallback'`).
Не копируем: нет диалога подтверждения, нет дерева подсессий, нет пинов,
английский UI, нет проверки на 0.18, multiselect (нам не нужен).

## Версии

- dsh-tui 0.18.0 (package.json пакета). Плагин не импортирует
  React / `@deepseek-harness-tui/*` и любые `@deepseek-ai/*` в рантайме:
  только node builtins.
- Контракт apply: `export const name`, `export function apply(ctx, config)`
  БЕЗ возврата fiber'а (cordis примет возврат за effect → «Invalid effect»);
  без `export default` (unwrapExports).
