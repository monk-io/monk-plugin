#!/usr/bin/env sh
set -eu

repo_root="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
launcher_root="${MONK_LAUNCHER_ROOT:-$repo_root}"
tmp="$(mktemp -d)"
home="$tmp/home"
fake_bin="$tmp/bin"
fake_agent="$home/.monk/bin/monk-agent"
started="$tmp/agent-started"
pid_file="$home/.monk/agent/launcher/run/monk-agent.pid"

cleanup() {
  if [ -f "$pid_file" ]; then
    pid="$(sed -n '1p' "$pid_file" 2>/dev/null || true)"
    [ -z "$pid" ] || kill "$pid" >/dev/null 2>&1 || true
  fi
  rm -rf "$tmp"
}
trap cleanup EXIT HUP INT TERM

mkdir -p "$home/.monk/agent/launcher/run" "$home/.monk/bin" "$fake_bin"

{
  printf '%s\n' '#!/usr/bin/env sh'
  printf '%s\n' 'printf "%s\n" Linux'
} >"$fake_bin/uname"

{
  printf '%s\n' '#!/usr/bin/env sh'
  printf '%s\n' 'if [ -f "$TEST_AGENT_STARTED" ]; then'
  printf '%s\n' '  printf "%s\n" "{\"resource\":\"http://127.0.0.1:7419/mcp\"}"'
  printf '%s\n' 'else'
  printf '%s\n' '  printf "%s\n" "{\"resource\":\"http://127.0.0.1:9999/not-monk\"}"'
  printf '%s\n' 'fi'
} >"$fake_bin/curl"

{
  printf '%s\n' '#!/usr/bin/env sh'
  printf '%s\n' ': >"$TEST_AGENT_STARTED"'
  printf '%s\n' 'trap "exit 0" HUP INT TERM'
  printf '%s\n' 'while :; do sleep 1; done'
} >"$fake_agent"

chmod +x "$fake_bin/uname" "$fake_bin/curl" "$fake_agent"

. "$launcher_root/scripts/plugin-version.sh"
run_dir="$home/.monk/agent/launcher/run"
printf '%s\n' "$fake_agent" >"$run_dir/monk-agent.path"
{
  printf '%s\n' \
    "MONK_AGENT_PATH=$fake_agent" \
    "MONK_AGENT_HOST=127.0.0.1" \
    "MONK_AGENT_PORT=7419" \
    "MONK_AUTH_URL=https://auth.monk.io" \
    "MONK_AGENT_AUTH_CLIENT_ID=UW84YWcJME3buMSLfqLX8IbBsYdNWi47" \
    "MONK_AUTH_AUDIENCE=oaknode.com" \
    "MONK_AUTOSPIN_URL=wss://api.app.monk.io/autospin/" \
    "MONK_AGENT_LOCAL=" \
    "MONK_PLUGIN_VERSION=${MONK_PLUGIN_VERSION:-}"
} >"$run_dir/monk-agent.config"

PATH="$fake_bin:/usr/bin:/bin" \
HOME="$home" \
MONK_AGENT_HOME="$home/.monk" \
MONK_AGENT_PATH="$fake_agent" \
MONK_AGENT_SKIP_SIGNIN_NUDGE=1 \
MONK_TELEMETRY=0 \
TEST_AGENT_STARTED="$started" \
  "$launcher_root/scripts/start-monk-agent.sh"

if [ ! -f "$started" ]; then
  echo "launcher accepted an unrelated health resource as monk-agent" >&2
  exit 1
fi

echo "launcher rejects an unrelated health resource before reusing a process"
