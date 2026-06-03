#!/usr/bin/env sh
set -eu

port="${MONK_AGENT_PORT:-7419}"
host="${MONK_AGENT_HOST:-127.0.0.1}"
auth_url="${MONK_AUTH_URL:-https://auth.monk.io}"
auth_client_id="${MONK_AGENT_AUTH_CLIENT_ID:-UW84YWcJME3buMSLfqLX8IbBsYdNWi47}"
auth_audience="${MONK_AUTH_AUDIENCE:-oaknode.com}"
autospin_url="${MONK_AUTOSPIN_URL:-wss://api.app.monk.io/autospin/}"
agent_path_env="${PATH:-/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin}"
script_dir="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"

case "$(uname -s 2>/dev/null || printf unknown)" in
  MINGW*|MSYS*|CYGWIN*)
    exec powershell.exe -NoProfile -ExecutionPolicy Bypass \
      -File "$script_dir/start-monk-agent.ps1" "$@"
    ;;
esac

plugin_root="${CLAUDE_PLUGIN_ROOT:-"$(dirname -- "$script_dir")"}"
case ":$agent_path_env:" in
  *:/opt/homebrew/bin:*) ;;
  *) agent_path_env="/opt/homebrew/bin:$agent_path_env" ;;
esac
case ":$agent_path_env:" in
  *:/usr/local/bin:*) ;;
  *) agent_path_env="/usr/local/bin:$agent_path_env" ;;
esac
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

hash_file() {
  path="$1"
  if [ ! -f "$path" ]; then
    printf '\n'
    return
  fi
  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$path" | awk '{print $1}'
    return
  fi
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$path" | awk '{print $1}'
    return
  fi
  printf '\n'
}

os="$(uname -s)"
managed_agent_path="${MONK_AGENT_INSTALL_DIR:-"$HOME/.monk/bin"}/monk-agent"
agent_hash_before="$(hash_file "$managed_agent_path")"

if [ -n "${MONK_AGENT_PATH:-}" ]; then
  agent_path="$MONK_AGENT_PATH"
elif [ "${MONK_AGENT_SKIP_ENSURE:-0}" = "1" ]; then
  agent_path="$managed_agent_path"
else
  agent_path="$("$plugin_root/scripts/ensure-monk-agent.sh")"
fi

if [ ! -x "$agent_path" ]; then
  echo "monk-agent is not executable at $agent_path" >&2
  exit 2
fi

agent_hash_after="$(hash_file "$agent_path")"
agent_updated=0
if [ -n "$agent_hash_after" ] && [ "$agent_hash_before" != "$agent_hash_after" ]; then
  agent_updated=1
fi

launchd_configured() {
  [ -f "$launchd_plist" ] &&
    grep -q "<string>$auth_client_id</string>" "$launchd_plist" &&
    grep -q "<string>$auth_url</string>" "$launchd_plist" &&
    grep -q "<string>$auth_audience</string>" "$launchd_plist" &&
    grep -q "<string>$autospin_url</string>" "$launchd_plist" &&
    grep -q "<string>$agent_path_env</string>" "$launchd_plist"
}

if [ "$os" != "Darwin" ] && [ "$agent_updated" = "0" ] && is_running; then
  exit 0
fi

if [ "$os" = "Darwin" ] && [ "$agent_updated" = "0" ] && is_running && launchd_configured; then
  exit 0
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
    <key>MONK_AUTOSPIN_URL</key>
    <string>$autospin_url</string>
    <key>PATH</key>
    <string>$agent_path_env</string>
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
  if [ -f "$pid_file" ]; then
    old_pid="$(cat "$pid_file" 2>/dev/null || true)"
    if [ -n "$old_pid" ]; then
      kill "$old_pid" >/dev/null 2>&1 || true
    fi
  fi
  export MONK_AUTH_URL="$auth_url"
  export MONK_AGENT_AUTH_CLIENT_ID="$auth_client_id"
  export MONK_AUTH_AUDIENCE="$auth_audience"
  export MONK_AUTOSPIN_URL="$autospin_url"
  export PATH="$agent_path_env"
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
