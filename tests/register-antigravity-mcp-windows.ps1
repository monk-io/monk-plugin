param(
  [string]$RepoRoot = (Split-Path -Parent $PSScriptRoot)
)

$ErrorActionPreference = "Stop"
$Launchers = @(
  (Join-Path $RepoRoot "scripts\start-monk-agent.ps1"),
  (Join-Path $RepoRoot "plugins\monk\scripts\start-monk-agent.ps1"),
  (Join-Path $RepoRoot ".antigravity-plugin\scripts\start-monk-agent.ps1")
)
$OriginalHome = $HOME

try {
  foreach ($Launcher in $Launchers) {
    $Tokens = $null
    $Errors = $null
    $Ast = [System.Management.Automation.Language.Parser]::ParseFile($Launcher, [ref]$Tokens, [ref]$Errors)
    if ($Errors.Count) { throw "PowerShell parse failed: $Launcher" }

    $Function = $Ast.Find({
      param($Node)
      $Node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
        $Node.Name -eq "Register-AntigravityMcp"
    }, $true)
    if (-not $Function) { throw "Missing Register-AntigravityMcp: $Launcher" }

    $Source = Get-Content -Raw $Launcher
    if ([regex]::Matches($Source, 'Register-AntigravityMcp').Count -ne 3) {
      throw "Registration must run on both successful launcher paths: $Launcher"
    }

    $TempHome = Join-Path $env:TEMP ("monk-register-mcp-" + [guid]::NewGuid())
    $ConfigDir = Join-Path $TempHome ".gemini\config"
    $ConfigPath = Join-Path $ConfigDir "mcp_config.json"
    New-Item -ItemType Directory -Force $ConfigDir | Out-Null
    '{"preferences":{"theme":"dark"},"mcpServers":{"existing":{"serverUrl":"http://127.0.0.1:9000/mcp"}}}' |
      Set-Content -NoNewline -Encoding UTF8 $ConfigPath

    try {
      Set-Variable -Name HOME -Value $TempHome -Force
      $AgentHost = "127.0.0.1"
      $Port = "17419"
      Invoke-Expression $Function.Extent.Text
      Register-AntigravityMcp
      Register-AntigravityMcp

      $Config = Get-Content -Raw $ConfigPath | ConvertFrom-Json
      if ($Config.preferences.theme -ne "dark") { throw "Unrelated config changed: $Launcher" }
      if ($Config.mcpServers.existing.serverUrl -ne "http://127.0.0.1:9000/mcp") {
        throw "Existing MCP server changed: $Launcher"
      }
      if ($Config.mcpServers.monk.serverUrl -ne "http://127.0.0.1:17419/mcp") {
        throw "Monk MCP URL missing or incorrect: $Launcher"
      }
      if (@($Config.mcpServers.PSObject.Properties.Name | Where-Object { $_ -eq "monk" }).Count -ne 1) {
        throw "Monk MCP registration is not idempotent: $Launcher"
      }

      foreach ($Seed in @('{}', '{"mcpServers":null}', '{"mcpServers":"invalid"}')) {
        $Seed | Set-Content -NoNewline -Encoding UTF8 $ConfigPath
        Register-AntigravityMcp
        $Config = Get-Content -Raw $ConfigPath | ConvertFrom-Json
        if ($Config.mcpServers.monk.serverUrl -ne "http://127.0.0.1:17419/mcp") {
          throw "Monk MCP URL missing when mcpServers is absent, null, or non-object: $Launcher"
        }
      }

      '{"mcpServers":{"monk":{"serverUrl":"http://127.0.0.1:7419/mcp","transport":"http"}}}' |
        Set-Content -NoNewline -Encoding UTF8 $ConfigPath
      Register-AntigravityMcp
      $Config = Get-Content -Raw $ConfigPath | ConvertFrom-Json
      if ($Config.mcpServers.monk.serverUrl -ne "http://127.0.0.1:17419/mcp") {
        throw "Stale Monk MCP URL was not updated: $Launcher"
      }
      if ($Config.mcpServers.monk.transport -ne "http") {
        throw "Existing Monk MCP properties were not preserved: $Launcher"
      }

      $OldWarningPreference = $WarningPreference
      try {
        $WarningPreference = "SilentlyContinue"
        foreach ($Seed in @('{invalid', '[]')) {
          $Seed | Set-Content -NoNewline -Encoding UTF8 $ConfigPath
          Register-AntigravityMcp
          if ((Get-Content -Raw $ConfigPath) -ne $Seed) {
            throw "Invalid or non-object config was overwritten: $Launcher"
          }
        }
      } finally {
        $WarningPreference = $OldWarningPreference
      }
    } finally {
      Set-Variable -Name HOME -Value $OriginalHome -Force
      Remove-Item -Recurse -Force $TempHome -ErrorAction SilentlyContinue
    }
  }
} finally {
  Set-Variable -Name HOME -Value $OriginalHome -Force
}

Write-Host "Windows Antigravity MCP registration tests passed."
