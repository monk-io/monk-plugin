#!/usr/bin/env sh
set -e

MONK_AGENT_HOME="${MONK_AGENT_HOME:-$HOME/.monk}"
MONK_AGENT_INSTALL_DIR="${MONK_AGENT_INSTALL_DIR:-$MONK_AGENT_HOME/agent}"
MONK_AGENT_PATH="${MONK_AGENT_PATH:-$MONK_AGENT_INSTALL_DIR/monk-agent}"
MONK_AGENT_LAUNCHER_DIR="$MONK_AGENT_HOME/agent/launcher"
MONK_AGENT_PID_FILE="$MONK_AGENT_LAUNCHER_DIR/run/monk-agent.pid"
MONK_AGENT_LOG_FILE="$MONK_AGENT_LAUNCHER_DIR/logs/monk-agent.log"

ensure_monk_agent() {
  if [ -n "$MONK_AGENT_SKIP_ENSURE" ]; then
    return 0
  fi

  if [ ! -f "$MONK_AGENT_PATH" ]; then
    echo "Monk agent not found at $MONK_AGENT_PATH" >&2
    return 1
  fi

  mkdir -p "$MONK_AGENT_LAUNCHER_DIR/run" "$MONK_AGENT_LAUNCHER_DIR/logs"
}

register_mcp() {
  mcp_cfg="${GEMINI_CONFIG_DIR:-$HOME/.gemini/config}/mcp_config.json"

  if [ ! -f "$mcp_cfg" ]; then
    mkdir -p "$(dirname "$mcp_cfg")"
    echo '{"mcpServers":{}}' > "$mcp_cfg"
  fi

  if ! python3 -c "import json, sys; json.load(sys.stdin)" < "$mcp_cfg" 2>/dev/null; then
    echo "Warning: $mcp_cfg is not valid JSON, skipping MCP registration" >&2
    return 0
  fi

  has_monk_server=$(python3 - "$mcp_cfg" <<'PYEOF'
import json, sys
try:
    with open(sys.argv[1], "r", encoding="utf-8") as f:
        cfg = json.load(f)
    servers = cfg.get("mcpServers")
    if isinstance(servers, dict) and "monk" in servers:
        print("yes")
    else:
        print("no")
except Exception:
    print("no")
PYEOF
)

  if [ "$has_monk_server" = "yes" ]; then
    return 0
  fi

  companion_url="${MONK_COMPANION_URL:-http://localhost:44004}"
  mcp_resource=$(curl -sf "$companion_url/health" | python3 -c "import json, sys; print(json.load(sys.stdin).get('resource', ''))" 2>/dev/null || echo "")

  if [ -z "$mcp_resource" ]; then
    echo "Warning: Could not get MCP resource URL from companion" >&2
    return 0
  fi

  python3 - "$mcp_cfg" "$mcp_resource" <<'PYEOF'
import json, sys

try:
    with open(sys.argv[1], "r", encoding="utf-8") as f:
        cfg = json.load(f)
except Exception:
    cfg = {}

if not isinstance(cfg.get("mcpServers"), dict):
    cfg["mcpServers"] = {}

cfg["mcpServers"]["monk"] = {"serverUrl": sys.argv[2]}

with open(sys.argv[1], "w", encoding="utf-8") as f:
    json.dump(cfg, f, indent=2)
    f.write("\n")
PYEOF
}

start_agent() {
  if [ -f "$MONK_AGENT_PID_FILE" ]; then
    pid=$(cat "$MONK_AGENT_PID_FILE" 2>/dev/null || echo "")
    if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
      return 0
    fi
  fi

  nohup "$MONK_AGENT_PATH" >> "$MONK_AGENT_LOG_FILE" 2>&1 &
  echo $! > "$MONK_AGENT_PID_FILE"
}

main() {
  ensure_monk_agent
  register_mcp
  start_agent

  if [ -z "$MONK_AGENT_SKIP_SIGNIN_NUDGE" ]; then
    echo "Monk agent started. Sign in at http://localhost:44004"
  fi
}

main
