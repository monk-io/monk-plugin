#!/usr/bin/env sh
# Regression coverage for the launcher's "healthy agent, skip restart" fast
# path (ENG-390, ENG-397): a custom MONK_AGENT_PATH must be reused across
# sessions while unchanged and restarted exactly once when it (or the
# auth/autospin config) changes.
set -eu

repo_root="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
fixture_bin="$repo_root/tests/fixtures/start-monk-agent"
work_dir="$(mktemp -d)"
trap 'rm -rf "$work_dir"' EXIT HUP INT TERM

run_launcher() {
  agent_home="$1"
  auth_url="$2"
  HOME="$work_dir/home" \
  PATH="$fixture_bin:/usr/bin:/bin" \
  MONK_AGENT_PATH=/usr/bin/true \
  MONK_AGENT_HOME="$agent_home" \
  MONK_AUTH_URL="$auth_url" \
  MONK_AGENT_SKIP_SIGNIN_NUDGE=1 \
    "$repo_root/scripts/start-monk-agent.sh"
}

write_state() {
  state_file="$1"
  auth_url="$2"
  {
    printf 'agent_path=/usr/bin/true\n'
    printf 'auth_url=%s\n' "$auth_url"
    printf 'auth_client_id=UW84YWcJME3buMSLfqLX8IbBsYdNWi47\n'
    printf 'auth_audience=oaknode.com\n'
    printf 'autospin_url=wss://api.app.monk.io/autospin/\n'
  } >"$state_file"
}

# Case 1: unchanged custom path + unchanged auth config -> reused, no restart.
unchanged_dir="$work_dir/unchanged/monk"
unchanged_run_dir="$unchanged_dir/agent/launcher/run"
mkdir -p "$unchanged_run_dir"
write_state "$unchanged_run_dir/monk-agent.state" "https://auth.monk.io"

run_launcher "$unchanged_dir" "https://auth.monk.io"

if [ -e "$unchanged_run_dir/monk-agent.pid" ]; then
  echo "healthy companion was restarted even though its path and config were unchanged" >&2
  exit 1
fi

# Case 2: unchanged custom path but a changed MONK_AUTH_URL -> restarted once,
# state file reflects the new config (ENG-397).
drift_dir="$work_dir/drift/monk"
drift_run_dir="$drift_dir/agent/launcher/run"
mkdir -p "$drift_run_dir"
write_state "$drift_run_dir/monk-agent.state" "https://auth-one.invalid"

run_launcher "$drift_dir" "https://auth-two.invalid"

if [ ! -e "$drift_run_dir/monk-agent.pid" ]; then
  echo "companion was not restarted after auth_url drifted" >&2
  exit 1
fi
if ! grep -Fxq "auth_url=https://auth-two.invalid" "$drift_run_dir/monk-agent.state"; then
  echo "updated auth_url was not recorded in the state file" >&2
  exit 1
fi

echo "start-monk-agent fast-path tests passed."
