#!/usr/bin/env node
/**
 * doc.mjs — журнал версий DSH в формате заметки Obsidian.
 *
 *   doc.mjs path [--json]
 *   doc.mjs write [--snapshot DIR] [--verify-dir DIR] [--dir DIR]
 *                 [--kind update|rollback] [--skipped TEXT]...
 *                 [--no-verify] [--stdout] [--json]
 *
 * path   — куда скилл будет писать (или чего не хватает для выбора).
 * write  — переписать dsh-versions.md по текущему состоянию.
 *
 * «До» берётся из manifest.json снимка (--snapshot), «после» — из collect.mjs.
 * Если снимка нет, «до» — состояние из предыдущей записи журнала. История
 * хранится рядом с заметкой в скрытом .dsh-versions.json.
 */
import {
  accessSync,
  chmodSync,
  constants,
  existsSync,
  mkdirSync,
  readFileSync,
  renameSync,
  statSync,
  unlinkSync,
  writeFileSync,
} from 'node:fs'
import { homedir } from 'node:os'
import { basename, dirname, join, resolve } from 'node:path'
import { collect } from './collect.mjs'
import { parse, satisfies } from './util.mjs'

const HOME = homedir()
const DSH_HOME = process.env.DSH_HOME || join(HOME, '.dsh')
const STATE_DIR = process.env.DSH_UPDATE_STATE || join(DSH_HOME, 'updates')
const REPORT_DIR = join(STATE_DIR, 'reports')
const BACKUP_ROOT = resolve(
  process.env.DSH_UPDATE_BACKUP_ROOT || join(HOME, 'Documents/ForSys/Backup'),
)
const DOC_DIR = join(BACKUP_ROOT, 'doc')
const TARGET_FILE = join(STATE_DIR, 'doc-target')
const FILE_NAME = 'dsh-versions.md'
const LEDGER_NAME = '.dsh-versions.json'
const TUI_PKG = '@deepseek-harness-tui/dsh-tui'
const FORMAT = 'dsh-update-doc/1'

const ARGS = process.argv.slice(2)
const CMD = ARGS.shift() ?? 'path'

const OPTS = {
  snapshot: '',
  verifyDir: '',
  dir: '',
  kind: 'update',
  skipped: [],
  noVerify: false,
  stdout: false,
  json: false,
}

for (let i = 0; i < ARGS.length; i++) {
  const arg = ARGS[i]
  switch (arg) {
    case '--snapshot':
      OPTS.snapshot = ARGS[++i] ?? ''
      break
    case '--verify-dir':
      OPTS.verifyDir = ARGS[++i] ?? ''
      break
    case '--dir':
      OPTS.dir = ARGS[++i] ?? ''
      break
    case '--kind':
      OPTS.kind = ARGS[++i] ?? 'update'
      break
    case '--skipped':
      OPTS.skipped.push(ARGS[++i] ?? '')
      break
    case '--no-verify':
      OPTS.noVerify = true
      break
    case '--stdout':
      OPTS.stdout = true
      break
    case '--json':
      OPTS.json = true
      break
    case '-h':
    case '--help':
      usage()
      process.exit(0)
      break
    default:
      fail(`неизвестный аргумент: ${arg}`, 2)
  }
}

function usage() {
  process.stdout.write(
    [
      'doc.mjs path [--json]',
      'doc.mjs write [--snapshot DIR] [--verify-dir DIR] [--dir DIR]',
      '               [--kind update|rollback] [--skipped TEXT]...',
      '               [--no-verify] [--stdout] [--json]',
      '',
    ].join('\n'),
  )
}

function fail(message, code = 2) {
  process.stderr.write(`doc: ${message}\n`)
  process.exit(code)
}

function warn(message) {
  process.stderr.write(`doc: ${message}\n`)
}

function pad(value) {
  return String(value).padStart(2, '0')
}

function localDate(date = new Date()) {
  return `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())}`
}

function localIso(date = new Date()) {
  const offset = -date.getTimezoneOffset()
  const sign = offset >= 0 ? '+' : '-'
  const abs = Math.abs(offset)
  return `${localDate(date)}T${pad(date.getHours())}:${pad(date.getMinutes())}:${pad(date.getSeconds())}${sign}${pad(
    Math.floor(abs / 60),
  )}:${pad(abs % 60)}`
}

function shortDate(iso) {
  const date = new Date(iso)
  if (Number.isNaN(date.getTime())) return String(iso ?? '—')
  return `${pad(date.getDate())}.${pad(date.getMonth() + 1)}.${date.getFullYear()}`
}

function dateTime(iso) {
  const date = new Date(iso)
  if (Number.isNaN(date.getTime())) return String(iso ?? '—')
  return `${shortDate(iso)} ${pad(date.getHours())}:${pad(date.getMinutes())}`
}

