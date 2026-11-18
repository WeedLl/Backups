import test from 'node:test'
import assert from 'node:assert/strict'
import { buildChildrenIndex, collectDescendants } from '../tree.js'

function session(id, kind, createdAt = 0) {
  return { id, kind, createdAt, title: { text: id, source: 'auto' } }
}

const root = () => session('root', { kind: 'root' }, 1)

test('собирает потомков листья → корень, рекурсивно', () => {
  const s1 = session('s1', { kind: 'subagent', parent: 'root', depth: 1 }, 10)
  const s2 = session('s2', { kind: 'subagent', parent: 'root', depth: 1 }, 20)
  const s3 = session('s3', { kind: 'subagent', parent: 's1', depth: 2 }, 30)
  const s4 = session('s4', { kind: 'subagent', parent: 's3', depth: 3 }, 40)
  const sessions = [root(), s2, s4, s1, s3] // список вперемешку

  const out = collectDescendants(sessions, 'root')
  // пост-ордер: листья раньше родителей; среди детей — по createdAt
  assert.deepEqual(out.map((s) => s.id), ['s4', 's3', 's1', 's2'])
})

test('корень не попадает в результат', () => {
  const s1 = session('s1', { kind: 'subagent', parent: 'root', depth: 1 })
  const out = collectDescendants([root(), s1], 'root')
  assert.deepEqual(out.map((s) => s.id), ['s1'])
})

test('форки не потомки', () => {
  const fork = session('fork', { kind: 'fork', parent: 'root' })
  const sub = session('sub', { kind: 'subagent', parent: 'root', depth: 1 })
  const out = collectDescendants([root(), fork, sub], 'root')
  assert.deepEqual(out.map((s) => s.id), ['sub'])
})

test('подсессия без родителя не входит ни в чьё дерево', () => {
  const orphan = session('orphan', { kind: 'subagent', parent: undefined, depth: 0 })
  const out = collectDescendants([root(), orphan], 'root')
  assert.deepEqual(out.map((s) => s.id), [])
})

test('глубина: цепочка из трёх уровней сохраняет порядок листья → корень', () => {
  const a = session('a', { kind: 'subagent', parent: 'root', depth: 1 }, 1)
  const b = session('b', { kind: 'subagent', parent: 'a', depth: 2 }, 2)
  const c = session('c', { kind: 'subagent', parent: 'b', depth: 3 }, 3)
  const out = collectDescendants([root(), c, b, a], 'root')
  assert.deepEqual(out.map((s) => s.id), ['c', 'b', 'a'])
})

test('цикл не зацикливает сбор и не дублирует записи', () => {
  // X → Y → X (оба subagent, родители друг на друга)
  const x = session('x', { kind: 'subagent', parent: 'y', depth: 1 })
  const y = session('y', { kind: 'subagent', parent: 'x', depth: 2 })
  const out = collectDescendants([x, y], 'x')
  assert.deepEqual(out.map((s) => s.id), ['y'])
  // и в обратную сторону
  const out2 = collectDescendants([x, y], 'y')
  assert.deepEqual(out2.map((s) => s.id), ['x'])
})

test('ромб (два родителя, общий потомок) — потомок один раз', () => {
  // root имеет двух детей a и b; у b есть ребёнок c; у a ребёнок тоже c
  // (искусственно: buildChildrenIndex отдаст c под обоими родителями)
  const a = session('a', { kind: 'subagent', parent: 'root', depth: 1 }, 1)
  const b = session('b', { kind: 'subagent', parent: 'root', depth: 1 }, 2)
  const c = session('c', { kind: 'subagent', parent: 'a', depth: 2 }, 3)
  const c2 = session('c', { kind: 'subagent', parent: 'b', depth: 2 }, 3)
  const out = collectDescendants([root(), a, b, c, c2], 'root')
  assert.deepEqual(out.map((s) => s.id).sort(), ['a', 'b', 'c'])
})

test('пустой и невалидный ввод не падают', () => {
  assert.deepEqual(collectDescendants([], 'root'), [])
  assert.deepEqual(collectDescendants(undefined, 'root'), [])
  assert.deepEqual(collectDescendants([null, {}, 42], 'root'), [])
})

test('buildChildrenIndex отдаёт детей в порядке createdAt, затем id', () => {
  const late = session('late', { kind: 'subagent', parent: 'p', depth: 1 }, 50)
  const early = session('early', { kind: 'subagent', parent: 'p', depth: 1 }, 5)
  const same = session('a', { kind: 'subagent', parent: 'p', depth: 1 }, 10)
  const same2 = session('b', { kind: 'subagent', parent: 'p', depth: 1 }, 10)
  const index = buildChildrenIndex([late, same, early, same2])
  assert.deepEqual(index.get('p').map((s) => s.id), ['early', 'a', 'b', 'late'])
})
