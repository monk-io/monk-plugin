$ErrorActionPreference = "Stop"

$Port = if ($env:MONK_AGENT_PORT) { $env:MONK_AGENT_PORT } else { "7419" }
$AgentHost = if ($env:MONK_AGENT_HOST) { $env:MONK_AGENT_HOST } else { "127.0.0.1" }
$AuthUrl = if ($env:MONK_AUTH_URL) { $env:MONK_AUTH_URL } else { "https://auth.monk.io" }
$AuthClientId = if ($env:MONK_AGENT_AUTH_CLIENT_ID) { $env:MONK_AGENT_AUTH_CLIENT_ID } else { "UW84YWcJME3buMSLfqLX8IbBsYdNWi47" }
$AuthAudience = if ($env:MONK_AUTH_AUDIENCE) { $env:MONK_AUTH_AUDIENCE } else { "oaknode.com" }
$AutospinUrl = if ($env:MONK_AUTOSPIN_URL) { $env:MONK_AUTOSPIN_URL } else { "wss://api.app.monk.io/autospin/" }

# Host hooks terminate this launcher after 180 seconds. Reserve enough time for
# this script to emit its own startup diagnostics instead of being killed
# mid-wait (ENG-410).
$ReadyTimeoutSec = 150
$RequestedReadyTimeout = 0
if ($env:MONK_AGENT_READY_TIMEOUT -and
    [int]::TryParse($env:MONK_AGENT_READY_TIMEOUT, [ref]$RequestedReadyTimeout)) {
  $ReadyTimeoutSec = [Math]::Max(1, [Math]::Min(150, $RequestedReadyTimeout))
}

$ScriptDir = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }
$PluginRoot = if ($env:CLAUDE_PLUGIN_ROOT) { $env:CLAUDE_PLUGIN_ROOT } else { Split-Path -Parent $ScriptDir }
$InstallDir = if ($env:MONK_AGENT_INSTALL_DIR) { $env:MONK_AGENT_INSTALL_DIR } else { Join-Path $HOME ".monk\bin" }
$MonkHome = if ($env:MONK_AGENT_HOME) { $env:MONK_AGENT_HOME } else { Join-Path $HOME ".monk" }

# Rendered at plugin build time; sets $env:MONK_PLUGIN_VERSION so both the
# launcher telemetry beacon (below) and the spawned agent can report the real
# plugin version. Guarded: an older rendered plugin without the file must still
# launch (the agent falls back to a labeled agent-binary version). Dot-sourced
# early so the value is set before the telemetry emit and the agent spawn. The
# PowerShell counterpart of the plugin-version.sh source in start-monk-agent.sh.
$PluginVersionScript = Join-Path $ScriptDir "plugin-version.ps1"
if (Test-Path $PluginVersionScript) { . $PluginVersionScript }
$PluginVersion = if ($env:MONK_PLUGIN_VERSION) { $env:MONK_PLUGIN_VERSION } else { "" }

$DataDir = Join-Path $MonkHome "agent\launcher"
$LogDir = Join-Path $DataDir "logs"
$RunDir = Join-Path $DataDir "run"
$LogOut = Join-Path $LogDir "monk-agent.out.log"
$LogErr = Join-Path $LogDir "monk-agent.err.log"
$PidFile = Join-Path $RunDir "monk-agent.pid"
$StateFile = Join-Path $RunDir "monk-agent.state"
# IPv6 loopback hosts (e.g. ::1, an explicit MONK_AGENT_HOST override) must be
# bracketed in a URL authority or the port separator is ambiguous.
$UrlHost = if ($AgentHost.Contains(":") -and -not ($AgentHost.StartsWith("[") -and $AgentHost.EndsWith("]"))) {
  "[$AgentHost]"
} else {
  $AgentHost
}
$BaseUrl = "http://${UrlHost}:$Port"
$HealthUrl = "$BaseUrl/.well-known/oauth-protected-resource"
$HealthResource = "$BaseUrl/mcp"

# Proxy-bypass arguments for the loopback probes below, splatted so the flag is
# only passed where it exists. -NoProxy is PowerShell 6+ only, but these hooks run
# under Windows PowerShell 5.1 (pinned by run-powershell.cmd / the MINGW re-exec in
# start-monk-agent.sh, ENG-441), where it raises ParameterBindingException — which
# the probes' own catch blocks swallowed, so every health check returned a
# permanent $false: the agent was killed and respawned every session and the
# readiness loop below burned its full timeout and exited 1 (ENG-469).
#
# Omitting it on 5.1 does NOT reintroduce plugin#8 (loopback probes routed through
# a user's proxy). Verified on 5.1.19041: .NET Framework ignores
# http_proxy/https_proxy/all_proxy entirely, and for the system/DefaultWebProxy path
# it bypasses loopback destinations unconditionally — WebProxy.IsBypassed is $true
# for 127.0.0.1 and localhost even with BypassProxyOnLocal=$false. On PowerShell 7
# both of those protections are absent (env proxies are honored, IsBypassed is
# $false), which is exactly where -NoProxy is still required, so it is still passed.
#
# Probed by capability, not by $PSVersionTable: this asks the interpreter that will
# actually run the call, so it cannot be wrong about a version boundary.
$ProxyArgs = @{}
if ((Get-Command Invoke-WebRequest).Parameters.ContainsKey("NoProxy")) {
  $ProxyArgs["NoProxy"] = $true
}

