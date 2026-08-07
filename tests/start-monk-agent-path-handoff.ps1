$ErrorActionPreference = "Stop"

# Regression coverage for switching between two custom MONK_AGENT_PATH values.
# The launcher must authenticate the recorded PID against the executable that
# started it, stop that process, and then hand ownership to the new executable.

$Repo = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$Root = Join-Path ([IO.Path]::GetTempPath()) ("monk-path-handoff-" + [guid]::NewGuid().ToString("N"))
$SourcePath = Join-Path $Root "fake-agent.cs"
$OldAgentPath = Join-Path $Root "old-agent.exe"
$NewAgentPath = Join-Path $Root "new-agent.exe"
$MonkHome = Join-Path $Root "home"
$RunDir = Join-Path $MonkHome "agent\launcher\run"
$PidFile = Join-Path $RunDir "monk-agent.pid"
$StateFile = Join-Path $RunDir "monk-agent.state"
$NewPidFile = Join-Path $Root "new-agent.pid"
$StdoutPath = Join-Path $Root "launcher.out.log"
$StderrPath = Join-Path $Root "launcher.err.log"
$OldProcess = $null
$NewProcess = $null
$Launcher = $null

$EnvironmentNames = @(
  "MONK_AGENT_HOME",
  "MONK_AGENT_PATH",
  "MONK_AGENT_PORT",
  "MONK_AGENT_READY_TIMEOUT",
  "MONK_AGENT_SKIP_ENSURE",
  "MONK_AGENT_SKIP_SIGNIN_NUDGE",
  "MONK_PLUGIN_VERSION",
  "NEW_AGENT_PID_FILE",
  "NO_COLOR"
)
$OriginalEnvironment = @{}
foreach ($Name in $EnvironmentNames) {
  $OriginalEnvironment[$Name] = [Environment]::GetEnvironmentVariable($Name, "Process")
}

function Test-ProcessAlive {
  param([int]$ProcessId)
  return $null -ne (Get-Process -Id $ProcessId -ErrorAction SilentlyContinue)
}

