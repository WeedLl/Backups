/**
 * session-alerts — macOS system notifications for DSH sessions.
 *
 * A host-only cordis plugin. One standing host composition observes every
 * session (foreground, background, subagents — scope dispatch flows UP the
 * chain, and an unscoped root listener receives all of them) and pushes
 * notifications for:
 *
 * - `turn/end` `completed` — after a settle delay that a next `turn/start`
 *   cancels; the body carries the session title and the last model answer;
 * - `turn/end` `aborted` / `error` / `max-tokens` — interrupt/error copy;
 * - `approval/request` (waterfall) — passive: notify and always `next()`;
 * - `user-questions/request` (waterfall) — same; `intent.kind ===
 *   'plan-review'` (raised by dsh-plan-mode's `exit_plan_mode`) is notified
 *   as "план ждёт ревью";
 *
 * Anti-spam: per-session completion settlement, debounce keyed by
 * kind+session+callId/id, a global per-minute cap, a 2-second replay grace
 * window, and completion suppression while the session waits for an
 * approval/question. Subagent TURN notifications are off by default; their
 * approvals and questions are always notified.
 *
 * The plugin writes nothing to stdout/stderr: notifications go through
 * `execFile('osascript', …)` (or `terminal-notifier` when present) with
 * `stdio: 'ignore'`, a 3-second timeout, and failures degrade to a logger
 * warning.
 * @module index
 */
import { appendFile } from 'node:fs/promises'
import type { Context } from '@deepseek-ai/cordis'
import { Config, effectiveSound, resolveConfig, type ResolvedConfig, type SessionAlertsConfig } from './config.js'
import { isSubagentSession, type ApprovalRequestLike, type AssistantMessageLike, type SessionEventLike, type SessionLike, type TurnEndDataLike, type UserQuestionsRequestLike } from './events.js'
import {
  errorText,
  extractAssistantText,
  formatApprovalBody,
  formatFinishBody,
  formatInterruptBody,
  formatQuestionBody,
  phrases,
  sessionLabel,
} from './format.js'
import { DebounceGate, SlidingRateLimiter } from './limiter.js'
import { BODY_LIMIT, createNotifier, findTerminalNotifier, type Notifier } from './notify.js'
import { REPLAY_GRACE_MS } from './config.js'

export const name = 'session-alerts'

export { Config }
export type { SessionAlertsConfig, ResolvedConfig } from './config.js'

/** Per-session runtime bookkeeping. */
interface SessionState {
  /** Latest folded `session/title`. */
  title?: string
  /** Last assistant answer seen (any turn) and its turn number. */
  lastAssistant?: { turn?: number; text: string }
  /** Pending completion notification timer (the settle window). */
  pendingFinish?: NodeJS.Timeout
  /** The session waits for an approval/question that we already notified. */
  interacting: boolean
}

/** Title composed from the configured prefix and the event copy. */
function makeTitle(prefix: string, text: string): string {
  return prefix === '' ? text : `${prefix} · ${text}`
}

