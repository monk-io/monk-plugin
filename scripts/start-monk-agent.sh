#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

host="${MONK_AGENT_HOST:-127.0.0.1}"
port="${MONK_AGENT_PORT:-7419}"

log() {
  echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*" >&2
}

register_mcp() {
  local mcp_cfg="$HOME/.gemini/config/mcp_config.json"
  local server_url="http://$host:$port/mcp"
  
  log "Registering Monk MCP at $server_url"
  
  if [ ! -d "$(dirname "$mcp_cfg")" ]; then
    mkdir -p "$(dirname "$mcp_cfg")"
  fi
  
  if [ ! -f "$mcp_cfg" ]; then
    echo '{"mcpServers":{}}' > "$mcp_cfg"
  fi
  
  local current_url=""
  if command -v jq >/dev/null 2>&1; then
    current_url=$(jq -r '.mcpServers.monk.serverUrl // ""' "$mcp_cfg" 2>/dev/null || echo "")
  else
    current_url=$(grep -o '"monk"[^}]*"serverUrl"[[:space:]]*:[[:space:]]*"[^"]*"' "$mcp_cfg" 2>/dev/null | sed -n 's/.*"serverUrl"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' || echo "")
  fi
  
  if [ "$current_url" = "$server_url" ]; then
    log "Monk MCP already registered at correct URL: $server_url"
    return 0
  fi
  
  if [ -n "$current_url" ]; then
    log "Updating stale Monk MCP registration from $current_url to $server_url"
  fi
  
  if command -v jq >/dev/null 2>&1; then
    local tmp_file="${mcp_cfg}.tmp"
    jq --arg url "$server_url" '.mcpServers.monk = {"serverUrl": $url}' "$mcp_cfg" > "$tmp_file" && mv "$tmp_file" "$mcp_cfg"
  else
    if grep -q '"monk"' "$mcp_cfg" 2>/dev/null; then
      sed -i.bak 's|"monk"[[:space:]]*:[[:space:]]*{[^}]*}|"monk": {"serverUrl": "'"$server_url"'"}|' "$mcp_cfg"
      rm -f "${mcp_cfg}.bak"
    else
      local tmp_file="${mcp_cfg}.tmp"
      sed 's/{"mcpServers":{/{"mcpServers":{"monk":{"serverUrl":"'"$server_url"'"},/' "$mcp_cfg" > "$tmp_file" && mv "$tmp_file" "$mcp_cfg"
    fi
  fi
  
  log "Monk MCP registered successfully"
}

start_agent() {
  log "Starting Monk agent on $host:$port"
  
  cd "$PROJECT_ROOT"
  
  export MONK_AGENT_HOST="$host"
  export MONK_AGENT_PORT="$port"
  
  if [ -f "package.json" ]; then
    if [ ! -d "node_modules" ]; then
      log "Installing dependencies..."
      npm install
    fi
    
    log "Starting agent with npm start"
    npm start
  else
    log "ERROR: package.json not found in $PROJECT_ROOT"
    exit 1
  fi
}

register_mcp
start_agent
