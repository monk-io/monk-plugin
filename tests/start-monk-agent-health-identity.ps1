param(
  [Parameter(Mandatory = $true)]
  [string]$AgentPath,
  [string]$RepoRoot
)

$ErrorActionPreference = "Stop"
if (-not $RepoRoot) {
  $RepoRoot = Split-Path -Parent $PSScriptRoot
}
$TempRoot = Join-Path ([IO.Path]::GetTempPath()) ("monk-health-identity-" + [guid]::NewGuid())
$InstallDir = Join-Path $TempRoot "bin"
$AgentHome = Join-Path $TempRoot "home"
$Launcher = Join-Path $RepoRoot "scripts\start-monk-agent.ps1"
$ManagedAgent = Join-Path $InstallDir "monk-agent.exe"
$PidFile = Join-Path $AgentHome "agent\launcher\run\monk-agent.pid"
$Wrapper = Join-Path $TempRoot "run-launcher.ps1"
$Port = "17425"
$ExpectedResource = "http://127.0.0.1:$Port/mcp"
$Previous = @{}
$Names = @(
  "MONK_AGENT_HOME",
  "MONK_AGENT_INSTALL_DIR",
  "MONK_AGENT_PORT",
  "MONK_AGENT_SKIP_ENSURE",
  "MONK_AGENT_SKIP_SIGNIN_NUDGE",
  "MONK_AGENT_DEV",
  "MONK_AGENT_SIMULATE_AUTH",
  "MONK_AGENT_MOCK_RUNTIME",
  "MONK_AGENT_VAULT_BACKEND",
  "MONK_AGENT_STORE",
  "MONK_AGENT_OPEN_BROWSER",
  "MONK_TELEMETRY",
  "TEST_LAUNCHER",
  "TEST_PID_FILE",
  "TEST_EXPECTED_RESOURCE"
)

foreach ($Name in $Names) {
  $Previous[$Name] = [Environment]::GetEnvironmentVariable($Name)
}

try {
  if (-not (Test-Path -LiteralPath $AgentPath)) {
    throw "monk-agent test executable not found: $AgentPath"
  }

  New-Item -ItemType Directory -Force -Path $InstallDir | Out-Null
  Copy-Item -LiteralPath $AgentPath -Destination $ManagedAgent

  @'
$ErrorActionPreference = "Stop"
$PidFile = $env:TEST_PID_FILE
function global:Invoke-WebRequest {
  param(
    [string]$Uri,
    [switch]$UseBasicParsing,
    [int]$TimeoutSec
  )
  if (Test-Path -LiteralPath $PidFile) {
    return [pscustomobject]@{ Content = ('{{"resource":"{0}"}}' -f $env:TEST_EXPECTED_RESOURCE) }
  }
  return [pscustomobject]@{ Content = '{"resource":"http://127.0.0.1:9999/not-monk"}' }
}
& $env:TEST_LAUNCHER
'@ | Set-Content -LiteralPath $Wrapper

  $env:MONK_AGENT_HOME = $AgentHome
  $env:MONK_AGENT_INSTALL_DIR = $InstallDir
  $env:MONK_AGENT_PORT = $Port
  $env:MONK_AGENT_SKIP_ENSURE = "1"
  $env:MONK_AGENT_SKIP_SIGNIN_NUDGE = "1"
  $env:MONK_AGENT_DEV = "1"
  $env:MONK_AGENT_SIMULATE_AUTH = "1"
  $env:MONK_AGENT_MOCK_RUNTIME = "1"
  $env:MONK_AGENT_VAULT_BACKEND = "file"
  $env:MONK_AGENT_STORE = "file"
  $env:MONK_AGENT_OPEN_BROWSER = "0"
  $env:MONK_TELEMETRY = "0"
  $env:TEST_LAUNCHER = $Launcher
  $env:TEST_PID_FILE = $PidFile
  $env:TEST_EXPECTED_RESOURCE = $ExpectedResource

  & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $Wrapper
  if ($LASTEXITCODE -ne 0) {
    throw "launcher subprocess failed with exit code $LASTEXITCODE"
  }
  if (-not (Test-Path -LiteralPath $PidFile)) {
    throw "launcher accepted an unrelated resource without starting monk-agent"
  }

  $AgentPid = [int](Get-Content -Raw -LiteralPath $PidFile)
  $Process = Get-Process -Id $AgentPid -ErrorAction Stop
  if ($Process.HasExited) {
    throw "launcher-created monk-agent exited before identity validation completed"
  }
} finally {
  if ($AgentPid) {
    Stop-Process -Id $AgentPid -Force -ErrorAction SilentlyContinue
  }
  foreach ($Name in $Names) {
    [Environment]::SetEnvironmentVariable($Name, $Previous[$Name])
  }
  Remove-Item -LiteralPath $TempRoot -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host "Windows launcher rejects an unrelated health resource."
