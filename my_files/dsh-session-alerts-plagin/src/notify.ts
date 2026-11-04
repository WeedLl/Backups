/**
 * macOS notification transport: `osascript display notification` via
 * `execFile` (no shell), with an optional `terminal-notifier` fast path when
 * the binary is present in PATH. Never writes to stdout/stderr and never
 * throws — failures are reported through the injected warn sink only.
 *
 * Escape discipline (AppleScript string literals are double-quoted, and the
 * whole script is passed as a single argv entry — no shell is involved):
 * double quotes and backslashes are stripped, all whitespace runs collapse
 * to single spaces, and title/body lengths are capped.
 * @module notify
 */
import { execFile } from 'node:child_process'
import { statSync } from 'node:fs'
import { appendFile } from 'node:fs/promises'
import { join } from 'node:path'

export const TITLE_LIMIT = 60
export const BODY_LIMIT = 200
export const EXEC_TIMEOUT_MS = 3000

export interface NotificationPayload {
  title: string
  body: string
  /** System sound name; `'none'` (or empty) means silence. */
  sound: string
  /** Bundle id activated on click (terminal-notifier only); empty = none. */
  activate?: string
}

/**
 * terminal-notifier reads option values through NSUserDefaults, which
 * misparses values whose FIRST character looks like a property list
 * (`[`, `(`, `{`, `"`, `'`). Prefix such values with a backslash.
 */
function escapePlists(value: string): string {
  return /^[[({"']/.test(value) ? '\\' + value : value
}

/** Strip AppleScript-significant characters and collapse whitespace runs. */
export function sanitizeText(text: string): string {
  return text
    .replace(/["\\]/g, '')
    .replace(/\s+/g, ' ')
    .trim()
}

/** Cap a string at `max` code points without breaking surrogate pairs. */
export function capLength(text: string, max: number): string {
  const chars = Array.from(text)
  if (chars.length <= max) return text
  return `${chars.slice(0, Math.max(0, max - 1)).join('')}…`
}

/** Sanitize + cap a notification title. */
export function prepareTitle(title: string): string {
  return capLength(sanitizeText(title), TITLE_LIMIT)
}

/** Sanitize + cap a notification body. */
export function prepareBody(body: string): string {
  return capLength(sanitizeText(body), BODY_LIMIT)
}

/**
 * Build the `osascript` argv for one notification. `-e` receives the whole
 * AppleScript as one argument; no shell quoting is involved, and the
 * sanitized text cannot terminate the double-quoted AppleScript literal.
 */
export function osascriptArgs(payload: NotificationPayload): string[] {
  const title = prepareTitle(payload.title)
  const body = prepareBody(payload.body)
  const script = payload.sound !== 'none' && payload.sound !== ''
    ? `display notification "${body}" with title "${title}" sound name "${payload.sound}"`
    : `display notification "${body}" with title "${title}"`
  return ['-e', script]
}

/**
 * Build the `terminal-notifier` argv. terminal-notifier is silent by
 * default, so the `-sound` flag is only added for a real sound name.
 */
export function terminalNotifierArgs(payload: NotificationPayload): string[] {
  const title = escapePlists(prepareTitle(payload.title))
  const body = escapePlists(prepareBody(payload.body))
  const args = ['-title', title, '-message', body]
  if (payload.sound !== 'none' && payload.sound !== '') args.push('-sound', payload.sound)
  if (typeof payload.activate === 'string' && payload.activate !== '') {
    args.push('-activate', sanitizeText(payload.activate))
  }
  return args
}

/** True when a `terminal-notifier` executable exists in PATH. */
export function findTerminalNotifier(env: { PATH?: string } = process.env): boolean {
  const path = env.PATH
  if (typeof path !== 'string' || path === '') return false
  return path.split(':').some((dir) => {
    if (dir === '') return false
    try {
      return statSync(join(dir, 'terminal-notifier')).isFile()
    } catch {
      return false
    }
  })
}

/** Minimal logger surface; cordis' `ctx.logger(name)` satisfies it. */
export interface WarnSink {
  warn(message: string): void
}

/** execFile-shaped function, injectable for tests. */
export type ExecFileLike = (
  file: string,
  args: string[],
  options: { timeout: number; stdio: 'ignore' },
  callback: (error: Error | null) => void,
) => unknown

export interface NotifierOptions {
  warn: WarnSink
  /** Prefer `terminal-notifier` when available in PATH. */
  preferTerminalNotifier?: boolean
  /** Detected once by the caller; kept here for testability. */
  terminalNotifierAvailable?: boolean
  exec?: ExecFileLike
  timeoutMs?: number
}

export interface Notifier {
  (payload: NotificationPayload): void
}

/**
 * Debug/testing seam: when `DSH_SESSION_ALERTS_LOG_ONLY=1`, the notifier
 * records every payload here instead of spawning osascript /
 * terminal-notifier. Used by the integration tests so they never emit real
 * notifications; never writes to stdout/stderr.
 */
export const capturedPayloads: NotificationPayload[] = []
export function resetCapturedPayloads(): void {
  capturedPayloads.length = 0
}

/**
 * Debug seam for end-to-end verification against the real DSH runtime:
 * when `DSH_SESSION_ALERTS_CAPTURE_FILE=<path>` is set, every payload is
 * appended as one JSON line to that file and nothing is spawned. File errors
 * are swallowed; stdout/stderr are never touched.
 */
function captureToFile(): ((payload: NotificationPayload) => void) | undefined {
  const file = process.env.DSH_SESSION_ALERTS_CAPTURE_FILE
  if (typeof file !== 'string' || file === '') return undefined
  return (payload: NotificationPayload): void => {
    appendFile(file, `${JSON.stringify(payload)}\n`, 'utf8').catch(() => {
      // A capture file that cannot be written must never break the plugin.
    })
  }
}

/**
 * Fire-and-forget notifier. `stdio: 'ignore'` guarantees the TUI-owned
 * stdout/stderr are never touched, and every failure — spawn error, nonzero
 * exit, timeout kill — lands in the warn sink instead of the process.
 */
export function createNotifier(options: NotifierOptions): Notifier {
  const warn = options.warn
  const timeoutMs = options.timeoutMs ?? EXEC_TIMEOUT_MS
  const exec = options.exec ?? execFile
  const useTerminalNotifier = options.preferTerminalNotifier === true && options.terminalNotifierAvailable !== false
  const logOnly = process.env.DSH_SESSION_ALERTS_LOG_ONLY === '1'
  const captureFile = captureToFile()

  return (payload: NotificationPayload): void => {
    if (logOnly) {
      capturedPayloads.push(payload)
      return
    }
    if (captureFile !== undefined) {
      captureFile(payload)
      return
    }
    let command: string
    let args: string[]
    if (useTerminalNotifier) {
      command = 'terminal-notifier'
      args = terminalNotifierArgs(payload)
    } else {
      command = 'osascript'
      args = osascriptArgs(payload)
    }
    try {
      exec(command, args, { timeout: timeoutMs, stdio: 'ignore' }, (error) => {
        if (error !== null) warn.warn(`notification failed (${command}): ${error.message}`)
      })
    } catch (error) {
      warn.warn(`notification failed to spawn (${command}): ${String(error)}`)
    }
  }
}
