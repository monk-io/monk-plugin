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

# Rendered at plugin build time; carries MONK_PLUGIN_VERSION so the agent can
# report the real plugin version in telemetry. Guarded: an older rendered
# plugin without the file must still launch (the agent falls back to a labeled
# agent-binary version).
[ -f "$script_dir/plugin-version.sh" ] && . "$script_dir/plugin-version.sh"

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

# Client whose hook fired this launcher. Order matters: Cursor sets
# CLAUDE_PLUGIN_ROOT as a Claude-compat shim (verified, see
# docs/plugin-hooks-per-client.md), so it MUST be detected via CURSOR_* before
# the CLAUDE_PLUGIN_ROOT check or it is misreported as claude-code. Used by the
# launcher telemetry event, the MONK_AGENT_LAUNCH_CLIENT hand-off to the agent,
# and the signin nudge.
client="unknown"
if [ -n "${CURSOR_VERSION:-}" ] || [ -n "${CURSOR_PLUGIN_ROOT:-}" ]; then
  client="cursor"
elif [ -n "${CLAUDE_PLUGIN_ROOT:-}" ]; then
  client="claude-code"
elif [ -n "${PLUGIN_ROOT:-}" ]; then
  client="codex"
fi
ide_version="${CURSOR_VERSION:-}"

health_url="http://$host:$port/.well-known/oauth-protected-resource"
health_resource="http://$host:$port/mcp"

# Register monk in Antigravity's global MCP config if ~/.gemini/config/ exists.
# Idempotent — skips if already registered. Uses jq when available; prints
# manual instructions otherwise.
register_antigravity_mcp() {
  gemini_cfg="$HOME/.gemini/config"
  [ -d "$gemini_cfg" ] || return 0
  mcp_cfg="$gemini_cfg/mcp_config.json"
  server_url="http://$host:$port/mcp"
  if [ -f "$mcp_cfg" ] && grep -q '"monk"' "$mcp_cfg" 2>/dev/null; then
    return 0
  fi
  # Treat an empty file the same as a missing file to avoid jq/python parse errors.
  has_existing=0
  if [ -f "$mcp_cfg" ] && [ -s "$mcp_cfg" ]; then
    has_existing=1
  fi
  tmp="$(mktemp)"
  if command -v jq >/dev/null 2>&1; then
    if [ "$has_existing" = "1" ]; then
      jq --arg u "$server_url" '.mcpServers.monk = {serverUrl: $u}' "$mcp_cfg" >"$tmp"
    else
      jq -n --arg u "$server_url" '{mcpServers: {monk: {serverUrl: $u}}}' >"$tmp"
    fi
  elif command -v python3 >/dev/null 2>&1; then
    if [ "$has_existing" = "1" ]; then
      python3 -c "
import json, sys
cfg = json.load(open('$mcp_cfg'))
servers = cfg.get('mcpServers')
if not isinstance(servers, dict):
    servers = {}
cfg['mcpServers'] = servers
servers['monk'] = {'serverUrl': '$server_url'}
json.dump(cfg, sys.stdout, indent=2)
print()
" >"$tmp"
    else
      printf '{"mcpServers":{"monk":{"serverUrl":"%s"}}}\n' "$server_url" >"$tmp"
    fi
  else
    rm -f "$tmp"
    echo "Add monk to $mcp_cfg to enable Antigravity MCP (jq or python3 required to auto-write):" >&2
    printf '  {"mcpServers":{"monk":{"serverUrl":"%s"}}}\n' "$server_url" >&2
    return 0
  fi
  mv "$tmp" "$mcp_cfg"
  echo "Registered monk MCP server in $mcp_cfg" >&2
}

