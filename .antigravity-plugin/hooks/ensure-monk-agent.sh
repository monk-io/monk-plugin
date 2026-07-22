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

# Emit an Antigravity injectSteps payload carrying a single ephemeral message.
# jq is not guaranteed to be installed — when it was missing this hook exited
# 127 and injected nothing at all — so encode the JSON string ourselves,
# escaping the backslashes and double quotes that can appear in the embedded
# filesystem paths. The messages are otherwise single-line and control-free.
emit_inject_steps() {
  escaped=$(printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g')
  printf '%s\n' "{\"injectSteps\":[{\"ephemeralMessage\":\"$escaped\"}]}"
}

# Fast path — already up. No telemetry here: this is a PreInvocation hook that
# fires per model step, so emitting on the warm path would spam. The beacon
# fires only on the cold-start paths below (install-needed / (re)start), which
# is the meaningful "launcher started" signal for Antigravity.
if is_running; then
  printf '%s\n' "{}"
  exit 0
fi

# Cold start — emit the earliest plugin_launcher_started beacon before doing any
# work. Shared helper, best-effort; must never abort the hook. launch_client is
# hardcoded because this hook is Antigravity-specific.
telemetry_helper="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)/scripts/monk-launcher-telemetry.sh"
if [ -f "$telemetry_helper" ]; then
  . "$telemetry_helper"
  monk_emit_launcher_event antigravity || true
fi

# Find the installed binary
agent_path="${MONK_AGENT_PATH:-${MONK_AGENT_INSTALL_DIR:-"$HOME/.monk/bin"}/monk-agent}"

if [ ! -x "$agent_path" ]; then
  plugin_dir="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
  emit_inject_steps "monk-agent is not installed. Run \`$plugin_dir/scripts/start-monk-agent.sh\` once to install and start it, then continue."
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
agent_pid=$!

# Wait briefly for the agent to become reachable. If the process exits early or
# the health endpoint never responds, report an attempted start with a pointer
# to the logs instead of a false "has been started".
i=0
while [ "$i" -lt 10 ]; do
  sleep 1
  if ! kill -0 "$agent_pid" 2>/dev/null; then
    break
  fi
  if is_running; then
    emit_inject_steps "monk-agent was not running and has been started. It may take a few seconds to initialize — use monk.install.status or monk.runtime.status to check readiness before issuing Monk operations."
    exit 0
  fi
  i=$((i + 1))
done

emit_inject_steps "monk-agent was started but did not become ready within 10 seconds. Check monk.install.status or monk.runtime.status for details, or the launcher logs under $log_dir."
