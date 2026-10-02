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
# ConnectTimeoutSec bounds only reaching a response (connect/TLS/headers);
# StallTimeoutSec is the real guard (see Invoke-FileDownload below) and should
# stay generous -- it only fires on near-zero throughput, not a merely slow
# one, so widening it costs nothing on a healthy connection.
$DownloadConnectTimeoutSec = if ($env:MONK_AGENT_DOWNLOAD_CONNECT_TIMEOUT) {
  [int]$env:MONK_AGENT_DOWNLOAD_CONNECT_TIMEOUT
} else { 15 }
$DownloadStallTimeoutSec = if ($env:MONK_AGENT_DOWNLOAD_STALL_TIMEOUT) {
  [int]$env:MONK_AGENT_DOWNLOAD_STALL_TIMEOUT
} else { 30 }

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

function Invoke-FileDownload {
  # Invoke-WebRequest's own -TimeoutSec (PS 5.1) is a hard cap on the whole
  # request, which would abort a slow-but-progressing download. HttpWebRequest
  # separates the two: .Timeout bounds only reaching a response (connect +
  # headers), while .ReadWriteTimeout is a per-read deadline that resets on
  # every chunk received -- a genuine stall guard. It shares
  # ServicePointManager with Invoke-WebRequest, so proxy/TLS handling is
  # unchanged; AllowAutoRedirect is set explicitly to preserve prior behavior.
  param(
    [string]$Uri,
    [string]$OutFile,
    [int]$ConnectTimeoutSec = 15,
    [int]$StallTimeoutSec = 30
  )
  $Request = [System.Net.HttpWebRequest]::Create($Uri)
  $Request.Method = "GET"
  $Request.AllowAutoRedirect = $true
  $Request.Timeout = $ConnectTimeoutSec * 1000
  $Request.ReadWriteTimeout = $StallTimeoutSec * 1000
  $Response = $Request.GetResponse()
  try {
    $ResponseStream = $Response.GetResponseStream()
    try {
      $FileStream = [System.IO.File]::Create($OutFile)
      try {
        $ResponseStream.CopyTo($FileStream)
      } finally {
        $FileStream.Dispose()
      }
    } finally {
      $ResponseStream.Dispose()
    }
  } finally {
    $Response.Dispose()
  }
}

# The public half of the key Monk releases are signed with (keys/monk-release.pub.pem),
# as RSA modulus and exponent: .NET Framework, which Windows PowerShell 5.1 runs on,
# can't read a PEM. Carried here rather than downloaded, so the download host can't
# swap it.
# @monk-release-key-begin
$MonkReleaseKeyModulus = "qZvBwFF2qcg8QgQQdPFDadR5dB0X+BcMSQmn/kz6liUAUiM93jK3Is+GOzTxGJT86PZXzo0E0NjLCCDvp9TRAyHm4umRh/xUI6mA97LMOPTDau3sMzKiK/At+ijmgwS5Md7KPhNY8/tGtF9/iRcVqQZ2k7fKtQ6RcUmXU30I/SNr0E/iJ8dDLxc7L6sPfbrV2qBNF08u06KysKnWwykw7lJOkNcJFbWtN6op7r+Rq2lB6kHtnB6gjY1voRiUZWfWEHl2A5lKLVwQNh8MpGmt85FBD58alUJOTXumIej7qz9IxWEi/vHjZfKDLrd9N9BH09MzzQGWnucZcgbUc5eN4vMwkRW5VjWINb/cKKZ9vaADvXB+TI5Liu5lxIlaQAaxwVHzHe00Br+swZDmNK1CM4bw4p9OecMBeNBpYvyfEvnqq2m9WHMEt0NnMppvPwAjnGxp6isghQDacB9arYHDN/Urk4xWqRLWntpERA0/FKLQAA09Nkk/ut/sOmBmOYiH"
$MonkReleaseKeyExponent = "AQAB"
# @monk-release-key-end

