# Shared launcher telemetry, DOT-SOURCED (not executed) by start-monk-agent.ps1
# and the Antigravity PreInvocation hook. Defines Invoke-MonkLauncherEvent, which
# fires the earliest possible "plugin_launcher_started" beacon straight to
# PostHog — before ensure/serve — so plugin activity is visible even if the
# download fails or the agent crashes on init.
#
# Contract: entirely best-effort inside try/catch; never throws, never writes to
# stdout (the Antigravity hook's stdout must stay pure JSON). Mirrors the agent's
# own telemetry config (MONK_POSTHOG_HOST/KEY and the MONK_DISABLE_ANALYTICS /
# MONK_TELEMETRY / MONK_AGENT_TELEMETRY opt-outs).

function Invoke-MonkLauncherEvent {
  param(
    [string]$Client = "unknown",
    [string]$IdeVersion = ""
  )
  if ($env:MONK_DISABLE_ANALYTICS -eq "1" -or $env:MONK_TELEMETRY -eq "0" -or $env:MONK_AGENT_TELEMETRY -eq "0") {
    return
  }
  try {
    $PhHost = if ($env:MONK_POSTHOG_HOST) { $env:MONK_POSTHOG_HOST.TrimEnd("/") } else { "https://us.i.posthog.com" }
    $PhKey = if ($env:MONK_POSTHOG_KEY) { $env:MONK_POSTHOG_KEY } else { "phc_VQNP031TPUwNQcWy0RAaKl05b5g67l7rgyzfvk804fn" }
    $MonkHome = if ($env:MONK_AGENT_HOME) { $env:MONK_AGENT_HOME } else { Join-Path $HOME ".monk" }
    $DataDir = Join-Path $MonkHome "agent\launcher"
    $InstallDir = if ($env:MONK_AGENT_INSTALL_DIR) { $env:MONK_AGENT_INSTALL_DIR } else { Join-Path $HOME ".monk\bin" }
    $ManagedAgentPath = Join-Path $InstallDir "monk-agent.exe"
    New-Item -ItemType Directory -Force -Path $DataDir -ErrorAction SilentlyContinue | Out-Null

    # Dedup the .ps1/.sh SessionStart double-fire (and any rapid re-run) into one
    # event per session: skip if the marker was touched under ~15s ago. Genuine
    # restarts (minutes apart) still emit. The launch itself proceeds regardless.
    $EmitMarker = Join-Path $DataDir "last-launch-emit"
    if (Test-Path $EmitMarker) {
      $Age = (Get-Date) - (Get-Item $EmitMarker).LastWriteTime
      if ($Age.TotalSeconds -lt 15) {
        return
      }
    }
    Set-Content -Path $EmitMarker -Value (Get-Date -Format o) -ErrorAction SilentlyContinue

    # first_start (once-ever, distinct from the per-session dedup above): true
    # only when neither this marker NOR a managed binary exists, so installs
    # predating the marker don't report a false first install.
    $FirstMarker = Join-Path $DataDir "first-start"
    $FirstStart = (-not (Test-Path $FirstMarker)) -and (-not (Test-Path $ManagedAgentPath))
    if (-not (Test-Path $FirstMarker)) {
      Set-Content -Path $FirstMarker -Value (Get-Date -Format o) -ErrorAction SilentlyContinue
    }
    $AgentInstalled = [bool](Test-Path $ManagedAgentPath)

    # distinct_id: reuse the agent's stored anon client id so launcher and agent
    # events unify under one identity; ephemeral fallback (true first run, or the
    # sqlite backend with no client.json), flagged via client_id_source.
    $ClientId = ""
    $ClientFile = Join-Path $MonkHome "agent\store\global\telemetry\client.json"
    if (Test-Path $ClientFile) {
      try {
        $ClientId = (Get-Content -Raw $ClientFile | ConvertFrom-Json).clientId
      } catch {
        $ClientId = ""
      }
    }
    $ClientIdSource = "store"
    if (-not $ClientId) {
      $ClientIdSource = "ephemeral"
      $ClientId = [guid]::NewGuid().ToString()
    }

    $Payload = @{
      api_key     = $PhKey
      event       = "plugin_launcher_started"
      distinct_id = $ClientId
      properties  = @{
        launch_client    = $Client
        host_client      = $Client
        client           = $Client
        first_start      = $FirstStart
        agent_installed  = $AgentInstalled
        client_id_source = $ClientIdSource
        plugin_version   = $(if ($env:MONK_PLUGIN_VERSION) { $env:MONK_PLUGIN_VERSION } else { "" })
        ide_version      = $IdeVersion
        platform         = "windows"
        os_arch          = $(if ($env:PROCESSOR_ARCHITECTURE) { $env:PROCESSOR_ARCHITECTURE } else { "unknown" })
        source           = "monk-plugin-launcher"
      }
    } | ConvertTo-Json -Compress -Depth 5
    Invoke-RestMethod -Uri "$PhHost/capture/" -Method Post -ContentType "application/json" -Body $Payload -TimeoutSec 3 | Out-Null
  } catch {
  }
}
