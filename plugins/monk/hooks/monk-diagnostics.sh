#!/usr/bin/env bash
# Monk diagnostics hook - checks health of monk installation

set -euo pipefail

echo "=== Monk Diagnostics ==="
echo "Date: $(date)"
echo ""

echo "--- monk-agent process ---"
if pgrep -f "monk-agent" >/dev/null 2>&1; then
    echo "monk-agent: RUNNING"
    pgrep -f "monk-agent" | while read pid; do
        echo "  PID: $pid"
    done
else
    echo "monk-agent: NOT RUNNING"
fi
echo ""

echo "--- monkd connectivity (127.0.0.1:2137) ---"
if command -v nc >/dev/null 2>&1; then
    if nc -z 127.0.0.1 2137 >/dev/null 2>&1; then
        echo "monkd: REACHABLE"
    else
        echo "monkd: UNREACHABLE (ECONNREFUSED)"
    fi
elif command -v timeout >/dev/null 2>&1; then
    if timeout 1 bash -c "cat < /dev/null > /dev/tcp/127.0.0.1/2137" 2>/dev/null; then
        echo "monkd: REACHABLE"
    else
        echo "monkd: UNREACHABLE (ECONNREFUSED)"
    fi
else
    if (exec 3<>/dev/tcp/127.0.0.1/2137) 2>/dev/null; then
        exec 3<&-
        echo "monkd: REACHABLE"
    else
        echo "monkd: UNREACHABLE (ECONNREFUSED)"
    fi
fi
echo ""

echo "--- WSL Ubuntu-Monk distro status ---"
if command -v wsl.exe >/dev/null 2>&1; then
    wsl.exe -l -v 2>/dev/null | grep -i "ubuntu-monk" || echo "Ubuntu-Monk: NOT FOUND"
else
    echo "WSL: NOT AVAILABLE"
fi
echo ""

echo "--- monk version ---"
if command -v monk >/dev/null 2>&1; then
    monk --version 2>/dev/null || echo "monk CLI not in PATH"
else
    echo "monk CLI: NOT IN PATH"
fi
echo ""

echo "--- Recovery hint ---"
if command -v wsl.exe >/dev/null 2>&1; then
    distro_state=$(wsl.exe -l -v 2>/dev/null | grep -i "ubuntu-monk" | awk '{print $NF}' | tr -d '\r')
    if [[ "$distro_state" == "Stopped" ]]; then
        echo "ISSUE DETECTED: Ubuntu-Monk distro is Stopped"
        echo "RECOVERY: Run 'wsl --shutdown' then start Ubuntu-Monk, or use 'Monk: Restart Runtime' command"
    fi
fi
