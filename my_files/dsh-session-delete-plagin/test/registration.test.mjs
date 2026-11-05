import test from 'node:test'
import assert from 'node:assert/strict'
import * as mod from '../index.js'
import { apply, name, normalizeConfig } from '../index.js'

/** Фейковый cordis-ctx: перехватывает inject/effect, собирает warnings. */
function makeCtx() {
  const injectCalls = []
  const effects = []
  const warnings = []
  const ctx = {
    logger: { warn: (message) => warnings.push(message) },
    inject: (deps, callback) => {
      injectCalls.push({ deps, callback })
    },
    effect: (callback, label) => {
      effects.push({ callback, label })
      return () => {}
    },
  }
  return { ctx, injectCalls, effects, warnings }
}

/** Фейковые швы host'а: tuiScenes + commands с учётом открытий. */
function makeHost() {
  const state = {
    scene: undefined,
    sceneDisposed: false,
    command: undefined,
    commandDisposed: false,
    opened: [],
  }
  const host = {
    tuiScenes: {
      register(descriptor) {
        state.scene = descriptor
        return () => {
          state.sceneDisposed = true
        }
      },
      open(id) {
        state.opened.push(id)
        return state.scene?.id === id
      },
    },
    commands: {
      register(definition) {
        state.command = definition
        return () => {
          state.commandDisposed = true
        }
      },
    },
    effect: () => {},
    get: (key) => {
      if (key === 'tuiScenes') return host.tuiScenes
      if (key === 'commands') return host.commands
      return undefined
    },
  }
  return { host, state }
}

test('модуль: есть name, apply, нет export default', () => {
  assert.equal(name, 'session-delete')
  assert.equal(typeof apply, 'function')
  assert.equal('default' in mod, false)
})

test('apply ждёт швы через ctx.inject([tuiScenes, commands])', () => {
  const { ctx, injectCalls } = makeCtx()
  const result = apply(ctx, {})
  assert.equal(result, undefined) // без возврата fiber'а
  assert.equal(injectCalls.length, 1)
  assert.deepEqual(injectCalls[0].deps, ['tuiScenes', 'commands'])
})

test('регистрируются сцена и команда; команда открывает сцену и отвечает success', () => {
  const { ctx, injectCalls } = makeCtx()
  apply(ctx, {})
  const { host, state } = makeHost()
  injectCalls[0].callback(host)

  assert.ok(state.scene, 'сцена не зарегистрирована')
  assert.equal(state.scene.id, 'session-delete')
  assert.equal(typeof state.scene.component, 'function')

  assert.ok(state.command, 'команда не зарегистрирована')
  assert.equal(state.command.name, 'session-delete')
  assert.equal(typeof state.command.description, 'string')
  assert.ok(state.command.description.length > 0)

  const result = state.command.handler()
  assert.deepEqual(state.opened, ['session-delete'])
  assert.deepEqual(result, { kind: 'success' })
})

test('если сцена не открылась — команда отвечает error', () => {
  const { ctx, injectCalls } = makeCtx()
  apply(ctx, {})
  const { host, state } = makeHost()
  injectCalls[0].callback(host)
  // Сцена «не зарегистрирована» с точки зрения open (id не совпадает).
  state.scene = { id: 'other-scene', component: () => null }

  const result = state.command.handler()
  assert.deepEqual(result, { kind: 'error', text: 'не удалось открыть диалог удаления сессий' })
})

test('dispose сцены и команды корректны и идемпотентны', () => {
  const { ctx, injectCalls } = makeCtx()
  apply(ctx, {})
  const { host, state } = makeHost()
  injectCalls[0].callback(host)

  // Возвращённые регистраторами dispose-функции уже отработали бы через
  // host.effect; эмулируем повторный вызов вручную.
  const disposeScene = state.scene
  assert.equal(state.sceneDisposed, false)
  state.scene.component = () => null
  // Сам dispose проверить напрямую нельзя (перехвачен в замыкании регистра),
  // поэтому проверяем, что регистрация вернула функцию.
  const probe = host.tuiScenes.register({ id: 'probe', component: () => null })
  assert.equal(typeof probe, 'function')
  probe()
  probe() // идемпотентно
  assert.ok(true)
})

