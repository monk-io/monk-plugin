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

# Shell quoting/escaping ("monk", m\onk) and a short wrapper-command list
# (sudo/command/env/exec/powershell -Command/cmd /c) don't change what
# actually runs, so strip backslashes/quotes before matching and recognize
# `monkd` + a leading forward-slash path (/usr/local/bin/monk). Blunt,
# non-quote-aware strip — good enough for a degraded fallback that only runs
# when the binary itself is missing (see block-monk.sh for the same
# tradeoff). Known gap versus the primary `monk-agent hook block-monk` path:
# a backslash-separated Windows path (C:\tools\monk.exe) loses its separator
# to the blind strip here and isn't detected — the compiled binary's
# quote-state-aware tokenizer handles that case correctly.
$normalized = $command.Replace('\', '').Replace('"', '').Replace("'", '')
if ($normalized -match '(^|[\r\n;&|`({])\s*(sudo|command|env|exec|powershell(\.exe)?\s+-(Command|c)|cmd(\.exe)?\s+/c)?\s*([^\s;&|`(){}]*[\\/])?monkd?(\.(exe|cmd|bat|ps1))?(\s|$)') {
  @{
    hookSpecificOutput = @{
      hookEventName            = "PreToolUse"
      permissionDecision       = "deny"
      permissionDecisionReason = "Blocked: do not shell out to the ``monk`` CLI - it desyncs the cluster state Monk manages. Use the monk-agent MCP tools instead."
    }
  } | ConvertTo-Json -Compress
}

exit 0
