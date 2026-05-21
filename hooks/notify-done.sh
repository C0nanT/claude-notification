
#!/usr/bin/env bash

STATE_DIR="${XDG_RUNTIME_DIR:-/tmp}/claude-notification"
mkdir -p "$STATE_DIR" 2>/dev/null
DEBOUNCE_SECONDS=2

if command -v jq >/dev/null 2>&1; then
  payload=$(cat)
  session_id=$(printf '%s' "$payload" | jq -r '.session_id // empty' 2>/dev/null)
  event=$(printf '%s' "$payload" | jq -r '.hook_event_name // empty' 2>/dev/null)
  if [ -n "$session_id" ] && [ -n "$event" ]; then
    key=$(printf '%s-%s' "$session_id" "$event" | tr -c 'a-zA-Z0-9-' '_')
    state_file="$STATE_DIR/$key.ts"
    now=$(date +%s)
    if [ -f "$state_file" ]; then
      last=$(cat "$state_file" 2>/dev/null || echo 0)
      if [ $((now - last)) -lt $DEBOUNCE_SECONDS ]; then
        exit 0
      fi
    fi
    echo "$now" > "$state_file"
  fi
fi

is_wsl() {
  grep -qi microsoft /proc/version 2>/dev/null || [ -n "${WSL_DISTRO_NAME:-}" ]
}

if is_wsl; then
  powershell.exe -WindowStyle Hidden -Command "
    [Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime] | Out-Null
    [Windows.Data.Xml.Dom.XmlDocument, Windows.Data.Xml.Dom.XmlDocument, ContentType = WindowsRuntime] | Out-Null
    \$template = [Windows.UI.Notifications.ToastNotificationManager]::GetTemplateContent([Windows.UI.Notifications.ToastTemplateType]::ToastText02)
    \$template.SelectSingleNode('//text[@id=1]').InnerText = 'Claude Code'
    \$template.SelectSingleNode('//text[@id=2]').InnerText = 'Tarefa concluida'
    \$toast = [Windows.UI.Notifications.ToastNotification]::new(\$template)
    [Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier('Claude Code').Show(\$toast)
    [Console]::Beep(523, 120)
    [Console]::Beep(659, 120)
    [Console]::Beep(784, 180)
  " &
  exit 0
fi

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