# Returns the sha256 the signed release list gives for $Name. Throws, saying why, if
# the list isn't signed by Monk's key or doesn't name the archive. Works on the raw
# bytes: the signature covers everything after the first line exactly as served.
function Get-VerifiedDigest {
  param([string]$Path, [string]$Name)
  $Bytes = [System.IO.File]::ReadAllBytes($Path)
  $Newline = [Array]::IndexOf($Bytes, [byte]10)
  $Header = if ($Newline -gt 0) { [System.Text.Encoding]::ASCII.GetString($Bytes, 0, $Newline).Trim() } else { "" }
  if (-not $Header.StartsWith("signature: ")) {
    throw "The Monk release list is not signed."
  }
  $Body = New-Object byte[] ($Bytes.Length - $Newline - 1)
  [Array]::Copy($Bytes, $Newline + 1, $Body, 0, $Body.Length)

  $Valid = $false
  $Rsa = New-Object System.Security.Cryptography.RSACryptoServiceProvider
  try {
    $Key = New-Object System.Security.Cryptography.RSAParameters
    $Key.Modulus = [Convert]::FromBase64String($MonkReleaseKeyModulus)
    $Key.Exponent = [Convert]::FromBase64String($MonkReleaseKeyExponent)
    $Rsa.ImportParameters($Key)
    $Signature = [Convert]::FromBase64String($Header.Substring(11))
    $Valid = $Rsa.VerifyData($Body, "SHA256", $Signature)
  } catch {
    $Valid = $false
  } finally {
    $Rsa.Dispose()
  }
  if (-not $Valid) {
    throw "The Monk release list is not signed by Monk's release key; not installing from it."
  }

  foreach ($Line in ([System.Text.Encoding]::UTF8.GetString($Body) -split "`n")) {
    $Fields = $Line.Trim() -split "\s+"
    if ($Fields.Count -eq 2 -and $Fields[1] -eq $Name -and $Fields[0] -match "^[0-9a-fA-F]{64}$") {
      return $Fields[0].ToLowerInvariant()
    }
  }
  throw "The Monk release list does not include $Name."
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
# The signed release list: a `signature:` line, then every archive's sha256
# (scripts/sign_release_manifest.sh). It replaces trusting the `.sha256` file
# next to the archive, which whoever can change the archive can change too.
$ChecksumUrl = "$DownloadBase/checksums.signed.txt"
$ArchiveTmp = Join-Path $InstallDir ".monk-agent.tmp.zip"
$ChecksumTmp = Join-Path $InstallDir ".monk-agent.tmp.signed"
$ExtractDir = Join-Path $InstallDir ".monk-agent.extract"
New-Item -ItemType Directory -Force -Path $InstallDir | Out-Null

# Launchers on different ports hold different launcher mutexes but still share
# these installer paths, so serialize the complete update transaction here.
$InstallLockTimeoutSec = 60
if ($env:MONK_AGENT_INSTALL_LOCK_TIMEOUT) {
  if (-not [int]::TryParse($env:MONK_AGENT_INSTALL_LOCK_TIMEOUT, [ref]$InstallLockTimeoutSec) -or $InstallLockTimeoutSec -lt 0) {
    Write-Error "MONK_AGENT_INSTALL_LOCK_TIMEOUT must be a non-negative integer."
    exit 2
  }
}
$InstallerMutex = New-Object System.Threading.Mutex($false, "Local\monk-agent-installer")
$InstallerMutexOwned = $false
try {
  try {
    $InstallerMutexOwned = $InstallerMutex.WaitOne([TimeSpan]::FromSeconds($InstallLockTimeoutSec))
  } catch [System.Threading.AbandonedMutexException] {
    # A previous installer died while holding the mutex; ownership transfers to us.
    $InstallerMutexOwned = $true
  }
  if (-not $InstallerMutexOwned) {
    Write-Error "Timed out after ${InstallLockTimeoutSec}s waiting for another monk-agent install."
    exit 1
  }

  # Invoke-FileDownload reads the response stream directly and never asks
  # Invoke-WebRequest to parse it, so the Internet Explorer engine dependency
  # that -UseBasicParsing exists to route around (ENG-501, unavailable on
  # Server Core / uninitialized on fresh desktop profiles) never comes into
  # play here.
  try {
    Invoke-FileDownload -Uri $ChecksumUrl -OutFile $ChecksumTmp `
      -ConnectTimeoutSec $DownloadConnectTimeoutSec -StallTimeoutSec $DownloadStallTimeoutSec
    $Expected = Get-VerifiedDigest $ChecksumTmp $Artifact
  } catch {
    # A transient failure fetching the release list, or a list that fails its
    # signature check, must not abort a cold start when a previously-verified
    # local binary is already installed (ENG-422) -- only fall back when that
    # binary's hash still matches the checksum recorded at install time.
    # Nothing new is installed from an unverified list.
    Write-Warning "$_"
    $Installed = ""
    if ((Test-Path $Target) -and (Test-Path $ChecksumInstalled)) {
      try {
        # The binary's own hash (line 2), not the archive's: comparing the archive
        # hash with the binary meant this fallback never matched after an install.
        $Lines = @((Get-Content $ChecksumInstalled) | Where-Object { $_.Trim() })
        $Line = if ($Lines.Count -ge 2) { $Lines[1] } else { $Lines[0] }
        $Installed = (($Line.Trim()) -split "\s+")[0].ToLowerInvariant()
      } catch {
        $Installed = ""
      }
    }

    $TargetSize = if (Test-Path $Target) { (Get-Item $Target).Length } else { 0 }
    $ActualInstalled = if ($TargetSize -gt 0) { Get-FileSha256 $Target } else { "" }
    if ($TargetSize -gt 0 -and
        $Installed -match "^[0-9a-f]{64}$" -and
        $ActualInstalled -eq $Installed) {
      Remove-Item -Force $ChecksumTmp -ErrorAction SilentlyContinue
      Write-Warning "Unable to check for monk-agent updates; using the previously checksummed installation at $Target."
      Write-Output $Target
      exit 0
    }

    throw
  }

  if ((Test-Path $Target) -and (Get-Item $Target).Length -gt 0 -and (Test-Path $ChecksumInstalled)) {
    $Installed = ((Get-Content -Raw $ChecksumInstalled).Trim() -split "\s+")[0].ToLowerInvariant()
    if ($Installed -eq $Expected) {
      Remove-Item -Force $ChecksumTmp
      Write-Output $Target
      exit 0
    }
  }

  Write-Host "Installing monk-agent from $Url"
  Invoke-FileDownload -Uri $Url -OutFile $ArchiveTmp `
    -ConnectTimeoutSec $DownloadConnectTimeoutSec -StallTimeoutSec $DownloadStallTimeoutSec

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
  # Line 1: the archive's sha256 and name, to tell when there's nothing new.
  # Line 2: the binary's own sha256, for the offline fallback above.
  "$Expected  $Artifact`n$(Get-FileSha256 $Target)  monk-agent.exe" | Set-Content -NoNewline $ChecksumInstalled
  Remove-Item -Recurse -Force $ExtractDir
  Remove-Item -Force $ArchiveTmp, $ChecksumTmp
  Write-Output $Target
} finally {
  if ($InstallerMutexOwned) {
    $InstallerMutex.ReleaseMutex()
  }
  $InstallerMutex.Dispose()
}
