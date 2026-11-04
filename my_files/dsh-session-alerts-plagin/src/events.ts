/**
 * Structural, dependency-free views of the DSH event vocabulary this plugin
 * consumes. Deliberately NO imports from `@deepseek-ai/dsh-*` packages: the
 * plugin only peers on `@deepseek-ai/cordis` and `@deepseek-ai/schemastery`,
 * and the shapes here were transcribed from the installed runtime's `.d.ts`
 * files (dsh-session, dsh-user-approval, dsh-user-questions, dsh-llm,
 * dsh-agent) for DSH 0.2.0-rc.2. Runtime access is defensive everywhere.
 *
 * Sources of truth in the runtime:
 * - `dsh-session/lib/types/types.d.ts` → SessionEventMap, SessionHeader
 * - `dsh-user-approval/lib/types/types.d.ts` → ApprovalRequestEvent
 * - `dsh-user-questions/lib/types/types.d.ts` → AskUserQuestionRequestEvent
 * - `dsh-llm/lib/types/types.d.ts` → ContentBlock
 * @module events
 */

/** Why an active agent driver was cancelled (dsh-session `AgentCancelCause`). */
export interface TurnCancelCauseLike {
  readonly kind: 'user' | 'parent' | 'hook' | 'disposed' | 'legacy' | (string & {});
  readonly reason?: string;
}

/** Flattened provider/transport failure (dsh-llm `LlmFailure`). */
export interface LlmFailureLike {
  readonly message?: string;
  readonly code?: string;
  readonly status?: number;
}

/**
 * Why a turn ended (dsh-session `TurnEndReason`, merge-extensible). Unknown
 * kinds are tolerated: handlers switch on the known ones only.
 */
export type TurnEndReasonLike =
  | { readonly kind: 'completed' }
  | { readonly kind: 'aborted'; readonly reason?: TurnCancelCauseLike }
  | { readonly kind: 'blocked' }
  | { readonly kind: 'error'; readonly error?: LlmFailureLike }
  | { readonly kind: 'max-tokens' }
  | { readonly kind: 'interrupted' }
  | { readonly kind: 'forked' };

/** `turn/end` event data. */
export interface TurnEndDataLike {
  readonly turn?: number;
  readonly reason?: TurnEndReasonLike;
}

/** One model content block (dsh-llm `ContentBlock` union, text subset). */
export interface ContentBlockLike {
  readonly type?: string;
  readonly text?: string;
}

/** The model-visible assistant message (dsh-llm `AssistantMessage`). */
export interface AssistantMessageLike {
  readonly role?: 'assistant';
  readonly content?: readonly ContentBlockLike[];
}

/** `assistant/message` event data. */
export interface AssistantMessageEventDataLike {
  readonly turn?: number;
  readonly message?: AssistantMessageLike;
}

/** `session/title` event data (dsh-session-title `SessionTitleEventData`). */
export interface SessionTitleEventDataLike {
  readonly title?: string;
}

/**
 * One entry in the session log (dsh-session `SessionEvent`). `type` is the
 * discriminated union tag; `data` carries the payload.
 */
export interface SessionEventLike {
  readonly type: string;
  readonly seq?: number;
  readonly time?: number;
  readonly data?: unknown;
  readonly ignorable?: true;
}

/**
 * Structural view of dsh-session `Session` plus its `SessionHeader`.
 * `header.origin === 'subagent'` / `header.delegationDepth >= 1` mark a
 * subagent (forked) session.
 */
export interface SessionLike {
  readonly id?: unknown;
  readonly header?: {
    readonly cwd?: string;
    readonly createdAt?: number;
    readonly origin?: 'subagent' | string;
    readonly delegationDepth?: number;
  };
}

/**
 * Live runtime agent (dsh-agent runtime `Agent`); only the session handle is
 * needed here.
 */
export interface AgentLike {
  readonly session?: SessionLike;
}

/**
 * One pending approval decision (dsh-user-approval `ApprovalRequestEvent`),
 * as dispatched on the `approval/request` cordis waterfall.
 */
export interface ApprovalRequestLike {
  readonly agent?: AgentLike;
  readonly toolName?: string;
  /** Branded `ToolCallId`; stringify before use. */
  readonly callId?: unknown;
  readonly reason?: string;
  readonly displayReason?: {
    readonly en?: string;
    readonly [locale: string]: unknown;
  };
  readonly signal?: AbortSignal;
}

/**
 * A plan submitted for review (dsh-user-questions `AskUserQuestionIntent`
 * with `kind: 'plan-review'`); `dsh-plan-mode` raises exactly this through
 * `user-questions/request` when the model calls `exit_plan_mode`.
 */
export interface QuestionIntentLike {
  readonly kind?: string;
  readonly approve?: string;
  readonly callId?: unknown;
}

/** One question (dsh-user-questions `AskUserQuestionItem`). */
export interface QuestionItemLike {
  readonly id?: string;
  readonly question?: string;
  readonly detail?: string;
  readonly header?: string;
  readonly intent?: QuestionIntentLike;
}

/**
 * One pending user-question request (dsh-user-questions
 * `AskUserQuestionRequestEvent`), as dispatched on the
 * `user-questions/request` cordis waterfall.
 */
export interface UserQuestionsRequestLike {
  readonly questions?: readonly QuestionItemLike[];
  readonly agent?: AgentLike;
  readonly signal?: AbortSignal;
  readonly wait?: {
    readonly callId?: unknown;
    readonly timed?: boolean;
  };
}

/** True when the session header marks a subagent (forked) session. */
export function isSubagentSession(session: SessionLike | undefined | null): boolean {
  const header = session?.header
  if (header === undefined || header === null) return false
  if (header.origin === 'subagent') return true
  if (typeof header.delegationDepth === 'number' && header.delegationDepth >= 1) return true
  return false
}
