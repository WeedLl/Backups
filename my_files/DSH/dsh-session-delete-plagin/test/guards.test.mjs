import test from 'node:test'
import assert from 'node:assert/strict'
import { checkDeletionTarget, SAFE_ID } from '../session-ops.js'

function session(id, kind, extra = {}) {
  return { id, kind, title: { text: `title-${id}`, source: 'auto' }, cwd: '/tmp', createdAt: 1, updatedAt: 1, ...extra }
}

const root = () => session('root-1', { kind: 'root' })

test('whitelist: допустимые и недопустимые id', () => {
  assert.ok(SAFE_ID.test('session-a2584cdd-59aa-415b-af36-e23efc751d5e'))
  assert.ok(SAFE_ID.test('a-b_c'))
  assert.ok(!SAFE_ID.test('../evil'))
  assert.ok(!SAFE_ID.test('a b'))
  assert.ok(!SAFE_ID.test(''))
  assert.ok(!SAFE_ID.test('-lead'))
  assert.ok(!SAFE_ID.test('a/b'))
  assert.ok(!SAFE_ID.test('a\u0000b'))
})

test('target отсутствует → missing', () => {
  const verdict = checkDeletionTarget({ target: undefined, sessions: [root()], rowsById: new Map() })
  assert.equal(verdict.ok, false)
  assert.equal(verdict.reason, 'missing')
})

test('небезопасный id → unsafe', () => {
  const verdict = checkDeletionTarget({ target: session('../evil', { kind: 'root' }), sessions: [], rowsById: new Map() })
  assert.equal(verdict.ok, false)
  assert.equal(verdict.reason, 'unsafe')
})

test('id не в списке → missing', () => {
  const target = session('ghost', { kind: 'root' })
  const verdict = checkDeletionTarget({ target, sessions: [root()], rowsById: new Map() })
  assert.equal(verdict.ok, false)
  assert.equal(verdict.reason, 'missing')
})

test('текущая сессия (agentViewRows.current) → current', () => {
  const target = root()
  const rows = new Map([[target.id, { id: target.id, current: true, live: true }]])
  const verdict = checkDeletionTarget({ target, sessions: [target], rowsById: rows })
  assert.equal(verdict.ok, false)
  assert.equal(verdict.reason, 'current')
})

test('текущая сессия (attachedSessionId) → current', () => {
  const target = root()
  const verdict = checkDeletionTarget({ target, sessions: [target], rowsById: new Map(), attachedSessionId: target.id })
  assert.equal(verdict.ok, false)
  assert.equal(verdict.reason, 'current')
})

test('live-сессия → live', () => {
  const target = root()
  const rows = new Map([[target.id, { id: target.id, current: false, live: true }]])
  const verdict = checkDeletionTarget({ target, sessions: [target], rowsById: rows })
  assert.equal(verdict.ok, false)
  assert.equal(verdict.reason, 'live')
})

test('live-потомок блокирует всё дерево', () => {
  const target = root()
  const sub = session('sub-1', { kind: 'subagent', parent: target.id, depth: 1 })
  const rows = new Map([[sub.id, { id: sub.id, current: false, live: true }]])
  const verdict = checkDeletionTarget({ target, sessions: [target, sub], rowsById: rows })
  assert.equal(verdict.ok, false)
  assert.equal(verdict.reason, 'descendant-live')
  assert.deepEqual(verdict.descendants.map((s) => s.id), ['sub-1'])
})

test('текущая среди потомков блокирует всё дерево', () => {
  const target = root()
  const sub = session('sub-1', { kind: 'subagent', parent: target.id, depth: 1 })
  const verdict = checkDeletionTarget({ target, sessions: [target, sub], rowsById: new Map(), attachedSessionId: sub.id })
  assert.equal(verdict.ok, false)
  assert.equal(verdict.reason, 'descendant-current')
})

test('чистый план: потомки от листьев, затем цель', () => {
  const target = root()
  const s1 = session('s1', { kind: 'subagent', parent: target.id, depth: 1 }, { createdAt: 10 })
  const s2 = session('s2', { kind: 'subagent', parent: target.id, depth: 1 }, { createdAt: 20 })
  const s3 = session('s3', { kind: 'subagent', parent: 's1', depth: 2 }, { createdAt: 30 })
  const fork = session('fork-1', { kind: 'fork', parent: target.id })
  const verdict = checkDeletionTarget({
    target,
    sessions: [target, fork, s3, s1, s2],
    rowsById: new Map(),
  })
  assert.equal(verdict.ok, true)
  assert.deepEqual(verdict.ids, ['s3', 's1', 's2', target.id])
  assert.equal(verdict.descendants.length, 3)
})

test('archived не блокирует удаление (архив — просто бейдж)', () => {
  const target = session('arch-1', { kind: 'root' }, { archived: true })
  const verdict = checkDeletionTarget({ target, sessions: [target], rowsById: new Map() })
  assert.equal(verdict.ok, true)
})

test('rowsById без записи о цели — не мешает удалению', () => {
  const target = root()
  const verdict = checkDeletionTarget({ target, sessions: [target], rowsById: new Map() })
  assert.equal(verdict.ok, true)
  assert.deepEqual(verdict.ids, [target.id])
})
