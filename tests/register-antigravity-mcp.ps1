$ErrorActionPreference = "Stop"

# Regression coverage for the bug-bounty report #367: Register-AntigravityMcp
# must write mcp_config.json as BOM-free UTF-8. Windows PowerShell 5.1's
# "Set-Content -Encoding UTF8" emits a UTF-8 BOM (EF BB BF), which Antigravity's
# MCP config parser does not accept. The defect only reproduces under 5.1
# (pwsh 7's "UTF8" already means BOM-less), so this test must run under BOTH
# Windows PowerShell 5.1 and PowerShell 7 (see CI).

$Repo = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$LauncherPath = Join-Path $Repo "scripts\start-monk-agent.ps1"

$Tokens = $null
$ParseErrors = $null
$Ast = [System.Management.Automation.Language.Parser]::ParseFile($LauncherPath, [ref]$Tokens, [ref]$ParseErrors)
if ($ParseErrors.Count -gt 0) {
  throw "launcher script did not parse: $($ParseErrors[0].Message)"
}
$FunctionAst = $Ast.Find(
  { param($Node) $Node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $Node.Name -eq "Register-AntigravityMcp" },
  $true
)
if ($null -eq $FunctionAst) {
  throw "Register-AntigravityMcp not found in $LauncherPath"
}

$Root = Join-Path ([IO.Path]::GetTempPath()) ("monk-mcp-bom-" + [guid]::NewGuid().ToString("N"))
$TestHome = Join-Path $Root "home"
$ConfigDir = Join-Path $TestHome ".gemini\config"
$ConfigPath = Join-Path $ConfigDir "mcp_config.json"
$ServerUrl = "http://127.0.0.1:57419/mcp"

try {
  New-Item -ItemType Directory -Force -Path $ConfigDir | Out-Null

  # Run the real shipped function body. $HOME is read-only/constant in both
  # host runtimes, so substitute the literal $HOME token in the extracted body
  # with the sandbox path (it is referenced exactly once, by Join-Path).
  $Body = $FunctionAst.Extent.Text -replace '\$HOME', ("'" + $TestHome + "'")
  . ([scriptblock]::Create($Body))
  $HealthResource = $ServerUrl
  Register-AntigravityMcp

  if (-not (Test-Path $ConfigPath)) {
    throw "mcp_config.json was not written under $TestHome"
  }
  $Bytes = [IO.File]::ReadAllBytes($ConfigPath)
  if ($Bytes.Length -ge 3 -and $Bytes[0] -eq 0xEF -and $Bytes[1] -eq 0xBB -and $Bytes[2] -eq 0xBF) {
    throw "mcp_config.json starts with a UTF-8 BOM (EF BB BF): $ConfigPath"
  }
  $Parsed = Get-Content -Raw -LiteralPath $ConfigPath | ConvertFrom-Json
  if ($null -eq $Parsed.mcpServers.monk -or $Parsed.mcpServers.monk.serverUrl -ne $ServerUrl) {
    throw "unexpected serverUrl in mcp_config.json: $($Parsed.mcpServers.monk.serverUrl)"
  }

  Write-Host "register_mcp_bom_status=pass no_bom=true powershell=$($PSVersionTable.PSVersion)"
} finally {
  Remove-Item -LiteralPath $Root -Recurse -Force -ErrorAction SilentlyContinue
}