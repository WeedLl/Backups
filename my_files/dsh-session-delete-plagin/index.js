/**
 * dsh-session-delete — удаление сохранённых сессий dsh-TUI.
 *
 * Команда `/session-delete` открывает full-screen сцену `session-delete`
 * (собственный модал: host-диалоги поверх сцены не рендерятся). Сцена
 * показывает сохранённые сессии (`channel.listSessions` + live-факты из
 * `channel.agentViewRows`), позволяет выбрать одну, подтвердить и удалить
 * её вместе с подсессиями через штатный `channel.deleteSession`, после чего
 * вычищает «хвосты» в state-файлах (sweep) и пустые slug-каталоги.
 *
 * Подключение — только `ctx.inject(['tuiScenes','commands'], …)`: строки TUI
 * монтируются позже этой строки, soft-probe проигрывает гонку. В headless-
 * хосте callback просто не выполняется — плагин бездействует, не ломая boot.
 *
 * Контракты cordis: `export const name` + `export function apply`; apply НЕ
 * возвращает fiber (возврат был бы принят за effect → «Invalid effect»);
 * `export default` отсутствует (unwrapExports схлопнул бы namespace).
 *
 * Вывод в stdout/stderr отсутствует; диагностика — только `ctx.logger.warn`
 * (флаг `DSH_SESSION_DELETE_DEBUG=1` добавляет подробности в лог).
 * @module dsh-session-delete
 */

import { createSessionDeleteScene } from './scene.js'
import { T, textOf } from './strings.js'

/** Cordis-имя плагина (локальная идентичность строки). */
export const name = 'session-delete'

/** Id сцены и имя команды: `/session-delete` — валидно по `/^[a-z][a-z0-9_-]*$/`. */
export const SCENE_ID = 'session-delete'
export const COMMAND_NAME = 'session-delete'

/**
 * Нормализация конфига строки cordis без schemastery: `{sweep, backup}`,
 * оба по умолчанию true; неизвестные ключи игнорируются.
 */
export function normalizeConfig(config) {
  const source = config !== null && typeof config === 'object' ? config : {}
  return {
    sweep: source.sweep !== false,
    backup: source.backup !== false,
  }
}

/**
 * Активация плагина.
 * @param {object} ctx — cordis-контекст.
 * @param {{sweep?: boolean, backup?: boolean}} [config]
 */
export function apply(ctx, config = {}) {
  const settings = normalizeConfig(config)
  const logger = ctx?.logger
  const warn = (message) => {
    try {
      logger?.warn?.(`[${name}] ${message}`)
    } catch {
      // Логирование не должно ронять активацию.
    }
  }
  const debug = process.env.DSH_SESSION_DELETE_DEBUG === '1'
    ? (message) => warn(`debug: ${message}`)
    : () => {}

  // Компонент создаётся ОДИН раз на активацию: пересоздание на каждый
  // рендер перемонтировало бы сцену и потеряло состояние.
  const component = createSessionDeleteScene(settings)

  /**
   * Монтаж из одного инъектированного fiber'а: сцена и команда должны
   * принадлежать ОДНОЙ активации, иначе `tuiScenes.open` откажет
   * («belongs to another activation»).
   */
  const mount = (host) => {
    try {
      const scenes = host?.tuiScenes ?? host?.get?.('tuiScenes', false)
      const commands = host?.commands ?? host?.get?.('commands', false)
      if (scenes === undefined || typeof scenes.register !== 'function') {
        warn('tuiScenes недоступен — сцена не зарегистрирована')
        return
      }
      if (commands === undefined || typeof commands.register !== 'function') {
        warn('commands недоступен — команда не зарегистрирована')
        return
      }

      const disposeScene = scenes.register(
        {
          id: SCENE_ID,
          title: T.title,
          component,
        },
        host,
      )
      if (typeof host?.effect === 'function') {
        host.effect(() => disposeScene, `${name} scene`)
      }
      debug('scene registered')

      const disposeCommand = commands.register({
        name: COMMAND_NAME,
        description: T.commandDescription,
        handler: () => {
          try {
            const opened = scenes.open(SCENE_ID)
            if (opened !== true) return { kind: 'error', text: T.sceneOpenFailed }
            // Тихое открытие: сцена занимает экран, чат не засоряется.
            return { kind: 'success' }
          } catch (error) {
            warn(`command handler failed: ${textOf(error)}`)
            return { kind: 'error', text: T.sceneOpenFailed }
          }
        },
      })
      if (typeof host?.effect === 'function') {
        host.effect(() => disposeCommand, `${name} command`)
      }
      debug('command registered')
    } catch (error) {
      warn(`registration failed: ${textOf(error)}`)
    }
  }

  try {
    if (typeof ctx?.inject === 'function') {
      ctx.inject(['tuiScenes', 'commands'], mount)
      debug('injected (ожидание tuiScenes + commands)')
    } else {
      // Хост без inject-механизма: швы, если есть, уже на месте.
      mount(ctx)
    }
  } catch (error) {
    warn(`apply failed: ${textOf(error)}`)
  }
}
