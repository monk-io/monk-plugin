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

# On non-Windows the .sh sibling decides; bow out so the two hooks never both
# emit a decision. On Windows the .ps1 owns it (the .sh can't read a TTY stdin
# when a host spawns it in a git-bash window, and it bows out on Windows).
if ($env:OS -ne 'Windows_NT' -and (Get-Command bash -ErrorAction SilentlyContinue)) { exit 0 }

$InstallDir = if ($env:MONK_AGENT_INSTALL_DIR) { $env:MONK_AGENT_INSTALL_DIR } else { Join-Path $HOME ".monk\bin" }
$agent = if ($env:MONK_AGENT_PATH) { $env:MONK_AGENT_PATH } else { Join-Path $InstallDir "monk-agent.exe" }

# Let the binary read the hook payload straight from stdin. Reading it into a
# PowerShell string first and re-piping it corrupts non-ASCII bytes (e.g. a
# leading UTF-8 BOM) under an OEM console code page - which the cmd.exe launcher
# sets - so the binary would get unparseable JSON. The binary reads raw UTF-8
# (BOM-tolerant) from the inherited stdin and is unaffected.
if (Test-Path $agent) {
  & $agent hook block-monk --format antigravity
  exit $LASTEXITCODE
}

# Fallback: binary unavailable. Read stdin as UTF-8 (BOM stripped), match `monk`.
$reader = New-Object System.IO.StreamReader([Console]::OpenStandardInput(), [System.Text.Encoding]::UTF8)
$hookInput = $reader.ReadToEnd()
try { $command = ($hookInput | ConvertFrom-Json).toolCall.args.CommandLine } catch { exit 0 }
if (-not $command) { exit 0 }

# Shell quoting/escaping ("monk", m\onk) and a short wrapper-command list
# don't change what actually runs, so strip backslashes/quotes before
# matching and recognize `monkd` + a leading forward-slash path. Blunt,
# non-quote-aware strip — known gap versus the primary `monk-agent hook
# block-monk` path: a backslash-separated Windows path loses its separator
# to the strip here and isn't detected (see plugin/static/claude/hooks/
# block-monk.ps1 for the same tradeoff, spelled out in more detail).
$normalized = $command.Replace('\', '').Replace('"', '').Replace("'", '')
if ($normalized -match '(^|[\r\n;&|`({])\s*(sudo|command|env|exec|powershell(\.exe)?\s+-(Command|c)|cmd(\.exe)?\s+/c)?\s*([^\s;&|`(){}]*[\\/])?monkd?(\.(exe|cmd|bat|ps1))?(\s|$)') {
  @{
    decision = "deny"
    reason   = "Blocked: do not shell out to the ``monk`` CLI - it desyncs the cluster state Monk manages. Use the monk-agent MCP tools instead."
  } | ConvertTo-Json -Compress
}

exit 0
