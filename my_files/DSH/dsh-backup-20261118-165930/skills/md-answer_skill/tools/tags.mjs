#!/usr/bin/env node
/**
 * tags.mjs — показать актуальные теги хранилища Obsidian.
 *
 * Тонкая обёртка над `vault-tags.mjs`: сама ничего не кэширует. Валидатор
 * (`check.mjs`) делает ту же перепись сам, поэтому кэш-файл больше не нужен;
 * `--out` остаётся для случая, когда снимок хочется сохранить руками.
 *
 * Использование:
 *   node tools/tags.mjs                  # топ-20 тегов
 *   node tools/tags.mjs --brief          # одна строка: все теги (для подбора)
 *   node tools/tags.mjs --candidates     # список хранилищ из реестра Obsidian
 *   node tools/tags.mjs /path/to/vault   # явное хранилище
 *   node tools/tags.mjs --out snapshot.json
 */

import { writeFileSync, mkdirSync } from 'node:fs'
import { dirname, resolve } from 'node:path'
import { detectVault, readVaultRegistry, scanVault, formatBrief } from './vault-tags.mjs'
import { existsSync } from 'node:fs'

const argv = process.argv.slice(2)
const flags = new Set(argv.filter((a) => a.startsWith('-')))
const positional = collectPositional()
const topN = Number(readArg('--top') ?? 20)
const outFile = readArg('--out')

function collectPositional() {
  const takesValue = new Set(['--out', '--top'])
  const out = []
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i]
    if (takesValue.has(a)) {
      i++
      continue
    }
    if (a.startsWith('-')) continue
    out.push(a)
  }
  return out
}

function readArg(name) {
  const exact = argv.find((a) => a.startsWith(`${name}=`))
  if (exact) return exact.slice(name.length + 1)
  const i = argv.indexOf(name)
  if (i !== -1 && argv[i + 1] && !argv[i + 1].startsWith('-')) return argv[i + 1]
  return null
}

if (flags.has('--help')) {
  console.log(`tags.mjs — теги хранилища Obsidian, всегда свежие

  node tools/tags.mjs [хранилище]        топ тегов
  --brief                                одна строка со всеми тегами
  --candidates                           какие хранилища видит Obsidian
  --top N                                сколько показать (по умолчанию 20)
  --out FILE                             сохранить снимок в JSON
  --quiet                                без вывода плана

Хранилище: аргумент → $OBSIDIAN_VAULT → активное в реестре Obsidian →
единственное → самое свежее. Если непонятно какое — код 2 и список.`)
  process.exit(0)
}

if (flags.has('--candidates')) {
  const vaults = readVaultRegistry()
  if (vaults.length === 0) console.log('реестр Obsidian пуст или не найден')
  for (const v of vaults.sort((a, b) => b.ts - a.ts)) {
    const when = v.ts ? new Date(v.ts).toISOString().slice(0, 10) : '—'
    console.log(`${v.open ? '*' : ' '} ${v.path}  (${when})${existsSync(v.path) ? '' : '  [нет на диске]'}`)
  }
  process.exit(0)
}

const vault = detectVault(positional[0])

if (vault.error) {
  console.error(`tags: не удалось выбрать хранилище (${vault.error}).`)
  for (const v of vault.candidates ?? []) console.error(`  ${v.path}`)
  console.error('tags: передай путь аргументом или через $OBSIDIAN_VAULT.')
  process.exit(2)
}

if (vault.ambiguous) {
  console.error(`tags: активного хранилища нет, беру свежее: ${vault.path}`)
  console.error('tags: если нужно другое — передай путь аргументом или $OBSIDIAN_VAULT.')
}

const scan = scanVault(vault.path)

if (scan.files === 0) {
  console.error(`tags: в «${vault.path}» нет ни одной .md-заметки — это не похоже на хранилище.`)
  process.exit(2)
}

if (outFile) {
  const target = resolve(outFile)
  mkdirSync(dirname(target), { recursive: true })
  writeFileSync(target, JSON.stringify({
    vault: vault.path,
    scannedAt: new Date().toISOString(),
    files: scan.files,
    unique: scan.tags.length,
    tags: Object.fromEntries(scan.tags),
  }, null, 2) + '\n')
  console.log(`снимок: ${target}`)
}

if (flags.has('--brief')) {
  console.log(formatBrief(vault, scan))
  process.exit(0)
}

if (!flags.has('--quiet')) {
  console.log(`хранилище: ${vault.path}  (${vault.source})`)
  console.log(`заметок: ${scan.files}, с тегами: ${scan.tagged}, уникальных тегов: ${scan.tags.length}`)
  if (topN > 0) {
    console.log(`топ-${Math.min(topN, scan.tags.length)}:`)
    for (const [tag, n] of scan.tags.slice(0, topN)) console.log(`  ${String(n).padStart(4)}  ${tag}`)
  }
}
