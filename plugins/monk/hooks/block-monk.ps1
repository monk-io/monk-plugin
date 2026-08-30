# PreToolUse hook for the Bash tool: block any shell-out to the `monk` CLI.
# Monk owns its own cluster state - running `monk ...` from a shell desyncs it.
# Use monk-agent MCP tools instead.
#
# Delegates to `monk-agent hook block-monk` so the logic stays in one place.
# Falls back to native PowerShell if the binary is unavailable.

$agentDir = if ($env:MONK_AGENT_INSTALL_DIR) { $env:MONK_AGENT_INSTALL_DIR } else { Join-Path $HOME ".monk\bin" }
$agent = if ($env:MONK_AGENT_PATH) { $env:MONK_AGENT_PATH } else { Join-Path $agentDir "monk-agent.exe" }

# Buffer stdin as bytes so the helper receives the original UTF-8 payload
# without a PowerShell console-code-page round trip (re-piping a PowerShell
# string corrupts non-ASCII bytes, e.g. a leading UTF-8 BOM, under the OEM
# code page the cmd.exe launcher sets). Keeping the bytes also lets the
# native parser make the decision if the helper fails or emits an invalid
# response.
$inputStream = [Console]::OpenStandardInput()
$inputBuffer = New-Object byte[] 4096
$payloadStream = New-Object System.IO.MemoryStream
while (($bytesRead = $inputStream.Read($inputBuffer, 0, $inputBuffer.Length)) -gt 0) {
  $payloadStream.Write($inputBuffer, 0, $bytesRead)
}
$hookBytes = $payloadStream.ToArray()
$payloadStream.Dispose()

if (Test-Path $agent) {
  # Treat the helper as authoritative only when it succeeds and emits a
  # decision. An interrupted update, incompatible binary, or startup failure
  # must not turn the guard off: discard the helper error and use the native
  # parser below. A successful empty response also falls through safely; the
  # fallback permits ordinary commands and still blocks direct `monk` calls.
  $agentProcess = $null
  $agentText = $null
  $agentExitCode = $null
  try {
    $startInfo = New-Object System.Diagnostics.ProcessStartInfo
    $startInfo.FileName = $agent
    $startInfo.Arguments = "hook block-monk --format claude"
    $startInfo.UseShellExecute = $false
    $startInfo.RedirectStandardInput = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    $startInfo.CreateNoWindow = $true

    $agentProcess = New-Object System.Diagnostics.Process
    $agentProcess.StartInfo = $startInfo
    [void]$agentProcess.Start()
    $outputTask = $agentProcess.StandardOutput.ReadToEndAsync()
    $errorTask = $agentProcess.StandardError.ReadToEndAsync()
    $agentProcess.StandardInput.BaseStream.Write($hookBytes, 0, $hookBytes.Length)
    $agentProcess.StandardInput.BaseStream.Close()

    # Stay inside the host hook budget. If the compiled helper wedges, kill it
    # and fall through to the native parser instead of letting the host timeout
    # terminate this hook before it can return a deny decision.
    $helperFinished = $agentProcess.WaitForExit(2000)
    if ($helperFinished) {
      $agentText = $outputTask.GetAwaiter().GetResult()
      [void]$errorTask.GetAwaiter().GetResult()
      $agentExitCode = $agentProcess.ExitCode
    } else {
      try { $agentProcess.Kill() } catch { }
      try { [void]$agentProcess.WaitForExit(1000) } catch { }
      $agentText = $null
      $agentExitCode = $null
    }
  } catch {
    $agentText = $null
  } finally {
    if ($agentProcess) {
      $agentProcess.Dispose()
    }
  }

  if ($agentExitCode -eq 0 -and -not [string]::IsNullOrWhiteSpace($agentText)) {
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

# Fallback: decode the buffered UTF-8 payload and strip a leading BOM before
# matching `monk` in command position.
$hookInput = [System.Text.Encoding]::UTF8.GetString($hookBytes)
if ($hookInput.Length -gt 0 -and $hookInput[0] -eq [char]0xFEFF) {
  $hookInput = $hookInput.Substring(1)
}
try { $command = ($hookInput | ConvertFrom-Json).tool_input.command } catch { exit 0 }
if (-not $command) { exit 0 }

# Shell quoting/escaping ("monk", m\onk) and a wrapper-command list
# (sudo/command/env/exec/eval/xargs/awk/perl/python/nohup/time/bare-or--c
# bash|sh|zsh/powershell -Command/cmd /c — ENG-494), an optional
# `timeout [flags] N` prefix (ENG-492), and zero or more leading
# `NAME=value` assignments (ENG-492) don't change what actually runs, so
# strip backslashes/quotes before matching and recognize `monkd` + a leading
# forward-slash path (/usr/local/bin/monk). Blunt, non-quote-aware strip —
# good enough for a degraded fallback that only runs when the binary itself
# is missing (see block-monk.sh for the same tradeoff). Known gap versus the
# primary `monk-agent hook block-monk` path: a backslash-separated Windows
# path (C:\tools\monk.exe) loses its separator to the blind strip here and
# isn't detected, nor is `find -exec monk ...` or stacked wrappers
# (`sudo env monk`) — the compiled binary's quote-state-aware tokenizer
# handles those cases correctly.
$normalized = $command.Replace('\', '').Replace('"', '').Replace("'", '')
if ($normalized -match '(^|[\r\n;&|`({])\s*(sudo|command|env|exec|nohup|time|eval|xargs|awk|perl|python[0-9.]*|powershell(\.exe)?\s+-(Command|c)|cmd(\.exe)?\s+/c|(bash|sh|zsh)(\s+-c)?)?\s*(timeout(\s+-[A-Za-z]+(\s+\S+)?)*\s+[0-9.]+\s+)?([A-Za-z_][A-Za-z0-9_]*=\S*\s+)*([^\s;&|`(){}]*[\\/])?monkd?(\.(exe|cmd|bat|ps1))?(\s|$)') {
  @{
    hookSpecificOutput = @{
      hookEventName            = "PreToolUse"
      permissionDecision       = "deny"
      permissionDecisionReason = "Blocked: do not shell out to the ``monk`` CLI - it desyncs the cluster state Monk manages. Use the monk-agent MCP tools instead."
    }
  } | ConvertTo-Json -Compress
}

exit 0
