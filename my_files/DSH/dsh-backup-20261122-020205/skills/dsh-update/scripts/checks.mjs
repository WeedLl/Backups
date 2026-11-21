#!/usr/bin/env node
/**
 * checks.mjs — статические проверки по данным collect.mjs.
 *
 *   node checks.mjs <current.json> [baseline.json]
 *
 * Печатает JSON-массив находок: [{level, scope, check, message}].
 * level: ok | warn | fail | skip.
 */
import { readFileSync } from 'node:fs'
import { satisfies } from './util.mjs'

const [currentPath, baselinePath] = process.argv.slice(2)
const read = file => JSON.parse(readFileSync(file, 'utf8'))
const current = read(currentPath)
const baseline = baselinePath === undefined ? undefined : read(baselinePath)

const findings = []
const add = (level, scope, check, message) => findings.push({ level, scope, check, message })

const coreVersion = current.core?.version ?? ''
const profiles = current.profiles ?? {}

/* ── ядро ────────────────────────────────────────────────────────────── */
if (coreVersion === '') add('fail', 'global', 'core', 'не удалось определить версию ядра (dsh --version)')
else add('ok', 'global', 'core', `ядро ${coreVersion} (${current.core.installMethod})`)
if (current.core?.installMethod === 'unknown' || current.core?.installMethod === 'other') {
  add('warn', 'global', 'core-install', `способ установки ядра не распознан: ${current.core.installDir || '?'} — обновлять только вручную`)
}

/* ── профили ─────────────────────────────────────────────────────────── */
for (const [name, profile] of Object.entries(profiles)) {
  const dump = profile.dump
  if (dump === undefined) {
    add('warn', name, 'dump', 'конфиг не проверялся (снимок без --dumps)')
  } else if (dump.exit !== 0) {
    add('fail', name, 'dump', `конфиг профиля не собирается: exit ${dump.exit}`)
  } else {
    add('ok', name, 'dump', `конфиг собирается: ${dump.entries} записей`)
  }

  const missing = Object.entries(profile.bundleResolution ?? {}).filter(([, v]) => v.ok !== true).map(([k]) => k)
  if (missing.length > 0) add('fail', name, 'bundles', `не найдены bundles: ${missing.join(', ')}`)
  else add('ok', name, 'bundles', `все ${profile.bundles.length} bundles на месте`)

  const badDeps = Object.entries(profile.deps ?? {}).filter(([, d]) => d.status === 'missing').map(([k]) => k)
  if (badDeps.length > 0) add('fail', name, 'deps', `не установлены: ${badDeps.join(', ')}`)
  const drift = Object.entries(profile.deps ?? {}).filter(([, d]) => d.status === 'drift').map(([k, d]) => `${k} (${d.installed} != lock ${d.lockVersion})`)
  if (drift.length > 0) add('warn', name, 'deps-lock', `расхождение с lockfile: ${drift.join(', ')}`)
  const unlocked = Object.entries(profile.deps ?? {}).filter(([, d]) => d.status === 'unlocked').map(([k]) => k)
  if (unlocked.length > 0) add('warn', name, 'deps-lock', `нет записи в lockfile: ${unlocked.join(', ')}`)

  for (const [dep, info] of Object.entries(profile.deps ?? {})) {
    if (info.kind === 'file' && info.installed !== '' && info.name !== dep) {
      add('warn', name, 'fork', `${dep} установлен как "${info.name}" — переименованный форк, обновление из npm его затрёт`)
    }
  }

  if (profile.tui !== undefined && coreVersion !== '') {
    const verdict = profile.tui.peerCore === undefined ? 'unknown' : satisfies(profile.tui.peerCore, coreVersion)
    if (verdict === 'yes') add('ok', name, 'peer', `TUI ${profile.tui.version} поддерживает ядро ${coreVersion}`)
    else if (verdict === 'no') add('fail', name, 'peer', `TUI ${profile.tui.version} НЕ поддерживает ядро ${coreVersion}`)
    else add('warn', name, 'peer', `совместимость TUI ${profile.tui.version} и ядра ${coreVersion} не подтверждена`)
  }
}

/* ── новые предупреждения загрузчика ─────────────────────────────────── */
const warningsOf = snapshot =>
  Object.entries(snapshot.profiles ?? {}).flatMap(([profile, p]) => (p.dump?.warnings ?? []).map(line => ({ profile, line })))
if (baseline !== undefined) {
  const before = new Set(warningsOf(baseline).map(w => `${w.profile}|${w.line}`))
  const after = warningsOf(current)
  const fresh = after.filter(w => !before.has(`${w.profile}|${w.line}`))
  for (const w of fresh) add('warn', w.profile, 'loader-warning', `новое предупреждение: ${w.line}`)
  const known = after.length - fresh.length
  if (known > 0 && fresh.length === 0) add('ok', 'global', 'loader-warning', `${known} известных предупреждений — как в базовой линии`)
} else {
  for (const w of warningsOf(current)) add('warn', w.profile, 'loader-warning', w.line)
}

/* ── скиллы ──────────────────────────────────────────────────────────── */
const skills = current.skills ?? []
const invalid = skills.filter(s => s.ok !== true)
for (const s of invalid) add('fail', 'global', 'skill', `${s.path}: ${s.problem}`)
if (invalid.length === 0) add('ok', 'global', 'skill', `${skills.length} скиллов, фронтматтер валиден`)

const byProfile = new Map()
for (const s of skills) {
  if (s.profile === undefined) continue
  const key = `${s.profile}|${s.name}`
  byProfile.set(key, (byProfile.get(key) ?? 0) + 1)
}
for (const [key, count] of byProfile) {
  if (count > 1) add('warn', key.split('|')[0], 'skill', `скилл ${key.split('|')[1]} объявлен ${count} раза — перекрытие`)
}
const userSkills = new Set(skills.filter(s => s.source === 'user').map(s => s.name))
for (const s of skills) {
  if (s.source === 'plugin' && userSkills.has(s.name)) {
    add('warn', s.profile ?? 'global', 'skill', `скилл ${s.name} из плагина перекрыт пользовательским ~/.dsh/skills`)
  }
}

/* ── dsh_backup ──────────────────────────────────────────────────────── */
const backup = current.backup ?? {}
if (backup.exists === true) {
  if ((backup.uncoveredTui ?? []).length > 0) {
    add('warn', 'global', 'backup', `dsh_backup не покрывает файлы TUI: ${backup.uncoveredTui.join(', ')}`)
  } else {
    add('ok', 'global', 'backup', 'dsh_backup покрывает все файлы состояния TUI')
  }
  for (const gap of backup.structuralGaps ?? []) add('warn', 'global', 'backup', `вне dsh_backup: ${gap}`)
  if (backup.run !== undefined && backup.run.ok === true) {
    add('ok', 'global', 'backup-run', 'dsh_backup выполняется в dry-run без ошибок')
  } else if (backup.run !== undefined) {
    add('fail', 'global', 'backup-run', `dsh_backup -n падает (exit ${backup.run.exit}): ${backup.run.stderr || 'без вывода'}`)
  }
} else {
  add('skip', 'global', 'backup', `скрипт dsh_backup не найден (${backup.script ?? '?'}) — проверка покрытия пропущена`)
}

process.stdout.write(JSON.stringify(findings, null, 2) + '\n')
