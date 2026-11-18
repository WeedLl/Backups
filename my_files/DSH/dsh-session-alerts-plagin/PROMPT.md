## Зафиксированные решения

| Параметр | Решение |
|---|---|
| Имя npm-пакета | `dsh-session-alerts` |
| Каталог исходников | `~/Documents/Ai/DSH/dsh-session-alerts-plagin` |
| Установка | профили `tui`, `web`, `headless` |
| Звук | включён по умолчанию |
| Фоновые сессии | уведомлять всегда, без исключений |
| Текущая сессия | уведомлять тоже (без дублей и «тишины в фокусе») |

---

```text
# Задача: плагин dsh-session-alerts — системные уведомления macOS для DSH (tui / web / headless)

## Контекст
- macOS (Apple Silicon), терминал kitty 0.49.2; tmux не использовать.
- DSH 0.2.0-rc.2 (`/opt/homebrew/lib/node_modules/@deepseek-ai/dsh`), dsh-tui 0.18.0.
- Профили: `~/.dsh/profiles/tui`, `~/.dsh/profiles/web`, `~/.dsh/profiles/headless`.
  У каждого свой `package.json`, `cordis.patch.yml`, `node_modules`.
  pnpm, `nodeLinker: hoisted`, `autoInstallPeers: false`.
- Каталог исходников: `~/Documents/Ai/DSH/dsh-session-alerts-plagin` (создан, пуст).
- Имя npm-пакета: `dsh-session-alerts` (имя каталога от него отличается — это нормально).
- Установка: `dsh plugin --profile <p> add file:/Users/weed/Documents/Ai/DSH/dsh-session-alerts-plagin`.
- Сначала ПРОЧИТАЙ исходники установленного DSH, а не полагайся на память:
  `/opt/homebrew/lib/node_modules/@deepseek-ai/dsh/node_modules/@deepseek-ai/dsh-user-approval`
  `.../dsh-user-questions`, `.../dsh-session`, `.../dsh-agent`.
  Эталон host-плагина, который слушает сессии:
  `~/.dsh/profiles/tui/node_modules/dsh-working-activity`.

## Цель
Один host-only плагин, который шлёт macOS-уведомление, когда:
1. ход завершился успешно — в ЛЮБОЙ сессии, включая фоновые;
2. ход упал или прерван (опционально, включено по умолчанию);
3. инструмент просит подтверждение (approval) — включая фоновые сессии и субагентов;
4. агент задаёт вопрос (`ask_user_question`);
5. план ждёт ревью (если в 0.2.0-rc.2 есть стабильное событие; иначе — пропустить и отметить в README).

Никаких исключений «только foreground»: фоновые сессии — главный сценарий, ради которого плагин и пишется.

## Non-goals
- Никакого web-клиента (`dsh.client`), React-компонентов и страницы настроек в v1.
- Никакого inbound-управления (approve из уведомления), Telegram, телефона.
- Не писать в stdout/stderr процесса: TUI владеет stdout, любая запись ломает кадр.
- Не объявлять peerDependencies на `@deepseek-ai/dsh-session` и другие пакеты DSH —
  это ровно та ошибка, на которой DSH заблокировал `dsh-notifier@0.13.1`
  («incompatible with dsh 0.2.0-rc.2 … may cause crashes or data loss»).
  Разрешены только peer `@deepseek-ai/cordis` и `@deepseek-ai/schemastery` (для Config).

## Архитектура
Плагин = cordis-плагин: `export const name = 'session-alerts'`,
`export const Config = z.object({...})`, `export function apply(ctx, config)`.

Подписки:
- `ctx.on('session/event', (session, event) => ...)` — все сессии, включая фоновые.
  `event.type`: `turn/start`, `turn/end`, `assistant/message`, `goal/change`, ...
  `turn/end` несёт `event.data.reason.kind` (`completed` | `aborted` | ...).
- `ctx.on('approval/request', (req, next) => { ...; return next() })` — пассивно:
  уведомить и ОБЯЗАТЕЛЬНО вернуть `next()`, никогда не подменять ответ.
  Поля: `agent`, `toolName`, `callId?`, `reason?`, `displayReason?`.
- `ctx.on('user-questions/request', (req, next) => { ...; return next() })` — то же;
  поля: `questions[]`, `agent?`, `signal?`, `wait?`.

Перед реализацией сверь точные сигнатуры по `.d.ts` в перечисленных пакетах.
Если waterfall-слушатель нельзя зарегистрировать «пассивно» — используй
`ctx.inject`/`ctx.on` так, чтобы чужой запрос не потреблялся, и опиши это в README.

## Идентификация сессии
Для каждого события получить: `session.id`, заголовок (из `session/title`-события или метаданных),
рабочий каталог (для подписи). Фоновую сессию специально не выделять: id + заголовок
достаточно, чтобы понять, «где ждут».

## Правила, чтобы не спамить
- `turn/end` + `completed`: подождать `settleMs` (1500 мс); если за это время начался
  новый `turn/start` в той же сессии — уведомление отменить.
- Не уведомлять о завершении хода, если сессия ждёт approval/question: об этом уже
  было отдельное уведомление.
- Завершение субагентских ходов — НЕ уведомлять (иначе workflow за минуту даст десятки
  уведомлений). Конфиг `notifySubagentTurns: false`; кто хочет «совсем всё» — включает.
  Approval и вопросы от субагентов — уведомлять всегда.
- Дедупликация: ключ `kind + sessionId + callId/id`, окно `debounceMs` (10 000 мс).
- Глобальный лимит: не больше `maxPerMinute` (12) уведомлений в минуту.
- Replay: не уведомлять о событиях, пришедших в первые 2 секунды после старта плагина
  (это проигрывание истории при подписке).

## Транспорт (macOS)
- `osascript -e 'display notification "<body>" with title "<title>" sound name "<sound>"'`.
- Запуск через `execFile('osascript', [...])` БЕЗ shell; таймаут 3 с; `stdio: 'ignore'`.
- Экранирование: убрать `"` и `\`, схлопнуть переводы строк, тело ≤ 200 символов,
  заголовок ≤ 60.
