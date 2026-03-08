# Local <-> Server Workflow

This repo uses the server state as the baseline and keeps the memory workflow reproducible locally.

## One-time setup done

- Local OpenClaw CLI aligned to server version: `2026.2.22-2`.
- Server state pulled into local paths.
- Automation scripts added:
  - `scripts/pull_server_state.ps1`
  - `scripts/deploy_to_server.ps1`
  - `scripts/reset_main_session_silent.sh`
  - `scripts/consolidate_daily_memory.mjs`

## Daily flow (recommended)

1. Pull latest server state before starting:
   - `.\scripts\pull_server_state.ps1`
2. Make changes locally.
3. Review and commit:
   - `git status`
   - `git add <files>`
   - `git commit -m "your message"`
4. Deploy + restart + health check:
   - `.\scripts\deploy_to_server.ps1`
5. Verify runtime state:
   - `ssh root@46.225.221.45 "openclaw gateway health; tail -n 30 /root/openclaw-gateway.log"`

## Memory-specific notes

- Stable startup context lives in workspace Markdown files:
  - `/root/clawd/AGENTS.md`
  - `/root/clawd/USER.md`
  - `/root/clawd/IDENTITY.md`
  - `/root/clawd/SOUL.md`
- Recent startup context lives in daily files under `/root/clawd/memory/`.
- The hourly reset script calls `scripts/consolidate_daily_memory.mjs` before `sessions.reset`.
- Deploy now syncs both workspace `memory/` directories and the helper under `/root/bin/`.
- Deploy also syncs workspace `skills/` directories, including the shared weather skill.
- Pull now backs up local `memory/` directories before applying the server snapshot.

## What deploy updates

- `/root/.openclaw/openclaw.json`
- `/root/clawd/*.md` and `/root/clawd/memory/**`
- `/root/clawd/skills/**`
- `/root/openclaw-romualdo/*.md` and `/root/openclaw-romualdo/memory/**`
- `/root/openclaw-romualdo/skills/**`
- `/root/bin/reset_main_session_silent.sh`
- `/root/bin/consolidate_daily_memory.mjs`

## Notes

- Pull script saves a timestamped snapshot in `C:\Users\<you>\server-sync\`.
- Deploy script creates remote backups in `/root/backups/openclaw-sync/<timestamp>/`.
- Repo mirrors `clawcito-AGENTS.md` and `romualdo-AGENTS.md` are synced into the local workspaces on deploy when the repo copy is newer.
- Repo `skills/weather/` is synced into both local workspaces on deploy and refreshed from the server on pull.

## If `openclaw` command is not found in current terminal

Restart the terminal, or use:

`C:\Users\rolda\AppData\Roaming\npm\openclaw.cmd --version`
