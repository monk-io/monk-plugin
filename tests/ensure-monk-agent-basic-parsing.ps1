$ErrorActionPreference = "Stop"

# Windows PowerShell 5.1 falls back to the Internet Explorer parser unless
# Invoke-WebRequest receives -UseBasicParsing. Exercise the real installer with
# deterministic local archive/checksum fixtures and a cmdlet shim that models
# the documented headless-host failure.

$Repo = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$Root = Join-Path ([IO.Path]::GetTempPath()) ("monk-basic-parsing-" + [guid]::NewGuid().ToString("N"))
$PayloadDir = Join-Path $Root "payload"
$ArchivePath = Join-Path $Root "monk-agent.zip"
$ChecksumPath = Join-Path $Root "monk-agent.zip.sha256"
$InstallDir = Join-Path $Root "install"
$MonkHome = Join-Path $Root "home"
$ShimPath = Join-Path $Root "invoke-installer.ps1"
$DownloadLog = Join-Path $Root "downloads.log"
$InstallerPath = Join-Path $Repo "scripts\ensure-monk-agent.ps1"
$WindowsPowerShell = Join-Path $env:SystemRoot "System32\WindowsPowerShell\v1.0\powershell.exe"

$EnvironmentNames = @(
  "MONK_AGENT_INSTALL_DIR",
  "MONK_AGENT_HOME",
  "MONK_AGENT_DOWNLOAD_BASE",
  "MONK_AGENT_AUTO_UPDATE",
  "MONK_TEST_ARCHIVE",
  "MONK_TEST_CHECKSUM",
  "MONK_TEST_DOWNLOAD_LOG",
  "MONK_TEST_INSTALLER"
)
$OriginalEnvironment = @{}
foreach ($Name in $EnvironmentNames) {
  $OriginalEnvironment[$Name] = [Environment]::GetEnvironmentVariable($Name, "Process")
}

try {
  New-Item -ItemType Directory -Force -Path $PayloadDir | Out-Null
  "fixture-agent" | Set-Content -NoNewline (Join-Path $PayloadDir "monk-agent.exe")
  Compress-Archive -Path (Join-Path $PayloadDir "monk-agent.exe") -DestinationPath $ArchivePath
  $Hash = (Get-FileHash -Algorithm SHA256 $ArchivePath).Hash.ToLowerInvariant()
  "$Hash  monk-agent-windows-latest.zip" | Set-Content -NoNewline $ChecksumPath

  @'
$ErrorActionPreference = "Stop"
function Invoke-WebRequest {
  [CmdletBinding()]
  param(
    [string]$Uri,
    [string]$OutFile,
    [switch]$UseBasicParsing
  )

  if (-not $UseBasicParsing) {
    throw "The response content cannot be parsed because the Internet Explorer engine is not available."
  }

  if ($Uri.EndsWith(".sha256")) {
    Copy-Item -Force $env:MONK_TEST_CHECKSUM $OutFile
  } else {
    Copy-Item -Force $env:MONK_TEST_ARCHIVE $OutFile
  }
  "basic=$($UseBasicParsing.IsPresent) uri=$Uri" | Add-Content $env:MONK_TEST_DOWNLOAD_LOG
}

. $env:MONK_TEST_INSTALLER
'@ | Set-Content -NoNewline $ShimPath

  $env:MONK_AGENT_INSTALL_DIR = $InstallDir
  $env:MONK_AGENT_HOME = $MonkHome
  $env:MONK_AGENT_DOWNLOAD_BASE = "https://fixture.invalid"
  $env:MONK_AGENT_AUTO_UPDATE = "1"
  $env:MONK_TEST_ARCHIVE = $ArchivePath
  $env:MONK_TEST_CHECKSUM = $ChecksumPath
  $env:MONK_TEST_DOWNLOAD_LOG = $DownloadLog
  $env:MONK_TEST_INSTALLER = $InstallerPath

  $Output = & $WindowsPowerShell -NoLogo -NoProfile -ExecutionPolicy Bypass -File $ShimPath 2>&1
  if ($LASTEXITCODE -ne 0) {
    throw "installer exited $LASTEXITCODE`: $Output"
  }

  $InstalledAgent = Join-Path $InstallDir "monk-agent.exe"
  if (-not (Test-Path $InstalledAgent)) {
    throw "installer did not extract monk-agent.exe"
  }
  if ((Get-Content -Raw $InstalledAgent) -ne "fixture-agent") {
    throw "installed fixture content changed"
  }

  $Downloads = @(Get-Content $DownloadLog)
  if ($Downloads.Count -ne 2 -or @($Downloads | Where-Object { $_ -notmatch "^basic=True " }).Count -ne 0) {
    throw "expected two basic-parsing downloads, got: $($Downloads -join '; ')"
  }

  $ShippedCopies = @(
    ".antigravity-plugin\scripts\ensure-monk-agent.ps1",
    "plugins\monk\scripts\ensure-monk-agent.ps1"
  )
  $ExpectedHash = (Get-FileHash -Algorithm SHA256 $InstallerPath).Hash
  foreach ($RelativePath in $ShippedCopies) {
    $CopyHash = (Get-FileHash -Algorithm SHA256 (Join-Path $Repo $RelativePath)).Hash
    if ($CopyHash -ne $ExpectedHash) {
      throw "generated PowerShell installer differs: $RelativePath"
    }
  }

  Write-Host "ensure_basic_parsing_status=pass downloads=$($Downloads.Count)"
} finally {
  foreach ($Name in $EnvironmentNames) {
    [Environment]::SetEnvironmentVariable($Name, $OriginalEnvironment[$Name], "Process")
  }
  Remove-Item -LiteralPath $Root -Recurse -Force -ErrorAction SilentlyContinue
}