function displayPath(file) {
  if (typeof file !== 'string' || file === '') return ''
  const resolved = resolve(file)
  if (resolved === HOME) return '~'
  if (resolved.startsWith(`${HOME}/`)) return `~${resolved.slice(HOME.length)}`
  return resolved
}

function isDir(file) {
  try {
    return existsSync(file) && statSync(file).isDirectory()
  } catch {
    return false
  }
}

function isWritableDir(dir) {
  try {
    accessSync(dir, constants.W_OK)
    return true
  } catch {
    return false
  }
}

function dirReady(dir) {
  if (existsSync(dir)) return isDir(dir) && isWritableDir(dir)
  const parent = dirname(dir)
  return isDir(parent) && isWritableDir(parent)
}

function readJson(file) {
  return JSON.parse(readFileSync(file, 'utf8'))
}

function answersDir() {
  const explicit = process.env.DSH_UPDATE_ANSWERS_DIR ?? process.env.MD_ANSWER_DIR
  if (typeof explicit === 'string' && explicit !== '') return resolve(explicit)
  const cwdAnswers = join(process.cwd(), 'answers')
  const knownAnswers = join(HOME, 'Documents/ForSys/DSH/answers')
  if (isDir(cwdAnswers)) return cwdAnswers
  if (isDir(knownAnswers)) return knownAnswers
  return cwdAnswers
}

function readSavedTarget() {
  try {
    const value = readFileSync(TARGET_FILE, 'utf8').trim()
    return value === '' ? '' : resolve(value)
  } catch {
    return ''
  }
}

function saveTarget(dir) {
  try {
    mkdirSync(STATE_DIR, { recursive: true })
    writeFileSync(TARGET_FILE, `${resolve(dir)}\n`, 'utf8')
  } catch (error) {
    warn(`не удалось запомнить путь журнала: ${error.message}`)
  }
}

function resolveTarget(explicitDir) {
  if (typeof explicitDir === 'string' && explicitDir !== '') {
    return { dir: resolve(explicitDir), source: 'аргумент --dir', needsChoice: false, candidates: [] }
  }

  const fromEnv = process.env.DSH_UPDATE_DOC_DIR
  if (typeof fromEnv === 'string' && fromEnv !== '') {
    return { dir: resolve(fromEnv), source: 'DSH_UPDATE_DOC_DIR', needsChoice: false, candidates: [] }
  }

  if (isDir(DOC_DIR)) {
    return { dir: DOC_DIR, source: 'Backup/doc', needsChoice: false, candidates: [] }
  }

  const saved = readSavedTarget()
  const savedIsMissingDocChoice = saved !== '' && resolve(saved) === DOC_DIR && !isDir(DOC_DIR)
  if (saved !== '' && !savedIsMissingDocChoice && dirReady(saved)) {
    return { dir: saved, source: 'сохранённый выбор', needsChoice: false, candidates: [] }
  }

  if (isDir(BACKUP_ROOT)) {
    const candidates = [
      { label: 'Backup', dir: BACKUP_ROOT, file: join(BACKUP_ROOT, FILE_NAME) },
      { label: 'answers', dir: answersDir(), file: join(answersDir(), FILE_NAME) },
    ]
    return {
      dir: '',
      source: 'Backup без doc',
      needsChoice: true,
      candidates,
    }
  }

  return { dir: answersDir(), source: 'answers (Backup нет)', needsChoice: false, candidates: [] }
}

function targetInfo(target) {
  return {
    format: 'dsh-update-doc-path/1',
    target: target.dir || null,
    file: target.dir ? join(target.dir, FILE_NAME) : null,
    needsChoice: target.needsChoice,
    source: target.source,
    candidates: target.candidates ?? [],
  }
}

function extractState(source) {
  const profiles = {}
  for (const [profile, value] of Object.entries(source?.profiles ?? {})) {
    const deps = {}
    for (const [name, dep] of Object.entries(value?.deps ?? {})) {
      deps[name] = {
        installed: dep?.installed ?? '',
        spec: dep?.spec ?? '',
        kind: dep?.kind ?? '',
      }
    }
    profiles[profile] = {
      tui:
        value?.tui === undefined || value?.tui === null
          ? null
          : { version: value.tui.version ?? '', peerCore: value.tui.peerCore ?? '' },
      deps,
    }
  }
  return {
    core: {
      version: source?.core?.version ?? '',
      installMethod: source?.core?.installMethod ?? '',
      installDir: source?.core?.installDir ?? '',
    },
    profiles,
    env: {
      node: source?.env?.node ?? '',
      npm: source?.env?.npm ?? '',
      pnpm: source?.env?.pnpm ?? '',
    },
  }
}

