/**
 * Integration tests: run the real `apply(ctx, config)` against a bare cordis
 * Context, feed synthetic session events / waterfall requests, and assert
 * the notification side effects (captured via the LOG_ONLY seam — no real
 * osascript is ever spawned here).
 */
import assert from 'node:assert/strict'
import { after, before, test } from 'node:test'
import { Context } from '@deepseek-ai/cordis'
import { apply } from '../lib/index.js'
import { capturedPayloads, resetCapturedPayloads } from '../lib/notify.js'

process.env.DSH_SESSION_ALERTS_LOG_ONLY = '1'
process.env.DSH_SESSION_ALERTS_REPLAY_MS = '0'

const BASE_SESSION = {
  id: 'session-abc123',
  header: { cwd: '/Users/weed/projects/demo' },
}

/** Wait for pending timers/microtasks. */
const settle = (ms: number): Promise<void> => new Promise((resolve) => setTimeout(resolve, ms))

function makeContext() {
  const ctx = new Context()
  apply(ctx, { settleMs: 20, debounceMs: 10000, maxPerMinute: 100 })
  return ctx
}

before(() => resetCapturedPayloads())
after(() => {
  delete process.env.DSH_SESSION_ALERTS_LOG_ONLY
  delete process.env.DSH_SESSION_ALERTS_REPLAY_MS
})

test('turn/end completed → one finish notification after settle, with answer text', async () => {
  resetCapturedPayloads()
  const ctx = makeContext()
  ctx.emit('session/event', BASE_SESSION, { type: 'session/title', data: { title: 'Демо-проект' } })
  ctx.emit('session/event', BASE_SESSION, {
    type: 'assistant/message',
    data: { turn: 1, message: { content: [{ type: 'text', text: 'Готово, всё собралось.' }] } },
  })
  ctx.emit('session/event', BASE_SESSION, { type: 'turn/end', data: { turn: 1, reason: { kind: 'completed' } } })
  await settle(60)
  assert.equal(capturedPayloads.length, 1)
  assert.match(capturedPayloads[0]!.title, /ход завершён/)
  assert.match(capturedPayloads[0]!.body, /Демо-проект/)
  assert.match(capturedPayloads[0]!.body, /Готово, всё собралось/)
  assert.equal(capturedPayloads[0]!.sound, 'Glass')
})

test('turn/start inside the settle window cancels the finish notification', async () => {
  resetCapturedPayloads()
  const ctx = makeContext()
  ctx.emit('session/event', BASE_SESSION, { type: 'turn/end', data: { turn: 1, reason: { kind: 'completed' } } })
  ctx.emit('session/event', BASE_SESSION, { type: 'turn/start', data: { turn: 2 } })
  await settle(60)
  assert.equal(capturedPayloads.length, 0)
})

test('session/flush delivers a pending completion immediately (headless path)', async () => {
  resetCapturedPayloads()
  const ctx = makeContext()
  ctx.emit('session/event', BASE_SESSION, { type: 'turn/end', data: { turn: 1, reason: { kind: 'completed' } } })
  // One-shot runners flush right after the turn and then dispose the tree;
  // the notification must arrive at flush, not after the settle timer.
  ctx.emit('session/flush', BASE_SESSION)
  assert.equal(capturedPayloads.length, 1)
  assert.match(capturedPayloads[0]!.title, /ход завершён/)
  // And it fires exactly once: the settle timer must be disarmed.
  await settle(60)
  assert.equal(capturedPayloads.length, 1)
})

test('aborted turn → interrupt notification with reason; error turn → error copy', async () => {
  resetCapturedPayloads()
  const ctx = makeContext()
  ctx.emit('session/event', BASE_SESSION, {
    type: 'turn/end',
    data: { turn: 1, reason: { kind: 'aborted', reason: { kind: 'user' } } },
  })
  await settle(5)
  assert.equal(capturedPayloads.length, 1)
  assert.match(capturedPayloads[0]!.title, /ход прерван/)
  assert.match(capturedPayloads[0]!.body, /прервано пользователем/)
  // soundOnInterrupt defaults to false → silent
  assert.equal(capturedPayloads[0]!.sound, 'none')

  // A different session so the per-session debounce key does not merge them.
  ctx.emit('session/event', { id: 'session-other', header: { cwd: '/tmp' } }, {
    type: 'turn/end',
    data: { turn: 2, reason: { kind: 'error', error: { message: 'provider 500' } } },
  })
  await settle(5)
  assert.equal(capturedPayloads.length, 2)
  assert.match(capturedPayloads[1]!.title, /ошибка/)
  assert.match(capturedPayloads[1]!.body, /provider 500/)
})

test('approval waterfall: notifies AND passes the request through next()', async () => {
  resetCapturedPayloads()
  const ctx = makeContext()
  const outcome = await ctx.waterfall(
    'approval/request',
    { agent: { session: BASE_SESSION }, toolName: 'bash', callId: 'call-1', reason: 'запись вне каталога' },
    () => Promise.resolve('allowed-once'),
  )
  assert.equal(outcome, 'allowed-once') // fallback reached → request not consumed
  assert.equal(capturedPayloads.length, 1)
  assert.match(capturedPayloads[0]!.title, /нужно подтверждение/)
  assert.match(capturedPayloads[0]!.body, /bash/)
  assert.match(capturedPayloads[0]!.body, /запись вне каталога/)
  assert.equal(capturedPayloads[0]!.sound, 'Glass')
})

test('approval request from a subagent is still notified', async () => {
  resetCapturedPayloads()
  const ctx = makeContext()
  const subSession = { id: 'session-sub-1', header: { cwd: '/tmp', origin: 'subagent' } }
  await ctx.waterfall(
    'approval/request',
    { agent: { session: subSession }, toolName: 'web_fetch', callId: 'call-2' },
    () => Promise.resolve('rejected'),
  )
  assert.equal(capturedPayloads.length, 1)
})

