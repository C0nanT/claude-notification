#!/usr/bin/env bash

export DISPLAY="${DISPLAY:-:0}"
export DBUS_SESSION_BUS_ADDRESS="${DBUS_SESSION_BUS_ADDRESS:-unix:path=/run/user/$(id -u)/bus}"

command -v notify-send >/dev/null 2>&1 || exit 0

notify-send 'Claude Code' 'Tarefa concluída ✅'

if command -v paplay >/dev/null 2>&1; then
  paplay --volume=32768 /usr/share/sounds/freedesktop/stereo/complete.oga 2>/dev/null \
    || paplay --volume=32768 /usr/share/sounds/freedesktop/stereo/bell.oga 2>/dev/null \
    || true
elif command -v aplay >/dev/null 2>&1; then
  aplay /usr/share/sounds/alsa/Front_Center.wav 2>/dev/null || true
fi

exit 0
