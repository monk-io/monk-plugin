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

function Stop-ManagedAgent {
  if (-not (Test-Path $PidFile)) {
    return
  }

  $raw = (Get-Content -Raw $PidFile).Trim()
  if (-not $raw) {
    return
  }

  $parsedPid = 0
  if (-not [int32]::TryParse($raw, [ref]$parsedPid) -or $parsedPid -le 0) {
    Remove-Item -Force $PidFile -ErrorAction SilentlyContinue
    return
  }

  $process = Get-Process -Id $parsedPid -ErrorAction SilentlyContinue
  if ($process) {
    try {
      $name = [IO.Path]::GetFileName($process.Path)
    } catch {
      $name = ""
    }
    if (-not $name -or $name -ieq "monk-agent.exe") {
      Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
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

  if ($distro -eq "Ubuntu-Monk") {
    wsl.exe --terminate Ubuntu-Monk 2>$null
    wsl.exe --unregister Ubuntu-Monk
    return
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
}

Stop-ManagedAgent
Remove-AgentFiles
if ($Runtime) {
  Remove-MonkRuntime
}

Write-Host "monk-agent uninstall complete."
