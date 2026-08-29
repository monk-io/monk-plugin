$ErrorActionPreference = "Stop"

$RepoRoot = Split-Path -Parent $PSScriptRoot
$EnsureScript = Join-Path $RepoRoot "scripts\ensure-monk-agent.ps1"
$PowerShellExe = (Get-Command powershell.exe -ErrorAction SilentlyContinue).Source
if (-not $PowerShellExe) {
  $PowerShellExe = (Get-Process -Id $PID).Path
}

function New-TestListener {
  $Listener = [System.Net.Sockets.TcpListener]::new([Net.IPAddress]::Loopback, 0)
  $Listener.Start()
  return $Listener
}

function Start-InstallerProcess {
  param([string]$Root, [int]$Port)
  $env:MONK_AGENT_INSTALL_DIR = Join-Path $Root "install"
  $env:MONK_AGENT_HOME = Join-Path $Root "home"
  $env:MONK_AGENT_DOWNLOAD_BASE = "http://127.0.0.1:$Port"
  $env:MONK_AGENT_DOWNLOAD_CONNECT_TIMEOUT = "2"
  $env:MONK_AGENT_DOWNLOAD_STALL_TIMEOUT = "2"

  $Info = [Diagnostics.ProcessStartInfo]::new()
  $Info.FileName = $PowerShellExe
  $Info.UseShellExecute = $false
  $Info.RedirectStandardOutput = $true
  $Info.RedirectStandardError = $true
  if ($PowerShellExe -match '(?i)powershell\.exe$') {
    $Info.Arguments = "-NoLogo -NoProfile -ExecutionPolicy Bypass -File `"$EnsureScript`""
  } else {
    $Info.Arguments = "-NoLogo -NoProfile -File `"$EnsureScript`""
  }
  $Process = [Diagnostics.Process]::new()
  $Process.StartInfo = $Info
  if (-not $Process.Start()) { throw "failed to start installer child" }
  return $Process
}

function Wait-ForClient {
  param($Listener, $Process, [int]$TimeoutMs = 5000)
  $Deadline = [DateTime]::UtcNow.AddMilliseconds($TimeoutMs)
  while ([DateTime]::UtcNow -lt $Deadline) {
    if ($Listener.Pending()) { return $Listener.AcceptTcpClient() }
    if ($Process.HasExited) {
      $Process.WaitForExit()
      $Out = $Process.StandardOutput.ReadToEnd()
      $Err = $Process.StandardError.ReadToEnd()
      throw "installer exited before connecting (exit=$($Process.ExitCode)): stdout=[$Out] stderr=[$Err]"
    }
    Start-Sleep -Milliseconds 25
  }
  throw "installer did not connect to the fixture within ${TimeoutMs}ms"
}

function Wait-BoundedExit {
  param($Process, [int]$TimeoutMs = 7000)
  if (-not $Process.WaitForExit($TimeoutMs)) {
    try { $Process.Kill() } catch {}
    throw "installer exceeded its configured download deadline"
  }
  $Process.WaitForExit()
  return [pscustomobject]@{
    ExitCode = $Process.ExitCode
    Stdout = $Process.StandardOutput.ReadToEnd()
    Stderr = $Process.StandardError.ReadToEnd()
  }
}

