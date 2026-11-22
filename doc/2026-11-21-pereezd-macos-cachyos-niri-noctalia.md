---
tags:
  - sys
  - sys/app
type: guide
source: by_ai
created: 2026-11-21
---
# Переезд с macOS на CachyOS + niri + Noctalia: правила и журнал

> [!abstract] TL;DR
> Переезжаем не «с мака на линукс» вообще, а переносим конкретные привычки и конфиги в CachyOS + niri + Noctalia, попутно вычищая macOS-специфику.
> Приоритет решений: сначала родной инструмент CachyOS/Arch, потом общелинуксовый, и только если это дёшево — ветка совместимости с macOS.
> Текущее состояние: DSH восстановлен, `dsh_backup` портирован, плагины проверены; niri/Noctalia, kitty/alacritty, nvim и mimeapps/XDG настроены; репозиторий разделён на ветки `macos` и `linux`.
> В конце файла — «Что уже сделано» и «Нюансы и грабли»; следующая сессия должна начинать с них.

## Содержание
- [[#Цель и принципы]]
- [[#Среда]]
- [[#Правила портирования]]
- [[#Чек-лист mac-изма]]
- [[#Карта компонентов]]
- [[#Функции zsh]]
- [[#DSH]]
- [[#Git: ветки и синхронизация]]
- [[#Проверки]]
- [[#Что не покрыто]]
- [[#Предложения]]
- [[#Что дальше]]
- [[#Nvim: аудит]]
- [[#Ошибки, актуальные и для macOS]]
- [[#Напоминалка: клавиши]]
- [[#Напоминалка для ветки macos]]
- [[#Что уже сделано]]
- [[#Нюансы и грабли]]

## Цель и принципы

- **Целевая система:** CachyOS (Arch-based), Wayland, композитор niri, оболочка Noctalia.
- **Приоритет портирования:** CachyOS/Arch → Linux в целом → кроссплатформенность. Если Linux-путь проще и надёжнее, macOS-ветку не тащим.
- **Переносим смысл, а не клавиши.** `Cmd` на маке и `Super` на niri — разные слои; сначала проверяем, не занял ли биндинг композитор.
- **Никаких жёстких `/Users/...` и `/opt/homebrew/...`** в новых правках: только `$HOME`, XDG-каталоги и `command -v`.
- **Платформенная развилка — только если она дешёвая.** Один `if` по `process.platform` или `uname -s` допустим; две полноценные копии скрипта — нет.
- **Каждый mac-изм получает запись** в разделах «Что уже сделано» и «Нюансы», иначе следующая сессия повторит работу.
- **Ветка `macos` — архив, а не рабочая.** Все новые правки идут в `linux`; `master` удалён и не воссоздаётся.

> [!note] Сопутствующий аудит
> Подробный разбор конфигов, раскладки, терминалов, niri/Noctalia и зеркал лежит в `~/Documents/2026-11-21-konfigi-backup-cachyos.md`. Этот файл — процесс и журнал, а не замена аудиту.

## Среда

| Что | Значение |
|---|---|
| ОС | CachyOS Linux, `ID_LIKE=arch`, ядро `7.3.5-2-cachyos` |
| Композитор | niri `26.04-1.1`, запуск через SDDM (`niri.desktop`) |
| Оболочка | Noctalia `5.6.0-1.1`, бинарь `noctalia`, конфиг `~/.config/noctalia/` |
| Конфиг niri | `~/.config/niri/config.kdl` |
| Сессия | Wayland, `XDG_CURRENT_DESKTOP=niri`, `XDG_SESSION_TYPE=wayland`, `WAYLAND_DISPLAY=wayland-1` |
| D-Bus | сессионная шина есть; `notify-send` 0.8.9 доставляет уведомления |
| Secret Service | `gnome-keyring-daemon` запущен с компонентами `pkcs11,secrets` |
| Shell | zsh 5.9.2, oh-my-zsh из `/usr/share/oh-my-zsh` |
| DSH | ядро `0.2.2-rc.5`, TUI `0.20.2` |
| Терминалы | kitty `0.51.0`, alacritty `0.17.0` |
| Буфер обмена | `wl-copy`/`wl-paste` есть; `xclip`, `xsel`, `tmux` пока не установлены |
| Хеши | `sha256sum` (coreutils), `shasum` из `core_perl` |
| Obsidian | реестр `~/.config/obsidian/obsidian.json` отсутствует |

> [!tip] Быстрая проверка среды
> ```bash
> niri --version; noctalia --version
> echo "$XDG_CURRENT_DESKTOP/$XDG_SESSION_TYPE"
> command -v notify-send wl-copy sha256sum shasum nvim
> notify-send -a DSH "проверка" "Noctalia принимает уведомления"
> ```

## Правила портирования

| macOS | CachyOS / Arch / Linux | Нюанс |
|---|---|---|
| `/Users/<user>/...` | `$HOME/...` | В `package.json` и `pnpm-lock.yaml` пути `file:/Users/...` нужно переписать до `pnpm install` |
| `/opt/homebrew/bin/...` | `/usr/bin/...` | Пакеты ставятся `pacman`/`paru`, а не brew |
| `brew install` | `pacman -S` / `paru -S` | Проверять имя пакета в репозитории, а не угадывать |
| `osascript display notification` | `notify-send` | Нужны D-Bus и демон уведомлений (Noctalia) |
| `terminal-notifier` | `notify-send` | На Linux нет звука и действия по клику |
| `pbcopy` / `pbpaste` | `wl-copy` / `wl-paste` | Wayland; `xclip`/`xsel` — только X11-фолбэк |
| `open`, `open -a` | `xdg-open`, `gtk-launch` | Проверять `.desktop`-файл |
| `launchctl`, LaunchAgents | `systemctl --user` | Юниты в `~/.config/systemd/user/` |
| `defaults write` | конфиг-файл, `gsettings`, `dconf` | У каждой программы свой формат |
| `Cmd+...` | `Super+...` | niri уже занимает `Super+T/D/W/1..9/HJKL/[/]` — проверять `niri msg` и конфиг |
| `screencapture` | `grim` + `slurp` | В niri есть свои `Print`-биндинги и `screenshot-path` |
| `security` (Keychain) | Secret Service | gnome-keyring, KWallet или KeePassXC |
| `say`, `afplay` | `spd-say`, `paplay` | Для уведомлений обычно не нужно |
| `diskutil` | `lsblk`, `udisksctl` | Монтирование — через udisks2 |
| `sed -i ''` | `sed -i` | BSD и GNU `sed` по-разному принимают суффикс |
| `stat -f` | `stat -c` | Разные наборы форматов |
| `date -r <file>` | `date -d @<epoch>` | GNU `date` не понимает BSD-форму |
| `md5` | `md5sum` | Для целостности лучше `sha256sum` |
| `shasum -a 256` | `sha256sum` | `shasum` на Arch есть, но тянет perl; в новом коде — `sha256sum` с фолбэком |
| BSD `cp -n` (exit 1) | GNU `cp -n` (exit 0) | Не полагаться на код возврата при merge-копировании |
| `plutil` | `jq`, `yq` | Проверять, что JSON/YAML действительно валиден |

### Где ломается чаще всего

- **Абсолютные пути в зависимостях.** `file:`-зависимости DSH и `pnpm-lock.yaml` хранят и абсолютный specifier, и относительный `version:`. После смены `$HOME` их надо переписать и переустановить пакеты.
- **Сборка TypeScript-плагинов.** `lib/` обычно в `.gitignore`; после чистого клонирования плагин не загрузится, пока не выполнить `npm run build`.
- **`npm` без dev-зависимостей.** На этой машине глобально стоит `omit=dev`, поэтому сборка плагина требует `npm ci --include=dev`.
- **Уведомления.** `osascript` на Linux отсутствует; `notify-send` требует сессионную D-Bus и демон уведомлений. Без них плагин не падает, но пишет warning.
- **Буфер обмена.** X11-утилиты в Wayland-сессии не работают; нужен `wl-clipboard`, а в приложениях — OSC 52 или явный `wl-copy`.
- **Клавиши.** Мак-привычки `Cmd+*` превращаются в `Super+*`, но часть занята niri; конфликт решается настройкой композитора, а не правкой конфига терминала.
- **`shasum`.** Он есть на Arch через `perl`, но это не гарантия для минимальных систем; в переносимом коде — `sha256sum`, иначе `shasum`.
- **pnpm и hardlink'и.** Файлы `file:`-плагина в профиле могут быть жёсткими ссылками на исходник. Пересборка `lib/` меняет и установленную копию, но уже запущенный процесс TUI держит старый модуль в памяти до перезапуска.

> [!warning] Не тащить macOS-ветку «на всякий случай»
> Если Linux-путь очевиден (`notify-send`, `wl-copy`, `systemctl --user`), оставлять мёртвый `osascript`-код не нужно. Исключение — код, который реально живёт на двух платформах и ветвление стоит одну строку.

## Чек-лист mac-изма

1. **Найти.** Пройтись по конфигам, функциям и плагинам поиском:
   ```bash
   grep -rnE '/Users/|/opt/homebrew|osascript|terminal-notifier|pbcopy|pbpaste|launchctl|/Applications|open -a|afplay|screencapture|stat -f|date -r' \
     ~/.zsh_MyFunctions ~/.config ~/Documents/ForSys/Backup/my_files/DSH 2>/dev/null
   ```
2. **Классифицировать.** Это путь, системный API, утилита, клавиша или формат файла?
3. **Найти родной аналог.** Таблица выше; при сомнении — `pacman -Ss`, `man`, `--help`.
4. **Решить, нужна ли macOS-ветка.** Если да — один `if` по `uname -s` / `process.platform`; если нет — Linux-only.
5. **Убрать хардкод.** `$HOME`, `XDG_CONFIG_HOME`, `XDG_STATE_HOME`, `command -v`.
6. **Проверить.** Синтаксис (`zsh -n`, `niri validate`, `node --check`), композиция (`dsh --profile <p> --dump-config`), тесты, реальное уведомление/буфер.
7. **Записать.** Добавить пункт в «Что уже сделано» и, если остался риск, в «Нюансы и грабли».

> [!example] Пример безопасной развилки
> ```js
> const command = process.platform === 'linux' ? 'notify-send' : 'osascript'
> const args = process.platform === 'linux'
>   ? ['-a', 'DSH', title, body]
>   : ['-e', `display notification "${body}" with title "${title}"`]
> ```
> Ветка выбирается в одном месте, тесты фиксируют обе.

## Карта компонентов

| Компонент | Где | Состояние |
|---|---|---|
| `.zshrc` | `~/` | Портирован: omz из `/usr/share`, brew, venv, `ZSH_CUSTOM`; PATH `venv → brew → local → system`, FPATH `функции → brew`; `fzf-tab 1.3.0-2` установлен; `stty -ixon` для префикса tmux |
| `.bash_profile` | `~/` | Портирован: source `.bashrc`, brew, venv, `prepend_path`; PATH `venv → brew → local`; без mac-путей |
| `.zsh_MyFunctions` | `~/` | Проверены и исправлены; live-копия синхронизирована с репозиторием |
| Git | `~/.gitconfig` | `core.editor` и `difftool.shvimdiff` переведены на `/usr/bin/nvim`; цвета lazygit сохранены; `credential.helper`/подпись не проверялись |
| Neovim | `~/.config/nvim` | Добавлены niri-backend раскладки и `python3_host_prog` на `~/.global_venv`; clipboard/spell/ruff/stylua и tracked-мусор — отдельно |
| Vim | `~/.vimrc` | Исправлен: GUI-опции только для GUI, `language en_US.utf8`, vim-plug под проверкой, `colorscheme` через `silent!`, spell без ошибки при отсутствии `ru` |
| IdeaVim | `~/.ideavimrc` | Переписан в минимальный IdeaVim-совместимый вид: без vim-plug/`Plug`, NERDTree, `:language`, GUI-опций |
| alacritty | `~/.config/alacritty/` | Визуально и по общим клавишам выровнен под kitty: padding 3, 130x40, opacity убран, `Ctrl+Shift+PageUp/Down`, `Ctrl+Shift+=/-/0`, `Ctrl+Shift+N/Q`; шрифты сохранены. Вкладок/сплитов нет — через tmux |
| kitty | `~/.config/kitty/` | Vim-first: `hjkl` фокус, `Alt+hjkl` перемещение, стрелки — ресайз; вкладки `,/.`, перенос `Alt+,/.`; W — вкладка, Q — окно; `kitty_grab` установлен |
| niri | `~/.config/niri/` | Установлен, сессия работает; конфиг в бэкапе (`.config/niri/`), `niri validate` перед изменениями |
| Noctalia | `~/.config/noctalia/` | Установлена; конфиг в бэкапе; `full_config.toml` применять вручную |
| AeroSpace | `.config/aerospace/aerospace.toml` | Удалён как лишний: niri заменяет его, конфиг не переносится |
| btop | `~/.config/btop/btop.conf` | Тема переведена на `/usr/share/btop/themes/gruvbox_dark.theme`; live и repo синхронны |
| tmux | `~/.config/tmux/tmux.conf` | `default-terminal tmux-256color`, `set-clipboard on`; `stty -ixon` в `.zshrc`; tmux пока не установлен |
| yazi / treemd | `~/.config/yazi`, `~/.config/treemd` | Конфиги кроссплатформенные; `treemd` установлен |
| lazygit / pgcli / psql / mycli | `~/.config/...` | mac-путей нет; live-каталоги mycli/pgcli/psql отсутствуют; у mycli путь `~/.myclirc` — отдельный нюанс |
| DSH | `~/.dsh`, `~/.dsh-tui` | Восстановлен из mac-бэкапа, см. ниже |
| Obsidian | — | Реестра нет; `md-answer` не найдёт хранилище без `OBSIDIAN_VAULT` |
| Приложения | `my_files/Apps.md` | Замены mac-only приложений — в аудите |

## Функции zsh

Проверены на CachyOS; live-копия в `~/.zsh_MyFunctions` синхронизирована, изменения закоммичены в `linux`.

| Функция | Что проверено и исправлено |
|---|---|
| `backup_mySysFile` | Каталоги копировались как `dst/src` при существующем `dst` — теперь `cp -R src/. dst/`. Убран `aerospace`, `cat` заменён на `command cat`, ошибки `cp` больше не маскируются |
| `unload_mySysFile` | Тот же баг вложенности; `aerospace` вёл в `/.config/...` (потерян `~`), `treemd` копировал файл сам в себя (не было `:dst`). Исправлено, «Восстановлено» печатается только при успехе |
| `diff_mySysFile` | `nvim` берётся из PATH вместо `/opt/homebrew/bin/nvim`; добавлен отчёт «нет ни там, ни там»; `aerospace` убран; режим `diff` проверен с фейковым nvim |
| `gdbranch` | `target_given` не выставлялся: `gdbranch base target` всегда сравнивал рабочее дерево. Исправлено; `-f` без значения даёт ошибку |
| `y` | `mktemp -t` заменён на `${TMPDIR:-/tmp}/...`; добавлена проверка `yazi`; cwd-файл проверен фейковым yazi |
| `vault_merge` | mac-специфики нет; простой merge двух временных хранилищ прошёл; конфликты требуют nvim и вручную не тестировались |
| `dsh_backup` | Dry-run старого бэкапа: 55 сумм, миграция путей, очистка `resume.txt` — ок |
| Комплишены | `_dsh_backup`: добавлены `-L/--skip-locks`, `--help`; `_DiffBackupUnload`: `--help` вместо `--Help`, `aerospace` убран; `_gbranch` без изменений |

> [!warning] `unload_mySysFile all/zsh` — только на копии
> Репозиторий уже Linux-ориентирован, но `all` перезаписывает live `.config`; перед запуском проверить diff и делать на временном HOME. `zshf` безопасен.

> [!note] Что не запускалось
> `backup_mySysFile all` не запускал, чтобы не перезаписывать репозиторий живыми конфигами: копирование проверено на временных каталогах. `unload_mySysFile all` тоже не запускался — только `zshf`.

Проверка путей на этой машине: `~/Documents/ForSys/Backup`, `~/.zsh_MyFunctions`, `~/.dsh`, `~/.dsh-tui` существуют. Нет `.config/neovide`, `.config/psql`, `.config/pgcli`, `.config/mycli`, `.config/tmux`, `.vim/UltiSnips`; `.vimrc`, `.ideavimrc`, `.config/alacritty` есть. `treemd` установлен. У `mycli` на Linux ожидается `~/.myclirc`, а функции используют `~/.config/mycli/.myclirc` — при установке mycli это надо учесть.

## DSH

### Пути и версии

- Ядро: `~/.dsh`, состояние TUI: `~/.dsh-tui`.
- Профили: `headless`, `tui`, `web`.
- Бэкап-источник: `my_files/DSH/dsh-backup-20261118-165930` (снят на macOS: DSH `0.2.2-rc.1`, TUI `0.19.0`).
- Сейчас: DSH `0.2.2-rc.5`, TUI `0.20.2`.
- Сессии и секреты в бэкапе отсутствовали; `~/.dsh/.credentials.yaml` не трогали.

### Что восстановлено

- 3 профиля, 14 файлов состояния TUI, 26 файлов скиллов (`dsh-update`, `md-answer_skill`).
- Пути `file:/Users/weed/...` переписаны на `$HOME/...`.
- `resume.txt` очищен: сессии из бэкапа на этой машине нет.
- Отсутствующий `dsh-tui-pkg-ru` удалён из `tui`; TUI поднят до `0.20.2`.
- `.dsh-backup-pre-restore-20261121-221736` — страховка до разгрузки, не удалять без нужды.

### `dsh_backup`

Функция установлена в `~/.zsh_MyFunctions/dsh_backup.zsh`, изменения лежат в ветке `linux`.

- Хешер выбирается сам: `sha256sum` → фолбэк `shasum`.
- При разгрузке `file:/Users/<user>/...` переписывается на `$HOME/...`, если `/Users` отсутствует.
- `resume.txt` чистится, если сессии нет; `.DS_Store` и `._*` выбрасываются.
- В манифесте появились `os:`, `home:`, `home-files:`, `checksums:`.
- Новый флаг `-L/--skip-locks` — не восстанавливать `pnpm-lock.yaml`.
- Страховка перед разгрузкой включает домашний слой и `credentials.yaml`.
- Отсутствующие `file:`-источники перечисляются, но не ломают разгрузку.
- Примеры в `-h` всё ещё указывают на `~/Documents/ForSys/Backup` — пути намеренно не менялись.

### Плагины

| Плагин | Статус |
|---|---|
| `dsh-session-alerts` | Исправлен: на Linux транспорт `notify-send`, тесты 42/42. В установленных копиях профилей уже лежит новый `lib/` (pnpm hardlink), но текущий процесс TUI держит старый модуль до перезапуска |
| `dsh-session-delete` | Работает: `DSH_HOME`/`homedir`, тесты 63/63 |
| `dsh-tui-workspace-sidebar` 0.1.5 | Работает; буфер через `wl-copy`, SSH-сессии пропускаются |
| `dsh-fact-check` 1.5.2 | Работает; `doctor` видит Linux, curl/python; нет опциональных `whois`/`zstandard` и ключа API |
| `dsh-cost-meter` 1.9.46 | Работает; блокировки через `/proc` |
| `dsh-ctl` 0.1.1 | Автозапуск только Windows; на Linux возможность отсутствует по замыслу |
| `dsh-at-file` 0.6.3 | Несовместим с ядром `0.2.2-rc.5`: нет экспорта `settingsNamespace`. 0.7.0 тоже падает: `ctx.settings.register is not a function`. Оставлен как есть по решению |
| `dsh-tui-pkg-ru` | Исходников нет ни в бэкапе, ни на диске; из `tui` удалён |

### Как активировать исправления

```bash
# пересобрать локальный TS-плагин (если lib/ потерян)
cd ~/Documents/ForSys/Backup/my_files/DSH/dsh-session-alerts-plagin
npm ci --include=dev
npm run build
npm test

# переустановить плагины в профили (если копии не обновились)
dsh plugin --profile tui install --force
dsh plugin --profile headless install --force
dsh plugin --profile web install --force
```

После этого перезапустить TUI: текущая сессия продолжает работать на старом коде.

## Git: ветки и синхронизация

Репозиторий: `~/Documents/ForSys/Backup`. Рабочая ветка — `linux`.

| Ветка | Где | Состояние |
|---|---|---|
| `macos` | локально + `origin` | Чистый мак-снимок `6d52314`; default branch на GitHub |
| `linux` | локально + `origin` | 5 коммитов: `02b1326`, `161dfdf`, `defe658`, `0c9018c`, `451f153`; впереди origin на 4 |
| `master` | — | Удалён на GitHub; не воссоздавать |
| `min` | `origin` | Старая ветка, не трогали |

Рабочее дерево чистое. Ветка `linux` впереди `origin/linux` на 4 коммита; последний — `451f153`. Документ, который ты читаешь, лежит в `~/Documents/ForSys/Backup/doc/2026-11-21-pereezd-macos-cachyos-niri-noctalia.md` и входит в репозиторий.

> [!danger] Не пушить `master`
> `git push origin master` заново создаст удалённую ветку и снова сделает её кандидатом в default. Если это случилось — сначала вернуть default на `macos`, потом удалять.

Другой ПК, где ещё `master`:

```bash
cd /путь/к/Backup
git stash -u                 # если есть незакоммиченные правки
git fetch --prune
git remote set-head origin -a
git switch -c macos --track origin/macos
git branch -d master         # если в master нет своих коммитов
```

Если `master` не сливается, сначала проверить `git log --oneline macos..master`.

Чтобы получить `linux` на другом ПК, сначала здесь:

```bash
git commit -m "linux: dsh_backup + notify-send + миграция"
git push -u origin linux
```

потом там: `git fetch && git switch linux`.

## Проверки

```bash
# синтаксис функции
zsh -n ~/.zsh_MyFunctions/dsh_backup.zsh

# композиция профилей (exit 0; у tui допустимы два warning про tool-ralph)
for p in tui headless web; do dsh --profile "$p" --dump-config >/dev/null; done

# плагины профилей
dsh plugin --profile tui list
dsh plugin --profile headless list
dsh plugin --profile web list

# тесты локальных плагинов
(cd my_files/DSH/dsh-session-alerts-plagin && npm test)
(cd my_files/DSH/dsh-session-delete-plagin && npm test)

# уведомления и буфер
notify-send -a DSH "DSH · тест" "Linux-транспорт"
printf test | wl-copy && wl-paste

# перед коммитом
git diff --cached --check
git status
```

Ожидаемые известные предупреждения:

- `dsh --profile tui --dump-config`: `patch: entry "tool-ralph" not found` и `tool-subagent-list-agents` — это патчи самого TUI 0.20.2, не наши плагины.
- `dsh --profile web --help`: `dsh-at-file` не активируется из-за несовместимости с ядром.
- `md-answer`/`tags.mjs`: нет Obsidian-реестра, поэтому автопоиск хранилища не работает.

## Что не покрыто

- **Секреты и ключи.** SSH (`~/.ssh`), GPG, git credential helper, GitHub-аутентификация, `~/.dsh/.credentials.yaml`, `pgcli`/`mycli` keyring. Их перенос — отдельная задача, в этот документ не входит.
- **Личные данные.** `~/Documents`, `~/Pictures`, закладки браузеров, базы PostgreSQL (нужен логический дамп, а не копия каталога).
- **Рабочее окружение niri/Noctalia.** Аудио (PipeWire), Bluetooth, печать, управление питанием, шрифты и методы ввода. Аудит частично покрывает раскладку и шрифты, но не эти подсистемы.
- **Резервное копирование Linux.** Чем и куда бэкапить `~/.config`, `~/.dsh`, `~/Documents` (restic/borg/внешний диск); политика хранения и проверка восстановления.

## Предложения

- **Этот файл уже в репозитории:** `Backup/doc/2026-11-21-pereezd-macos-cachyos-niri-noctalia.md`; он попадёт на другой ПК вместе с веткой `linux`.
- **Добавить `scripts/check-mac-isms.sh`** с грепом из чек-листа и прогонять перед коммитом; это дешевле, чем ловить `/opt/homebrew` в рантайме.
- **Пометить `macos` тегом** (`git tag macos-2026-11-18`) и не коммитить в неё; ветка должна оставаться неизменным снимком.
- **Не копировать папку целиком для экспериментов**, а использовать `git worktree`: у нас уже был лишний `BackupLinux`, который пришлось удалять.
- **Пушить `linux` раньше**, чем накопится много изменений: другой ПК не увидит ветку, пока она локальная.
- **Разделить документы:** аудит конфигов — отдельно, живой журнал/правила — этот файл; не дублировать таблицы.
- **Добавить мини-`doctor` для niri/Noctalia**: `notify-send`, `wl-copy`, `gnome-keyring`, `niri validate`, `noctalia` в процессах.
- **Секреты не коммитить.** `dsh_backup -s` кладёт `credentials.yaml` только в бэкап с режимом 600; в git ему не место.

## Что дальше

> [!todo] Ближайшие шаги
> - Перезапустить TUI и проверить реальное уведомление от завершённого хода.
> - `dsh-at-file` — ждём совместимую версию, пока не трогать.
> - Настроить Obsidian-реестр или задать `OBSIDIAN_VAULT`.
> - Запушить `linux` (4 коммита) и обновить другой ПК.
>

- Проверить `tmux`, `xclip`/`xsel` только если они реально нужны; для Wayland базовый вариант — `wl-clipboard`.
- Конфиги niri/noctalia, kitty/alacritty, mimeapps/XDG и nvim уже Linux; при переносе проверить mycli/pgcli/psql/tmux/neovide.
- Проверить `backup_mySysFile all` на копии репозитория, а не на рабочем.
- Nvim: в реальном GUI проверить `:checkhealth`; LSP-предупреждения ленивые — исчезают после открытия файла.
- Nvim: при желании поставить TeX (`latexmk`, `bibtex`, `biber`) — vimtex включит компилятор сам.
- Решить с `mycli`: живой каталог отсутствует, на Linux он ждёт `~/.myclirc`; при установке добавить symlink или перенести файл.
- Поставить Handy: `paru -S handy-bin`; `wtype` уже установлен — проверить вставку в niri/Noctalia.
- Поставить `tmux`/`neovide`, если нужны; tmux-конфиг исправлен, neovide-конфига нет.

## Nvim: аудит

Аудит и Linux-портирование завершены; клавиши обновлены (см. ниже).

- **Раскладка — исправлено.** `lua/core/layout/niri.lua` читает `niri msg --json keyboard-layouts` и переключает через `niri msg action switch-layout <index>`. `core/layout/init.lua` на Linux сначала пробует niri, старые CLI-адаптеры остаются fallback. Проверены `get/default/list/set` и English↔Russian с возвратом.
- **Python-provider — исправлено.** В `lua/core/options.lua` задан `python3_host_prog = ~/.global_venv/bin/python` (если файл существует). Проверено в headless.
- **Mason PATH — исправлено.** `~/.local/share/nvim/mason/bin` добавлен в `vim.env.PATH`; `ruff`, `stylua`, `pyright` теперь находятся (проверено `vim.fn.executable`).
- **Treesitter — исправлено.** `tree-sitter-cli 0.26.9` установлен пакетом `tree-sitter-cli`; ручной `~/.local/bin/tree-sitter` удалён, `command -v tree-sitter` → `/usr/bin/tree-sitter`. Установлены 12 парсеров в `~/.local/share/nvim/site/parser` (python, sql, markdown, markdown_inline, lua, vim, vimdoc, bash, zsh, json, yaml, latex); они управляются `nvim-treesitter` и обновляются `:TSUpdate`. Для отсутствующего CLI в `configs/treesitter.lua` добавлено предупреждение.
- **Spell — исправлено.** В `~/.local/share/nvim/site/spell` лежат `ru.utf-8.spl`/`.sug`; `spelllang = { "ru", "en" }` работает.
- **Clipboard — проверено.** `vim.fn.setreg("+", ...)` и `getreg("+")` работают через `wl-copy`; `opt.clipboard` не задан, поэтому обычный yank не синхронизируется автоматически. Отдельного `:checkhealth clipboard` в Neovim 0.12 нет.
- **Folding — исправлено.** Fallback на `indent` теперь срабатывает и по `BufWinEnter`, поэтому файлы без filetype/парсера (`.foo`) не падают; `.py` с парсером остаётся `expr`.
- **VimTeX — исправлено под Linux.** Вместо macOS-метода `open` — `general` + `xdg-open`; компилятор включается только при наличии `latexmk` (сейчас его нет). Health даёт только предупреждения про `bibtex`/`biber`.
- **Мусор — убран.** Удалены `nvim.log`, `backup_init.vim`, `lua/configs/gruvbox.lua.backup_trueColor`; добавлен `.config/nvim/.gitignore` с `nvim.log`. `soso_key-map.jpg` оставлен как ассет.
- **`langmapper.nvim` — удалён.** Он был установлен и в lock, но нигде не подключался; `vim.pack` health больше не ругается. В lock 25 плагинов.
- **`:checkhealth` — 0 ошибок.** Остались предупреждения: необязательные языки Mason (Go/Ruby/PHP/Java/Julia/luarocks), `bibtex`/`biber`, `which-key` без `mini.icons` и 7 LSP-конфигов «not found» из-за ленивой загрузки. После открытия `.py` конфиги `pyright`/`ruff` видны, клиенты стартуют.
- **Клавиши.** `<C-m>` убран, Neo-tree/Yazi — на `<leader>n`/`<leader>y`, signature help — `<C-k>`, terminal — `<leader>t`; `C-n`/`C-y` возвращены дефолтам. Цель vim-like с дефолтами — в «Напоминалке: клавиши».

## Ошибки, актуальные и для macOS

> [!warning] Помечено для будущей ветки macos
> Это не Linux-специфика; на Linux часть уже исправлена. В ветке `macos` те же места надо проверить/повторить.

- [ ] **alacritty:** `Ctrl+U/D/Y` перехватываются (`ScrollPageUp/Down`, `Copy`) и на маке тоже мешают shell.
- [ ] **kitty:** дубль `map cmd+w` (`close_tab`, затем `close_window`); `window_padding_height`, `unfocused_cursor_shape`, `draw_bold_text_with_bright_colors` невалидны и на маке.
- [ ] **tmux:** префикс `C-q` глушится IXON; `screen-256color` вместо `tmux-256color`; нет `set-clipboard on` — актуально и для mac.
- [ ] **mycli:** конфиг в `.config/mycli/.myclirc`, а CLI обычно читает `~/.myclirc` — проверить и на маке.
- [ ] **nvim:** `spelllang ru` — на Linux файл лежит в `site/spell`; на маке проверить/положить.
- [ ] **nvim:** folding — на Linux добавлен fallback по `BufWinEnter`; в macos-ветке повторить.
- [ ] **nvim:** tracked `nvim.log`, `backup_init.vim`, `gruvbox.lua.backup_trueColor` — на Linux удалены; в macos-ветке проверить.
- [ ] **`.ideavimrc`/`.vimrc`:** старые `plug#begin`/`Plug` без vim-plug; на маке может работать случайно, если vim-plug установлен.
- [ ] **Функции zsh:** `gdbranch`, `unload_mySysFile`, `diff_mySysFile`, комплишены — подробно в «Напоминалке для ветки macos».

## Напоминалка: клавиши

> Текущее: `Mod` = Super; cheatsheet — `Mod+F1`; launcher — `Mod+Space`; `Mod+N` — уведомления; `Mod+Shift+N` — DND; `Mod+Return` — kitty; `Mod+B` — Zen; focus — `Mod+hjkl`; move — `Mod+Shift+hjkl`; resize — `Mod+Ctrl+hjkl`; workspace — `Mod+Alt+J/K`; floating move — `Mod+Ctrl+Alt+hjkl`; floating resize — `Mod+Ctrl+Alt+Shift+hjkl`; floating/tiling focus — `Mod+V`; screenshot area/screen/window — `Mod+Print`, `Mod+Shift+Print`, `Mod+Ctrl+Print`; CapsLock = Ctrl; раскладка — Alt+Shift; gaps 8, radius 10, opacity 0.94.


> [!note] Цель
> Сделать **vim-like** набор: максимально опираться на дефолты Neovim, терминала, niri и Noctalia; кастомные сочетания добавлять только там, где они реально улучшают ощущения, а не дублируют привычное.

> [!todo] Согласовать позже
> Затрагивает alacritty, kitty, nvim, niri и Noctalia. Сначала собрать текущие биндинги в одну таблицу, затем убрать конфликты. Пока не менять вслепую.

- [x] **alacritty:** `Ctrl+U/D/Y` убраны; scroll — `Ctrl+Shift+PageUp/Down`, zoom — `Ctrl+Shift+=/-/0`, new window — `Ctrl+Shift+N`, quit — `Ctrl+Shift+Q`.
- [x] **kitty:** неизвестные ключи убраны; `cmd+...` переведены на `Ctrl+Shift`, дубль `cmd+w` исправлен, `kitty_grab` установлен.
- [x] **niri:** занятые `Super+...` зафиксированы; терминалы используют `Ctrl+Shift`, nvim — `Ctrl`/leader.
- [x] **nvim:** `Ctrl+U/D/Y` не перехватываются; проверены `Ctrl+Shift+...` и terminal-биндинги.
- [x] **Noctalia:** launcher/панели/уведомления сведены с niri через `Mod`-биндинги.
- [ ] Составить итоговую таблицу «кто владеет сочетанием» и только потом менять конфиги.

## Напоминалка для ветки macos

> [!todo] Когда вернёмся на macOS
> Это задачи **только для ветки `macos`**, не для `linux`. Перед правками: `git switch macos`, поставить тег/бэкап (`macos-2026-11-18`), делать отдельным коммитом. Mac-пути (`/opt/homebrew`, `$HOME/.oh-my-zsh`) на Linux-аналоги не заменять.

### Ошибки, которые были и на mac

- [ ] `gdbranch`: `target_given` не выставлялся — `gdbranch base target` всегда сравнивал рабочее дерево. Выставить флаг, убрать дублирующий `local target_label`, проверить `-f` без значения.
- [ ] `unload_mySysFile`: у `aerospace` в destination потерян `~` (`/.config/...`); у `treemd` нет `:dst`, поэтому `cp` копирует файл сам в себя. Исправить destinations.
- [ ] `unload_mySysFile`: `_unload_item` не проверяет код возврата `cp` и печатает «Восстановлено» при ошибке. Проверять статус и не врать.
- [ ] `backup_mySysFile`: `_backup_item` тоже не проверяет `cp`; добавить проверку. Копирование каталогов через `cp -R src/ dst` на mac сливает содержимое, но для единообразия лучше `src/.`.
- [ ] `diff_mySysFile`: при отсутствии компонента и в системе, и в бэкапе он попадает сразу в два списка («только в бэкапе» и «только текущий»). Развести в отдельный «нет ни там, ни там».
- [ ] Комплишены: `_DiffBackupUnload` содержит `--Help` вместо `--help` (не работает и на mac); проверить `_arguments` для `diff`; при бэкпорте флагов добавить `_dsh_backup` `-L/--skip-locks` и `--help`.
- [ ] `dsh_backup`: решить, бэкпортить ли в `macos` улучшения из linux-ветки (манифест с ОС, страховка home/credentials, `-L`, проверка missing `file:`). Если нет — хотя бы не терять исправления при будущих правках.

### Улучшения логики `.zshrc`

- [ ] Блок 1 (до compinit) и блок 2 (после) сохранить, но в блоке 2 безусловно выставлять **все** приоритетные пути; иначе `typeset -U` фиксирует порядок, унаследованный из окружения.
- [ ] Проверить порядок `FPATH`: `~/.zsh_MyFunctions` → brew site-functions → системные; в обоих блоках одинаково.
- [ ] `brew shellenv` сделать условным, не дублировать; `fzf-tab`/autosuggestions/syntax-highlighting source-ить с проверкой файла.
- [ ] `stty intr undef` обернуть в `[[ -t 0 ]]`; `fastfetch` — в `command -v fastfetch`.
- [ ] Заменить `cat` в heredoc на `command cat` (иначе алиас `cat=bat` ломает справки при повторном source).
- [ ] Проверить `RPS1` против `RPROMPT` темы; убрать мёртвые `/opt/homebrew`-пути, если brew переехал.
- [ ] Использовать `${f:t}` вместо внешнего `basename` в цикле функций.

### Улучшения логики `.bash_profile`

- [ ] `prepend_path` должен **перемещать** каталог в начало и удалять старые вхождения, а не только добавлять отсутствующий.
- [ ] Добавить `source ~/.bashrc` для login-shell; убрать MacVim-алиасы, `psqlc`, `PSQL_EDITOR`, `LDFLAGS`/`CPPFLAGS`.
- [ ] `Dpython`/`Dbackup` — `ForSys`, не `For\ Sys`; `EDITOR`/`v` — `/opt/homebrew/bin/nvim` или `command -v nvim`.
- [ ] Решить, нужен ли кастомный `PS1`: сейчас он перекрывает prompt из `.bashrc`.
- [ ] Проверить порядок `venv → brew → local → system` на маке; `zoxide init bash` не должен сдвигать PATH.

### Проверка после правок

- [ ] `zsh -n`/`bash -n`; `gdbranch HEAD HEAD` (пусто) и `gdbranch HEAD` (рабочее дерево).
- [ ] `diff_mySysFile` без аргументов — корректные разделы «нет ни там, ни там».
- [ ] `unload_mySysFile` проверять на временном `HOME`, не на живом.
- [ ] `backup_mySysFile zshf`/`bash` — без вложенных `dst/src`.
- [ ] `dsh_backup -h`, dry-run; `shellcheck`/`zsh -n` по возможности.

## Что уже сделано

- **2026-11-21. Аудит и проверка бэкапа.** Найден `my_files/DSH/dsh-backup-20261118-165930`, манифест подтвердил macOS (`MacBook-Pro--Weed.local`), 55 контрольных сумм сошлись.
- **Восстановление DSH.** Развёрнуты профили `headless/tui/web`, 14 файлов TUI, 26 файлов скиллов; `resume.txt` очищен, отсутствующий форк убран, TUI поднят до `0.20.2`; страховка `~/.dsh/.dsh-backup-pre-restore-20261121-221736`.
- **Портирование `dsh_backup`.** Добавлены `sha256sum`/`shasum`, миграция `/Users`, очистка `resume.txt`, удаление `.DS_Store`, `-L`, расширенный манифест, страховка с `credentials.yaml`, предупреждение о missing `file:`-источниках.
- **Проверка плагинов.** `dsh-session-alerts` переведён на `notify-send` (тесты 42/42, реальное уведомление отправлено); `dsh-session-delete` — 63/63; sidebar проверен на `wl-copy`; fact-check прогнан через `doctor`; cost-meter/ctl разобраны.
- **Найденные ограничения.** `dsh-at-file` несовместим с ядром `0.2.2-rc.5` (обе версии), `dsh-tui-pkg-ru` отсутствует; зафиксировано в «Нюансах».
- **Аудит функций zsh.** Исправлены вложенное копирование каталогов в `backup_mySysFile`/`unload_mySysFile`, битые destinations `aerospace`/`treemd`, `target_given` в `gdbranch`, `/opt/homebrew` в `diff_mySysFile`, `mktemp -t` в `y`, комплишены; live-копия синхронизирована через `unload_mySysFile zshf`.
- **Портирование `.zshrc`.** `ZSH=/usr/share/oh-my-zsh`, `ZSH_CUSTOM=$HOME/.oh-my-zsh/custom`; brew `shellenv` условный; PATH зафиксирован как `venv → brew bin/sbin → local → system`; FPATH — `~/.zsh_MyFunctions → brew site-functions → system`; убраны PostgreSQL/`LDFLAGS`/`CPPFLAGS`, mac-алиасы и `/opt/homebrew`; `stty` под `[[ -t 0 ]]`; `fzf-tab` source под проверкой файла. Live и repo синхронизированы; бэкап `~/.zshrc.bak-20261122-001218`.
- **Портирование `.bash_profile`.** Добавлен `source ~/.bashrc`; `prepend_path` с удалением старых вхождений и порядком `local → brew → venv` (итог `venv → brew → local → system`); `EDITOR=/usr/bin/nvim`; убраны `/opt/homebrew`, PostgreSQL, `LDFLAGS`/`CPPFLAGS`, MacVim/`psqlc`; `Dpython`/`Dbackup` переведены на `ForSys`. Live и repo синхронизированы; бэкап `~/.bash_profile.bak-20261122-001347`.
- **`.gitconfig`.** `core.editor` и `difftool.shvimdiff` переведены с `/opt/homebrew/bin/nvim` на `/usr/bin/nvim`; live и repo синхронизированы.
- **`.vimrc`.** GUI-опции (`langmenu`, `guifont`, `mousehide`) под `has('gui_running')`; `language en_US.utf8`; vim-plug подключается только при наличии `~/.vim/autoload/plug.vim`; `colorscheme` через `silent!`; русский spell включается только при наличии файла. Live `~/.vimrc` создан, repo синхронизирован.
- **Пути в скиллах.** `dsh-update` и `md-answer` переведены с `/Users/weed/...` на `$HOME/Documents/ForSys/Backup/my_files/DSH/...`; live-копии обновлены, `/Users` в них больше нет. Старый `my_files/DSH/dsh-backup-...` не трогали.
- **`.ideavimrc`.** Переписан под IdeaVim: только `set`-опции без vim-plug, NERDTree, `:language`, `:langmenu` и GUI-опций; live и repo синхронизированы.
- **`.config` (кроме nvim).** `btop` — системная тема; `neovide` — конфига нет; `tmux` — `tmux-256color`, `set-clipboard on`, `stty -ixon` в `.zshrc`; `lazygit`/`treemd`/`yazi`/`pgcli`/`psql` проверены, mac-путей нет; `mycli`/`pgcli`/`psql`/`tmux` live отсутствуют.
- **alacritty.** Убраны mac-only `blur` и `option_as_alt`; padding 3, размер 130x40, `opacity` убран — прозрачность даёт niri 0.94. Шрифты `JetBrainsMono NF` сохранены. `Ctrl+U/D/Y` убраны; добавлены `Ctrl+Shift+PageUp/Down`, `Ctrl+Shift+=/-/0`, `Ctrl+Shift+N` (new window), `Ctrl+Shift+Q` (quit). Вкладок/сплитов в Alacritty нет — только окна/tmux.
- **kitty.** Vim-first: `Ctrl+Shift+hjkl` — фокус окон, `Ctrl+Shift+Alt+hjkl` — перемещение, `Ctrl+Shift+Arrow` — ресайз; вкладки — `Ctrl+Shift+,/.`, перенос вкладок — `Ctrl+Shift+Alt+,/.`. W закрывает вкладку, Q — окно. `kitty_grab` установлен из GitHub, `grab.py` компилируется; `load_config` — 0 ошибок. Live и repo синхронизированы.
- **nvim: Linux-портирование.** Новый `lua/core/layout/niri.lua` + выбор niri первым в `core/layout/init.lua`; `python3_host_prog` на `~/.global_venv/bin/python`; Mason bin в `vim.env.PATH`; `tree-sitter-cli` из pacman и 12 парсеров; spell `ru` из `site/spell`; folding-fallback по `BufWinEnter`; vimtex на `xdg-open` с условным компилятором. Удалены `nvim.log`/бэкапы, `langmapper`, ручной `tree-sitter`; добавлен `.gitignore`; `:checkhealth` — 0 ошибок.
- **`fzf-tab`.** Установлен из AUR (`fzf-tab 1.3.0-2`), файл `/usr/share/zsh/plugins/fzf-tab/fzf-tab.zsh` на месте, source в `.zshrc` работает.
- **nvim keymaps.** `<C-m>` больше не перекрывает Enter; Neo-tree переведён с `<C-n>` на `<leader>n`, Yazi — с `<C-y>` на `<leader>y`, поэтому `Ctrl+n`/`Ctrl+y` снова дефолтные. `<C-h/j/k/l>` оставлены как быстрая навигация по split'ам; terminal — `<leader>t`, `<C-\\>` освобождён.
- **LSP signature help.** `<C-S>` удалён из insert/select (XOFF/flow control), вместо него `<C-k>`; в normal `<C-k>` по-прежнему окно вверх. Плата — в insert больше нет дефолтного digraph на `C-k`.
- **nvim splits/which-key.** `splitright`/`splitbelow` включены; для leader-префиксов добавлены группы which-key (`n`, `y`, `p`, `s`, `f`, `d`, `r`, `c`, `m`, `t`), окнам — `desc`.
- [ ] **macOS: общий аудит keymap.** Сравнить `core/keymaps.lua`, `configs/lsp.lua` и карты плагинов (neo-tree, yazi, luasnip, snacks, grug-far, conform, md-render) с Linux. Повторить: убрать `<C-m>`, Neo-tree → `<leader>n`, Yazi → `<leader>y`, signature help → `<C-k>`, вернуть `<C-n>/<C-y>`, проверить `<C-hjkl>`. Учесть mac-специфику Cmd/Super и не ломать системные сочетания; где можно — приблизить к текущей linux-схеме.
- **Git.** Ветка `master` переименована в `macos` и запушена; `master` удалён на GitHub; default переключён на `macos`; временная `BackupLinux` удалена; работа продолжается в `Backup` на ветке `linux`.
- **`Apps.md`.** Структура и нумерация обновлены; предустановленные: `git`, `zsh`+OhMyZsh, `fastfetch`, `bat`, `btop`, `fzf`, `ripgrep`, `fd`, `vim`, `alacritty`. macOS-only удалены, Handy возвращён под Linux (AUR + `wtype` + модели), `fzf-tab` и `happ-desktop-bin` добавлены. `treemd` и `wtype` уже установлены, Handy пока нет.
- **Текущий индекс `linux`.** Коммиты: `02b1326`, `161dfdf`, `defe658`, `0c9018c`, `451f153`; рабочее дерево чистое, впереди `origin/linux` на 4.
- **Документ.** Перенесён из `~/Documents/ForSys/DSH/answers/` в `~/Documents/ForSys/Backup/doc/`; теперь входит в репозиторий, дальнейшие записи — здесь.
- **mimeapps/XDG.** В `backup_mySysFile`/`unload_mySysFile`/`diff_mySysFile` добавлены `mimeapps` (`~/.config/mimeapps.list`), `xdg` (`~/.config/user-dirs.dirs`) и `xdg-locale` (`~/.config/user-dirs.locale`); автодополнение обновлено. Файлы скопированы, `diff_mySysFile` — без различий. В `mimeapps.list` текущие ассоциации Zen для http/https/html.
- **Свежий DSH-бэкап.** `my_files/DSH/dsh-backup-20261122-020205`, 552K, 57 файлов: профили 3, TUI 14, скиллы 26; `secrets: 0`, `sessions: 0`; `sha256sum -c checksums.txt` — OK. Добавлен в коммит.
- **niri: начальная настройка.** Явно `layout "us,ru"` и `options "ctrl:nocaps,grp:alt_shift_toggle"`; CapsLock → Ctrl, раскладка — Alt+Shift. `gaps 8`, `geometry-corner-radius 10`, `opacity 0.94`. Cheatsheet — `Mod+F1`; launcher — `Mod+Space`; уведомления — `Mod+N`, DND — `Mod+Shift+N`; терминал — `kitty`, браузер — Zen. Перемещение — `Mod+Shift+hjkl`, ресайз — `Mod+Ctrl+hjkl`, workspace — `Mod+Alt+J/K`, floating move — `Mod+Ctrl+Alt+hjkl`, floating resize — `Mod+Ctrl+Alt+Shift+hjkl`, floating/tiling focus — `Mod+V`; screenshot area — `Mod+Print`. Удалены старые mouse-алиасы перемещения (`Mod+Ctrl+Wheel*`, `Mod+Ctrl+Shift+Wheel*`, `Mod+Shift+Wheel*`) и дубли `Mod+Minus/Equal`. `niri validate` OK, English↔Russian проверено.
- **niri/Noctalia в бэкапе.** Скопированы `.config/niri/` (10 файлов) и `.config/noctalia/` (2 файла); `backup_mySysFile niri noctalia` и `diff_mySysFile niri noctalia` — без различий. `full_config.toml` в help помечен как применяемый вручную.
- **Чистка.** Удалены старый `dsh-backup-20261118-165930`, `kitty.conf.bak`, `.zshrc.bak*`, `.bash_profile.bak*`, `.gitconfig.bak*`, временный снимок функций и `/tmp`-артефакты.
- **Zsh-функции.** Временный снимок `~/.zsh_MyFunctions.bak-20261122-020152` сделан и после проверки удалён; `zsh -n` всех 10 файлов — OK; help, `backup_mySysFile zshf` → `diff_mySysFile zshf` без различий, `gdbranch HEAD HEAD` без diff. В `backup_mySysFile`/`unload_mySysFile`/`diff_mySysFile` добавлены `niri` и `noctalia`, в автодополнение — тоже; `full_config.toml` помечен как ручной.
- **Текущее состояние на 2026-11-22.** nvim Linux-порт завершён (`:checkhealth` — 0 ошибок); `treemd` и `wtype` установлены, Handy ещё нет; `Apps.md` обновлён; niri/noctalia в бэкапе; kitty/alacritty выровнены; `kitty_grab` установлен; nvim keymaps/splits/which-key настроены; mimeapps/XDG добавлены; последний коммит — `451f153`.

## Нюансы и грабли

1. **Установленные копии плагина — hardlink'и на исходник.** После `npm run build` новый `lib/notify.js` появился и в `~/.dsh/profiles/*/node_modules/dsh-session-alerts/lib/`, но запущенный TUI держит старый модуль в памяти. Нужен перезапуск, а не только пересборка.
2. **`lib/` в `.gitignore`.** После чистого клонирования `dsh-session-alerts` не загрузится: сначала `npm ci --include=dev && npm run build`. Глобальный npm стоит с `omit=dev`.
3. **`dsh-at-file` 0.6.3** падает с `does not provide an export named 'settingsNamespace'`; **0.7.0** — с `ctx.settings.register is not a function`. Это несовместимость с ядром, а не macOS-баг. Пока оставлен включённым: web-сервер стартует, но пишет предупреждение.
4. **`dsh-tui-pkg-ru`** (локальный форк TUI) отсутствует и в бэкапе, и на диске; зависимость удалена из `tui`. Если форк нужен — исходники придётся найти отдельно.
5. **Уведомления.** `notify-send` работает через D-Bus и Noctalia; звук и `activate` на Linux игнорируются. Если TUI запущен вне сессионной шины (systemd-сервис), уведомлений не будет.
6. **Буфер.** В Wayland работает `wl-copy`; `xclip`/`xsel` не установлены и не нужны, пока нет X11-приложений. `tmux` тоже пока не установлен.
7. **Secret Service.** `gnome-keyring-daemon` запущен, но это надо проверять после перезагрузки/входа: без провайдера история буфера и уведомлений Noctalia не шифруется, а `pgcli` с `keyring = True` может ругаться.
8. **Obsidian.** Реестра `~/.config/obsidian/obsidian.json` нет, поэтому `md-answer` не находит хранилище автоматически; проще задать `OBSIDIAN_VAULT=/путь/к/vault` (или открыть Obsidian один раз, чтобы он создал реестр).
9. **Скиллы.** В `dsh-update/SKILL.md`, `dsh-update/references/recovery.md` и `md-answer_skill/INSTALL.md` осталось 8 маковских путей; на работу не влияют, но при следующей правке их стоит заменить.
10. **`diff_mySysFile`** теперь берёт `nvim` из `PATH`; если его нет, отчёт всё равно строится, а редактор пропускается. Старый жёсткий `/opt/homebrew/bin/nvim` убран.
11. **Пути в функциях не менялись.** `backup_mySysFile`, `unload_mySysFile`, `diff_mySysFile` и примеры `dsh_backup` по-прежнему указывают на `~/Documents/ForSys/Backup`. Это осознанно: `BackupLinux` удалена, репозиторий остался на старом пути.
12. **`master` удалён, default — `macos`.** Не пушить `master` и не делать его default; иначе GitHub снова запретит удаление.
13. **`linux` не запушен.** Впереди `origin/linux` на 4 коммита; рабочее дерево чистое. На другом ПК ветки нет, пока не сделать push.
14. **AeroSpace.** `.config/aerospace/aerospace.toml` удалён вручную как лишний; удаление в индексе, компонент `aerospace` убран из `backup_mySysFile`, `unload_mySysFile`, `diff_mySysFile` и комплишенов. В истории ветки `macos` файл остаётся.
15. **mac-бэкап остаётся маковским.** В нём TUI `0.19.0`, DSH `0.2.2-rc.1`, сессий и секретов нет. Это архив для сравнения, а не источник для повседневного восстановления.
16. **Текущая TUI-сессия старше восстановленных настроек.** Она держит старый снимок `settings.json`; если менять настройки до перезапуска, можно перезаписать восстановленные значения.
17. **`dsh_backup -u` на старом бэкапе** предупредит об отсутствующем `dsh-tui-pkg-ru`; это ожидаемо, зависимость надо убирать вручную или мириться с предупреждением.
18. **`shasum` есть, но не гарантирован.** На CachyOS он тянется из `perl`; в новом коде первичен `sha256sum`.

19. **Копирование каталогов в `backup_mySysFile`/`unload_mySysFile`.** Раньше при существующем `dst` получалось `dst/src/...`; теперь используется `cp -R src/. dst/`, содержимое сливается. Ошибки `cp` больше не выдают «Восстановлено» молча.
20. **`unload_mySysFile all` — только на копии.** Репозиторий уже Linux-ориентирован, но `all` перезаписывает live-конфиги; перед запуском проверить diff и использовать временный HOME. `zshf` безопасен и уже применён.

21. **`fzf-tab` установлен из AUR** (`fzf-tab 1.3.0-2`), файл `/usr/share/zsh/plugins/fzf-tab/fzf-tab.zsh` на месте. `source` в `.zshrc` защищён проверкой на случай удаления пакета.
22. **`zsh -i -c` без tty** всё ещё может писать `can't change option: zle` — это не PATH и не `.zshrc`-логика, в обычном терминале zle доступен. `stty` уже обёрнут в `[[ -t 0 ]]`, поэтому его ошибки в non-tty больше нет.

23. **`.bash_profile` для login-shell.** Он source-ит `~/.bashrc`, затем задаёт PATH через `prepend_path` (удаляет старые вхождения и поднимает каталог в начало). Итог: `venv → brew → local → system`. `PS1` из mac-версии сохранён и перекрывает `PS1` из `.bashrc`; если нужен дефолтный bash-prompt, эту строку надо убрать.

24. **`.vimrc` и vim-plug.** Плагины vim (`plug#begin`) подключаются только если есть `~/.vim/autoload/plug.vim`; сейчас его нет, поэтому vim стартует без плагинов, но и без ошибок. Для `gruvbox`/NERDTree их надо поставить отдельно. Русский spell (`vim-spell-ru`) не установлен, поэтому `.vimrc` проверяет наличие `ru.utf-8.spl`.
25. **Старый DSH-бэкап удалён.** После свежего `dsh-backup-20261122-020205` старый `dsh-backup-20261118-165930` удалён из рабочего дерева; он остаётся в истории git. Новый бэкап проверен по checksums, без секретов и сессий.

26. **IdeaVim.** Новый `~/.ideavimrc` — минимальный: `set`-опции, без vim-plug/`Plug` и NERDTree. Плагины в IDE даёт сама IDE; если нужны маппинги — добавлять в IdeaVim-совместимом виде.
27. **`mycli`.** Конфиг лежит в `.config/mycli/.myclirc`, но на Linux mycli обычно читает `~/.myclirc`; live-каталога нет, поэтому не проверял. При установке — symlink `~/.myclirc` на `.config/mycli/.myclirc` или перенос.
28. **`treemd`.** Конфиг `~/.config/treemd/config.toml` на месте, бинарь установлен; opener в yazi для `.md` должен работать.
29. **`tmux`/`neovide`.** tmux-конфиг исправлен, но приложения нет; синтаксис tmux не проверен. neovide-конфига нет, приложение не установлено. `tmux` при установке получит `tmux-256color` и `set-clipboard on`; префикс `C-q` теперь не глушится IXON благодаря `stty -ixon`.

30. **alacritty-биндинги — решено.** `Ctrl+U/D/Y` убраны; scroll — `Ctrl+Shift+PageUp/Down`, zoom — `Ctrl+Shift+=/-/0`, new window — `Ctrl+Shift+N`, quit — `Ctrl+Shift+Q`.
31. **alacritty opacity — решено.** `window.opacity` убран; прозрачность даёт niri `0.94`. `blur`/`option_as_alt` убраны как macOS-only.

32. **kitty-ключи — решено.** Неизвестные ключи убраны; `map cmd+...` заменены на `Ctrl+Shift`; дубль закрытия исправлен; `kitty_grab` установлен.

33. **Nvim: niri-раскладка — решено.** `core/layout/niri.lua` использует IPC niri; `init.lua` выбирает niri первым на Linux, fcitx5/ibus/xkb-switch остаются fallback. В headless переключение отключено, как и раньше.
34. **Nvim: Python-provider — решено.** `python3_host_prog` указывает на `~/.global_venv/bin/python`, если он существует; при удалении venv настройка просто не выставится, Neovim вернётся к поиску в PATH.
35. **Nvim: spell — решено.** В `~/.local/share/nvim/site/spell` есть `ru.utf-8.spl`/`.sug`; `spelllang = { "ru", "en" }` работает. На другой машине файл надо положить отдельно.
36. **Nvim: clipboard.** `opt.clipboard` не задан, поэтому обычный yank не идёт в системный буфер; `setreg("+")`/`getreg("+")` через `wl-copy` работают. Отдельного `:checkhealth clipboard` в 0.12 нет.
37. **Nvim: treesitter.** Для сборки парсеров нужен `tree-sitter-cli`; он установлен пакетом pacman (`/usr/bin/tree-sitter`), парсеры — в `~/.local/share/nvim/site/parser`. Без CLI `nvim-treesitter` не установит парсеры, теперь есть предупреждение.
38. **Nvim: Mason PATH.** `ruff`/`stylua`/`pyright` лежат в `~/.local/share/nvim/mason/bin`, которого не было в PATH; `core/options.lua` добавляет его первым.
39. **Nvim: vimtex.** `open` был macOS-методом; на Linux — `general` + `xdg-open`. Компилятор отключён, пока нет `latexmk`; health предупреждает про `bibtex`/`biber`, это ожидаемо без TeX.
40. **Nvim: health-предупреждения.** `mason` ругается на необязательные Go/Ruby/PHP/Java/Julia/luarocks; `vim.lsp` — на ленивые конфиги до первого файла; `which-key` — на отсутствие `mini.icons`; `vimtex` — на `bibtex`/`biber`. Ошибок (`❌`) нет.
41. **tree-sitter CLI — pacman.** Пакет `tree-sitter-cli 0.26.9` установлен через pacman; ручной `~/.local/bin/tree-sitter` удалён, `command -v tree-sitter` → `/usr/bin/tree-sitter`. Парсеры в `~/.local/share/nvim/site/parser` — не пакеты, обновляются `:TSUpdate`; ставить `tree-sitter-*` из pacman не нужно, Nvim их оттуда не подхватит.
42. **Nvim: каналы обновления.** Плагины — `:lua vim.pack.update()`; парсеры — `:TSUpdate`; Mason-инструменты (`ruff`, `stylua`, `pyright`, `lua-language-server`, `marksman`, `shuck`) — `:MasonUpdate` + `:Mason` (Update All), они не pacman-пакеты.

43. **Документация.** Журнал перенесён в `Backup/doc/2026-11-21-pereezd-macos-cachyos-niri-noctalia.md` и добавлен в индекс `linux`; дальнейшие записи вести там, а не в `DSH/answers/`.
