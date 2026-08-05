$ErrorActionPreference = "Stop"

# Windows PowerShell 5.1 renders an Invoke-WebRequest progress record per read
# chunk, and that rendering — not the network — dominates a large download. This
# installer runs inside the blocking SessionStart hook, so the cost is charged
# directly against the host's startup budget. Measured on 5.1.19041 pulling the
# 62MB windows agent archive over a ~10MB/s link:
#
#   Invoke-WebRequest -OutFile, progress on    46.5s  (1.3 MB/s)
#   Invoke-WebRequest -OutFile, progress off    6.0s  (10.4 MB/s)
#   WebClient.DownloadFile                      5.9s  (10.6 MB/s)
#
# A 7.7x penalty, ~40s of pure progress rendering. That is enough on its own to
# blow the VSCode extension's 60s subprocess-init ceiling on any release that
# ships a new agent binary: an observed upgrade spent 46.5s here and had the
# agent up 3s after the extension had already given up on the session. Suppressed
# rather than switched to WebClient because silencing progress already reaches
# line rate, so the cmdlet's redirect/proxy/TLS handling is worth keeping.
#
# Deliberately script-scoped: this process is a short-lived installer whose only
# console output is the "Installing monk-agent" line, so there is no interactive
# progress worth preserving. Also covers Expand-Archive below (1.8s, not a
# bottleneck — left alone).
$ProgressPreference = "SilentlyContinue"

$InstallDir = if ($env:MONK_AGENT_INSTALL_DIR) { $env:MONK_AGENT_INSTALL_DIR } else {
  Join-Path $HOME ".monk\bin"
}
$Channel = if ($env:MONK_AGENT_CHANNEL) { $env:MONK_AGENT_CHANNEL } else { "stable" }
$DownloadBase = if ($env:MONK_AGENT_DOWNLOAD_BASE) { $env:MONK_AGENT_DOWNLOAD_BASE } else {
  "https://get.monk.io/$Channel"
}
$AutoUpdate = if ($env:MONK_AGENT_AUTO_UPDATE) { $env:MONK_AGENT_AUTO_UPDATE } else { "1" }

$Target = Join-Path $InstallDir "monk-agent.exe"
$ChecksumInstalled = Join-Path $InstallDir "monk-agent.sha256"
$MonkHome = if ($env:MONK_AGENT_HOME) { $env:MONK_AGENT_HOME } else { Join-Path $HOME ".monk" }
$PidFile = Join-Path $MonkHome "agent\launcher\run\monk-agent.pid"

function Get-FileSha256 {
  param([string]$Path)
  if (-not (Test-Path $Path)) {
    return ""
  }

  if (Get-Command Get-FileHash -ErrorAction SilentlyContinue) {
    return (Get-FileHash -Algorithm SHA256 $Path).Hash.ToLowerInvariant()
  }

  $Stream = [System.IO.File]::OpenRead($Path)
  try {
    $Sha256 = [System.Security.Cryptography.SHA256]::Create()
    try {
      $Hash = $Sha256.ComputeHash($Stream)
    } finally {
      $Sha256.Dispose()
    }
  } finally {
    $Stream.Dispose()
  }
  return ([System.BitConverter]::ToString($Hash) -replace "-", "").ToLowerInvariant()
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

  $RawPid = (Get-Content -Raw $PidFile).Trim()
  if (-not $RawPid) {
    return
  }

  # Validate the PID is numeric before casting; a malformed PID file (text,
  # whitespace, BOM artifacts) would otherwise throw a terminating error under
  # ErrorActionPreference = "Stop". Treat non-numeric content as stale state.
  $ParsedPid = 0
  if (-not [int]::TryParse($RawPid, [ref]$ParsedPid) -or $ParsedPid -le 0) {
    Remove-Item -Force $PidFile -ErrorAction SilentlyContinue
    return
  }

  $OldProcess = Get-Process -Id $ParsedPid -ErrorAction SilentlyContinue
  if (-not $OldProcess) {
    Remove-Item -Force $PidFile -ErrorAction SilentlyContinue
    return
  }

  $ProcessPath = ""
  try {
    $ProcessPath = $OldProcess.Path
  } catch {
    $ProcessPath = ""
  }

  if (Test-SameFilePath $ProcessPath $Target) {
    Stop-Process -Id $OldProcess.Id -Force -ErrorAction SilentlyContinue
    try {
      Wait-Process -Id $OldProcess.Id -Timeout 10 -ErrorAction SilentlyContinue
    } catch {
      Start-Sleep -Milliseconds 500
    }
  }

  Remove-Item -Force $PidFile -ErrorAction SilentlyContinue
}

