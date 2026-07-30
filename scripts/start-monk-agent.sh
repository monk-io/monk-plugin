#!/bin/sh
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

AGENT_DIR="${AGENT_DIR:-$HOME/.monk}"
AGENT_BIN="$AGENT_DIR/monk-agent"
PID_FILE="$AGENT_DIR/monk-agent.pid"
LOG_FILE="$AGENT_DIR/monk-agent.log"
HEALTH_PORT="${MONK_AGENT_PORT:-28651}"
MAX_WAIT="${MONK_START_TIMEOUT:-30}"

ensure_agent_binary() {
  if [ ! -f "$AGENT_BIN" ]; then
    echo "Installing monk-agent to $AGENT_DIR..."
    mkdir -p "$AGENT_DIR"
    "$SCRIPT_DIR/install-monk-agent.sh"
  fi
}

stop_old_agent() {
  if [ -f "$PID_FILE" ]; then
    old_pid="$(cat "$PID_FILE" 2>/dev/null || true)"
    if [ -n "$old_pid" ] && kill -0 "$old_pid" 2>/dev/null; then
      echo "Stopping old agent (PID $old_pid)..."
      kill "$old_pid" 2>/dev/null || true
      
      wait_count=0
      while kill -0 "$old_pid" 2>/dev/null && [ $wait_count -lt 30 ]; do
        sleep 0.1
        wait_count=$((wait_count + 1))
      done
      
      if kill -0 "$old_pid" 2>/dev/null; then
        echo "Force killing old agent..."
        kill -9 "$old_pid" 2>/dev/null || true
        sleep 0.2
      fi
    fi
    rm -f "$PID_FILE"
  fi
}

check_health() {
  if command -v curl >/dev/null 2>&1; then
    curl -sf "http://127.0.0.1:$HEALTH_PORT/health" >/dev/null 2>&1
  elif command -v wget >/dev/null 2>&1; then
    wget -q -O- "http://127.0.0.1:$HEALTH_PORT/health" >/dev/null 2>&1
  else
    nc -z 127.0.0.1 "$HEALTH_PORT" 2>/dev/null
  fi
}

start_with_background_process() {
  nohup "$AGENT_BIN" >>"$LOG_FILE" 2>&1 &
  new_pid=$!
  echo "$new_pid" > "$PID_FILE"
  
  echo "Started monk-agent (PID $new_pid), waiting for health check..."
  
  elapsed=0
  while [ $elapsed -lt "$MAX_WAIT" ]; do
    if ! kill -0 "$new_pid" 2>/dev/null; then
      echo "ERROR: Agent process $new_pid exited prematurely"
      rm -f "$PID_FILE"
      return 1
    fi
    
    if check_health; then
      if ! kill -0 "$new_pid" 2>/dev/null; then
        echo "ERROR: Agent process $new_pid exited after health check succeeded"
        rm -f "$PID_FILE"
        return 1
      fi
      echo "Agent is healthy and running (PID $new_pid)"
      return 0
    fi
    
    sleep 1
    elapsed=$((elapsed + 1))
  done
  
  if kill -0 "$new_pid" 2>/dev/null; then
    echo "ERROR: Agent health check timeout after ${MAX_WAIT}s (PID $new_pid still running)"
    kill "$new_pid" 2>/dev/null || true
  else
    echo "ERROR: Agent process $new_pid exited during health check wait"
  fi
  rm -f "$PID_FILE"
  return 1
}

start_with_launchd() {
  PLIST_PATH="$HOME/Library/LaunchAgents/io.monk.agent.plist"
  
  cat > "$PLIST_PATH" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>io.monk.agent</string>
  <key>ProgramArguments</key>
  <array>
    <string>$AGENT_BIN</string>
  </array>
  <key>RunAtLoad</key>
  <true/>
  <key>KeepAlive</key>
  <true/>
  <key>StandardOutPath</key>
  <string>$LOG_FILE</string>
  <key>StandardErrorPath</key>
  <string>$LOG_FILE</string>
</dict>
</plist>
EOF

  launchctl unload "$PLIST_PATH" 2>/dev/null || true
  launchctl load "$PLIST_PATH"
  
  echo "Started monk-agent via launchd, waiting for health check..."
  
  elapsed=0
  while [ $elapsed -lt "$MAX_WAIT" ]; do
    if check_health; then
      sleep 1
      if check_health; then
        echo "Agent is healthy"
        return 0
      fi
    fi
    sleep 1
    elapsed=$((elapsed + 1))
  done
  
  echo "ERROR: Agent health check timeout after ${MAX_WAIT}s"
  return 1
}

ensure_agent_binary

if [ -f "$PID_FILE" ]; then
  old_pid="$(cat "$PID_FILE" 2>/dev/null || true)"
  if [ -n "$old_pid" ] && kill -0 "$old_pid" 2>/dev/null && check_health; then
    agent_updated=0
    if [ -f "$AGENT_DIR/.last-version" ]; then
      current_hash="$(shasum -a 256 "$AGENT_BIN" 2>/dev/null | cut -d' ' -f1 || true)"
      last_hash="$(cat "$AGENT_DIR/.last-version" 2>/dev/null || true)"
      if [ "$current_hash" != "$last_hash" ]; then
        agent_updated=1
      fi
    fi
    
    if [ "$agent_updated" = "0" ]; then
      echo "Agent already running and healthy (PID $old_pid)"
      exit 0
    fi
  fi
fi

stop_old_agent

if [ "$(uname)" = "Darwin" ] && [ -d "$HOME/Library/LaunchAgents" ]; then
  start_with_launchd
else
  start_with_background_process
fi

if [ $? -eq 0 ]; then
  shasum -a 256 "$AGENT_BIN" 2>/dev/null | cut -d' ' -f1 > "$AGENT_DIR/.last-version" 2>/dev/null || true
fi