# If the agent is up but the user is not signed in to Monk, print SessionStart
# context telling the host agent to prompt the user to sign in via /mcp. Without
# this the host only sees "tools unavailable" and mis-reports it as a connection
# problem instead of an auth one. Best-effort; never blocks session start.
#
# Skippable via MONK_AGENT_SKIP_SIGNIN_NUDGE=1, for callers that already
# guarantee sign-in out of band and don't need this nudge's own status check.
emit_signin_nudge() {
  [ "${MONK_AGENT_SKIP_SIGNIN_NUDGE:-0}" = "1" ] && return 0
  # /auth.json is the cheap, auth-only status endpoint (~40ms). Deliberately NOT
  # /status.json, which runs ~10 synchronous install probes (~2s/call and
  # serializes under concurrent dashboard/MCP load) — that latency pushed this
  # check past the curl timeout and made the nudge racy.
  status_url="http://$host:$port/auth.json"
  body=""
  # A just-(re)started agent can still report a transient MISS on the first probe
  # (connection refused during the restart window, or a 500 from a cold macOS
  # Keychain read that the agent itself retries then surfaces as an error rather
  # than a false signed-out). Both show up here as an EMPTY body, so retry only on
  # empty. A non-empty body is a definitive answer — signed in OR out — and must be
  # acted on immediately: retrying a confirmed signedIn:false just adds ~2s and two
  # extra probes on precisely the signed-out path this nudge targets.
  # --max-time is modest because /auth.json is ~40ms; this also bounds how long a
  # hung endpoint can block the synchronous SessionStart hook (<=3x5+2x1s).
  attempt=0
  while [ "$attempt" -lt 3 ]; do
    if command -v curl >/dev/null 2>&1; then
      body="$(curl -fsS --max-time 5 "$status_url" 2>/dev/null || true)"
    elif command -v wget >/dev/null 2>&1; then
      body="$(wget -q -T 5 -O - "$status_url" 2>/dev/null || true)"
    fi
    [ -n "$body" ] && break
    attempt=$((attempt + 1))
    [ "$attempt" -lt 3 ] && sleep 1
  done
  case "$body" in
    *'"signedIn":true'*) return 0 ;;
  esac
  # Empty body = read error / 500 / timeout, NOT a confirmed signed-out state —
  # suppress the nudge. Only an affirmative signedIn:false reaches the nudge below.
  [ -n "$body" ] || return 0
  # $client is resolved once at the top of the script (Cursor-aware ordering).
  nudge_url="http://$host:$port/plugin/nudge?type=signin&client=$client"
  if command -v curl >/dev/null 2>&1; then
    curl -fsS --max-time 2 -X POST "$nudge_url" >/dev/null 2>&1 || true
  elif command -v wget >/dev/null 2>&1; then
    wget -q -T 2 -O - --post-data="" "$nudge_url" >/dev/null 2>&1 || true
  fi
  msg="monk-agent is running but you are NOT signed in to Monk. The Monk MCP tools require sign-in. If the user asks to deploy, analyze, or operate anything with Monk, first tell them to run /mcp and authenticate the monk MCP server (this signs them in to Monk). Do NOT describe this as a connection or restart problem, and do NOT deploy via Docker or another platform to work around it."
  if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && command -v jq >/dev/null 2>&1; then
    jq -n --arg ctx "$msg" \
      '{hookSpecificOutput: {hookEventName: "SessionStart", additionalContext: $ctx}}'
  else
    printf '%s\n' "$msg"
  fi
}

