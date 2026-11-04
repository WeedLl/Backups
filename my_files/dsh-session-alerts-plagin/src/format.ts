/**
 * Presentation helpers: ru/en notification copy, session labeling, text
 * extraction and length capping. Pure — no I/O, no cordis imports.
 * @module format
 */
import { basename } from 'node:path'
import type { AssistantMessageLike, SessionLike, TurnCancelCauseLike, TurnEndReasonLike } from './events.js'

export type Lang = 'ru' | 'en'

/** Notification copy per language. */
export interface Phrases {
  finishTitle: string
  interruptedTitle: string
  errorTitle: string
  approvalTitle: string
  questionTitle: string
  planReviewTitle: string
  cancelUser: string
  cancelParent: string
  cancelHook: string
  cancelDisposed: string
  cancelLegacy: string
  unknownSession: string
}

export const PHRASES: Record<Lang, Phrases> = {
  ru: {
    finishTitle: 'ход завершён',
    interruptedTitle: 'ход прерван',
    errorTitle: 'ошибка',
    approvalTitle: 'нужно подтверждение',
    questionTitle: 'вопрос',
    planReviewTitle: 'план ждёт ревью',
    cancelUser: 'прервано пользователем',
    cancelParent: 'прервано родителем',
    cancelHook: 'прервано хуком',
    cancelDisposed: 'прервано: сессия закрыта',
    cancelLegacy: 'прервано',
    unknownSession: 'сессия',
  },
  en: {
    finishTitle: 'turn finished',
    interruptedTitle: 'turn interrupted',
    errorTitle: 'error',
    approvalTitle: 'approval required',
    questionTitle: 'question',
    planReviewTitle: 'plan awaits review',
    cancelUser: 'cancelled by user',
    cancelParent: 'cancelled by parent',
    cancelHook: 'cancelled by hook',
    cancelDisposed: 'cancelled: session closed',
    cancelLegacy: 'cancelled',
    unknownSession: 'session',
  },
}

export function phrases(lang: Lang): Phrases {
  return PHRASES[lang] ?? PHRASES.ru
}

/** Cut a string to at most `max` code points; never breaks surrogate pairs. */
export function truncate(text: string, max: number): string {
  if (max <= 0) return ''
  const chars = Array.from(text)
  if (chars.length <= max) return text
  return `${chars.slice(0, Math.max(0, max - 1)).join('')}…`
}

/**
 * Human label for a session in notifications: the latest folded title when
 * known, else the working-directory basename, else the short session id,
 * else a generic word. Used in bodies ("где ждут").
 */
export function sessionLabel(
  session: SessionLike | undefined | null,
  title: string | undefined,
  lang: Lang,
): string {
  if (typeof title === 'string' && title.trim() !== '') return title.trim()
  const cwd = session?.header?.cwd
  if (typeof cwd === 'string' && cwd !== '') {
    const base = basename(cwd)
    if (base !== '' && base !== '.' && base !== '/') return base
  }
  const id = session?.id
  if (id !== undefined && id !== null && String(id) !== '') {
    return String(id).slice(0, 8)
  }
  return phrases(lang).unknownSession
}

/** Concatenate the plain-text blocks of an assistant message. */
export function extractAssistantText(message: AssistantMessageLike | undefined | null): string {
  const content = message?.content
  if (!Array.isArray(content)) return ''
  let out = ''
  for (const block of content) {
    if (block !== null && typeof block === 'object' && block.type === 'text' && typeof block.text === 'string') {
      out += block.text
    }
  }
  return out
}

/** One-line reason for a cancelled turn (`turn/end` with `kind: 'aborted'`). */
export function cancelCauseText(cause: TurnCancelCauseLike | undefined, lang: Lang): string {
  const p = phrases(lang)
  switch (cause?.kind) {
    case 'user': return p.cancelUser
    case 'parent': return p.cancelParent
    case 'hook': return cause.reason !== undefined && cause.reason !== '' ? `${p.cancelHook}: ${cause.reason}` : p.cancelHook
    case 'disposed': return p.cancelDisposed
    case 'legacy': return p.cancelLegacy
    default: return p.cancelLegacy
  }
}

/** One-line reason for a failed turn (`turn/end` with `kind: 'error'`). */
export function errorText(reason: TurnEndReasonLike, lang: Lang): string {
  const p = phrases(lang)
  switch (reason.kind) {
    case 'aborted':
      return cancelCauseText(reason.reason, lang)
    case 'error': {
      const message = reason.error?.message
      if (typeof message === 'string' && message !== '') return message
      const code = reason.error?.code
      if (typeof code === 'string' && code !== '') return `${p.errorTitle}: ${code}`
      return p.errorTitle
    }
    case 'max-tokens':
      return 'max-tokens'
    default:
      return p.errorTitle
  }
}

/** Format a body line: parts joined by ' · ', empty parts dropped. */
export function joinBody(...parts: Array<string | undefined>): string {
  return parts.filter((part): part is string => typeof part === 'string' && part.trim() !== '').map(part => part.trim()).join(' · ')
}

/** Finish-notification body: session label plus the last model answer. */
export function formatFinishBody(label: string, answer: string | undefined, bodyLimit: number): string {
  const trimmed = typeof answer === 'string' ? answer.trim() : ''
  if (trimmed === '') return truncate(label, bodyLimit)
  return truncate(joinBody(label, trimmed), bodyLimit)
}

/** Interrupt/error-notification body: reason plus session label. */
export function formatInterruptBody(reasonText: string, label: string, bodyLimit: number): string {
  return truncate(joinBody(reasonText, label), bodyLimit)
}

/** Approval-notification body: tool name plus session label, plus reason. */
export function formatApprovalBody(toolName: string, label: string, reason: string | undefined, bodyLimit: number): string {
  return truncate(joinBody(toolName, label, reason), bodyLimit)
}

/** Question-notification body: first question plus session label. */
export function formatQuestionBody(question: string, label: string, bodyLimit: number): string {
  return truncate(joinBody(question, label), bodyLimit)
}
