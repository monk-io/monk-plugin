<#
.SYNOPSIS
    Ensure monk-agent is running. If not, start it.
    Also handles WSL Ubuntu-Monk distro stopped state recovery.
#>

$ErrorActionPreference = "Stop"

$LogFile = "$env:USERPROFILE\.monk\ensure-monk-agent.log"
$LogDir = Split-Path $LogFile
if (-not (Test-Path $LogDir)) { New-Item -ItemType Directory -Path $LogDir -Force | Out-Null }

function Write-Log {
    param([string]$Message)
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "[$timestamp] $Message" | Out-File -FilePath $LogFile -Append -Encoding utf8
}

Write-Log "ensure-monk-agent started"

# Check if monk-agent process is running
$monkAgent = Get-Process -Name "monk-agent" -ErrorAction SilentlyContinue
if ($monkAgent) {
    Write-Log "monk-agent already running"
    exit 0
}

Write-Log "monk-agent not running, checking prerequisites"

# Function to check and recover Ubuntu-Monk WSL distro
function Check-AndRecoverWslDistro {
    # Check if wsl.exe is available
    if (-not (Get-Command wsl.exe -ErrorAction SilentlyContinue)) {
        return $true
    }

    $distroInfo = wsl.exe -l -v 2>$null | Where-Object { $_ -match 'Ubuntu-Monk' }
    if (-not $distroInfo) {
        Write-Log "Ubuntu-Monk distro not found in WSL"
        return $true
    }

    # Parse state (last column)
    $parts = $distroInfo -split '\s+'
    $state = $parts[-1].Trim()
    
    if ($state -eq "Stopped") {
        Write-Log "Ubuntu-Monk distro is Stopped, attempting recovery..."
        
        # First try graceful shutdown
        wsl.exe --shutdown 2>$null
        Start-Sleep -Seconds 2
        
        # Start the distro
        try {
            wsl.exe -d Ubuntu-Monk -e true 2>$null | Out-Null
            Write-Log "Ubuntu-Monk distro started successfully"
            Start-Sleep -Seconds 3  # Give monkd time to start
            return $true
        } catch {
            Write-Log "Failed to start Ubuntu-Monk distro automatically: $_"
            return $false
        }
    }
    
    return $true
}

# Attempt WSL distro recovery if needed
Check-AndRecoverWslDistro

# Function to check if monkd is reachable on port 2137
function Test-Monkd {
    try {
        $tcp = New-Object System.Net.Sockets.TcpClient
        $connect = $tcp.BeginConnect("127.0.0.1", 2137, $null, $null)
        $wait = $connect.AsyncWaitHandle.WaitOne(1000)
        if ($wait -and $tcp.Connected) {
            $tcp.Close()
            return $true
        }
        $tcp.Close()
    } catch {}
    return $false
}

# Wait for monkd to become available (up to 30 seconds)
Write-Log "Waiting for monkd on 127.0.0.1:2137..."
for ($i = 1; $i -le 30; $i++) {
    if (Test-Monkd) {
        Write-Log "monkd is reachable"
        break
    }
    Start-Sleep -Seconds 1
    if ($i -eq 30) {
        Write-Log "ERROR: monkd not reachable after 30 seconds"
        Write-Log "Hint: If using WSL, try 'wsl --shutdown' then restart Ubuntu-Monk"
        exit 1
    }
}

# Start monk-agent
Write-Log "Starting monk-agent..."
& monk-agent *>&1 | Tee-Object -FilePath $LogFile -Append
