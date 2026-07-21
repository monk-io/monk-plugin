#!/usr/bin/env sh
set -eu

repo_root="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
fixture_bin="$repo_root/tests/fixtures/start-monk-agent"
same_dir="$(mktemp -d)"
changed_dir="$(mktemp -d)"
trap 'rm -rf "$same_dir" "$changed_dir"' EXIT HUP INT TERM

run_launcher() {
  agent_home="$1"
  PATH="$fixture_bin:/usr/bin:/bin" \
  MONK_AGENT_PATH=/usr/bin/true \
  MONK_AGENT_HOME="$agent_home" \
  MONK_AGENT_SKIP_SIGNIN_NUDGE=1 \
    "$repo_root/scripts/start-monk-agent.sh"
}

run_dir="$same_dir/monk/agent/launcher/run"
mkdir -p "$run_dir"
printf '%s\n' /usr/bin/true >"$run_dir/monk-agent.path"

run_launcher "$same_dir/monk"

pid_file="$run_dir/monk-agent.pid"
if [ -e "$pid_file" ]; then
  echo "custom agent was restarted even though the health check passed" >&2
  exit 1
fi

changed_run_dir="$changed_dir/monk/agent/launcher/run"
mkdir -p "$changed_run_dir"
printf '%s\n' /usr/bin/false >"$changed_run_dir/monk-agent.path"

run_launcher "$changed_dir/monk"

if [ ! -e "$changed_run_dir/monk-agent.pid" ]; then
  echo "custom agent was not restarted after its configured path changed" >&2
  exit 1
fi
if [ "$(cat "$changed_run_dir/monk-agent.path")" != /usr/bin/true ]; then
  echo "updated custom agent path was not recorded" >&2
  exit 1
fi

echo "custom agent was reused when unchanged and restarted once when changed"
