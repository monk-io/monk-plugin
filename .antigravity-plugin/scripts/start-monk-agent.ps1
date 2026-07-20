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

# If the agent is up but the user is not signed in to Monk, print SessionStart
# context telling the host agent to prompt the user to sign in via /mcp. Without
# this the host only sees "tools unavailable" and mis-reports it as a connection
# problem instead of an auth one. Best-effort; never blocks session start.
#
# Skippable via MONK_AGENT_SKIP_SIGNIN_NUDGE=1 — see the comment on the sh
# equivalent (emit_signin_nudge) for why hook-originated calls to an ad-hoc dev
# port aren't reliable, and why callers with an out-of-band sign-in guarantee
# (e.g. MONK_AGENT_SIMULATE_AUTH) should skip this check instead.
function Show-SigninNudge {
  if ($env:MONK_AGENT_SKIP_SIGNIN_NUDGE -eq "1") { return }
  # /auth.json is the cheap, auth-only status endpoint (~40ms). Deliberately NOT
  # /status.json, which runs ~10 synchronous install probes (~2s/call and
  # serializes under concurrent dashboard/MCP load) — that latency made this
  # check racy against a cold, signed-out agent.
  $StatusUrl = "http://${AgentHost}:$Port/auth.json"
  # A just-(re)started agent can still report a transient MISS on the first probe
  # (connection refused during the restart window, or a 500 from a cold DPAPI
  # read the agent itself retries then surfaces as an error rather than a false
  # signed-out). Both show up here as an EMPTY body, so retry only on empty. A
  # non-empty body is a definitive answer — signed in OR out — and must be acted
  # on immediately: retrying a confirmed signedIn:false just adds latency on
  # precisely the signed-out path this nudge targets. TimeoutSec is modest
  # because /auth.json is ~40ms; this also bounds how long a hung endpoint can
  # block the synchronous SessionStart hook (<=3x5s + 2x1s).
  $Body = ""
  for ($Attempt = 0; $Attempt -lt 3; $Attempt++) {
    try {
      $Response = Invoke-WebRequest -Uri $StatusUrl -UseBasicParsing -TimeoutSec 5
      $Body = $Response.Content
    } catch {
      $Body = ""
    }
    if ($Body) {
      break
    }
    if ($Attempt -lt 2) {
      Start-Sleep -Seconds 1
    }
  }
  # Empty body = read error / 500 / timeout, NOT a confirmed signed-out state —
  # suppress the nudge. Only a definitive answer reaches the decision below.
  if (-not $Body) {
    return
  }
  # PowerShell has a native JSON parser (unlike the POSIX-sh sibling, which is
  # stuck string-matching), so decide structurally: an unparseable payload is
  # treated as non-definitive (suppress), and only a truthy signedIn returns
  # without nudging — an explicit signedIn:false falls through to the nudge.
  try {
    $Auth = $Body | ConvertFrom-Json
  } catch {
    return
  }
  if ($Auth.signedIn) {
    return
  }
  $Client = if ($env:CLAUDE_PLUGIN_ROOT) { "claude-code" } elseif ($env:PLUGIN_ROOT) { "codex" } else { "unknown" }
  try {
    Invoke-RestMethod -Uri "http://${AgentHost}:$Port/plugin/nudge?type=signin&client=$Client" -Method Post -TimeoutSec 2 | Out-Null
  } catch {
  }
  $Msg = "monk-agent is running but you are NOT signed in to Monk. The Monk MCP tools require sign-in. If the user asks to deploy, analyze, or operate anything with Monk, first tell them to run /mcp and authenticate the monk MCP server (this signs them in to Monk). Do NOT describe this as a connection or restart problem, and do NOT deploy via Docker or another platform to work around it."
  if ($env:CLAUDE_PLUGIN_ROOT) {
    @{ hookSpecificOutput = @{ hookEventName = "SessionStart"; additionalContext = $Msg } } | ConvertTo-Json -Compress -Depth 4 | Write-Output
  } else {
    Write-Output $Msg
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

# Single-instance guard. On Windows-with-bash, Claude Code fires BOTH SessionStart
# entries: this .ps1 directly, and start-monk-agent.sh which on MINGW/MSYS/CYGWIN
# re-execs this same .ps1. On a cold start (agent down) the two launchers would
# otherwise both install and `serve`, racing on the binary and the port. Serialize
# them on a per-port named mutex: the first launcher installs/starts while the
# second blocks here, then proceeds and no-ops at the "already running" check
# below. The OS releases the mutex when the holder exits, so the script's many
# `exit` points need no explicit unlock.
$LauncherMutex = New-Object System.Threading.Mutex($false, "Local\monk-agent-launcher-$Port")
try {
  [void]$LauncherMutex.WaitOne([TimeSpan]::FromSeconds(190))
} catch [System.Threading.AbandonedMutexException] {
  # A previous holder died mid-start; we now own the mutex and continue.
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
  Show-SigninNudge
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

$Deadline = [DateTimeOffset]::UtcNow.AddSeconds(170).ToUnixTimeSeconds()
while ([DateTimeOffset]::UtcNow.ToUnixTimeSeconds() -lt $Deadline) {
  if (Test-AgentRunning) {
    Show-SigninNudge
    exit 0
  }
  if ($Process.HasExited) {
    break
  }
  Start-Sleep -Seconds 1
}

Write-Error "monk-agent did not become ready at $HealthUrl within 170s. Logs: $LogOut, $LogErr"
exit 1
