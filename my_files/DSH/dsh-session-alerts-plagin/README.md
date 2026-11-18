# dsh-session-alerts

Системные уведомления macOS для DSH (0.2.0-rc.2): когда ход агента завершился,
упал или прерван, когда инструмент просит подтверждение, когда агент задаёт
вопрос, и когда план ждёт ревью. Host-only cordis-плагин: **все сессии,
включая фоновые и субагентские** — никаких исключений «только foreground».

Без web-клиента, без inbound-управления (approve из уведомления), без
зависимостей в рантайме (только Node builtins + peer `@deepseek-ai/cordis` /
`@deepseek-ai/schemastery` для Config).

## Установка

```bash
cd ~/Documents/Ai/DSH/dsh-session-alerts-plagin
npm install && npm run build && node --test     # сборка + 37 тестов

dsh plugin --profile tui      add file:$PWD
dsh plugin --profile web      add file:$PWD
dsh plugin --profile headless add file:$PWD
```

Каждая команда: pnpm-установка пакета в профиль, добавление в
`dsh.profile.bundles`, применение `cordis.patch.yml` пакета (строка
`session-alerts` монтируется в композицию). Перезапустите приложение профиля
(TUI / web-сервер / headless-запуск), чтобы плагин активировался.

Проверка композиции: `dsh --profile <p> --dump-config | grep -A 20 session-alerts`.

### Откат

```bash
dsh plugin --profile tui      remove dsh-session-alerts
dsh plugin --profile web      remove dsh-session-alerts
dsh plugin --profile headless remove dsh-session-alerts
# + перезапуск приложения профиля
```

Или без удаления: строка `- id: session-alerts, disabled: true` в
`~/.dsh/profiles/<p>/cordis.patch.yml` + перезапуск.

## Конфиг

Все ключи имеют дефолты; править в `~/.dsh/profiles/<p>/cordis.patch.yml`
(переопределение по id, вторая строка с тем же id не нужна):

```yaml
- id: session-alerts
  name: 'dsh-session-alerts'
  config:
    enabled: true            # мастер-выключатель
    onFinish: true           # ход завершён (любая сессия, включая фоновые)
    onError: true            # ход прерван / ошибка
    onApproval: true         # инструмент просит подтверждение
    onQuestion: true         # агент задаёт вопрос (ask_user_question)
    onPlanReview: true       # план ждёт ревью (exit_plan_mode)
    notifySubagentTurns: false  # уведомлять и о завершении ходов субагентов
    settleMs: 1500           # пауза перед «ход завершён» (см. ниже)
    debounceMs: 10000        # дедупликация одинаковых событий, мс
    maxPerMinute: 12         # глобальный лимит уведомлений в минуту
    sound: 'Glass'           # системный звук; 'none' — тишина
    soundOnFinish: true
    soundOnInterrupt: false
    soundOnApproval: true
    soundOnQuestion: true
    titlePrefix: 'DSH'       # префикс заголовка
    activate: ''             # bundle-id приложения, активируемого по клику
                             #   (только terminal-notifier), напр. 'net.kovidgoyal.kitty'
    lang: 'ru'               # 'ru' | 'en'
```

## Что уведомляется и как

| Событие | Заголовок | Тело |
|---|---|---|
| `turn/end` `completed` | `<prefix> · ход завершён` | заголовок сессии · последний ответ (≤200 симв.) |
| `turn/end` `aborted` | `<prefix> · ход прерван` | причина · заголовок сессии |
| `turn/end` `error` / `max-tokens` | `<prefix> · ошибка` | сообщение ошибки · заголовок сессии |
| `approval/request` | `<prefix> · нужно подтверждение` | toolName · заголовок сессии (+ reason) |
| `user-questions/request` | `<prefix> · вопрос` | первый вопрос · заголовок сессии |
| `user-questions/request` с `intent.kind: 'plan-review'` | `<prefix> · план ждёт ревью` | вопрос ревью · заголовок сессии |

«Заголовок сессии» — последний `session/title`; если его нет — базовое имя
рабочего каталога (`session.header.cwd`), затем короткий id сессии. Тело —
только текст ответа/вопроса: аргументы инструментов и пути к ключам не
попадают в уведомления.

**План ждёт ревью.** В 0.2.0-rc.2 отдельного cordis-события «план на ревью»
нет. Стабильный сигнал есть: `dsh-plan-mode` (инструмент `exit_plan_mode`)
поднимает `user-questions/request` с `questions[0].intent.kind ===
'plan-review'` — плагин распознаёт именно его. Если `onPlanReview: false`,
такой запрос уведомляется как обычный вопрос (при `onQuestion: true`).

## Правила против спама

