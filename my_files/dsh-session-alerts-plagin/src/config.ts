/**
 * Plugin configuration: the schemastery schema (every key has a default) and
 * the typed resolution used by `apply`.
 * @module config
 */
import z from '@deepseek-ai/schemastery'

/** Raw plugin config as declared by the schema; every key optional. */
export interface SessionAlertsConfig {
  /** Master switch. When false the plugin stays composed but stays silent. */
  enabled?: boolean
  /** Notify when a turn completes (any session, including background ones). */
  onFinish?: boolean
  /** Notify when a turn is aborted or fails. */
  onError?: boolean
  /** Notify when a tool asks for approval (any session, subagents included). */
  onApproval?: boolean
  /** Notify when the agent asks the user a question. */
  onQuestion?: boolean
  /** Notify when a plan waits for review (user-questions request with `intent.kind === 'plan-review'`). */
  onPlanReview?: boolean
  /** Also notify turn completion/interrupts of subagent (forked) sessions. Approvals and questions are always notified. */
  notifySubagentTurns?: boolean
  /**
   * After a turn completes, wait this long before notifying; a new
   * `turn/start` in the same session within the window cancels the
   * notification.
   */
  settleMs?: number
  /** Deduplication window: identical event key + session is not re-notified. */
  debounceMs?: number
  /** Global rate limit: maximum notifications per rolling minute. */
  maxPerMinute?: number
  /** System sound for notifications; `'none'` silences everything. Any macOS sound name (e.g. `'Glass'`, `'Ping'`, `'Bottle'`) is accepted. */
  sound?: string
  /** Play sound for turn-completion notifications. */
  soundOnFinish?: boolean
  /** Play sound for interrupt/error notifications. */
  soundOnInterrupt?: boolean
  /** Play sound for approval notifications. */
  soundOnApproval?: boolean
  /** Play sound for question notifications. */
  soundOnQuestion?: boolean
  /** Prefix for every notification title, e.g. `'DSH'`. */
  titlePrefix?: string
  /**
   * Bundle id brought to front when the notification is clicked, e.g.
   * `'net.kovidgoyal.kitty'`. terminal-notifier only — osascript cannot
   * control click behavior (its notifications open Script Editor).
   */
  activate?: string
  /** Notification copy language. */
  lang?: 'ru' | 'en'
}

/** Resolved config after schema defaults; every key present. */
export interface ResolvedConfig {
  enabled: boolean
  onFinish: boolean
  onError: boolean
  onApproval: boolean
  onQuestion: boolean
  onPlanReview: boolean
  notifySubagentTurns: boolean
  settleMs: number
  debounceMs: number
  maxPerMinute: number
  sound: string
  soundOnFinish: boolean
  soundOnInterrupt: boolean
  soundOnApproval: boolean
  soundOnQuestion: boolean
  titlePrefix: string
  activate: string
  lang: 'ru' | 'en'
}

export const DEFAULT_SOUND = 'Glass'
export const REPLAY_GRACE_MS = 2000

/**
 * Schemastery schema. The explicit annotation mirrors what
 * `dsh-working-activity` does: the inferred `z.dict` output references
 * cosmokit through a pnpm-virtual path that is not portable in declaration
 * emit. The global `Schemastery` interface comes from schemastery's own
 * d.ts (declare global).
 */
export const Config: Schemastery<SessionAlertsConfig> = z.object({
  enabled: z.boolean().default(true),
  onFinish: z.boolean().default(true),
  onError: z.boolean().default(true),
  onApproval: z.boolean().default(true),
  onQuestion: z.boolean().default(true),
  onPlanReview: z.boolean().default(true),
  notifySubagentTurns: z.boolean().default(false),
  settleMs: z.number().step(1).min(0).max(60_000).default(1500),
  debounceMs: z.number().step(1).min(0).max(300_000).default(10_000),
  maxPerMinute: z.number().step(1).min(1).max(60).default(12),
  sound: z.string().default(DEFAULT_SOUND),
  soundOnFinish: z.boolean().default(true),
  soundOnInterrupt: z.boolean().default(false),
  soundOnApproval: z.boolean().default(true),
  soundOnQuestion: z.boolean().default(true),
  titlePrefix: z.string().max(20).default('DSH'),
  activate: z.string().max(64).default(''),
  lang: z.union(['ru', 'en']).default('ru'),
})

/** Apply the schema defaults by hand — the loader normally does this, but the
 * plugin must also work when imported directly (tests, unusual compositions). */
export function resolveConfig(config: SessionAlertsConfig = {}): ResolvedConfig {
  return {
    enabled: config.enabled ?? true,
    onFinish: config.onFinish ?? true,
    onError: config.onError ?? true,
    onApproval: config.onApproval ?? true,
    onQuestion: config.onQuestion ?? true,
    onPlanReview: config.onPlanReview ?? true,
    notifySubagentTurns: config.notifySubagentTurns ?? false,
    settleMs: config.settleMs ?? 1500,
    debounceMs: config.debounceMs ?? 10_000,
    maxPerMinute: config.maxPerMinute ?? 12,
    sound: config.sound ?? DEFAULT_SOUND,
    soundOnFinish: config.soundOnFinish ?? true,
    soundOnInterrupt: config.soundOnInterrupt ?? false,
    soundOnApproval: config.soundOnApproval ?? true,
    soundOnQuestion: config.soundOnQuestion ?? true,
    titlePrefix: config.titlePrefix ?? 'DSH',
    activate: config.activate ?? '',
    lang: config.lang ?? 'ru',
  }
}

/** Effective sound name for one event kind; `'none'` means silence. */
export function effectiveSound(resolved: ResolvedConfig, kind: 'finish' | 'interrupt' | 'approval' | 'question'): string {
  const base = resolved.sound
  if (base === 'none' || base === '') return 'none'
  switch (kind) {
    case 'finish': return resolved.soundOnFinish ? base : 'none'
    case 'interrupt': return resolved.soundOnInterrupt ? base : 'none'
    case 'approval': return resolved.soundOnApproval ? base : 'none'
    case 'question': return resolved.soundOnQuestion ? base : 'none'
  }
}
