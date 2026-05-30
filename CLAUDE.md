# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

Claude Code plugin. Fires desktop notifications (visual + sound) on `Notification` and `Stop` hook events. Works on native Linux and WSL.

## Structure

- `.claude-plugin/plugin.json` — plugin manifest; maps hook events to shell scripts
- `.claude-plugin/marketplace.json` — marketplace registry metadata
- `hooks/notify-attention.sh` — fires on `Notification` (attention needed)
- `hooks/notify-done.sh` — fires on `Stop` (task complete)
- `install.sh` — installs system deps, registers marketplace in `~/.claude/settings.json`

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

**Deduplication** — requires `jq`. State files at `$XDG_RUNTIME_DIR/claude-notification/` (fallback `/tmp/claude-notification/`). Key = `session_id + hook_event_name`, 2s debounce window. Suppresses duplicate fires from Claude Code issue #3465 (hook fires twice when CWD is `$HOME`).

**WSL detection** — `is_wsl()` checks `/proc/version` for "microsoft" or `$WSL_DISTRO_NAME`. WSL path uses `powershell.exe` WinRT toast + `[Console]::Beep()`, then exits — no Linux notify path runs.

**Native Linux** — `notify-send` for popup, `paplay` (PulseAudio) preferred for sound with `--volume=32768` (50% of 65536 max). Falls back to `aplay`.

**Volume** — change `--volume=32768` in both hook scripts. Range: `0`–`65536`.
