import test from 'node:test'
import assert from 'node:assert/strict'
import {
  existsSync,
  mkdirSync,
  mkdtempSync,
  readFileSync,
  readdirSync,
  rmSync,
  symlinkSync,
  writeFileSync,
} from 'node:fs'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import { defaultRoots, findSessionDirs, removeEmptySessionDirs, sweepSessions } from '../sweep.js'

const ID = 'a1b2c3d4-0000-1111-2222-333344445555'
const OTHER = 'zzz-other'

/** Временное окружение $DSH_HOME/$DSH_TUI_HOME со всеми файловыми целями. */
function makeEnv() {
  const dsh = mkdtempSync(join(tmpdir(), 'dsh-home-'))
  const tui = mkdtempSync(join(tmpdir(), 'dsh-tui-home-'))
  mkdirSync(join(dsh, 'storages', 'session_projcache', 'sessions'), { recursive: true })
  mkdirSync(join(tui, 'session-lists'), { recursive: true })

  // Цели sweep (7) + чужой файл + битый JSON.
  writeFileSync(join(dsh, 'storages', 'session_projcache', 'sessions', `${ID}.json`), '{"cached":true}\n')
  writeFileSync(
    join(dsh, 'storages', 'workspace.json'),
    JSON.stringify({
      unit: { name: 'workspace', version: 2 },
      global: { initialized: true, workspaceIds: ['w1'], archivedSessionIds: [ID, OTHER], pinnedSessionIds: [ID] },
      tables: { workspaces: { w1: { path: '/p', title: 'P', sessionIds: [ID, OTHER, ID] } } },
    }) + '\n',
  )
  writeFileSync(join(tui, 'session-index.json'), JSON.stringify({ version: 4, entries: { [ID]: { x: 1 }, [OTHER]: { x: 2 } } }) + '\n')
  writeFileSync(join(tui, 'session-mounts.json'), JSON.stringify({ version: 1, owners: [{ pid: 1, startedAt: 1, sessionIds: [ID, OTHER] }] }) + '\n')
  writeFileSync(join(tui, 'session-lists', 'list-a.json'), JSON.stringify({ version: 1, rows: [{ id: ID }, { id: OTHER }] }) + '\n')
  writeFileSync(join(tui, 'session-lists', 'list-b.json'), JSON.stringify({ version: 1, rows: [{ id: OTHER }] }) + '\n')
  writeFileSync(join(tui, 'session-pins.json'), JSON.stringify([ID, OTHER]) + '\n')
  writeFileSync(join(tui, 'last-run.json'), JSON.stringify({ backendId: 'dsh', sessionId: ID, cwd: '/p', attemptId: 'x', pid: 1, updatedAt: 1 }) + '\n')

  // Чужие файлы — не трогать.
  mkdirSync(join(dsh, 'storages', 'cost-meter'), { recursive: true })
  writeFileSync(join(dsh, 'storages', 'cost-meter', 'meter.jsonl'), '{"keep":true}\n')
  writeFileSync(join(tui, 'settings.json'), JSON.stringify({ theme: 'dark' }) + '\n')
  writeFileSync(join(tui, 'history.jsonl'), `${ID} something\n`)
  writeFileSync(join(tui, 'session-lists', 'broken.json'), '{not json')

  // Каталоги сессий.
  mkdirSync(join(dsh, 'sessions', '--slug-empty--', ID), { recursive: true })
  mkdirSync(join(dsh, 'sessions', '--slug-full--', OTHER), { recursive: true })
  writeFileSync(join(dsh, 'sessions', '--slug-full--', OTHER, 'log.jsonl'), 'x\n')
  // По-настоящему пустой slug-каталог.
  mkdirSync(join(dsh, 'sessions', '--slug-void--'), { recursive: true })

  return {
    dsh,
    tui,
    options: { dshHome: dsh, tuiHome: tui, now: new Date(2026, 0, 15, 12, 0, 0).getTime() },
    cleanup: () => {
      rmSync(dsh, { recursive: true, force: true })
      rmSync(tui, { recursive: true, force: true })
    },
  }
}

