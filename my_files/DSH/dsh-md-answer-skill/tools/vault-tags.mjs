/**
 * vault-tags.mjs — поиск хранилища Obsidian и перепись его тегов.
 *
 * Общий модуль для `tags.mjs` (CLI) и `check.mjs` (валидатор). Валидатор
 * вызывает его на каждом запуске, поэтому кэша здесь нет вообще: список
 * тегов всегда соответствует тому, что лежит в хранилище прямо сейчас.
 *
 * Читается только YAML-frontmatter (первые ~80 строк заметки) и, отдельно,
 * инлайновые `#теги` в теле. Полные тексты никогда не покидают функцию.
 *
 * Ноль зависимостей, Node >= 18.
 */

import { readdirSync, readFileSync, existsSync, statSync } from 'node:fs'
import { join, resolve } from 'node:path'
import { homedir, platform } from 'node:os'

/** Реестр Obsidian: путь зависит от ОС. */
export function registryPath() {
  if (platform() === 'darwin') return join(homedir(), 'Library/Application Support/obsidian/obsidian.json')
  if (platform() === 'win32') return join(process.env.APPDATA ?? homedir(), 'obsidian/obsidian.json')
  return join(homedir(), '.config/obsidian/obsidian.json')
}

/** @returns {Array<{path:string, ts:number, open:boolean}>} */
export function readVaultRegistry() {
  const file = registryPath()
  if (!existsSync(file)) return []
  try {
    const data = JSON.parse(readFileSync(file, 'utf8'))
    return Object.values(data.vaults ?? {}).map((v) => ({
      path: v.path,
      ts: Number(v.ts ?? 0),
      open: v.open === true,
    }))
  } catch {
    return []
  }
}

/**
 * Выбрать хранилище.
 *
 * Порядок: явный аргумент → $OBSIDIAN_VAULT → активное в реестре → единственное
 * → самое свежее (с пометкой `ambiguous`). Если неоднозначно и нет активного —
 * вызывающий обязан спросить пользователя, а не гадать.
 *
 * @param {string} [explicitPath]
 * @returns {{path:string, source:string, ambiguous?:boolean} | {error:'registry-empty'|'multiple-open'|'missing', candidates:Array}}
 */
export function detectVault(explicitPath) {
  if (explicitPath) {
    const path = resolve(explicitPath)
    return existsSync(path) ? { path, source: 'аргумент' } : { error: 'missing', candidates: [{ path }] }
  }
  if (process.env.OBSIDIAN_VAULT) {
    const path = resolve(process.env.OBSIDIAN_VAULT)
    return existsSync(path) ? { path, source: 'OBSIDIAN_VAULT' } : { error: 'missing', candidates: [{ path }] }
  }

  const vaults = readVaultRegistry().filter((v) => existsSync(v.path))
  if (vaults.length === 0) return { error: 'registry-empty', candidates: [] }

  const open = vaults.filter((v) => v.open)
  if (open.length === 1) return { path: open[0].path, source: 'активное хранилище Obsidian' }
  if (open.length > 1) return { error: 'multiple-open', candidates: open }
  if (vaults.length === 1) return { path: vaults[0].path, source: 'единственное в реестре' }

  const latest = [...vaults].sort((a, b) => b.ts - a.ts)[0]
  return { path: latest.path, source: 'самое свежее в реестре', ambiguous: true }
}

/**
 * Перепись тегов хранилища.
 *
 * @param {string} root Путь к хранилищу.
 * @returns {{root:string, files:number, tagged:number, tags:Array<[string,number]>}}
 */
export function scanVault(root) {
  const counts = new Map()
  let files = 0
  let tagged = 0

  const bump = (tag) => {
    const t = String(tag).trim().replace(/^#/, '').replace(/\/+$/, '')
    if (!t) return false
    counts.set(t, (counts.get(t) ?? 0) + 1)
    return true
  }

  const scanFile = (file) => {
    files++
    let text
    try {
      text = readFileSync(file, 'utf8')
    } catch {
      return
    }
    const lines = text.replace(/^\uFEFF/, '').replace(/\r\n/g, '\n').split('\n')

    let fmEnd = 0
    let hasTags = false
    if (lines[0] === '---') {
      const close = lines.indexOf('---', 1)
      if (close > 0) {
        fmEnd = close
        let inTags = false
        for (let i = 1; i < close; i++) {
          const line = lines[i]
          const key = line.match(/^tags?:\s*(.*)$/)
          if (key) {
            inTags = true
            const inline = key[1].trim()
            if (inline.startsWith('[')) {
              for (const t of inline.replace(/^\[|\]$/g, '').split(',')) {
                if (t.trim() && bump(t)) hasTags = true
              }
              inTags = false
            } else if (inline) {
              if (bump(inline)) hasTags = true
              inTags = false
            }
            continue
          }
          if (inTags) {
            const item = line.match(/^\s*-\s*(.+)$/)
            if (item) {
              if (bump(item[1].replace(/^["']|["']$/g, ''))) hasTags = true
              continue
            }
            if (line.trim() === '') continue
            inTags = false
          }
        }
      }
    }

    let inFence = false
    for (let i = fmEnd + 1; i < lines.length; i++) {
      const line = lines[i]
      if (/^\s*(```|~~~)/.test(line)) {
        inFence = !inFence
        continue
      }
      if (inFence || /^\s*#{1,6}\s/.test(line)) continue
      for (const m of line.matchAll(/(^|\s)#([\p{L}\p{N}_/-]+)/gu)) {
        const t = m[2]
        if (!/[\p{L}_]/u.test(t)) continue
        if (bump(t)) hasTags = true
      }
    }
    if (hasTags) tagged++
  }

  const walk = (dir) => {
    let entries
    try {
      entries = readdirSync(dir, { withFileTypes: true })
    } catch {
      return
    }
    for (const e of entries) {
      if (e.name.startsWith('.')) continue
      const p = join(dir, e.name)
      if (e.isDirectory()) walk(p)
      else if (e.name.endsWith('.md')) scanFile(p)
    }
  }

  walk(root)

  const tags = [...counts].sort((a, b) => b[1] - a[1] || a[0].localeCompare(b[0]))
  return { root, files, tagged, tags }
}

/** Компактная строка для контекста модели: путь, счётчики, список тегов. */
export function formatBrief(vault, scan) {
  return `${vault.path} | ${scan.files} заметок | ${scan.tags.length} тегов: ${scan.tags.map(([t]) => t).join(', ')}`
}
