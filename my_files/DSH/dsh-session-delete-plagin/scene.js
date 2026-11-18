/**
 * Сцена «Удаление сессии» — собственный модал поверх чата.
 *
 * Почему свой модал: сцена dsh-tui — ранний return ПОВЕРХ кадра чата
 * (Chat.js), поэтому host-диалоги (`ctx.tuiDialogs`) из сцены не видны.
 * UI собран целиком здесь: центрированная панель, список, два режима ввода
 * (список/фильтр), подтверждение в футере, отчёт после удаления.
 *
 * Контракт компонента: только `props.React.createElement`, `props.ui`,
 * `props.channel`, `props.close` — никаких импортов React или
 * `@deepseek-harness-tui/*`. Хуки — строго на верхнем уровне функции;
 * ошибки ловятся, рендер ничего не бросает.
 *
 * Поток удаления:
 * 1. guard-вердикт ДО первой операции (whitelist id, current, live,
 *    наличие в списке, live-потомок);
 * 2. каталоги сессий и их slug-родители запоминаются ДО удаления;
 * 3. `channel.deleteSession(id)` по плану: потомки от листьев, затем
 *    корень; отказ потомка блокирует родителя;
 * 4. после каждого успешного удаления — `sweepSessions([id])`;
 * 5. после всех — `removeEmptySessionDirs(slugs)`, перечитать список,
 *    показать отчёт.
 * @module dsh-session-delete/scene
 */

import { checkDeletionTarget, filterSessions, formatAge, isEmptyArtifact, shortCwd, sortSessions, truncate } from './session-ops.js'
import { findSessionDirs, removeEmptySessionDirs, sweepSessions } from './sweep.js'
import { T, textOf } from './strings.js'
import { collectDescendants } from './tree.js'

/** Сколько строк отчёта помещается в футер фазы done. */
const REPORT_LINES = 4

/**
 * Создать компонент сцены. Компонент создаётся ОДИН раз при регистрации:
 * новая функция на каждый рендер перемонтирует сцену и теряет состояние.
 *
 * @param {{sweep?: boolean, backup?: boolean}} [settings] — конфиг строки
 *   cordis: `sweep` — чистить хвосты, `backup` — бэкапы перед записью.
 * @returns {Function} React-компонент сцены.
 */
