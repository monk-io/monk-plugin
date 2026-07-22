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
$HealthUrl = "http://${AgentHost}:$Port/.well-known/oauth-protected-resource"
$HealthResource = "http://${AgentHost}:$Port/mcp"

function Write-Json {
  param([object]$Object)
  $Object | ConvertTo-Json -Compress -Depth 6 | Write-Output
}

function Test-AgentRunning {
  try {
    $Response = Invoke-WebRequest -Uri $HealthUrl -UseBasicParsing -TimeoutSec 2
    $Document = $Response.Content | ConvertFrom-Json -ErrorAction Stop
    return [string]$Document.resource -ceq $HealthResource
  } catch {
    return $false
  }
}

# Fast path - already up. No telemetry here: this is a PreInvocation hook that
# fires per model step, so emitting on the warm path would spam. The beacon fires
# only on the cold-start paths below (install-needed / (re)start), which is the
# meaningful "launcher started" signal for Antigravity.
if (Test-AgentRunning) {
  Write-Output "{}"
  exit 0
}

# Cold start - emit the earliest plugin_launcher_started beacon before doing any
# work. Shared helper, best-effort; writes no stdout so the hook's JSON stays
# clean. launch_client is hardcoded because this hook is Antigravity-specific.
$ScriptDir = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }
$TelemetryHelper = Join-Path (Split-Path -Parent $ScriptDir) "scripts\monk-launcher-telemetry.ps1"
if (Test-Path $TelemetryHelper) {
  . $TelemetryHelper
  Invoke-MonkLauncherEvent -Client "antigravity"
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

$Process = $null
try {
  $Process = Start-Process `
    -FilePath $AgentPath `
    -ArgumentList @("serve", "--host", $AgentHost, "--port", $Port) `
    -WindowStyle Hidden `
    -RedirectStandardOutput $LogOut `
    -RedirectStandardError $LogErr `
    -PassThru
} catch {
}

# Wait briefly for the agent to become reachable. If the process exits early or
# the health endpoint never responds, report an attempted start with a pointer
# to the logs instead of a false "has been started".
if ($Process -and -not $Process.HasExited) {
  for ($i = 0; $i -lt 10; $i++) {
    Start-Sleep -Seconds 1
    if ($Process.HasExited) { break }
    if (Test-AgentRunning) {
      Write-Json @{
        injectSteps = @(
          @{ ephemeralMessage = "monk-agent was not running and has been started. It may take a few seconds to initialize - use monk.install.status or monk.runtime.status to check readiness before issuing Monk operations." }
        )
      }
      exit 0
    }
  }
}

Write-Json @{
  injectSteps = @(
    @{ ephemeralMessage = "monk-agent was started but did not become ready within 10 seconds. Check monk.install.status or monk.runtime.status for details, or the launcher logs under $LogDir." }
  )
}
exit 0
