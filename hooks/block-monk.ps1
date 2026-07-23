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
  # Treat the helper as authoritative only when it succeeds and emits a
  # decision. An interrupted update, incompatible binary, or startup failure
  # must not turn the guard off: discard the helper error and use the native
  # parser below. A successful empty response also falls through safely; the
  # fallback permits ordinary commands and still blocks direct `monk` calls.
  $agentOutput = @($hookInput | & $agent hook block-monk --format claude 2>$null)
  if ($LASTEXITCODE -eq 0 -and $agentOutput.Count -gt 0) {
    $agentText = $agentOutput -join [Environment]::NewLine
    try {
      $agentDecision = $agentText | ConvertFrom-Json
    } catch {
      $agentDecision = $null
    }
    if ($agentDecision.hookSpecificOutput.hookEventName -eq "PreToolUse" -and
        $agentDecision.hookSpecificOutput.permissionDecision -in @("allow", "ask", "deny")) {
      Write-Output $agentText
      exit 0
    }
  }
}

# Fallback: binary unavailable. Match `monk` only in command position.
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
