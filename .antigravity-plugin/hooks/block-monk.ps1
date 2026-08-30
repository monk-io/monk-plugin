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
    $startInfo.Arguments = "hook block-monk --format antigravity"
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
    if ($agentDecision.decision -eq "deny") {
      Write-Output $agentText
      exit 0
    }
  }
}

# Fallback: decode the buffered UTF-8 payload and strip a leading BOM before
# matching `monk`.
$hookInput = [System.Text.Encoding]::UTF8.GetString($hookBytes)
if ($hookInput.Length -gt 0 -and $hookInput[0] -eq [char]0xFEFF) {
  $hookInput = $hookInput.Substring(1)
}
try { $command = ($hookInput | ConvertFrom-Json).toolCall.args.CommandLine } catch { exit 0 }
if (-not $command) { exit 0 }

# Shell quoting/escaping ("monk", m\onk) and a wrapper-command list
# (sudo/command/env/exec/eval/xargs/awk/perl/python/nohup/time/bare-or--c
# bash|sh|zsh/powershell -Command/cmd /c — ENG-494), an optional
# `timeout [flags] N` prefix (ENG-492), and zero or more leading
# `NAME=value` assignments (ENG-492) don't change what actually runs, so
# strip backslashes/quotes before matching and recognize `monkd` + a leading
# forward-slash path. Blunt, non-quote-aware strip — known gap versus the
# primary `monk-agent hook block-monk` path: a backslash-separated Windows
# path loses its separator to the strip here and isn't detected, nor is
# `find -exec monk ...` or stacked wrappers (see plugin/static/claude/hooks/
# block-monk.ps1 for the same tradeoff, spelled out in more detail).
$normalized = $command.Replace('\', '').Replace('"', '').Replace("'", '')
if ($normalized -match '(^|[\r\n;&|`({])\s*(sudo|command|env|exec|nohup|time|eval|xargs|awk|perl|python[0-9.]*|powershell(\.exe)?\s+-(Command|c)|cmd(\.exe)?\s+/c|(bash|sh|zsh)(\s+-c)?)?\s*(timeout(\s+-[A-Za-z]+(\s+\S+)?)*\s+[0-9.]+\s+)?([A-Za-z_][A-Za-z0-9_]*=\S*\s+)*([^\s;&|`(){}]*[\\/])?monkd?(\.(exe|cmd|bat|ps1))?(\s|$)') {
  @{
    decision = "deny"
    reason   = "Blocked: do not shell out to the ``monk`` CLI - it desyncs the cluster state Monk manages. Use the monk-agent MCP tools instead."
  } | ConvertTo-Json -Compress
}

exit 0