- Звук ВКЛЮЧЁН по умолчанию: `sound: 'Glass'`. Отдельные ключи:
  `soundOnFinish: true`, `soundOnInterrupt: false`, `soundOnApproval: true`, `soundOnQuestion: true`.
  `'none'` — тишина.
- Если `osascript` упал — только `ctx.logger.warn`, никаких throw.
- Опционально: если в PATH есть `terminal-notifier`, использовать его (даёт клик и иконку),
  иначе osascript. Не добавлять зависимость в package.json.

## Конфиг (schemastery, все поля с дефолтами)
enabled: true
onFinish: true            # завершение хода (любая сессия, включая фоновые)
onError: true             # aborted / failed
onApproval: true
onQuestion: true
onPlanReview: true
notifySubagentTurns: false
settleMs: 1500
debounceMs: 10000
maxPerMinute: 12
sound: 'Glass'
soundOnFinish: true
soundOnInterrupt: false
soundOnApproval: true
soundOnQuestion: true
titlePrefix: 'DSH'

Ключ `quietWhenFocused` в v1 НЕ реализовывать: из host-процесса на macOS фокус надёжно
не определить без Accessibility, а костыль будет врать.

## Структура пакета (TypeScript, ESM, zero runtime deps)
dsh-session-alerts-plagin/
  package.json          # name dsh-session-alerts, version 1.0.0, type module,
                        # exports ".", engines.node >=22,
                        # dsh: { bundle: { patch: "./cordis.patch.yml" } }  ← БЕЗ client
  cordis.patch.yml      # insert: [{ id: session-alerts, name: 'dsh-session-alerts', config: {...} }]
  tsconfig.json         # NodeNext, declaration, outDir lib
  src/index.ts          # apply(ctx, config): подписки, таймеры, dispose
  src/config.ts         # Config schema + resolveConfig
  src/events.ts         # structural-типы событий, без импорта dsh-*
  src/notify.ts         # osascript / terminal-notifier, экранирование, лимитер
  src/format.ts         # тексты (ru/en), обрезка, подписи сессий
  src/limiter.ts        # debounce + maxPerMinute
  test/                 # node:test, без сети: format, limiter, экранирование
  README.md             # установка в 3 профиля, конфиг, ограничения, откат
  PROMPT.md             # этот файл (не удалять)

## Поведение по событиям
1) turn/end completed:
   title: "<prefix> · ход завершён"
   body:  "<заголовок сессии> · <последний ответ, 200 символов>"
          (если ответа нет — только заголовок сессии)
