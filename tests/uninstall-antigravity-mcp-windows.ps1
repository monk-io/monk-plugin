param(
  [string]$RepoRoot = (Split-Path -Parent $PSScriptRoot)
)

$ErrorActionPreference = "Stop"
$WindowsPowerShell = Join-Path $env:SystemRoot "System32\WindowsPowerShell\v1.0\powershell.exe"
$TempRoot = Join-Path $env:TEMP "monk-uninstall-mcp-$PID"
$PreviousInstallDir = $env:MONK_AGENT_INSTALL_DIR
$PreviousMonkHome = $env:MONK_AGENT_HOME
$PreviousConfig = $env:MONK_ANTIGRAVITY_CONFIG

$Scripts = @(
  (Join-Path $RepoRoot "scripts\uninstall-monk-agent.ps1"),
  (Join-Path $RepoRoot "plugins\monk\scripts\uninstall-monk-agent.ps1"),
  (Join-Path $RepoRoot ".antigravity-plugin\scripts\uninstall-monk-agent.ps1")
)

function Invoke-IsolatedUninstall {
  param(
    [string]$Script,
    [string]$Name,
    [string]$ConfigText
  )

  $CaseRoot = Join-Path $TempRoot $Name
  $ConfigPath = Join-Path $CaseRoot "config\mcp_config.json"
  New-Item -ItemType Directory -Force -Path (Split-Path -Parent $ConfigPath) | Out-Null
  [IO.File]::WriteAllText($ConfigPath, $ConfigText, [Text.UTF8Encoding]::new($false))

  $env:MONK_AGENT_INSTALL_DIR = Join-Path $CaseRoot "install"
  $env:MONK_AGENT_HOME = Join-Path $CaseRoot "monk-home"
  $env:MONK_ANTIGRAVITY_CONFIG = $ConfigPath
  New-Item -ItemType Directory -Force -Path $env:MONK_AGENT_INSTALL_DIR, $env:MONK_AGENT_HOME | Out-Null

  & $WindowsPowerShell -NoProfile -ExecutionPolicy Bypass -File $Script -Yes -KeepData | Out-Null
  if ($LASTEXITCODE -ne 0) {
    throw "Uninstaller failed for $Name with exit code $LASTEXITCODE"
  }
  return $ConfigPath
}

try {
  for ($Index = 0; $Index -lt $Scripts.Count; $Index++) {
    $ConfigPath = Invoke-IsolatedUninstall -Script $Scripts[$Index] -Name "copy-$Index" -ConfigText @'
{
  "theme": "dark",
  "mcpServers": {
    "existing": { "serverUrl": "http://127.0.0.1:9000/mcp" },
    "monk": { "serverUrl": "http://127.0.0.1:7419/mcp" }
  }
}
'@
    $Config = Get-Content -Raw -LiteralPath $ConfigPath | ConvertFrom-Json
    if ($Config.theme -ne "dark") {
      throw "Uninstaller changed an unrelated top-level value for copy $Index"
    }
    if ($null -eq $Config.mcpServers.existing) {
      throw "Uninstaller removed an unrelated MCP server for copy $Index"
    }
    if ($null -ne $Config.mcpServers.PSObject.Properties["monk"]) {
      throw "Uninstaller left the Monk MCP registration for copy $Index"
    }
  }

  $EmptyConfigPath = Invoke-IsolatedUninstall -Script $Scripts[0] -Name "empty-servers" -ConfigText '{"other":true,"mcpServers":{"monk":{"serverUrl":"http://127.0.0.1:7419/mcp"}}}'
  $EmptyConfig = Get-Content -Raw -LiteralPath $EmptyConfigPath | ConvertFrom-Json
  if ($null -ne $EmptyConfig.PSObject.Properties["mcpServers"] -or -not $EmptyConfig.other) {
    throw "Uninstaller did not remove the empty mcpServers object cleanly"
  }

  $Malformed = '{not-json'
  $MalformedPath = Invoke-IsolatedUninstall -Script $Scripts[0] -Name "malformed" -ConfigText $Malformed
  if ((Get-Content -Raw -LiteralPath $MalformedPath) -cne $Malformed) {
    throw "Uninstaller changed malformed JSON"
  }

  $Reference = (Get-Content -Raw -LiteralPath $Scripts[0]) -replace "`r`n", "`n"
  foreach ($Script in $Scripts[1..2]) {
    $Copy = (Get-Content -Raw -LiteralPath $Script) -replace "`r`n", "`n"
    if ($Copy -cne $Reference) {
      throw "Rendered PowerShell uninstaller differs: $Script"
    }
  }
} finally {
  $env:MONK_AGENT_INSTALL_DIR = $PreviousInstallDir
  $env:MONK_AGENT_HOME = $PreviousMonkHome
  $env:MONK_ANTIGRAVITY_CONFIG = $PreviousConfig
  Remove-Item -LiteralPath $TempRoot -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host "Windows Antigravity MCP uninstall tests passed."
