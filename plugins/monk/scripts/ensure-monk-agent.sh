#!/usr/bin/env bash
# Ensure monk-agent is running. If not, start it.
# Also handles WSL Ubuntu-Monk distro stopped state recovery.

set -euo pipefail

LOG_FILE="${HOME}/.monk/ensure-monk-agent.log"
mkdir -p "$(dirname "$LOG_FILE")"

exec >>"$LOG_FILE" 2>&1
echo "[$(date)] ensure-monk-agent started"

# Check if monk-agent process is running
if pgrep -f "monk-agent" >/dev/null 2>&1; then
    echo "[$(date)] monk-agent already running"
    exit 0
fi

echo "[$(date)] monk-agent not running, checking prerequisites"

# Function to check and recover Ubuntu-Monk WSL distro
check_and_recover_wsl_distro() {
    # Only relevant on Windows with WSL
    if ! command -v wsl.exe >/dev/null 2>&1; then
        return 0
    fi

    local distro_state
    distro_state=$(wsl.exe -l -v 2>/dev/null | grep -i "ubuntu-monk" | awk '{print $NF}' | tr -d '\r')
    
    if [[ "$distro_state" == "Stopped" ]]; then
        echo "[$(date)] Ubuntu-Monk distro is Stopped, attempting recovery..."
        
        # First try graceful shutdown
        wsl.exe --shutdown 2>/dev/null || true
        sleep 2
        
        # Start the distro
        if wsl.exe -d Ubuntu-Monk true 2>/dev/null; then
            echo "[$(date)] Ubuntu-Monk distro started successfully"
            sleep 3  # Give monkd time to start
            return 0
        else
            echo "[$(date)] Failed to start Ubuntu-Monk distro automatically"
            return 1
        fi
    fi
    
    return 0
}

# Attempt WSL distro recovery if needed
check_and_recover_wsl_distro

# Check if monkd is reachable on port 2137
check_monkd() {
    if command -v nc >/dev/null 2>&1; then
        nc -z 127.0.0.1 2137 >/dev/null 2>&1
    elif command -v timeout >/dev/null 2>&1; then
        timeout 1 bash -c "cat < /dev/null > /dev/tcp/127.0.0.1/2137" 2>/dev/null
    else
        # Fallback: try to connect with bash builtin
        (exec 3<>/dev/tcp/127.0.0.1/2137) 2>/dev/null && exec 3<&-
    fi
}

# Wait for monkd to become available (up to 30 seconds)
echo "[$(date)] Waiting for monkd on 127.0.0.1:2137..."
for i in {1..30}; do
    if check_monkd; then
        echo "[$(date)] monkd is reachable"
        break
    fi
    sleep 1
    if [[ $i -eq 30 ]]; then
        echo "[$(date)] ERROR: monkd not reachable after 30 seconds"
        echo "[$(date)] Hint: If using WSL, try 'wsl --shutdown' then restart Ubuntu-Monk"
        exit 1
    fi
done

# Start monk-agent
echo "[$(date)] Starting monk-agent..."
exec monk-agent >>"$LOG_FILE" 2>&1
