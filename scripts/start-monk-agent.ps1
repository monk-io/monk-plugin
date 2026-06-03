$ErrorActionPreference = "Stop"

$Port = if ($env:MONK_AGENT_PORT) { $env:MONK_AGENT_PORT } else { "7419" }
$AgentHost = if ($env:MONK_AGENT_HOST) { $env:MONK_AGENT_HOST } else { "127.0.0.1" }
$AuthUrl = if ($env:MONK_AUTH_URL) { $env:MONK_AUTH_URL } else { "https://auth.monk.io" }
$AuthClientId = if ($env:MONK_AGENT_AUTH_CLIENT_ID) { $env:MONK_AGENT_AUTH_CLIENT_ID } else { "UW84YWcJME3buMSLfqLX8IbBsYdNWi47" }
$AuthAudience = if ($env:MONK_AUTH_AUDIENCE) { $env:MONK_AUTH_AUDIENCE } else { "oaknode.com" }
$AutospinUrl = if ($env:MONK_AUTOSPIN_URL) { $env:MONK_AUTOSPIN_URL } else { "wss://api.app.monk.io/autospin/" }

$ScriptDir = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }
$PluginRoot = if ($env:CLAUDE_PLUGIN_ROOT) { $env:CLAUDE_PLUGIN_ROOT } else { Split-Path -Parent $ScriptDir }
$InstallDir = if ($env:MONK_AGENT_INSTALL_DIR) { $env:MONK_AGENT_INSTALL_DIR } else { Join-Path $HOME ".monk\bin" }
$MonkHome = if ($env:MONK_AGENT_HOME) { $env:MONK_AGENT_HOME } else { Join-Path $HOME ".monk" }

$DataDir = Join-Path $MonkHome "agent\launcher"
$LogDir = Join-Path $DataDir "logs"
$RunDir = Join-Path $DataDir "run"
$LogOut = Join-Path $LogDir "monk-agent.out.log"
$LogErr = Join-Path $LogDir "monk-agent.err.log"
$PidFile = Join-Path $RunDir "monk-agent.pid"
$HealthUrl = "http://${AgentHost}:$Port/.well-known/oauth-protected-resource"

New-Item -ItemType Directory -Force -Path $LogDir, $RunDir | Out-Null

function Test-AgentRunning {
  try {
    $Response = Invoke-WebRequest -Uri $HealthUrl -UseBasicParsing -TimeoutSec 2
    return $Response.Content -match '"resource"'
  } catch {
    return $false
  }
}

function Get-FileSha256 {
  param([string]$Path)
  if (-not (Test-Path $Path)) {
    return ""
  }
  if (Get-Command Get-FileHash -ErrorAction SilentlyContinue) {
    return (Get-FileHash -Algorithm SHA256 $Path).Hash.ToLowerInvariant()
  }

  $Stream = [System.IO.File]::OpenRead($Path)
  try {
    $Sha256 = [System.Security.Cryptography.SHA256]::Create()
    try {
      $Hash = $Sha256.ComputeHash($Stream)
    } finally {
      $Sha256.Dispose()
    }
  } finally {
    $Stream.Dispose()
  }
  return ([System.BitConverter]::ToString($Hash) -replace "-", "").ToLowerInvariant()
}

function Stop-ManagedAgent {
  if (-not (Test-Path $PidFile)) {
    return
  }

  $RawPid = (Get-Content -Raw $PidFile).Trim()
  if (-not $RawPid) {
    return
  }

  $OldProcess = Get-Process -Id ([int]$RawPid) -ErrorAction SilentlyContinue
  if (-not $OldProcess) {
    return
  }

  $ProcessPath = ""
  try {
    $ProcessPath = $OldProcess.Path
  } catch {
    $ProcessPath = ""
  }

  if (-not $ProcessPath -or ([IO.Path]::GetFileName($ProcessPath) -ieq "monk-agent.exe")) {
    Stop-Process -Id $OldProcess.Id -Force -ErrorAction SilentlyContinue
    try {
      Wait-Process -Id $OldProcess.Id -Timeout 10 -ErrorAction SilentlyContinue
    } catch {
      Start-Sleep -Milliseconds 500
    }
  }
}

$ManagedAgentPath = Join-Path $InstallDir "monk-agent.exe"
$AgentHashBefore = Get-FileSha256 $ManagedAgentPath

if ($env:MONK_AGENT_PATH) {
  $AgentPath = $env:MONK_AGENT_PATH
} elseif ($env:MONK_AGENT_SKIP_ENSURE -eq "1") {
  $AgentPath = $ManagedAgentPath
} else {
  $EnsureScript = Join-Path $PluginRoot "scripts\ensure-monk-agent.ps1"
  if (-not (Test-Path $EnsureScript)) {
    Write-Error "monk-agent installer not found at $EnsureScript"
    exit 2
  }
  $AgentPath = (& $EnsureScript | Select-Object -Last 1)
}

$AgentPath = [string]$AgentPath
if (-not (Test-Path $AgentPath)) {
  Write-Error "monk-agent is not installed at $AgentPath"
  exit 2
}

$AgentHashAfter = Get-FileSha256 $AgentPath
$AgentUpdated = $AgentHashAfter -and ($AgentHashBefore -ne $AgentHashAfter)

if (-not $AgentUpdated -and (Test-AgentRunning)) {
  exit 0
}

Stop-ManagedAgent

$env:MONK_AUTH_URL = $AuthUrl
$env:MONK_AGENT_AUTH_CLIENT_ID = $AuthClientId
$env:MONK_AUTH_AUDIENCE = $AuthAudience
$env:MONK_AUTOSPIN_URL = $AutospinUrl
if ($env:PATH -notlike "*$InstallDir*") {
  $env:PATH = "$InstallDir;$env:PATH"
}

$Arguments = @("serve", "--host", $AgentHost, "--port", $Port)
$Process = Start-Process `
  -FilePath $AgentPath `
  -ArgumentList $Arguments `
  -PassThru `
  -WindowStyle Hidden `
  -RedirectStandardOutput $LogOut `
  -RedirectStandardError $LogErr

$Process.Id | Set-Content -NoNewline $PidFile

for ($Attempt = 0; $Attempt -lt 30; $Attempt++) {
  if (Test-AgentRunning) {
    exit 0
  }
  if ($Process.HasExited) {
    break
  }
  Start-Sleep -Seconds 1
}

Write-Error "monk-agent did not become ready at $HealthUrl within 30s. Logs: $LogOut, $LogErr"
exit 1
