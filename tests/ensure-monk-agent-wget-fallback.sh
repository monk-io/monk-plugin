#!/usr/bin/env sh
set -eu

repo="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
root="$(mktemp -d)"
cleanup() { rm -rf "$root"; }
trap cleanup EXIT HUP INT TERM

hook="$repo/.antigravity-plugin/hooks/ensure-monk-agent.sh"

set +e
out="$(
  HOME="$root/home" \
  MONK_AGENT_HOME="$root/monk" \
  MONK_AGENT_PATH=/usr/bin/true \
  PATH=/definitely-no-system-tools \
  /bin/sh -c '
    wget() {
      printf "%s\n" "{\"resource\":\"http://127.0.0.1:7419/mcp\"}"
    }
    jq() {
      printf "%s\n" \
        "{\"injectSteps\":[{\"ephemeralMessage\":\"monk-agent was not running and has been started.\"}]}"
    }
    mkdir() { /bin/mkdir "$@"; }
    setsid() {
      printf "%s\n" START_CALLED >&2
      "$@"
    }

    . "$0"
  ' "$hook" 2>&1
)"
status=$?
set -e

log="$root/monk/agent/launcher/logs/monk-agent.log"
if [ -f "$log" ]; then
  start_calls="$(grep -c '^START_CALLED$' "$log" || true)"
else
  start_calls=0
fi
started_notices="$(printf '%s\n' "$out" | grep -c 'has been started' || true)"

printf 'status=%s\n' "$status"
printf 'start_calls=%s\n' "$start_calls"
printf 'started_notices=%s\n' "$started_notices"
printf '%s\n' "$out"

[ "$status" -eq 0 ]
[ "$start_calls" -eq 0 ]
[ "$started_notices" -eq 0 ]
[ "$out" = "{}" ]
