$ErrorActionPreference = "Stop"

# Regression coverage for Windows PowerShell 5.1 hosts where the Internet
# Explorer engine is unavailable or has never completed first-run setup.
# Invoke-WebRequest uses that engine unless -UseBasicParsing is explicit.

$Repo = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$Root = Join-Path ([IO.Path]::GetTempPath()) ("monk-basic-parsing-" + [guid]::NewGuid().ToString("N"))
$InstallDir = Join-Path $Root "install"
$MonkHome = Join-Path $Root "home"
$FixtureDir = Join-Path $Root "fixture"
$FixtureExe = Join-Path $FixtureDir "monk-agent.exe"
$FixtureArchive = Join-Path $Root "monk-agent-windows-latest.zip"
$FixtureChecksum = Join-Path $Root "monk-agent-windows-latest.zip.sha256"
$Target = Join-Path $InstallDir "monk-agent.exe"

$EnvironmentNames = @(
  "MONK_AGENT_INSTALL_DIR",
  "MONK_AGENT_HOME",
  "MONK_AGENT_CHANNEL",
  "MONK_AGENT_DOWNLOAD_BASE",
  "MONK_AGENT_AUTO_UPDATE"
)
$OriginalEnvironment = @{}
foreach ($Name in $EnvironmentNames) {
  $OriginalEnvironment[$Name] = [Environment]::GetEnvironmentVariable($Name, "Process")
}

$global:MonkBasicParsingFixtureArchive = $FixtureArchive
$global:MonkBasicParsingFixtureChecksum = $FixtureChecksum
$global:MonkBasicParsingDownloadRequests = @()

# Simulate Windows PowerShell 5.1 on a headless/Server Core installation:
# omitting -UseBasicParsing fails before any network response is processed.
function Invoke-WebRequest {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true)]
    [string]$Uri,
    [Parameter(Mandatory = $true)]
    [string]$OutFile,
    [switch]$UseBasicParsing
  )

  if (-not $UseBasicParsing) {
    throw "The response content cannot be parsed because the Internet Explorer engine is not available."
  }

  $global:MonkBasicParsingDownloadRequests += [pscustomobject]@{
    Uri = $Uri
    UseBasicParsing = [bool]$UseBasicParsing
  }
  $Source = if ($Uri.EndsWith(".sha256")) {
    $global:MonkBasicParsingFixtureChecksum
  } else {
    $global:MonkBasicParsingFixtureArchive
  }
  Copy-Item -LiteralPath $Source -Destination $OutFile -Force
}

try {
  New-Item -ItemType Directory -Force -Path $FixtureDir | Out-Null
  [IO.File]::WriteAllText($FixtureExe, "fake monk-agent binary")
  Compress-Archive -LiteralPath $FixtureExe -DestinationPath $FixtureArchive
  $Expected = (Get-FileHash -Algorithm SHA256 $FixtureArchive).Hash.ToLowerInvariant()
  "$Expected  monk-agent-windows-latest.zip" | Set-Content -NoNewline $FixtureChecksum

  $env:MONK_AGENT_INSTALL_DIR = $InstallDir
  $env:MONK_AGENT_HOME = $MonkHome
  $env:MONK_AGENT_CHANNEL = "stable"
  $env:MONK_AGENT_DOWNLOAD_BASE = "https://downloads.invalid/stable"
  $env:MONK_AGENT_AUTO_UPDATE = "1"

  $EnsurePath = Join-Path $Repo "scripts\ensure-monk-agent.ps1"
  $Output = @(& $EnsurePath)

  if (-not (Test-Path $Target)) {
    throw "ensure script did not install the fixture agent"
  }
  if ((Get-Content -Raw $Target) -ne "fake monk-agent binary") {
    throw "installed agent content differs from the fixture"
  }
  if ($Output[-1] -ne $Target) {
    throw "ensure script did not emit the installed agent path: $($Output -join ' | ')"
  }
  if ($global:MonkBasicParsingDownloadRequests.Count -ne 2) {
    throw "expected two downloads, got $($global:MonkBasicParsingDownloadRequests.Count)"
  }
  if (@($global:MonkBasicParsingDownloadRequests | Where-Object { -not $_.UseBasicParsing }).Count) {
    throw "one or more downloads omitted -UseBasicParsing"
  }

  $ShippedCopies = @(
    "plugins\monk\scripts\ensure-monk-agent.ps1",
    ".antigravity-plugin\scripts\ensure-monk-agent.ps1"
  )
  $ExpectedHash = (Get-FileHash -Algorithm SHA256 $EnsurePath).Hash
  foreach ($RelativePath in $ShippedCopies) {
    $CopyHash = (Get-FileHash -Algorithm SHA256 (Join-Path $Repo $RelativePath)).Hash
    if ($CopyHash -ne $ExpectedHash) {
      throw "generated PowerShell installer differs: $RelativePath"
    }
  }

  Write-Host "ensure_basic_parsing_status=pass downloads=$($global:MonkBasicParsingDownloadRequests.Count)"
} finally {
  foreach ($Name in $EnvironmentNames) {
    [Environment]::SetEnvironmentVariable($Name, $OriginalEnvironment[$Name], "Process")
  }
  Remove-Variable -Scope Global -Name MonkBasicParsingFixtureArchive -ErrorAction SilentlyContinue
  Remove-Variable -Scope Global -Name MonkBasicParsingFixtureChecksum -ErrorAction SilentlyContinue
  Remove-Variable -Scope Global -Name MonkBasicParsingDownloadRequests -ErrorAction SilentlyContinue

  $ResolvedRoot = [IO.Path]::GetFullPath($Root)
  $ResolvedTemp = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
  if ($ResolvedRoot.StartsWith($ResolvedTemp, [StringComparison]::OrdinalIgnoreCase) -and
      (Split-Path -Leaf $ResolvedRoot).StartsWith("monk-basic-parsing-")) {
    Remove-Item -LiteralPath $ResolvedRoot -Recurse -Force -ErrorAction SilentlyContinue
  }
}
