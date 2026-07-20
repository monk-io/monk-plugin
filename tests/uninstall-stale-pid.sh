#!/usr/bin/env sh
set -eu

repo="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
root="$(mktemp -d)"
victim_pid=""

cleanup() {
  if [ -n "$victim_pid" ]; then
    kill "$victim_pid" 2>/dev/null || true
  fi
  rm -rf "$root"
}
trap cleanup EXIT HUP INT TERM

run_stale_pid_case() {
  script="$1"

  mkdir -p "$root/home/agent/launcher/run" "$root/install" "$root/user"
  sleep 300 &
  victim_pid="$!"
  printf '%s\n' "$victim_pid" > "$root/home/agent/launcher/run/monk-agent.pid"

  MONK_AGENT_HOME="$root/home" \
    MONK_AGENT_INSTALL_DIR="$root/install" \
    HOME="$root/user" \
    sh "$script" --yes >/dev/null

  if ! kill -0 "$victim_pid" 2>/dev/null; then
    echo "uninstaller terminated unrelated process for $script" >&2
    exit 1
  fi

  if [ -e "$root/home/agent/launcher/run/monk-agent.pid" ]; then
    echo "stale PID file was not removed for $script" >&2
    exit 1
  fi

  kill "$victim_pid" 2>/dev/null || true
  victim_pid=""
  rm -rf "$root/home" "$root/install" "$root/user"
}

run_stale_pid_case "$repo/scripts/uninstall-monk-agent.sh"
run_stale_pid_case "$repo/plugins/monk/scripts/uninstall-monk-agent.sh"

echo "uninstall stale PID protection is correct"
