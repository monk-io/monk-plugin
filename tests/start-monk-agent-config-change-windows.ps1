$ErrorActionPreference = "Stop"

$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$Launcher = Join-Path $RepoRoot "scripts\start-monk-agent.ps1"
$TestRoot = Join-Path ([IO.Path]::GetTempPath()) ("monk-launcher-config-" + [guid]::NewGuid().ToString("N"))
$InstallDir = Join-Path $TestRoot "install"
$MonkHome = Join-Path $TestRoot "home"
$CapturePath = Join-Path $TestRoot "starts.log"
$Port = Get-Random -Minimum 20000 -Maximum 45000
$ServerJob = $null
$Previous = @{}

try {
  New-Item -ItemType Directory -Force -Path $InstallDir, $MonkHome | Out-Null

  $AgentPath = Join-Path $InstallDir "monk-agent.exe"
  $AgentSource = @'
using System;
using System.IO;

public static class FakeMonkAgent
{
    public static int Main()
    {
        var capture = Environment.GetEnvironmentVariable("MONK_CAPTURE_PATH");
        File.AppendAllText(capture,
            "auth=" + Environment.GetEnvironmentVariable("MONK_AUTH_URL") + Environment.NewLine);
        return 0;
    }
}
'@
  Add-Type -TypeDefinition $AgentSource -OutputAssembly $AgentPath -OutputType ConsoleApplication

  $ServerJob = Start-Job -ArgumentList $Port -ScriptBlock {
    param($ListenPort)
    $Listener = [Net.HttpListener]::new()
    $Listener.Prefixes.Add("http://127.0.0.1:$ListenPort/")
    $Listener.Start()
    try {
      while ($true) {
        $Context = $Listener.GetContext()
        $Body = '{"resource":"http://127.0.0.1:' + $ListenPort + '/mcp","signedIn":true}'
        $Bytes = [Text.Encoding]::UTF8.GetBytes($Body)
        $Context.Response.StatusCode = 200
        $Context.Response.ContentType = "application/json"
        $Context.Response.OutputStream.Write($Bytes, 0, $Bytes.Length)
        $Context.Response.Close()
      }
    } finally {
      $Listener.Close()
    }
  }

  $HealthUrl = "http://127.0.0.1:$Port/.well-known/oauth-protected-resource"
  $Ready = $false
  for ($Attempt = 0; $Attempt -lt 50; $Attempt++) {
    try {
      Invoke-WebRequest -UseBasicParsing -TimeoutSec 1 -Uri $HealthUrl | Out-Null
      $Ready = $true
      break
    } catch {
      Start-Sleep -Milliseconds 100
    }
  }
  if (-not $Ready) { throw "Health fixture did not start." }

  $Names = @(
    "MONK_AGENT_INSTALL_DIR", "MONK_AGENT_HOME", "MONK_AGENT_PORT",
    "MONK_AGENT_SKIP_ENSURE", "MONK_AGENT_SKIP_SIGNIN_NUDGE",
    "MONK_DISABLE_ANALYTICS", "MONK_CAPTURE_PATH", "MONK_AUTH_URL"
  )
  foreach ($Name in $Names) { $Previous[$Name] = [Environment]::GetEnvironmentVariable($Name, "Process") }

  $env:MONK_AGENT_INSTALL_DIR = $InstallDir
  $env:MONK_AGENT_HOME = $MonkHome
  $env:MONK_AGENT_PORT = [string]$Port
  $env:MONK_AGENT_SKIP_ENSURE = "1"
  $env:MONK_AGENT_SKIP_SIGNIN_NUDGE = "1"
  $env:MONK_DISABLE_ANALYTICS = "1"
  $env:MONK_CAPTURE_PATH = $CapturePath

  function Invoke-Launcher([string]$AuthUrl) {
    $env:MONK_AUTH_URL = $AuthUrl
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $Launcher
    if ($LASTEXITCODE -ne 0) { throw "Launcher exited with code $LASTEXITCODE." }
    Start-Sleep -Milliseconds 300
  }

  Invoke-Launcher "https://auth-one.invalid"
  Invoke-Launcher "https://auth-one.invalid"
  Invoke-Launcher "https://auth-two.invalid"
  Invoke-Launcher "https://auth-two.invalid"

  $Starts = @(Get-Content $CapturePath)
  if ($Starts.Count -ne 2) {
    throw "Expected two starts (initial plus configuration change), got $($Starts.Count): $($Starts -join ', ')"
  }
  if ($Starts[0] -ne "auth=https://auth-one.invalid" -or $Starts[1] -ne "auth=https://auth-two.invalid") {
    throw "Unexpected launch configurations: $($Starts -join ', ')"
  }

  $ConfigFile = Join-Path $MonkHome "agent\launcher\run\monk-agent.config"
  if (-not (Test-Path $ConfigFile) -or -not (Get-Content -Raw $ConfigFile).Trim()) {
    throw "Launcher configuration fingerprint was not persisted."
  }

  Write-Host "Windows launcher configuration-change regression passed."
} finally {
  foreach ($Name in $Previous.Keys) {
    [Environment]::SetEnvironmentVariable($Name, $Previous[$Name], "Process")
  }
  if ($ServerJob) {
    Stop-Job $ServerJob -ErrorAction SilentlyContinue
    Remove-Job $ServerJob -Force -ErrorAction SilentlyContinue
  }
  $ResolvedTemp = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
  $ResolvedTest = [IO.Path]::GetFullPath($TestRoot)
  if ($ResolvedTest.StartsWith($ResolvedTemp, [StringComparison]::OrdinalIgnoreCase) -and (Test-Path $ResolvedTest)) {
    Remove-Item -LiteralPath $ResolvedTest -Recurse -Force
  }
}
