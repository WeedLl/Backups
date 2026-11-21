#!/usr/bin/env node
/**
 * check.mjs — «что можно обновить и чем это грозит».
 *
 *   node check.mjs [--json] [--offline]
 *
 * Ничего не устанавливает и не меняет: только читает реестр, профили и локальные
 * исходники. Пишет отчёт в stdout. Код выхода 0, если отчёт построен.
 */
import { execFileSync } from 'node:child_process'
import { existsSync } from 'node:fs'
import { homedir } from 'node:os'
import { join } from 'node:path'
import { collect } from './collect.mjs'
import { compare, satisfies } from './util.mjs'

const argv = process.argv.slice(2)
const AS_JSON = argv.includes('--json')
const OFFLINE = argv.includes('--offline')
const DSH_HOME = process.env.DSH_HOME ?? join(homedir(), '.dsh')
const CORE_PKG = '@deepseek-ai/dsh'
const TUI_PKG = '@deepseek-harness-tui/dsh-tui'

const run = (bin, args, timeout = 60_000) => {
  try {
    return { ok: true, out: execFileSync(bin, args, { encoding: 'utf8', timeout, maxBuffer: 16 * 1024 * 1024 }) }
  } catch (error) {
    return { ok: false, out: (error.stdout ?? '') + (error.stderr ?? ''), error }
  }
}

const parseJson = text => {
  try {
    return JSON.parse(text)
  } catch {
    return undefined
  }
}

const npmJson = args => {
  if (OFFLINE) return undefined
  const r = run('npm', args)
  return r.ok ? parseJson(r.out) : undefined
}

const collectData = collect({ dumps: true })

/* ── версии ядра ─────────────────────────────────────────────────────── */
const coreTags = npmJson(['view', CORE_PKG, 'dist-tags', '--json']) ?? {}
const coreVersions = npmJson(['view', CORE_PKG, 'versions', '--json']) ?? []
const coreCurrent = collectData.core.version
const coreLatest = coreTags.latest
const coreNext = coreTags.next
const newerCores = Array.isArray(coreVersions)
  ? coreVersions.filter(v => v !== coreCurrent && compare(v, coreCurrent) > 0)
  : []

/* ── версии TUI ──────────────────────────────────────────────────────── */
const tuiTags = npmJson(['view', TUI_PKG, 'dist-tags', '--json']) ?? {}
const tuiLatest = tuiTags.latest
const tuiProfiles = Object.entries(collectData.profiles).filter(([, p]) => p.tui !== undefined)
const tuiCurrent = tuiProfiles[0]?.[1]?.tui?.version

const peerCache = new Map()
const peerRangeOf = version => {
  if (version === undefined) return undefined
  if (peerCache.has(version)) return peerCache.get(version)
  const peers = npmJson(['view', `${TUI_PKG}@${version}`, 'peerDependencies', '--json'])
  const range = peers?.['@deepseek-ai/dsh-agent']
  peerCache.set(version, range)
  return range
}

/* ── устаревшие пакеты в профилях ────────────────────────────────────── */
const outdatedByProfile = {}
for (const [name, profile] of Object.entries(collectData.profiles)) {
  if (OFFLINE) {
    outdatedByProfile[name] = {}
    continue
  }
  const r = run('pnpm', ['--dir', profile.dir, 'outdated', '--json'], 90_000)
  const data = parseJson(r.out.trim() === '' ? '{}' : r.out)
  if (data !== undefined && typeof data === 'object') outdatedByProfile[name] = data
}

/* ── классификация обновлений плагинов ───────────────────────────────── */
const KNOWN_FORK_NAMES = new Set(['dsh-tui-pkg'])
const bumpKind = (a, b) => {
  const parse = v => {
    const m = String(v).match(/^v?(\d+)\.(\d+)\.(\d+)(?:-([^+]+))?/)
    return m === null ? undefined : { M: +m[1], m: +m[2], p: +m[3], pre: m[4] ?? '' }
  }
  const x = parse(a)
  const y = parse(b)
  if (x === undefined || y === undefined) return 'unknown'
  if (x.M !== y.M) return 'major'
  if (x.m !== y.m) return 'minor'
  if (x.p !== y.p) return 'patch'
  if (x.pre !== y.pre) return 'prerelease'
  return 'same'
}