function readJson(path) {
  return JSON.parse(readFileSync(path, 'utf8'))
}

test('sweep вычищает все 7 целей и не трогает чужие файлы', (t) => {
  const env = makeEnv()
  t.after(env.cleanup)
  const { dsh, tui, options } = env

  const result = sweepSessions([ID], options)

  assert.deepEqual(result.skipped, [])
  // Единственная ожидаемая ошибка — битый broken.json (его не трогаем).
  assert.equal(result.errors.length, 1, `errors: ${result.errors.join('; ')}`)
  assert.ok(result.errors[0].includes('broken.json'), result.errors.join('; '))
  assert.ok(result.removed.includes(`projcache/${ID}.json`))

  // 1: projcache-файл удалён.
  assert.ok(!existsSync(join(dsh, 'storages', 'session_projcache', 'sessions', `${ID}.json`)))
  // 2: workspace.json — id вычищен отовсюду, чужой жив.
  const ws = readJson(join(dsh, 'storages', 'workspace.json'))
  assert.deepEqual(ws.tables.workspaces.w1.sessionIds, [OTHER])
  assert.deepEqual(ws.global.pinnedSessionIds, [])
  assert.deepEqual(ws.global.archivedSessionIds, [OTHER])
  // 3: session-index entries.
  const index = readJson(join(tui, 'session-index.json'))
  assert.ok(!(ID in index.entries))
  assert.ok(OTHER in index.entries)
  // 4: mounts.
  const mounts = readJson(join(tui, 'session-mounts.json'))
  assert.deepEqual(mounts.owners[0].sessionIds, [OTHER])
  // 5: session-lists (оба файла прочитаны; list-b не изменился — нет бэкапа).
  const listA = readJson(join(tui, 'session-lists', 'list-a.json'))
  assert.deepEqual(listA.rows, [{ id: OTHER }])
  assert.ok(!existsSync(join(tui, 'session-lists', 'list-b.json.bak-sweep-20260115-120000')))
  // 6: pins.
  assert.deepEqual(readJson(join(tui, 'session-pins.json')), [OTHER])
  // 7: last-run.
  assert.equal(readJson(join(tui, 'last-run.json')).sessionId, '')

  // Бэкапы для каждого ИЗМЕНЁННОГО файла.
  const stamp = '.bak-sweep-20260115-120000'
  for (const name of ['workspace.json', 'session-index.json', 'session-mounts.json', 'session-pins.json', 'last-run.json']) {
    assert.ok(existsSync(join(name === 'workspace.json' ? dsh + '/storages' : tui, `${name}${stamp}`)), `нет бэкапа ${name}`)
  }
  assert.ok(existsSync(join(tui, 'session-lists', `list-a.json${stamp}`)))
  // Бэкап содержит ПРЕЖНЕЕ содержимое.
  assert.ok(ID in readJson(join(tui, `session-index.json${stamp}`)).entries)

  // Чужие файлы целы.
  assert.equal(readFileSync(join(dsh, 'storages', 'cost-meter', 'meter.jsonl'), 'utf8'), '{"keep":true}\n')
  assert.equal(readFileSync(join(tui, 'history.jsonl'), 'utf8'), `${ID} something\n`)
  assert.equal(readJson(join(tui, 'settings.json')).theme, 'dark')
  // Битый JSON не тронут (байт-в-байт) и зафиксирован в ошибках.
  assert.equal(readFileSync(join(tui, 'session-lists', 'broken.json'), 'utf8'), '{not json')
  assert.ok(result.errors.some((e) => e.includes('broken.json')), result.errors.join('; '))
})

