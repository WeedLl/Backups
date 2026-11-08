#!/usr/bin/env node
/**
 * check.mjs — валидатор формата заметок скилла `md-answer`.
 *
 * Проверяет только то, что можно проверить детерминированно: frontmatter,
 * заголовки, набор callouts, TL;DR, оглавление, «Источники». Смысл текста
 * не оценивает — это работа модели.
 *
 * Ноль зависимостей, Node >= 18.
 *
 * Использование:
 *   node tools/check.mjs answers/2026-11-08-x.md
 *   node tools/check.mjs --strict answers/*.md
 *   node tools/check.mjs --json answers/2026-11-08-x.md
 *
 * Коды выхода: 0 — чисто; 1 — есть ошибки (или предупреждения при --strict);
 * 2 — файл не найден или не .md.
 */

import { readFileSync, existsSync } from 'node:fs'
import { resolve, extname } from 'node:path'
import { detectVault, scanVault } from './vault-tags.mjs'

/** Разрешённый набор: ровно девять типов. */
const ALLOWED = new Set([
  'note', 'abstract', 'todo', 'tip', 'question', 'warning', 'danger', 'example', 'quote',
])

/** Запрещённые типы и причина, которую увидит модель. */
const ALIASES = new Map([
  ['success', 'в treemd делит 💡 с tip, в md-render — галочку с todo'],
  ['check', 'делит 💡 с tip в treemd'],
  ['done', 'делит 💡 с tip в treemd'],
  ['hint', 'тот же слот 💡, в md-render падает в фолбэк note + ❝'],
  ['important', 'в Obsidian отрисовывается как tip — дубль при живом tip'],
  ['caution', 'в treemd 🛑 как у danger, в Obsidian — warning'],
  ['attention', 'в treemd 🛑 как у danger, в Obsidian — warning'],
  ['failure', 'тот же 🛑, что у danger'],
  ['fail', 'тот же 🛑, что у danger'],
  ['missing', 'тот же 🛑, что у danger'],
  ['error', 'в Obsidian синоним danger'],
  ['bug', 'тот же 🛑, что у danger'],
  ['info', 'в nvim тот же глиф и цвет, что у note'],
  ['tldr', 'алиас abstract — пиши abstract'],
  ['summary', 'алиас abstract — пиши abstract'],
  ['faq', 'алиас question'],
  ['help', 'алиас question'],
  ['cite', 'алиас quote'],
])

/** Поля frontmatter, которые скилл допускает без отдельной просьбы. */
const KNOWN_KEYS = new Set(['tags', 'created', 'aliases', 'status', 'source', 'cssclasses', 'publish'])

/** Заголовки, которые не описывают тему и потому не годятся в H1. */
const WEAK_TITLES = new Set(['ответ', 'заметка', 'документ', 'инструкция', 'итог', 'выводы', 'answer', 'note'])

/** Длина, после которой TL;DR обязателен. */
const TLDR_THRESHOLD = 40
/** С какого числа разделов оглавление имеет смысл. */
const TOC_MIN_SECTIONS = 5
/** Сколько внешних ссылок требуют раздела «Источники». */
const SOURCES_THRESHOLD = 2

