#!/usr/bin/env sh
# PreInvocation hook: ensure monk-agent is running before the model is called.
# Fast no-op (~100ms) when already running. Starts the installed binary and
# injects an ephemeral notice when it was not running.
#
# Antigravity PreInvocation I/O:
#   stdin:  {"invocationNum":N,"initialNumSteps":N,"workspacePaths":[...],...}
#   stdout: {"injectSteps":[{"ephemeralMessage":"..."}]} or {}

set -eu

port="${MONK_AGENT_PORT:-7419}"
host="${MONK_AGENT_HOST:-127.0.0.1}"
health_url="http://$host:$port/.well-known/oauth-protected-resource"

is_running() {
  expected_resource="http://$host:$port/mcp"
  health_body=""
  if command -v curl >/dev/null 2>&1; then
    health_body="$(curl -fsS --max-time 2 "$health_url" 2>/dev/null || true)"
  elif command -v wget >/dev/null 2>&1; then
    health_body="$(wget -q -T 2 -O - "$health_url" 2>/dev/null || true)"
  else
    return 1
  fi
  case "$health_body" in
    *"$expected_resource"*) return 0 ;;
  esac
  return 1
}

# Fast path — already up
if is_running; then
  printf '%s\n' "{}"
  exit 0
fi

# Find the installed binary
agent_path="${MONK_AGENT_PATH:-${MONK_AGENT_INSTALL_DIR:-"$HOME/.monk/bin"}/monk-agent}"

if [ ! -x "$agent_path" ]; then
  plugin_dir="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
  if command -v jq >/dev/null 2>&1; then
    jq -n --arg script "$plugin_dir/scripts/start-monk-agent.sh" '{
      injectSteps: [{
        ephemeralMessage: ("monk-agent is not installed. Run `" + $script + "` once to install and start it, then continue.")
      }]
    }'
  else
    printf '{"injectSteps":[{"ephemeralMessage":"monk-agent is not installed. Run `%s` once to install and start it, then continue."}]}\n' "$plugin_dir/scripts/start-monk-agent.sh"
  fi
  exit 0
fi

# Binary present but not running — start it directly
log_dir="${MONK_AGENT_HOME:-"$HOME/.monk"}/agent/launcher/logs"
mkdir -p "$log_dir"
log_file="$log_dir/monk-agent.log"

export MONK_AUTH_URL="${MONK_AUTH_URL:-https://auth.monk.io}"
export MONK_AGENT_AUTH_CLIENT_ID="${MONK_AGENT_AUTH_CLIENT_ID:-UW84YWcJME3buMSLfqLX8IbBsYdNWi47}"
export MONK_AUTH_AUDIENCE="${MONK_AUTH_AUDIENCE:-oaknode.com}"
export MONK_AUTOSPIN_URL="${MONK_AUTOSPIN_URL:-wss://api.app.monk.io/autospin/}"

if command -v setsid >/dev/null 2>&1; then
  setsid "$agent_path" serve --host "$host" --port "$port" >>"$log_file" 2>&1 </dev/null &
elif command -v nohup >/dev/null 2>&1; then
  nohup "$agent_path" serve --host "$host" --port "$port" >>"$log_file" 2>&1 </dev/null &
else
  "$agent_path" serve --host "$host" --port "$port" >>"$log_file" 2>&1 </dev/null &
fi

started_msg="monk-agent was not running and has been started. It may take a few seconds to initialize — use monk.install.status or monk.runtime.status to check readiness before issuing Monk operations."
if command -v jq >/dev/null 2>&1; then
  jq -n --arg msg "$started_msg" '{
    injectSteps: [{
      ephemeralMessage: $msg
    }]
  }'
else
  printf '{"injectSteps":[{"ephemeralMessage":"%s"}]}\n' "$started_msg"
fi
