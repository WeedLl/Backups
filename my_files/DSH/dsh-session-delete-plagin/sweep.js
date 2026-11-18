/**
 * Вычистка «хвостов» после успешного `channel.deleteSession(id)`.
 *
 * Штатное удаление хоста сносит каталог лога, `last-used`, agent-view и
 * resume-маркер. Остаются ссылки на id в восьми местах, которые хост НЕ
 * трогает:
 *
 * 1. `$DSH_HOME/storages/session_projcache/sessions/<id>.json` — удалить файл;
 * 2. `$DSH_HOME/storages/workspace.json` — `tables.workspaces[*].sessionIds`,
 *    `global.pinnedSessionIds`, `global.archivedSessionIds`;
 * 3. `$DSH_TUI_HOME/session-index.json` — `entries[id]`;
 * 4. `$DSH_TUI_HOME/session-mounts.json` — `owners[*].sessionIds`;
 * 5. `$DSH_TUI_HOME/session-lists/*.json` — `rows[]` с этим id;
 * 6. `$DSH_TUI_HOME/session-pins.json` — массив id (если файл есть);
 * 7. `$DSH_TUI_HOME/last-run.json` — `sessionId === id` → `''`;
 * 8. `$DSH_TUI_HOME/workspace-sidebar.json` — `sessions[id]` (кэш inbox
 *    плагина `dsh-tui-workspace-sidebar`).
 *
 * Дополнительно {@link cleanInboxState} на старте плагина (до загрузки
 * sidebar) убирает из `workspace-sidebar.json` строки уже несуществующих
 * сессий — страховка от перезаписи файла живым трекером и удалений мимо
 * этого плагина.
 *
 * Пустые `$DSH_HOME/sessions/<slug>/` — отдельный шаг
 * {@link removeEmptySessionDirs} ПОСЛЕ удаления (не внутри sweep).
 *
 * Правила безопасности:
 * - id только `^[A-Za-z0-9][A-Za-z0-9_-]*$`, иначе skip;
 * - бэкап `<file>.bak-sweep-YYYYMMDD-HHMMSS` перед первой записью файла;
 * - атомарная запись: tmp + rename, режим 0600;
 * - непарсибельный JSON не трогаем, пишем в errors;
 * - ничего не бросаем: `{removed, pruned, skipped, errors, summary}`;
 * - `dryRun` для тестов; `backup` отключается конфигом;
 * - rm/rmdir — только внутри корней после realpath-проверки.
 * @module dsh-session-delete/sweep
 */

import {
  chmodSync,
  existsSync,
  readFileSync,
  readdirSync,
  realpathSync,
  renameSync,
  rmSync,
  rmdirSync,
  writeFileSync,
} from 'node:fs'
import { homedir } from 'node:os'
import { join, sep } from 'node:path'

export const SAFE_ID = /^[A-Za-z0-9][A-Za-z0-9_-]*$/
/** Slug-каталог вида `--Users-weed-Documents-DSH--`. */
const SAFE_SLUG = /^[A-Za-z0-9_.@-]+$/

/** Корни по умолчанию: переменные окружения, затем ~/.dsh и ~/.dsh-tui. */
export function defaultRoots() {
  const rawDsh = process.env.DSH_HOME?.trim()
  const rawTui = process.env.DSH_TUI_HOME?.trim()
  return {
    dshHome: rawDsh !== undefined && rawDsh !== '' ? rawDsh : join(homedir(), '.dsh'),
    tuiHome: rawTui !== undefined && rawTui !== '' ? rawTui : join(homedir(), '.dsh-tui'),
  }
}

/** `YYYYMMDD-HHMMSS` из миллисекунд epoch (инъекция для детерминизма в тестах). */
function stamp(nowMs) {
  const d = new Date(nowMs)
  const p = (n) => String(n).padStart(2, '0')
  return `${d.getFullYear()}${p(d.getMonth() + 1)}${p(d.getDate())}-${p(d.getHours())}${p(d.getMinutes())}${p(d.getSeconds())}`
}

function errorText(error) {
  return error instanceof Error ? error.message : String(error ?? '')
}

/**
 * Реальный путь `child` находится внутри реального `parent` (файл/каталог
 * должны существовать). Ошибки — `false`: не трогаем то, чего не видим.
 */
function isInside(child, parent) {
  try {
    const realParent = realpathSync(parent)
    const realChild = realpathSync(child)
    return realChild === realParent || realChild.startsWith(realParent + sep)
  } catch {
    return false
  }
}

