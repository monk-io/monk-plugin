param(
  [string]$RepoRoot = (Split-Path -Parent $PSScriptRoot)
)

$ErrorActionPreference = "Stop"
$WindowsPowerShell = Join-Path $env:SystemRoot "System32\WindowsPowerShell\v1.0\powershell.exe"
$Launchers = @(
  "scripts\start-monk-agent.ps1",
  "plugins\monk\scripts\start-monk-agent.ps1",
  ".antigravity-plugin\scripts\start-monk-agent.ps1"
)

foreach ($RelativeLauncher in $Launchers) {
  $Root = Join-Path $env:TEMP ("monk-launcher-mutex-timeout-" + [guid]::NewGuid())
  $Port = Get-Random -Minimum 20000 -Maximum 60000
  $Mutex = New-Object System.Threading.Mutex($false, "Local\monk-agent-launcher-$Port")
  $Acquired = $false
  $PreviousPort = $env:MONK_AGENT_PORT
  $PreviousPath = $env:MONK_AGENT_PATH
  $PreviousHome = $env:MONK_AGENT_HOME

  try {
    New-Item -ItemType Directory -Force -Path $Root | Out-Null
    $SourcePath = Join-Path $RepoRoot $RelativeLauncher
    $TestLauncher = Join-Path $Root "start-monk-agent.ps1"
    $FakeAgent = Join-Path $Root "fake-agent.cmd"
    $Marker = Join-Path $Root "fake-agent-started"

    $Source = Get-Content -LiteralPath $SourcePath -Raw
    $Source = $Source.Replace(
      '$LauncherMutex.WaitOne([TimeSpan]::FromSeconds(190))',
      '$LauncherMutex.WaitOne([TimeSpan]::FromMilliseconds(100))'
    )
    if ($Source -notmatch 'FromMilliseconds\(100\)') {
      throw "Could not shorten the mutex wait in $RelativeLauncher."
    }
    Set-Content -LiteralPath $TestLauncher -Value $Source -NoNewline
    Set-Content -LiteralPath $FakeAgent -Value "@echo off`r`necho started>$Marker`r`nexit /b 0`r`n" -NoNewline

    $Acquired = $Mutex.WaitOne([TimeSpan]::FromSeconds(1))
    if (-not $Acquired) {
      throw "Could not acquire the test mutex for port $Port."
    }

    $env:MONK_AGENT_PORT = [string]$Port
    $env:MONK_AGENT_PATH = $FakeAgent
    $env:MONK_AGENT_HOME = Join-Path $Root "home"
    $PreviousPreference = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    try {
      $Output = & $WindowsPowerShell -NoProfile -ExecutionPolicy Bypass -File $TestLauncher 2>&1
      $ExitCode = $LASTEXITCODE
    } finally {
      $ErrorActionPreference = $PreviousPreference
    }
    $OutputText = $Output | Out-String

    if ($ExitCode -eq 0) {
      throw "$RelativeLauncher unexpectedly succeeded without owning the launcher mutex."
    }
    if ($OutputText -notmatch 'Timed out waiting for another monk-agent launcher') {
      throw "$RelativeLauncher did not report its mutex timeout. Output: $OutputText"
    }
    if (Test-Path -LiteralPath $Marker) {
      throw "$RelativeLauncher started work after its mutex wait timed out."
    }
  } finally {
    if ($Acquired) {
      $Mutex.ReleaseMutex()
    }
    $Mutex.Dispose()
    $env:MONK_AGENT_PORT = $PreviousPort
    $env:MONK_AGENT_PATH = $PreviousPath
    $env:MONK_AGENT_HOME = $PreviousHome
    Remove-Item -LiteralPath $Root -Recurse -Force -ErrorAction SilentlyContinue
  }
}

Write-Host "Windows launcher mutex timeout tests passed."