function readSnapshotState(snapshotDir) {
  if (typeof snapshotDir !== 'string' || snapshotDir === '') return null
  const file = join(resolve(snapshotDir), 'manifest.json')
  if (!existsSync(file)) {
    warn(`в снимке нет manifest.json: ${file}`)
    return null
  }
  try {
    return extractState(readJson(file))
  } catch (error) {
    warn(`не читается manifest.json: ${error.message}`)
    return null
  }
}

function readVerify(verifyDir) {
  let dir = verifyDir
  if (typeof dir !== 'string' || dir === '') {
    const pointer = join(REPORT_DIR, '.latest')
    if (!existsSync(pointer)) return null
    try {
      dir = readFileSync(pointer, 'utf8').trim()
    } catch {
      return null
    }
  } else {
    dir = resolve(dir)
  }
  if (!isDir(dir)) return null

  const findings = join(dir, 'findings.tsv')
  if (!existsSync(findings)) return null

  let age = 0
  try {
    age = Date.now() - statSync(dir).mtimeMs
  } catch {
    age = 0
  }
  if (verifyDir === '' && age > 24 * 60 * 60 * 1000) return null

  const rows = readFileSync(findings, 'utf8')
    .split(/\r?\n/)
    .filter(Boolean)
    .map(line => {
      const [level, scope, check, message] = line.split('\t')
      return { level, scope: scope ?? '', check: check ?? '', message: message ?? '' }
    })

  const errors = rows.filter(row => row.level === 'fail').map(row => `${row.scope}: ${row.message}`)
  const warnings = rows.filter(row => row.level === 'warn').map(row => `${row.scope}: ${row.message}`)
  return {
    dir,
    fails: errors.length,
    warns: warnings.length,
    oks: rows.filter(row => row.level === 'ok').length,
    skips: rows.filter(row => row.level === 'skip').length,
    errors: errors.slice(0, 5),
    warnings: warnings.slice(0, 5),
  }
}

function plural(count, one, few, many) {
  const n10 = Math.abs(count) % 10
  const n100 = Math.abs(count) % 100
  if (n10 === 1 && n100 !== 11) return one
  if (n10 >= 2 && n10 <= 4 && (n100 < 12 || n100 > 14)) return few
  return many
}

function verifyText(verify) {
  if (verify === null || verify === undefined) return 'не проверялось'
  return `${verify.fails} ${plural(verify.fails, 'ошибка', 'ошибки', 'ошибок')}, ${verify.warns} ${plural(
    verify.warns,
    'предупреждение',
    'предупреждения',
    'предупреждений',
  )}`
}

function kindLabel(kind) {
  switch (kind) {
    case 'rollback':
      return 'откат'
    case 'baseline':
      return 'первичная запись'
    default:
      return 'обновление'
  }
}

function deltaKind(before, after) {
  if ((before ?? '') === '' && (after ?? '') === '') return '—'
  if ((before ?? '') === '') return 'added'
  if ((after ?? '') === '') return 'removed'
  if (before === after) return '—'
  const oldVersion = parse(before)
  const newVersion = parse(after)
  if (oldVersion === undefined || newVersion === undefined) return 'changed'
  if (oldVersion.major !== newVersion.major) return 'major'
  if (oldVersion.minor !== newVersion.minor) return 'minor'
  if (oldVersion.patch !== newVersion.patch) return 'patch'
  if (oldVersion.pre.join('.') !== newVersion.pre.join('.')) return 'prerelease'
  return 'changed'
}

function depKind(dep) {
  const spec = String(dep?.spec ?? '')
  if (spec.startsWith('file:')) return 'file:'
  if (spec.startsWith('link:')) return 'link:'
  if (spec.startsWith('portal:')) return 'portal:'
  if (spec.startsWith('github:')) return 'github'
  if (/^https?:/i.test(spec)) return 'url'
  if (dep?.kind === 'file') return 'file:'
  if (dep?.kind === 'url') return 'url'
  return 'registry'
}

function cell(value) {
  const text = String(value ?? '')
    .replace(/\|/g, '\\|')
    .replace(/\r?\n/g, ' ')
    .trim()
  return text === '' ? '—' : text
}

function code(value) {
  const text = String(value ?? '').trim()
  return text === '' ? '—' : `\`${text.replace(/`/g, '')}\``
}