function readJson(path) {
  try {
    return JSON.parse(readFileSync(path, 'utf8'))
  } catch {
    return undefined
  }
}

/**
 * Атомарная запись с бэкапом. При сбое после rename бэкапа восстанавливаем
 * оригинал из бэкапа. Возвращает true; ошибки пробрасываются вызывающему
 * (он пишет их в отчёт).
 */
function writeJsonAtomic(path, data, { backup, backupPath, dryRun }) {
  if (dryRun) return
  let backedUp = false
  if (backup && backupPath !== undefined && !existsSync(backupPath)) {
    renameSync(path, backupPath)
    backedUp = true
  }
  try {
    const tmp = `${path}.tmp-sweep-${process.pid}`
    writeFileSync(tmp, `${JSON.stringify(data)}\n`, { encoding: 'utf8', mode: 0o600 })
    try {
      chmodSync(tmp, 0o600)
    } catch {
      // Режим — желательное, а не обязательное.
    }
    renameSync(tmp, path)
  } catch (error) {
    if (backedUp) {
      try {
        renameSync(backupPath, path)
      } catch {
        // Бэкап остаётся единственной копией; отчёт покажет ошибку записи.
      }
    }
    throw error
  }
}

// ---- pruners: мутируют распарсенные данные, возвращают true при изменении ----

function pruneMap(data, ids) {
  if (data === null || typeof data !== 'object' || Array.isArray(data)) return false
  let changed = false
  for (const id of ids) {
    if (Object.prototype.hasOwnProperty.call(data, id)) {
      delete data[id]
      changed = true
    }
  }
  return changed
}

function pruneStringArray(list, ids) {
  if (!Array.isArray(list)) return false
  const set = new Set(ids)
  const next = list.filter((id) => typeof id === 'string' && !set.has(id))
  if (next.length === list.length) return false
  list.splice(0, list.length, ...next)
  return true
}

function pruneWorkspace(data, ids) {
  let changed = false
  const workspaces = data?.tables?.workspaces
  if (workspaces !== null && typeof workspaces === 'object') {
    for (const workspace of Object.values(workspaces)) {
      if (workspace === null || typeof workspace !== 'object') continue
      if (pruneStringArray(workspace.sessionIds, ids)) changed = true
    }
  }
  const global = data?.global
  if (global !== null && typeof global === 'object') {
    if (pruneStringArray(global.pinnedSessionIds, ids)) changed = true
    if (pruneStringArray(global.archivedSessionIds, ids)) changed = true
  }
  return changed
}

function pruneMounts(data, ids) {
  const owners = data?.owners
  if (!Array.isArray(owners)) return false
  let changed = false
  for (const owner of owners) {
    if (owner === null || typeof owner !== 'object') continue
    if (pruneStringArray(owner.sessionIds, ids)) changed = true
  }
  return changed
}

function pruneSessionListRows(data, ids) {
  const rows = data?.rows
  if (!Array.isArray(rows)) return false
  const set = new Set(ids)
  const next = rows.filter((row) => row !== null && typeof row === 'object' && !set.has(row.id))
  if (next.length === rows.length) return false
  data.rows = next
  return true
}

function prunePins(data, ids) {
  // По контракту — массив id; другие формы не трогаем.
  return pruneStringArray(Array.isArray(data) ? data : undefined, ids)
}

function pruneLastRun(data, ids) {
  if (data === null || typeof data !== 'object' || Array.isArray(data)) return false
  if (typeof data.sessionId !== 'string') return false
  if (!ids.includes(data.sessionId)) return false
  data.sessionId = ''
  return true
}

/**
 * Найти каталоги сессий `$DSH_HOME/sessions/<slug>/<id>` для данных id
 * (нужно до удаления: slug-родители могут опустеть после).
 * Не бросает; realpath-проверка: только внутри `$DSH_HOME/sessions`.
 *
 * @param {readonly string[]} ids
 * @param {{dshHome?: string}} [options]
 * @returns {{found: {id: string, slug: string, path: string}[], errors: string[]}}
 */