export function apply(ctx: Context, config: SessionAlertsConfig = {}): void {
  const resolved: ResolvedConfig = resolveConfig(config)
  const logger = ctx.logger('session-alerts')
  const warn = (message: string): void => {
    try {
      logger.warn(message)
    } catch {
      // Logging must never throw back into an event handler.
    }
  }

  const startedAt = Date.now()
  /**
   * Replay suppression. DSH never publishes seed history on `session/event`
   * (restored sessions emit only synthetic `turn/end interrupted` closers,
   * which this plugin ignores), so a blind wall-clock window would swallow
   * legitimate fast turns of brand-new sessions (a headless one-shot can
   * finish under two seconds). Replay is therefore detected by facts:
   *
   * - an event stamped before the plugin started is history;
   * - a session created before the plugin started (resume at boot) is
   *   additionally silenced for the grace window, covering the resume
   *   closers appended during startup.
   *
   * `DSH_SESSION_ALERTS_REPLAY_MS` overrides the grace window (integration
   * tests set it to 0).
   */
  const replayGraceMs = (() => {
    const raw = Number(process.env.DSH_SESSION_ALERTS_REPLAY_MS)
    return Number.isFinite(raw) && raw >= 0 ? raw : REPLAY_GRACE_MS
  })()
  const isReplay = (session: SessionLike, event: SessionEventLike): boolean => {
    if (typeof event.time === 'number' && event.time < startedAt) return true
    const createdAt = session?.header?.createdAt
    if (typeof createdAt === 'number' && createdAt < startedAt && Date.now() - startedAt < replayGraceMs) return true
    return false
  }

  /**
   * Diagnostic trace seam: when `DSH_SESSION_ALERTS_DEBUG_FILE=<path>` is
   * set, plugin lifecycle, received events, and dispatch decisions are
   * appended as JSON lines to that file. File errors are swallowed; nothing
   * is written to stdout/stderr. Off by default, zero overhead otherwise.
   */
  const debugFile = process.env.DSH_SESSION_ALERTS_DEBUG_FILE
  const debug = (entry: unknown): void => {
    if (typeof debugFile !== 'string' || debugFile === '') return
    void appendFile(debugFile, `${JSON.stringify(entry)}\n`, 'utf8').catch(() => {
      // A debug file that cannot be written must never break the plugin.
    })
  }
  debug({ kind: 'apply', startedAt })

  const notifier: Notifier = createNotifier({
    warn: { warn },
    preferTerminalNotifier: findTerminalNotifier(),
  })
  const debounce = new DebounceGate(resolved.debounceMs)
  const rateLimit = new SlidingRateLimiter(60_000, resolved.maxPerMinute)

  const p = phrases(resolved.lang)
  const sessions = new Map<string, SessionState>()

  const stateOf = (session: SessionLike | undefined | null): SessionState | undefined => {
    const key = String(session?.id ?? '')
    if (key === '') return undefined
    let state = sessions.get(key)
    if (state === undefined) {
      state = { interacting: false }
      sessions.set(key, state)
    }
    return state
  }

  const cancelPendingFinish = (state: SessionState | undefined): void => {
    if (state === undefined || state.pendingFinish === undefined) return
    clearTimeout(state.pendingFinish)
    state.pendingFinish = undefined
  }

  /** Gate + send one notification; returns whether it was actually sent. */
  const dispatch = (
    dedupKey: string,
    title: string,
    body: string,
    sound: string,
  ): boolean => {
    if (!resolved.enabled) return false
    if (!debounce.allow(dedupKey)) return false
    if (!rateLimit.allow()) return false
    notifier({ title, body, sound, activate: resolved.activate })
    return true
  }

  // ---- turn lifecycle ----------------------------------------------------

  const onTurnStart = (session: SessionLike, state: SessionState): void => {
    // A new turn in the same session cancels the pending completion
    // notification of the previous one.
    cancelPendingFinish(state)
  }

  /** Send the pending completion notification now and disarm the timer. */
  const firePendingFinish = (session: SessionLike, state: SessionState): void => {
    if (state.pendingFinish === undefined) return
    clearTimeout(state.pendingFinish)
    state.pendingFinish = undefined
    const answer = state.lastAssistant?.text
    dispatch(
      `finish:${String(session?.id ?? '')}`,
      makeTitle(resolved.titlePrefix, p.finishTitle),
      formatFinishBody(sessionLabel(session, state.title, resolved.lang), answer, BODY_LIMIT),
      effectiveSound(resolved, 'finish'),
    )
  }

  const onTurnEnd = (session: SessionLike, state: SessionState, data: unknown): void => {
    const payload = data as TurnEndDataLike | null | undefined
    const reason = payload?.reason
    if (reason === undefined || reason === null) return
    const kind = reason.kind
    const sessionId = String(session?.id ?? '')
    const isSub = isSubagentSession(session)
    const label = sessionLabel(session, state.title, resolved.lang)

    if (kind === 'completed') {
      const wasInteracting = state.interacting
      state.interacting = false
      if (!resolved.onFinish) return
      if (isSub && !resolved.notifySubagentTurns) return
      if (wasInteracting) return // approval/question already notified the user
      const timer = setTimeout(() => {
        firePendingFinish(session, state)
      }, resolved.settleMs)
      state.pendingFinish = timer
      return
    }

    if (kind === 'aborted' || kind === 'error' || kind === 'max-tokens') {
      state.interacting = false
      cancelPendingFinish(state)
      if (!resolved.onError) return
      if (isSub && !resolved.notifySubagentTurns) return
      const interrupted = kind === 'aborted'
      const titleText = interrupted ? p.interruptedTitle : p.errorTitle
      dispatch(
        `error:${sessionId}`,
        makeTitle(resolved.titlePrefix, titleText),
        formatInterruptBody(errorText(reason, resolved.lang), label, BODY_LIMIT),
        effectiveSound(resolved, 'interrupt'),
      )
      return
    }

    // 'blocked', 'interrupted' (replay-only), 'forked' (seed-only), unknown:
    // no notification.
  }

  // ---- interactive requests ---------------------------------------------

  const onApprovalRequest = (req: ApprovalRequestLike): void => {
    if (!resolved.onApproval) return
    const session = req.agent?.session
    const state = stateOf(session)
    // The user is being asked; any pending completion notification is stale.
    cancelPendingFinish(state)
    const sessionId = String(session?.id ?? '')
    const label = sessionLabel(session, state?.title, resolved.lang)
    const toolName = typeof req.toolName === 'string' && req.toolName !== '' ? req.toolName : 'tool'
    const reason = typeof req.reason === 'string' && req.reason !== '' ? req.reason : undefined
    const callId = req.callId === undefined || req.callId === null ? undefined : String(req.callId)
    const sent = dispatch(
      `approval:${sessionId}:${callId ?? toolName}`,
      makeTitle(resolved.titlePrefix, p.approvalTitle),
      formatApprovalBody(toolName, label, reason, BODY_LIMIT),
      effectiveSound(resolved, 'approval'),
    )
    if (sent && state !== undefined) state.interacting = true
  }

  const onQuestionsRequest = (req: UserQuestionsRequestLike): void => {
    const questions = req.questions
    const first = Array.isArray(questions) && questions.length > 0 ? questions[0] : undefined
    if (first === undefined) return
    const isPlanReview = first?.intent?.kind === 'plan-review'
    const enabled = isPlanReview ? resolved.onPlanReview : resolved.onQuestion
    if (!enabled) return

    const session = req.agent?.session
    const state = stateOf(session)
    cancelPendingFinish(state)
    const sessionId = String(session?.id ?? '')
    const label = sessionLabel(session, state?.title, resolved.lang)
    const question = typeof first.question === 'string' ? first.question : ''
    const itemId = typeof first.id === 'string' && first.id !== '' ? first.id : 'question'
    const intentCallId = first.intent?.callId === undefined || first.intent?.callId === null
      ? undefined
      : String(first.intent.callId)

    const sent = isPlanReview
      ? dispatch(
        `plan:${sessionId}:${intentCallId ?? itemId}`,
        makeTitle(resolved.titlePrefix, p.planReviewTitle),
        formatQuestionBody(question, label, BODY_LIMIT),
        effectiveSound(resolved, 'question'),
      )
      : dispatch(
        `question:${sessionId}:${itemId}`,
        makeTitle(resolved.titlePrefix, p.questionTitle),
        formatQuestionBody(question, label, BODY_LIMIT),
        effectiveSound(resolved, 'question'),
      )
    if (sent && state !== undefined) state.interacting = true
  }

  // ---- subscriptions -----------------------------------------------------

  // All sessions, background and subagent included: scope-filtered dispatch
  // admits untagged (root) listeners for every scoped event.
  ctx.on('session/event' as never, ((session: SessionLike, event: SessionEventLike) => {
    try {
      if (event === null || typeof event !== 'object') return
      debug({ kind: 'session/event', type: event.type, sessionId: String(session?.id ?? ''), seq: event.seq, replay: isReplay(session, event) })
      if (isReplay(session, event)) return
      const state = stateOf(session)
      if (state === undefined) return
      switch (event.type) {
        case 'session/title': {
          const title = (event.data as { title?: unknown } | undefined)?.title
          if (typeof title === 'string' && title.trim() !== '') state.title = title.trim()
          break
        }
        case 'assistant/message': {
          const data = event.data as { turn?: number; message?: AssistantMessageLike } | undefined
          const text = extractAssistantText(data?.message)
          if (text !== '') state.lastAssistant = { turn: data?.turn, text }
          break
        }
        case 'turn/start':
          onTurnStart(session, state)
          break
        case 'turn/end':
          onTurnEnd(session, state, event.data)
          break
        default:
          break
      }
    } catch (error) {
      warn(`session/event handler failed: ${String(error)}`)
    }
  }) as never)

  // Passive waterfall listeners: notify, then ALWAYS delegate via next() so
  // the real answerer (TUI/web UI) still receives and settles the request.
  ctx.on('approval/request' as never, ((req: ApprovalRequestLike, next: () => Promise<unknown>) => {
    try {
      debug({ kind: 'approval/request', sessionId: String(req.agent?.session?.id ?? ''), toolName: String(req.toolName ?? '') })
      onApprovalRequest(req)
    } catch (error) {
      warn(`approval handler failed: ${String(error)}`)
    }
    return next()
  }) as never)

  ctx.on('user-questions/request' as never, ((req: UserQuestionsRequestLike, next: () => Promise<unknown>) => {
    try {
      debug({ kind: 'user-questions/request', sessionId: String(req.agent?.session?.id ?? ''), firstId: String(req.questions?.[0]?.id ?? '') })
      onQuestionsRequest(req)
    } catch (error) {
      warn(`questions handler failed: ${String(error)}`)
    }
    return next()
  }) as never)

  ctx.on('session/disposed' as never, ((session: SessionLike) => {
    try {
      const key = String(session?.id ?? '')
      const state = sessions.get(key)
      cancelPendingFinish(state)
      sessions.delete(key)
    } catch {
      // Disposal cleanup must never throw.
    }
  }) as never)

  // Durability checkpoint at the turn boundary. One-shot runners (headless)
  // flush right after the turn completes and then dispose the tree — the
  // settle timer would otherwise never fire — so a pending completion
  // notification is delivered here. In interactive TUI sessions this event
  // coincides with the next activity, whose `turn/start` has already
  // cancelled the pending notification, so the settle window is preserved.
  ctx.on('session/flush' as never, ((session: SessionLike) => {
    try {
      const key = String(session?.id ?? '')
      const state = sessions.get(key)
      debug({ kind: 'session/flush', sessionId: key, pending: state?.pendingFinish !== undefined })
      if (state !== undefined) firePendingFinish(session, state)
    } catch {
      // Flush must never reject the durability checkpoint.
    }
  }) as never)

  // All timers are torn down with the plugin fiber (cordis 4 has no
  // 'dispose' event type; ctx.effect is the lifecycle cleanup mechanism).
  ctx.effect(() => () => {
    for (const state of sessions.values()) cancelPendingFinish(state)
    sessions.clear()
  }, 'session-alerts timers')
}
