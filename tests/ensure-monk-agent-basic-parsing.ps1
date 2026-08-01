param(
  [string]$RepoRoot = (Split-Path -Parent $PSScriptRoot)
)

$ErrorActionPreference = "Stop"

$Installers = @(
  (Join-Path $RepoRoot "scripts\ensure-monk-agent.ps1"),
  (Join-Path $RepoRoot "plugins\monk\scripts\ensure-monk-agent.ps1"),
  (Join-Path $RepoRoot ".antigravity-plugin\scripts\ensure-monk-agent.ps1")
)

foreach ($Installer in $Installers) {
  if (-not (Test-Path -LiteralPath $Installer)) {
    throw "Missing installer: $Installer"
  }

  $Downloads = Select-String -LiteralPath $Installer -Pattern "Invoke-WebRequest.*-OutFile"
  if ($Downloads.Count -ne 2) {
    throw "$Installer should contain exactly two download calls; found $($Downloads.Count)."
  }

  foreach ($Download in $Downloads) {
    if ($Download.Line -notmatch "-UseBasicParsing") {
      throw "$Installer has a download without -UseBasicParsing at line $($Download.LineNumber)."
    }
  }
}

Write-Output "ensure_basic_parsing_status=pass installers=$($Installers.Count) downloads=$($Installers.Count * 2)"
