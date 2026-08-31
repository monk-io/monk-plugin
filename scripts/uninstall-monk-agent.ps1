param(
  [switch]$Runtime,
  [switch]$All,
  [switch]$KeepData,
  [switch]$Yes,
  [switch]$FromHook
)

$ErrorActionPreference = "Stop"

if ($FromHook -and $env:MONK_PLUGIN_UNINSTALL -ne "1") {
  exit 0
}

if ($env:MONK_UNINSTALL_RUNTIME -eq "1") {
  $Runtime = $true
}
if ($All) {
  $Runtime = $true
}

$InstallDir = if ($env:MONK_AGENT_INSTALL_DIR) { $env:MONK_AGENT_INSTALL_DIR } else {
  Join-Path $HOME ".monk\bin"
}
$MonkHome = if ($env:MONK_AGENT_HOME) { $env:MONK_AGENT_HOME } else {
  Join-Path $HOME ".monk"
}
$AgentDataDir = Join-Path $MonkHome "agent"
$PidFile = Join-Path $AgentDataDir "launcher\run\monk-agent.pid"
$Target = Join-Path $InstallDir "monk-agent.exe"
$Checksum = Join-Path $InstallDir "monk-agent.sha256"

if (-not $Yes) {
  $suffix = if ($Runtime) { " and Monk runtime" } else { "" }
  $answer = Read-Host "Remove monk-agent$suffix? [y/N]"
  if ($answer -notin @("y", "Y", "yes", "YES")) {
    Write-Host "Cancelled."
    exit 0
  }
}

function Test-SameFilePath {
  param([string]$Actual, [string]$Expected)
  if (-not $Actual -or -not $Expected) {
    return $false
  }
  try {
    return [string]::Equals(
      [IO.Path]::GetFullPath($Actual),
      [IO.Path]::GetFullPath($Expected),
      [StringComparison]::OrdinalIgnoreCase
    )
  } catch {
    return $false
  }
}

function Stop-ManagedAgent {
  if (-not (Test-Path $PidFile)) {
    return
  }

  $raw = (Get-Content -Raw $PidFile).Trim()
  if (-not $raw) {
    return
  }

  # Validate the PID is numeric before casting; a malformed PID file (text,
  # whitespace, BOM artifacts) would otherwise throw a terminating error under
  # ErrorActionPreference = "Stop". Treat non-numeric content as stale state.
  $ParsedPid = 0
  if (-not [int]::TryParse($raw, [ref]$ParsedPid) -or $ParsedPid -le 0) {
    Remove-Item -Force $PidFile -ErrorAction SilentlyContinue
    return
  }

  $process = Get-Process -Id $ParsedPid -ErrorAction SilentlyContinue
  if ($process) {
    try {
      $processPath = $process.Path
    } catch {
      $processPath = ""
    }
    if (Test-SameFilePath $processPath $Target) {
      Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
      try {
        Wait-Process -Id $process.Id -Timeout 10 -ErrorAction SilentlyContinue
      } catch {
        Start-Sleep -Milliseconds 500
      }
    }
  }
  Remove-Item -Force $PidFile -ErrorAction SilentlyContinue
}

function Remove-AgentFiles {
  Remove-Item -Force $Target, $Checksum -ErrorAction SilentlyContinue
  $tempPaths = @(
    (Join-Path $InstallDir ".monk-agent.extract"),
    (Join-Path $InstallDir ".monk-agent.tmp.zip"),
    (Join-Path $InstallDir ".monk-agent.tmp.sha256")
  )
  Remove-Item -Recurse -Force -Path $tempPaths -ErrorAction SilentlyContinue
  if (-not $KeepData) {
    Remove-Item -Recurse -Force $AgentDataDir -ErrorAction SilentlyContinue
  }
}

function Get-WslDistros {
  try {
    $raw = (wsl.exe -l -q) -replace [char]0, ""
    return $raw -split "\r?\n" |
      ForEach-Object { $_.Trim() } |
      Where-Object { $_ }
  } catch {
    return @()
  }
}

function Assert-NativeCommandSucceeded {
  param(
    [string]$Operation,
    [int]$ExitCode
  )

  if ($ExitCode -ne 0) {
    throw "$Operation failed with exit code $ExitCode."
  }
}

# The distro name alone is not proof monk-agent created it -- an unrelated
# distro can collide with "Ubuntu-Monk", or $env:MONK_AGENT_WSL_DISTRO can
# point at a pre-existing one. Ownership is only verified when the token
# written into the distro at provisioning time (see windowsInstallDistroCommand
# in src/services/install/intents.ts) matches the record kept on the host.
$OwnerFile = Join-Path $MonkHome "wsl-distro.owner"