test('dryRun ничего не пишет, но отчитывается', (t) => {
  const env = makeEnv()
  t.after(env.cleanup)
  const { dsh, tui, options } = env

  const result = sweepSessions([ID], { ...options, dryRun: true })

  assert.ok(result.removed.includes(`projcache/${ID}.json`))
  assert.ok(result.summary.includes('(dry run)'))
  // Файлы на диске не изменились.
  assert.ok(existsSync(join(dsh, 'storages', 'session_projcache', 'sessions', `${ID}.json`)))
  const ws = readJson(join(dsh, 'storages', 'workspace.json'))
  assert.ok(ws.tables.workspaces.w1.sessionIds.includes(ID))
  const index = readJson(join(tui, 'session-index.json'))
  assert.ok(ID in index.entries)
  // И бэкапов нет.
  const all = readdirSync(tui).filter((f) => f.includes('bak-sweep'))
  assert.deepEqual(all, [])
})

test('whitelist: небезопасные id пропускаются без прикосновения к диску', (t) => {
  const env = makeEnv()
  t.after(env.cleanup)
  const { dsh, options } = env

  const result = sweepSessions(['../evil', 'a b', ID], options)
  assert.deepEqual(result.skipped, ['../evil', 'a b'])
  assert.ok(result.removed.includes(`projcache/${ID}.json`))
  const ws = readJson(join(dsh, 'storages', 'workspace.json'))
  assert.ok(!ws.tables.workspaces.w1.sessionIds.includes(ID))
})

test('backup: false — запись без бэкапов', (t) => {
  const env = makeEnv()
  t.after(env.cleanup)
  const { tui, options } = env

  const result = sweepSessions([ID], { ...options, backup: false })
  // Единственная ошибка — ожидаемый битый broken.json.
  assert.ok(result.errors.every((e) => e.includes('broken.json')), result.errors.join('; '))
  const index = readJson(join(tui, 'session-index.json'))
  assert.ok(!(ID in index.entries))
  const all = readdirSync(tui).filter((f) => f.includes('bak-sweep'))
  assert.deepEqual(all, [])
})

test('нет принятых id → нечего вычищать', (t) => {
  const env = makeEnv()
  t.after(env.cleanup)
  const result = sweepSessions(['../../x'], env.options)
  assert.equal(result.removed.length, 0)
  assert.equal(result.pruned.length, 0)
  assert.equal(result.skipped.length, 1)
  assert.ok(result.summary.includes('whitelist'))
})

test('непарсибельные основные JSON-файлы не трогаются', (t) => {
  const env = makeEnv()
  t.after(env.cleanup)
  const { tui, options } = env
  writeFileSync(join(tui, 'last-run.json'), '{broken')
  const before = readFileSync(join(tui, 'last-run.json'), 'utf8')

  const result = sweepSessions([ID], options)
  assert.equal(readFileSync(join(tui, 'last-run.json'), 'utf8'), before)
  assert.ok(result.errors.some((e) => e.includes('last-run.json')), result.errors.join('; '))
  // Остальные цели всё равно вычищены.
  assert.ok(!(ID in readJson(join(tui, 'session-index.json')).entries))
})

test('findSessionDirs находит каталоги и slug-родителей', (t) => {
  const env = makeEnv()
  t.after(env.cleanup)
  const { dsh, options } = env

  const result = findSessionDirs([ID, OTHER], options)
  const ids = result.found.map((f) => f.id).sort()
  assert.deepEqual(ids, [ID, OTHER].sort())
  const slug = result.found.find((f) => f.id === ID).slug
  assert.equal(slug, '--slug-empty--')
  assert.equal(result.errors.length, 0)
})

test('findSessionDirs не выходит за пределы sessions через symlink', (t) => {
  const env = makeEnv()
  t.after(env.cleanup)
  const { dsh, options } = env
  const outside = mkdtempSync(join(tmpdir(), 'outside-'))
  t.after(() => rmSync(outside, { recursive: true, force: true }))
  mkdirSync(join(outside, ID), { recursive: true })
  symlinkSync(outside, join(dsh, 'sessions', '--evil-link--'))

  const result = findSessionDirs([ID], options)
  // Найдена только легитимная запись из makeEnv; symlink наружу проигнорирован.
  assert.deepEqual(result.found.map((f) => f.slug), ['--slug-empty--'])
  assert.ok(result.found.every((f) => !f.path.includes('evil-link')))
})

