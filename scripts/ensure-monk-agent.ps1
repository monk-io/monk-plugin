$ErrorActionPreference = "Stop"

$InstallDir = if ($env:MONK_AGENT_INSTALL_DIR) { $env:MONK_AGENT_INSTALL_DIR } else {
  Join-Path $HOME ".monk\bin"
}
$Channel = if ($env:MONK_AGENT_CHANNEL) { $env:MONK_AGENT_CHANNEL } else { "nightly" }
$DownloadBase = if ($env:MONK_AGENT_DOWNLOAD_BASE) { $env:MONK_AGENT_DOWNLOAD_BASE } else {
  "https://get.monk.io/$Channel"
}
$AutoUpdate = if ($env:MONK_AGENT_AUTO_UPDATE) { $env:MONK_AGENT_AUTO_UPDATE } else { "1" }

$Target = Join-Path $InstallDir "monk-agent.exe"
$ChecksumInstalled = Join-Path $InstallDir "monk-agent.sha256"

if ($AutoUpdate -eq "0" -or $AutoUpdate -eq "false") {
  $Existing = Get-Command monk-agent.exe -ErrorAction SilentlyContinue
  if ($Existing) {
    Write-Output $Existing.Source
    exit 0
  }

  if (Test-Path $Target) {
    Write-Output $Target
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

$Actual = (Get-FileHash -Algorithm SHA256 $ArchiveTmp).Hash.ToLowerInvariant()
if ($Actual -ne $Expected) {
  Write-Error "Checksum verification failed for monk-agent."
  exit 1
}

if (Test-Path $ExtractDir) {
  Remove-Item -Recurse -Force $ExtractDir
}
New-Item -ItemType Directory -Force -Path $ExtractDir | Out-Null
Expand-Archive -Force -Path $ArchiveTmp -DestinationPath $ExtractDir
Move-Item -Force (Join-Path $ExtractDir "monk-agent.exe") $Target
"$Expected  $Artifact" | Set-Content -NoNewline $ChecksumInstalled
Remove-Item -Recurse -Force $ExtractDir
Remove-Item -Force $ArchiveTmp, $ChecksumTmp
Write-Output $Target