try {
  New-Item -ItemType Directory -Force -Path $Root, $RunDir | Out-Null

  # Both files contain the same small companion. The first occupies the health
  # endpoint. The replacement retries that endpoint briefly, then exits cleanly
  # if its predecessor was not stopped, matching the real companion's behavior.
  @"
using System;
using System.Diagnostics;
using System.IO;
using System.Net;
using System.Net.Sockets;
using System.Text;
using System.Threading;

class Program
{
    static int Main(string[] args)
    {
        bool oldMode = args.Length > 0 && args[0] == "old";
        int port = 0;
        if (oldMode)
        {
            port = int.Parse(args[1]);
        }
        else
        {
            for (int i = 0; i + 1 < args.Length; i++)
            {
                if (args[i] == "--port")
                {
                    port = int.Parse(args[i + 1]);
                    break;
                }
            }
            string pidFile = Environment.GetEnvironmentVariable("NEW_AGENT_PID_FILE");
            if (!String.IsNullOrEmpty(pidFile))
            {
                File.WriteAllText(pidFile, Process.GetCurrentProcess().Id.ToString());
            }
        }

        TcpListener listener = null;
        for (int attempt = 0; attempt < 10; attempt++)
        {
            try
            {
                listener = new TcpListener(IPAddress.Loopback, port);
                listener.Start();
                break;
            }
            catch (SocketException)
            {
                if (listener != null) listener.Stop();
                listener = null;
                Thread.Sleep(250);
            }
        }
        if (listener == null) return 0;

        string body = "{\"resource\":\"http://127.0.0.1:" + port + "/mcp\"}";
        byte[] payload = Encoding.UTF8.GetBytes(body);
        while (true)
        {
            using (TcpClient client = listener.AcceptTcpClient())
            using (NetworkStream stream = client.GetStream())
            {
                byte[] request = new byte[4096];
                stream.Read(request, 0, request.Length);
                string headers = "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: " +
                    payload.Length + "\r\nConnection: close\r\n\r\n";
                byte[] headerBytes = Encoding.ASCII.GetBytes(headers);
                stream.Write(headerBytes, 0, headerBytes.Length);
                stream.Write(payload, 0, payload.Length);
            }
        }
    }
}
"@ | Set-Content -Encoding UTF8 $SourcePath

  $Csc = Join-Path $env:WINDIR "Microsoft.NET\Framework64\v4.0.30319\csc.exe"
  if (-not (Test-Path $Csc)) {
    $Csc = (Get-ChildItem "$env:WINDIR\Microsoft.NET\Framework64" -Filter csc.exe -Recurse -ErrorAction SilentlyContinue |
      Select-Object -First 1 -ExpandProperty FullName)
  }
  if (-not $Csc) {
    throw "csc.exe not found; cannot build the custom path handoff fixture"
  }
  & $Csc /nologo /out:$OldAgentPath $SourcePath | Out-Null
  if (-not (Test-Path $OldAgentPath)) {
    throw "failed to compile old-agent.exe"
  }
  Copy-Item -LiteralPath $OldAgentPath -Destination $NewAgentPath

  $PortProbe = [Net.Sockets.TcpListener]::new([Net.IPAddress]::Loopback, 0)
  $PortProbe.Start()
  $Port = ([Net.IPEndPoint]$PortProbe.LocalEndpoint).Port
  $PortProbe.Stop()

  $OldProcess = Start-Process -FilePath $OldAgentPath -ArgumentList @("old", $Port) -PassThru
  $HealthUrl = "http://127.0.0.1:$Port/.well-known/oauth-protected-resource"
  $Ready = $false
  for ($Attempt = 0; $Attempt -lt 20; $Attempt++) {
    try {
      $Response = Invoke-WebRequest -Uri $HealthUrl -UseBasicParsing -NoProxy -TimeoutSec 1
      if ($Response.Content -match '"resource"') {
        $Ready = $true
        break
      }
    } catch {
      Start-Sleep -Milliseconds 100
    }
  }
  if (-not $Ready) {
    throw "old custom companion did not become ready"
  }

  $OldProcess.Id | Set-Content -NoNewline -Encoding ASCII $PidFile
  . (Join-Path $Repo "scripts\plugin-version.ps1")
  @(
    "agent_path=$OldAgentPath",
    "auth_url=https://auth.monk.io",
    "auth_client_id=UW84YWcJME3buMSLfqLX8IbBsYdNWi47",
    "auth_audience=oaknode.com",
    "autospin_url=wss://api.app.monk.io/autospin/",
    "plugin_version=$env:MONK_PLUGIN_VERSION"
  ) -join "`n" | Set-Content -NoNewline -Encoding ASCII $StateFile

  $env:MONK_AGENT_HOME = $MonkHome
  $env:MONK_AGENT_PATH = $NewAgentPath
  $env:MONK_AGENT_PORT = [string]$Port
  $env:MONK_AGENT_READY_TIMEOUT = "10"
  $env:MONK_AGENT_SKIP_ENSURE = "1"
  $env:MONK_AGENT_SKIP_SIGNIN_NUDGE = "1"
  $env:NEW_AGENT_PID_FILE = $NewPidFile
  $env:NO_COLOR = "1"

  $LauncherPath = Join-Path $Repo "scripts\start-monk-agent.ps1"
  $ChildCommand = "`$ErrorView = 'NormalView'; & '$LauncherPath'"
  $Launcher = Start-Process -FilePath (Get-Process -Id $PID).Path `
    -ArgumentList @("-NoLogo", "-NoProfile", "-Command", $ChildCommand) `
    -PassThru -RedirectStandardOutput $StdoutPath -RedirectStandardError $StderrPath
  $Finished = $Launcher.WaitForExit(20000)
  if (-not $Finished) {
    throw "launcher did not exit within the bounded test wait"
  }
  $Output = (Get-Content -Raw $StdoutPath -ErrorAction SilentlyContinue) +
    (Get-Content -Raw $StderrPath -ErrorAction SilentlyContinue)
  if ($Launcher.ExitCode -ne 0) {
    throw "expected launcher exit 0, got $($Launcher.ExitCode): $Output"
  }

  for ($Attempt = 0; $Attempt -lt 20 -and -not (Test-Path $NewPidFile); $Attempt++) {
    Start-Sleep -Milliseconds 100
  }
  if (-not (Test-Path $NewPidFile)) {
    throw "replacement custom companion did not record its PID"
  }
  $NewPid = [int](Get-Content -Raw $NewPidFile)
  $NewProcess = Get-Process -Id $NewPid -ErrorAction SilentlyContinue
  Start-Sleep -Seconds 3

  if (Test-ProcessAlive $OldProcess.Id) {
    if (-not (Test-ProcessAlive $NewPid)) {
      throw "launcher returned success against the old custom companion while the replacement exited"
    }
    throw "old custom companion remained alive after MONK_AGENT_PATH changed"
  }
  if (-not (Test-ProcessAlive $NewPid)) {
    throw "replacement custom companion is not running"
  }
  if ([int](Get-Content -Raw $PidFile) -ne $NewPid) {
    throw "launcher PID file does not belong to the replacement companion"
  }
  $State = Get-Content -Raw $StateFile
  if (($State -split "`r?`n") -cnotcontains "agent_path=$NewAgentPath") {
    throw "launcher state does not record the replacement custom path"
  }

  $ShippedCopies = @(
    ".antigravity-plugin\scripts\start-monk-agent.ps1",
    "plugins\monk\scripts\start-monk-agent.ps1"
  )
  $ExpectedHash = (Get-FileHash -Algorithm SHA256 $LauncherPath).Hash
  foreach ($RelativePath in $ShippedCopies) {
    $CopyHash = (Get-FileHash -Algorithm SHA256 (Join-Path $Repo $RelativePath)).Hash
    if ($CopyHash -ne $ExpectedHash) {
      throw "shipped PowerShell launcher differs: $RelativePath"
    }
  }

  Write-Host "custom_agent_path_handoff_status=pass"
} finally {
  foreach ($Process in @($Launcher, $NewProcess, $OldProcess)) {
    if ($null -ne $Process) {
      Stop-Process -Id $Process.Id -Force -ErrorAction SilentlyContinue
    }
  }
  if (Test-Path $PidFile) {
    $RecordedPid = (Get-Content -Raw $PidFile).Trim()
    if ($RecordedPid -match "^[0-9]+$") {
      Stop-Process -Id ([int]$RecordedPid) -Force -ErrorAction SilentlyContinue
    }
  }
  foreach ($Name in $EnvironmentNames) {
    [Environment]::SetEnvironmentVariable($Name, $OriginalEnvironment[$Name], "Process")
  }
  Remove-Item -LiteralPath $Root -Recurse -Force -ErrorAction SilentlyContinue
}