function Test-MonkOwnsDistro {
  param([string]$Distro)

  if (-not (Test-Path $OwnerFile)) {
    return $false
  }
  $record = (Get-Content -Raw $OwnerFile).Trim()
  $separator = $record.IndexOf("=")
  if ($separator -lt 0) {
    return $false
  }
  $recordDistro = $record.Substring(0, $separator)
  $recordToken = $record.Substring($separator + 1).Trim()
  if ($recordDistro -ne $Distro -or -not $recordToken) {
    return $false
  }

  $remoteToken = ""
  try {
    $remoteToken = ((wsl.exe -d $Distro --user root -- sh -lc "cat /etc/monk-agent.owned 2>/dev/null") -replace [char]0, "").Trim()
  } catch {
    return $false
  }
  return $remoteToken -and $remoteToken -eq $recordToken
}

function Remove-AntigravityMcp {
  $ConfigDir = Join-Path $HOME ".gemini\config"
  $ConfigFile = Join-Path $ConfigDir "mcp_config.json"
  if (-not (Test-Path $ConfigFile)) { return }
  try {
    $Config = Get-Content -Raw $ConfigFile -Encoding UTF8 | ConvertFrom-Json
    if ($Config.mcpServers -and $Config.mcpServers.PSObject.Properties["monk"]) {
      $Config.mcpServers.PSObject.Properties.Remove("monk")
      if ($Config.mcpServers.PSObject.Properties.Count -eq 0) {
        $Config.PSObject.Properties.Remove("mcpServers")
      }
      $TempPath = "$ConfigFile.tmp-$PID"
      $Config | ConvertTo-Json -Depth 10 | Set-Content -Encoding UTF8 $TempPath
      [System.IO.File]::Copy($TempPath, $ConfigFile, $true)
      Remove-Item -Force $TempPath -ErrorAction SilentlyContinue
    }
  } catch {
  }
}

function Remove-MonkRuntime {
  $distros = @(Get-WslDistros)
  if (-not $distros.Length) {
    return
  }

  $preferred = if ($env:MONK_AGENT_WSL_DISTRO) { $env:MONK_AGENT_WSL_DISTRO } else { "Ubuntu-Monk" }
  $distro = if ($distros -contains $preferred) {
    $preferred
  } elseif ($distros -contains "Ubuntu-Monk") {
    "Ubuntu-Monk"
  } else {
    $distros | Where-Object { $_ -match "^Ubuntu(?:[-\s]|$)" } | Select-Object -First 1
  }
  if (-not $distro) {
    return
  }

  if ($distro -eq "Ubuntu-Monk" -and (Test-MonkOwnsDistro $distro)) {
    wsl.exe --terminate Ubuntu-Monk 2>$null
    wsl.exe --unregister Ubuntu-Monk
    Assert-NativeCommandSucceeded "Unregistering WSL distro 'Ubuntu-Monk'" $LASTEXITCODE
    return
  }

  if ($distro -eq "Ubuntu-Monk") {
    Write-Warning ("Found a WSL distro named 'Ubuntu-Monk' but could not verify monk-agent created it, " +
      "so it was left in place instead of being unregistered. If this distro belongs to Monk, remove it " +
      "yourself with 'wsl.exe --unregister Ubuntu-Monk'; otherwise no action is needed.")
  }

  $script = @'
set -e
systemctl stop monkd >/dev/null 2>&1 || true
systemctl disable monkd >/dev/null 2>&1 || true
rm -rf /etc/systemd/system/monkd.service.d
systemctl daemon-reload >/dev/null 2>&1 || true
if command -v apt-get >/dev/null 2>&1 && dpkg-query -W monk >/dev/null 2>&1; then
  apt-get remove -y monk
elif command -v dnf >/dev/null 2>&1 && rpm -q monk >/dev/null 2>&1; then
  dnf remove -y monk
fi
'@
  wsl.exe -d $distro --user root -- sh -lc $script
  Assert-NativeCommandSucceeded "Removing Monk runtime from WSL distro '$distro'" $LASTEXITCODE
}

Stop-ManagedAgent
Remove-AgentFiles
Remove-AntigravityMcp
if ($Runtime) {
  Remove-MonkRuntime
}

Write-Host "monk-agent uninstall complete."