export function findSessionDirs(ids, options = {}) {
  const roots = options.dshHome ?? defaultRoots().dshHome
  const sessionsRoot = join(roots, 'sessions')
  const found = []
  const errors = []
  if (!existsSync(sessionsRoot)) return { found, errors }
  let realRoot
  try {
    realRoot = realpathSync(sessionsRoot)
  } catch (error) {
    errors.push(`sessions недоступен: ${errorText(error)}`)
    return { found, errors }
  }
  const wanted = new Set(ids)
  let entries
  try {
    entries = readdirSync(sessionsRoot)
  } catch (error) {
    errors.push(`sessions не читается: ${errorText(error)}`)
    return { found, errors }
  }
  for (const slug of entries) {
    const dir = join(sessionsRoot, slug)
    if (!isInside(dir, sessionsRoot)) continue
    let children
    try {
      children = readdirSync(dir)
    } catch {
      continue
    }
    for (const entry of children) {
      if (!wanted.has(entry)) continue
      const child = join(dir, entry)
      if (!isInside(child, sessionsRoot)) continue
      found.push({ id: entry, slug, path: child })
    }
  }
  return { found, errors }
}

/**
 * Вычистить все хвосты по списку удалённых id. Никогда не бросает.
 *
 * @param {readonly string[]} sessionIds
 * @param {{backup?: boolean, dryRun?: boolean, dshHome?: string,
 *   tuiHome?: string, now?: number}} [options]
 * @returns {{removed: string[], pruned: string[], skipped: string[],
 *   errors: string[], summary: string}}
 */
export function sweepSessions(sessionIds, options = {}) {
  const roots = defaultRoots()
  const dshHome = options.dshHome ?? roots.dshHome
  const tuiHome = options.tuiHome ?? roots.tuiHome
  const backup = options.backup !== false
  const dryRun = options.dryRun === true
  const backupStamp = stamp(options.now ?? Date.now())

  const accepted = []
  const skipped = []
  for (const id of sessionIds ?? []) {
    if (typeof id === 'string' && SAFE_ID.test(id)) accepted.push(id)
    else skipped.push(String(id))
  }

  const removed = []
  const pruned = []
  const errors = []
  if (accepted.length === 0) {
    return {
      removed,
      pruned,
      skipped,
      errors,
      summary: skipped.length > 0 ? 'нечего вычищать (id не прошли whitelist)' : 'нечего вычищать',
    }
  }

  // 1. Проекционный кэш: файл на сессию.
  const cacheDir = join(dshHome, 'storages', 'session_projcache', 'sessions')
  for (const id of accepted) {
    const file = join(cacheDir, `${id}.json`)
    if (!existsSync(file)) continue
    if (!isInside(file, dshHome)) {
      errors.push(`projcache/${id}.json: вне $DSH_HOME, не тронут`)
      continue
    }
    if (dryRun) {
      removed.push(`projcache/${id}.json`)
      continue
    }
    try {
      rmSync(file, { force: true })
      removed.push(`projcache/${id}.json`)
    } catch (error) {
      errors.push(`projcache/${id}.json: ${errorText(error)}`)
    }
  }

  // 2–8. Общие JSON-файлы: pruner мутирует данные, пишем только при изменении.
  const targets = [
    {
      label: 'storages/workspace.json',
      path: join(dshHome, 'storages', 'workspace.json'),
      home: dshHome,
      prune: pruneWorkspace,
    },
    {
      label: 'session-index.json',
      path: join(tuiHome, 'session-index.json'),
      home: tuiHome,
      prune: (data, ids) => pruneMap(data?.entries, ids),
    },
    {
      label: 'session-mounts.json',
      path: join(tuiHome, 'session-mounts.json'),
      home: tuiHome,
      prune: pruneMounts,
    },
    {
      label: 'session-pins.json',
      path: join(tuiHome, 'session-pins.json'),
      home: tuiHome,
      prune: prunePins,
    },
    {
      label: 'last-run.json',
      path: join(tuiHome, 'last-run.json'),
      home: tuiHome,
      prune: pruneLastRun,
    },
    {
      label: 'workspace-sidebar.json',
      path: join(tuiHome, 'workspace-sidebar.json'),
      home: tuiHome,
      // `sessions` — карта id → строка; pruneMap сам отсекает не-объект.
      prune: (data, ids) => pruneMap(data?.sessions, ids),
    },
  ]

  for (const target of targets) {
    if (!existsSync(target.path)) continue
    if (!isInside(target.path, target.home)) {
      errors.push(`${target.label}: вне корня, не тронут`)
      continue
    }
    const data = readJson(target.path)
    if (data === undefined) {
      errors.push(`${target.label}: непарсибельный JSON, не тронут`)
      continue
    }
    let changed = false
    try {
      changed = target.prune(data, accepted) === true
    } catch (error) {
      errors.push(`${target.label}: ${errorText(error)}`)
      continue
    }
    if (!changed) continue
    pruned.push(target.label)
    if (dryRun) continue
    try {
      writeJsonAtomic(target.path, data, {
        backup,
        backupPath: `${target.path}.bak-sweep-${backupStamp}`,
        dryRun,
      })
    } catch (error) {
      errors.push(`${target.label}: ${errorText(error)}`)
    }
  }

  // 5. session-lists/*.json — по одному файлу на источник списков.
  const listsDir = join(tuiHome, 'session-lists')
  if (existsSync(listsDir)) {
    let entries = []
    try {
      entries = readdirSync(listsDir)
    } catch (error) {
      errors.push(`session-lists: ${errorText(error)}`)
    }
    for (const entry of entries) {
      if (!entry.endsWith('.json')) continue
      const file = join(listsDir, entry)
      const label = `session-lists/${entry}`
      if (!isInside(file, tuiHome)) {
        errors.push(`${label}: вне $DSH_TUI_HOME, не тронут`)
        continue
      }
      const data = readJson(file)
      if (data === undefined) {
        errors.push(`${label}: непарсибельный JSON, не тронут`)
        continue
      }
      let changed = false
      try {
        changed = pruneSessionListRows(data, accepted) === true
      } catch (error) {
        errors.push(`${label}: ${errorText(error)}`)
        continue
      }
      if (!changed) continue
      pruned.push(label)
      if (dryRun) continue
      try {
        writeJsonAtomic(file, data, {
          backup,
          backupPath: `${file}.bak-sweep-${backupStamp}`,
          dryRun,
        })
      } catch (error) {
        errors.push(`${label}: ${errorText(error)}`)
      }
    }
  }

  const parts = []
  if (removed.length > 0) parts.push(`удалено файлов: ${removed.length}`)
  if (pruned.length > 0) parts.push(`вычищено списков: ${pruned.length}`)
  if (skipped.length > 0) parts.push(`пропущено: ${skipped.length}`)
  if (errors.length > 0) parts.push(`ошибок: ${errors.length}`)
  if (dryRun) parts.push('(dry run)')
  return {
    removed,
    pruned,
    skipped,
    errors,
    summary: parts.length > 0 ? parts.join(' · ') : 'хвостов не найдено',
  }
}

