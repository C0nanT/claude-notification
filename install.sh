#!/usr/bin/env bash
set -e

PLUGIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SETTINGS="$HOME/.claude/settings.json"

source "$PLUGIN_DIR/lib/common.sh"

if ! is_wsl; then
  if ! command -v notify-send >/dev/null 2>&1; then
    echo "Installing libnotify-bin..."
    sudo apt install -y libnotify-bin
  fi

  if ! command -v paplay >/dev/null 2>&1; then
    echo "Installing pulseaudio-utils..."
    sudo apt install -y pulseaudio-utils
  fi
fi

chmod +x "$PLUGIN_DIR/hooks/"*.sh

if [ ! -f "$SETTINGS" ]; then
  echo '{}' > "$SETTINGS"
fi

python3 - "$SETTINGS" "$PLUGIN_DIR" <<'EOF'
import json, sys

settings_path, plugin_dir = sys.argv[1], sys.argv[2]

with open(settings_path) as f:
    cfg = json.load(f)

marketplaces = cfg.setdefault("extraKnownMarketplaces", {})

marketplaces["claude-notification"] = {
    "source": {
        "source": "directory",
        "path": plugin_dir
    },
    "autoUpdate": False
}

with open(settings_path, "w") as f:
    json.dump(cfg, f, indent=2, ensure_ascii=False)
    f.write("\n")

print(f"Added claude-notification marketplace pointing to: {plugin_dir}")
EOF

echo ""
echo "Done. Restart Claude Code, then run: /plugin install claude-notification@claude-notification"
