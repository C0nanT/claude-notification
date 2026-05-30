# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

Claude Code plugin. Fires desktop notifications (visual + sound) on `Notification` and `Stop` hook events. Works on native Linux and WSL.

## Structure

- `.claude-plugin/plugin.json` — plugin manifest; maps hook events to shell scripts
- `.claude-plugin/marketplace.json` — marketplace registry metadata
- `hooks/notify-attention.sh` — thin wrapper for `Notification` event
- `hooks/notify-done.sh` — thin wrapper for `Stop` event
- `lib/common.sh` — shared functions: `is_wsl`, `deduplicate_or_exit`, `setup_display`, `notify_linux`, `notify_wsl`, `play_sound`
- `install.sh` — installs system deps (skips on WSL), registers marketplace in `~/.claude/settings.json`

## Install / test cycle

```bash
bash install.sh                        # registers marketplace, installs deps
# restart Claude Code, then:
/plugin install claude-notification@claude-notification
```

Manual test (simulate hook payload):
```bash
echo '{"session_id":"test","hook_event_name":"Notification"}' | bash hooks/notify-attention.sh
echo '{"session_id":"test","hook_event_name":"Stop"}' | bash hooks/notify-done.sh
```

## Key behaviors

**Deduplication** — requires `jq`. State files at `$XDG_RUNTIME_DIR/claude-notification/` (fallback `/tmp/claude-notification/`). Key = `session_id + hook_event_name`, 2s debounce window. Suppresses duplicate fires from Claude Code issue #3465 (hook fires twice when CWD is `$HOME`). Implemented in `lib/common.sh:deduplicate_or_exit`.

**WSL detection** — `is_wsl()` in `lib/common.sh` checks `/proc/version` for "microsoft" or `$WSL_DISTRO_NAME`. WSL path uses `powershell.exe` WinRT toast + `[Console]::Beep()`, then exits — no Linux notify path runs. `install.sh` skips apt deps on WSL.

**Native Linux** — `notify-send` for popup, `paplay` (PulseAudio) preferred for sound with `--volume=32768` (50% of 65536 max). Falls back to `aplay`.

**Volume** — change `--volume=32768` in `lib/common.sh:play_sound`. Range: `0`–`65536`.

**Adding new hooks** — source `lib/common.sh`, declare constants at top, call `deduplicate_or_exit` → `is_wsl` branch → `notify_linux` + `play_sound`.