export function createSessionDeleteScene(settings = {}) {
  const sweepEnabled = settings.sweep !== false
  const backupEnabled = settings.backup !== false
  const HOME = process.env.HOME ?? ''

  return function SessionDeleteScene(props) {
    const { React, ui, channel, close } = props
    const { Box, Text, useInput, useTerminalSize } = ui
    const h = React.createElement
    const { columns, rows } = useTerminalSize()

    const [sessions, setSessions] = React.useState(undefined)
    const [agentRows, setAgentRows] = React.useState([])
    const [loadError, setLoadError] = React.useState(undefined)
    const [cursor, setCursor] = React.useState(0)
    const [query, setQuery] = React.useState('')
    const [filterMode, setFilterMode] = React.useState(false)
    /** browse → confirm → busy → done → browse. */
    const [phase, setPhase] = React.useState('browse')
    /** Транзитное сообщение в футере (guard-отказ и т. п.). */
    const [notice, setNotice] = React.useState(undefined)
    /** Отчёт фазы done: [{text, color}]. */
    const [report, setReport] = React.useState([])
    /** Guard-вердикт цели, выбранной для подтверждения. */
    const [verdict, setVerdict] = React.useState(undefined)

    const mounted = React.useRef(true)
    React.useEffect(() => () => {
      mounted.current = false
    }, [])

    const attachedId = typeof channel.sessionId === 'string' ? channel.sessionId : ''

    const load = React.useCallback(async () => {
      try {
        const list = await channel.listSessions()
        if (mounted.current) {
          setSessions(Array.isArray(list) ? [...list] : [])
          setLoadError(undefined)
        }
      } catch (error) {
        if (mounted.current) {
          setSessions([])
          setLoadError(T.loadError(textOf(error)))
        }
      }
      try {
        const rows = channel.agentViewRows()
        if (mounted.current) setAgentRows(Array.isArray(rows) ? rows : [])
      } catch {
        if (mounted.current) setAgentRows([])
      }
    }, [channel])

    React.useEffect(() => {
      void load()
    }, [load])

    // ---- проекция ----------------------------------------------------------

    const sorted = sortSessions(sessions ?? [])
    const filtered = filterSessions(sorted, query)
    const rowsById = new Map(agentRows.map((row) => [row.id, row]))
    const safeCursor = filtered.length === 0 ? 0 : Math.min(cursor, filtered.length - 1)
    const target = filtered[safeCursor]
    const descendants = target !== undefined ? collectDescendants(sorted, target.id) : []

    const shortTitle = (session) =>
      session === undefined || session === null ? '?' : truncate(session.title?.text ?? T.untitled, 48)

    // ---- удаление -----------------------------------------------------------

    const runDelete = async (currentVerdict) => {
      if (!currentVerdict?.ok || target === undefined) return
      const byId = new Map(sorted.map((session) => [session.id, session]))
      const ids = currentVerdict.ids
      const rootId = target.id
      const lines = []
      const deleted = []

      setPhase('busy')
      setNotice(undefined)

      // Каталоги сессий и их slug-родители — ДО удаления.
      const slugSet = new Set()
      try {
        const dirs = findSessionDirs(ids)
        for (const found of dirs.found) slugSet.add(found.slug)
        for (const error of dirs.errors) lines.push({ text: T.errSweep('каталоги', error), color: 'warning' })
      } catch (error) {
        lines.push({ text: T.errSweep('каталоги', textOf(error)), color: 'warning' })
      }

      // Дети в пределах плана — чтобы отказ потомка блокировал родителя.
      const childrenOf = new Map()
      for (const id of ids) {
        const session = byId.get(id)
        const parent = session?.kind?.kind === 'subagent' ? session.kind.parent : undefined
        if (parent !== undefined && ids.includes(parent)) {
          const list = childrenOf.get(parent) ?? []
          list.push(id)
          childrenOf.set(parent, list)
        }
      }

      const failed = new Set()
      for (const id of ids) {
        const kids = childrenOf.get(id) ?? []
        if (kids.some((kid) => failed.has(kid))) {
          failed.add(id)
          lines.push({ text: T.errChildBlocked(shortTitle(byId.get(id))), color: 'error' })
          continue
        }
        let ok = false
        try {
          ok = (await channel.deleteSession(id)) === true
        } catch (error) {
          lines.push({ text: `✗ ${id}: ${textOf(error)}`, color: 'error' })
        }
        if (!ok) {
          failed.add(id)
          lines.push({ text: T.errHostRefused(shortTitle(byId.get(id))), color: 'error' })
          continue
        }
        deleted.push(id)
        lines.push({
          text: id === rootId ? T.deleted(shortTitle(byId.get(id))) : T.deletedSub(shortTitle(byId.get(id))),
          color: 'success',
        })
        if (sweepEnabled) {
          try {
            const swept = sweepSessions([id], { backup: backupEnabled })
            lines.push({ text: T.swept(swept.summary), color: 'subtle' })
            for (const error of swept.errors) lines.push({ text: T.errSweep(id, error), color: 'warning' })
          } catch (error) {
            lines.push({ text: T.errSweep(id, textOf(error)), color: 'warning' })
          }
        }
      }

      if (deleted.length > 0 && slugSet.size > 0) {
        try {
          const cleaned = removeEmptySessionDirs([...slugSet])
          if (cleaned.removed.length > 0) lines.push({ text: T.emptyDirsRemoved(cleaned.removed.length), color: 'subtle' })
          for (const error of cleaned.errors) lines.push({ text: T.errSweep('каталоги', error), color: 'warning' })
        } catch (error) {
          lines.push({ text: T.errSweep('каталоги', textOf(error)), color: 'warning' })
        }
      }

      await load().catch(() => {})
      if (mounted.current) {
        setVerdict(undefined)
        setReport(lines)
        setPhase('done')
      }
    }

    // ---- ввод ---------------------------------------------------------------

    useInput((input, key) => {
      if (phase === 'busy') return

      if (phase === 'confirm') {
        if (input === 'y' || input === 'Y') void runDelete(verdict)
        else if (input === 'n' || input === 'N' || key.escape) {
          setVerdict(undefined)
          setPhase('browse')
        }
        return
      }

      if (phase === 'done') {
        setReport([])
        setPhase('browse')
        return
      }

      if (key.ctrl && input === 'c') {
        close()
        return
      }

      if (filterMode) {
        if (key.return || key.escape) {
          setFilterMode(false)
          setNotice(undefined)
          return
        }
        if (key.backspace || key.delete) {
          setQuery((value) => value.slice(0, -1))
          return
        }
        if (input.length > 0 && !key.ctrl && !key.meta && !key.alt) {
          setQuery((value) => value + input)
        }
        return
      }

      // Список.
      if (key.escape) {
        if (query.trim() !== '') {
          setQuery('')
          setNotice(undefined)
          return
        }
        close()
        return
      }
      if (input === 'q' || input === 'Q') {
        close()
        return
      }
      if (key.upArrow || input === 'k') {
        setCursor((value) => Math.max(0, value - 1))
        setNotice(undefined)
        return
      }
      if (key.downArrow || input === 'j') {
        setCursor((value) => Math.min(Math.max(filtered.length - 1, 0), value + 1))
        setNotice(undefined)
        return
      }
      if (key.pageUp) {
        setCursor((value) => Math.max(0, value - listRows))
        setNotice(undefined)
        return
      }
      if (key.pageDown) {
        setCursor((value) => Math.min(Math.max(filtered.length - 1, 0), value + listRows))
        setNotice(undefined)
        return
      }
      if (input === '/') {
        setFilterMode(true)
        setNotice(undefined)
        return
      }
      if (input === 'r' || input === 'R') {
        void load()
        return
      }
      if (key.return) {
        if (target === undefined) return
        const next = checkDeletionTarget({ target, sessions: sorted, rowsById, attachedSessionId: attachedId })
        if (!next.ok) {
          setNotice({ text: next.text, color: 'warning' })
          return
        }
        setNotice(undefined)
        setVerdict(next)
        setPhase('confirm')
      }
    })

    // ---- раскладка ------------------------------------------------------------

    const panelWidth = Math.max(40, Math.min(Math.max(columns - 6, 20), 78))
    const panelHeight = Math.max(6, Math.min(Math.max(rows - 4, 4), 32))

    const footerRows =
      phase === 'confirm'
        ? 2 + (verdict !== undefined && verdict.descendants.length > 0 ? 1 : 0)
        : phase === 'done'
          ? Math.min(report.length, REPORT_LINES) + 1
          : phase === 'browse' && notice !== undefined
            ? 2
            : 1
    const listRows = Math.max(1, panelHeight - 2 - 1 - footerRows)

    // Окно списка следует за курсором.
    const maxStart = Math.max(0, filtered.length - listRows)
    let start = 0
    if (safeCursor < start) start = safeCursor
    else if (safeCursor >= start + listRows) start = safeCursor - listRows + 1
    start = Math.max(0, Math.min(start, maxStart))

    const visible = filtered.slice(start, start + listRows)

    const listNodes = visible.map((session) => {
      const row = rowsById.get(session.id)
      const subCount = collectDescendants(sorted, session.id).length
      const badges = []
      if (row?.current === true || session.id === attachedId) badges.push(T.badgeCurrent)
      if (row?.live === true) badges.push(T.badgeLive)
      if (session.archived === true) badges.push(T.badgeArchived)
      if (isEmptyArtifact(session)) badges.push(T.badgeEmpty)
      if (subCount > 0) badges.push(T.badgeSubs(subCount))
      const title = truncate(session.title?.text ?? T.untitled, Math.max(8, panelWidth - 30))
      const meta = truncate(
        `${badges.length > 0 ? `${badges.join(' · ')} · ` : ''}${shortCwd(session.cwd, HOME)} · ${formatAge(session.updatedAt)}`,
        34,
      )
      const isCursor = session === target
      return h(
        Box,
        { key: session.id, flexDirection: 'row', justifyContent: 'space-between' },
        h(
          Text,
          { wrap: 'truncate', color: isCursor ? 'accent' : 'text', bold: isCursor },
          `${isCursor ? '❯ ' : '  '}${title}`,
        ),
        h(Text, { color: 'subtle', wrap: 'truncate' }, meta),
      )
    })

    const bodyNodes = []
    if (sessions === undefined) {
      bodyNodes.push(h(Text, { key: 'loading', color: 'subtle' }, T.loading))
    } else if (loadError !== undefined) {
      bodyNodes.push(h(Text, { key: 'error', color: 'error' }, loadError))
    } else if (filtered.length === 0) {
      bodyNodes.push(h(Text, { key: 'empty', color: 'subtle' }, query.trim() === '' ? T.noSessions : T.noMatches))
    } else {
      bodyNodes.push(...listNodes)
    }

    const headerRight =
      query.trim() !== ''
        ? `${T.filterLabel}${truncate(query, 28)}`
        : T.count(sorted.length)

    const footerNodes = []
    if (phase === 'confirm') {
      footerNodes.push(h(Text, { key: 'confirm-title', color: 'warning', bold: true }, T.confirmTitle(shortTitle(target))))
      if (verdict !== undefined && verdict.descendants.length > 0) {
        footerNodes.push(h(Text, { key: 'confirm-subs', color: 'warning' }, T.confirmSubs(verdict.descendants.length)))
      }
      footerNodes.push(h(Text, { key: 'confirm-warn', color: 'subtle' }, T.confirmWarn))
    } else if (phase === 'busy') {
      footerNodes.push(h(Text, { key: 'busy', color: 'accent' }, T.busy))
    } else if (phase === 'done') {
      // Ошибки — первыми, чтобы они не терялись за окном из REPORT_LINES.
      const rank = (color) => (color === 'error' ? 0 : color === 'warning' ? 1 : color === 'success' ? 2 : 3)
      const shown = [...report].sort((a, b) => rank(a.color) - rank(b.color)).slice(0, REPORT_LINES)
      for (const [index, line] of shown.entries()) {
        footerNodes.push(h(Text, { key: `report-${index}`, color: line.color }, line.text))
      }
      footerNodes.push(h(Text, { key: 'done-hint', color: 'subtle' }, T.hintDone))
    } else if (filterMode) {
      footerNodes.push(h(Text, { key: 'filter', color: 'accent' }, `${T.filterLabel}${query}▌`))
    } else {
      if (notice !== undefined) {
        footerNodes.push(h(Text, { key: 'notice', color: notice.color }, notice.text))
      }
      footerNodes.push(h(Text, { key: 'hint', color: 'subtle' }, T.hintBrowse))
    }

    return h(
      Box,
      { flexDirection: 'column', width: columns, height: rows, alignItems: 'center', justifyContent: 'center' },
      h(
        Box,
        {
          flexDirection: 'column',
          width: panelWidth,
          height: panelHeight,
          borderStyle: 'round',
          borderColor: 'subtle',
          paddingX: 1,
          overflow: 'hidden',
        },
        h(
          Box,
          { key: 'header', flexDirection: 'row', justifyContent: 'space-between' },
          h(Text, { bold: true, color: 'accent' }, T.title),
          h(Text, { color: 'subtle' }, headerRight),
        ),
        h(Box, { key: 'list', flexDirection: 'column', flexGrow: 1, overflow: 'hidden' }, ...bodyNodes),
        h(Box, { key: 'footer', flexDirection: 'column' }, ...footerNodes),
      ),
    )
  }
}
