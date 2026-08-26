<#
.SYNOPSIS
    Monk diagnostics hook - checks health of monk installation
#>

$ErrorActionPreference = "Continue"

Write-Host "=== Monk Diagnostics ==="
Write-Host "Date: $(Get-Date)"
Write-Host ""

Write-Host "--- monk-agent process ---"
$monkAgent = Get-Process -Name "monk-agent" -ErrorAction SilentlyContinue
if ($monkAgent) {
    Write-Host "monk-agent: RUNNING"
    $monkAgent | ForEach-Object { Write-Host "  PID: $($_.Id)" }
} else {
    Write-Host "monk-agent: NOT RUNNING"
}
Write-Host ""

Write-Host "--- monkd connectivity (127.0.0.1:2137) ---"
try {
    $tcp = New-Object System.Net.Sockets.TcpClient
    $connect = $tcp.BeginConnect("127.0.0.1", 2137, $null, $null)
    $wait = $connect.AsyncWaitHandle.WaitOne(1000)
    if ($wait -and $tcp.Connected) {
        Write-Host "monkd: REACHABLE"
    } else {
        Write-Host "monkd: UNREACHABLE (ECONNREFUSED)"
    }
    $tcp.Close()
} catch {
    Write-Host "monkd: UNREACHABLE (ECONNREFUSED)"
}
Write-Host ""

Write-Host "--- WSL Ubuntu-Monk distro status ---"
if (Get-Command wsl.exe -ErrorAction SilentlyContinue) {
    $distroInfo = wsl.exe -l -v 2>$null | Where-Object { $_ -match 'Ubuntu-Monk' }
    if ($distroInfo) {
        Write-Host $distroInfo
        $parts = $distroInfo -split '\s+'
        $state = $parts[-1].Trim()
        if ($state -eq "Stopped") {
            Write-Host ""
            Write-Host "ISSUE DETECTED: Ubuntu-Monk distro is Stopped" -ForegroundColor Yellow
            Write-Host "RECOVERY: Run 'wsl --shutdown' then start Ubuntu-Monk, or use 'Monk: Restart Runtime' command" -ForegroundColor Cyan
        }
    } else {
        Write-Host "Ubuntu-Monk: NOT FOUND"
    }
} else {
    Write-Host "WSL: NOT AVAILABLE"
}
Write-Host ""

Write-Host "--- monk version ---"
if (Get-Command monk -ErrorAction SilentlyContinue) {
    monk --version 2>$null
} else {
    Write-Host "monk CLI: NOT IN PATH"
}
