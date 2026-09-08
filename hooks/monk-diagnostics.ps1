# PostToolUse hook for MANIFEST/MonkScript edits.
# Asks local monk-agent for analyzer diagnostics and feeds concise results back
# into the agent after template edits.
#
# All logic (path resolution, workspace discovery, the MCP call, and formatting)
# lives in `monk-agent hook diagnostics`, so this wrapper depends only on the
# binary the plugin already installs. Best-effort: a missing binary, missing
# agent, auth issues, or unavailable analyzer support must never block the
# user's edit, so we always exit 0.
#
# -Format selects the output shape: "claude" (default, also used by Cursor) emits
# a superset of fields; "codex" emits ONLY the documented PostToolUse fields,
# because Codex silently drops hook output that carries any unrecognized top-level
# key (see diagnosticsResponseJson in src/hooks/cli.ts). The Codex hook passes
# `-Format codex`; Claude/Cursor leave the default.
param([ValidateSet('claude', 'codex')][string]$Format = 'claude')

# On non-Windows the .sh sibling handles this; bow out to avoid emitting the same
# diagnostics twice. On Windows the .ps1 owns it: a host may spawn the .sh in an
# interactive git-bash window whose stdin is a TTY (e.g. Cursor), where the .sh
# can't read the payload - so the .sh bows out on Windows and the .ps1 does the
# work here.
if ($env:OS -ne 'Windows_NT' -and (Get-Command bash -ErrorAction SilentlyContinue)) { exit 0 }

$agentDir = if ($env:MONK_AGENT_INSTALL_DIR) { $env:MONK_AGENT_INSTALL_DIR } else { Join-Path $HOME ".monk\bin" }
$agent = if ($env:MONK_AGENT_PATH) { $env:MONK_AGENT_PATH } else { Join-Path $agentDir "monk-agent.exe" }

if (-not (Test-Path $agent)) { exit 0 }

# Buffer stdin as bytes up front and write it to the child's own redirected
# stdin, rather than leaving standard handles un-redirected and relying on
# implicit inheritance. That was tried first (to keep the payload byte-exact
# per block-monk.ps1's comment on re-piping) but a System.Diagnostics.Process
# with no RedirectStandardInput does not reliably inherit a *piped* parent
# stdin on Windows -- every real host pipes the hook payload in, so the
# child's stdin read never saw EOF and hung until the watchdog below killed
# it, silently discarding the diagnostics on every single invocation
# (ENG-641/681/708 follow-up incident, 2026-09-02). Buffering up front and
# writing+closing the child's own stdin stream sidesteps that gap entirely.
$inputStream = [Console]::OpenStandardInput()
$inputBuffer = New-Object byte[] 4096
$payloadStream = New-Object System.IO.MemoryStream
while (($bytesRead = $inputStream.Read($inputBuffer, 0, $inputBuffer.Length)) -gt 0) {
  $payloadStream.Write($inputBuffer, 0, $bytesRead)
}
$hookBytes = $payloadStream.ToArray()
$payloadStream.Dispose()

$startInfo = New-Object System.Diagnostics.ProcessStartInfo
$startInfo.FileName = $agent
$startInfo.Arguments = "hook diagnostics --format $Format"
$startInfo.UseShellExecute = $false
$startInfo.RedirectStandardInput = $true
$startInfo.CreateNoWindow = $true

$agentProcess = $null
try {
  $agentProcess = New-Object System.Diagnostics.Process
  $agentProcess.StartInfo = $startInfo
  [void]$agentProcess.Start()
  $agentProcess.StandardInput.BaseStream.Write($hookBytes, 0, $hookBytes.Length)
  $agentProcess.StandardInput.BaseStream.Close()
  # A wedged (not merely failing) helper must not block the edit indefinitely:
  # bound the wait and kill it on timeout. Unlike block-monk's 2s default
  # (which must stay well under every host's tight 5s PreToolUse budget),
  # this hook's host budget is a generous 30s and the analyzer call itself
  # can legitimately take several seconds on a cold/first-request agent -- an
  # aggressive bound here was confirmed live (2026-09-02 e2e-smoke) to
  # truncate real, still-in-flight analyzer responses before they ever came
  # back, so a working call was silently discarded exactly like a genuinely
  # wedged one. 20s leaves the watchdog's own kill overhead safely inside the
  # 30s budget while giving a slow-but-healthy call real room to finish. PS
  # 5.1's Process class has no tree-kill overload, so this only reaches the
  # helper itself.
  $timeoutMs = if ($env:MONK_AGENT_HOOK_TIMEOUT_MS) { [int]$env:MONK_AGENT_HOOK_TIMEOUT_MS } else { 20000 }
  if (-not $agentProcess.WaitForExit($timeoutMs)) {
    try { $agentProcess.Kill() } catch {}
  }
} catch {
} finally {
  if ($agentProcess) { $agentProcess.Dispose() }
}
exit 0
