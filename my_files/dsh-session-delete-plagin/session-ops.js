/**
 * Чистые функции для списка сессий: сортировка, фильтр, форматирование,
 * guard-вердикты и план удаления. Без TUI и без файловой системы —
 * тестируются напрямую.
 * @module dsh-session-delete/session-ops
 */

import { collectDescendants } from './tree.js'
import { T } from './strings.js'

/** Id, допустимый как имя файла и ключ карты. Всё иное — skip. */
export const SAFE_ID = /^[A-Za-z0-9][A-Za-z0-9_-]*$/

/**
 * Byte-порог «пустой» сессии: созданная хостом, но не использованная запись
 * (без человеческого промпта, < 4096 B, fallback-заголовок) — артефакт
 * загрузки. Консервативно: любая неизвестность считается настоящей сессией.
 */
export const EMPTY_ARTIFACT_BYTES = 4096

/**
 * Kind сессии как строка. Хост отдаёт ОБЪЕКТ
 * (`{kind:'root'|'fork'|'subagent', parent?, depth?}`); принимаем и плоскую
 * строку на случай будущих версий.
 */
export function kindOf(session) {
  const kind = session?.kind
  if (typeof kind === 'string') return kind
  if (kind !== null && typeof kind === 'object' && typeof kind.kind === 'string') return kind.kind
  return undefined
}

/** Сортировка по `updatedAt` по убыванию (свежие сверху); стабильная. */
export function sortSessions(sessions) {
  return [...(sessions ?? [])].sort((a, b) => {
    const at = typeof a?.updatedAt === 'number' ? a.updatedAt : 0
    const bt = typeof b?.updatedAt === 'number' ? b.updatedAt : 0
    return bt - at
  })
}

/** Совпадает ли сессия с регистронезависимым фильтром (title/cwd/id). */
export function matchesQuery(session, needle) {
  const q = String(needle ?? '').toLowerCase()
  const title = session?.title?.text ?? ''
  return (
    title.toLowerCase().includes(q) ||
    (typeof session?.cwd === 'string' ? session.cwd.toLowerCase() : '').includes(q) ||
    (typeof session?.id === 'string' ? session.id.toLowerCase() : '').includes(q)
  )
}

/** Фильтр по title/cwd/id; пустой запрос возвращает список как есть. */
export function filterSessions(sessions, query) {
  const needle = typeof query === 'string' ? query.trim().toLowerCase() : ''
  if (needle === '') return sessions
  return sessions.filter((session) => matchesQuery(session, needle))
}

/** Короткий возраст последней активности: «только что», «12 мин», «3 ч», «9 дн». */
export function formatAge(timestamp) {
  if (typeof timestamp !== 'number' || !Number.isFinite(timestamp)) return ''
  const minutes = Math.floor((Date.now() - timestamp) / 60000)
  if (minutes < 1) return 'только что'
  if (minutes < 60) return `${minutes} мин`
  const hours = Math.floor(minutes / 60)
  if (hours < 24) return `${hours} ч`
  return `${Math.floor(hours / 24)} дн`
}

/** Короткий cwd: `/Users/weed/project` → `~/project`; пусто → `—`. */
export function shortCwd(cwd, home = '') {
  const value = typeof cwd === 'string' ? cwd : ''
  if (value === '') return '—'
  if (home !== '' && value === home) return '~'
  if (home !== '' && value.startsWith(home + '/')) return `~${value.slice(home.length)}`
  return value
}

/** Обрезка строки под бюджет ячеек без середины графемы. */
export function truncate(text, budget) {
  const value = typeof text === 'string' ? text : ''
  if (value.length <= budget) return value
  if (budget <= 1) return value.slice(0, budget)
  return `${value.slice(0, budget - 1)}…`
}

/**
 * «Пустой» артефакт: не подсессия, `hasPrompt === false` (хост доказал, что
 * человеческого сообщения нет), маленький лог и fallback-заголовок.
 */
export function isEmptyArtifact(session) {
  if (session === null || typeof session !== 'object') return false
  if (kindOf(session) === 'subagent') return false
  if (session.hasPrompt !== false) return false
  if (typeof session.bytes !== 'number' || !Number.isFinite(session.bytes)) return false
  if (session.bytes >= EMPTY_ARTIFACT_BYTES) return false
  return session.title?.source === 'fallback'
}

/**
 * Полный guard-вердикт ПЕРЕД удалением: whitelist id, наличие в списке,
 * current, live (самой цели и любого потомка). При ok возвращает готовый
 * план: id потомков от листьев к корню, затем сама цель.
 *
 * @param {{target: object|undefined, sessions: readonly object[],
 *   rowsById: Map<string, object>|undefined, attachedSessionId?: string}} args
 * @returns {{ok: true, ids: string[], descendants: object[]} |
 *   {ok: false, reason: string, text: string, descendants?: object[]}}
 */
export function checkDeletionTarget({ target, sessions, rowsById, attachedSessionId }) {
  if (target === undefined || target === null) {
    return { ok: false, reason: 'missing', text: T.errMissing }
  }
  const id = String(target.id ?? '')
  if (!SAFE_ID.test(id)) {
    return { ok: false, reason: 'unsafe', text: T.errUnsafe }
  }
  const listed = (sessions ?? []).some((session) => session?.id === id)
  if (!listed) {
    return { ok: false, reason: 'missing', text: T.errMissing }
  }
  const row = rowsById?.get(id)
  if (row?.current === true || id === attachedSessionId) {
    return { ok: false, reason: 'current', text: T.errCurrent }
  }
  if (row?.live === true) {
    return { ok: false, reason: 'live', text: T.errLive }
  }
  const descendants = collectDescendants(sessions, id)
  for (const descendant of descendants) {
    const descendantRow = rowsById?.get(descendant.id)
    if (descendantRow?.current === true || descendant.id === attachedSessionId) {
      return {
        ok: false,
        reason: 'descendant-current',
        text: T.errDescendantCurrent,
        descendants,
      }
    }
    if (descendantRow?.live === true) {
      return {
        ok: false,
        reason: 'descendant-live',
        text: T.errDescendantLive,
        descendants,
      }
    }
  }
  return {
    ok: true,
    ids: [...descendants.map((descendant) => descendant.id), id],
    descendants,
  }
}