function rowsFor(before, after) {
  const rows = []
  const beforeCore = before?.core?.version ?? null
  const afterCore = after?.core?.version ?? null
  rows.push({
    group: 'core',
    component: 'Ядро DSH',
    profile: '—',
    before: beforeCore,
    after: afterCore,
    delta: deltaKind(beforeCore, afterCore),
    note: after?.core?.installMethod ?? '—',
  })

  const profiles = [...new Set([...Object.keys(before?.profiles ?? {}), ...Object.keys(after?.profiles ?? {})])].sort()
  for (const profile of profiles) {
    const oldTui = before?.profiles?.[profile]?.tui?.version ?? null
    const newTui = after?.profiles?.[profile]?.tui?.version ?? null
    if (oldTui === null && newTui === null) continue
    const peerRange = after?.profiles?.[profile]?.tui?.peerCore ?? ''
    let peer = 'unknown'
    if (peerRange !== '' && afterCore !== null) {
      try {
        peer = satisfies(peerRange, afterCore)
      } catch {
        peer = 'unknown'
      }
    }
    rows.push({
      group: 'tui',
      component: 'TUI',
      profile,
      before: oldTui,
      after: newTui,
      delta: deltaKind(oldTui, newTui),
      note: peer === 'yes' ? 'peer ok' : peer === 'no' ? 'peer ✗' : 'peer ?',
    })
  }

  for (const profile of profiles) {
    const oldDeps = before?.profiles?.[profile]?.deps ?? {}
    const newDeps = after?.profiles?.[profile]?.deps ?? {}
    const names = [...new Set([...Object.keys(oldDeps), ...Object.keys(newDeps)])]
      .filter(name => name !== TUI_PKG)
      .sort()
    for (const name of names) {
      const oldDep = oldDeps[name]
      const newDep = newDeps[name]
      const oldVersion = oldDep?.installed ?? null
      const newVersion = newDep?.installed ?? null
      const kind = depKind(newDep ?? oldDep)
      const notes = []
      if (kind === 'file:') notes.push('`file:`-форк')
      else if (kind === 'url') notes.push('URL/архив')
      else if (kind === 'github') notes.push('github')
      if (oldVersion === null && newVersion !== null) notes.push('добавлен')
      if (oldVersion !== null && newVersion === null) notes.push('удалён')
      if (notes.length === 0) notes.push(kind)
      rows.push({
        group: 'plugin',
        component: name,
        profile,
        before: oldVersion,
        after: newVersion,
        delta: deltaKind(oldVersion, newVersion),
        note: notes.join('; '),
      })
    }
  }
  return rows
}

function changedRows(rows) {
  return rows.filter(row => row.delta !== '—' && row.delta !== 'same')
}

function profileCount(state) {
  return Object.keys(state?.profiles ?? {}).length
}

function pluginCount(state) {
  let count = 0
  for (const profile of Object.values(state?.profiles ?? {})) {
    count += Object.keys(profile?.deps ?? {}).filter(name => name !== TUI_PKG).length
  }
  return count
}

function tuiSummary(state) {
  const entries = Object.entries(state?.profiles ?? {})
    .filter(([, value]) => value?.tui?.version)
    .map(([profile, value]) => `${profile}: ${value.tui.version}`)
  return entries
}

function changedPluginCount(run) {
  return changedRows(rowsFor(run.before, run.after)).filter(row => row.group === 'plugin').length
}

function corePhrase(run) {
  const before = run.before?.core?.version ?? ''
  const after = run.after?.core?.version ?? ''
  if (before === '' || after === '') return '—'
  if (before === after) return 'не менялось'
  return `${before} → ${after}`
}

function tuiPhrase(run) {
  const before = new Set(Object.keys(run.before?.profiles ?? {}))
  const after = new Set(Object.keys(run.after?.profiles ?? {}))
  const profiles = [...new Set([...before, ...after])].sort()
  const entries = []
  for (const profile of profiles) {
    const oldVersion = run.before?.profiles?.[profile]?.tui?.version ?? ''
    const newVersion = run.after?.profiles?.[profile]?.tui?.version ?? ''
    if (oldVersion === '' && newVersion === '') continue
    if (oldVersion === newVersion) continue
    entries.push(`${profile === 'tui' ? '' : `${profile}: `}${oldVersion || '—'} → ${newVersion || '—'}`)
  }
  if (entries.length === 0) {
    const exists = profiles.some(profile => run.after?.profiles?.[profile]?.tui?.version)
    return exists ? 'не менялось' : 'нет'
  }
  return entries.join('; ')
}

function osLabel() {
  const name =
    process.platform === 'darwin' ? 'macOS' : process.platform === 'linux' ? 'Linux' : process.platform
  const arch = process.arch === 'x64' ? 'x86_64' : process.arch === 'arm64' ? 'arm64' : process.arch
  return `${name} ${arch}`
}

