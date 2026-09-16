# Regression coverage for plugin#472: Antigravity ensure-monk-agent.ps1 must
# invoke the managed bootstrap script on cold start so plugin upgrades refresh
# monk-agent automatically.

$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$hook = Join-Path $repoRoot ".antigravity-plugin\hooks\ensure-monk-agent.ps1"
$bootstrap = Join-Path $repoRoot ".antigravity-plugin\scripts\ensure-monk-agent.ps1"

if (-not (Test-Path $hook)) {
  throw "Hook not found: $hook"
}
if (-not (Test-Path $bootstrap)) {
  throw "Bootstrap script not found: $bootstrap"
}

$hookText = Get-Content $hook -Raw
$bootstrapText = Get-Content $bootstrap -Raw

# The hook must delegate to the managed bootstrap (with -Quiet so that status
# output does not corrupt the Antigravity hook stdout).
if ($hookText -notmatch 'scripts\\ensure-monk-agent\.ps1') {
  throw "ensure-monk-agent.ps1 does not reference the managed bootstrap script"
}
if ($hookText -notmatch '-Quiet') {
  throw "ensure-monk-agent.ps1 does not pass -Quiet to the bootstrap"
}

# The bootstrap must support the -Quiet switch.
if ($bootstrapText -notmatch 'param\s*\(\s*\[switch\]\s*\$Quiet') {
  throw "ensure-monk-agent.ps1 bootstrap does not support -Quiet"
}

# The bootstrap's only stdout output must be the binary path (Write-Host is
# gated by -Quiet; Write-Output returns the path).
if ($bootstrapText -notmatch 'if\s*\(\s*-not\s+\$Quiet\s*\)\s*\{\s*Write-Host') {
  throw "ensure-monk-agent.ps1 bootstrap does not gate Write-Host with -Quiet"
}

Write-Host "ensure-monk-agent.ps1 wiring for managed bootstrap is correct."
