# PreToolUse hook for the run_command tool: block any shell-out to the `monk`
# CLI or `monkd` daemon.
# Windows (stock, no Git Bash) counterpart of block-monk.sh.
#
# Antigravity PreToolUse I/O:
#   stdin:  {"toolCall":{"name":"run_command","args":{"CommandLine":"..."}},...}
#   stdout: {"decision":"deny","reason":"..."} to block, or exit 0 to allow
#
# Delegates to `monk-agent hook block-monk --format antigravity`; post-filters
# helper allow/no-output results and falls back to a native regex biased toward
# BLOCKING when the binary is unavailable. Always exits 0 (the deny JSON is the
# block signal).

$ErrorActionPreference = "SilentlyContinue"

# On non-Windows the .sh sibling decides; bow out so the two hooks never both
# emit a decision. On Windows the .ps1 owns it (the .sh can't read a TTY stdin
# when a host spawns it in a git-bash window, and it bows out on Windows).
if ($env:OS -ne 'Windows_NT' -and (Get-Command bash -ErrorAction SilentlyContinue)) { exit 0 }

$InstallDir = if ($env:MONK_AGENT_INSTALL_DIR) { $env:MONK_AGENT_INSTALL_DIR } else { Join-Path $HOME ".monk\bin" }
$agent = if ($env:MONK_AGENT_PATH) { $env:MONK_AGENT_PATH } else { Join-Path $InstallDir "monk-agent.exe" }

function Read-StandardInputBytes {
  $stream = [Console]::OpenStandardInput()
  $buffer = New-Object byte[] 8192
  $memory = New-Object System.IO.MemoryStream
  try {
    while (($read = $stream.Read($buffer, 0, $buffer.Length)) -gt 0) {
      $memory.Write($buffer, 0, $read)
    }
    $memory.ToArray()
  } finally {
    $memory.Dispose()
  }
}

function Invoke-AgentHook {
  param([byte[]]$InputBytes)

  $startInfo = New-Object System.Diagnostics.ProcessStartInfo
  $startInfo.FileName = $agent
  $startInfo.Arguments = "hook block-monk --format antigravity"
  $startInfo.UseShellExecute = $false
  $startInfo.RedirectStandardInput = $true
  $startInfo.RedirectStandardOutput = $true
  $startInfo.RedirectStandardError = $true
  $startInfo.CreateNoWindow = $true

  $process = New-Object System.Diagnostics.Process
  $process.StartInfo = $startInfo
  [void]$process.Start()
  if ($InputBytes.Length -gt 0) {
    $process.StandardInput.BaseStream.Write($InputBytes, 0, $InputBytes.Length)
  }
  $process.StandardInput.Close()
  $stdout = $process.StandardOutput.ReadToEnd()
  $stderr = $process.StandardError.ReadToEnd()
  $process.WaitForExit()

  @{
    ExitCode = $process.ExitCode
    Stdout   = $stdout
    Stderr   = $stderr
  }
}

function Test-MonkShellCommand {
  param([string]$Command)

  $binary = '(?:(?:[A-Za-z]:\\|~[\\/]|/)(?:[^\s"'';&|(){}]+[\\/])*)?monkd?(?:\.exe)?'
  $boundary = '(^|[\r\n;&|`({])\s*'
  $prefix = '(?:(?:sudo|command)\s+)*(?:env(?:\s+(?:-\S+|[A-Za-z_][A-Za-z0-9_]*=(?:"[^"]*"|''[^'']*''|[^\s]+)))*\s+)?'
  $tail = '(\s|$|[;&|`"''\)])'
  $quote = '(?:["'']\s*)?'
  $inlineLead = '(?:[^"'';&|]*[;&|]\s*)?'

  if ($Command -match ($boundary + $prefix + $binary + $tail)) { return $true }
  if ($Command -match ($boundary + '\$\([^\r\n)]*\bwhich\s+monkd?\b[^\r\n)]*\)\s+\S+')) { return $true }

  $shell = '(?:bash|sh|zsh)(?:\.exe)?'
  if ($Command -match ($boundary + '(?:sudo\s+)?' + $shell + '\s+-[A-Za-z]*c\s+' + $quote + $inlineLead + $prefix + $binary + $tail)) {
    return $true
  }

  $powerShell = '(?:powershell|powershell\.exe|pwsh|pwsh\.exe)'
  if ($Command -match ($boundary + '(?:sudo\s+)?' + $powerShell + '\b[^\r\n;&|]*\s-(?:Command|c)\s+' + $quote + $inlineLead + $prefix + $binary + $tail)) {
    return $true
  }

  return $false
}

function Write-Deny {
  @{
    decision = "deny"
    reason   = "Blocked: do not shell out to the ``monk`` CLI or ``monkd`` daemon - it desyncs the cluster state Monk manages. Use the monk-agent MCP tools instead."
  } | ConvertTo-Json -Compress
}

$hookBytes = Read-StandardInputBytes
$agentResult = $null

if (Test-Path $agent) {
  $agentResult = Invoke-AgentHook -InputBytes $hookBytes
  if ($agentResult["Stdout"] -match '"decision"\s*:\s*"deny"') {
    [Console]::Out.Write($agentResult["Stdout"])
    exit 0
  }
  if ($agentResult["ExitCode"] -ne 0) {
    if ($agentResult["Stdout"]) { [Console]::Out.Write($agentResult["Stdout"]) }
    if ($agentResult["Stderr"]) { [Console]::Error.Write($agentResult["Stderr"]) }
    exit $agentResult["ExitCode"]
  }
}

$hookInput = [System.Text.Encoding]::UTF8.GetString($hookBytes)
if ($hookInput.Length -gt 0 -and [int][char]$hookInput[0] -eq 0xFEFF) {
  $hookInput = $hookInput.Substring(1)
}

try { $command = ($hookInput | ConvertFrom-Json).toolCall.args.CommandLine } catch { $command = "" }
if ($command -and (Test-MonkShellCommand -Command $command)) {
  Write-Deny
  exit 0
}

if ($agentResult -and $agentResult["Stdout"]) {
  [Console]::Out.Write($agentResult["Stdout"])
}

exit 0