# A usage error (unknown parameter, missing cmdlet) is a bug in this script, not
# evidence about the agent's health. The probes below must not translate one into a
# plausible-looking "agent is down" answer — that is precisely how the -NoProxy
# regression hid for two weeks. Transport failures still fall through to the
# caller's own default.
function Test-ProbeUsageError {
  param([System.Management.Automation.ErrorRecord]$ErrorRecord)
  $Exception = $ErrorRecord.Exception
  if ($Exception -is [System.Management.Automation.ParameterBindingException] -or
      $Exception -is [System.Management.Automation.CommandNotFoundException]) {
    throw $ErrorRecord
  }
}

New-Item -ItemType Directory -Force -Path $LogDir, $RunDir | Out-Null

# Client whose hook fired this launcher. Order matters: Cursor sets
# CLAUDE_PLUGIN_ROOT as a Claude-compat shim (verified, see
# docs/plugin-hooks-per-client.md), so it MUST be detected via CURSOR_* before
# the CLAUDE_PLUGIN_ROOT check or it is misreported as claude-code. Used by the
# launcher telemetry event, the MONK_AGENT_LAUNCH_CLIENT hand-off, and the nudge.
$Client = if ($env:CURSOR_VERSION -or $env:CURSOR_PLUGIN_ROOT) {
  "cursor"
} elseif ($env:CLAUDE_PLUGIN_ROOT) {
  "claude-code"
} elseif ($env:PLUGIN_ROOT) {
  "codex"
} else {
  "unknown"
}
$IdeVersion = if ($env:CURSOR_VERSION) { $env:CURSOR_VERSION } else { "" }

function Test-AgentRunning {
  try {
    $Response = Invoke-WebRequest -Uri $HealthUrl -UseBasicParsing -TimeoutSec 2 @ProxyArgs
    # Require the resource field to equal our own MCP endpoint, not merely be
    # present — an unrelated service on the same port could otherwise be
    # mistaken for monk-agent.
    $Document = $Response.Content | ConvertFrom-Json -ErrorAction Stop
    return [string]$Document.resource -ceq $HealthResource
  } catch {
    Test-ProbeUsageError $_
    return $false
  }
}

