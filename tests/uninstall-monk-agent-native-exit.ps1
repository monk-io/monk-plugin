$ErrorActionPreference = "Stop"

$RepoRoot = Split-Path -Parent $PSScriptRoot
$Uninstaller = Join-Path $RepoRoot "scripts\uninstall-monk-agent.ps1"

function Restore-EnvironmentValue {
  param(
    [string]$Name,
    [AllowNull()][string]$Value
  )

  if ($null -eq $Value) {
    Remove-Item "Env:\$Name" -ErrorAction SilentlyContinue
  } else {
    Set-Item "Env:\$Name" $Value
  }
}

function Test-WslFailure {
  param(
    [string]$Distro,
    [string]$FailingCall,
    [int]$ExitCode,
    [string]$ExpectedError
  )

  $TempRoot = Join-Path ([IO.Path]::GetTempPath()) ("monk-uninstall-test-" + [guid]::NewGuid())
  $OutputPath = Join-Path $TempRoot "output.txt"
  New-Item -ItemType Directory -Force $TempRoot | Out-Null

  $PreviousInstallDir = $env:MONK_AGENT_INSTALL_DIR
  $PreviousHome = $env:MONK_AGENT_HOME
  $global:FakeWslDistro = $Distro
  $global:FakeWslFailingCall = $FailingCall
  $global:FakeWslExitCode = $ExitCode
  $global:FakeWslCalls = [System.Collections.Generic.List[string]]::new()

  function global:wsl.exe {
    $Call = $args -join " "
    $global:FakeWslCalls.Add($Call)

    if ($Call -eq "-l -q") {
      Write-Output $global:FakeWslDistro
      $global:LASTEXITCODE = 0
      return
    }

    if ($Call.StartsWith($global:FakeWslFailingCall, [StringComparison]::Ordinal)) {
      $global:LASTEXITCODE = $global:FakeWslExitCode
      return
    }

    $global:LASTEXITCODE = 0
  }

  try {
    $env:MONK_AGENT_INSTALL_DIR = Join-Path $TempRoot "bin"
    $env:MONK_AGENT_HOME = Join-Path $TempRoot "home"
    $Caught = $null

    try {
      & $Uninstaller -Runtime -Yes *> $OutputPath
    } catch {
      $Caught = $_
    }

    if (-not $Caught) {
      throw "Expected WSL failure for $Distro, but uninstall succeeded. Calls: $($global:FakeWslCalls -join ' | ')"
    }
    if ($Caught.Exception.Message -notlike "*$ExpectedError*") {
      throw "Unexpected error for ${Distro}: $($Caught.Exception.Message)"
    }

    $Output = if (Test-Path $OutputPath) { Get-Content -Raw $OutputPath } else { "" }
    if ($Output -match "monk-agent uninstall complete") {
      throw "Uninstaller printed a success message after WSL failure for $Distro."
    }
    if (-not ($global:FakeWslCalls | Where-Object { $_.StartsWith($FailingCall, [StringComparison]::Ordinal) })) {
      throw "Expected fake WSL call '$FailingCall' was not made."
    }
  } finally {
    Remove-Item Function:\wsl.exe -ErrorAction SilentlyContinue
    Restore-EnvironmentValue "MONK_AGENT_INSTALL_DIR" $PreviousInstallDir
    Restore-EnvironmentValue "MONK_AGENT_HOME" $PreviousHome
    Remove-Item -Recurse -Force $TempRoot -ErrorAction SilentlyContinue
    Remove-Variable FakeWslDistro, FakeWslFailingCall, FakeWslExitCode, FakeWslCalls -Scope Global -ErrorAction SilentlyContinue
  }
}

Test-WslFailure `
  -Distro "Ubuntu-Monk" `
  -FailingCall "--unregister Ubuntu-Monk" `
  -ExitCode 43 `
  -ExpectedError "Unregistering WSL distro 'Ubuntu-Monk' failed with exit code 43."

Test-WslFailure `
  -Distro "Ubuntu-24.04" `
  -FailingCall "-d Ubuntu-24.04 --user root sh -lc" `
  -ExitCode 44 `
  -ExpectedError "Removing Monk runtime from WSL distro 'Ubuntu-24.04' failed with exit code 44."

$PackagedCopies = @(
  (Join-Path $RepoRoot "scripts\uninstall-monk-agent.ps1"),
  (Join-Path $RepoRoot "plugins\monk\scripts\uninstall-monk-agent.ps1"),
  (Join-Path $RepoRoot ".antigravity-plugin\scripts\uninstall-monk-agent.ps1")
)
$CopyHashes = $PackagedCopies | ForEach-Object { (Get-FileHash -Algorithm SHA256 $_).Hash }
if (@($CopyHashes | Select-Object -Unique).Count -ne 1) {
  throw "Packaged PowerShell uninstallers are not identical."
}

Write-Host "Windows uninstaller native exit tests passed."
