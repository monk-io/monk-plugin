param(
  [string]$RepoRoot = (Split-Path -Parent $PSScriptRoot)
)

$ErrorActionPreference = "Stop"
$WindowsPowerShell = Join-Path $env:SystemRoot "System32\WindowsPowerShell\v1.0\powershell.exe"
$EnsureScript = Join-Path $RepoRoot "scripts\ensure-monk-agent.ps1"
$TempRoot = Join-Path ([IO.Path]::GetTempPath()) ("monk-zero-byte-agent-test-" + [guid]::NewGuid())
$InstallDir = Join-Path $TempRoot "install"
$Target = Join-Path $InstallDir "monk-agent.exe"
$Sidecar = Join-Path $InstallDir "monk-agent.sha256"
$WrapperScript = Join-Path $TempRoot "run-ensure-with-stubs.ps1"
$RequestLog = Join-Path $TempRoot "requests.log"
$ArchiveBytes = [Text.Encoding]::UTF8.GetBytes("fake monk-agent archive")
$Expected = ([System.BitConverter]::ToString(
  [System.Security.Cryptography.SHA256]::Create().ComputeHash($ArchiveBytes)
) -replace "-", "").ToLowerInvariant()

$PreviousInstallDir = $env:MONK_AGENT_INSTALL_DIR
$PreviousDownloadBase = $env:MONK_AGENT_DOWNLOAD_BASE
$PreviousPath = $env:Path

try {
  New-Item -ItemType Directory -Force -Path $InstallDir | Out-Null
  [IO.File]::WriteAllBytes($Target, [byte[]]@())
  [IO.File]::WriteAllText($Sidecar, ("{0}  monk-agent-windows-latest.zip" -f $Expected))

  @'
param(
  [string]$EnsureScript,
  [string]$RequestLog,
  [string]$Expected
)

$ErrorActionPreference = "Stop"

function global:Invoke-WebRequest {
  param([string]$Uri, [string]$OutFile)
  Add-Content -Path $RequestLog -Value $Uri
  if ($Uri.EndsWith(".sha256", [StringComparison]::Ordinal)) {
    [IO.File]::WriteAllText($OutFile, ("{0}  monk-agent-windows-latest.zip" -f $Expected))
    return
  }
  [IO.File]::WriteAllBytes($OutFile, [Text.Encoding]::UTF8.GetBytes("fake monk-agent archive"))
}

function global:Expand-Archive {
  param([string]$Path, [string]$DestinationPath, [switch]$Force)
  New-Item -ItemType Directory -Force -Path $DestinationPath | Out-Null
  [IO.File]::WriteAllBytes((Join-Path $DestinationPath "monk-agent.exe"), [Text.Encoding]::UTF8.GetBytes("fake exe"))
}

& $EnsureScript
'@ | Set-Content -Encoding UTF8 $WrapperScript

  $env:MONK_AGENT_INSTALL_DIR = $InstallDir
  $env:MONK_AGENT_DOWNLOAD_BASE = "https://example.invalid/monk"
  $env:Path = Split-Path -Parent $WindowsPowerShell

  $Output = & $WindowsPowerShell -NoProfile -ExecutionPolicy Bypass -File $WrapperScript `
    -EnsureScript $EnsureScript `
    -RequestLog $RequestLog `
    -Expected $Expected
  if ($LASTEXITCODE -ne 0) {
    throw "ensure script exited with code $LASTEXITCODE. Output: $Output"
  }
  if (($Output | Select-Object -Last 1) -ne $Target) {
    throw "Expected ensure script to output target path '$Target'. Output: $Output"
  }

  $Requests = if (Test-Path $RequestLog) { @(Get-Content -Path $RequestLog) } else { @() }
  $ArchiveRequests = @($Requests | Where-Object {
    $_ -like "*/monk-agent-windows-latest.zip"
  })
  if ($ArchiveRequests.Count -ne 1) {
    throw "Expected one archive download after rejecting zero-byte target; saw $($ArchiveRequests.Count). Requests: $($Requests -join ', ')"
  }

  if ((Get-Item -LiteralPath $Target).Length -le 0) {
    throw "Expected target to be replaced with a non-empty monk-agent.exe"
  }
} finally {
  $env:MONK_AGENT_INSTALL_DIR = $PreviousInstallDir
  $env:MONK_AGENT_DOWNLOAD_BASE = $PreviousDownloadBase
  $env:Path = $PreviousPath
  Remove-Item -Recurse -Force $TempRoot -ErrorAction SilentlyContinue
}

Write-Host "Windows zero-byte monk-agent recovery test passed."
