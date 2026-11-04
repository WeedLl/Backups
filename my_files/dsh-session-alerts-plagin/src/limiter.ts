/**
 * Anti-spam gates: per-key debounce and a global per-minute rate limit.
 * Clock-injected and free of I/O so unit tests are deterministic.
 * @module limiter
 */

export interface Clock {
  now(): number
}

/** Suppress repeats of the same dedup key within a window. */
export class DebounceGate {
  private readonly last: Map<string, number> = new Map()

  constructor(
    private readonly windowMs: number,
    private readonly clock: Clock = Date,
  ) {}

  /**
   * True when the key is allowed through (and recorded), false when the key
   * was already seen inside the window.
   */
  allow(key: string): boolean {
    const now = this.clock.now()
    const prev = this.last.get(key)
    if (prev !== undefined && now - prev < this.windowMs) return false
    this.last.set(key, now)
    // Bound the map: never more than a few hundred live keys.
    if (this.last.size > 512) {
      for (const [k, t] of this.last) {
        if (now - t >= this.windowMs) this.last.delete(k)
      }
    }
    return true
  }

  /** Forget one key (e.g. when a scheduled notification is cancelled). */
  forget(key: string): void {
    this.last.delete(key)
  }
}

/** Cap the number of allowed notifications per rolling window. */
export class SlidingRateLimiter {
  private readonly hits: number[] = []

  constructor(
    private readonly windowMs: number,
    private readonly max: number,
    private readonly clock: Clock = Date,
  ) {}

  /** True when under the limit (and recorded), false when the window is full. */
  allow(): boolean {
    const now = this.clock.now()
    const cutoff = now - this.windowMs
    while (this.hits.length > 0 && this.hits[0]! <= cutoff) this.hits.shift()
    if (this.hits.length >= this.max) return false
    this.hits.push(now)
    return true
  }
}
