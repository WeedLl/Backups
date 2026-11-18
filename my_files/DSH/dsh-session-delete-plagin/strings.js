/**
 * Все тексты плагина — только русские строки, в одном месте.
 * @module dsh-session-delete/strings
 */

/** Русская плюрализация: 1 сессия, 2 сессии, 5 сессий. */
export function plural(n, one, few, many) {
  const m10 = n % 10
  const m100 = n % 100
  if (m10 === 1 && m100 !== 11) return one
  if (m10 >= 2 && m10 <= 4 && (m100 < 12 || m100 > 14)) return few
  return many
}

/** Ошибка любой формы — в одну строку для показа. */
export function textOf(error) {
  return error instanceof Error ? error.message : String(error ?? '')
}

export const T = {
  // Шапка и список
  title: 'Удаление сессии',
  count: (n) => `${n} ${plural(n, 'сессия', 'сессии', 'сессий')}`,
  filterLabel: 'фильтр: ',
  badgeCurrent: 'текущая',
  badgeLive: 'работает',
  badgeArchived: 'архив',
  badgeEmpty: 'пустая',
  badgeSubs: (n) => `подсессии ×${n}`,
  untitled: '(без названия)',
  loading: 'загружаю сессии…',
  loadError: (e) => `Не удалось загрузить список сессий: ${e}`,
  noSessions: 'Сохранённых сессий нет.',
  noMatches: 'Ничего не найдено по фильтру.',

  // Футер
  hintBrowse: '↑↓/j k — выбор · Enter — удалить · / — фильтр · r — обновить · q/Esc — закрыть',
  hintFilter: 'печатайте фильтр · Enter/Esc — назад к списку',
  hintDone: 'любая клавиша — назад к списку',
  confirmTitle: (title) => `Удалить «${title}»?`,
  confirmSubs: (n) => `Вместе с ней: ${n} ${plural(n, 'подсессия', 'подсессии', 'подсессий')}.`,
  confirmWarn: 'Логи будут стёрты безвозвратно. y — удалить · n — отмена',
  busy: 'удаляю…',
  deleted: (title) => `Удалено: ${title}`,
  deletedSub: (title) => `Удалено: ${title} (подсессия)`,
  swept: (summary) => `вычищено: ${summary}`,
  emptyDirsRemoved: (n) => `пустых каталогов сессий удалено: ${n}`,

  // Ошибки и отказы
  errCurrent: 'Текущая сессия не может быть удалена.',
  errLive: 'Сессия выполняется — удаление невозможно.',
  errDescendantCurrent: 'Среди подсессий есть текущая — удаление отменено.',
  errDescendantLive: 'Одна из подсессий выполняется — удаление отменено.',
  errMissing: 'Сессия не найдена в списке сохранённых.',
  errUnsafe: 'Недопустимый идентификатор сессии.',
  errHostRefused: (title) => `✗ ${title}: хост отказал (сессия занята или недоступна)`,
  errChildBlocked: (title) => `✗ ${title}: не удалено — подсессия отклонена хостом`,
  errSweep: (what, e) => `✗ вычистка (${what}): ${e}`,

  // Команда
  commandDescription: 'Удалить сохранённую сессию вместе с подсессиями (модальный диалог)',
  sceneOpenFailed: 'не удалось открыть диалог удаления сессий',
}
