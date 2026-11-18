/**
 * Дерево подсессий.
 *
 * Потомком сессии считаются ТОЛЬКО записи с `kind.kind === 'subagent'` и
 * `kind.parent === <id>` (авторитет — `origin`, а не `parentSession`; форки
 * `kind.kind === 'fork'` — независимые копии и в дерево не входят).
 *
 * Порядок результата — «листья → корень» (post-order), чтобы удаление
 * никогда не оставляло осиротевших детей. Сбор защищён от циклов: каждый
 * id обрабатывается не более одного раза.
 * @module dsh-session-delete/tree
 */

/** Дети-подсессии каждого родителя; детерминированный порядок (createdAt, id). */
export function buildChildrenIndex(sessions) {
  const childrenOf = new Map()
  for (const session of sessions ?? []) {
    const kind = session?.kind
    if (kind === null || typeof kind !== 'object') continue
    if (kind.kind !== 'subagent') continue
    const parent = typeof kind.parent === 'string' && kind.parent !== '' ? kind.parent : undefined
    if (parent === undefined) continue
    const list = childrenOf.get(parent) ?? []
    list.push(session)
    childrenOf.set(parent, list)
  }
  for (const list of childrenOf.values()) {
    list.sort((a, b) => {
      const at = typeof a?.createdAt === 'number' ? a.createdAt : 0
      const bt = typeof b?.createdAt === 'number' ? b.createdAt : 0
      if (at !== bt) return at - bt
      return String(a?.id ?? '') < String(b?.id ?? '') ? -1 : 1
    })
  }
  return childrenOf
}

/**
 * Все потомки `rootId` (подсессии и их подсессии рекурсивно), листья →
 * корень, БЕЗ самого `rootId`. Циклы и повторные вхождения (ромбы) не
 * дублируют запись: каждый id попадает в результат один раз.
 *
 * @param {readonly object[]} sessions — полный список сессий хоста.
 * @param {string} rootId — id сессии, чьих потомков собираем.
 * @returns {object[]} сессии-потомки в порядке удаления (листья раньше корня).
 */
export function collectDescendants(sessions, rootId) {
  const childrenOf = buildChildrenIndex(sessions)
  const byId = new Map()
  for (const session of sessions ?? []) {
    if (session !== null && typeof session === 'object' && session.id !== undefined) {
      byId.set(session.id, session)
    }
  }
  const out = []
  const visited = new Set()
  const visit = (id) => {
    if (visited.has(id)) return
    visited.add(id)
    for (const child of childrenOf.get(id) ?? []) visit(child.id)
    if (id !== rootId) {
      const found = byId.get(id)
      if (found !== undefined) out.push(found)
    }
  }
  visit(rootId)
  return out
}