/**
 * Собрать id сессий, существующих на диске (`$DSH_HOME/sessions/<slug>/<id>`).
 * `undefined` означает «прочитать не удалось целиком»: вызывающий в этом
 * случае не должен удалять ни одной строки.
 *
 * @param {string} sessionsRoot
 * @returns {Set<string> | undefined}
 */
export function collectSessionIds(sessionsRoot) {
  if (!existsSync(sessionsRoot)) return undefined
  let slugs
  try {
    slugs = readdirSync(sessionsRoot, { withFileTypes: true })
  } catch {
    return undefined
  }
  const ids = new Set()
  for (const slug of slugs) {
    if (!slug.isDirectory()) continue
    let children
    try {
      children = readdirSync(join(sessionsRoot, slug.name), { withFileTypes: true })
    } catch {
      // Один нечитаемый slug делает картину неполной — не рискуем.
      return undefined
    }
    for (const child of children) {
      if (child.isDirectory()) ids.add(child.name)
    }
  }
  return ids
}

/**
 * Стартовая чистка кэша inbox `dsh-tui-workspace-sidebar`.
 *
 * Удаляет из `workspace-sidebar.json` только `finished`-строки, для которых
 * на диске больше нет каталога сессии. `running`-строки не трогает (их
 * sidebar и так не восстанавливает). При любой неопределённости — нет файла,
 * битый JSON, нечитаемый `sessions` — файл остаётся как есть.
 *
 * Вызывается из `apply()` до регистрации сцены; чтобы это было ДО загрузки
 * sidebar, строка `session-delete` должна стоять в bundles раньше
 * `dsh-tui-workspace-sidebar`.
 *
 * @param {{stateFile?: string, dshHome?: string, tuiHome?: string,
 *   backup?: boolean, now?: number}} [options]
 * @returns {{changed: boolean, removed: string[], skipped: string[],
 *   errors: string[]}}
 */
