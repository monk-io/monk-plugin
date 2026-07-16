#!/usr/bin/env sh
set -eu

repo_root="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
fixture_bin="$repo_root/tests/fixtures/start-monk-agent"
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT HUP INT TERM
run_dir="$tmp_dir/monk/agent/launcher/run"
mkdir -p "$run_dir"
printf '%s\n' /usr/bin/true >"$run_dir/monk-agent.path"

PATH="$fixture_bin:/usr/bin:/bin" \
MONK_AGENT_PATH=/usr/bin/true \
MONK_AGENT_HOME="$tmp_dir/monk" \
MONK_AGENT_SKIP_SIGNIN_NUDGE=1 \
  "$repo_root/scripts/start-monk-agent.sh"

pid_file="$run_dir/monk-agent.pid"
if [ -e "$pid_file" ]; then
  echo "custom agent was restarted even though the health check passed" >&2
  exit 1
fi

echo "custom agent was reused"
