# PreToolUse hook for the Bash tool: block any shell-out to the `monk` CLI.
# Monk owns its own cluster state - running `monk ...` from a shell desyncs it.
# Use monk-agent MCP tools instead.
#
# Delegates to `monk-agent hook block-monk` so the logic stays in one place.
# Falls back to native PowerShell if the binary is unavailable.

$hookInput = [Console]::In.ReadToEnd()

$agentDir = if ($env:MONK_AGENT_INSTALL_DIR) { $env:MONK_AGENT_INSTALL_DIR } else { Join-Path $HOME ".monk\bin" }
$agent = if ($env:MONK_AGENT_PATH) { $env:MONK_AGENT_PATH } else { Join-Path $agentDir "monk-agent.exe" }

if (Test-Path $agent) {
  $hookInput | & $agent hook block-monk --format claude
  exit $LASTEXITCODE
}

# Fallback: binary unavailable. Match `monk` only in command position.
try { $command = ($hookInput | ConvertFrom-Json).tool_input.command } catch { exit 0 }
if (-not $command) { exit 0 }

if ($command -match '(^|[;&|`({\n])\s*(sudo\s+)?monk(\s|$)') {
  @{
    hookSpecificOutput = @{
      hookEventName            = "PreToolUse"
      permissionDecision       = "deny"
      permissionDecisionReason = "Blocked: do not shell out to the ``monk`` CLI - it desyncs the cluster state Monk manages. Use the monk-agent MCP tools instead."
    }
  } | ConvertTo-Json -Compress
}

exit 0
