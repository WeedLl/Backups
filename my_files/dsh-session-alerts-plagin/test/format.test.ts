import assert from 'node:assert/strict'
import { test } from 'node:test'
import {
  cancelCauseText,
  errorText,
  extractAssistantText,
  formatApprovalBody,
  formatFinishBody,
  formatInterruptBody,
  formatQuestionBody,
  joinBody,
  sessionLabel,
  truncate,
} from '../lib/format.js'

test('truncate keeps short strings intact and caps long ones at code points', () => {
  assert.equal(truncate('abc', 5), 'abc')
  assert.equal(truncate('abcdef', 5), 'abcd…')
  assert.equal(truncate('', 5), '')
  assert.equal(truncate('hello', 0), '')
  // surrogate pairs are not split in half
  assert.equal(truncate('😀😀😀', 2), '😀…')
})

test('sessionLabel prefers title, falls back to cwd basename then short id', () => {
  assert.equal(sessionLabel({ id: 'abc123' }, '  My Title  ', 'ru'), 'My Title')
  assert.equal(sessionLabel({ id: 'abc123', header: { cwd: '/Users/weed/projects/x' } }, '', 'ru'), 'x')
  assert.equal(sessionLabel({ id: 'session-12345678' }, undefined, 'ru'), 'session-')
  assert.equal(sessionLabel({}, undefined, 'ru'), 'сессия')
  assert.equal(sessionLabel(null, undefined, 'en'), 'session')
})

test('extractAssistantText joins only text blocks', () => {
  assert.equal(
    extractAssistantText({ content: [{ type: 'text', text: 'hi' }, { type: 'reasoning', text: 'thinking' }, { type: 'text', text: ' there' }] }),
    'hi there',
  )
  assert.equal(extractAssistantText({ content: [{ type: 'tool-call' }] }), '')
  assert.equal(extractAssistantText(undefined), '')
  assert.equal(extractAssistantText({}), '')
})

test('cancelCauseText maps causes per language', () => {
  assert.equal(cancelCauseText({ kind: 'user' }, 'ru'), 'прервано пользователем')
  assert.equal(cancelCauseText({ kind: 'user' }, 'en'), 'cancelled by user')
  assert.equal(cancelCauseText({ kind: 'hook', reason: 'policy' }, 'ru'), 'прервано хуком: policy')
  assert.equal(cancelCauseText({ kind: 'legacy' }, 'ru'), 'прервано')
  assert.equal(cancelCauseText(undefined, 'en'), 'cancelled')
})

test('errorText renders aborted cause, error message, code fallback', () => {
  assert.equal(errorText({ kind: 'aborted', reason: { kind: 'parent' } }, 'ru'), 'прервано родителем')
  assert.equal(errorText({ kind: 'error', error: { message: 'boom' } }, 'en'), 'boom')
  assert.equal(errorText({ kind: 'error', error: { code: 'X1' } }, 'ru'), 'ошибка: X1')
  assert.equal(errorText({ kind: 'error', error: {} }, 'ru'), 'ошибка')
  assert.equal(errorText({ kind: 'max-tokens' }, 'ru'), 'max-tokens')
})

test('joinBody drops empty parts and joins with middle dot', () => {
  assert.equal(joinBody('a', '', 'b', undefined, '  '), 'a · b')
  assert.equal(joinBody('', ''), '')
})

test('formatFinishBody: label + answer, capped; label only when no answer', () => {
  assert.equal(formatFinishBody('Проект', 'ответ', 200), 'Проект · ответ')
  assert.equal(formatFinishBody('Проект', '   ', 200), 'Проект')
  assert.equal(formatFinishBody('Проект', 'x'.repeat(300), 200).length, 200)
})

test('formatInterruptBody/ApprovalBody/QuestionBody join and cap', () => {
  assert.equal(formatInterruptBody('прервано пользователем', 'Проект', 200), 'прервано пользователем · Проект')
  assert.equal(formatApprovalBody('bash', 'Проект', undefined, 200), 'bash · Проект')
  assert.equal(formatApprovalBody('bash', 'Проект', 'запись вне каталога', 200), 'bash · Проект · запись вне каталога')
  assert.equal(formatQuestionBody('Продолжить?', 'Проект', 200), 'Продолжить? · Проект')
})
