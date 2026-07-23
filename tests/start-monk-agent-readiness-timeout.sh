#!/usr/bin/env sh
set -eu

repo="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
root="$(mktemp -d)"
cleanup() {
  rm -rf "$root"
}
trap cleanup EXIT HUP INT TERM

started="$(date +%s)"
set +e
output="$(
  HOME="$root/home" \
  MONK_AGENT_HOME="$root/monk" \
  MONK_AGENT_PATH=/usr/bin/true \
  MONK_AGENT_READY_TIMEOUT=2 \
  MONK_AGENT_SKIP_SIGNIN_NUDGE=1 \
  TEST_ROOT="$root" \
  /bin/sh -c '
    sleep_calls=0
    cleanup() {
      pid_file="$TEST_ROOT/monk/agent/launcher/run/monk-agent.pid"
      if [ -f "$pid_file" ]; then
        IFS= read -r child_pid <"$pid_file" || true
        [ -z "${child_pid:-}" ] || kill "$child_pid" 2>/dev/null || true
      fi
      printf "sleep_calls=%s\n" "$sleep_calls"
    }
    trap cleanup EXIT HUP INT TERM
    uname() { printf "%s\n" Linux; }
    curl() { return 7; }
    setsid() { /bin/sleep 1000; }
    sleep() {
      sleep_calls=$((sleep_calls + 1))
      /bin/sleep "$1"
    }
    . "$0"
  ' "$repo/scripts/start-monk-agent.sh" 2>&1
)"
status=$?
set -e
elapsed=$(( $(date +%s) - started ))

[ "$status" -eq 1 ]
printf '%s\n' "$output" | grep -q 'within 2s'
sleep_calls="$(printf '%s\n' "$output" | sed -n 's/^sleep_calls=//p')"
[ -n "$sleep_calls" ]
[ "$sleep_calls" -le 2 ]
[ "$elapsed" -le 5 ]

cmp scripts/start-monk-agent.sh plugins/monk/scripts/start-monk-agent.sh
cmp scripts/start-monk-agent.sh .antigravity-plugin/scripts/start-monk-agent.sh
cmp scripts/start-monk-agent.ps1 plugins/monk/scripts/start-monk-agent.ps1
cmp scripts/start-monk-agent.ps1 .antigravity-plugin/scripts/start-monk-agent.ps1

grep -q '\$ReadyTimeoutSec = 150' scripts/start-monk-agent.ps1
grep -q 'Stopwatch.*StartNew' scripts/start-monk-agent.ps1

printf 'readiness_timeout_status=pass elapsed=%ss sleeps=%s\n' "$elapsed" "$sleep_calls"
