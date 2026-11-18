#!/usr/bin/env node
/**
 * util.mjs — микро-утилиты без зависимостей для скилла /dsh-update.
 *
 *   util.mjs cmp <a> <b>                 -1 | 0 | 1
 *   util.mjs max                         максимальная версия из списка на stdin
 *   util.mjs newer <base>                версии со stdin, которые новее base
 *   util.mjs peer <range> <version>      yes | no | unknown
 *   util.mjs bundles <package.json>      JSON-массив dsh.profile.bundles
 *   util.mjs deps <package.json>         JSON {name: spec}
 *   util.mjs lock <pnpm-lock.yaml>       JSON {name: {specifier, version}}
 *   util.mjs skill <SKILL.md>            JSON {name, description, ok, problem}
 *   util.mjs pkg <package.json>          JSON {name, version}
 */
import { readFileSync } from 'node:fs'
import { pathToFileURL } from 'node:url'

export { compare, satisfies, parseLock, parseSkill, parse }

function fail(msg) {
  process.stderr.write(`util: ${msg}\n`)
  process.exit(2)
}

function parse(v) {
  const m = String(v).trim().match(/^v?(\d+)\.(\d+)\.(\d+)(?:-([0-9A-Za-z.-]+))?(?:\+.*)?$/)
  if (!m) return undefined
  return { major: +m[1], minor: +m[2], patch: +m[3], pre: m[4] === undefined ? [] : m[4].split('.') }
}

function cmpPre(a, b) {
  if (a.length === 0 && b.length === 0) return 0
  if (a.length === 0) return 1
  if (b.length === 0) return -1
  for (let i = 0; i < Math.max(a.length, b.length); i++) {
    const x = a[i]
    const y = b[i]
    if (x === undefined) return -1
    if (y === undefined) return 1
    const nx = /^\d+$/.test(x)
    const ny = /^\d+$/.test(y)
    if (nx && ny) {
      const d = Number(x) - Number(y)
      if (d !== 0) return d > 0 ? 1 : -1
    } else if (nx !== ny) {
      return nx ? -1 : 1
    } else if (x !== y) {
      return x > y ? 1 : -1
    }
  }
  return 0
}

function compare(a, b) {
  const pa = parse(a)
  const pb = parse(b)
  if (pa === undefined || pb === undefined) fail(`cannot parse version ${pa === undefined ? a : b}`)
  for (const k of ['major', 'minor', 'patch']) {
    if (pa[k] !== pb[k]) return pa[k] > pb[k] ? 1 : -1
  }
  return cmpPre(pa.pre, pb.pre)
}

function readStdin() {
  try {
    return readFileSync(0, 'utf8')
  } catch {
    return ''
  }
}

function lines(text) {
  return text
    .split(/\r?\n/)
    .map(s => s.trim())
    .filter(Boolean)
}

/** npm-range subset: exact, ^, ~, >=, >, <=, <, =, *, x. */
function satisfies(range, version) {
  const v = parse(version)
  if (v === undefined) return 'unknown'
  const alternatives = String(range).split('||').map(s => s.trim()).filter(Boolean)
  if (alternatives.length === 0) return 'unknown'
  let sawUnknown = false
  for (const alt of alternatives) {
    const r = checkOne(alt, version)
    if (r === true) return 'yes'
    if (r === 'unknown') sawUnknown = true
  }
  return sawUnknown ? 'unknown' : 'no'
}

function checkOne(alt, version) {
  const v = parse(version)
  const token = alt.trim()
  if (token === '*' || token === 'x') return true
  const m = token.match(/^(\^|~|>=|<=|>|<|=)?\s*v?(.+)$/)
  if (!m) return 'unknown'
  const op = m[1] ?? '='
  const base = parse(m[2])
  if (base === undefined) return 'unknown'
  const c = compare(version, m[2])
  switch (op) {
    case '=':
      return c === 0
    case '>':
      return c > 0
    case '>=':
      return c >= 0
    case '<':
      return c < 0
    case '<=':
      return c <= 0
    case '~': {
      const upper = { ...base, minor: base.minor + 1, patch: 0, pre: [] }
      return c >= 0 && compare(version, `${upper.major}.${upper.minor}.${upper.patch}`) < 0
    }
    case '^': {
      let upper
      if (base.major > 0) upper = `${base.major + 1}.0.0`
      else if (base.minor > 0) upper = `0.${base.minor + 1}.0`
      else upper = `0.0.${base.patch + 1}`
      return c >= 0 && compare(version, upper) < 0
    }
    default:
      return 'unknown'
  }
}