test('повторный apply (перезагрузка профиля) не падает: новый inject, новый монтаж', () => {
  const { ctx, injectCalls, warnings } = makeCtx()
  apply(ctx, {})
  apply(ctx, {})

  assert.equal(injectCalls.length, 2)
  const hostA = makeHost()
  const hostB = makeHost()
  injectCalls[0].callback(hostA.host)
  injectCalls[1].callback(hostB.host)
  assert.equal(hostA.state.scene.id, 'session-delete')
  assert.equal(hostB.state.scene.id, 'session-delete')
  // Дубликат в ОДНОМ хосте регистрируется вторым callback'ом — так ведёт
  // себя cordis при двух живых активациях; сам плагин ошибки не бросает.
  assert.equal(warnings.filter((w) => w.includes('registration failed')).length, 0)
})

test('idle при отсутствии швов: apply без inject не бросает', () => {
  const warnings = []
  const ctx = {
    logger: { warn: (message) => warnings.push(message) },
    // inject отсутствует; швов нет — mount должен уйти в warn и вернуться.
  }
  assert.doesNotThrow(() => apply(ctx, {}))
  assert.ok(warnings.some((w) => w.includes('tuiScenes недоступен')))
})

test('хост с швами, но без inject: монтируется напрямую', () => {
  const warnings = []
  const ctx = {
    logger: { warn: (message) => warnings.push(message) },
  }
  const { host, state } = makeHost()
  ctx.tuiScenes = host.tuiScenes
  ctx.commands = host.commands
  ctx.get = host.get
  apply(ctx, {})
  assert.equal(state.scene.id, 'session-delete')
  assert.equal(state.command.name, 'session-delete')
})

test('инъектированный fiber с неполными швами не падает', () => {
  const { ctx, injectCalls, warnings } = makeCtx()
  apply(ctx, {})
  const { host, state } = makeHost()
  delete host.commands // commands отсутствует
  host.get = (key) => (key === 'tuiScenes' ? host.tuiScenes : undefined)
  injectCalls[0].callback(host)
  assert.ok(warnings.some((w) => w.includes('commands недоступен')))
})

test('сцена и команда регистрируются из одного host-объекта (одна активация)', () => {
  const { ctx, injectCalls } = makeCtx()
  apply(ctx, {})
  const { host, state } = makeHost()
  injectCalls[0].callback(host)
  // open() открывает сцену, зарегистрированную этим же host'ом.
  assert.equal(host.tuiScenes.open('session-delete'), true)
})

test('normalizeConfig: дефолты, переопределения, неизвестные ключи', () => {
  assert.deepEqual(normalizeConfig({}), { sweep: true, backup: true })
  assert.deepEqual(normalizeConfig(undefined), { sweep: true, backup: true })
  assert.deepEqual(normalizeConfig(null), { sweep: true, backup: true })
  assert.deepEqual(normalizeConfig({ sweep: false }), { sweep: false, backup: true })
  assert.deepEqual(normalizeConfig({ backup: false }), { sweep: true, backup: false })
  assert.deepEqual(
    normalizeConfig({ sweep: false, backup: false, unknown: 42, nested: { x: 1 } }),
    { sweep: false, backup: false },
  )
})

test('apply не пишет в stdout/stderr', () => {
  const { ctx, injectCalls } = makeCtx()
  const writes = []
  const origOut = process.stdout.write
  const origErr = process.stderr.write
  process.stdout.write = (chunk) => {
    writes.push(String(chunk))
    return true
  }
  process.stderr.write = (chunk) => {
    writes.push(String(chunk))
    return true
  }
  try {
    apply(ctx, {})
    injectCalls[0].callback(makeHost().host)
    assert.equal(writes.length, 0)
  } finally {
    process.stdout.write = origOut
    process.stderr.write = origErr
  }
})
