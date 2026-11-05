import test from 'node:test'
import assert from 'node:assert/strict'
import {
  filterSessions,
  formatAge,
  isEmptyArtifact,
  kindOf,
  matchesQuery,
  shortCwd,
  sortSessions,
  truncate,
} from '../session-ops.js'

function session(id, updatedAt, { title = `Задача ${id}`, cwd = '/Users/weed/proj' } = {}) {
  return {
    id,
    updatedAt,
    title: { text: title, source: 'renamed' },
    cwd,
    kind: { kind: 'root' },
    createdAt: updatedAt - 1000,
  }
}

test('сортировка по updatedAt убывает, стабильно', () => {
  const a = session('a', 100)
  const b = session('b', 300)
  const c = session('c', 200)
  const d = session('d', 200)
  const out = sortSessions([a, b, c, d])
  assert.deepEqual(out.map((s) => s.id), ['b', 'c', 'd', 'a'])
})

test('сортировка терпима к отсутствию updatedAt', () => {
  const a = session('a', 100)
  const noTime = { id: 'x', title: { text: 'x', source: 'auto' }, cwd: '', kind: { kind: 'root' } }
  const out = sortSessions([noTime, a])
  assert.deepEqual(out.map((s) => s.id), ['a', 'x'])
})

test('пустой список и undefined не падают', () => {
  assert.deepEqual(sortSessions([]), [])
  assert.deepEqual(sortSessions(undefined), [])
  assert.deepEqual(filterSessions([], 'x'), [])
})

test('регистронезависимый поиск по title/cwd/id', () => {
  const s = session('Abc-123', 100, { title: 'Рефакторинг', cwd: '/Users/weed/MyProject' })
  assert.ok(matchesQuery(s, 'рефактор'))
  assert.ok(matchesQuery(s, 'РЕФАКТОР'))
  assert.ok(matchesQuery(s, 'myproject'))
  assert.ok(matchesQuery(s, 'ABC-1'))
  assert.ok(!matchesQuery(s, 'нет такого'))
})

test('фильтр пустой строки возвращает исходный список', () => {
  const list = [session('a', 2), session('b', 1)]
  assert.equal(filterSessions(list, ''), list)
  assert.equal(filterSessions(list, '   '), list)
})

test('фильтр по подстроке оставляет только совпадения', () => {
  const list = [
    session('a', 3, { title: 'Первый' }),
    session('b', 2, { title: 'Второй' }),
    session('c', 1, { title: 'первый же' }),
  ]
  const out = filterSessions(list, 'Первый')
  assert.deepEqual(out.map((s) => s.id), ['a', 'c'])
})

test('kindOf: объект и плоская строка', () => {
  assert.equal(kindOf({ kind: { kind: 'root' } }), 'root')
  assert.equal(kindOf({ kind: { kind: 'subagent', parent: 'p', depth: 1 } }), 'subagent')
  assert.equal(kindOf({ kind: 'fork' }), 'fork')
  assert.equal(kindOf({}), undefined)
  assert.equal(kindOf(undefined), undefined)
})

test('isEmptyArtifact: только доказанно пустые', () => {
  const base = {
    kind: { kind: 'root' },
    hasPrompt: false,
    bytes: 512,
    title: { text: 'cwd', source: 'fallback' },
  }
  assert.ok(isEmptyArtifact(base))
  assert.ok(!isEmptyArtifact({ ...base, bytes: 4096 }))
  assert.ok(!isEmptyArtifact({ ...base, hasPrompt: true }))
  assert.ok(!isEmptyArtifact({ ...base, title: { text: 'x', source: 'auto' } }))
  assert.ok(!isEmptyArtifact({ ...base, kind: { kind: 'subagent', parent: 'p', depth: 1 } }))
  assert.ok(!isEmptyArtifact(null))
  assert.ok(!isEmptyArtifact({}))
})

test('shortCwd: домашний каталог → ~, пусто → —', () => {
  assert.equal(shortCwd('/Users/weed/proj', '/Users/weed'), '~/proj')
  assert.equal(shortCwd('/Users/weed', '/Users/weed'), '~')
  assert.equal(shortCwd('/tmp/x', '/Users/weed'), '/tmp/x')
  assert.equal(shortCwd('', '/Users/weed'), '—')
  assert.equal(shortCwd(undefined, '/Users/weed'), '—')
  assert.equal(shortCwd('/Users/weeden/x', '/Users/weed'), '/Users/weeden/x')
})

test('formatAge: минуты/часы/дни', () => {
  const now = Date.now()
  assert.equal(formatAge(now - 30_000), 'только что')
  assert.equal(formatAge(now - 12 * 60_000), '12 мин')
  assert.equal(formatAge(now - 3 * 60 * 60_000), '3 ч')
  assert.equal(formatAge(now - 9 * 24 * 60 * 60_000), '9 дн')
  assert.equal(formatAge(undefined), '')
  assert.equal(formatAge('soon'), '')
})

test('truncate: обрезка с многоточием', () => {
  assert.equal(truncate('короткая', 20), 'короткая')
  assert.equal(truncate('длинная строка', 7), 'длинна…')
  assert.equal(truncate('x', 1), 'x')
  assert.equal(truncate('abc', 0), '')
})
