import test from 'node:test'
import assert from 'node:assert/strict'
import {
  existsSync,
  mkdirSync,
  mkdtempSync,
  readFileSync,
  readdirSync,
  rmSync,
  writeFileSync,
} from 'node:fs'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import { cleanInboxState, collectSessionIds } from '../sweep.js'

const ALIVE = 'a1b2c3d4-0000-1111-2222-333344445555'
const ALSO_ALIVE = 'zzz-other'
const STALE = 'stale-finished'
const RUNNING = 'stale-running'
const NOW = new Date(2026, 0, 15, 12, 0, 0).getTime()

function row(id, status) {
  return {
    id,
    cwd: '/tmp/project',
    title: id,
    status,
    failed: false,
    updatedAt: NOW - 1000,
    finishedAt: status === 'finished' ? NOW - 1000 : 0,
    seenAt: 0,
  }
}

/** Временные $DSH_HOME/$DSH_TUI_HOME: две живые сессии и две «мёртвые» строки. */
function makeEnv() {
  const dsh = mkdtempSync(join(tmpdir(), 'dsh-janitor-home-'))
  const tui = mkdtempSync(join(tmpdir(), 'dsh-janitor-tui-'))
  mkdirSync(join(dsh, 'sessions', '--slug--', ALIVE), { recursive: true })
  mkdirSync(join(dsh, 'sessions', '--slug--', ALSO_ALIVE), { recursive: true })
  const file = join(tui, 'workspace-sidebar.json')
  writeFileSync(
    file,
    JSON.stringify({
      version: 1,
      sessions: {
        [ALIVE]: row(ALIVE, 'finished'),
        [ALSO_ALIVE]: row(ALSO_ALIVE, 'finished'),
        [STALE]: row(STALE, 'finished'),
        [RUNNING]: row(RUNNING, 'running'),
      },
    }, null, 2) + '\n',
  )
  return {
    dsh,
    tui,
    file,
    cleanup: () => {
      rmSync(dsh, { recursive: true, force: true })
      rmSync(tui, { recursive: true, force: true })
    },
  }
}

function readJson(file) {
  return JSON.parse(readFileSync(file, 'utf8'))
}

test('collectSessionIds: собирает id из slug-каталогов, отсутствие корня — undefined', (t) => {
  const env = makeEnv()
  t.after(env.cleanup)

  const ids = collectSessionIds(join(env.dsh, 'sessions'))
  assert.ok(ids instanceof Set)
  assert.ok(ids.has(ALIVE))
  assert.ok(ids.has(ALSO_ALIVE))
  assert.equal(ids.has(STALE), false)

  assert.equal(collectSessionIds(join(env.dsh, 'no-such-sessions')), undefined)
})

test('janitor удаляет только finished-строки без каталога сессии', (t) => {
  const env = makeEnv()
  t.after(env.cleanup)

  const result = cleanInboxState({ dshHome: env.dsh, tuiHome: env.tui, now: NOW })
  assert.equal(result.changed, true)
  assert.deepEqual(result.removed, [STALE])
  assert.deepEqual(result.errors, [])

  const state = readJson(env.file)
  assert.ok(ALIVE in state.sessions)
  assert.ok(ALSO_ALIVE in state.sessions)
  assert.ok(RUNNING in state.sessions, 'running-строку трогать нельзя')
  assert.ok(!(STALE in state.sessions))

  // Бэкап содержит прежнее содержимое, включая удалённую строку.
  const backups = readdirSync(env.tui).filter((name) => name.startsWith('workspace-sidebar.json.bak-janitor-'))
  assert.equal(backups.length, 1)
  assert.ok(STALE in readJson(join(env.tui, backups[0])).sessions)
})

test('janitor идемпотентен: повторный запуск ничего не меняет', (t) => {
  const env = makeEnv()
  t.after(env.cleanup)

  const first = cleanInboxState({ dshHome: env.dsh, tuiHome: env.tui, now: NOW })
  assert.equal(first.changed, true)
  const afterFirst = readFileSync(env.file, 'utf8')
  const second = cleanInboxState({ dshHome: env.dsh, tuiHome: env.tui, now: NOW })
  assert.equal(second.changed, false)
  assert.deepEqual(second.removed, [])
  assert.equal(readFileSync(env.file, 'utf8'), afterFirst)
})

test('битый JSON и нечитаемый sessions оставляют файл нетронутым', (t) => {
  const env = makeEnv()
  t.after(env.cleanup)

  writeFileSync(env.file, '{broken')
  const broken = cleanInboxState({ dshHome: env.dsh, tuiHome: env.tui, now: NOW })
  assert.equal(broken.changed, false)
  assert.ok(broken.errors.some((error) => error.includes('непарсибельный')))
  assert.equal(readFileSync(env.file, 'utf8'), '{broken')

  // Нет каталога sessions — нельзя доказать, что сессии мертвы.
  rmSync(join(env.dsh, 'sessions'), { recursive: true, force: true })
  const good = JSON.stringify({ version: 1, sessions: { [STALE]: row(STALE, 'finished') } }) + '\n'
  writeFileSync(env.file, good)
  const noRoot = cleanInboxState({ dshHome: env.dsh, tuiHome: env.tui, now: NOW })
  assert.equal(noRoot.changed, false)
  assert.ok(noRoot.errors.some((error) => error.includes('sessions')))
  assert.equal(readFileSync(env.file, 'utf8'), good)
})

test('нет файла — skip; backup:false — без бэкапа', (t) => {
  const env = makeEnv()
  t.after(env.cleanup)

  const missing = cleanInboxState({ dshHome: env.dsh, tuiHome: env.tui, stateFile: join(env.tui, 'nope.json') })
  assert.equal(missing.changed, false)
  assert.ok(missing.skipped.some((text) => text.includes('отсутствует')))

  const result = cleanInboxState({ dshHome: env.dsh, tuiHome: env.tui, backup: false, now: NOW })
  assert.equal(result.changed, true)
  assert.ok(!existsSync(join(env.tui, `workspace-sidebar.json.bak-janitor-20260115-120000`)))
  assert.ok(readdirSync(env.tui).every((name) => !name.startsWith('workspace-sidebar.json.bak-janitor-')))
})
