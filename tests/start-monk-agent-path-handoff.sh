#!/usr/bin/env sh
# Regression coverage for switching between two custom MONK_AGENT_PATH values.
# The launcher must authenticate the recorded PID against the executable that
# started it, stop that process, and then hand ownership to the new executable.
set -eu

repo_root="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
fixture_bin="$repo_root/tests/fixtures/start-monk-agent"
work_dir="$(mktemp -d)"
helper_bin="$work_dir/bin"
agent_home="$work_dir/monk"
run_dir="$agent_home/agent/launcher/run"
new_pid_file="$work_dir/new-agent.pid"
old_pid=""
new_pid=""

cleanup() {
  if [ -z "$new_pid" ] && [ -f "$run_dir/monk-agent.pid" ]; then
    new_pid="$(cat "$run_dir/monk-agent.pid" 2>/dev/null || true)"
  fi
  for candidate in "$new_pid" "$old_pid"; do
    case "$candidate" in
      ''|*[!0-9]*) continue ;;
    esac
    kill "$candidate" >/dev/null 2>&1 || true
  done
  rm -rf "$work_dir"
}
trap cleanup EXIT HUP INT TERM

mkdir -p "$helper_bin" "$run_dir" "$work_dir/home"

# The shipped PID ownership check is Linux-only. This fixture selects that
# branch on every CI host and models the two readlink operations it performs:
# /proc/<pid>/exe resolves to the old custom executable, while readlink -f
# canonicalizes the recorded path.
cat >"$helper_bin/readlink" <<'EOF'
#!/usr/bin/env sh
case "${1:-}" in
  -f) printf '%s\n' "$2" ;;
  /proc/*/exe) printf '%s\n' "$OLD_AGENT_PATH" ;;
  *) exit 1 ;;
esac
EOF
chmod +x "$helper_bin/readlink"

# The replacement stays alive long enough for the launcher to complete its
# readiness check and for this test to verify that the PID/state handoff won.
new_agent="$work_dir/new-monk-agent"
cat >"$new_agent" <<'EOF'
#!/usr/bin/env sh
printf '%s\n' "$$" >"$NEW_AGENT_PID_FILE"
# Match monk-agent's healthy-port-conflict behavior: briefly allow a stopping
# predecessor to release the endpoint, then defer with a clean exit if it is
# still alive.
attempt=0
while kill -0 "$OLD_COMPANION_PID" >/dev/null 2>&1 && [ "$attempt" -lt 2 ]; do
  sleep 1
  attempt=$((attempt + 1))
done
if kill -0 "$OLD_COMPANION_PID" >/dev/null 2>&1; then
  exit 0
fi
while :; do sleep 1; done
EOF
chmod +x "$new_agent"

old_agent=/usr/bin/yes
"$old_agent" >/dev/null 2>&1 &
old_pid="$!"

cat >"$run_dir/monk-agent.state" <<EOF
agent_path=$old_agent
auth_url=https://auth.monk.io
auth_client_id=UW84YWcJME3buMSLfqLX8IbBsYdNWi47
auth_audience=oaknode.com
autospin_url=wss://api.app.monk.io/autospin/
EOF
printf '%s\n' "$old_pid" >"$run_dir/monk-agent.pid"

HOME="$work_dir/home" \
PATH="$helper_bin:$fixture_bin:/usr/bin:/bin" \
OLD_AGENT_PATH="$old_agent" \
OLD_COMPANION_PID="$old_pid" \
NEW_AGENT_PID_FILE="$new_pid_file" \
MONK_AGENT_PATH="$new_agent" \
MONK_AGENT_HOME="$agent_home" \
MONK_AGENT_SKIP_SIGNIN_NUDGE=1 \
  "$repo_root/scripts/start-monk-agent.sh"

attempt=0
while [ ! -s "$new_pid_file" ] && [ "$attempt" -lt 5 ]; do
  sleep 1
  attempt=$((attempt + 1))
done
if [ ! -s "$new_pid_file" ]; then
  echo "replacement custom companion did not record its PID" >&2
  exit 1
fi
new_pid="$(cat "$new_pid_file")"

# Allow the replacement's bounded handoff check to finish before inspecting
# which process owns the lifecycle.
sleep 3
if kill -0 "$old_pid" >/dev/null 2>&1; then
  if ! kill -0 "$new_pid" >/dev/null 2>&1; then
    echo "launcher returned success against the old custom companion while the replacement exited" >&2
  else
    echo "old custom companion remained alive after MONK_AGENT_PATH changed" >&2
  fi
  exit 1
fi
if ! kill -0 "$new_pid" >/dev/null 2>&1; then
  echo "replacement custom companion is not running" >&2
  exit 1
fi
if [ "$(cat "$run_dir/monk-agent.pid")" != "$new_pid" ]; then
  echo "launcher PID file does not belong to the replacement companion" >&2
  exit 1
fi
if ! grep -Fxq "agent_path=$new_agent" "$run_dir/monk-agent.state"; then
  echo "launcher state does not record the replacement custom path" >&2
  exit 1
fi

echo "custom agent path handoff test passed."