function renderNow(after) {
  const lines = []
  lines.push('| Компонент | Версия | Тип | Где |')
  lines.push('|---|---|---|---|')
  lines.push(
    `| Ядро DSH | ${cell(after.core.version)} | ${cell(after.core.installMethod)} | ${
      after.core.installDir ? code(displayPath(after.core.installDir)) : '—'
    } |`,
  )

  const tuiEntries = Object.entries(after.profiles ?? {}).filter(([, value]) => value?.tui?.version)
  if (tuiEntries.length === 0) {
    lines.push('| TUI | — | — | не установлен |')
  } else {
    for (const [profile, value] of tuiEntries) {
      lines.push(`| TUI | ${cell(value.tui.version)} | registry | профиль ${code(profile)} |`)
    }
  }

  lines.push('')
  lines.push('### Плагины')
  lines.push('')
  lines.push('| Профиль | Плагин | Версия | Тип |')
  lines.push('|---|---|---|---|')
  let anyPlugin = false
  for (const profile of Object.keys(after.profiles ?? {}).sort()) {
    const deps = after.profiles[profile]?.deps ?? {}
    for (const name of Object.keys(deps).sort()) {
      if (name === TUI_PKG) continue
      anyPlugin = true
      lines.push(`| ${cell(profile)} | ${cell(name)} | ${cell(deps[name]?.installed)} | ${cell(depKind(deps[name]))} |`)
    }
  }
  if (!anyPlugin) lines.push('| — | — | — | — |')

  const env = after.env ?? {}
  const environment = [
    osLabel(),
    env.node ? `node ${env.node}` : '',
    env.npm ? `npm ${env.npm}` : '',
    env.pnpm ? `pnpm ${env.pnpm}` : '',
  ].filter(Boolean)
  lines.push('')
  lines.push(`**Среда:** ${environment.join(' · ')}.`)
  return lines.join('\n')
}

function renderRowsTable(rows) {
  const lines = []
  lines.push('| Компонент | Профиль | До | После | Δ | Примечание |')
  lines.push('|---|---|---|---|---|---|')
  for (const row of rows) {
    lines.push(
      `| ${cell(row.component)} | ${cell(row.profile)} | ${cell(row.before)} | ${cell(row.after)} | ${cell(
        row.delta,
      )} | ${cell(row.note)} |`,
    )
  }
  return lines.join('\n')
}

function renderLast(run) {
  const lines = []
  lines.push(
    `**Когда:** ${dateTime(run.at)} · **Тип:** ${kindLabel(run.kind)} · **Снимок:** ${
      run.snapshot ? code(displayPath(run.snapshot)) : '—'
    } · **Проверка:** ${verifyText(run.verify)}`,
  )
  lines.push('')

  if (run.before === null || run.kind === 'baseline') {
    lines.push('Первичная запись: предыдущее состояние неизвестно — снимка до обновления нет. Текущие версии — в разделе «Сейчас».')
  } else {
    lines.push(renderRowsTable(rowsFor(run.before, run.after)))
  }

  lines.push('')
  lines.push(
    `**Не обновилось:** ${
      (run.skipped ?? []).length === 0 ? '—' : run.skipped.map(item => cell(item)).join(', ')
    }`,
  )

  const errors = (run.verify?.errors ?? []).slice(0, 3)
  if (errors.length > 0) {
    lines.push('')
    lines.push(`**Ошибки:** ${errors.map(item => cell(item)).join('; ')}`)
  }

  const warnings = (run.verify?.warnings ?? []).slice(0, 3)
  lines.push('')
  lines.push(`**Предупреждения:** ${warnings.length === 0 ? '—' : warnings.map(item => cell(item)).join('; ')}`)

  lines.push('')
  lines.push('> [!warning] Нужен ручной перезапуск')
  lines.push('> Текущая TUI/web-сессия работает на старом коде. Перезапусти TUI вручную — скилл этого не делает.')

  if (run.snapshot) {
    lines.push('')
    lines.push('> [!tip] Откат')
    lines.push(
      `> \`~/.dsh/skills/dsh-update/scripts/rollback.sh --snapshot "${displayPath(run.snapshot)}" --yes\``,
    )
  }
  return lines.join('\n')
}

function renderPrevious(run) {
  if (run === null || run === undefined) {
    return 'Предыдущих обновлений нет — это первая запись в журнале.'
  }
  const lines = []
  lines.push(
    `**Когда:** ${dateTime(run.at)} · **Тип:** ${kindLabel(run.kind)} · **Снимок:** ${
      run.snapshot ? code(displayPath(run.snapshot)) : '—'
    } · **Проверка:** ${verifyText(run.verify)}`,
  )
  lines.push('')

  if (run.before === null || run.kind === 'baseline') {
    lines.push('Первичная запись: сравнивать не с чем.')
    return lines.join('\n')
  }

  const changed = changedRows(rowsFor(run.before, run.after))
  if (changed.length === 0) {
    lines.push('Изменений версий не было.')
  } else {
    lines.push(renderRowsTable(changed))
  }
  lines.push('')
  lines.push(
    `**Итог:** ${changed.length} ${plural(changed.length, 'компонент', 'компонента', 'компонентов')}, ${verifyText(
      run.verify,
    )}.`,
  )
  return lines.join('\n')
}

