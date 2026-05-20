
#!/usr/bin/env bash

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