export function cleanInboxState(options = {}) {
  const roots = defaultRoots()
  const dshHome = options.dshHome ?? roots.dshHome
  const tuiHome = options.tuiHome ?? roots.tuiHome
  const customFile = typeof options.stateFile === 'string' && options.stateFile.trim() !== ''
  const file = customFile ? options.stateFile.trim() : join(tuiHome, 'workspace-sidebar.json')
  const backup = options.backup !== false
  const now = options.now ?? Date.now()

  const result = { changed: false, removed: [], skipped: [], errors: [] }
  try {
    if (!existsSync(file)) {
      result.skipped.push('workspace-sidebar.json отсутствует')
      return result
    }
    // Для дефолтного пути держим проверку корня; явно заданный stateFile
    // считаем доверенным конфигом.
    if (!customFile && !isInside(file, tuiHome)) {
      result.errors.push('workspace-sidebar.json: вне $DSH_TUI_HOME, не тронут')
      return result
    }
    const data = readJson(file)
    if (data === undefined) {
      result.errors.push('workspace-sidebar.json: непарсибельный JSON, не тронут')
      return result
    }
    if (data === null || typeof data !== 'object' || Array.isArray(data)) {
      result.errors.push('workspace-sidebar.json: не объект, не тронут')
      return result
    }
    if (data.version !== 1) {
      result.skipped.push(`workspace-sidebar.json: version ${String(data.version)}`)
      return result
    }
    const sessions = data.sessions
    if (sessions === null || typeof sessions !== 'object' || Array.isArray(sessions)) {
      result.skipped.push('workspace-sidebar.json: нет sessions')
      return result
    }
    const alive = collectSessionIds(join(dshHome, 'sessions'))
    if (alive === undefined) {
      result.errors.push('sessions: не читается, workspace-sidebar.json не тронут')
      return result
    }
    for (const [id, row] of Object.entries(sessions)) {
      if (row === null || typeof row !== 'object' || Array.isArray(row)) continue
      if (row.status !== 'finished') continue
      if (alive.has(id)) continue
      delete sessions[id]
      result.removed.push(id)
    }
    if (result.removed.length === 0) return result

    let backupPath = `${file}.bak-janitor-${stamp(now)}`
    let seq = 1
    while (existsSync(backupPath)) {
      backupPath = `${file}.bak-janitor-${stamp(now)}-${seq}`
      seq += 1
    }
    writeJsonAtomic(file, data, { backup, backupPath, dryRun: false })
    result.changed = true
    return result
  } catch (error) {
    result.errors.push(`workspace-sidebar.json: ${errorText(error)}`)
    return result
  }
}

/**
 * Удалить ОПУСТЕВШИЕ slug-каталоги внутри `$DSH_HOME/sessions` (rmdir —
 * непустой каталог не тронется). Только пустые, только внутри
 * `$DSH_HOME/sessions` после realpath-проверки. Не бросает.
 *
 * @param {readonly string[]} slugs
 * @param {{dshHome?: string, dryRun?: boolean}} [options]
 * @returns {{removed: string[], errors: string[]}}
 */
export function removeEmptySessionDirs(slugs, options = {}) {
  const roots = options.dshHome ?? defaultRoots().dshHome
  const dryRun = options.dryRun === true
  const sessionsRoot = join(roots, 'sessions')
  const removed = []
  const errors = []
  if (!existsSync(sessionsRoot)) return { removed, errors }
  let realRoot
  try {
    realRoot = realpathSync(sessionsRoot)
  } catch (error) {
    errors.push(`sessions недоступен: ${errorText(error)}`)
    return { removed, errors }
  }
  for (const slug of slugs ?? []) {
    if (typeof slug !== 'string' || !SAFE_SLUG.test(slug) || slug === '.' || slug === '..') {
      errors.push(`небезопасный slug: ${String(slug)}`)
      continue
    }
    const dir = join(sessionsRoot, slug)
    let real
    try {
      real = realpathSync(dir)
    } catch {
      continue // каталога нет — удалять нечего
    }
    if (real !== realRoot && !real.startsWith(realRoot + sep)) {
      errors.push(`${slug}: вне $DSH_HOME/sessions, не тронут`)
      continue
    }
    try {
      if (readdirSync(dir).length > 0) continue
      if (!dryRun) rmdirSync(dir)
      removed.push(slug)
    } catch (error) {
      errors.push(`${slug}: ${errorText(error)}`)
    }
  }
  return { removed, errors }
}