is_running() {
  response=""
  if command -v curl >/dev/null 2>&1; then
    response="$(curl -fsS --max-time 2 "$health_url" 2>/dev/null)" || return 1
  elif command -v wget >/dev/null 2>&1; then
    response="$(wget -q -T 2 -O - "$health_url" 2>/dev/null)" || return 1
  else
    return 1
  fi
  resource="$(printf '%s\n' "$response" | sed -n 's/.*"resource"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n 1)"
  [ "$resource" = "$health_resource" ]
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

# Earliest telemetry signal: fire a plugin_launcher_started beacon straight to
# PostHog BEFORE ensure/health-check/serve, so plugin activity is visible even if
# the download fails or the agent crashes on init. The beacon lives in a shared,
# sourced helper (monk-launcher-telemetry.sh) reused by the Antigravity hook, so
# the logic stays in one place. Guarded on presence for older rendered plugins
# and invoked with `|| true` — a failure here must never abort the launch.
if [ -f "$script_dir/monk-launcher-telemetry.sh" ]; then
  . "$script_dir/monk-launcher-telemetry.sh"
  monk_emit_launcher_event "$client" "$ide_version" || true
fi

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
  # Deliberately excludes PATH: it is derived from the invoking shell/app and
  # legitimately differs across hosts (Claude Code, VS Code, plain terminal) and
  # even across sessions of the same host (nvm/asdf switches, plugin cache
  # entries). Gating a restart on an exact PATH match meant nearly every new
  # session tore down an already-running, already-authenticated agent and raced
  # the cold-start auth read in emit_signin_nudge. PATH is still refreshed
  # in the plist whenever a real restart happens for another reason.
  # MONK_PLUGIN_VERSION IS included (unlike PATH): it changes only on a plugin
  # install/upgrade — rare, stable within a plugin install, and exactly the
  # moment the agent should restart so telemetry reports the new version. It
  # cannot cause the per-session restart churn PATH did.
  [ -f "$launchd_plist" ] &&
    grep -q "<string>$auth_client_id</string>" "$launchd_plist" &&
    grep -q "<string>$auth_url</string>" "$launchd_plist" &&
    grep -q "<string>$auth_audience</string>" "$launchd_plist" &&
    grep -q "<string>$autospin_url</string>" "$launchd_plist" &&
    grep -q "<string>${MONK_AGENT_LOCAL:-}</string>" "$launchd_plist" &&
    grep -q "<string>${MONK_PLUGIN_VERSION:-}</string>" "$launchd_plist"
}

if [ "${MONK_AGENT_SKIP_ENSURE:-0}" != "1" ]; then
  if [ "$os" != "Darwin" ] && [ "$agent_updated" = "0" ] && is_running; then
    register_antigravity_mcp
    emit_signin_nudge
    exit 0
  fi

  if [ "$os" = "Darwin" ] && [ "$agent_updated" = "0" ] && is_running && launchd_configured; then
    register_antigravity_mcp
    emit_signin_nudge
    exit 0
  fi
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
  <!-- Respawn on crashes/non-zero exits, but NOT on a clean exit 0. The agent
       exits 0 when it finds another healthy monk-agent already on the port
       (see handlePortConflict) so a lost bind race defers instead of hot-looping;
       a foreign process holding the port exits non-zero and is retried, throttled. -->
  <key>KeepAlive</key>
  <dict>
    <key>SuccessfulExit</key>
    <false/>
  </dict>
  <!-- launchd's default throttle floor is 10s; widen it so an unrecoverable
       failure (e.g. a foreign process pinning the port) costs ~1 relaunch/min
       instead of ~6, while still self-healing once the port frees. -->
  <key>ThrottleInterval</key>
  <integer>60</integer>
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
    <key>MONK_AGENT_LOCAL</key>
    <string>${MONK_AGENT_LOCAL:-}</string>
    <key>MONK_PLUGIN_VERSION</key>
    <string>${MONK_PLUGIN_VERSION:-}</string>
    <!-- Deliberately NOT gated in launchd_configured(): the launching client
         legitimately differs per session, and gating a restart on it would
         reintroduce the per-session churn the PATH exclusion comment warns
         about. On macOS this reflects the client of the last real (re)start. -->
    <key>MONK_AGENT_LAUNCH_CLIENT</key>
    <string>$client</string>
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
  export MONK_AGENT_LOCAL="${MONK_AGENT_LOCAL:-}"
  export MONK_PLUGIN_VERSION="${MONK_PLUGIN_VERSION:-}"
  export MONK_AGENT_LAUNCH_CLIENT="$client"
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
while [ "$tries" -lt 180 ]; do
  if is_running; then
    register_antigravity_mcp
    emit_signin_nudge
    exit 0
  fi
  # Break early if the background process has exited -- no point waiting 180s.
  if [ -f "$pid_file" ]; then
    _pid="$(cat "$pid_file" 2>/dev/null || true)"
    if [ -n "$_pid" ] && ! kill -0 "$_pid" 2>/dev/null; then
      break
    fi
  fi
  tries=$((tries + 1))
  sleep 1
done

echo "monk-agent did not become ready at $health_url within 180s." >&2
echo "Log: $log_file" >&2
exit 1