- **settle**: «ход завершён» шлётся через `settleMs` после `turn/end`; если за
  это время в той же сессии начался новый `turn/start` — уведомление
  отменяется. Исключение: `session/flush` (durability-чекпойнт на границе
  хода, который headless-раннер await'ит перед выходом) доставляет отложенное
  уведомление сразу — иначе one-shot процесс выходил бы раньше таймера.
- **interacting**: если сессия ждёт approval/question (о чём уже было
  отдельное уведомление), завершение хода не уведомляется.
- **субагенты**: завершения их ходов выключены по умолчанию
  (`notifySubagentTurns: false`) — workflow за минуту дал бы десятки
  уведомлений. Approval и вопросы от субагентов уведомляются всегда.
- **дедупликация**: ключ `kind + sessionId + callId/id`, окно `debounceMs`.
- **лимит**: не больше `maxPerMinute` уведомлений за скользящую минуту.
- **replay**: события, записанные раньше старта плагина (история), не
  уведомляются; сессии, созданные до старта плагина (resume при загрузке),
  дополнительно глушатся первые 2 секунды. Свежие сессии уведомляются сразу —
  быстрый headless-ход укладывается в пару секунд и не должен теряться.

## Иконка и клик по уведомлению

Транспорт по умолчанию — `osascript`. Ограничение macOS: у `osascript` нет
собственного app-bundle, поэтому Notification Center приписывает уведомление
**Script Editor** (иконка — Script Editor), а клик по уведомлению открывает
Script Editor / папку со скриптами. Изменить это средствами osascript нельзя.

Чтобы получить нормальную иконку и осмысленный клик — поставьте
`terminal-notifier` (плагин подхватит его автоматически, он в PATH):

```bash
brew install terminal-notifier
```

Тогда: иконка — terminal-notifier (или кастомная: `make icon ICON=... APP_NAME=...`
из исходников terminal-notifier — macOS всегда берёт иконку из bundle
отправителя, поменять её per-notification нельзя), а клик по уведомлению
активирует приложение из конфига `activate` (например kitty:
`activate: 'net.kovidgoyal.kitty'`). Без `activate` клик просто закрывает
уведомление. В v3 опции `-sender`/`-appIcon` удалены автором
terminal-notifier (не работают на UserNotifications API), поэтому вместо
них — `-activate`.

## Архитектура и безопасность

- Cordis-плагин `name: 'session-alerts'`; подписки:
  `session/event` (все сессии, включая фоновые и субагентов — scope-диспетчеризация
  идёт вверх по цепочке, root-слушатель получает всё), `session/flush`,
  `session/disposed`, и пассивные waterfall-слушатели `approval/request` /
  `user-questions/request`: плагин уведомляет и **всегда** возвращает
  `next()` — чужой запрос не потребляется, ответ принимает настоящий UI.
- Транспорт: `execFile('osascript', ['-e', 'display notification …'])` без
  shell, `stdio: 'ignore'`, таймаут 3 с. Если в PATH есть `terminal-notifier`,
  используется он (зависимость в package.json не добавляется). Упавший
  `osascript` — только `ctx.logger.warn`, процесс DSH не падает.
- Экранирование: из текста убираются `"` и `\`, переносы строк схлопываются,
  заголовок ≤ 60, тело ≤ 200 символов.
- Плагин ничего не пишет в stdout/stderr (кадр TUI не ломается), не читает и
  не пишет `~/.dsh-tui`, не объявляет peer-зависимостей на
  `@deepseek-ai/dsh-*` (только cordis и schemastery) — предупреждения
  «incompatible with dsh …» при установке нет.
- Все таймеры чистятся при dispose (`ctx.effect`); обработчики обёрнуты в
  try/catch — сбой в любом из них логируется и не роняет процесс.
- Типы событий — структурные (`src/events.ts`), без импортов dsh-пакетов;
  сверены с `.d.ts` установленного DSH 0.2.0-rc.2.

### TUI: выключите taskNotifications

Если в TUI включены собственные нотификации задач, на завершение хода будет
два уведомления. Выключите `taskNotifications` в TUI (или `onFinish: false`
в конфиге плагина) — дублей не будет.

## Разработка и отладка

```bash
npm run build       # tsc → lib/
node --test test/   # юнит-тесты (format/limiter/notify) + интеграция на cordis
```

Отладочные env-переменные (не пишут в stdout/stderr):

- `DSH_SESSION_ALERTS_DEBUG_FILE=<path>` — JSON-строки: загрузка плагина,
  полученные события, решения о dispatch.
- `DSH_SESSION_ALERTS_CAPTURE_FILE=<path>` — только payload'ы уведомлений
  (спавн osascript отключается).
- `DSH_SESSION_ALERTS_LOG_ONLY=1` — payload'ы в память (используется тестами).
- `DSH_SESSION_ALERTS_REPLAY_MS=<ms>` — переопределение replay-окна.

## Ограничения v1

- macOS-only (osascript). На других платформах уведомления деградируют в warn.
- Нет клика по уведомлению (с `terminal-notifier` клик открывает… ничего —
  v1 без web-клиента и inbound-действий).
- `quietWhenFocused` не реализован: из host-процесса фокус терминала надёжно
  не определяется без Accessibility.
- Копии в профилях ссылаются на каталог исходников (`file:`), не на
  опубликованный tarball.