$TempRoot = Join-Path ([IO.Path]::GetTempPath()) ("monk-win-download-timeout-" + [guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Force -Path $TempRoot | Out-Null
$Saved = @{}
foreach ($Name in @(
  "MONK_AGENT_INSTALL_DIR",
  "MONK_AGENT_HOME",
  "MONK_AGENT_DOWNLOAD_BASE",
  "MONK_AGENT_DOWNLOAD_CONNECT_TIMEOUT",
  "MONK_AGENT_DOWNLOAD_STALL_TIMEOUT"
)) {
  $Saved[$Name] = [Environment]::GetEnvironmentVariable($Name, "Process")
}

try {
  # Control 1: the TCP connection succeeds, but the server never sends response
  # headers. The connect/request deadline must terminate the installer.
  $Listener = New-TestListener
  try {
    $Port = ([Net.IPEndPoint]$Listener.LocalEndpoint).Port
    $P = Start-InstallerProcess (Join-Path $TempRoot "headers") $Port
    $Client = Wait-ForClient $Listener $P
    try {
      $Timer = [Diagnostics.Stopwatch]::StartNew()
      $Result = Wait-BoundedExit $P
      $Timer.Stop()
      if ($Result.ExitCode -eq 0) { throw "header-stall installer unexpectedly succeeded" }
      if ($Timer.Elapsed.TotalSeconds -gt 6) { throw "header stall was not bounded: $($Timer.Elapsed.TotalSeconds)s" }
    } finally {
      $Client.Dispose()
    }
  } finally {
    $Listener.Stop()
  }

  # Control 2: checksum completes, archive returns HTTP 200 plus three bytes and
  # then makes no further progress. ReadWriteTimeout must terminate that stream
  # without imposing an absolute deadline on a normally advancing download.
  $Listener = New-TestListener
  try {
    $Port = ([Net.IPEndPoint]$Listener.LocalEndpoint).Port
    $P = Start-InstallerProcess (Join-Path $TempRoot "body") $Port

    $ChecksumClient = Wait-ForClient $Listener $P
    try {
      $Stream = $ChecksumClient.GetStream()
      $Body = ([string]::new('0', 64) + "  monk-agent-windows-latest.zip`n")
      $Bytes = [Text.Encoding]::ASCII.GetBytes($Body)
      $Header = [Text.Encoding]::ASCII.GetBytes("HTTP/1.1 200 OK`r`nContent-Length: $($Bytes.Length)`r`nConnection: close`r`n`r`n")
      $Stream.Write($Header, 0, $Header.Length)
      $Stream.Write($Bytes, 0, $Bytes.Length)
      $Stream.Flush()
    } finally {
      $ChecksumClient.Dispose()
    }

    $ArchiveClient = Wait-ForClient $Listener $P
    try {
      $Stream = $ArchiveClient.GetStream()
      $Header = [Text.Encoding]::ASCII.GetBytes("HTTP/1.1 200 OK`r`nContent-Length: 100000`r`nConnection: close`r`n`r`nabc")
      $Stream.Write($Header, 0, $Header.Length)
      $Stream.Flush()
      $Timer = [Diagnostics.Stopwatch]::StartNew()
      $Result = Wait-BoundedExit $P
      $Timer.Stop()
      if ($Result.ExitCode -eq 0) { throw "body-stall installer unexpectedly succeeded" }
      if ($Timer.Elapsed.TotalSeconds -gt 6) { throw "body stall was not bounded: $($Timer.Elapsed.TotalSeconds)s" }
    } finally {
      $ArchiveClient.Dispose()
    }
  } finally {
    $Listener.Stop()
  }

  $Copies = @(
    "scripts\ensure-monk-agent.ps1",
    "plugins\monk\scripts\ensure-monk-agent.ps1",
    ".antigravity-plugin\scripts\ensure-monk-agent.ps1"
  ) | ForEach-Object { Join-Path $RepoRoot $_ }
  $Hashes = $Copies | ForEach-Object { (Get-FileHash -Algorithm SHA256 $_).Hash }
  if (($Hashes | Select-Object -Unique).Count -ne 1) {
    throw "distributed PowerShell installer copies differ"
  }

  Write-Host "windows_download_timeout_status=pass header_stall=bounded body_stall=bounded copies=3"
} finally {
  foreach ($Name in $Saved.Keys) {
    [Environment]::SetEnvironmentVariable($Name, $Saved[$Name], "Process")
  }
  Remove-Item -Recurse -Force $TempRoot -ErrorAction SilentlyContinue
}
