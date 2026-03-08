param(
    [string]$Server = "root@46.225.221.45",
    [string]$UserHome = $env:USERPROFILE,
    [string]$SnapshotRoot = ""
)

$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($SnapshotRoot)) {
    $SnapshotRoot = Join-Path $UserHome "server-sync"
}

$RepoRoot = Split-Path -Parent $PSScriptRoot
$Timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$SnapshotDir = Join-Path $SnapshotRoot $Timestamp
$LocalBackupDir = Join-Path $SnapshotRoot "local-backup-$Timestamp"

$LocalClawd = Join-Path $UserHome "clawd"
$LocalRomualdo = Join-Path $UserHome "openclaw-romualdo"
$LocalOpenclaw = Join-Path $UserHome ".openclaw"
$RepoWeatherSkill = Join-Path $RepoRoot "skills\weather"

New-Item -ItemType Directory -Path $SnapshotDir -Force | Out-Null
New-Item -ItemType Directory -Path $LocalBackupDir -Force | Out-Null

Write-Host "== Pulling snapshot from server =="
scp -r "${Server}:/root/clawd" "$SnapshotDir\"
scp -r "${Server}:/root/openclaw-romualdo" "$SnapshotDir\"
New-Item -ItemType Directory -Path "$SnapshotDir\.openclaw" -Force | Out-Null
scp "${Server}:/root/.openclaw/openclaw.json" "$SnapshotDir\.openclaw\openclaw.json"
scp -r "${Server}:/root/.openclaw/agents" "$SnapshotDir\.openclaw\" 2>$null

Write-Host "== Backing up local key files =="
if (Test-Path "$LocalClawd\AGENTS.md") { Copy-Item "$LocalClawd\AGENTS.md" "$LocalBackupDir\clawd-AGENTS.md" -Force }
if (Test-Path "$LocalRomualdo\AGENTS.md") { Copy-Item "$LocalRomualdo\AGENTS.md" "$LocalBackupDir\romualdo-AGENTS.md" -Force }
if (Test-Path "$LocalClawd\memory") { Copy-Item "$LocalClawd\memory" "$LocalBackupDir\clawd-memory" -Recurse -Force }
if (Test-Path "$LocalRomualdo\memory") { Copy-Item "$LocalRomualdo\memory" "$LocalBackupDir\romualdo-memory" -Recurse -Force }
if (Test-Path "$LocalClawd\skills") { Copy-Item "$LocalClawd\skills" "$LocalBackupDir\clawd-skills" -Recurse -Force }
if (Test-Path "$LocalRomualdo\skills") { Copy-Item "$LocalRomualdo\skills" "$LocalBackupDir\romualdo-skills" -Recurse -Force }
if (Test-Path "$LocalOpenclaw\openclaw.json") { Copy-Item "$LocalOpenclaw\openclaw.json" "$LocalBackupDir\openclaw.json" -Force }
if (Test-Path "$RepoRoot\clawcito-AGENTS.md") { Copy-Item "$RepoRoot\clawcito-AGENTS.md" "$LocalBackupDir\clawcito-AGENTS.md" -Force }
if (Test-Path "$RepoRoot\romualdo-AGENTS.md") { Copy-Item "$RepoRoot\romualdo-AGENTS.md" "$LocalBackupDir\romualdo-AGENTS.md" -Force }
if (Test-Path $RepoWeatherSkill) { Copy-Item $RepoWeatherSkill "$LocalBackupDir\repo-weather-skill" -Recurse -Force }

Write-Host "== Syncing snapshot into local paths =="
robocopy "$SnapshotDir\clawd" "$LocalClawd" /E /R:2 /W:1 /NFL /NDL /NJH /NJS /NC /NS | Out-Null
if ($LASTEXITCODE -gt 7) { throw "robocopy clawd failed with code $LASTEXITCODE" }

robocopy "$SnapshotDir\openclaw-romualdo" "$LocalRomualdo" /E /R:2 /W:1 /NFL /NDL /NJH /NJS /NC /NS | Out-Null
if ($LASTEXITCODE -gt 7) { throw "robocopy openclaw-romualdo failed with code $LASTEXITCODE" }

Copy-Item "$SnapshotDir\.openclaw\openclaw.json" "$LocalOpenclaw\openclaw.json" -Force
if (Test-Path "$SnapshotDir\.openclaw\agents") {
    robocopy "$SnapshotDir\.openclaw\agents" "$LocalOpenclaw\agents" /E /R:2 /W:1 /NFL /NDL /NJH /NJS /NC /NS | Out-Null
    if ($LASTEXITCODE -gt 7) { throw "robocopy .openclaw/agents failed with code $LASTEXITCODE" }
}

Write-Host "== Updating repo mirrors =="
Copy-Item "$SnapshotDir\clawd\AGENTS.md" "$RepoRoot\clawcito-AGENTS.md" -Force
Copy-Item "$SnapshotDir\openclaw-romualdo\AGENTS.md" "$RepoRoot\romualdo-AGENTS.md" -Force
Copy-Item "$SnapshotDir\.openclaw\openclaw.json" "$RepoRoot\openclaw.json" -Force
if (Test-Path "$SnapshotDir\clawd\skills\weather") {
    New-Item -ItemType Directory -Path (Split-Path -Parent $RepoWeatherSkill) -Force | Out-Null
    robocopy "$SnapshotDir\clawd\skills\weather" $RepoWeatherSkill /E /R:2 /W:1 /NFL /NDL /NJH /NJS /NC /NS | Out-Null
    if ($LASTEXITCODE -gt 7) { throw "robocopy repo weather skill failed with code $LASTEXITCODE" }
}

Write-Host ""
Write-Host "Pull complete."
Write-Host "Snapshot: $SnapshotDir"
Write-Host "Local backup: $LocalBackupDir"
