$ErrorActionPreference = "Stop"

$RepoRoot = Split-Path -Parent $PSScriptRoot
$Hook = Join-Path $RepoRoot ".antigravity-plugin\hooks\ensure-monk-agent.ps1"
$PowerShell = Join-Path $env:SystemRoot "System32\WindowsPowerShell\v1.0\powershell.exe"
$TempRoot = Join-Path ([IO.Path]::GetTempPath()) ("monk-antigravity-bash-stub-" + [Guid]::NewGuid().ToString("N"))

New-Item -ItemType Directory -Force -Path $TempRoot | Out-Null
try {
  # Model the legacy Windows/WSL bash.exe launcher when WSL is installed but
  # no usable /bin/bash exists. Get-Command succeeds; execution does not.
  $BashStub = Join-Path $TempRoot "bash.cmd"
  "@exit /b 1" | Set-Content -Encoding Ascii -NoNewline $BashStub

  $OldPath = $env:PATH
  $OldAgentPath = $env:MONK_AGENT_PATH
  $OldPort = $env:MONK_AGENT_PORT
  try {
    $env:PATH = "$TempRoot;$env:SystemRoot\System32"
    $env:MONK_AGENT_PATH = Join-Path $TempRoot "missing-monk-agent.exe"
    $env:MONK_AGENT_PORT = "65534"

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
    "@exit /b 0" | Set-Content -Encoding Ascii -NoNewline $BashStub
    $DelegatedOutput = "{}" | & $PowerShell -NoProfile -ExecutionPolicy Bypass -File $Hook
    if ($LASTEXITCODE -ne 0) {
      throw "ensure hook exited with status $LASTEXITCODE for a usable Bash command"
    }
    if (@($DelegatedOutput).Count -ne 0) {
      throw "usable Bash command should suppress the native Antigravity hook; stdout='$DelegatedOutput'"
    }
  } finally {
    $env:PATH = $OldPath
    $env:MONK_AGENT_PATH = $OldAgentPath
    $env:MONK_AGENT_PORT = $OldPort
  }
} finally {
  Remove-Item -Recurse -Force $TempRoot -ErrorAction SilentlyContinue
}

Write-Output "PASS: unusable bash command does not suppress the native Antigravity ensure hook"
