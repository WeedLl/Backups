# Установка

Скилл — это каталог с `SKILL.md`. Ядро DSH подхватывает каталоги из `~/.dsh/skills/`, поэтому установка — копирование папки:

```bash
mkdir -p ~/.dsh/skills
rsync -a md-answer_skill/ ~/.dsh/skills/md-answer_skill/
```

## Где что лежит

| Путь | Роль |
|---|---|
| `/Users/weed/Documents/DSH/md-answer_skill` | **рабочая копия**: здесь правки |
| `~/.dsh/skills/md-answer_skill` | **установленная**: её видит DSH, все профили |

После правок рабочей копии — синхронизация в одну сторону:

```bash
rsync -a /Users/weed/Documents/DSH/md-answer_skill/ ~/.dsh/skills/md-answer_skill/
```

Копии расходятся молча: DSH читает только установленную, поэтому «поменял и не проверил» выглядит как «поменял, а ничего не изменилось». Это правило проще соблюдать, чем помнить.

Альтернатива — симлинк вместо копии (ядро ходит по симлинкам):

```bash
rm -rf ~/.dsh/skills/md-answer_skill
ln -s /Users/weed/Documents/DSH/md-answer_skill ~/.dsh/skills/md-answer_skill
```

Тогда каталог один и синхронизировать нечего.

## Имя папки и имя скилла — разные вещи

DSH берёт имя из `name:` в YAML-frontmatter `SKILL.md`, а не из имени каталога. Каталог нужен только как **resourceBase** — точка отсчёта для `tools/check.mjs` и `references/`. Поэтому:

- папка может называться как угодно: `md-answer_skill`, `md-answer`, `dsh-md-answer_skill`;
- в `/skills` и в команде `/md-answer` будет ровно то, что написано в `name`;
- переименование папки не ломает скилл, пока внутри лежит `SKILL.md` с валидным `name` (kebab-case) и `description`.

Проверка: `/skills` в TUI — в списке должен появиться `md-answer`. Команда `dsh-tui cli skills list` на текущей версии DSH не работает (адаптер проверяет старые версии и падает с `ADAPTER_UNAVAILABLE`), так что на неё не рассчитывай.

## Обновление и удаление

```bash
rsync -a /Users/weed/Documents/DSH/md-answer_skill/ ~/.dsh/skills/md-answer_skill/   # обновить
rm -rf ~/.dsh/skills/md-answer_skill                                                   # удалить
```

## Пути внутри скилла

Пути в `SKILL.md` вида `tools/check.mjs` резолвятся от каталога скилла. Если запускаешь из другой папки, используй полный путь:

```bash
node ~/.dsh/skills/md-answer_skill/tools/check.mjs answers/2026-11-08-x.md
```

## Перенос на другую машину

`dsh_backup` каталог `~/.dsh/skills/` не сохраняет. Скилл переносится копированием папки целиком — она самодостаточна, кроме Node ≥ 18 для `tools/*.mjs`.
