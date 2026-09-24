$ErrorActionPreference = "Stop"

# Regression coverage for plugin#394: the Antigravity ensure hook must kill a
# stale monk-agent PID recorded in its PID file before starting a replacement.

$Repo = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$Root = Join-Path ([IO.Path]::GetTempPath()) ("monk-ensure-kill-" + [guid]::NewGuid().ToString("N"))
$SourcePath = Join-Path $Root "fake-agent.cs"
$AgentPath = Join-Path $Root "monk-agent.exe"
$MonkHome = Join-Path $Root "home"
$RunDir = Join-Path $MonkHome "agent\launcher\run"
$PidFile = Join-Path $RunDir "monk-agent.pid"
$HookPath = Join-Path $Repo ".antigravity-plugin\hooks\ensure-monk-agent.ps1"

$EnvironmentNames = @(
  "MONK_AGENT_HOME",
  "MONK_AGENT_PATH",
  "MONK_AGENT_PORT",
  "MONK_AGENT_SKIP_SIGNIN_NUDGE",
  "NO_COLOR"
)
$OriginalEnvironment = @{}
foreach ($Name in $EnvironmentNames) {
  $OriginalEnvironment[$Name] = [Environment]::GetEnvironmentVariable($Name, "Process")
}

$StaleProcess = $null
$NewProcess = $null
$HookProcess = $null

function Test-ProcessAlive {
  param([int]$ProcessId)
  return $null -ne (Get-Process -Id $ProcessId -ErrorAction SilentlyContinue)
}

try {
  New-Item -ItemType Directory -Force -Path $Root, $RunDir | Out-Null

  # A companion binary that ignores serve/host/port args and just sleeps, so
  # the hook's readiness loop sees a live process without a real MCP listener.
  @"
using System;
using System.Threading;

class Program
{
    static void Main(string[] args)
    {
        Thread.Sleep(TimeSpan.FromSeconds(60));
    }
}
"@ | Set-Content -Encoding UTF8 $SourcePath

  $Csc = Join-Path $env:WINDIR "Microsoft.NET\Framework64\v4.0.30319\csc.exe"
  if (-not (Test-Path $Csc)) {
    $Csc = (Get-ChildItem "$env:WINDIR\Microsoft.NET\Framework64" -Filter csc.exe -Recurse -ErrorAction SilentlyContinue |
      Select-Object -First 1 -ExpandProperty FullName)
  }
  if (-not $Csc) {
    throw "csc.exe not found; cannot build the fake agent fixture"
  }
  & $Csc /nologo /out:$AgentPath $SourcePath | Out-Null
  if (-not (Test-Path $AgentPath)) {
    throw "failed to compile fake-agent.exe"
  }

  # Seed a stale process and record it as the previous launch.
  $StaleProcess = Start-Process -FilePath $AgentPath -PassThru
  $StaleProcess.Id | Set-Content -NoNewline -Encoding ASCII $PidFile
  Start-Sleep -Seconds 1

  $env:MONK_AGENT_HOME = $MonkHome
  $env:MONK_AGENT_PATH = $AgentPath
  $env:MONK_AGENT_PORT = "57420"
  $env:MONK_AGENT_SKIP_SIGNIN_NUDGE = "1"
  $env:NO_COLOR = "1"

  # The hook drains [Console]::In; run it in a child with an empty redirected
  # stdin so this test's console is not blocked.
  $ProcessInfo = New-Object Diagnostics.ProcessStartInfo
  $ProcessInfo.FileName = (Get-Process -Id $PID).Path
  $ProcessInfo.Arguments = "-NoLogo -NoProfile -Command `"& '$HookPath'`""
  $ProcessInfo.UseShellExecute = $false
  $ProcessInfo.CreateNoWindow = $true
  $ProcessInfo.RedirectStandardInput = $true
  $ProcessInfo.RedirectStandardOutput = $true
  $ProcessInfo.RedirectStandardError = $true
  $HookProcess = New-Object Diagnostics.Process
  $HookProcess.StartInfo = $ProcessInfo
  if (-not $HookProcess.Start()) {
    throw "failed to start hook child process"
  }
  $HookProcess.StandardInput.Close()
  $Finished = $HookProcess.WaitForExit(25000)
  if (-not $Finished) {
    throw "ensure hook did not exit within the bounded test wait"
  }

  if (-not (Test-Path $PidFile)) {
    throw "PID file was not written by the hook"
  }
  $NewPid = [int](Get-Content -Raw $PidFile).Trim()
  if ($NewPid -eq $StaleProcess.Id) {
    throw "PID file still contains the stale process ID"
  }
  $NewProcess = Get-Process -Id $NewPid -ErrorAction SilentlyContinue
  Start-Sleep -Seconds 1

  if (Test-ProcessAlive $StaleProcess.Id) {
    throw "stale monk-agent process $($StaleProcess.Id) was not killed"
  }
  if (-not (Test-ProcessAlive $NewPid)) {
    throw "replacement monk-agent process $NewPid is not running"
  }

  Write-Host "ensure-monk-agent.ps1 stale PID kill test passed."
} finally {
  foreach ($Proc in @($HookProcess, $NewProcess, $StaleProcess)) {
    if ($null -ne $Proc) {
      Stop-Process -Id $Proc.Id -Force -ErrorAction SilentlyContinue
    }
  }
  foreach ($Name in $EnvironmentNames) {
    [Environment]::SetEnvironmentVariable($Name, $OriginalEnvironment[$Name], "Process")
  }
  Remove-Item -LiteralPath $Root -Recurse -Force -ErrorAction SilentlyContinue
}
