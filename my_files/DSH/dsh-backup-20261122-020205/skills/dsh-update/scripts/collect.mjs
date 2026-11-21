#!/usr/bin/env node
/**
 * collect.mjs — собрать все статические факты о профилях DSH в один JSON.
 *
 *   node collect.mjs [--dumps] [--json]
 *
 * --dumps  дополнительно прогнать `dsh --profile X --dump-config` (пишет cordis.yml
 *          в профиле — это штатное поведение любого запуска профиля) и сохранить
 *          код выхода, число записей и строки предупреждений.
 *
 * Используется snapshot.sh (базовая линия), check.sh (отчёт) и verify.sh (проверка).
 */
import { execFileSync, spawnSync } from 'node:child_process'
import { existsSync, readFileSync, readdirSync, realpathSync, statSync } from 'node:fs'
import { homedir } from 'node:os'
import { dirname, join, resolve } from 'node:path'
import { parseSkill, parseLock, satisfies } from './util.mjs'

const ARGS = process.argv.slice(2)

const HOME = homedir()
const DSH_HOME = process.env.DSH_HOME ?? join(HOME, '.dsh')
const TUI_HOME = process.env.DSH_TUI_HOME ?? join(HOME, '.dsh-tui')
const BACKUP_CANDIDATES = [
  process.env.DSH_BACKUP_SCRIPT,
  join(HOME, '.zsh_MyFunctions/dsh_backup.zsh'),
  join(HOME, 'Documents/Ai/DSH/dsh_backup/dsh_backup.zsh'),
  join(HOME, 'Documents/ForSys/Backup/.zsh_MyFunctions/dsh_backup.zsh'),
].filter(p => typeof p === 'string' && p !== '')
const BACKUP_SCRIPT = BACKUP_CANDIDATES.find(p => existsSync(p)) ?? BACKUP_CANDIDATES[0]
const DUMPS_TIMEOUT = Number(process.env.DSH_UPDATE_DUMP_TIMEOUT_MS ?? 90_000)

const readJson = file => {
  try {
    return JSON.parse(readFileSync(file, 'utf8'))
  } catch {
    return undefined
  }
}

const listDirs = dir => {
  try {
    return readdirSync(dir, { withFileTypes: true })
      .filter(e => e.isDirectory() || e.isSymbolicLink())
      .map(e => e.name)
      .filter(n => !n.startsWith('.'))
      .sort()
  } catch {
    return []
  }
}

const listFiles = dir => {
  try {
    return readdirSync(dir, { withFileTypes: true })
      .filter(e => e.isFile())
      .map(e => e.name)
      .sort()
  } catch {
    return []
  }
}

function coreInfo() {
  let version = ''
  try {
    version = execFileSync('dsh', ['--version'], { encoding: 'utf8', timeout: 30_000 }).trim().split('\n')[0].trim()
  } catch {
    version = ''
  }
  let bin = ''
  try {
    bin = execFileSync('which', ['dsh'], { encoding: 'utf8' }).trim()
  } catch {
    bin = ''
  }
  let real = bin
  try {
    if (bin !== '') real = realpathSync(bin)
  } catch {
    real = bin
  }
  const installDir = real.endsWith('/lib/bin.js') ? dirname(dirname(real)) : ''
  let npmRoot = ''
  try {
    npmRoot = execFileSync('npm', ['root', '-g'], { encoding: 'utf8', timeout: 30_000 }).trim()
  } catch {
    npmRoot = ''
  }
  const installMethod =
    installDir === '' ? 'unknown'
      : npmRoot !== '' && resolve(npmRoot, '@deepseek-ai/dsh') === resolve(installDir) ? 'npm-global'
        : installDir.includes('/pnpm/') ? 'pnpm-global'
          : installDir.includes('homebrew') ? 'npm-global' : 'other'
  return { version, binary: bin, realpath: real, installDir, npmRoot, installMethod }
}

function hostBundlesDir(installDir) {
  return installDir === '' ? '' : join(installDir, 'node_modules')
}

