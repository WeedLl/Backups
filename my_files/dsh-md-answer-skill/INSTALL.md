# Установка

Скилл — это каталог с `SKILL.md`. Ядро DSH подхватывает каталоги из `~/.dsh/skills/`, поэтому установка — копирование папки:

```bash
mkdir -p ~/.dsh/skills
rsync -a md-answer_skill/ ~/.dsh/skills/md-answer_skill/
```

## Имя папки и имя скилла — разные вещи

DSH берёт имя из `name:` в YAML-frontmatter `SKILL.md`, а не из имени каталога. Каталог нужен только как **resourceBase** — точка отсчёта для `tools/check.mjs` и `references/`. Поэтому:

- папка может называться как угодно: `md-answer_skill`, `md-answer`, `dsh-md-answer_skill`;
- в `/skills` и в команде `/md-answer` будет ровно то, что написано в `name`;
- переименование папки не ломает скилл, пока внутри лежит `SKILL.md` с валидным `name` (kebab-case) и `description`.

Проверка: в TUI — `/skills` (должен появиться `md-answer`), либо

```bash
dsh-tui cli skills list | grep md-answer
```

Использование: `/md-answer` или просто просьба «оформи в .md».

## Обновление и удаление

Обновление — заменить папку тем же `rsync`. Удаление:

```bash
rm -rf ~/.dsh/skills/md-answer_skill
```

## Пути внутри скилла

После установки пути в `SKILL.md` вида `tools/check.mjs` резолвятся от каталога скилла; если запускаешь из другой папки, используй полный путь:

```bash
node ~/.dsh/skills/md-answer_skill/tools/check.mjs answers/2026-11-08-x.md
```

## Копии и синхронизация

Скилл лежит в трёх местах, и это осознанно:

| Путь | Роль |
|---|---|
| `~/Documents/Ai/DSH/md-answer_skill` | **источник**, рядом с локальными плагинами |
| `~/.dsh/skills/md-answer_skill` | **установленная копия**, её видят все профили |
| рабочая папка (`…/DSH/md-answer_skill`) | черновик, его можно удалить |

После правок источника — одна команда:

```bash
rsync -a ~/Documents/Ai/DSH/md-answer_skill/ ~/.dsh/skills/md-answer_skill/
```

Вместо копии можно держать симлинк (ядро ходит по симлинкам):

```bash
rm -rf ~/.dsh/skills/md-answer_skill
ln -s ~/Documents/Ai/DSH/md-answer_skill ~/.dsh/skills/md-answer_skill
```

Тогда источник и установка — один каталог, расхождению взяться неоткуда.

## Перенос на другую машину

`dsh_backup` каталог `~/.dsh/skills/` не сохраняет. Скилл переносится копированием папки целиком — она самодостаточна, кроме Node ≥ 18 для `tools/*.mjs`.
