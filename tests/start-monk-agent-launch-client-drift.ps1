$ErrorActionPreference = "Stop"

# The healthy-process fast path must restart the Windows companion when a
# different supported host client fires the launcher. Otherwise the existing
# process keeps the stale MONK_AGENT_LAUNCH_CLIENT value it inherited at start.

$Repo = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$Root = Join-Path ([IO.Path]::GetTempPath()) ("monk-client-drift-" + [guid]::NewGuid().ToString("N"))
$SrcPath = Join-Path $Root "fake-agent.cs"
$AgentPath = Join-Path $Root "fake-agent.exe"
$CapturePath = Join-Path $Root "launches.txt"
$MonkHome = Join-Path $Root "home"
$Port = Get-Random -Minimum 57921 -Maximum 58920
$PidFile = Join-Path $MonkHome "agent\launcher\run\monk-agent.pid"
$StateFile = Join-Path $MonkHome "agent\launcher\run\monk-agent.state"

$EnvironmentNames = @(
  "MONK_AGENT_HOME",
  "MONK_AGENT_PATH",
  "MONK_AGENT_PORT",
  "MONK_AGENT_READY_TIMEOUT",
  "MONK_AGENT_SKIP_ENSURE",
  "MONK_AGENT_SKIP_SIGNIN_NUDGE",
  "MONK_CAPTURE_PATH",
  "MONK_DISABLE_ANALYTICS",
  "PLUGIN_ROOT",
  "CLAUDE_PLUGIN_ROOT",
  "CURSOR_PLUGIN_ROOT",
  "CURSOR_VERSION"
)
$OriginalEnvironment = @{}
foreach ($Name in $EnvironmentNames) {
  $OriginalEnvironment[$Name] = [Environment]::GetEnvironmentVariable($Name, "Process")
}

function Set-TestClient {
  param([ValidateSet("codex", "cursor")][string]$Client)

  Remove-Item Env:CLAUDE_PLUGIN_ROOT -ErrorAction SilentlyContinue
  Remove-Item Env:CURSOR_PLUGIN_ROOT -ErrorAction SilentlyContinue
  Remove-Item Env:CURSOR_VERSION -ErrorAction SilentlyContinue
  Remove-Item Env:PLUGIN_ROOT -ErrorAction SilentlyContinue
  if ($Client -eq "cursor") {
    $env:CURSOR_PLUGIN_ROOT = Join-Path $Root "cursor-plugin"
  } else {
    $env:PLUGIN_ROOT = Join-Path $Root "codex-plugin"
  }
}

function Invoke-TestLauncher {
  $LauncherPath = Join-Path $Repo "scripts\start-monk-agent.ps1"
  if (-not (Test-Path -LiteralPath $LauncherPath)) {
    throw "launcher fixture is missing at $LauncherPath"
  }
  $Runner = [PowerShell]::Create()
  try {
    $null = $Runner.AddCommand($LauncherPath)
    $null = $Runner.Invoke()
    if ($Runner.HadErrors) {
      throw "launcher failed: $($Runner.Streams.Error -join '; ')"
    }
  } finally {
    $Runner.Dispose()
  }
}

