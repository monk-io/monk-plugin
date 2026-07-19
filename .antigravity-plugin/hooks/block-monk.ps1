# PreToolUse hook for the run_command tool: block any shell-out to the `monk` CLI.
# Windows (stock, no Git Bash) counterpart of block-monk.sh.
#
# Antigravity PreToolUse I/O:
#   stdin:  {"toolCall":{"name":"run_command","args":{"CommandLine":"..."}},...}
#   stdout: {"decision":"deny","reason":"..."} to block, or exit 0 to allow
#
# Delegates to `monk-agent hook block-monk --format antigravity`; falls back to a
# native regex biased toward BLOCKING when the binary is unavailable. Always
# exits 0 (the deny JSON is the block signal).

$ErrorActionPreference = "SilentlyContinue"

$hookInput = [Console]::In.ReadToEnd()

# If bash is available the .sh sibling decides; bow out (allow) so the two hooks
# never both emit a decision (Antigravity runs every hook in the list).
if (Get-Command bash -ErrorAction SilentlyContinue) { exit 0 }

$InstallDir = if ($env:MONK_AGENT_INSTALL_DIR) { $env:MONK_AGENT_INSTALL_DIR } else { Join-Path $HOME ".monk\bin" }
$agent = if ($env:MONK_AGENT_PATH) { $env:MONK_AGENT_PATH } else { Join-Path $InstallDir "monk-agent.exe" }

if (Test-Path $agent) {
  $hookInput | & $agent hook block-monk --format antigravity
  if ($LASTEXITCODE -eq 0) { exit 0 }
}

# Fallback: binary unavailable. Match `monk` only in command position.
try { $command = ($hookInput | ConvertFrom-Json).toolCall.args.CommandLine } catch { exit 0 }
if (-not $command) { exit 0 }

if ($command -match '(^|[\r\n;&|`({])\s*(sudo\s+)?monk(\s|$)') {
  @{
    decision = "deny"
    reason   = "Blocked: do not shell out to the ``monk`` CLI - it desyncs the cluster state Monk manages. Use the monk-agent MCP tools instead."
  } | ConvertTo-Json -Compress
}

exit 0
