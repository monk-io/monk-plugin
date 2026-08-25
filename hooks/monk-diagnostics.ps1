<#
.SYNOPSIS
    Monk diagnostics script for Windows PowerShell
.DESCRIPTION
    This script checks the health of the Monk runtime and agent
#>

$ErrorActionPreference = "Stop"

function Write-Info { param([string]$Message) Write-Host "[INFO] $Message" -ForegroundColor Green }
function Write-Warn { param([string]$Message) Write-Host "[WARN] $Message" -ForegroundColor Yellow }
function Write-ErrorMsg { param([string]$Message) Write-Host "[ERROR] $Message" -ForegroundColor Red }

# Check if monkd is running and reachable
function Check-Monkd {
    Write-Info "Checking monkd connectivity..."
    
    # Check if monkd process is running
    $monkdProcess = Get-Process -Name "monkd" -ErrorAction SilentlyContinue
    if (-not $monkdProcess) {
        Write-ErrorMsg "monkd process not found"
        return $false
    }
    Write-Info "monkd process is running (PID: $($monkdProcess.Id))"
    
    # Check if the gRPC port is listening (port 2137)
    # Note: Port 2137 speaks gRPC/WebSocket, not HTTP - so we check TCP connectivity only
    $listener = Get-NetTCPConnection -LocalPort 2137 -State Listen -ErrorAction SilentlyContinue
    if ($listener) {
        Write-Info "monkd gRPC port 2137 is listening"
    } else {
        Write-ErrorMsg "monkd gRPC port 2137 is not listening"
        return $false
    }
    
    # Try to use monk CLI to verify full connectivity
    if (Get-Command "monk" -ErrorAction SilentlyContinue) {
        try {
            monk version | Out-Null
            Write-Info "monk CLI reports daemon is reachable"
        } catch {
            Write-Warn "monk CLI cannot reach daemon (may need auth)"
        }
    } else {
        Write-Warn "monk CLI not in PATH"
    }
    
    return $true
}

# Check if monk-agent is running
function Check-MonkAgent {
    Write-Info "Checking monk-agent connectivity..."
    
    # Check if monk-agent process is running
    $agentProcess = Get-Process -Name "monk-agent" -ErrorAction SilentlyContinue
    if (-not $agentProcess) {
        Write-ErrorMsg "monk-agent process not found"
        return $false
    }
    Write-Info "monk-agent process is running (PID: $($agentProcess.Id))"
    
    # Check MCP server port (default 2138)
    $listener = Get-NetTCPConnection -LocalPort 2138 -State Listen -ErrorAction SilentlyContinue
    if ($listener) {
        Write-Info "monk-agent MCP port 2138 is listening"
    } else {
        Write-Warn "monk-agent MCP port 2138 is not listening"
    }
    
    return $true
}

# Main
Write-Host "=== Monk Diagnostics ==="
Write-Host ""

$monkdOk = Check-Monkd
Write-Host ""
$agentOk = Check-MonkAgent
Write-Host ""
Write-Host "=== Summary ==="
if ($monkdOk -and $agentOk) {
    Write-Info "All checks passed"
    exit 0
} else {
    Write-ErrorMsg "Some checks failed"
    exit 1
}
