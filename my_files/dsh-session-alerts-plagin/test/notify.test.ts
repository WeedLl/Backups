import assert from 'node:assert/strict'
import { test } from 'node:test'
import {
  capLength,
  createNotifier,
  findTerminalNotifier,
  osascriptArgs,
  prepareBody,
  prepareTitle,
  sanitizeText,
  terminalNotifierArgs,
} from '../lib/notify.js'

test('sanitizeText strips quotes/backslashes and collapses whitespace', () => {
  assert.equal(sanitizeText('a"b\\c'), 'abc')
  assert.equal(sanitizeText('line1\nline2\t  line3'), 'line1 line2 line3')
  assert.equal(sanitizeText('  padded  '), 'padded')
})

test('prepareTitle/prepareBody cap at 60 and 200 code points', () => {
  assert.equal(prepareTitle('t'.repeat(100)).length, 60)
  assert.equal(prepareTitle('t'.repeat(100)).endsWith('…'), true)
  assert.equal(prepareBody('b'.repeat(500)).length, 200)
  assert.equal(prepareTitle('ok'), 'ok')
})

test('osascriptArgs builds a single -e script with sound', () => {
  const args = osascriptArgs({ title: 'DSH · ход завершён', body: 'Проект · ответ', sound: 'Glass' })
  assert.equal(args.length, 2)
  assert.equal(args[0], '-e')
  assert.match(args[1]!, /^display notification "Проект · ответ" with title "DSH · ход завершён" sound name "Glass"$/)
})

test('osascriptArgs omits the sound clause for silence', () => {
  const args = osascriptArgs({ title: 't', body: 'b', sound: 'none' })
  assert.equal(args[1], 'display notification "b" with title "t"')
  assert.doesNotMatch(args[1]!, /sound name/)
})

test('osascriptArgs output contains no quotes or backslashes from user text', () => {
  const args = osascriptArgs({ title: 'say "hi" \\ now', body: 'x\ny\\z"', sound: 'Glass' })
  const script = args[1]!
  assert.equal(script.includes('"hi"'), false)
  assert.equal(script.includes('\\'), false)
  assert.equal(script.includes('\n'), false)
})

test('terminalNotifierArgs passes -title/-message and -sound only when sound set', () => {
  assert.deepEqual(
    terminalNotifierArgs({ title: 'T', body: 'B', sound: 'Glass' }),
    ['-title', 'T', '-message', 'B', '-sound', 'Glass'],
  )
  assert.deepEqual(
    terminalNotifierArgs({ title: 'T', body: 'B', sound: 'none' }),
    ['-title', 'T', '-message', 'B'],
  )
})

test('terminalNotifierArgs adds -activate only when set, sanitized', () => {
  assert.deepEqual(
    terminalNotifierArgs({ title: 'T', body: 'B', sound: 'none', activate: 'net.kovidgoyal.kitty' }),
    ['-title', 'T', '-message', 'B', '-activate', 'net.kovidgoyal.kitty'],
  )
  assert.deepEqual(
    terminalNotifierArgs({ title: 'T', body: 'B', sound: 'Glass', activate: '' }),
    ['-title', 'T', '-message', 'B', '-sound', 'Glass'],
  )
})

test('terminal-notifier values starting with plist characters get escaped', () => {
  const args = terminalNotifierArgs({ title: '[T]', body: '(B)', sound: 'none' })
  assert.deepEqual(args, ['-title', '\\[T]', '-message', '\\(B)'])
})

test('createNotifier uses osascript by default and warns on exec failure', () => {
  const warnings: string[] = []
  const calls: Array<{ file: string; args: string[] }> = []
  const notifier = createNotifier({
    warn: { warn: (m) => warnings.push(m) },
    exec: (file, args, _opts, callback) => {
      calls.push({ file, args })
      callback(new Error('killed by timeout'))
    },
  })
  notifier({ title: 't', body: 'b', sound: 'Glass' })
  assert.equal(calls.length, 1)
  assert.equal(calls[0]!.file, 'osascript')
  assert.equal(warnings.length, 1)
  assert.match(warnings[0]!, /notification failed \(osascript\)/)
})

test('createNotifier prefers terminal-notifier when requested', () => {
  const calls: Array<{ file: string }> = []
  const notifier = createNotifier({
    warn: { warn: () => {} },
    preferTerminalNotifier: true,
    terminalNotifierAvailable: true,
    exec: (file, _args, _opts, callback) => {
      calls.push({ file })
      callback(null)
    },
  })
  notifier({ title: 't', body: 'b', sound: 'none' })
  assert.equal(calls[0]!.file, 'terminal-notifier')
})

test('createNotifier never throws on spawn errors', () => {
  const notifier = createNotifier({
    warn: { warn: () => {} },
    exec: () => {
      throw new Error('ENOENT')
    },
  })
  assert.doesNotThrow(() => notifier({ title: 't', body: 'b', sound: 'Glass' }))
})

test('findTerminalNotifier respects PATH', () => {
  assert.equal(findTerminalNotifier({ PATH: '' }), false)
  assert.equal(findTerminalNotifier({}), false)
  // A PATH with only nonexistent dirs must not crash.
  assert.equal(findTerminalNotifier({ PATH: '/definitely/not/here' }), false)
})