function renderHistory(runs) {
  const lines = []
  lines.push('| Дата | Тип | Ядро | TUI | Плагины | Проверка | Снимок |')
  lines.push('|---|---|---|---|---|---|---|')
  if (runs.length === 0) {
    lines.push('| — | — | — | — | — | — | — |')
    return lines.join('\n')
  }

  for (const run of [...runs].reverse()) {
    const core =
      run.before?.core?.version === undefined || run.before?.core?.version === ''
        ? '—'
        : run.before.core.version === run.after.core.version
          ? cell(run.after.core.version)
          : `${cell(run.before.core.version)} → ${cell(run.after.core.version)}`

    const tuiEntries = []
    if (run.before !== null) {
      const tuiRows = changedRows(rowsFor(run.before, run.after)).filter(row => row.group === 'tui')
      const singleProfile = new Set(tuiRows.map(row => row.profile)).size === 1
      for (const row of tuiRows) {
        tuiEntries.push(
          singleProfile
            ? `${row.before || '—'} → ${row.after || '—'}`
            : `${row.profile}: ${row.before || '—'} → ${row.after || '—'}`,
        )
      }
    }

    const pluginChanges = run.before === null ? null : changedPluginCount(run)
    const plugins = pluginChanges === null || pluginChanges === 0 ? '—' : String(pluginChanges)
    const verify =
      run.verify === null || run.verify === undefined ? '—' : `${run.verify.fails} / ${run.verify.warns}`
    lines.push(
      `| ${dateTime(run.at)} | ${kindLabel(run.kind)} | ${core} | ${
        tuiEntries.length === 0 ? '—' : tuiEntries.join('; ')
      } | ${plugins} | ${verify} | ${run.snapshot ? code(basename(run.snapshot)) : '—'} |`,
    )
  }
  return lines.join('\n')
}

function renderSnapshots(runs) {
  const snapshots = runs
    .filter(run => run.kind !== 'rollback')
    .map(run => run.snapshot)
    .filter(Boolean)
  const last = snapshots[snapshots.length - 1]
  const previous = snapshots[snapshots.length - 2]
  const keepSnapshots = process.env.DSH_UPDATE_KEEP_SNAPSHOTS ?? '5'
  const keepReports = process.env.DSH_UPDATE_KEEP_REPORTS ?? '20'
  const lines = []
  lines.push(`- Последний снимок: ${last ? code(displayPath(last)) : '—'}`)
  lines.push(`- Предыдущий: ${previous ? code(displayPath(previous)) : '—'}`)
  lines.push(`- Хранится: ${keepSnapshots} снимков, ${keepReports} отчётов.`)
  lines.push(
    '- Откат: `~/.dsh/skills/dsh-update/scripts/rollback.sh --snapshot "<путь>" --yes`',
  )
  const lastVerify = [...runs].reverse().find(run => run.verify?.dir)
  if (lastVerify) lines.push(`- Последний отчёт: ${code(displayPath(lastVerify.verify.dir))}`)
  return lines.join('\n')
}

function renderTldr(runs) {
  const last = runs[runs.length - 1]
  const previous = runs.length > 1 ? runs[runs.length - 2] : null
  const tui = tuiSummary(last.after)
  const tuiText =
    tui.length === 0
      ? '**нет**'
      : tui.length === 1
        ? `**${tui[0].split(': ')[1]}** (профиль \`${tui[0].split(': ')[0]}\`)`
        : tui.map(item => `**${item}**`).join(', ')
  const plugins = pluginCount(last.after)
  const profiles = profileCount(last.after)

  const lines = []
  lines.push(
    `> Сейчас: ядро **${last.after.core.version || '—'}**${
      last.after.core.installMethod ? ` (${last.after.core.installMethod})` : ''
    }, TUI ${tuiText}, ${plugins} ${plural(plugins, 'плагин', 'плагина', 'плагинов')} в ${profiles} ${plural(
      profiles,
      'профиле',
      'профилях',
      'профилях',
    )}.`,
  )

  if (last.kind === 'baseline' || last.before === null) {
    lines.push(`> Первичная запись ${shortDate(last.at)}: зафиксировано текущее состояние, предыдущих версий нет.`)
  } else {
    const what = last.kind === 'rollback' ? 'Последний откат' : 'Последнее обновление'
    const changed = changedPluginCount(last)
    if (changed === 0 && corePhrase(last) === 'не менялось' && tuiPhrase(last) === 'не менялось') {
      lines.push(`> ${what} ${shortDate(last.at)}: версии не менялись.`)
    } else {
      lines.push(
        `> ${what} ${shortDate(last.at)}: ядро ${corePhrase(last)}, TUI ${tuiPhrase(last)}, изменено ${changed} ${plural(
          changed,
          'плагин',
          'плагина',
          'плагинов',
        )}.`,
      )
    }
  }

  lines.push(
    `> Проверка: ${verifyText(last.verify)}. Снимок: ${last.snapshot ? code(basename(last.snapshot)) : '—'}.`,
  )

  if (previous === null) {
    lines.push('> Предыдущих обновлений нет — это первая запись.')
  } else {
    const what = previous.kind === 'rollback' ? 'Предыдущий откат' : 'Предыдущее обновление'
    lines.push(`> ${what} ${shortDate(previous.at)}: ядро ${corePhrase(previous)}, TUI ${tuiPhrase(previous)}.`)
  }
  return lines.join('\n')
}