function readJson(file) {
  try {
    return JSON.parse(readFileSync(file, 'utf8'))
  } catch (error) {
    fail(`cannot read ${file}: ${error.message}`)
  }
}

/** Minimal pnpm-lock (v6/v9/v10) importer parser: only the root importer. */
function parseLock(file) {
  let text
  try {
    text = readFileSync(file, 'utf8')
  } catch {
    return {}
  }
  const out = {}
  let inImporters = false
  let importerIndent = -1
  let section = ''
  let dep = ''
  for (const raw of text.split(/\r?\n/)) {
    if (/^importers:\s*$/.test(raw)) {
      inImporters = true
      continue
    }
    if (!inImporters) continue
    if (/^\S/.test(raw) && !/^importers:/.test(raw)) break
    const indent = raw.length - raw.trimStart().length
    const line = raw.trim()
    if (!line || line.startsWith('#')) continue
    if (indent === 2 && /^\.:?$/.test(line)) {
      importerIndent = 2
      continue
    }
    if (importerIndent < 0) continue
    if (indent <= 2) {
      importerIndent = -1
      continue
    }
    if (indent === 4 && /^[A-Za-z][\w-]*:\s*$/.test(line)) {
      section = line.slice(0, -1)
      dep = ''
      continue
    }
    if (section !== 'dependencies' && section !== 'devDependencies' && section !== 'optionalDependencies') continue
    if (indent === 6 && line.endsWith(':')) {
      dep = line.slice(0, -1).replace(/^['"]|['"]$/g, '')
      out[dep] = out[dep] ?? {}
      continue
    }
    if (indent >= 8 && dep !== '') {
      const m = line.match(/^(specifier|version):\s*(.+)$/)
      if (m) out[dep][m[1]] = m[2].replace(/^['"]|['"]$/g, '').replace(/\(.*\)$/, '')
    }
  }
  return out
}

function parseSkill(file) {
  let text
  try {
    text = readFileSync(file, 'utf8')
  } catch (error) {
    return { ok: false, problem: `unreadable: ${error.message}` }
  }
  const m = text.match(/^\uFEFF?---\r?\n([\s\S]*?)\r?\n---\r?\n/)
  if (!m) return { ok: false, problem: 'no YAML frontmatter' }
  const yaml = m[1]
  const name = (yaml.match(/^name:\s*(.+)$/m) ?? [])[1]
  const description = (yaml.match(/^description:\s*(.+)$/m) ?? [])[1]
  const clean = value => (value === undefined ? undefined : value.trim().replace(/^['"]|['"]$/g, ''))
  const result = { name: clean(name), description: clean(description), ok: true, problem: '' }
  if (result.name === undefined || result.name === '') {
    result.ok = false
    result.problem = 'missing name'
  } else if (!/^[a-z0-9][a-z0-9-]*$/.test(result.name)) {
    result.ok = false
    result.problem = `name "${result.name}" is not kebab-case`
  }
  if (result.description === undefined || result.description === '') {
    result.ok = false
    result.problem = `${result.problem ? result.problem + '; ' : ''}missing description`
  }
  return result
}

function main() {
const [cmd, ...args] = process.argv.slice(2)
switch (cmd) {
  case 'cmp':
    console.log(compare(args[0], args[1]))
    break
  case 'peer':
    console.log(satisfies(args[0], args[1]))
    break
  case 'max': {
    const all = lines(readStdin())
    if (all.length === 0) fail('max: empty stdin')
    console.log(all.sort(compare).at(-1))
    break
  }
  case 'newer': {
    const base = args[0]
    const all = lines(readStdin())
    console.log(all.filter(v => parse(v) !== undefined && compare(v, base) > 0).join('\n'))
    break
  }
  case 'bundles': {
    const pkg = readJson(args[0])
    console.log(JSON.stringify(pkg?.dsh?.profile?.bundles ?? []))
    break
  }
  case 'deps': {
    const pkg = readJson(args[0])
    console.log(JSON.stringify({ ...(pkg.dependencies ?? {}), ...(pkg.devDependencies ?? {}) }))
    break
  }
  case 'lock':
    console.log(JSON.stringify(parseLock(args[0])))
    break
  case 'skill':
    console.log(JSON.stringify(parseSkill(args[0])))
    break
  case 'pkg': {
    const pkg = readJson(args[0])
    console.log(JSON.stringify({ name: pkg.name, version: pkg.version }))
    break
  }
  default:
    fail(`unknown command "${cmd}"`)
}
}

if (process.argv[1] !== undefined && import.meta.url === pathToFileURL(process.argv[1]).href) main()
