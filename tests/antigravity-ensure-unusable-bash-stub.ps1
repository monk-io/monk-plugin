$ErrorActionPreference = "Stop"

$RepoRoot = Split-Path -Parent $PSScriptRoot
$Hook = Join-Path $RepoRoot ".antigravity-plugin\hooks\ensure-monk-agent.ps1"
$PowerShell = Join-Path $env:SystemRoot "System32\WindowsPowerShell\v1.0\powershell.exe"
$TempRoot = Join-Path ([IO.Path]::GetTempPath()) ("monk-antigravity-bash-stub-" + [Guid]::NewGuid().ToString("N"))

New-Item -ItemType Directory -Force -Path $TempRoot | Out-Null
try {
  # Model the legacy Windows/WSL bash.exe launcher when WSL is installed but
  # no usable /bin/bash exists. Get-Command succeeds; execution does not.
  $BashStub = Join-Path $TempRoot "bash.exe"
  $BashSource = Join-Path $TempRoot "fake-bash.cs"
  @"
using System;
using System.Threading;
class Program {
  static int Main() {
    int delay;
    if (int.TryParse(Environment.GetEnvironmentVariable("FAKE_BASH_DELAY_MS"), out delay) && delay > 0) {
      Thread.Sleep(delay);
    }
    int exitCode;
    return int.TryParse(Environment.GetEnvironmentVariable("FAKE_BASH_EXIT"), out exitCode) ? exitCode : 1;
  }
}
"@ | Set-Content $BashSource

  $Csc = Join-Path $env:WINDIR "Microsoft.NET\Framework64\v4.0.30319\csc.exe"
  if (-not (Test-Path $Csc)) {
    $Csc = Get-ChildItem "$env:WINDIR\Microsoft.NET\Framework64" -Filter csc.exe -Recurse |
      Select-Object -First 1 -ExpandProperty FullName
  }
  if (-not $Csc) {
    throw "csc.exe not found; cannot build the fake Bash launcher"
  }
  & $Csc /nologo /out:$BashStub $BashSource | Out-Null
  if (-not (Test-Path $BashStub)) {
    throw "failed to compile fake Bash launcher"
  }

  $OldPath = $env:PATH
  $OldAgentPath = $env:MONK_AGENT_PATH
  $OldPort = $env:MONK_AGENT_PORT
  $OldBashExit = $env:FAKE_BASH_EXIT
  $OldBashDelay = $env:FAKE_BASH_DELAY_MS
  try {
    $env:PATH = "$TempRoot;$env:SystemRoot\System32"
    $env:MONK_AGENT_PATH = Join-Path $TempRoot "missing-monk-agent.exe"
    $env:MONK_AGENT_PORT = "65534"
    $env:FAKE_BASH_EXIT = "1"
    $env:FAKE_BASH_DELAY_MS = "0"

    $SelectedBash = Get-Command bash -ErrorAction Stop
    if ($SelectedBash.Source -ne $BashStub) {
      throw "fixture setup failed: expected $BashStub, got $($SelectedBash.Source)"
    }

    $Output = "{}" | & $PowerShell -NoProfile -ExecutionPolicy Bypass -File $Hook
    if ($LASTEXITCODE -ne 0) {
      throw "ensure hook exited with status $LASTEXITCODE"
    }

    $Text = [string]::Join("`n", @($Output))
    if (-not $Text.Contains("monk-agent is not installed")) {
      throw "FAIL: unusable bash command made the native Antigravity hook exit without its install guidance; stdout='$Text'"
    }

    # Preserve the intended de-duplication behavior when Bash is actually
    # runnable: the native hook should yield to the concurrently registered
    # POSIX sibling and emit nothing itself.
    $env:FAKE_BASH_EXIT = "0"
    $DelegatedOutput = "{}" | & $PowerShell -NoProfile -ExecutionPolicy Bypass -File $Hook
    if ($LASTEXITCODE -ne 0) {
      throw "ensure hook exited with status $LASTEXITCODE for a usable Bash command"
    }
    if (@($DelegatedOutput).Count -ne 0) {
      throw "usable Bash command should suppress the native Antigravity hook; stdout='$DelegatedOutput'"
    }

    # A launcher that never returns must not consume the host's entire hook
    # budget. The bounded probe should fall back to native guidance promptly.
    $env:FAKE_BASH_DELAY_MS = "10000"
    $Timer = [Diagnostics.Stopwatch]::StartNew()
    $HungOutput = "{}" | & $PowerShell -NoProfile -ExecutionPolicy Bypass -File $Hook
    $Timer.Stop()
    $HungText = [string]::Join("`n", @($HungOutput))
    if (-not $HungText.Contains("monk-agent is not installed")) {
      throw "hung Bash command suppressed native install guidance; stdout='$HungText'"
    }
    if ($Timer.Elapsed.TotalSeconds -gt 6) {
      throw "hung Bash liveness probe exceeded its bounded fallback time: $($Timer.Elapsed.TotalSeconds)s"
    }
  } finally {
    $env:PATH = $OldPath
    $env:MONK_AGENT_PATH = $OldAgentPath
    $env:MONK_AGENT_PORT = $OldPort
    $env:FAKE_BASH_EXIT = $OldBashExit
    $env:FAKE_BASH_DELAY_MS = $OldBashDelay
  }
} finally {
  Remove-Item -Recurse -Force $TempRoot -ErrorAction SilentlyContinue
}

Write-Output "PASS: unusable bash command does not suppress the native Antigravity ensure hook"
