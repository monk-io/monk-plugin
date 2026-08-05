#!/usr/bin/env sh
# Regression coverage for Linux/other-POSIX background launch recovery: if the
# first child exits before readiness, retry within the existing readiness budget.
set -eu

repo="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
root="$(mktemp -d)"
cleanup() {
  if [ -f "$root/monk/agent/launcher/run/monk-agent.pid" ]; then
    IFS= read -r child_pid <"$root/monk/agent/launcher/run/monk-agent.pid" || true
    [ -z "${child_pid:-}" ] || kill "$child_pid" 2>/dev/null || true
  fi
  rm -rf "$root"
}
trap cleanup EXIT HUP INT TERM

set +e
output="$(
  HOME="$root/home" \
  MONK_AGENT_HOME="$root/monk" \
  MONK_AGENT_PATH=/usr/bin/true \
  MONK_AGENT_READY_TIMEOUT=6 \
  MONK_AGENT_BACKGROUND_RESTARTS=2 \
  MONK_AGENT_SKIP_SIGNIN_NUDGE=1 \
  TEST_ROOT="$root" \
  /bin/sh -c '
    count_file="$TEST_ROOT/launch-count"
    printf "0\n" >"$count_file"
    uname() { printf "%s\n" Linux; }
    curl() {
      count="$(cat "$count_file")"
      if [ "$count" -ge 2 ]; then
        printf "%s\n" "{\"resource\":\"http://127.0.0.1:7419/mcp\"}"
        return 0
      fi
      return 7
    }
    setsid() {
      count="$(cat "$count_file")"
      count=$((count + 1))
      printf "%s\n" "$count" >"$count_file"
      if [ "$count" -eq 1 ]; then
        return 1
      fi
      /bin/sleep 1000
    }
    sleep() { /bin/sleep "$1"; }
    . "$0"
  ' "$repo/scripts/start-monk-agent.sh" 2>&1
)"
status=$?
set -e

[ "$status" -eq 0 ]
launch_count="$(cat "$root/launch-count")"
[ "$launch_count" -eq 2 ]
printf '%s\n' "$output" | grep -q 'retrying background start (1/2)'

cmp "$repo/scripts/start-monk-agent.sh" "$repo/plugins/monk/scripts/start-monk-agent.sh"
cmp "$repo/scripts/start-monk-agent.sh" "$repo/.antigravity-plugin/scripts/start-monk-agent.sh"

printf 'background_retry_status=pass launches=%s\n' "$launch_count"