function renderMarkdown(ledger) {
  const runs = ledger.runs
  const last = runs[runs.length - 1]
  const previous = runs.length > 1 ? runs[runs.length - 2] : null
  const created = ledger.createdAt || localDate(new Date(last.at))

  const lines = []
  lines.push('---')
  lines.push('tags:')
  lines.push('  - sys')
  lines.push('type: backup')
  lines.push('source: by_ai')
  lines.push(`created: ${created}`)
  lines.push(`time: ${last.at}`)
  lines.push('---')
  lines.push('# DSH: версии и журнал обновлений')
  lines.push('')
  lines.push('> [!abstract] TL;DR')
  lines.push(renderTldr(runs))
  lines.push('')
  lines.push('## Содержание')
  lines.push('- [[#Сейчас]]')
  lines.push('- [[#Последнее обновление]]')
  lines.push('- [[#Предыдущее обновление]]')
  lines.push('- [[#История]]')
  lines.push('- [[#Снимки и откат]]')
  lines.push('')
  lines.push('## Сейчас')
  lines.push('')
  lines.push(renderNow(last.after))
  lines.push('')
  lines.push('## Последнее обновление')
  lines.push('')
  lines.push(renderLast(last))
  lines.push('')
  lines.push('## Предыдущее обновление')
  lines.push('')
  lines.push(renderPrevious(previous))
  lines.push('')
  lines.push('## История')
  lines.push('')
  lines.push(renderHistory(runs))
  lines.push('')
  lines.push('## Снимки и откат')
  lines.push('')
  lines.push(renderSnapshots(runs))
  lines.push('')
  return lines.join('\n')
}

function stateKey(state) {
  const parts = [state?.core?.version ?? '']
  for (const profile of Object.keys(state?.profiles ?? {}).sort()) {
    parts.push(`${profile}::${state.profiles[profile]?.tui?.version ?? ''}`)
    for (const name of Object.keys(state.profiles[profile]?.deps ?? {}).sort()) {
      parts.push(`${profile}/${name}@${state.profiles[profile].deps[name]?.installed ?? ''}`)
    }
  }
  return parts.join('|')
}

function runKey(run) {
  return `${run.kind}|${run.snapshot ?? ''}|${stateKey(run.after)}`
}

function loadLedger(dir) {
  const file = join(dir, LEDGER_NAME)
  if (!existsSync(file)) return { format: FORMAT, createdAt: '', runs: [] }
  let parsed
  try {
    parsed = readJson(file)
  } catch (error) {
    fail(`не читается ${file}: ${error.message}. Исправьте или удалите его, чтобы начать журнал заново.`, 5)
  }
  if (parsed === null || typeof parsed !== 'object' || !Array.isArray(parsed.runs)) {
    fail(`${file}: ожидался объект с массивом runs`, 5)
  }
  return {
    format: parsed.format ?? FORMAT,
    createdAt: typeof parsed.createdAt === 'string' ? parsed.createdAt : '',
    runs: parsed.runs.filter(run => run !== null && typeof run === 'object'),
  }
}

function existingCreated(dir) {
  const file = join(dir, FILE_NAME)
  if (!existsSync(file)) return ''
  try {
    const text = readFileSync(file, 'utf8').slice(0, 4000)
    const match = text.match(/^created:\s*(\d{4}-\d{2}-\d{2})\s*$/m)
    return match === null ? '' : match[1]
  } catch {
    return ''
  }
}

function writeAtomic(file, text) {
  const directory = dirname(file)
  const temporary = join(directory, `.${basename(file)}.tmp-${process.pid}`)
  try {
    writeFileSync(temporary, text, { encoding: 'utf8', mode: 0o644 })
    renameSync(temporary, file)
    try {
      chmodSync(file, 0o644)
    } catch {
      // режим не критичен
    }
  } catch (error) {
    try {
      unlinkSync(temporary)
    } catch {
      // временного файла могло не быть
    }
    throw error
  }
}

function currentState() {
  try {
    return extractState(collect({ dumps: false }))
  } catch (error) {
    fail(`collect.mjs не смог собрать состояние: ${error.message}`, 5)
  }
}

