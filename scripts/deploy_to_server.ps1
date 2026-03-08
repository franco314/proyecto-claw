param(
    [string]$Server = "root@46.225.221.45",
    [string]$UserHome = $env:USERPROFILE,
    [switch]$SkipRestart
)

$ErrorActionPreference = "Stop"

$RepoRoot = Split-Path -Parent $PSScriptRoot
$LocalClawd = Join-Path $UserHome "clawd"
$LocalRomualdo = Join-Path $UserHome "openclaw-romualdo"
$RepoClawdAgents = Join-Path $RepoRoot "clawcito-AGENTS.md"
$RepoRomualdoAgents = Join-Path $RepoRoot "romualdo-AGENTS.md"
$RepoWeatherSkillDir = Join-Path $RepoRoot "skills\weather"
$LocalOpenclawJson = Join-Path $RepoRoot "openclaw.json"
$LocalResetScript = Join-Path $RepoRoot "scripts\reset_main_session_silent.sh"
$LocalMemoryHelper = Join-Path $RepoRoot "scripts\consolidate_daily_memory.mjs"
$Timestamp = Get-Date -Format "yyyyMMdd-HHmmss"

function Sync-MirrorIfNewer {
    param(
        [string]$MirrorPath,
        [string]$LocalPath,
        [string]$Label
    )

    if (-not (Test-Path $MirrorPath)) {
        return
    }

    $useMirror = -not (Test-Path $LocalPath)
    if (-not $useMirror) {
        $mirrorItem = Get-Item $MirrorPath
        $localItem = Get-Item $LocalPath
        $useMirror = $mirrorItem.LastWriteTimeUtc -gt $localItem.LastWriteTimeUtc
    }

    if ($useMirror) {
        Copy-Item $MirrorPath $LocalPath -Force
        Write-Host "== Synced repo mirror to $Label =="
    }
}

function Sync-RepoDirectory {
    param(
        [string]$SourcePath,
        [string]$DestinationPath,
        [string]$Label
    )

    if (-not (Test-Path $SourcePath)) {
        return
    }

    $destinationParent = Split-Path -Parent $DestinationPath
    if (-not (Test-Path $destinationParent)) {
        New-Item -ItemType Directory -Path $destinationParent -Force | Out-Null
    }

    robocopy $SourcePath $DestinationPath /E /R:2 /W:1 /NFL /NDL /NJH /NJS /NC /NS | Out-Null
    if ($LASTEXITCODE -gt 7) { throw "robocopy $Label failed with code $LASTEXITCODE" }
    Write-Host "== Synced repo directory to $Label =="
}

Sync-MirrorIfNewer -MirrorPath $RepoClawdAgents -LocalPath (Join-Path $LocalClawd "AGENTS.md") -Label "clawd\\AGENTS.md"
Sync-MirrorIfNewer -MirrorPath $RepoRomualdoAgents -LocalPath (Join-Path $LocalRomualdo "AGENTS.md") -Label "openclaw-romualdo\\AGENTS.md"
Sync-RepoDirectory -SourcePath $RepoWeatherSkillDir -DestinationPath (Join-Path $LocalClawd "skills\weather") -Label "clawd\\skills\\weather"
Sync-RepoDirectory -SourcePath $RepoWeatherSkillDir -DestinationPath (Join-Path $LocalRomualdo "skills\weather") -Label "openclaw-romualdo\\skills\\weather"

if (-not (Test-Path $LocalOpenclawJson)) {
    throw "Missing local file: $LocalOpenclawJson"
}
if (-not (Test-Path "$LocalClawd\AGENTS.md")) {
    throw "Missing local file: $LocalClawd\AGENTS.md"
}
if (-not (Test-Path "$LocalRomualdo\AGENTS.md")) {
    throw "Missing local file: $LocalRomualdo\AGENTS.md"
}
if (-not (Test-Path "$LocalClawd\skills\weather\SKILL.md")) {
    throw "Missing local weather skill in $LocalClawd\skills\weather"
}
if (-not (Test-Path "$LocalRomualdo\skills\weather\SKILL.md")) {
    throw "Missing local weather skill in $LocalRomualdo\skills\weather"
}
if (-not (Test-Path $LocalMemoryHelper)) {
    throw "Missing local file: $LocalMemoryHelper"
}

Write-Host "== Creating remote backup =="
$backupCmd = @"
set -e