if ($AutoUpdate -eq "0" -or $AutoUpdate -eq "false") {
  if (Test-Path $Target) {
    Write-Output $Target
    exit 0
  }

  $Existing = Get-Command monk-agent.exe -ErrorAction SilentlyContinue
  if ($Existing) {
    Write-Output $Existing.Source
    exit 0
  }
}

$Arch = [System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture.ToString().ToLowerInvariant()
switch ($Arch) {
  "x64" { $Artifact = "monk-agent-windows-latest.zip" }
  default {
    Write-Error "Unsupported Windows architecture for monk-agent bootstrap: $Arch"
    exit 2
  }
}

$Url = "$DownloadBase/windows/$Artifact"
$ChecksumUrl = "$Url.sha256"
$ArchiveTmp = Join-Path $InstallDir ".monk-agent.tmp.zip"
$ChecksumTmp = Join-Path $InstallDir ".monk-agent.tmp.sha256"
$ExtractDir = Join-Path $InstallDir ".monk-agent.extract"
New-Item -ItemType Directory -Force -Path $InstallDir | Out-Null

# Launchers on different ports hold different launcher mutexes but still share
# these installer paths, so serialize the complete update transaction here.
$InstallerMutex = New-Object System.Threading.Mutex($false, "Local\monk-agent-installer")
$InstallerMutexOwned = $false
try {
  try {
    $InstallerMutexOwned = $InstallerMutex.WaitOne()
  } catch [System.Threading.AbandonedMutexException] {
    # A previous installer died while holding the mutex; ownership transfers to us.
    $InstallerMutexOwned = $true
  }

  Invoke-WebRequest -UseBasicParsing -Uri $ChecksumUrl -OutFile $ChecksumTmp

  $Expected = ((Get-Content -Raw $ChecksumTmp).Trim() -split "\s+")[0].ToLowerInvariant()

  if ((Test-Path $Target) -and (Get-Item $Target).Length -gt 0 -and (Test-Path $ChecksumInstalled)) {
    $Installed = ((Get-Content -Raw $ChecksumInstalled).Trim() -split "\s+")[0].ToLowerInvariant()
    if ($Installed -eq $Expected) {
      Remove-Item -Force $ChecksumTmp
      Write-Output $Target
      exit 0
    }
  }

  Write-Host "Installing monk-agent from $Url"
  Invoke-WebRequest -UseBasicParsing -Uri $Url -OutFile $ArchiveTmp

  $Actual = Get-FileSha256 $ArchiveTmp
  if ($Actual -ne $Expected) {
    Write-Error "Checksum verification failed for monk-agent."
    exit 1
  }

  if (Test-Path $ExtractDir) {
    Remove-Item -Recurse -Force $ExtractDir
  }
  New-Item -ItemType Directory -Force -Path $ExtractDir | Out-Null
  Expand-Archive -Force -Path $ArchiveTmp -DestinationPath $ExtractDir
  Stop-ManagedAgent
  Move-Item -Force (Join-Path $ExtractDir "monk-agent.exe") $Target
  "$Expected  $Artifact" | Set-Content -NoNewline $ChecksumInstalled
  Remove-Item -Recurse -Force $ExtractDir
  Remove-Item -Force $ArchiveTmp, $ChecksumTmp
  Write-Output $Target
} finally {
  if ($InstallerMutexOwned) {
    $InstallerMutex.ReleaseMutex()
  }
  $InstallerMutex.Dispose()
}
