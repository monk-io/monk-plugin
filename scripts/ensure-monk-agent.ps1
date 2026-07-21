$ErrorActionPreference = "Stop"

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

  if (-not $ProcessPath -or ([IO.Path]::GetFileName($ProcessPath) -ieq "monk-agent.exe")) {
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

  Invoke-WebRequest -Uri $ChecksumUrl -OutFile $ChecksumTmp

  $Expected = ((Get-Content -Raw $ChecksumTmp).Trim() -split "\s+")[0].ToLowerInvariant()

  if ((Test-Path $Target) -and (Test-Path $ChecksumInstalled)) {
    $Installed = ((Get-Content -Raw $ChecksumInstalled).Trim() -split "\s+")[0].ToLowerInvariant()
    if ($Installed -eq $Expected) {
      Remove-Item -Force $ChecksumTmp
      Write-Output $Target
      exit 0
    }
  }

  Write-Host "Installing monk-agent from $Url"
  Invoke-WebRequest -Uri $Url -OutFile $ArchiveTmp

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
