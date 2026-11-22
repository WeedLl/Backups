# niri: конфиг рабочего стола

Живая конфигурация niri (`niri 26.04`, Wayland, CachyOS) и оболочки Noctalia.
Здесь же — скрипт, который при автологине SDDM сразу закрывает сессию локскрином
Noctalia, чтобы экран входа выглядел как лок, а не как гриттер с аватарками.

Копия каталога лежит в репозитории `~/Documents/ForSys/Backup/.config/niri` и
синхронизируется функциями `backup_mySysFile niri`, `unload_mySysFile niri`,
`diff_mySysFile niri`.

## Состав

| Путь | Что это |
|---|---|
| `config.kdl` | точка входа: только `include` остальных файлов |
| `cfg/autostart.kdl` | что запускается при старте: `noctalia` и авто-лок |
| `cfg/keybinds.kdl` | все сочетания, `Mod` = Super; лок — `Mod+Alt+L` |
| `cfg/input.kdl` | раскладки `us,ru`, CapsLock → Ctrl, переключение Alt+Shift, тачпад |
| `cfg/layout.kdl` | gaps 8, пресеты ширины колонок, прозрачный фон под обои Noctalia |
| `cfg/rules.kdl` | радиус 10, opacity 0.94, blur, правила для Noctalia и Steam |
| `cfg/animation.kdl` | пружины и длительности анимаций |
| `cfg/display.kdl` | шаблон `output`, закомментирован `/-` |
| `cfg/misc.kdl` | окружение Qt/Electron под Wayland, курсор, blur композитора |
| `noctalia.kdl` | цвета focus-ring/border/tab-indicator под Gruvbox |
| `scripts/autolock-on-boot.sh` | лок Noctalia при первом входе после загрузки |

## Зачем ставить на другой машине

- Конфиг описывает привычную среду целиком: раскладка с CapsLock как Ctrl,
  vim-like фокус `Mod+hjkl`, workspace на `Mod+Alt+J/K`, floating на
  `Mod+Ctrl+Alt+hjkl`, скриншоты на `Mod+Print`.
- Без `cfg/layout.kdl` с `background-color "transparent"` Noctalia не покажет обои:
  композитор закрасит фон сам.
- Без `cfg/misc.kdl` Qt/Electron-приложения уйдут в X11-фолбэк, а курсор будет
  системным, не `capitaine-cursors`.
- Авто-лок имеет смысл только вместе с автологином SDDM: без автологина пароль
  вводится в гриттере, и немедленный лок был бы вторым вводом пароля подряд.

Порядок переноса: скопировать каталог в `~/.config/niri`, прогнать
`niri validate`, при необходимости — автологин (ниже), затем `systemctl reboot`.

## Автологин SDDM + лок Noctalia

### Зачем

Стандартный SDDM показывает гриттер: список пользователей, аватарки, дефолтная
тема. Автологин убирает его совсем, а сессия сразу закрывается локскрином Noctalia
(обои, виджеты, часы). Пароль по-прежнему нужен — но один раз и на локе.

### Как работает

1. SDDM читает `/etc/sddm.conf.d/10-autologin.conf` и входит в сессию `niri` без
   гриттера (`Relogin=false`: после явного `logout` гриттер вернётся).
2. niri поднимается и по `cfg/autostart.kdl` запускает `noctalia`
   (`spawn-at-startup`) и `scripts/autolock-on-boot.sh` (`spawn-sh-at-startup`).
   Оба стартуют параллельно.
3. Скрипт выходит, если нет дроп-ина автологина: убрал файл — лок отключился.
4. Сверяет `/proc/sys/kernel/random/boot_id` с маркером
   `~/.cache/niri-autolock-boot`. Совпало — значит, в этой загрузке уже лочились
   (например, после `logout → вход`), и лок не повторяется.
5. Ждёт готовности IPC Noctalia до ~20 секунд (`noctalia msg session lock`
   в цикле по 0.2 с) — иначе лок проиграл бы гонку старта оболочки.
6. При успехе пишет `boot_id` в маркер и выходит. Тот же код висит на `Mod+Alt+L`.

### Что нужно от root

Один файл, он не в репозитории (root-овое живёт в `/etc`):

```bash
sudo install -Dm644 /tmp/10-autologin.conf /etc/sddm.conf.d/10-autologin.conf
```

```ini
[Autologin]
User=weed
Session=niri
Relogin=false
```

`Session` — имя файла сессии без `.desktop`
(`/usr/share/wayland-sessions/niri.desktop` → `niri`).

### Проверка

```bash
sh -n ~/.config/niri/scripts/autolock-on-boot.sh
niri validate
noctalia msg session lock        # или Mod+Alt+L: экран должен закрыться
cat ~/.cache/niri-autolock-boot  # boot_id текущей загрузки
```

Признак успеха после ребута: гриттера нет, сразу локскрин Noctalia, после
разблокировки — обычный рабочий стол. Если после ребута видно гриттер — SDDM не
нашёл сессию, проверить значение `Session`.

### Откат

```bash
sudo rm /etc/sddm.conf.d/10-autologin.conf
```

Этого достаточно: скрипт проверяет наличие файла и больше не лочится. Полный
откат — убрать строку `spawn-sh-at-startup` из `cfg/autostart.kdl`.

### Нюансы

- **1–2 секунды до лока.** Локскрин живёт внутри Noctalia, а оболочка стартует
  после композитора. В это время видно только фон/обои, окна не мелькают.
- **Keyring.** При автологине PAM не получает пароль, поэтому `login.keyring`
  остаётся заблокированным: `pgcli`, git-креды и `secret-tool` могут спросить
  пароль ключницы. Для Noctalia это заметнее: ключ её хранилища берётся из Secret
  Service (`[storage] key_source = "secret-service"`), поэтому история уведомлений
  (`~/.local/state/noctalia/notification_history.enc`) и буфер обмена могут не
  открыться до разблокировки. Варианты: разблокировать ключницу вручную раз за
  загрузку, либо перевести `storage.key_source` на `file` с `key_file` в
  `~/.local/state/noctalia` (ключ на диске; диск всё равно не шифрован).
- **`logout`** возвращает в SDDM: автологин срабатывает один раз за загрузку.
- **Диск не зашифрован**, так что автологин почти не меняет модель физической
  безопасности: лок остаётся локом, а не границей доверия.

## Тесты скрипта

Скрипт можно прогнать без блокировки экрана: пути и команда `noctalia`
подменяются через `PATH` и переменные `NIRI_AUTOLOCK_CONF` /
`NIRI_AUTOLOCK_MARKER`. Проверяются четыре случая: нет дроп-ина автологина,
ретраи до готовности IPC, повторный запуск в ту же загрузку и таймаут.
