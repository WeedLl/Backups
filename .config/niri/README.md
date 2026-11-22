# niri: конфиг рабочего стола

Живая конфигурация niri (`niri 26.04`, Wayland, CachyOS) и оболочки Noctalia.
Здесь же — скрипт, который при автологине SDDM сразу закрывает сессию локскрином
Noctalia, чтобы экран входа выглядел как лок, а не как гриттер с аватарками.

Копия каталога лежит в репозитории `~/Documents/ForSys/Backup/.config/niri` и
синхронизируется функциями `backup_mySysFile niri`, `unload_mySysFile niri`,
`diff_mySysFile niri`. Настройки Noctalia — отдельный компонент
`noctalia-state` (см. ниже).

## Переустановка на чистую систему

Порядок важен: пакеты → репозиторий и конфиги → ключ хранилища → автологин →
ребут. Если включить автологин раньше, первый вход случится в полупустую сессию;
если не создать ключ, Noctalia стартует без него и не сохраняет историю.

### 1. Пакеты

```bash
sudo pacman -S niri noctalia kitty alacritty wl-clipboard zsh \
               gnome-keyring sddm xdg-desktop-portal-gnome
```

`niri` и `noctalia` есть в CachyOS-репозитории. `kitty` — терминал на
`Mod+Return`, `alacritty` — альтернатива, `wl-clipboard` — буфер в Wayland,
`gnome-keyring` — Secret Service, `sddm` — вход в систему.

### 2. Репозиторий и конфиги

Путь должен быть ровно `~/Documents/ForSys/Backup`: он зашит в
`backup_mySysFile`, `unload_mySysFile`, `diff_mySysFile` и в примеры `dsh_backup`.

```bash
git clone git@github.com:WeedLl/Backups.git ~/Documents/ForSys/Backup
# если SSH-ключа на новой машине ещё нет:
#   git clone https://github.com/WeedLl/Backups.git ~/Documents/ForSys/Backup
git -C ~/Documents/ForSys/Backup switch linux

# функции ещё не восстановлены — подгружаем прямо из репозитория
for f in backup unload diff; do
  source ~/Documents/ForSys/Backup/.zsh_MyFunctions/${f}_mySysFile.zsh
done

unload_mySysFile niri noctalia noctalia-state
diff_mySysFile niri noctalia noctalia-state   # ожидаем «Различий нет»
```

| Компонент | Из репозитория | Куда |
|---|---|---|
| `niri` | `.config/niri/` | `~/.config/niri/` (включая `scripts/autolock-on-boot.sh`) |
| `noctalia` | `.config/noctalia/` | `~/.config/noctalia/` |
| `noctalia-state` | `.local/state/noctalia/settings.toml` | `~/.local/state/noctalia/settings.toml` |

### 3. Автологин SDDM (root)

```bash
sudo install -Dm644 /dev/stdin /etc/sddm.conf.d/10-autologin.conf <<'EOF'
[Autologin]
User=weed
Session=niri
Relogin=false
EOF
```

`Session` — имя файла сессии без `.desktop`
(`/usr/share/wayland-sessions/niri.desktop` → `niri`), `User` — твой логин. Без
этого файла авто-лок не сработает (скрипт проверяет его наличие), а вход
останется через гриттер.

### 4. Ключ хранилища Noctalia

`settings.toml` из репозитория ссылается на
`~/.local/state/noctalia/storage.key`, но самого ключа в git нет — это секрет.
Новый ключ (история начнётся с нуля):

```bash
install -d -m700 ~/.local/state/noctalia
od -An -tx1 -N32 /dev/urandom | tr -d ' \n' > ~/.local/state/noctalia/storage.key
printf '\n' >> ~/.local/state/noctalia/storage.key
chmod 600 ~/.local/state/noctalia/storage.key
```

Формат строгий: **ровно 64 символа hex** (32 байта). На base64 или другой длине
Noctalia пишет `storage key file must contain one 64-character lowercase
hexadecimal key` и не сохраняет историю.

Перенос истории: скопировать со старой машины `storage.key` **и**
`notification_history.enc` (плюс `clipboard/`, если нужна история буфера). Без
того же ключа эти файлы не расшифруются.

### 5. Проверки перед ребутом

```bash
niri validate
sh -n ~/.config/niri/scripts/autolock-on-boot.sh
noctalia config validate
```

### 6. После ребута — чек-лист

1. Гриттера нет, экран сразу закрыт локскрином Noctalia.
2. Пароль спросили один раз — на локе. Второго запроса (ключницы) быть не должно.
3. `cat ~/.cache/niri-autolock-boot` — `boot_id` текущей загрузки.
4. `noctalia config export | grep -A2 '^\[storage\]'` → `key_source = "file"`.
5. `notify-send test test` → `~/.local/state/noctalia/notification_history.enc`
   обновился по времени и размеру.
6. `logout` → гриттер SDDM: это норма, автологин один раз за загрузку.

Если п.1 не сработал — проверить `Session` в дроп-ине (`sddm` пишет выбранную
сессию в journal). Если п.2 дал запрос ключницы — значит `[storage]` не в
`settings.toml`: в `~/.config/noctalia/config.toml` этот раздел не читается.

### 7. Что не переносится

| Что | Почему |
|---|---|
| `~/.local/state/noctalia/storage.key` | секрет и машинная привязка; в git не кладём |
| `~/.cache/niri-autolock-boot` | маркер загрузки, создаётся сам при первом локе |
| `~/.dsh/.credentials.yaml` | секреты DSH, только через `dsh_backup -s` |

### 8. Обновление на рабочей машине

```bash
backup_mySysFile niri noctalia noctalia-state
diff_mySysFile niri noctalia noctalia-state
cd ~/Documents/ForSys/Backup && git add -A && git commit -m "niri/noctalia: ..."
```

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

Один файл, он не в репозитории (root-овое живёт в `/etc`) — см. шаг 2
«Переустановки»:

```ini
[Autologin]
User=weed
Session=niri
Relogin=false
```

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
- **Keyring.** Автологин не даёт PAM пароль, поэтому `login.keyring` остаётся
  заблокированным. Чтобы Noctalia не просила пароль ключницы при старте, её
  хранилище переведено на файловый ключ: `[storage] key_source = "file"` и
  `key_file = "~/.local/state/noctalia/storage.key"` в state-`settings.toml`.
  Остальные программы (`pgcli`, git-креды) попросят пароль ключницы только при
  реальном обращении к секретам.
- **`logout`** возвращает в SDDM: автологин срабатывает один раз за загрузку.
- **Диск не зашифрован**, так что автологин почти не меняет модель физической
  безопасности: лок остаётся локом, а не границей доверия.

## Тесты скрипта

Скрипт можно прогнать без блокировки экрана: пути и команда `noctalia`
подменяются через `PATH` и переменные `NIRI_AUTOLOCK_CONF` /
`NIRI_AUTOLOCK_MARKER`. Проверяются четыре случая: нет дроп-ина автологина,
ретраи до готовности IPC, повторный запуск в ту же загрузку и таймаут.