function backupInfo() {
  let text = ''
  try {
    text = readFileSync(BACKUP_SCRIPT, 'utf8')
  } catch {
    return { script: BACKUP_SCRIPT, exists: false, coveredTuiFiles: [], coveredProfileFiles: [], uncoveredTui: [], uncoveredProfileFiles: [], structuralGaps: [] }
  }
  const coveredTuiFiles = []
  const tuiBlock = text.match(/tui_files=\(([\s\S]*?)\)/)
  if (tuiBlock) {
    for (const token of tuiBlock[1].split(/\s+/)) {
      if (token !== '' && !token.startsWith('#')) coveredTuiFiles.push(token)
    }
  }
  const coveredProfileFiles = []
  const profileLoop = text.match(/for f in ([^;]+); do/)
  if (profileLoop) {
    for (const token of profileLoop[1].split(/\s+/)) {
      if (token !== '' && !token.startsWith('$')) coveredProfileFiles.push(token)
    }
  }
  const actualTui = listFiles(TUI_HOME)
  const noise = /(\.bak[-.]|\.lock$|^crash\.log$|^restart\.log$|^history\.jsonl$|^effect-ledger\.jsonl$)/
  const uncoveredTui = actualTui.filter(f => !coveredTuiFiles.includes(f) && !noise.test(f))
  const uncoveredNoise = actualTui.filter(f => !coveredTuiFiles.includes(f) && noise.test(f))
  const uncoveredProfileFiles = (coveredProfileFiles.length === 0 ? [] : ['package.json', 'cordis.patch.yml', 'cordis.yml', 'pnpm-lock.yaml', 'pnpm-workspace.yaml'].filter(f => !coveredProfileFiles.includes(f)))
  const coversSkills = /root\/skills|\$dsh\/skills/.test(text)
  const structuralGaps = []
  for (const p of [join(DSH_HOME, 'skills'), join(DSH_HOME, 'storages'), join(DSH_HOME, 'dsh-market')]) {
    if (!existsSync(p)) continue
    if (p === join(DSH_HOME, 'skills') && coversSkills) continue
    structuralGaps.push(p)
  }
  if (existsSync(join(DSH_HOME, '.credentials.yaml'))) structuralGaps.push(join(DSH_HOME, '.credentials.yaml') + ' (только с -s)')
  let run
  try {
    const probe = spawnSync('zsh', ['-c', `source ${JSON.stringify(BACKUP_SCRIPT)} >/dev/null 2>&1; dsh_backup -n -b /tmp/dsh-update-dryrun`], { encoding: 'utf8', timeout: 25_000 })
    run = { exit: probe.status ?? -1, ok: (probe.status ?? 1) === 0, stderr: (probe.stderr ?? '').trim().split('\n').slice(-3).join(' ') }
  } catch (error) {
    run = { exit: -1, ok: false, stderr: String(error.message).slice(0, 300) }
  }
  return {
    script: BACKUP_SCRIPT,
    exists: true,
    run,
    coveredTuiFiles: coveredTuiFiles.sort(),
    coveredProfileFiles,
    actualTuiCount: actualTui.length,
    uncoveredTui,
    uncoveredNoise,
    uncoveredProfileFiles,
    structuralGaps,
  }
}

function skillEntries(profileNames) {
  const out = []
  const roots = [{ dir: join(DSH_HOME, 'skills'), source: 'user' }]
  for (const name of profileNames) {
    const nm = join(DSH_HOME, 'profiles', name, 'node_modules')
    roots.push({ dir: nm, source: 'plugin', profile: name })
    for (const scope of listDirs(nm).filter(d => d.startsWith('@'))) {
      // scoped packages: handled below by walking one level
      void scope
    }
  }
  const seen = new Set()
  const consider = (path, source, profile) => {
    if (seen.has(path)) return
    seen.add(path)
    const info = parseSkill(path)
    let pkg = undefined
    try {
      const dir = dirname(path)
      pkg = readJson(join(dir, 'package.json'))?.name
    } catch {
      pkg = undefined
    }
    out.push({ path, source, profile, plugin: pkg, ...info })
  }
  for (const root of roots) {
    if (root.source === 'user') {
      for (const dir of listDirs(root.dir)) {
        const p = join(root.dir, dir, 'SKILL.md')
        if (existsSync(p)) consider(p, 'user')
      }
      continue
    }
    const nm = root.dir
    for (const entry of listDirs(nm)) {
      const check = (dir, label) => {
        const direct = join(dir, 'SKILL.md')
        if (existsSync(direct)) consider(direct, 'plugin', root.profile)
        const skillsDir = join(dir, 'skills')
        if (existsSync(skillsDir)) {
          for (const sub of listDirs(skillsDir)) {
            const nested = join(skillsDir, sub, 'SKILL.md')
            if (existsSync(nested)) consider(nested, 'plugin', root.profile)
          }
        }
        void label
      }
      if (entry.startsWith('@')) {
        for (const scoped of listDirs(join(nm, entry))) check(join(nm, entry, scoped), `${entry}/${scoped}`)
      } else {
        check(join(nm, entry), entry)
      }
    }
  }
  return out
}

function resolveBundles(profile, bundles, installDir) {
  const nm = join(DSH_HOME, 'profiles', profile, 'node_modules')
  const hostNm = hostBundlesDir(installDir)
  const result = {}
  for (const bundle of bundles) {
    const inProfile = join(nm, bundle, 'package.json')
    const inHost = hostNm === '' ? '' : join(hostNm, bundle, 'package.json')
    if (existsSync(inProfile)) result[bundle] = { ok: true, where: 'profile' }
    else if (inHost !== '' && existsSync(inHost)) result[bundle] = { ok: true, where: 'host' }
    else result[bundle] = { ok: false, where: 'missing' }
  }
  return result
}