const CALLOUT_RE = /^(\s{0,3}(?:>\s?)+)\[!([^\]]*)\]([-+]?)(.*)$/
const QUOTE_RE = /^\s{0,3}>/
const HEADING_RE = /^\s{0,3}(#{1,6})\s+(.+?)\s*#*\s*$/
const FENCE_RE = /^\s{0,3}(?:```|~~~)/

/* ─────────────────────────── CLI ─────────────────────────── */

const argv = process.argv.slice(2)
const flags = new Set(argv.filter((a) => a.startsWith('-')))
const files = argv.filter((a) => !a.startsWith('-'))
const strict = flags.has('--strict')
const asJson = flags.has('--json')
const deepLinks = flags.has('--links')
const useVocab = !flags.has('--no-vocab')
const allowArg = argv.find((a) => a.startsWith('--allow='))?.slice('--allow='.length) ?? null

// Пользовательский формат может разрешать свои типы: расширяем набор на один запуск.
if (allowArg) {
  for (const t of allowArg.split(',')) {
    const type = t.trim().toLowerCase()
    if (type) ALLOWED.add(type)
  }
}

const HELP = `
check.mjs — валидатор формата заметок скилла md-answer

  node tools/check.mjs <file.md> [...]   проверить файл (можно несколько)

Флаги:
  --strict      предупреждения считать ошибками
  --json        машиночитаемый вывод (для скриптов)
  --links       проверить живость внешних ссылок (нужна сеть, медленно)
  --no-vocab    не сверять теги с хранилищем (по умолчанию — живой пересъём)
  --allow=a,b   разрешить дополнительные типы колаутов (свой формат пользователя)
  --help        эта справка

Коды выхода: 0 — чисто, 1 — ошибки (или предупреждения при --strict),
             2 — нет аргументов / файл не найден / не .md.

Что проверяется: frontmatter (tags, created, ai/by_ai), один H1, только
разрешённые callouts, пустые и глубоко вложенные блоки, TL;DR в длинном
файле, ссылки в оглавлении, раздел «Источники» при 2+ ссылках.
Теги сверяются с живым хранилищем Obsidian при каждом запуске (≈0,15 с).
`.trim()

if (flags.has('--help') || files.length === 0) {
  console.log(HELP)
  process.exit(files.length === 0 && !flags.has('--help') ? 2 : 0)
}

/**
 * Теги хранилища пересчитываются на каждом запуске — кэша нет.
 * Если хранилище не нашлось, проверка тегов невозможна: это отдельное
 * предупреждение `vocab-unavailable`, а не тихий пропуск.
 */
let VOCAB = null
let VOCAB_ERROR = null
if (useVocab) {
  const vault = detectVault()
  if (vault.path) {
    try {
      const scan = scanVault(vault.path)
      if (scan.files === 0) {
        VOCAB_ERROR = `в хранилище ${vault.path} нет заметок`
      } else {
        VOCAB = new Set(scan.tags.map(([t]) => t.toLowerCase()))
      }
    } catch (error) {
      VOCAB_ERROR = error.message
    }
  } else {
    VOCAB_ERROR = vault.error === 'multiple-open'
      ? 'открыто несколько хранилищ, непонятно какое брать'
      : vault.error === 'missing'
        ? `путь из $OBSIDIAN_VAULT не существует: ${vault.candidates?.[0]?.path ?? '?'}`
        : 'хранилище Obsidian не найдено'
  }
}

/* ──────────────────────── разбор файла ───────────────────── */

/**
 * @param {string} file Абсолютный путь.
 * @returns {{findings: Array<{line:number,level:'error'|'warn',code:string,message:string}>}}
 */
function checkFile(file) {
  const findings = []
  const add = (line, level, code, message) => findings.push({ line, level, code, message })

  const raw = readFileSync(file, 'utf8')
  const src = raw.replace(/^\uFEFF/, '').replace(/\r\n/g, '\n')
  const lines = src.split('\n')

  /* ── frontmatter ── */
  let bodyStart = 0
  let fmLines = null
  if (lines[0] !== '---') {
    add(1, 'error', 'fm-missing', 'нет YAML-frontmatter: файл должен начинаться с ---')
  } else {
    const close = lines.indexOf('---', 1)
    if (close === -1) {
      add(1, 'error', 'fm-unclosed', 'frontmatter не закрыт вторым ---')
    } else {
      fmLines = lines.slice(1, close)
      bodyStart = close + 1

      const tags = readTags(fmLines)
      if (tags === null) {
        add(1, 'error', 'fm-tags', 'в frontmatter нет поля tags')
      } else if (tags.length === 0) {
        add(1, 'error', 'fm-tags-empty', 'tags есть, но пустой: нужен список из 2–4 тегов')
      } else {
        if (tags.length > 6) add(1, 'warn', 'fm-tags-many', `тегов ${tags.length} — обычно хватает 2–4`)
        const seen = new Set()
        for (const tag of tags) {
          if (/\s/.test(tag)) add(1, 'warn', 'fm-tag-space', `тег «${tag}» содержит пробел: в Obsidian так нельзя, используй дефис`)
          if (seen.has(tag.toLowerCase())) add(1, 'warn', 'fm-tag-dup', `тег «${tag}» повторяется`)
          seen.add(tag.toLowerCase())
        }
        if (!seen.has('ai/by_ai')) {
          add(1, 'error', 'fm-ai-tag', 'нет обязательного тега ai/by_ai — он помечает, что заметку написал агент')
        }
        if (VOCAB) {
          for (const tag of tags) {
            const low = tag.toLowerCase()
            if (low === 'ai/by_ai') continue
            if (!VOCAB.has(low)) {
              add(1, 'warn', 'fm-tag-unknown', `тег «${tag}» не встречается в хранилище — либо опечатка, либо новый тег (тогда предложи его явно)`)
            }
          }
        }
      }

      const created = readScalar(fmLines, 'created')
      if (created === null) {
        add(1, 'error', 'fm-created', 'в frontmatter нет поля created')
      } else if (!/^\d{4}-\d{2}-\d{2}$/.test(created)) {
        add(1, 'error', 'fm-created-format', `created = «${created}», нужен формат YYYY-MM-DD`)
      } else if (Number.isNaN(Date.parse(created))) {
        add(1, 'error', 'fm-created-invalid', `created = «${created}» — такой даты нет`)
      }

      for (const key of readKeys(fmLines)) {
        if (!KNOWN_KEYS.has(key)) add(1, 'warn', 'fm-extra-key', `поле «${key}» не из набора скилла — добавляй только по просьбе`)
      }

      if (useVocab && !VOCAB) {
        add(1, 'warn', 'vocab-unavailable', `теги не с чем сверять: ${VOCAB_ERROR}. Спроси путь к хранилищу или запусти с --no-vocab`)
      }
    }
  }

  /* ── проход по строкам: код-фенсы, заголовки, колауты ── */
  const headings = []
  let inFence = false
  let h1Count = 0
  let prevLevel = 0
  const callouts = []

  for (let i = bodyStart; i < lines.length; i++) {
    const line = lines[i]

    if (FENCE_RE.test(line)) {
      inFence = !inFence
      continue
    }
    if (inFence) continue

    const heading = line.match(HEADING_RE)
    if (heading) {
      const level = heading[1].length
      const text = heading[2].trim()
      headings.push({ level, text, line: i + 1 })
      if (level === 1) {
        h1Count++
        if (WEAK_TITLES.has(text.toLowerCase().replace(/[.:!?]+$/, ''))) {
          add(i + 1, 'warn', 'h1-weak', `H1 «${text}» ничего не говорит о теме`)
        }
      }
      if (prevLevel && level > prevLevel + 1) {
        add(i + 1, 'warn', 'heading-jump', `прыжок с H${prevLevel} на H${level}`)
      }
      prevLevel = level
      if (/[\u{1F300}-\u{1FAFF}\u{2600}-\u{27BF}]/u.test(text)) {
        add(i + 1, 'warn', 'heading-emoji', 'эмодзи в заголовке — убери')
      }
      continue
    }

    const callout = line.match(CALLOUT_RE)
    if (callout) {
      const depth = (callout[1].match(/>/g) || []).length
      const rawType = callout[2].trim()
      const type = rawType.toLowerCase()
      const mark = callout[3]

      callouts.push({ type, line: i + 1 })

      if (depth > 2) {
        add(i + 1, 'error', 'callout-depth', `вложенность ${depth} — глубже двух уровней ломается вид в treemd`)
      }
      if (rawType !== type) {
        add(i + 1, 'warn', 'callout-case', `тип «${rawType}» — пиши строчными: [!${type}]`)
      }
      if (mark) {
        add(i + 1, 'error', 'callout-fold', `«${mark}» после ] ломает fold: treemd съедает маркер, render-markdown тащит дефис в заголовок`)
      }
      if (!ALLOWED.has(type)) {
        const reason = ALIASES.get(type) || 'кастомные типы не поддерживаются: в treemd получат нейтральный ❯, в render-markdown не станут колаутом'
        add(i + 1, 'error', 'callout-type', `[!${rawType}] запрещён — ${reason}; разрешены: ${[...ALLOWED].join(', ')}`)
      }

      // пустое тело: до первой непустой строки без >
      let body = ''
      for (let j = i + 1; j < lines.length && QUOTE_RE.test(lines[j]); j++) {
        body += lines[j].replace(QUOTE_RE, '').trim() + '\n'
      }
      const meaningful = body.replace(/\[![^\]]*\][^\n]*/g, '').replace(/\s+/g, '')
      if (!meaningful) add(i + 1, 'error', 'callout-empty', `[!${type}] без текста — это не блок, а мусор`)
    }
  }

  /* ── H1 ── */
  const bodyLines = lines.slice(bodyStart).filter((l) => l.trim() !== '').length
  if (h1Count === 0) add(bodyStart + 1, 'error', 'h1-missing', 'нет H1: первый заголовок файла должен быть # Тема')
  if (h1Count > 1) add(bodyStart + 1, 'error', 'h1-multiple', `H1 должен быть один, найдено: ${h1Count}`)
  if (headings.length && headings[0].level !== 1) {
    add(headings[0].line, 'error', 'h1-not-first', 'первый заголовок в файле — не H1')
  }

  /* ── TL;DR ── */
  const abstracts = callouts.filter((c) => c.type === 'abstract')
  if (bodyLines >= TLDR_THRESHOLD && abstracts.length === 0) {
    add(bodyStart + 1, 'error', 'tldr-missing', `файл на ${bodyLines} строк — нужен [!abstract] TL;DR сразу после H1`)
  }
  if (abstracts.length > 1) {
    add(abstracts[1].line, 'warn', 'tldr-duplicate', 'второй abstract: TL;DR должен быть один')
  }
  if (abstracts.length === 1 && callouts.length && callouts[0].type !== 'abstract') {
    add(abstracts[0].line, 'warn', 'tldr-not-first', `первый колаут — [!${callouts[0].type}], а TL;DR ожидается первым`)
  }
  const firstSection = headings.find((h) => h.level === 2)
  if (abstracts.length === 1 && firstSection && abstracts[0].line > firstSection.line) {
    add(abstracts[0].line, 'warn', 'tldr-late', 'TL;DR стоит после первого раздела — подними его сразу под H1')
  }

  /* ── ссылки и «Источники» ── */
  const hasSourcesHeading = headings.some((h) => /^(источники|sources)$/i.test(h.text))
  const links = collectExternalLinks(lines, bodyStart)
  const linkCount = links.length
  if (linkCount >= SOURCES_THRESHOLD && !hasSourcesHeading) {
    add(bodyStart + 1, 'error', 'sources-missing', `внешних ссылок ${linkCount}, а раздела «Источники» нет`)
  }
  if (hasSourcesHeading && linkCount === 0) {
    add(bodyStart + 1, 'warn', 'sources-empty', 'раздел «Источники» есть, а внешних ссылок в тексте нет')
  }

  /* ── оглавление ── */
  const toc = headings.find((h) => h.level === 2 && /^(содержание|оглавление|contents)$/i.test(h.text))
  const sections = headings.filter((h) => h.level === 2 && h !== toc)
  if (toc) {
    if (sections.length < 3) add(toc.line, 'warn', 'toc-unneeded', 'оглавление при менее чем трёх разделах — лишний шум')
    checkTocLinks(lines, toc, headings, add)
  } else if (sections.length >= TOC_MIN_SECTIONS) {
    add(bodyStart + 1, 'warn', 'toc-missing', `разделов ${sections.length} — стоит добавить «## Содержание» со ссылками [[#Раздел]]`)
  }

  return { findings, bodyLines, links }
}

