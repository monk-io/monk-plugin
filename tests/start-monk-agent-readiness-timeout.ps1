$ErrorActionPreference = "Stop"

# Regression coverage for ENG-410: the readiness wait must be bounded well
# under the 180s host-hook timeout instead of looping the full 180 tries.

$Repo = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$Root = Join-Path ([IO.Path]::GetTempPath()) ("monk-readiness-" + [guid]::NewGuid().ToString("N"))
$SrcPath = Join-Path $Root "fake-agent.cs"
$AgentPath = Join-Path $Root "fake-agent.exe"
$MonkHome = Join-Path $Root "home"
$StdoutPath = Join-Path $Root "launcher.out.log"
$StderrPath = Join-Path $Root "launcher.err.log"
$PidFile = Join-Path $MonkHome "agent\launcher\run\monk-agent.pid"

# Strips ANSI/VT100 escape sequences (color, cursor movement) from captured
# process output. PowerShell 7's Write-Error formatting emits these by
# default; on some hosts (observed on windows-latest runners) that formatting
# also wraps/re-colors long lines, splitting a literal substring like
# "within 2s" across escape codes so a plain -match against the raw text
# silently fails even though the launcher reported the right thing.
function Strip-AnsiCodes {
  param([string]$Text)
  return [regex]::Replace($Text, "`e\[[0-9;]*[A-Za-z]", "")
}

$EnvironmentNames = @(
  "MONK_AGENT_HOME",
  "MONK_AGENT_PATH",
  "MONK_AGENT_PORT",
  "MONK_AGENT_READY_TIMEOUT",
  "MONK_AGENT_SKIP_ENSURE",
  "MONK_AGENT_SKIP_SIGNIN_NUDGE",
  "NO_COLOR"
)
$OriginalEnvironment = @{}
foreach ($Name in $EnvironmentNames) {
  $OriginalEnvironment[$Name] = [Environment]::GetEnvironmentVariable($Name, "Process")
}

try {
  New-Item -ItemType Directory -Force -Path $Root | Out-Null

  # A companion binary that never answers the health check: it just sleeps,
  # so the launcher's readiness loop must give up on its own deadline instead
  # of relying on the process exiting.
  @"
using System;
using System.Threading;
class Program { static void Main(string[] args) { Thread.Sleep(TimeSpan.FromSeconds(30)); } }
"@ | Set-Content $SrcPath

  $Csc = Join-Path $env:WINDIR "Microsoft.NET\Framework64\v4.0.30319\csc.exe"
  if (-not (Test-Path $Csc)) {
    $Csc = (Get-ChildItem "$env:WINDIR\Microsoft.NET\Framework64" -Filter csc.exe -Recurse -ErrorAction SilentlyContinue |
      Select-Object -First 1 -ExpandProperty FullName)
  }
  if (-not $Csc) {
    throw "csc.exe not found; cannot build the fake never-ready agent for this test"
  }
  & $Csc /nologo /out:$AgentPath $SrcPath | Out-Null
  if (-not (Test-Path $AgentPath)) {
    throw "failed to compile fake-agent.exe"
  }

  $env:MONK_AGENT_HOME = $MonkHome
  $env:MONK_AGENT_PATH = $AgentPath
  $env:MONK_AGENT_PORT = "57419"
  $env:MONK_AGENT_READY_TIMEOUT = "2"
  $env:MONK_AGENT_SKIP_ENSURE = "1"
  $env:MONK_AGENT_SKIP_SIGNIN_NUDGE = "1"
  # Belt: ask the child to skip ANSI formatting outright (respected by
  # PowerShell 7.2+). The output is also sanitized below regardless, since
  # NO_COLOR support isn't guaranteed on every host/version this test runs on.
  $env:NO_COLOR = "1"

  $LauncherPath = Join-Path $Repo "scripts\start-monk-agent.ps1"
  $Timer = [Diagnostics.Stopwatch]::StartNew()
  # -NoProfile means $ErrorView can't be preset via a profile, and pwsh 7's
  # default "ConciseView" error formatter word-wraps long error lines to the
  # console width, which can split a literal substring like "within 2s"
  # across a line break (observed on windows-latest runners). Force the
  # unwrapped NormalView via -Command so the captured text is a single
  # contiguous line instead of guessing at every possible wrap point.
  $ChildCommand = "`$ErrorView = 'NormalView'; & '$LauncherPath'"
  $Launcher = Start-Process -FilePath (Get-Process -Id $PID).Path `
    -ArgumentList @("-NoLogo", "-NoProfile", "-Command", $ChildCommand) `
    -PassThru -RedirectStandardOutput $StdoutPath -RedirectStandardError $StderrPath
  $Finished = $Launcher.WaitForExit(15000)
  $Timer.Stop()

  if (-not $Finished) {
    Stop-Process -Id $Launcher.Id -Force -ErrorAction SilentlyContinue
    throw "launcher did not exit within the bounded test wait"
  }

  Start-Sleep -Milliseconds 200
  $Output = Strip-AnsiCodes ((Get-Content -Raw $StdoutPath -ErrorAction SilentlyContinue) +
    (Get-Content -Raw $StderrPath -ErrorAction SilentlyContinue))
  if ($Launcher.ExitCode -ne 1) {
    throw "expected launcher exit 1, got $($Launcher.ExitCode): $Output"
  }
  # Defense in depth: even with NormalView forced, tolerate any stray
  # whitespace/newline/continuation-pipe wrapping by normalizing before the
  # substring check instead of matching the raw text verbatim.
  $Normalized = ($Output -replace "[\r\n]", " ") -replace "\s*\|\s*", " " -replace "\s+", " "
  if ($Normalized -notmatch "within 2s") {
    throw "launcher did not report the configured deadline: $Output"
  }
  if ($Timer.Elapsed.TotalSeconds -gt 10) {
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

  Write-Host "readiness_timeout_status=pass elapsed=$([Math]::Round($Timer.Elapsed.TotalSeconds, 2))s"
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