2) turn/end aborted/failed (если onError):
   title: "<prefix> · ход прерван" / "<prefix> · ошибка"
   body:  причина + заголовок сессии
3) approval/request:
   title: "<prefix> · нужно подтверждение"
   body:  "<toolName> · <заголовок сессии>" (+ reason, если есть)
4) user-questions/request:
   title: "<prefix> · вопрос"
   body:  первый вопрос (≤200) + заголовок сессии
5) план: "<prefix> · план ждёт ревью" (если событие найдено)

## Ограничения и безопасность
- Crash-safe: любая ошибка в обработчике ловится и логируется, процесс DSH не падает.
- Без секретов: тело — только текст ответа/вопроса, без аргументов инструментов и путей к ключам.
- Все таймеры очищаются в `ctx.on('dispose', ...)`.
- Не читать и не писать в `~/.dsh-tui` (это чужой слой).

## Установка и тестирование (обязательно)
1. `npm install && npm run build && node --test` — юнит-тесты.
2. Чистый профиль-копия:
   cp -R ~/.dsh/profiles/headless ~/.dsh/profiles/alert-test
   dsh plugin --profile alert-test add file:/Users/weed/Documents/Ai/DSH/dsh-session-alerts-plagin
   dsh --profile alert-test --help    # композиция + активация без запроса к модели
3. Ручные сценарии в профиле `tui` после рестарта:
   a. обычный ход → «ход завершён» (одно уведомление);
   b. `bash` с записью вне рабочего каталога → «нужно подтверждение» ДО ответа;
   c. `ask_user_question` → «вопрос»;
   d. /bg, затем работа в фоне → уведомление приходит (главная проверка);
   e. Ctrl+C → «прерван»;
   f. два быстрых хода подряд → одно уведомление, без дублей;
   g. approval из субагента → уведомление приходит.
4. Проверить, что в TUI не появилось мусора в кадре (stdout/stderr не трогаем).
5. Повторить установку и smoke-проверку в `web` и `headless`:
   dsh plugin --profile web add file:<path>
   dsh plugin --profile headless add file:<path>
   dsh headless "ответь одним словом: ок"    # ожидается уведомление о завершении

## Критерии приёмки
- [ ] `dsh plugin --profile tui add file:<path>` проходит без ERR_PNPM_* и без
      предупреждения «incompatible» (значит, peer-зависимостей на DSH нет).
- [ ] Плагин стоит в `tui`, `web`, `headless` и грузится во всех трёх.
- [ ] Уведомления приходят по всем включённым событиям, включая фоновые сессии.
- [ ] Нет дублей и шторма при серии быстрых ходов.
- [ ] Никогда не пишет в stdout/stderr и не роняет процесс при сбое osascript.
- [ ] Звук включён по умолчанию и настраивается.
- [ ] `taskNotifications` в TUI можно выключить — дублей не будет.
- [ ] README: установка в 3 профиля, конфиг, ограничения, откат (remove + restart).

## Порядок работы
1. Прочитать `.d.ts` approval/questions/session в установленном DSH, зафиксировать поля.
2. Каркас пакета + Config + заглушка notify (пишет только в лог).
3. Подписки, правила дедупа и таймеров, юнит-тесты.
4. Транспорт osascript + ручные сценарии на scratch-профиле.
5. Установка в `tui`, сценарии a–g; затем `web` и `headless`.
6. README + версия 1.0.0 + git init и первый коммит.

Отвечай по-русски, коммить по шагам, в конце отчёт: что проверено, что нет,
какие события оказались недоступны и почему.
```

---

## Как пользоваться

```bash
cd ~/Documents/Ai/DSH/dsh-session-alerts-plagin
# открыть новую сессию DeepSeek в этом каталоге и вставить содержимое блока выше
```

После реализации поставить в три профиля:

```bash
P=/Users/weed/Documents/Ai/DSH/dsh-session-alerts-plagin
dsh plugin --profile tui      add file:$P
dsh plugin --profile web      add file:$P
dsh plugin --profile headless add file:$P
# затем перезапустить TUI: dsh tui
```

И выключить встроенные уведомления TUI, чтобы не было дублей:

```text
/settings → Conversation → taskNotifications = off
```
