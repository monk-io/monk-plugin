# PreInvocation hook: ensure monk-agent is running before the model is called.
# Windows (stock, no Git Bash) counterpart of ensure-monk-agent.sh.
#
# Antigravity PreInvocation I/O:
#   stdin:  {"invocationNum":N,"initialNumSteps":N,"workspacePaths":[...],...}
#   stdout: {"injectSteps":[{"ephemeralMessage":"..."}]} or {}
#
# Best-effort: never throws so a hook failure cannot block the invocation.

$ErrorActionPreference = "SilentlyContinue"

# Drain stdin so Antigravity's writer never blocks, even though we ignore it.
[Console]::In.ReadToEnd() | Out-Null

# If bash is available the .sh sibling handles this; bow out silently so the two
# hooks never both emit JSON (Antigravity runs every hook in the list).
if (Get-Command bash -ErrorAction SilentlyContinue) { exit 0 }

$Port = if ($env:MONK_AGENT_PORT) { $env:MONK_AGENT_PORT } else { "7419" }
$AgentHost = if ($env:MONK_AGENT_HOST) { $env:MONK_AGENT_HOST } else { "127.0.0.1" }
$UrlHost = if ($AgentHost.Contains(":") -and -not ($AgentHost.StartsWith("[") -and $AgentHost.EndsWith("]"))) {
  "[$AgentHost]"
} else {
  $AgentHost
}
$HealthUrl = "http://${UrlHost}:$Port/.well-known/oauth-protected-resource"

function Write-Json {
  param([object]$Object)
  $Object | ConvertTo-Json -Compress -Depth 6 | Write-Output
}

function Test-AgentRunning {
  try {
    $Response = Invoke-WebRequest -Uri $HealthUrl -UseBasicParsing -TimeoutSec 2
    return $Response.Content -match '"resource"'
  } catch {
    return $false
  }
}

# Fast path - already up.
if (Test-AgentRunning) {
  Write-Output "{}"
  exit 0
}

$InstallDir = if ($env:MONK_AGENT_INSTALL_DIR) { $env:MONK_AGENT_INSTALL_DIR } else { Join-Path $HOME ".monk\bin" }
$AgentPath = if ($env:MONK_AGENT_PATH) { $env:MONK_AGENT_PATH } else { Join-Path $InstallDir "monk-agent.exe" }

if (-not (Test-Path $AgentPath)) {
  $ScriptDir = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }
  $PluginDir = Split-Path -Parent $ScriptDir
  $StartScript = Join-Path $PluginDir "scripts\start-monk-agent.ps1"
  Write-Json @{
    injectSteps = @(
      @{ ephemeralMessage = "monk-agent is not installed. Run `"$StartScript`" once to install and start it, then continue." }
    )
  }
  exit 0
}

# Binary present but not running - start it directly (do not wait).
$MonkHome = if ($env:MONK_AGENT_HOME) { $env:MONK_AGENT_HOME } else { Join-Path $HOME ".monk" }
$LogDir = Join-Path $MonkHome "agent\launcher\logs"
New-Item -ItemType Directory -Force -Path $LogDir | Out-Null
$LogOut = Join-Path $LogDir "monk-agent.out.log"
$LogErr = Join-Path $LogDir "monk-agent.err.log"

$env:MONK_AUTH_URL = if ($env:MONK_AUTH_URL) { $env:MONK_AUTH_URL } else { "https://auth.monk.io" }
$env:MONK_AGENT_AUTH_CLIENT_ID = if ($env:MONK_AGENT_AUTH_CLIENT_ID) { $env:MONK_AGENT_AUTH_CLIENT_ID } else { "UW84YWcJME3buMSLfqLX8IbBsYdNWi47" }
$env:MONK_AUTH_AUDIENCE = if ($env:MONK_AUTH_AUDIENCE) { $env:MONK_AUTH_AUDIENCE } else { "oaknode.com" }
$env:MONK_AUTOSPIN_URL = if ($env:MONK_AUTOSPIN_URL) { $env:MONK_AUTOSPIN_URL } else { "wss://api.app.monk.io/autospin/" }

try {
  Start-Process `
    -FilePath $AgentPath `
    -ArgumentList @("serve", "--host", $AgentHost, "--port", $Port) `
    -WindowStyle Hidden `
    -RedirectStandardOutput $LogOut `
    -RedirectStandardError $LogErr | Out-Null
} catch {
}

Write-Json @{
  injectSteps = @(
    @{ ephemeralMessage = "monk-agent was not running and has been started. It may take a few seconds to initialize - use monk.install.status or monk.runtime.status to check readiness before issuing Monk operations." }
  )
}
exit 0