const plugins = []
for (const [profile, outdated] of Object.entries(outdatedByProfile)) {
  const deps = collectData.profiles[profile]?.deps ?? {}
  for (const [name, info] of Object.entries(outdated)) {
    if (name === TUI_PKG) continue
    const dep = deps[name] ?? {}
    const kind = bumpKind(info.current, info.latest)
    let risk = 'low'
    if (kind === 'major') risk = 'high'
    else if (kind === 'minor' && String(info.current).startsWith('0.')) risk = 'high'
    else if (kind === 'minor') risk = 'medium'
    else if (kind === 'prerelease') risk = 'medium'
    if (info.isDeprecated) risk = 'high'
    const notes = []
    if (dep.kind === 'file') notes.push('локальный file:, обновление только из исходника')
    if (dep.kind === 'url') notes.push('привязан к URL/архиву, не к версии в реестре')
    if (KNOWN_FORK_NAMES.has(name)) notes.push('имя совпадает с апстримом — @latest затрёт форк')
    if (info.isDeprecated) notes.push('версия помечена deprecated')
    if (String(info.current).startsWith('0.')) notes.push('0.x: minor может ломать API')
    plugins.push({
      profile,
      name,
      current: info.current,
      latest: info.latest,
      wanted: info.wanted,
      kind,
      risk,
      deprecated: info.isDeprecated === true,
      notes,
    })
  }
}

/* ── совместимость TUI ↔ ядро ────────────────────────────────────────── */
const cores = [...new Set([coreCurrent, coreLatest, coreNext].filter(v => typeof v === 'string' && v !== ''))]
const tuiVersions = [...new Set([tuiCurrent, tuiLatest].filter(v => typeof v === 'string' && v !== ''))]
const matrix = []
for (const tv of tuiVersions) {
  const range = peerRangeOf(tv)
  const cells = {}
  for (const cv of cores) cells[cv] = range === undefined ? 'unknown' : satisfies(range, cv)
  matrix.push({ tui: tv, range, cells })
}
const compat = (tuiV, coreV) => matrix.find(m => m.tui === tuiV)?.cells?.[coreV] ?? 'unknown'

/* ── предупреждения загрузчика и дрейф ───────────────────────────────── */
const loaderWarnings = []
for (const [name, profile] of Object.entries(collectData.profiles)) {
  for (const w of profile.dump?.warnings ?? []) loaderWarnings.push({ profile: name, line: w })
}

/* ── локальные зависимости ───────────────────────────────────────────── */
const localDeps = []
for (const [profile, p] of Object.entries(collectData.profiles)) {
  for (const [name, dep] of Object.entries(p.deps)) {
    if (dep.kind === 'file') {
      const path = String(dep.spec).replace(/^file:/, '')
      localDeps.push({ profile, name, spec: dep.spec, installed: dep.installed, path, exists: existsSync(path) })
    }
  }
}

/* ── скиллы ──────────────────────────────────────────────────────────── */
const skillsByName = new Map()
for (const skill of collectData.skills) {
  if (skill.name === undefined) continue
  if (!skillsByName.has(skill.name)) skillsByName.set(skill.name, [])
  skillsByName.get(skill.name).push(skill)
}
const skillConflicts = [...skillsByName.entries()].filter(([, list]) => {
  const hasUser = list.some(s => s.source === 'user')
  const hasPlugin = list.some(s => s.source === 'plugin')
  if (hasUser && hasPlugin) return true
  const perProfile = new Map()
  for (const s of list) if (s.profile !== undefined) perProfile.set(s.profile, (perProfile.get(s.profile) ?? 0) + 1)
  return [...perProfile.values()].some(n => n > 1)
})

