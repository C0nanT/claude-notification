#!/usr/bin/env bash

# Set display env vars if not already present (needed when running from background process)
export DISPLAY="${DISPLAY:-:0}"
export DBUS_SESSION_BUS_ADDRESS="${DBUS_SESSION_BUS_ADDRESS:-unix:path=/run/user/$(id -u)/bus}"

command -v notify-send >/dev/null 2>&1 || exit 0

notify-send -u critical 'Claude Code' 'Aguardando sua atenção 👀'

if command -v paplay >/dev/null 2>&1; then
  paplay --volume=32768 /usr/share/sounds/freedesktop/stereo/bell.oga 2>/dev/null \
    || paplay --volume=32768 /usr/share/sounds/freedesktop/stereo/message.oga 2>/dev/null \
    || true
elif command -v aplay >/dev/null 2>&1; then
  aplay /usr/share/sounds/alsa/Front_Center.wav 2>/dev/null || true
fi

exit 0