ts=$Timestamp
mkdir -p /root/backups/openclaw-sync/`$ts/clawd /root/backups/openclaw-sync/`$ts/openclaw-romualdo /root/backups/openclaw-sync/`$ts/openclaw-config /root/backups/openclaw-sync/`$ts/bin
for f in AGENTS.md SOUL.md IDENTITY.md USER.md TOOLS.md HEARTBEAT.md; do
  [ -f /root/clawd/`$f ] && cp -a /root/clawd/`$f /root/backups/openclaw-sync/`$ts/clawd/`$f || true
  [ -f /root/openclaw-romualdo/`$f ] && cp -a /root/openclaw-romualdo/`$f /root/backups/openclaw-sync/`$ts/openclaw-romualdo/`$f || true
done
[ -d /root/clawd/skills ] && cp -a /root/clawd/skills /root/backups/openclaw-sync/`$ts/clawd/ || true
[ -d /root/openclaw-romualdo/skills ] && cp -a /root/openclaw-romualdo/skills /root/backups/openclaw-sync/`$ts/openclaw-romualdo/ || true
[ -d /root/clawd/memory ] && cp -a /root/clawd/memory /root/backups/openclaw-sync/`$ts/clawd/ || true
[ -d /root/openclaw-romualdo/memory ] && cp -a /root/openclaw-romualdo/memory /root/backups/openclaw-sync/`$ts/openclaw-romualdo/ || true
[ -f /root/bin/reset_main_session_silent.sh ] && cp -a /root/bin/reset_main_session_silent.sh /root/backups/openclaw-sync/`$ts/bin/reset_main_session_silent.sh || true
[ -f /root/bin/consolidate_daily_memory.mjs ] && cp -a /root/bin/consolidate_daily_memory.mjs /root/backups/openclaw-sync/`$ts/bin/consolidate_daily_memory.mjs || true
[ -f /root/.openclaw/openclaw.json ] && cp -a /root/.openclaw/openclaw.json /root/backups/openclaw-sync/`$ts/openclaw-config/openclaw.json || true
echo REMOTE_BACKUP=/root/backups/openclaw-sync/`$ts
"@
ssh $Server $backupCmd
if ($LASTEXITCODE -ne 0) { throw "Remote backup failed with exit code $LASTEXITCODE" }

Write-Host "== Ensuring remote directories =="
$ensureDirsCmd = "set -e; mkdir -p /root/bin /root/clawd/memory /root/clawd/skills /root/openclaw-romualdo/memory /root/openclaw-romualdo/skills"
ssh $Server $ensureDirsCmd
if ($LASTEXITCODE -ne 0) { throw "Remote directory setup failed with exit code $LASTEXITCODE" }

Write-Host "== Uploading local state to server =="
scp "$LocalOpenclawJson" "${Server}:/root/.openclaw/openclaw.json"

foreach ($file in @("AGENTS.md", "SOUL.md", "IDENTITY.md", "USER.md", "TOOLS.md", "HEARTBEAT.md")) {
    if (Test-Path "$LocalClawd\$file") {
        scp "$LocalClawd\$file" "${Server}:/root/clawd/$file"
    }
    if (Test-Path "$LocalRomualdo\$file") {
        scp "$LocalRomualdo\$file" "${Server}:/root/openclaw-romualdo/$file"
    }
}

if (Test-Path "$LocalClawd\memory") {
    Write-Host "== Syncing clawd memory directory =="
    scp -r "$LocalClawd\memory" "${Server}:/root/clawd/"
}
if (Test-Path "$LocalRomualdo\memory") {
    Write-Host "== Syncing romualdo memory directory =="
    scp -r "$LocalRomualdo\memory" "${Server}:/root/openclaw-romualdo/"
}

if (Test-Path "$LocalClawd\skills") {
    Write-Host "== Syncing clawd skills directory =="
    scp -r "$LocalClawd\skills" "${Server}:/root/clawd/"
}
if (Test-Path "$LocalRomualdo\skills") {
    Write-Host "== Syncing romualdo skills directory =="
    scp -r "$LocalRomualdo\skills" "${Server}:/root/openclaw-romualdo/"
}

if (Test-Path $LocalResetScript) {
    Write-Host "== Syncing hourly reset script =="
    scp "$LocalResetScript" "${Server}:/root/bin/reset_main_session_silent.sh"
}

Write-Host "== Syncing memory consolidation helper =="
scp "$LocalMemoryHelper" "${Server}:/root/bin/consolidate_daily_memory.mjs"

$scriptFixCmd = @"
set -e
for f in /root/bin/reset_main_session_silent.sh /root/bin/consolidate_daily_memory.mjs; do
  [ -f `$f ] || continue
  sed -i 's/\r$//' `$f
  chmod +x `$f
done
find /root/clawd/skills /root/openclaw-romualdo/skills -type f -name '*.sh' 2>/dev/null | while read -r f; do
  sed -i 's/\r$//' "`$f"
  chmod +x "`$f"
done
"@
ssh $Server $scriptFixCmd
if ($LASTEXITCODE -ne 0) { throw "Remote script setup failed with exit code $LASTEXITCODE" }

if (-not $SkipRestart) {
    Write-Host "== Restarting remote gateway =="
    $restartCmd = @"
set -e

restart_status=0
if openclaw gateway restart >/tmp/openclaw-gateway-restart.log 2>&1; then
  restart_status=0
else
  restart_status=`$?
fi

if [ "`$restart_status" -ne 0 ]; then
  echo "openclaw gateway restart failed with exit code `$restart_status" >&2
  cat /tmp/openclaw-gateway-restart.log >&2 || true

  openclaw gateway stop >/dev/null 2>&1 || true
  pkill -x openclaw-gateway >/dev/null 2>&1 || true

  start_status=0
  if openclaw gateway start >/tmp/openclaw-gateway-start.log 2>&1; then
    start_status=0
  else
    start_status=`$?
  fi

  if [ "`$start_status" -ne 0 ]; then
    echo "openclaw gateway start failed with exit code `$start_status" >&2
    cat /tmp/openclaw-gateway-start.log >&2 || true

    echo "Falling back to unmanaged gateway launch" >&2
    nohup openclaw gateway >/root/openclaw-gateway.log 2>&1 &
    sleep 5
    openclaw gateway health >/dev/null 2>&1
  fi
fi
"@
    ssh $Server $restartCmd
    if ($LASTEXITCODE -ne 0) { throw "Remote restart failed with exit code $LASTEXITCODE" }
}

Write-Host "== Health check =="
$healthCmd = "set -e; echo '--- gateway status ---'; openclaw gateway status || true; echo '--- gateway health ---'; openclaw gateway health || true; echo '--- last logs ---'; tail -n 25 /root/openclaw-gateway.log || true"
ssh $Server $healthCmd
if ($LASTEXITCODE -ne 0) { throw "Remote health check failed with exit code $LASTEXITCODE" }

Write-Host ""
Write-Host "Deploy complete."