/* ── рекомендация ────────────────────────────────────────────────────── */
const steps = []
const tuiTarget = tuiLatest !== undefined && tuiCurrent !== undefined && compare(tuiLatest, tuiCurrent) > 0 ? tuiLatest : undefined
const coreTarget = coreLatest
if (tuiTarget !== undefined) {
  const c = compat(tuiTarget, coreCurrent)
  steps.push({
    order: steps.length + 1,
    action: `Обновить TUI ${tuiCurrent} → ${tuiTarget}`,
    command: `dsh plugin --profile ${tuiProfiles[0]?.[0] ?? 'tui'} add ${TUI_PKG}@${tuiTarget}`,
    why: c === 'yes' ? `совместим с текущим ядром ${coreCurrent}` : `совместимость с ядром ${coreCurrent}: ${c}`,
    risk: c === 'no' ? 'high' : 'medium',
  })
}
if (coreTarget !== undefined && coreCurrent !== '' && compare(coreTarget, coreCurrent) > 0) {
  const c = tuiTarget === undefined ? compat(tuiCurrent, coreTarget) : compat(tuiTarget, coreTarget)
  steps.push({
    order: steps.length + 1,
    action: `Обновить ядро ${coreCurrent} → ${coreTarget}`,
    command: `npm i -g ${CORE_PKG}@${coreTarget}`,
    why: `совместимость TUI: ${c}`,
    risk: c === 'no' ? 'high' : 'medium',
  })
}
if (coreNext !== undefined && coreNext !== coreTarget && coreCurrent !== '' && compare(coreNext, coreCurrent) > 0) {
  const c = compat(tuiTarget ?? tuiCurrent, coreNext)
  steps.push({
    order: steps.length + 1,
    action: `Ядро ${coreNext} доступно в теге next, но не в latest`,
    command: `# не обновлять вслепую: TUI ${tuiTarget ?? tuiCurrent} → ${c}`,
    why: `next опережает latest; совместимость: ${c}`,
    risk: c === 'no' ? 'high' : 'medium',
  })
}
for (const p of plugins.filter(x => x.risk === 'high').slice(0, 5)) {
  steps.push({
    order: steps.length + 1,
    action: `Проверить ${p.name} ${p.current} → ${p.latest} (${p.profile})`,
    command: `dsh plugin --profile ${p.profile} add ${p.name}@${p.latest}`,
    why: p.kind === 'major' ? 'мажорное обновление: читайте changelog' : '0.x: minor может ломать API',
    risk: 'high',
  })
}

/* ── вывод ───────────────────────────────────────────────────────────── */
const report = {
  format: 'dsh-update-check/1',
  generatedAt: new Date().toISOString(),
  core: {
    current: coreCurrent,
    latest: coreLatest,
    next: coreNext,
    newer: newerCores,
    installMethod: collectData.core.installMethod,
    installDir: collectData.core.installDir,
  },
  tui: {
    current: tuiCurrent,
    latest: tuiLatest,
    profile: tuiProfiles[0]?.[0],
    peerCore: peerRangeOf(tuiCurrent),
  },
  matrix,
  plugins,
  localDeps,
  loaderWarnings,
  skills: {
    total: collectData.skills.length,
    invalid: collectData.skills.filter(s => s.ok !== true),
    conflicts: skillConflicts.map(([name, list]) => ({ name, origins: list.map(s => ({ path: s.path, plugin: s.plugin, profile: s.profile })) })),
  },
  backup: collectData.backup,
  env: collectData.env,
  steps,
  profiles: Object.fromEntries(Object.entries(collectData.profiles).map(([k, v]) => [k, { bundles: v.bundles.length, dump: v.dump, tui: v.tui?.version }])),
}

if (AS_JSON) {
  process.stdout.write(JSON.stringify(report, null, 2) + '\n')
  process.exit(0)
}

const L = []
L.push(`# Проверка обновлений DSH — ${new Date().toLocaleString('ru-RU')}`)
L.push('')
if (OFFLINE) L.push('_(режим --offline: реестр не опрашивался, показано только локальное состояние)_')

L.push('## Сейчас')
L.push('')
L.push(`- ядро: **${coreCurrent || '?'}** (${collectData.core.installMethod}, ${collectData.core.installDir || '?'})`)
L.push(`- TUI: **${tuiCurrent || 'нет'}** в профиле \`${tuiProfiles[0]?.[0] ?? '—'}\``)
L.push(`- node ${collectData.env.node}, npm ${collectData.env.npm}, pnpm ${collectData.env.pnpm}`)
L.push(`- ключ модели в окружении: ${collectData.env.apiKeyInEnv ? 'есть' : 'нет (живой smoke-тест будет пропущен)'}`)
L.push('')
L.push('## Доступные обновления')
L.push('')
L.push('| Компонент | Сейчас | latest | next |')
L.push('|---|---|---|---|')
L.push(`| Ядро | ${coreCurrent || '?'} | ${coreLatest ?? 'н/д'} | ${coreNext ?? '—'} |`)
L.push(`| TUI | ${tuiCurrent ?? '?'} | ${tuiLatest ?? 'н/д'} | — |`)
L.push('')
if (newerCores.length > 0) {
  L.push(`Новее установленного ядра: ${newerCores.map(v => '`' + v + '`').join(', ')}`)
  L.push('')
}