/* ───────────────────────── парсеры ───────────────────────── */

/** Список тегов из строк frontmatter или null, если поля нет. */
function readTags(fmLines) {
  for (let i = 0; i < fmLines.length; i++) {
    const m = fmLines[i].match(/^tags:\s*(.*)$/)
    if (!m) continue
    const inline = m[1].trim()
    if (inline === '') {
      const out = []
      for (let j = i + 1; j < fmLines.length; j++) {
        const item = fmLines[j].match(/^\s+-\s+(.+)$/)
        if (item) out.push(item[1].trim().replace(/^["']|["']$/g, ''))
        else if (fmLines[j].trim() === '') continue
        else break
      }
      return out
    }
    if (inline.startsWith('[')) {
      const inner = inline.replace(/^\[/, '').replace(/\]$/, '').trim()
      if (!inner) return []
      return inner.split(',').map((s) => s.trim().replace(/^["']|["']$/g, '')).filter(Boolean)
    }
    return [inline.replace(/^["']|["']$/g, '')]
  }
  return null
}

/** Скалярное поле frontmatter или null. */
function readScalar(fmLines, key) {
  for (const line of fmLines) {
    const m = line.match(new RegExp(`^${key}:\\s*(.*)$`))
    if (m) return m[1].trim().replace(/^["']|["']$/g, '')
  }
  return null
}

/** Все верхнеуровневые ключи frontmatter. */
function readKeys(fmLines) {
  const keys = []
  for (const line of fmLines) {
    const m = line.match(/^([A-Za-z0-9_-]+):/)
    if (m) keys.push(m[1])
  }
  return keys
}

/** Внешние ссылки вне кода и frontmatter: [{url, line}]. */
function collectExternalLinks(lines, bodyStart) {
  let inFence = false
  const out = []
  for (let i = bodyStart; i < lines.length; i++) {
    const line = lines[i]
    if (FENCE_RE.test(line)) {
      inFence = !inFence
      continue
    }
    if (inFence) continue
    const matches = line.match(/https?:\/\/[^\s)>\]"']+/g)
    if (matches) for (const url of matches) out.push({ url: url.replace(/[.,;:]+$/, ''), line: i + 1 })
  }
  return out
}

/* ─────────────────── живость ссылок (--links) ─────────────────── */

/** Проверить один URL: 'ok' | 'dead' | 'blocked' | 'unreachable'. */
async function probe(url) {
  const opts = {
    method: 'HEAD',
    redirect: 'follow',
    signal: AbortSignal.timeout(8000),
    headers: { 'user-agent': 'md-answer-check/1.0 (+dsh skill)' },
  }
  try {
    let res = await fetch(url, opts)
    // Многие сайты не отдают HEAD: пробуем GET с Range, не выкачивая тело.
    if (res.status === 405 || res.status === 501) {
      res = await fetch(url, { ...opts, method: 'GET', headers: { ...opts.headers, range: 'bytes=0-0' } })
    }
    if (res.status === 404 || res.status === 410) return 'dead'
    if (res.status === 403 || res.status === 429) return 'blocked'
    if (res.status >= 400) return 'blocked'
    return 'ok'
  } catch {
    return 'unreachable'
  }
}

/** Проверить все уникальные ссылки файла, по 4 параллельно. */
async function verifyLinks(links) {
  const out = []
  const queue = [...new Map(links.map((l) => [l.url, l])).values()]
  let next = 0

  async function worker() {
    while (next < queue.length) {
      const link = queue[next++]
      const verdict = await probe(link.url)
      if (verdict === 'ok') continue
      if (verdict === 'dead') {
        out.push({ line: link.line, level: 'error', code: 'link-dead', message: `ссылка мертва (404/410): ${link.url}` })
      } else {
        const why = verdict === 'blocked' ? 'сайт закрыт для роботов' : 'нет ответа/нет сети'
        out.push({ line: link.line, level: 'warn', code: 'link-unverified', message: `не проверить: ${why} — ${link.url}` })
      }
    }
  }

  await Promise.all(Array.from({ length: Math.min(4, queue.length) }, worker))
  return out
}

/** Ссылки внутри блока «Содержание» должны вести на существующие заголовки. */
function checkTocLinks(lines, toc, headings, add) {
  const texts = new Map(headings.map((h) => [normalizeHeading(h.text), h.line]))
  const seen = new Set()

  for (let i = toc.line; i < lines.length; i++) {
    const line = lines[i]
    if (i > toc.line - 1 && HEADING_RE.test(line)) break

    for (const m of line.matchAll(/\[\[#([^\]|]+)(?:\|[^\]]*)?\]\]/g)) {
      const target = m[1].trim()
      if (!texts.has(normalizeHeading(target)) && !texts.has(normalizeAnchor(target))) {
        add(i + 1, 'warn', 'toc-unresolved', `ссылка [[#${target}]] не находит заголовок`)
      }
      seen.add(target)
    }
    for (const m of line.matchAll(/\[[^\]]*\]\(#([^)]+)\)/g)) {
      const target = decodeURIComponent(m[1])
      if (!texts.has(normalizeAnchor(target)) && ![...texts.keys()].some((k) => k === normalizeHeading(target))) {
        add(i + 1, 'warn', 'toc-unresolved', `якорь «#${target}» не находит заголовок`)
      }
      seen.add(target)
    }
  }

  if (seen.size === 0) add(toc.line, 'warn', 'toc-empty', 'блок «Содержание» без ссылок [[#Раздел]]')
}

/** Заголовок → сравнимая форма. */
function normalizeHeading(text) {
  return text.toLowerCase().replace(/[*_`]/g, '').replace(/\s+/g, ' ').trim()
}

/** Якорь Obsidian/GitHub → сравнимая форма (без пунктуации, пробелы в дефисы). */
function normalizeAnchor(text) {
  return text
    .toLowerCase()
    .replace(/[*_`]/g, '')
    .replace(/[^\p{L}\p{N}\s-]/gu, '')
    .replace(/\s+/g, '-')
    .replace(/-+/g, '-')
    .trim()
}

/* ────────────────────────── вывод ────────────────────────── */

const plural = (n, one, few, many) => {
  const n10 = n % 10
  const n100 = n % 100
  if (n10 === 1 && n100 !== 11) return one
  if (n10 >= 2 && n10 <= 4 && (n100 < 12 || n100 > 14)) return few
  return many
}

let failed = false
const report = []

for (const file of files) {
  if (!existsSync(file)) {
    console.error(`check: файл не найден — ${file}`)
    process.exitCode = 2
    continue
  }
  if (extname(file) !== '.md') {
    console.error(`check: не .md — ${file}`)
    process.exitCode = 2
    continue
  }

  const { findings, links } = checkFile(file)

  if (deepLinks && links.length) {
    const linkFindings = await verifyLinks(links)
    findings.push(...linkFindings)
  }

  findings.sort((a, b) => a.line - b.line || a.code.localeCompare(b.code))

  const errors = findings.filter((f) => f.level === 'error')
  const warns = findings.filter((f) => f.level === 'warn')
  const ok = errors.length === 0 && (!strict || warns.length === 0)
  if (!ok) failed = true

  report.push({ file, ok, errors: errors.length, warnings: warns.length, findings })

  if (asJson) continue

  const shown = resolve(file)
  console.log(`\n${shown}`)
  if (findings.length === 0) {
    console.log('  OK — формат соблюдён')
    continue
  }
  for (const f of findings) {
    const tag = f.level === 'error' ? 'ERROR' : 'WARN '
    console.log(`  ${tag} строка ${String(f.line).padStart(3)}  ${f.code.padEnd(18)} ${f.message}`)
  }
  const parts = []
  if (errors.length) parts.push(`${errors.length} ${plural(errors.length, 'ошибка', 'ошибки', 'ошибок')}`)
  if (warns.length) parts.push(`${warns.length} ${plural(warns.length, 'предупреждение', 'предупреждения', 'предупреждений')}`)
  console.log(`  итог: ${parts.join(' · ')}${strict && warns.length && !errors.length ? ' (--strict)' : ''}`)
}

if (asJson) {
  console.log(JSON.stringify(report.length === 1 ? report[0] : report, null, 2))
}

if (failed) process.exitCode = 1
else if (process.exitCode === undefined) process.exitCode = 0
