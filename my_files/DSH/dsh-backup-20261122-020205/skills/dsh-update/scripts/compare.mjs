#!/usr/bin/env node
/**
 * compare.mjs — что изменилось между базовой линией (снимком) и текущим состоянием.
 *
 *   node compare.mjs <baseline.json> <current.json> [--json]
 *
 * Оба файла — вывод collect.mjs. Печатает изменения версий, bundles,
 * предупреждений загрузчика, скиллов и зависимостей.
 */
import { readFileSync } from 'node:fs'

const [baselinePath, currentPath] = process.argv.slice(2)
if (baselinePath === undefined || currentPath === undefined) {
  process.stderr.write('usage: compare.mjs <baseline.json> <current.json>\n')
  process.exit(2)
}

const read = file => {
  try {
    return JSON.parse(readFileSync(file, 'utf8'))
  } catch (error) {
    process.stderr.write(`compare: cannot read ${file}: ${error.message}\n`)
    process.exit(2)
  }
}

const before = read(baselinePath)
const after = read(currentPath)
const AS_JSON = process.argv.includes('--json')

const diffSets = (a, b) => {
  const sa = new Set(a)
  const sb = new Set(b)
  return { added: [...sb].filter(x => !sa.has(x)), removed: [...sa].filter(x => !sb.has(x)) }
}

const warningsOf = snapshot =>
  Object.entries(snapshot.profiles ?? {}).flatMap(([profile, p]) => (p.dump?.warnings ?? []).map(line => `${profile}|${line}`))
const warningDiff = diffSets(warningsOf(before), warningsOf(after))

const bundlesDiff = {}
for (const name of new Set([...Object.keys(before.profiles ?? {}), ...Object.keys(after.profiles ?? {})])) {
  const b = before.profiles?.[name]?.bundles ?? []
  const a = after.profiles?.[name]?.bundles ?? []
  const d = diffSets(b, a)
  if (d.added.length > 0 || d.removed.length > 0) bundlesDiff[name] = d
}

const skillsOf = snapshot => (snapshot.skills ?? []).map(s => s.path)
const skillsDiff = diffSets(skillsOf(before), skillsOf(after))
const invalidSkills = (after.skills ?? []).filter(s => s.ok !== true)

const depsDiff = {}
for (const profile of Object.keys(after.profiles ?? {})) {
  const b = before.profiles?.[profile]?.deps ?? {}
  const a = after.profiles?.[profile]?.deps ?? {}
  const changed = {}
  for (const [name, dep] of Object.entries(a)) {
    const old = b[name]
    if (old === undefined) changed[name] = { from: null, to: dep.installed }
    else if (old.installed !== dep.installed) changed[name] = { from: old.installed, to: dep.installed }
  }
  if (Object.keys(changed).length > 0) depsDiff[profile] = changed
}

const result = {
  format: 'dsh-update-compare/1',
  core: { from: before.core?.version ?? null, to: after.core?.version ?? null },
  tui: Object.fromEntries(
    Object.keys(after.profiles ?? {})
      .map(name => [name, { from: before.profiles?.[name]?.tui?.version ?? null, to: after.profiles?.[name]?.tui?.version ?? null }])
      .filter(([, v]) => v.from !== v.to),
  ),
  bundles: bundlesDiff,
  warnings: warningDiff,
  skills: skillsDiff,
  invalidSkills,
  deps: depsDiff,
  entries: Object.fromEntries(
    Object.keys(after.profiles ?? {}).map(name => [name, { before: before.profiles?.[name]?.dump?.entries ?? null, after: after.profiles?.[name]?.dump?.entries ?? null }]),
  ),
}

if (AS_JSON) {
  process.stdout.write(JSON.stringify(result, null, 2) + '\n')
  process.exit(0)
}

const L = []
if (result.core.from !== result.core.to) L.push(`ядро: ${result.core.from} → ${result.core.to}`)
for (const [name, v] of Object.entries(result.tui)) L.push(`TUI (${name}): ${v.from} → ${v.to}`)
for (const [name, d] of Object.entries(result.deps)) {
  for (const [pkg, v] of Object.entries(d)) L.push(`${name}: ${pkg} ${v.from ?? '—'} → ${v.to ?? '—'}`)
}
for (const [name, d] of Object.entries(result.bundles)) {
  if (d.added.length > 0) L.push(`${name}: добавлены bundles ${d.added.join(', ')}`)
  if (d.removed.length > 0) L.push(`${name}: убраны bundles ${d.removed.join(', ')}`)
}
if (result.warnings.added.length > 0) {
  L.push('новые предупреждения загрузчика:')
  for (const w of result.warnings.added) L.push(`  + ${w}`)
}
if (result.warnings.removed.length > 0) {
  L.push('исчезли предупреждения:')
  for (const w of result.warnings.removed) L.push(`  - ${w}`)
}
if (result.skills.added.length > 0) L.push(`скиллы добавлены: ${result.skills.added.join(', ')}`)
if (result.skills.removed.length > 0) L.push(`скиллы исчезли: ${result.skills.removed.join(', ')}`)
for (const s of result.invalidSkills) L.push(`скилл сломан: ${s.path} — ${s.problem}`)
process.stdout.write((L.length === 0 ? 'без изменений\n' : L.join('\n') + '\n'))