function profileInfo(name, installDir, withDumps) {
  const dir = join(DSH_HOME, 'profiles', name)
  const pkg = readJson(join(dir, 'package.json')) ?? {}
  const bundles = pkg?.dsh?.profile?.bundles ?? []
  const deps = { ...(pkg.dependencies ?? {}), ...(pkg.devDependencies ?? {}) }
  const lock = existsSync(join(dir, 'pnpm-lock.yaml')) ? parseLock(join(dir, 'pnpm-lock.yaml')) : {}
  const resolved = {}
  for (const [dep, spec] of Object.entries(deps)) {
    const installedPkg = readJson(join(dir, 'node_modules', dep, 'package.json'))
    const lockEntry = lock[dep] ?? {}
    const installed = installedPkg?.version ?? ''
    let status = 'ok'
    const lockVersion = lockEntry.version === undefined ? undefined : String(lockEntry.version)
    if (installed === '') status = 'missing'
    else if (lockVersion === undefined) status = 'unlocked'
    else if (!/^\d+\.\d+\.\d+/.test(lockVersion)) status = 'ok'
    else if (lockVersion !== installed) status = 'drift'
    resolved[dep] = {
      spec,
      kind: spec.startsWith('file:') ? 'file' : /^(\^|~|>=|<=|>|<|=)?\s*v?\d+\.\d+\.\d+|^latest$|^\*$|^x$/.test(spec.trim()) ? 'registry' : 'url',
      installed,
      lockSpecifier: lockEntry.specifier,
      lockVersion: lockEntry.version,
      status,
      name: installedPkg?.name ?? dep,
    }
  }
  const tuiPkgPath = join(dir, 'node_modules/@deepseek-harness-tui/dsh-tui/package.json')
  const tuiPkg = readJson(tuiPkgPath)
  const peerCore = tuiPkg?.peerDependencies?.['@deepseek-ai/dsh-agent'] ?? undefined
  const result = {
    dir,
    bundles,
    bundleResolution: resolveBundles(name, bundles, installDir),
    deps: resolved,
    tui: tuiPkg === undefined ? undefined : { version: tuiPkg.version, peerCore },
    dump: undefined,
  }
  if (withDumps) {
    const run = spawnSync('dsh', ['--profile', name, '--dump-config'], { encoding: 'utf8', timeout: DUMPS_TIMEOUT, maxBuffer: 32 * 1024 * 1024 })
    const stderr = run.stderr ?? ''
    const lines = stderr.split(/\r?\n/).filter(l => /warning|failed|not found|error/i.test(l))
    const entries = ((run.stdout ?? '').match(/^- id:/gm) ?? []).length
    result.dump = { exit: run.status ?? -1, entries, warnings: lines.slice(0, 40) }
  }
  return result
}

export function collect(options = {}) {
  const withDumps = options.dumps === true
  const names = listDirs(join(DSH_HOME, 'profiles'))
  const core = coreInfo()
  const profiles = {}
  for (const name of names) profiles[name] = profileInfo(name, core.installDir, withDumps)
  const skills = skillEntries(names)
  const tuiStateFiles = listFiles(TUI_HOME).map(name => {
    let size = 0
    try {
      size = statSync(join(TUI_HOME, name)).size
    } catch {
      size = 0
    }
    return { name, size }
  })
  const backup = backupInfo()
  const result = {
    format: 'dsh-update-collect/1',
    generatedAt: new Date().toISOString(),
    host: execFileSync('hostname', { encoding: 'utf8' }).trim(),
    user: process.env.USER ?? '',
    env: {
      dshHome: DSH_HOME,
      tuiHome: TUI_HOME,
      backupScript: BACKUP_SCRIPT,
      stateDir: process.env.DSH_UPDATE_STATE ?? join(DSH_HOME, 'updates'),
      node: process.version,
      npm: tryVersion('npm'),
      pnpm: tryVersion('pnpm'),
      apiKeyInEnv: (process.env.DEEPSEEK_API_KEY ?? '') !== '',
    },
    core,
    profiles,
    skills,
    tuiState: { present: existsSync(TUI_HOME), files: tuiStateFiles },
    backup,
  }
  return result
}

function tryVersion(bin) {
  try {
    return execFileSync(bin, ['--version'], { encoding: 'utf8', timeout: 20_000 }).trim().split('\n')[0]
  } catch {
    return ''
  }
}

void satisfies

if (process.argv[1] !== undefined && process.argv[1].endsWith('collect.mjs')) {
  const withDumps = ARGS.includes('--dumps')
  process.stdout.write(JSON.stringify(collect({ dumps: withDumps }), null, 2) + '\n')
}
