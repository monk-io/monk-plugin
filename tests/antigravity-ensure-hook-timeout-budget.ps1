$ErrorActionPreference = "Stop"

$Repo = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$Root = Join-Path ([IO.Path]::GetTempPath()) ("monk-antigravity-timeout-" + [guid]::NewGuid().ToString("N"))
$AgentPath = Join-Path $Root "fake-agent.exe"
$AgentSource = Join-Path $Root "fake-agent.cs"
$EmptyInput = Join-Path $Root "stdin.txt"
$StdoutPath = Join-Path $Root "hook.stdout.json"
$StderrPath = Join-Path $Root "hook.stderr.log"
$MonkHome = Join-Path $Root "monk-home"
$PidFile = Join-Path $MonkHome "agent\launcher\run\monk-agent.pid"
$EnvironmentNames = @(
  "MONK_AGENT_PATH",
  "MONK_AGENT_HOME",
  "MONK_AGENT_PORT",
  "MONK_DISABLE_ANALYTICS"
)
$OriginalEnvironment = @{}

foreach ($Name in $EnvironmentNames) {
  $OriginalEnvironment[$Name] = [Environment]::GetEnvironmentVariable($Name, "Process")
}

try {
  New-Item -ItemType Directory -Force -Path $Root | Out-Null
  New-Item -ItemType File -Force -Path $EmptyInput | Out-Null

  @"
using System;
using System.Threading;
class Program { static void Main(string[] args) { Thread.Sleep(TimeSpan.FromSeconds(60)); } }
"@ | Set-Content $AgentSource

  $Csc = Join-Path $env:WINDIR "Microsoft.NET\Framework64\v4.0.30319\csc.exe"
  if (-not (Test-Path $Csc)) {
    $Csc = Get-ChildItem "$env:WINDIR\Microsoft.NET\Framework64" -Filter csc.exe -Recurse |
      Select-Object -First 1 -ExpandProperty FullName
  }
  if (-not $Csc) {
    throw "csc.exe not found; cannot build the fake never-ready agent"
  }

  & $Csc /nologo /out:$AgentPath $AgentSource | Out-Null
  if (-not (Test-Path $AgentPath)) {
    throw "failed to compile fake-agent.exe"
  }

  $Hooks = Get-Content -Raw (Join-Path $Repo ".antigravity-plugin\hooks.json") | ConvertFrom-Json
  $HostTimeoutSeconds = [int]$Hooks.'ensure-monk-agent'.PreInvocation[0].timeout
  $HookPath = Join-Path $Repo ".antigravity-plugin\hooks\ensure-monk-agent.ps1"

  $env:MONK_AGENT_PATH = $AgentPath
  $env:MONK_AGENT_HOME = $MonkHome
  $env:MONK_AGENT_PORT = "57420"
  $env:MONK_DISABLE_ANALYTICS = "1"

  # Force the native PowerShell hook and make each readiness probe consume its
  # full two-second budget without touching the network.
  $ChildCommand = @"
`$ProgressPreference = 'SilentlyContinue'
`$env:Path = `$PSHOME
function global:Invoke-WebRequest {
  Start-Sleep -Seconds 2
  throw 'fixture: companion unavailable'
}
& '$HookPath'
"@
  $EncodedCommand = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($ChildCommand))

  $HookProcess = Start-Process `
    -FilePath (Get-Process -Id $PID).Path `
    -ArgumentList @("-NoLogo", "-NoProfile", "-NonInteractive", "-EncodedCommand", $EncodedCommand) `
    -WindowStyle Hidden `
    -RedirectStandardInput $EmptyInput `
    -RedirectStandardOutput $StdoutPath `
    -RedirectStandardError $StderrPath `
    -PassThru

  $Finished = $HookProcess.WaitForExit($HostTimeoutSeconds * 1000)
  if (-not $Finished) {
    Stop-Process -Id $HookProcess.Id -Force -ErrorAction SilentlyContinue
    throw "Antigravity's declared $HostTimeoutSeconds-second timeout kills the native hook before it emits readiness JSON"
  }
  $HookProcess.WaitForExit()
  $HookProcess.Refresh()

  $Stdout = Get-Content -Raw $StdoutPath -ErrorAction SilentlyContinue
  $Stderr = Get-Content -Raw $StderrPath -ErrorAction SilentlyContinue
  if ($HookProcess.ExitCode -is [int] -and $HookProcess.ExitCode -ne 0) {
    throw "native ensure hook exited $($HookProcess.ExitCode): $Stderr"
  }
  if ($Stdout -notmatch "did not become ready") {
    throw "native ensure hook completed without the expected readiness diagnostic: $Stdout"
  }

  Write-Host "PASS: native Antigravity cold-start hook completes within its declared timeout"
} finally {
  if (Test-Path $PidFile) {
    $AgentPid = Get-Content $PidFile -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($AgentPid) {
      Stop-Process -Id $AgentPid -Force -ErrorAction SilentlyContinue
    }
  }
  foreach ($Name in $EnvironmentNames) {
    [Environment]::SetEnvironmentVariable($Name, $OriginalEnvironment[$Name], "Process")
  }
  Remove-Item -Recurse -Force $Root -ErrorAction SilentlyContinue
}