try {
  New-Item -ItemType Directory -Force -Path $Root | Out-Null

  # A minimal companion that records the inherited launch-client attribution,
  # serves the exact health metadata expected by the launcher, and stays alive
  # until a configuration drift forces the launcher to replace it.
  @"
using System;
using System.Diagnostics;
using System.IO;
using System.Net;
using System.Text;
class Program {
  static void Main(string[] args) {
    File.AppendAllText(
      Environment.GetEnvironmentVariable("MONK_CAPTURE_PATH"),
      Process.GetCurrentProcess().Id + "|" +
        Environment.GetEnvironmentVariable("MONK_AGENT_LAUNCH_CLIENT") +
        Environment.NewLine
    );
    var listener = new HttpListener();
    listener.Prefixes.Add("http://127.0.0.1:$Port/");
    listener.Start();
    while (true) {
      var context = listener.GetContext();
      var body = Encoding.UTF8.GetBytes(
        "{\"resource\":\"http://127.0.0.1:$Port/mcp\"}"
      );
      context.Response.ContentType = "application/json";
      context.Response.ContentLength64 = body.Length;
      context.Response.OutputStream.Write(body, 0, body.Length);
      context.Response.Close();
    }
  }
}
"@ | Set-Content $SrcPath

  $Csc = Join-Path $env:WINDIR "Microsoft.NET\Framework64\v4.0.30319\csc.exe"
  if (-not (Test-Path $Csc)) {
    $Csc = (Get-ChildItem "$env:WINDIR\Microsoft.NET\Framework64" -Filter csc.exe -Recurse -ErrorAction SilentlyContinue |
      Select-Object -First 1 -ExpandProperty FullName)
  }
  if (-not $Csc) {
    throw "csc.exe not found; cannot build the fake healthy agent for this test"
  }
  & $Csc /nologo /out:$AgentPath $SrcPath | Out-Null
  if (-not (Test-Path $AgentPath)) {
    throw "failed to compile fake-agent.exe"
  }

  $env:MONK_AGENT_HOME = $MonkHome
  $env:MONK_AGENT_PATH = $AgentPath
  $env:MONK_AGENT_PORT = [string]$Port
  $env:MONK_AGENT_READY_TIMEOUT = "5"
  $env:MONK_AGENT_SKIP_ENSURE = "1"
  $env:MONK_AGENT_SKIP_SIGNIN_NUDGE = "1"
  $env:MONK_CAPTURE_PATH = $CapturePath
  $env:MONK_DISABLE_ANALYTICS = "1"

  Set-TestClient "codex"
  Invoke-TestLauncher
  $FirstLaunches = @(Get-Content $CapturePath)
  if ($FirstLaunches.Count -ne 1 -or $FirstLaunches[0] -notmatch "\|codex$") {
    throw "first launch did not inherit codex: $($FirstLaunches -join ',')"
  }

  # Unchanged client attribution should take the healthy-process fast path.
  Invoke-TestLauncher
  $UnchangedLaunches = @(Get-Content $CapturePath)
  if ($UnchangedLaunches.Count -ne 1) {
    throw "unchanged launch client restarted the companion"
  }

  Set-TestClient "cursor"
  Invoke-TestLauncher
  $ChangedLaunches = @(Get-Content $CapturePath)
  if ($ChangedLaunches.Count -ne 2 -or $ChangedLaunches[1] -notmatch "\|cursor$") {
    throw "launch-client drift did not restart with cursor: $($ChangedLaunches -join ',')"
  }

  $State = Get-Content -Raw $StateFile
  if (($State -split "`r?`n") -notcontains "launch_client=cursor") {
    throw "launcher state did not persist the current launch client: $State"
  }

  $LauncherPath = Join-Path $Repo "scripts\start-monk-agent.ps1"
  $ExpectedHash = (Get-FileHash -Algorithm SHA256 $LauncherPath).Hash
  foreach ($RelativePath in @(
    ".antigravity-plugin\scripts\start-monk-agent.ps1",
    "plugins\monk\scripts\start-monk-agent.ps1"
  )) {
    $CopyHash = (Get-FileHash -Algorithm SHA256 (Join-Path $Repo $RelativePath)).Hash
    if ($CopyHash -ne $ExpectedHash) {
      throw "generated PowerShell launcher differs: $RelativePath"
    }
  }

  Write-Host "launch_client_restart_status=pass launches=$($ChangedLaunches.Count)"
} finally {
  if (Test-Path $PidFile) {
    $AgentPid = (Get-Content -Raw $PidFile).Trim()
    if ($AgentPid -match "^[0-9]+$") {
      Stop-Process -Id ([int]$AgentPid) -Force -ErrorAction SilentlyContinue
    }
  }
  foreach ($Name in $EnvironmentNames) {
    [Environment]::SetEnvironmentVariable($Name, $OriginalEnvironment[$Name], "Process")
  }
  Remove-Item -LiteralPath $Root -Recurse -Force -ErrorAction SilentlyContinue
}
