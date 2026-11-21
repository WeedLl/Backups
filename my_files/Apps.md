# Для работы

> [!note] CachyOS
> **предустановлено (CachyOS/Arch)** — было в базовой установке; для остальных указан первый доступный источник: **pacman → paru (AUR) → brew**. DSH — `npm`, `vim-plug` — `git`. **только macOS** — на Linux не переносится.

1. HomeBrew — `brew`, но только `python@3.15` и зависимости; основной менеджер — pacman
2. `git` — pacman **(предустановлено; CachyOS/Arch)**
3. `lazygit` — pacman
4. `zsh` + OhMyZsh — pacman (`zsh`, `oh-my-zsh-git`) **(предустановлено; CachyOS/Arch)** + Plug:
    - 4.1 `ttf-jetbrains-mono-nerd` — pacman, JetBrainsMono NFM **(regular 14)** — Alacritty
    - 4.2 `ttf-jetbrains-mono` — pacman, JetBrainsMono **(regular 14)** — Kitty *(у него свои иконки)*
    - 4.3 `fastfetch` — pacman — красивое отображение информации по системе при открытии терминала **(предустановлено; CachyOS/Arch)**
    - 4.4 `lsd` *(LSDeluxe)* — pacman
    - 4.5 `bat` *(cat с подсветкой)* — pacman **(предустановлено; CachyOS/Arch)**
    - 4.6 `btop` *(крутой top)* — pacman **(предустановлено; CachyOS/Arch)**
    - 4.7 `zoxide` *(умный `cd` по последним папкам?)* — pacman
    - 4.8 `fzf` *(поиск по файлам)* — pacman **(предустановлено; CachyOS/Arch)**
    - 4.9 `yazi` — файловый менеджер для терминала — pacman
        - 4.9.1 `ripgrep` — замена grep, поставил чисто для `yazi` — pacman **(предустановлено; CachyOS/Arch)**
        - 4.9.2 `fd` — замена find, поставил чисто для `yazi` — pacman **(предустановлено; CachyOS/Arch)**
    - 4.10 `fzf-tab` — AUR/paru, плагин zsh
5. `nvim` — pacman:
    - 5.1 `nodejs`, `npm` — pacman — для работы некоторых плагинов
    - 5.2 `tree-sitter`, `tree-sitter-cli` — pacman; команда одна — `tree-sitter`
    - 5.3 `imagemagick` **(можно установить: pacman)**
6. `vim` — pacman **(предустановлено; CachyOS/Arch)**; vim-plug **(нет пакета; git)**
    > [!note] Ну случай, если отвалится NeoVim
7. `treemd` — pacman — просмотр md с кликабельными ссылками
8. Kitty — pacman — терминал, нравится визуально. Оставлю только из-за этого
9. Alacritty — pacman — терминал, тоже не плох, нужен для tmux (kitty сложно подстроить для этого) **(предустановлено; CachyOS/Arch)**
10. `tmux` **(можно установить: pacman)**
11. DSH *(web profile)* + `dsh-tui` — npm: `@deepseek-ai/dsh`, `@deepseek-harness-tui/dsh-tui`; бинари в `~/.local/bin`
12. PostgreSQL **(можно установить: pacman)**
13. PgAdmin 4 **(можно установить: paru (AUR))**
14. `pgcli` — как `psql`, только с автокомплитом и подсветкой синтаксиса **(можно установить: pacman)**
15. ADB (android debug bridge) **(можно установить: pacman)**
16. Handy — **(можно установить: paru (AUR))** — транскрипция и перевод голоса в текст
    - `wtype` — pacman — вставка текста в Wayland (альтернатива `ydotool`)
    - Parakeet Ultra
    - Canary 1B v2

# Программы
1. Obsidian **(можно установить: pacman)**
2. Zen — pacman (`zen-browser-bin`), команда `zen-browser`
3. Telegram — pacman (`telegram-desktop`), команда `Telegram`
4. Discord **(можно установить: pacman)**
5. PyCharm **(можно установить: pacman)**
6. Happ — AUR/paru (`happ-desktop-bin`), GUI-клиент xray
- Остальные по желанию
