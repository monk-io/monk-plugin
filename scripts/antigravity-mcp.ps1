# Register monk in Antigravity's global MCP config, ~/.gemini/config/mcp_config.json.
# Dot-sourced by scripts/start-monk-agent.ps1 (any host's session start) and by
# Antigravity's own hooks/ensure-monk-agent.ps1, so the one entry has one writer
# here. POSIX counterpart: antigravity-mcp.sh. Windows PowerShell 5.1 syntax only.
#
# The entry runs monk-agent's stdio bridge rather than pointing serverUrl at the
# agent: through serverUrl, Antigravity's sign-in ends on a Google page showing a
# code the user has to paste back, while the bridge signs in with a loopback
# redirect like every other agent (ENG-852). `monk-agent setup` writes the same
# entry (registry.ts); keep them identical or each rewrites the other's.
#
# Idempotent — skips if the entry is already current, and replaces a stale one
# (a prior host/port or binary, or an older serverUrl entry). Does nothing
# without ~/.gemini/config, and writes nothing to stdout (hook output is JSON).
#
# Written as UTF-8 WITHOUT a byte-order mark: Windows PowerShell 5.1's
# `Set-Content -Encoding UTF8` prepends one, and Antigravity (Go) then rejects
# the whole file ("invalid character '﻿'"), losing every MCP server in it,
# and Monk's own setup refused to touch it. A file an older launcher already
# wrote with a BOM is rewritten even when the entry is current, which repairs it.

function Test-Utf8Bom([string]$Path) {
  $Stream = [System.IO.File]::OpenRead($Path)
  try {
    $Head = New-Object byte[] 3
    $Read = $Stream.Read($Head, 0, 3)
    return $Read -eq 3 -and $Head[0] -eq 0xEF -and $Head[1] -eq 0xBB -and $Head[2] -eq 0xBF
  } finally {
    $Stream.Dispose()
  }
}

function Write-Utf8NoBom([string]$Path, [string]$Text) {
  [System.IO.File]::WriteAllText($Path, $Text, (New-Object System.Text.UTF8Encoding $false))
}

function Register-AntigravityMcp {
  param([string]$AgentPath, [string]$ServerUrl)
  $ConfigDir = Join-Path $HOME ".gemini\config"
  if (-not (Test-Path $ConfigDir)) { return }

  $ConfigPath = Join-Path $ConfigDir "mcp_config.json"
  $ServerArgs = @("mcp-stdio", "--url", $ServerUrl)
  $HadBom = $false
  if ((Test-Path $ConfigPath) -and (Get-Item $ConfigPath).Length) {
    $HadBom = Test-Utf8Bom $ConfigPath
    try {
      $Config = Get-Content -Raw -Encoding UTF8 $ConfigPath | ConvertFrom-Json
    } catch {
      Write-Warning "Could not register Monk MCP server because $ConfigPath is not valid JSON."
      return
    }
    if ($null -eq $Config -or $Config.GetType().FullName -ne "System.Management.Automation.PSCustomObject") {
      Write-Warning "Could not register Monk MCP server because $ConfigPath is not a JSON object."
      return
    }
  } else {
    $Config = [pscustomobject]@{}
  }
  if ($null -eq $Config.mcpServers -or $Config.mcpServers.GetType().FullName -ne "System.Management.Automation.PSCustomObject") {
    Add-Member -InputObject $Config -NotePropertyName mcpServers -NotePropertyValue ([pscustomobject]@{}) -Force
  }
  $Entry = [pscustomobject]@{ command = $AgentPath; args = $ServerArgs }
  if ($Config.mcpServers.PSObject.Properties.Name -contains "monk") {
    $Current = $Config.mcpServers.monk
    $IsCurrent = $null -ne $Current -and
      $Current.GetType().FullName -eq "System.Management.Automation.PSCustomObject" -and
      [string]$Current.command -ceq $AgentPath -and
      (@($Current.args) -join "`n") -ceq ($ServerArgs -join "`n") -and
      @($Current.PSObject.Properties).Count -eq 2
    if ($IsCurrent -and -not $HadBom) { return }
    # Replaced whole: a serverUrl left next to command would leave Antigravity guessing.
    $Config.mcpServers.monk = $Entry
  } else {
    Add-Member -InputObject $Config.mcpServers -NotePropertyName monk -NotePropertyValue $Entry
  }
  $TempPath = "$ConfigPath.tmp-$PID"
  try {
    Write-Utf8NoBom $TempPath ($Config | ConvertTo-Json -Depth 100)
    Move-Item -Force $TempPath $ConfigPath
  } finally {
    Remove-Item -Force $TempPath -ErrorAction SilentlyContinue
  }
}
