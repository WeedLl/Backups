#!/bin/sh
# Лочит экран Noctalia при первом входе после загрузки.
#
# Рассчитан на автологин SDDM: без него пароль вводится в гриттере, и лок сразу
# после входа был бы лишним. Поэтому скрипт сам проверяет, что дроп-ин автологина
# на месте: убрал файл — лок отключился.
#
# Повторный вход в ту же загрузку (logout → вход) не лочится: boot_id
# сравнивается с маркером.
#
# Переменные ниже нужны только для тестов, в обычной работе не задаются.
set -u

sddm_conf=${NIRI_AUTOLOCK_CONF:-/etc/sddm.conf.d/10-autologin.conf}
marker=${NIRI_AUTOLOCK_MARKER:-$HOME/.cache/niri-autolock-boot}

[ -f "$sddm_conf" ] || exit 0

boot=$(cat /proc/sys/kernel/random/boot_id 2>/dev/null) || exit 0
[ -n "$boot" ] || exit 0

# Уже лочились в этой загрузке.
if [ "$(cat "$marker" 2>/dev/null)" = "$boot" ]; then
    exit 0
fi

mkdir -p "$(dirname "$marker")"

# Noctalia стартует параллельно: ждём готовности её IPC до ~20 секунд.
i=0
while [ "$i" -lt 100 ]; do
    if noctalia msg session lock >/dev/null 2>&1; then
        printf '%s\n' "$boot" > "$marker"
        exit 0
    fi
    i=$((i + 1))
    sleep 0.2
done

exit 1