# Register monk in Antigravity's global MCP config if ~/.gemini/config/ exists.
# POSIX parity: start-monk-agent.sh has had register_antigravity_mcp() since
# ENG-391/ENG-393/ENG-395/ENG-402; this launcher had no equivalent at all
# (ENG-451). Idempotent — skips if already registered at the current URL, and
# refreshes a stale URL from a prior host/port. Uses ConvertFrom-Json /
# ConvertTo-Json (always available in Windows PowerShell 5.1+) rather than
# jq/python3 shell-outs.
function Register-AntigravityMcp {
  $ConfigDir = Join-Path $HOME ".gemini\config"
  if (-not (Test-Path $ConfigDir)) { return }

  $ConfigPath = Join-Path $ConfigDir "mcp_config.json"
  $ServerUrl = $HealthResource
  if ((Test-Path $ConfigPath) -and (Get-Item $ConfigPath).Length) {
    try {
      $Config = Get-Content -Raw $ConfigPath | ConvertFrom-Json
    } catch {
      Write-Warning "Could not register Monk MCP server because $ConfigPath is not valid JSON."
      return
    }
    if ($null -eq $Config -or $Config.GetType().FullName -ne "System.Management.Automation.PSCustomObject") {
      Write-Warning "Could not register Monk MCP server because $ConfigPath is not a JSON object."
      return
    }
  } else {
    $Config = [pscustomobject]@{}
  }
  if ($null -eq $Config.mcpServers -or $Config.mcpServers.GetType().FullName -ne "System.Management.Automation.PSCustomObject") {
    Add-Member -InputObject $Config -NotePropertyName mcpServers -NotePropertyValue ([pscustomobject]@{}) -Force
  }
  if ($Config.mcpServers.PSObject.Properties.Name -contains "monk") {
    if ($Config.mcpServers.monk.serverUrl -eq $ServerUrl) { return }
    if ($null -ne $Config.mcpServers.monk -and $Config.mcpServers.monk.GetType().FullName -eq "System.Management.Automation.PSCustomObject") {
      Add-Member -InputObject $Config.mcpServers.monk -NotePropertyName serverUrl -NotePropertyValue $ServerUrl -Force
    } else {
      $Config.mcpServers.monk = [pscustomobject]@{ serverUrl = $ServerUrl }
    }
  } else {
    Add-Member -InputObject $Config.mcpServers -NotePropertyName monk -NotePropertyValue ([pscustomobject]@{ serverUrl = $ServerUrl })
  }
  $TempPath = "$ConfigPath.tmp-$PID"
  try {
    $Config | ConvertTo-Json -Depth 100 | Set-Content -Encoding UTF8 $TempPath
    Move-Item -Force $TempPath $ConfigPath
  } finally {
    Remove-Item -Force $TempPath -ErrorAction SilentlyContinue
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
  $StatusUrl = "$BaseUrl/auth.json"
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
      $Response = Invoke-WebRequest -Uri $StatusUrl -UseBasicParsing -TimeoutSec 5 @ProxyArgs
      $Body = $Response.Content
    } catch {
      Test-ProbeUsageError $_
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
  # $Client is resolved once at the top of the script (Cursor-aware ordering).
  # Stays fully best-effort (no Test-ProbeUsageError): this line is only reached
  # after the /auth.json probe above already bound @ProxyArgs successfully on this
  # interpreter, so a usage error here is unreachable — and throwing would cost the
  # user the nudge message below, which is the part that actually matters.
  try {
    Invoke-RestMethod -Uri "$BaseUrl/plugin/nudge?type=signin&client=$Client" -Method Post -TimeoutSec 2 @ProxyArgs | Out-Null
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

function Test-SameFilePath {
  param([string]$Actual, [string]$Expected)
  if (-not $Actual -or -not $Expected) {
    return $false
  }
  try {
    return [string]::Equals(
      [IO.Path]::GetFullPath($Actual),
      [IO.Path]::GetFullPath($Expected),
      [StringComparison]::OrdinalIgnoreCase
    )
  } catch {
    return $false
  }
}

function Get-RecordedAgentPath {
  param([string]$FallbackPath)
  if (-not (Test-Path $StateFile)) {
    return $FallbackPath
  }
  $State = Get-Content -Raw $StateFile -ErrorAction SilentlyContinue
  foreach ($Line in ($State -split "`r?`n")) {
    if ($Line.StartsWith("agent_path=", [StringComparison]::Ordinal)) {
      $RecordedPath = $Line.Substring("agent_path=".Length)
      if ($RecordedPath) {
        return $RecordedPath
      }
    }
  }
  return $FallbackPath
}

function Stop-ManagedAgent {
  if (-not (Test-Path $PidFile)) {
    return
  }

  $RawPid = (Get-Content -Raw $PidFile).Trim()
  if (-not $RawPid) {
    return
  }

  # Validate the PID is numeric before casting; a malformed PID file (text,
  # whitespace, BOM artifacts) would otherwise throw a terminating error under
  # ErrorActionPreference = "Stop". Treat non-numeric content as stale state.
  $ParsedPid = 0
  if (-not [int]::TryParse($RawPid, [ref]$ParsedPid) -or $ParsedPid -le 0) {
    Remove-Item -Force $PidFile -ErrorAction SilentlyContinue
    return
  }

  $OldProcess = Get-Process -Id $ParsedPid -ErrorAction SilentlyContinue
  if (-not $OldProcess) {
    return
  }

  $ProcessPath = ""
  try {
    $ProcessPath = $OldProcess.Path
  } catch {
    $ProcessPath = ""
  }

  # The recorded PID belongs to the executable from the previous launch. When
  # MONK_AGENT_PATH changes from A to B, validate ownership against A so it can
  # be stopped before B is started.
  $ExpectedProcessPath = Get-RecordedAgentPath $AgentPath
  if (Test-SameFilePath $ProcessPath $ExpectedProcessPath) {
    Stop-Process -Id $OldProcess.Id -Force -ErrorAction SilentlyContinue
    try {
      Wait-Process -Id $OldProcess.Id -Timeout 10 -ErrorAction SilentlyContinue
    } catch {
      Start-Sleep -Milliseconds 500
    }
  }
}

# Earliest telemetry signal: the plugin_launcher_started beacon lives in a shared,
# dot-sourced helper (monk-launcher-telemetry.ps1) reused by the Antigravity hook.
# Guarded on presence for older rendered plugins. Invoked below under the launcher
# mutex so the per-session dedup marker is race-free against the .ps1/.sh
# double-fire. Best-effort inside its own try/catch — never aborts the launch.
$TelemetryHelper = Join-Path $ScriptDir "monk-launcher-telemetry.ps1"
if (Test-Path $TelemetryHelper) {
  . $TelemetryHelper
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
  $LauncherMutexAcquired = $LauncherMutex.WaitOne([TimeSpan]::FromSeconds(190))
} catch [System.Threading.AbandonedMutexException] {
  # A previous holder died mid-start; we now own the mutex and continue.
  $LauncherMutexAcquired = $true
}
if (-not $LauncherMutexAcquired) {
  Write-Error "Timed out waiting for another monk-agent launcher on port $Port to finish."
  exit 1
}

$ManagedAgentPath = Join-Path $InstallDir "monk-agent.exe"
$AgentHashBefore = ""
$ManagedAgentEnsured = $false

if (Get-Command Invoke-MonkLauncherEvent -ErrorAction SilentlyContinue) {
  Invoke-MonkLauncherEvent -Client $Client -IdeVersion $IdeVersion
}

if ($env:MONK_AGENT_PATH) {
  $AgentPath = $env:MONK_AGENT_PATH
} elseif ($env:MONK_AGENT_SKIP_ENSURE -eq "1") {
  $AgentPath = $ManagedAgentPath
} else {
  # Only the managed install can have been updated by ensure-monk-agent.ps1,
  # so only compute a before/after hash on that path. Hashing the managed
  # binary's "before" state against a custom MONK_AGENT_PATH's "after" state
  # compares two unrelated files -- they always differ, so AgentUpdated was
  # always true and every session force-restarted a healthy custom companion
  # (ENG-390).
  $AgentHashBefore = Get-FileSha256 $ManagedAgentPath
  $EnsureScript = Join-Path $PluginRoot "scripts\ensure-monk-agent.ps1"
  if (-not (Test-Path $EnsureScript)) {
    Write-Error "monk-agent installer not found at $EnsureScript"
    exit 2
  }
  $AgentPath = (& $EnsureScript | Select-Object -Last 1)
  $ManagedAgentEnsured = $true
}

$AgentPath = [string]$AgentPath
if (-not (Test-Path $AgentPath)) {
  Write-Error "monk-agent is not installed at $AgentPath"
  exit 2
}

$AgentUpdated = $false
if ($ManagedAgentEnsured) {
  $AgentHashAfter = Get-FileSha256 $AgentPath
  $AgentUpdated = $AgentHashAfter -and ($AgentHashBefore -ne $AgentHashAfter)
}

# There is no launchd-style config store to introspect on Windows, so the
# fields that matter for reuse are persisted to $StateFile on every start and
# diffed here. Covers both a stale custom MONK_AGENT_PATH and drifted
# auth/autospin config on an otherwise-healthy companion (ENG-390, ENG-397).
function Test-BackgroundStateConfigured {
  if (-not (Test-Path $StateFile)) {
    return $false
  }
  $State = Get-Content -Raw $StateFile -ErrorAction SilentlyContinue
  if (-not $State) {
    return $false
  }
  $Expected = @(
    "agent_path=$AgentPath",
    "auth_url=$AuthUrl",
    "auth_client_id=$AuthClientId",
    "auth_audience=$AuthAudience",
    "autospin_url=$AutospinUrl",
    "plugin_version=$PluginVersion"
  )
  $Lines = $State -split "`r?`n"
  foreach ($Line in $Expected) {
    if (-not ($Lines -ccontains $Line)) {
      return $false
    }
  }
  return $true
}

if (-not $AgentUpdated -and (Test-BackgroundStateConfigured) -and (Test-AgentRunning)) {
  Register-AntigravityMcp
  Show-SigninNudge
  exit 0
}

Stop-ManagedAgent

$env:MONK_AUTH_URL = $AuthUrl
$env:MONK_AGENT_AUTH_CLIENT_ID = $AuthClientId
$env:MONK_AUTH_AUDIENCE = $AuthAudience
$env:MONK_AUTOSPIN_URL = $AutospinUrl
$env:MONK_AGENT_LAUNCH_CLIENT = $Client
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
@(
  "agent_path=$AgentPath",
  "auth_url=$AuthUrl",
  "auth_client_id=$AuthClientId",
  "auth_audience=$AuthAudience",
  "autospin_url=$AutospinUrl",
  "plugin_version=$PluginVersion"
) -join "`n" | Set-Content -NoNewline $StateFile

$ReadyTimer = [System.Diagnostics.Stopwatch]::StartNew()
while ($ReadyTimer.Elapsed.TotalSeconds -lt $ReadyTimeoutSec) {
  if (Test-AgentRunning) {
    Register-AntigravityMcp
    Show-SigninNudge
    exit 0
  }
  if ($Process.HasExited) {
    break
  }
  Start-Sleep -Seconds 1
}

Write-Error "monk-agent did not become ready at $HealthUrl within ${ReadyTimeoutSec}s. Logs: $LogOut, $LogErr"
exit 1
