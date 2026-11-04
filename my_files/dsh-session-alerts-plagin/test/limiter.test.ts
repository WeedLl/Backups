import assert from 'node:assert/strict'
import { test } from 'node:test'
import { DebounceGate, SlidingRateLimiter } from '../lib/limiter.js'

/** Mutable fake clock. */
function fakeClock(start = 0) {
  const state = { now: start }
  const clock = { now: () => state.now }
  const advance = (ms: number) => {
    state.now += ms
  }
  return { clock, advance }
}

test('DebounceGate suppresses repeats within the window and allows after it', () => {
  const { clock, advance } = fakeClock()
  const gate = new DebounceGate(10_000, clock)
  assert.equal(gate.allow('a'), true)
  assert.equal(gate.allow('a'), false)
  assert.equal(gate.allow('b'), true)
  advance(9_999)
  assert.equal(gate.allow('a'), false)
  advance(2)
  assert.equal(gate.allow('a'), true)
})

test('DebounceGate.forget releases a key', () => {
  const gate = new DebounceGate(10_000)
  assert.equal(gate.allow('x'), true)
  assert.equal(gate.allow('x'), false)
  gate.forget('x')
  assert.equal(gate.allow('x'), true)
})

test('SlidingRateLimiter caps per rolling minute', () => {
  const { clock, advance } = fakeClock()
  const limiter = new SlidingRateLimiter(60_000, 3, clock)
  assert.equal(limiter.allow(), true)
  assert.equal(limiter.allow(), true)
  assert.equal(limiter.allow(), true)
  assert.equal(limiter.allow(), false)
  advance(59_999)
  assert.equal(limiter.allow(), false)
  advance(2)
  assert.equal(limiter.allow(), true)
})

test('SlidingRateLimiter frees old hits as the window slides', () => {
  const { clock, advance } = fakeClock()
  const limiter = new SlidingRateLimiter(60_000, 2, clock)
  assert.equal(limiter.allow(), true)
  advance(30_000)
  assert.equal(limiter.allow(), true)
  advance(30_001) // first hit older than 60s
  assert.equal(limiter.allow(), true)
})
