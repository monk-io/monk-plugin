#!/usr/bin/env bash
# Monk diagnostics script for Codex environments
# This script checks the health of the Monk runtime and agent

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() { echo -e "${GREEN}[INFO]${NC} $*"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*"; }

# Check if monkd is running and reachable
check_monkd() {
    log_info "Checking monkd connectivity..."
    
    # Check if monkd process is running
    if ! pgrep -x "monkd" > /dev/null; then
        log_error "monkd process not found"
        return 1
    fi
    log_info "monkd process is running"
    
    # Check if the gRPC port is listening (port 2137)
    # Note: Port 2137 speaks gRPC/WebSocket, not HTTP - so we check TCP connectivity only
    if command -v nc > /dev/null 2>&1; then
        if nc -z 127.0.0.1 2137 2>/dev/null; then
            log_info "monkd gRPC port 2137 is reachable"
        else
            log_error "monkd gRPC port 2137 is not reachable"
            return 1
        fi
    elif command -v ss > /dev/null 2>&1; then
        if ss -ltn | grep -q ':2137 '; then
            log_info "monkd gRPC port 2137 is listening"
        else
            log_error "monkd gRPC port 2137 is not listening"
            return 1
        fi
    elif command -v netstat > /dev/null 2>&1; then
        if netstat -ltn 2>/dev/null | grep -q ':2137 '; then
            log_info "monkd gRPC port 2137 is listening"
        else
            log_error "monkd gRPC port 2137 is not listening"
            return 1
        fi
    else
        log_warn "Cannot check port 2137 (nc, ss, netstat not available)"
    fi
    
    # Try to use monk CLI to verify full connectivity
    if command -v monk > /dev/null 2>&1; then
        if monk version > /dev/null 2>&1; then
            log_info "monk CLI reports daemon is reachable"
        else
            log_warn "monk CLI cannot reach daemon (may need auth)"
        fi
    else
        log_warn "monk CLI not in PATH"
    fi
    
    return 0
}

# Check if monk-agent is running
check_monk_agent() {
    log_info "Checking monk-agent connectivity..."
    
    # Check if monk-agent process is running
    if ! pgrep -f "monk-agent" > /dev/null; then
        log_error "monk-agent process not found"
        return 1
    fi
    log_info "monk-agent process is running"
    
    # Check MCP server port (default 2138)
    if command -v nc > /dev/null 2>&1; then
        if nc -z 127.0.0.1 2138 2>/dev/null; then
            log_info "monk-agent MCP port 2138 is reachable"
        else
            log_warn "monk-agent MCP port 2138 is not reachable"
        fi
    fi
    
    return 0
}

# Main
echo "=== Monk Diagnostics ==="
echo ""

check_monkd
MONKD_STATUS=$?

echo ""

check_monk_agent
AGENT_STATUS=$?

echo ""
echo "=== Summary ==="
if [ $MONKD_STATUS -eq 0 ] && [ $AGENT_STATUS -eq 0 ]; then
    log_info "All checks passed"
    exit 0
else
    log_error "Some checks failed"
    exit 1
fi
