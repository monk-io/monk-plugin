#!/bin/sh
set -e

TEST_DIR="$(cd "$(dirname "$0")" && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

AGENT_DIR="$TMP_DIR/monk"
PID_FILE="$AGENT_DIR/monk-agent.pid"
HEALTH_PORT=28652

mkdir -p "$AGENT_DIR"

cat > "$AGENT_DIR/old-agent" <<'EOF'
#!/bin/sh
trap 'sleep 2; exit 0' TERM
while true; do
  echo "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\n\r\n{\"status\":\"ok\"}"
done | nc -l 127.0.0.1 28652 >/dev/null 2>&1 || true
EOF
chmod +x "$AGENT_DIR/old-agent"

cat > "$AGENT_DIR/monk-agent" <<'EOF'
#!/bin/sh
if nc -z 127.0.0.1 28652 2>/dev/null; then
  exit 0
fi
while true; do
  echo "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\n\r\n{\"status\":\"ok\"}"
done | nc -l 127.0.0.1 28652 >/dev/null 2>&1 || true
EOF
chmod +x "$AGENT_DIR/monk-agent"

"$AGENT_DIR/old-agent" &
old_pid=$!
echo "$old_pid" > "$PID_FILE"

sleep 0.5

if ! nc -z 127.0.0.1 28652 2>/dev/null; then
  echo "FAIL: Old agent did not start"
  kill $old_pid 2>/dev/null || true
  exit 1
fi

touch "$AGENT_DIR/.last-version"
echo "different-hash" > "$AGENT_DIR/.last-version"

export AGENT_DIR="$AGENT_DIR"
export MONK_AGENT_PORT="$HEALTH_PORT"
export MONK_START_TIMEOUT=10

cat > "$TMP_DIR/install-monk-agent.sh" <<'EOF'
#!/bin/sh
exit 0
EOF
chmod +x "$TMP_DIR/install-monk-agent.sh"

cat > "$TMP_DIR/start-wrapper.sh" <<EOF
#!/bin/sh
SCRIPT_DIR="$TMP_DIR"
export SCRIPT_DIR
. "$TEST_DIR/../scripts/start-monk-agent.sh"
EOF
chmod +x "$TMP_DIR/start-wrapper.sh"

"$TMP_DIR/start-wrapper.sh"
launcher_exit=$?

sleep 2.5

if kill -0 $old_pid 2>/dev/null; then
  old_alive="yes"
else
  old_alive="no"
fi

if [ -f "$PID_FILE" ]; then
  new_pid="$(cat "$PID_FILE")"
  if [ -n "$new_pid" ] && kill -0 "$new_pid" 2>/dev/null; then
    new_alive="yes"
  else
    new_alive="no"
  fi
else
  new_alive="no"
fi

kill $old_pid 2>/dev/null || true
if [ -n "$new_pid" ]; then
  kill "$new_pid" 2>/dev/null || true
fi

echo "launcher_exit=$launcher_exit"
echo "old_agent_alive=$old_alive"
echo "new_agent_alive=$new_alive"

if [ "$launcher_exit" != "0" ]; then
  echo "FAIL: Launcher returned error"
  exit 1
fi

if [ "$old_alive" = "yes" ]; then
  echo "FAIL: Old agent still running after restart"
  exit 1
fi

if [ "$new_alive" != "yes" ]; then
  echo "FAIL: New agent not running after successful launcher exit"
  exit 1
fi

echo "PASS: Restart completed successfully"
