$ErrorActionPreference = "Stop"

$ScriptUnderTest = Join-Path $PSScriptRoot "start-monk-agent.ps1"
$Source = Get-Content -LiteralPath $ScriptUnderTest -Raw

if ($Source -notmatch 'function\s+Invoke-LoopbackHttp') {
  throw "expected start-monk-agent.ps1 to define Invoke-LoopbackHttp"
}

if ($Source -notmatch '\$Handler\.UseProxy\s*=\s*\$false') {
  throw "expected Invoke-LoopbackHttp to disable proxy use for loopback requests"
}

if ($Source -match 'Invoke-WebRequest|Invoke-RestMethod') {
  throw "loopback launcher probes must not use proxy-aware Invoke-WebRequest/Invoke-RestMethod"
}

foreach ($ExpectedCall in @(
  'Invoke-LoopbackHttp -Uri $HealthUrl -TimeoutSec 2',
  'Invoke-LoopbackHttp -Uri $StatusUrl -TimeoutSec 5',
  'Invoke-LoopbackHttp -Uri "http://${AgentHost}:$Port/plugin/nudge?type=signin&client=$Client" -Method Post -TimeoutSec 2'
)) {
  if (-not $Source.Contains($ExpectedCall)) {
    throw "missing loopback HTTP call: $ExpectedCall"
  }
}
