$ErrorActionPreference = "Stop"

# Regression coverage for the Windows healthy-process fast path: a plugin
# version change must restart the companion so it inherits the current
# MONK_PLUGIN_VERSION value.

$Repo = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$Root = Join-Path ([IO.Path]::GetTempPath()) ("monk-version-drift-" + [guid]::NewGuid().ToString("N"))
$PluginScripts = Join-Path $Root "plugin\scripts"
$SrcPath = Join-Path $Root "fake-agent.cs"
$AgentPath = Join-Path $Root "fake-agent.exe"
$CapturePath = Join-Path $Root "launches.txt"
$MonkHome = Join-Path $Root "home"
$Port = Get-Random -Minimum 57420 -Maximum 57920
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
  "MONK_PLUGIN_VERSION"
)
$OriginalEnvironment = @{}
foreach ($Name in $EnvironmentNames) {
  $OriginalEnvironment[$Name] = [Environment]::GetEnvironmentVariable($Name, "Process")
}

function Set-TestPluginVersion {
  param([string]$Version)
  "`$env:MONK_PLUGIN_VERSION = `"$Version`"" |
    Set-Content (Join-Path $PluginScripts "plugin-version.ps1")
}

function Invoke-TestLauncher {
  $LauncherPath = Join-Path $PluginScripts "start-monk-agent.ps1"
  & (Get-Process -Id $PID).Path -NoLogo -NoProfile -File $LauncherPath
  if ($LASTEXITCODE -ne 0) {
    throw "launcher exited $LASTEXITCODE"
  }
}

try {
  New-Item -ItemType Directory -Force -Path $PluginScripts | Out-Null
  Copy-Item (Join-Path $Repo "scripts\start-monk-agent.ps1") $PluginScripts

  # A minimal companion that records the inherited plugin version, exposes the
  # exact protected-resource response expected by the launcher, and stays up
  # until the launcher restarts it.
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
        Environment.GetEnvironmentVariable("MONK_PLUGIN_VERSION") +
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

  Set-TestPluginVersion "old-version"
  Invoke-TestLauncher
  $FirstLaunches = @(Get-Content $CapturePath)
  if ($FirstLaunches.Count -ne 1 -or $FirstLaunches[0] -notmatch "\|old-version$") {
    throw "first launch did not inherit old-version: $($FirstLaunches -join ',')"
  }

  # Unchanged configuration should take the healthy-process fast path.
  Invoke-TestLauncher
  $UnchangedLaunches = @(Get-Content $CapturePath)
  if ($UnchangedLaunches.Count -ne 1) {
    throw "unchanged plugin version restarted the companion"
  }

  Set-TestPluginVersion "new-version"
  Invoke-TestLauncher
  $ChangedLaunches = @(Get-Content $CapturePath)
  if ($ChangedLaunches.Count -ne 2 -or $ChangedLaunches[1] -notmatch "\|new-version$") {
    throw "plugin version drift did not restart with new-version: $($ChangedLaunches -join ',')"
  }

  $State = Get-Content -Raw $StateFile
  if (($State -split "`r?`n") -notcontains "plugin_version=new-version") {
    throw "launcher state did not persist the current plugin version: $State"
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

  Write-Host "plugin_version_restart_status=pass launches=$($ChangedLaunches.Count)"
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