test('questions waterfall: notifies with first question and passes through', async () => {
  resetCapturedPayloads()
  const ctx = makeContext()
  const answer = await ctx.waterfall(
    'user-questions/request',
    {
      agent: { session: BASE_SESSION },
      questions: [{ id: 'q1', question: 'Продолжить с вариантом А?' }],
    },
    () => Promise.resolve({ answers: [] }),
  )
  assert.deepEqual(answer, { answers: [] })
  assert.equal(capturedPayloads.length, 1)
  assert.match(capturedPayloads[0]!.title, /вопрос/)
  assert.match(capturedPayloads[0]!.body, /Продолжить с вариантом А/)
})

test('plan-review intent → plan review notification, not a generic question', async () => {
  resetCapturedPayloads()
  const ctx = makeContext()
  await ctx.waterfall(
    'user-questions/request',
    {
      agent: { session: BASE_SESSION },
      questions: [{
        id: 'plan-review',
        question: 'Approve this plan and leave plan mode?',
        intent: { kind: 'plan-review', approve: 'Approve', callId: 'call-9' },
      }],
    },
    () => Promise.resolve({ answers: [] }),
  )
  assert.equal(capturedPayloads.length, 1)
  assert.match(capturedPayloads[0]!.title, /план ждёт ревью/)
})

test('completion while the session waits for approval is suppressed', async () => {
  resetCapturedPayloads()
  const ctx = makeContext()
  await ctx.waterfall(
    'approval/request',
    { agent: { session: BASE_SESSION }, toolName: 'bash', callId: 'call-3' },
    () => Promise.resolve('allowed-once'),
  )
  assert.equal(capturedPayloads.length, 1)
  ctx.emit('session/event', BASE_SESSION, { type: 'turn/end', data: { turn: 1, reason: { kind: 'completed' } } })
  await settle(60)
  assert.equal(capturedPayloads.length, 1) // no second notification
})

test('subagent turn completion is not notified by default; config can enable it', async () => {
  resetCapturedPayloads()
  const subSession = { id: 'session-sub-2', header: { cwd: '/tmp', origin: 'subagent' } }
  const ctx = new Context()
  apply(ctx, { settleMs: 20, debounceMs: 10000, maxPerMinute: 100 })
  ctx.emit('session/event', subSession, { type: 'turn/end', data: { turn: 1, reason: { kind: 'completed' } } })
  await settle(60)
  assert.equal(capturedPayloads.length, 0)

  const ctx2 = new Context()
  apply(ctx2, { settleMs: 20, debounceMs: 10000, maxPerMinute: 100, notifySubagentTurns: true })
  ctx2.emit('session/event', subSession, { type: 'turn/end', data: { turn: 1, reason: { kind: 'completed' } } })
  await settle(60)
  assert.equal(capturedPayloads.length, 1)
})

test('two quick completed turns → debounced to one notification', async () => {
  resetCapturedPayloads()
  const ctx = makeContext()
  ctx.emit('session/event', BASE_SESSION, { type: 'turn/end', data: { turn: 1, reason: { kind: 'completed' } } })
  await settle(40) // first settle window elapses → notification 1
  ctx.emit('session/event', BASE_SESSION, { type: 'turn/end', data: { turn: 2, reason: { kind: 'completed' } } })
  await settle(40)
  assert.equal(capturedPayloads.length, 1) // second suppressed by debounce key finish:session-abc123
})

test('history events (time before plugin start) are never notified', async () => {
  resetCapturedPayloads()
  const ctx = makeContext()
  ctx.emit('session/event', BASE_SESSION, {
    type: 'turn/end', time: 1, // long before apply()
    data: { turn: 1, reason: { kind: 'completed' } },
  })
  await settle(60)
  assert.equal(capturedPayloads.length, 0)
})

test('resumed session (created before plugin start) is silenced during the grace window', async () => {
  resetCapturedPayloads()
  delete process.env.DSH_SESSION_ALERTS_REPLAY_MS // restore default 2000ms
  const ctx = new Context()
  apply(ctx, { settleMs: 20, debounceMs: 10000, maxPerMinute: 100 })
  const resumed = { id: 'session-resumed', header: { cwd: '/tmp', createdAt: Date.now() - 60_000 } }
  ctx.emit('session/event', resumed, { type: 'turn/end', time: Date.now(), data: { turn: 1, reason: { kind: 'completed' } } })
  await settle(60)
  assert.equal(capturedPayloads.length, 0)
  process.env.DSH_SESSION_ALERTS_REPLAY_MS = '0'
})

test('fresh session notifies even immediately after apply (fast headless turn)', async () => {
  resetCapturedPayloads()
  const ctx = makeContext()
  ctx.emit('session/event', BASE_SESSION, { type: 'turn/end', time: Date.now(), data: { turn: 1, reason: { kind: 'completed' } } })
  await settle(60)
  assert.equal(capturedPayloads.length, 1)
})

test('enabled: false silences everything', async () => {
  resetCapturedPayloads()
  const ctx = new Context()
  apply(ctx, { enabled: false, settleMs: 20, debounceMs: 10000, maxPerMinute: 100 })
  ctx.emit('session/event', BASE_SESSION, { type: 'turn/end', data: { turn: 1, reason: { kind: 'completed' } } })
  await settle(60)
  await ctx.waterfall('approval/request', { agent: { session: BASE_SESSION }, toolName: 'bash' }, () => Promise.resolve('rejected'))
  assert.equal(capturedPayloads.length, 0)
})