L.push('## Совместимость TUI ↔ ядро')
L.push('')
L.push('| TUI | ' + cores.map(c => c).join(' | ') + ' |')
L.push('|---|' + cores.map(() => '---').join('|') + '|')
for (const row of matrix) {
  L.push(`| ${row.tui} | ` + cores.map(c => row.cells[c] === 'yes' ? '✓' : row.cells[c] === 'no' ? '✗' : '?').join(' | ') + ' |')
}
L.push('')
if (matrix.some(r => Object.values(r.cells).includes('no'))) {
  L.push('✗ — версия ядра не заявлена в peer-диапазоне TUI. ? — не удалось проверить (нет сети или нестандартный диапазон).')
  L.push('')
}

if (plugins.length > 0) {
  L.push('## Плагины с обновлениями')
  L.push('')
  L.push('| Профиль | Пакет | Сейчас | latest | Тип | Риск |')
  L.push('|---|---|---|---|---|---|')
  for (const p of plugins) {
    L.push(`| ${p.profile} | ${p.name} | ${p.current} | ${p.latest} | ${p.kind} | ${p.risk}${p.notes.length > 0 ? ' — ' + p.notes.join('; ') : ''} |`)
  }
  L.push('')
} else {
  L.push('## Плагины с обновлениями')
  L.push('')
  L.push('Обновлений нет (или реестр недоступен).')
  L.push('')
}

if (localDeps.length > 0) {
  L.push('## Локальные зависимости')
  L.push('')
  for (const d of localDeps) {
    L.push(`- \`${d.name}\` в ${d.profile}: ${d.installed || '?'} ← ${d.path} ${d.exists ? '' : '**(исходник не найден!)**'}`)
  }
  L.push('')
}

if (loaderWarnings.length > 0) {
  L.push('## Предупреждения загрузчика (уже сейчас)')
  L.push('')
  for (const w of loaderWarnings) L.push(`- [${w.profile}] ${w.line}`)
  L.push('')
}

if (skillConflicts.length > 0 || report.skills.invalid.length > 0) {
  L.push('## Скиллы')
  L.push('')
  for (const c of report.skills.conflicts) {
    L.push(`- конфликт имени \`${c.name}\`: ${c.origins.map(o => o.path).join(', ')}`)
  }
  for (const s of report.skills.invalid) L.push(`- невалидный фронтматтер: ${s.path} — ${s.problem}`)
  L.push('')
}

const gap = report.backup
if (gap.exists === true && (gap.uncoveredTui.length > 0 || gap.structuralGaps.length > 0)) {
  L.push('## dsh_backup: покрытие')
  L.push('')
  if (gap.uncoveredTui.length > 0) {
    L.push(`Не покрыты файлы состояния TUI: ${gap.uncoveredTui.map(f => '`' + f + '`').join(', ')}`)
  }
  if (gap.structuralGaps.length > 0) {
    L.push(`Вне бэкапа целиком: ${gap.structuralGaps.map(f => '`' + f + '`').join(', ')}`)
  }
  L.push('')
  L.push('Готовая строка для `dsh_backup.zsh`:')
  L.push('')
  L.push('```zsh')
  L.push(`tui_files+=(${gap.uncoveredTui.map(f => "'" + f + "'").join(' ')})`)
  L.push('```')
  L.push('')
}

L.push('## Рекомендация')
L.push('')
if (steps.length === 0) {
  L.push('Всё актуально; обновлять нечего.')
} else {
  let i = 0
  for (const s of steps) {
    i += 1
    L.push(`${i}. **${s.action}** — ${s.why} (риск: ${s.risk})`)
    if (s.command !== '' && !s.command.startsWith('#')) {
      L.push('   ```bash')
      L.push('   ' + s.command)
      L.push('   ```')
    }
  }
  L.push('')
  L.push('Порядок важен: сначала TUI, потом ядро — так падение установщика оставляет рабочую комбинацию «старый TUI + старое ядро».')
  L.push('')
  L.push('Дальше: `snapshot.sh create before-update`, затем `apply.sh` с выбранными версиями, затем `verify.sh --all`.')
}
L.push('')
L.push(`_Отчёт: ${collectData.host}, ${collectData.generatedAt}_`)

process.stdout.write(L.join('\n') + '\n')
void satisfies
