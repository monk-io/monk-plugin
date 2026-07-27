# PreToolUse hook for the Bash tool: block any shell-out to the `monk` CLI or
# `monkd` daemon.
# Monk owns its own cluster state - running these from a shell desyncs it.
# Use monk-agent MCP tools instead.
#
# Delegates to `monk-agent hook block-monk` so the logic stays in one place.
# Post-filters helper allow/no-output results and falls back to native
# PowerShell if the binary is unavailable.

$agentDir = if ($env:MONK_AGENT_INSTALL_DIR) { $env:MONK_AGENT_INSTALL_DIR } else { Join-Path $HOME ".monk\bin" }
$agent = if ($env:MONK_AGENT_PATH) { $env:MONK_AGENT_PATH } else { Join-Path $agentDir "monk-agent.exe" }

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
  $startInfo.Arguments = "hook block-monk --format claude"
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
    hookSpecificOutput = @{
      hookEventName            = "PreToolUse"
      permissionDecision       = "deny"
      permissionDecisionReason = "Blocked: do not shell out to the ``monk`` CLI or ``monkd`` daemon - it desyncs the cluster state Monk manages. Use the monk-agent MCP tools instead."
    }
  } | ConvertTo-Json -Compress
}

$hookBytes = Read-StandardInputBytes
$agentResult = $null

if (Test-Path $agent) {
  $agentResult = Invoke-AgentHook -InputBytes $hookBytes
  if ($agentResult["Stdout"] -match '"permissionDecision"\s*:\s*"deny"') {
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

try { $command = ($hookInput | ConvertFrom-Json).tool_input.command } catch { $command = "" }
if ($command -and (Test-MonkShellCommand -Command $command)) {
  Write-Deny
  exit 0
}

if ($agentResult -and $agentResult["Stdout"]) {
  [Console]::Out.Write($agentResult["Stdout"])
}

exit 0