test('removeEmptySessionDirs: пустые удаляются, непустые и чужие — нет', (t) => {
  const env = makeEnv()
  t.after(env.cleanup)
  const { dsh, options } = env

  const result = removeEmptySessionDirs(['--slug-void--', '--slug-empty--', '--slug-full--', '--missing--'], options)
  assert.deepEqual(result.removed, ['--slug-void--'])
  assert.ok(!existsSync(join(dsh, 'sessions', '--slug-void--')))
  // slug с каталогом сессии внутри и непустой slug не трогаются.
  assert.ok(existsSync(join(dsh, 'sessions', '--slug-empty--')))
  assert.ok(existsSync(join(dsh, 'sessions', '--slug-full--')))
  assert.equal(result.errors.length, 0)
})

test('removeEmptySessionDirs: symlink наружу не удаляется', (t) => {
  const env = makeEnv()
  t.after(env.cleanup)
  const { dsh, options } = env
  const outside = mkdtempSync(join(tmpdir(), 'outside-2-'))
  t.after(() => rmSync(outside, { recursive: true, force: true }))
  symlinkSync(outside, join(dsh, 'sessions', '--evil-link--'))

  const result = removeEmptySessionDirs(['--evil-link--'], options)
  assert.deepEqual(result.removed, [])
  assert.ok(result.errors.some((e) => e.includes('вне')), result.errors.join('; '))
  assert.ok(existsSync(outside))
})

test('removeEmptySessionDirs: небезопасный slug отклоняется', (t) => {
  const env = makeEnv()
  t.after(env.cleanup)
  const result = removeEmptySessionDirs(['../etc', '..', ''], env.options)
  assert.deepEqual(result.removed, [])
  assert.equal(result.errors.length, 3)
})

test('removeEmptySessionDirs: dryRun не удаляет', (t) => {
  const env = makeEnv()
  t.after(env.cleanup)
  const { dsh, options } = env
  const result = removeEmptySessionDirs(['--slug-void--'], { ...options, dryRun: true })
  assert.deepEqual(result.removed, ['--slug-void--'])
  assert.ok(existsSync(join(dsh, 'sessions', '--slug-void--')))
})

test('sweep не пишет в сессионные каталоги и не падает при отсутствии корней', () => {
  const result = sweepSessions([ID], { dshHome: join(tmpdir(), 'no-such-dsh-home'), tuiHome: join(tmpdir(), 'no-such-tui-home') })
  assert.equal(result.errors.length, 0)
  assert.equal(result.removed.length, 0)
  assert.equal(result.pruned.length, 0)
})

test('defaultRoots: переменные окружения и дефолты', () => {
  const oldDsh = process.env.DSH_HOME
  const oldTui = process.env.DSH_TUI_HOME
  try {
    process.env.DSH_HOME = '/tmp/custom-dsh'
    process.env.DSH_TUI_HOME = '  /tmp/custom-tui  '
    assert.equal(defaultRoots().dshHome, '/tmp/custom-dsh')
    assert.equal(defaultRoots().tuiHome, '/tmp/custom-tui')
    delete process.env.DSH_HOME
    delete process.env.DSH_TUI_HOME
    const roots = defaultRoots()
    assert.ok(roots.dshHome.endsWith('.dsh'))
    assert.ok(roots.tuiHome.endsWith('.dsh-tui'))
  } finally {
    if (oldDsh === undefined) delete process.env.DSH_HOME
    else process.env.DSH_HOME = oldDsh
    if (oldTui === undefined) delete process.env.DSH_TUI_HOME
    else process.env.DSH_TUI_HOME = oldTui
  }
})
