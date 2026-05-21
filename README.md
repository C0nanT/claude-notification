# claude-notification

Desktop notifications with sound on Linux when Claude needs attention or finishes a task.

**Events:**
- `Notification` — visual popup + bell sound (aguardando atenção)
- `Stop` — visual popup + complete sound (tarefa concluída)

**Requirements:** `notify-send` (libnotify-bin) + `paplay` (pulseaudio-utils)

**Optional:** `jq` — enables per-session deduplication (2s window). Without `jq` notifications still work but duplicates from Claude Code [issue #3465](https://github.com/anthropics/claude-code/issues/3465) (hook fires twice when running from `$HOME`) are not suppressed.

## Install

```bash
git clone <repo-url> ~/projects/tools/claude-notification
bash ~/projects/tools/claude-notification/install.sh
```

Then restart Claude Code and run:
```
/plugin install claude-notification@claude-notification
```

## Manual (without install.sh)

Add to `~/.claude/settings.json`:
```json
{
  "extraKnownMarketplaces": {
    "claude-notification": {
      "source": {
        "source": "directory",
        "path": "/absolute/path/to/claude-notification"
      },
      "autoUpdate": false
    }
  }
}
```

Then install via marketplace.

## Volume

Edit `hooks/notify-attention.sh` and `hooks/notify-done.sh`. Change `--volume=32768` (50%).  
Range: `0` (mute) → `65536` (100%).

## Troubleshooting

**Duplicate notifications** — install `jq` (`sudo apt install jq`). Hooks then dedupe by `session_id` + event in a 2s window. State files live under `$XDG_RUNTIME_DIR/claude-notification/` (fallback `/tmp/claude-notification/`).
