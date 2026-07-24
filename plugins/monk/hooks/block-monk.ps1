# PreToolUse hook for the Bash tool: block any shell-out to the `monk` CLI.
# Monk owns its own cluster state - running `monk ...` from a shell desyncs it.
# Use monk-agent MCP tools instead.
#
# Delegates to `monk-agent hook block-monk` so the logic stays in one place.
# Falls back to native PowerShell if the binary is unavailable.

$agentDir = if ($env:MONK_AGENT_INSTALL_DIR) { $env:MONK_AGENT_INSTALL_DIR } else { Join-Path $HOME ".monk\bin" }
$agent = if ($env:MONK_AGENT_PATH) { $env:MONK_AGENT_PATH } else { Join-Path $agentDir "monk-agent.exe" }

# Let the binary read the hook payload straight from stdin. Reading it into a
# PowerShell string first and re-piping it corrupts non-ASCII bytes (e.g. the
# leading UTF-8 BOM that some hosts prepend) whenever the console is on an OEM
# code page - which is exactly what the cmd.exe launcher sets - so the binary
# would receive unparseable JSON and silently allow the command. The binary
# reads raw UTF-8 (BOM-tolerant) from the inherited stdin and is unaffected.
if (Test-Path $agent) {
  & $agent hook block-monk --format claude
  exit $LASTEXITCODE
}

# Fallback: binary unavailable. Read stdin as UTF-8 (BOM stripped) so the payload
# survives a non-UTF-8 console code page, then match `monk` in command position.
$reader = New-Object System.IO.StreamReader([Console]::OpenStandardInput(), [System.Text.Encoding]::UTF8)
$hookInput = $reader.ReadToEnd()
try { $command = ($hookInput | ConvertFrom-Json).tool_input.command } catch { exit 0 }
if (-not $command) { exit 0 }

if ($command -match '(^|[\r\n;&|`({])\s*(sudo\s+)?monk(\s|$)') {
  @{
    hookSpecificOutput = @{
      hookEventName            = "PreToolUse"
      permissionDecision       = "deny"
      permissionDecisionReason = "Blocked: do not shell out to the ``monk`` CLI - it desyncs the cluster state Monk manages. Use the monk-agent MCP tools instead."
    }
  } | ConvertTo-Json -Compress
}

exit 0