function commandPath() {
  const target = resolveTarget(OPTS.dir)
  if (OPTS.json) {
    process.stdout.write(`${JSON.stringify(targetInfo(target), null, 2)}\n`)
    return target.needsChoice ? 3 : 0
  }
  if (target.needsChoice) {
    process.stderr.write('Нужен выбор, куда писать журнал:\n')
    for (const candidate of target.candidates) {
      process.stderr.write(`  • ${candidate.label}: ${candidate.file}\n`)
    }
    process.stderr.write('Повторите с --dir <каталог>.\n')
    return 3
  }
  process.stdout.write(`${target.dir}\n`)
  return 0
}

function commandWrite() {
  if (!['update', 'rollback', 'baseline'].includes(OPTS.kind)) {
    fail(`--kind: ожидается update, rollback или baseline, получено ${OPTS.kind}`, 2)
  }

  const target = resolveTarget(OPTS.dir)
  if (target.needsChoice) {
    process.stderr.write('Нет Backup/doc — выберите, куда писать журнал:\n')
    for (const candidate of target.candidates) {
      process.stderr.write(`  • ${candidate.label}: ${candidate.file}\n`)
    }
    process.stderr.write('Повторите с --dir <каталог>.\n')
    if (OPTS.json) process.stdout.write(`${JSON.stringify(targetInfo(target), null, 2)}\n`)
    return 3
  }

  const directory = target.dir
  try {
    mkdirSync(directory, { recursive: true })
  } catch (error) {
    fail(`не удалось создать ${directory}: ${error.message}`, 4)
  }

  const ledger = loadLedger(directory)
  const previousRun = ledger.runs.length > 0 ? ledger.runs[ledger.runs.length - 1] : null
  const before =
    OPTS.kind === 'rollback'
      ? previousRun?.after ?? null
      : OPTS.snapshot !== ''
        ? readSnapshotState(OPTS.snapshot) ?? previousRun?.after ?? null
        : previousRun?.after ?? null

  let kind = OPTS.kind
  if (before === null) kind = 'baseline'

  const run = {
    at: localIso(),
    kind,
    snapshot: OPTS.snapshot === '' ? null : resolve(OPTS.snapshot),
    before,
    after: currentState(),
    verify:
      OPTS.noVerify || (OPTS.kind === 'rollback' && OPTS.verifyDir === '')
        ? null
        : readVerify(OPTS.verifyDir),
    skipped: OPTS.skipped.map(item => String(item).trim()).filter(Boolean),
  }

  const key = runKey(run)
  const existingIndex = ledger.runs.findIndex(item => runKey(item) === key)
  if (existingIndex >= 0) {
    const old = ledger.runs[existingIndex]
    ledger.runs[existingIndex] = {
      ...run,
      at: typeof old.at === 'string' && old.at !== '' ? old.at : run.at,
      verify: run.verify ?? old.verify ?? null,
      skipped: run.skipped.length > 0 ? run.skipped : old.skipped ?? [],
    }
  } else {
    ledger.runs.push(run)
  }

  ledger.createdAt = ledger.createdAt || existingCreated(directory) || localDate(new Date(run.at))
  const markdown = renderMarkdown(ledger)
  const file = join(directory, FILE_NAME)

  if (OPTS.stdout) {
    process.stdout.write(markdown)
    return 0
  }

  try {
    writeAtomic(join(directory, LEDGER_NAME), `${JSON.stringify(ledger, null, 2)}\n`)
    writeAtomic(file, markdown)
  } catch (error) {
    fail(`не удалось записать журнал: ${error.message}`, 4)
  }

  if (OPTS.dir !== '' || target.source === 'сохранённый выбор') saveTarget(directory)

  if (OPTS.json) {
    process.stdout.write(
      `${JSON.stringify(
        {
          ok: true,
          file,
          createdAt: ledger.createdAt,
          run: {
            at: run.at,
            kind: run.kind,
            snapshot: run.snapshot,
            verify: run.verify === null ? null : { fails: run.verify.fails, warns: run.verify.warns },
            skipped: run.skipped,
            changed: changedRows(rowsFor(run.before, run.after)).length,
          },
        },
        null,
        2,
      )}\n`,
    )
  } else {
    process.stdout.write(`Журнал: ${file} (${kindLabel(run.kind)}, ${dateTime(run.at)})\n`)
  }
  return 0
}

let exitCode = 0
switch (CMD) {
  case 'path':
    exitCode = commandPath()
    break
  case 'write':
    exitCode = commandWrite()
    break
  case 'help':
  case '--help':
  case '-h':
    usage()
    break
  default:
    usage()
    fail(`неизвестная команда: ${CMD}`, 2)
}
process.exit(exitCode)
