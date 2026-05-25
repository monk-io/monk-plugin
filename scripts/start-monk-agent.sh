#!/usr/bin/env sh
set -eu

port="${MONK_AGENT_PORT:-7419}"
host="${MONK_AGENT_HOST:-127.0.0.1}"
auth_url="${MONK_AUTH_URL:-https://auth.monk.io}"
auth_client_id="${MONK_AGENT_AUTH_CLIENT_ID:-UW84YWcJME3buMSLfqLX8IbBsYdNWi47}"
auth_audience="${MONK_AUTH_AUDIENCE:-oaknode.com}"
monk_home="${MONK_AGENT_HOME:-"$HOME/.monk"}"
data_dir="$monk_home/agent/launcher"
log_dir="$data_dir/logs"
run_dir="$data_dir/run"
log_file="$log_dir/monk-agent.log"
pid_file="$run_dir/monk-agent.pid"
launchd_label="io.monk.agent"
launchd_plist="$HOME/Library/LaunchAgents/$launchd_label.plist"

mkdir -p "$log_dir" "$run_dir"

health_url="http://$host:$port/.well-known/oauth-protected-resource"

is_running() {
  if command -v curl >/dev/null 2>&1; then
    curl -fsS --max-time 2 "$health_url" 2>/dev/null | grep -q '"resource"'
    return $?
  fi
  if command -v wget >/dev/null 2>&1; then
    wget -q -T 2 -O - "$health_url" 2>/dev/null | grep -q '"resource"'
    return $?
  fi
  return 1
}

os="$(uname -s)"

launchd_configured() {
  [ -f "$launchd_plist" ] &&
    grep -q "<string>$auth_client_id</string>" "$launchd_plist" &&
    grep -q "<string>$auth_url</string>" "$launchd_plist" &&
    grep -q "<string>$auth_audience</string>" "$launchd_plist"
}

if [ "$os" != "Darwin" ] && is_running; then
  exit 0
fi

if [ "$os" = "Darwin" ] && is_running && launchd_configured; then
  exit 0
fi

agent_path="$("$CLAUDE_PLUGIN_ROOT/scripts/ensure-monk-agent.sh")"

if [ ! -x "$agent_path" ]; then
  echo "monk-agent is not executable at $agent_path" >&2
  exit 2
fi

start_with_launchd() {
  mkdir -p "$HOME/Library/LaunchAgents"
  cat >"$launchd_plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>$launchd_label</string>
  <key>ProgramArguments</key>
  <array>
    <string>$agent_path</string>
    <string>serve</string>
    <string>--host</string>
    <string>$host</string>
    <string>--port</string>
    <string>$port</string>
  </array>
  <key>RunAtLoad</key>
  <true/>
  <key>KeepAlive</key>
  <true/>
  <key>EnvironmentVariables</key>
  <dict>
    <key>MONK_AUTH_URL</key>
    <string>$auth_url</string>
    <key>MONK_AGENT_AUTH_CLIENT_ID</key>
    <string>$auth_client_id</string>
    <key>MONK_AUTH_AUDIENCE</key>
    <string>$auth_audience</string>
  </dict>
  <key>StandardOutPath</key>
  <string>$log_file</string>
  <key>StandardErrorPath</key>
  <string>$log_file</string>
</dict>
</plist>
EOF

  uid="$(id -u)"
  launchctl bootout "gui/$uid/$launchd_label" >/dev/null 2>&1 || true
  sleep 1
  launchctl bootstrap "gui/$uid" "$launchd_plist"
  launchctl kickstart -k "gui/$uid/$launchd_label" >/dev/null 2>&1 || true
}

start_with_background_process() {
  export MONK_AUTH_URL="$auth_url"
  export MONK_AGENT_AUTH_CLIENT_ID="$auth_client_id"
  export MONK_AUTH_AUDIENCE="$auth_audience"
  if command -v setsid >/dev/null 2>&1; then
    setsid "$agent_path" serve --host "$host" --port "$port" >>"$log_file" 2>&1 </dev/null &
  elif command -v nohup >/dev/null 2>&1; then
    nohup "$agent_path" serve --host "$host" --port "$port" >>"$log_file" 2>&1 </dev/null &
  else
    "$agent_path" serve --host "$host" --port "$port" >>"$log_file" 2>&1 </dev/null &
  fi
  pid="$!"
  printf '%s\n' "$pid" >"$pid_file"
}

case "$os" in
  Darwin) start_with_launchd ;;
  *) start_with_background_process ;;
esac

tries=0
while [ "$tries" -lt 30 ]; do
  if is_running; then
    exit 0
  fi
  tries=$((tries + 1))
  sleep 1
done

echo "monk-agent did not become ready at $health_url within 30s." >&2
echo "Log: $log_file" >&2
exit 1
