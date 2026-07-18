$ErrorActionPreference = "Stop"

$Repo = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$Root = Join-Path ([IO.Path]::GetTempPath()) ("monk-readiness-" + [guid]::NewGuid().ToString("N"))
$AgentPath = Join-Path $Root "monk-agent.exe"
$MonkHome = Join-Path $Root "home"
$StdoutPath = Join-Path $Root "launcher.out.log"
$StderrPath = Join-Path $Root "launcher.err.log"
$PidFile = Join-Path $MonkHome "agent\launcher\run\monk-agent.pid"

$EnvironmentNames = @(
  "MONK_AGENT_HOME",
  "MONK_AGENT_INSTALL_DIR",
  "MONK_AGENT_PATH",
  "MONK_AGENT_PORT",
  "MONK_AGENT_READY_TIMEOUT",
  "MONK_AGENT_SKIP_ENSURE",
  "MONK_AGENT_SKIP_SIGNIN_NUDGE"
)
$OriginalEnvironment = @{}
foreach ($Name in $EnvironmentNames) {
  $OriginalEnvironment[$Name] = [Environment]::GetEnvironmentVariable($Name, "Process")
}

try {
  New-Item -ItemType Directory -Force -Path $Root | Out-Null
  Add-Type -TypeDefinition @"
using System;
using System.Threading;

public static class Program
{
    public static void Main(string[] args)
    {
        Thread.Sleep(TimeSpan.FromSeconds(30));
    }
}
"@ -Language CSharp -OutputAssembly $AgentPath -OutputType ConsoleApplication

  $env:MONK_AGENT_HOME = $MonkHome
  $env:MONK_AGENT_INSTALL_DIR = $Root
  $env:MONK_AGENT_PATH = $AgentPath
  $env:MONK_AGENT_PORT = "57419"
  $env:MONK_AGENT_READY_TIMEOUT = "2"
  $env:MONK_AGENT_SKIP_ENSURE = "1"
  $env:MONK_AGENT_SKIP_SIGNIN_NUDGE = "1"

  $PowerShellPath = (Get-Process -Id $PID).Path
  $LauncherPath = Join-Path $Repo "scripts\start-monk-agent.ps1"
  $Timer = [Diagnostics.Stopwatch]::StartNew()
  $Launcher = Start-Process `
    -FilePath $PowerShellPath `
    -ArgumentList @("-NoLogo", "-NoProfile", "-File", $LauncherPath) `
    -PassThru `
    -Wait `
    -RedirectStandardOutput $StdoutPath `
    -RedirectStandardError $StderrPath
  $Timer.Stop()

  $Output = (Get-Content -Raw $StdoutPath -ErrorAction SilentlyContinue) +
    (Get-Content -Raw $StderrPath -ErrorAction SilentlyContinue)
  if ($Launcher.ExitCode -ne 1) {
    throw "expected launcher exit 1, got $($Launcher.ExitCode): $Output"
  }
  if ($Output -notmatch "within 2s") {
    throw "launcher did not report the configured deadline: $Output"
  }
  if ($Timer.Elapsed.TotalSeconds -gt 5) {
    throw "launcher exceeded bounded test time: $($Timer.Elapsed.TotalSeconds)s"
  }

  $ShippedCopies = @(
    ".antigravity-plugin\scripts\start-monk-agent.ps1",
    "plugins\monk\scripts\start-monk-agent.ps1"
  )
  $ExpectedHash = (Get-FileHash -Algorithm SHA256 $LauncherPath).Hash
  foreach ($RelativePath in $ShippedCopies) {
    $CopyHash = (Get-FileHash -Algorithm SHA256 (Join-Path $Repo $RelativePath)).Hash
    if ($CopyHash -ne $ExpectedHash) {
      throw "generated PowerShell launcher differs: $RelativePath"
    }
  }

  Write-Output "readiness_timeout_status=pass elapsed=$([Math]::Round($Timer.Elapsed.TotalSeconds, 2))s"
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
