#!/usr/bin/env sh
# Regression coverage for plugin#394: the Antigravity ensure hook must kill a
# stale monk-agent PID recorded in its PID file before starting a replacement.
set -eu

repo_root="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
work_dir="$(mktemp -d)"
old_pid=""
new_pid=""

stop_agents() {
  if [ -n "$old_pid" ]; then
    kill "$old_pid" >/dev/null 2>&1 || true
  fi
  if [ -n "$new_pid" ]; then
    kill "$new_pid" >/dev/null 2>&1 || true
  fi
  # Also try to clean up via the PID file left behind by the hook.
  if [ -f "$work_dir/monk/agent/launcher/run/monk-agent.pid" ]; then
    candidate="$(cat "$work_dir/monk/agent/launcher/run/monk-agent.pid" 2>/dev/null || true)"
    case "$candidate" in
      ''|*[!0-9]*) ;;
      *) kill "$candidate" >/dev/null 2>&1 || true ;;
    esac
  fi
}
cleanup() {
  stop_agents
  rm -rf "$work_dir"
}
trap cleanup EXIT HUP INT TERM

# This test exercises /proc/<pid>/exe (Linux) and ps -o comm= (Darwin). The
# PowerShell sibling covers Windows native execution.
case "$(uname -s)" in
  Linux|Darwin) ;;
  *) echo "ensure-monk-agent.sh stale PID kill test skipped on $(uname -s)"; exit 0 ;;
esac

fake_bin="$work_dir/bin"
run_dir="$work_dir/monk/agent/launcher/run"
log_dir="$work_dir/monk/agent/launcher/logs"
mkdir -p "$fake_bin" "$run_dir" "$log_dir"

# Use a copy of /bin/sh as the fake monk-agent binary so /proc/<pid>/exe on
# Linux resolves to the expected path and stop_stale_agent() authenticates the
# stale process before killing it. The hook invokes it as
#   monk-agent serve --host <host> --port <port>
# so provide a fake `serve` command in PATH that just sleeps.
sh_bin="$(command -v sh)"
[ -n "$sh_bin" ]
cp "$sh_bin" "$fake_bin/monk-agent"
chmod +x "$fake_bin/monk-agent"

cat >"$fake_bin/curl" <<'EOF'
#!/usr/bin/env sh
exit 7
EOF
chmod +x "$fake_bin/curl"

cat >"$fake_bin/serve" <<'EOF'
#!/usr/bin/env sh
exec sleep 1000
EOF
chmod +x "$fake_bin/serve"

pid_file="$run_dir/monk-agent.pid"

# Start a stale monk-agent process and record it as the previous launch.
"$fake_bin/monk-agent" -c 'sleep 1000' &
old_pid=$!
printf '%s\n' "$old_pid" >"$pid_file"
sleep 1

# Run the hook. The health probe always fails, forcing a cold start.
HOME="$work_dir/home" \
PATH="$fake_bin:/usr/bin:/bin" \
MONK_AGENT_PATH="$fake_bin/monk-agent" \
MONK_AGENT_HOME="$work_dir/monk" \
MONK_AGENT_PORT="57420" \
MONK_AGENT_SKIP_SIGNIN_NUDGE=1 \
  "$repo_root/.antigravity-plugin/hooks/ensure-monk-agent.sh" </dev/null >/dev/null 2>&1 || true

# Wait for the hook to finish its readiness loop and write a new PID.
attempt=0
while [ "$attempt" -lt 15 ]; do
  if [ -f "$pid_file" ]; then
    candidate="$(cat "$pid_file" 2>/dev/null || true)"
    case "$candidate" in
      ''|*[!0-9]*) ;;
      *) if [ "$candidate" != "$old_pid" ]; then new_pid="$candidate"; break; fi ;;
    esac
  fi
  sleep 1
  attempt=$((attempt + 1))
done

if [ -z "$new_pid" ]; then
  echo "new monk-agent PID was not recorded" >&2
  exit 1
fi

if kill -0 "$old_pid" 2>/dev/null; then
  echo "stale monk-agent process ($old_pid) was not killed" >&2
  exit 1
fi

if ! kill -0 "$new_pid" 2>/dev/null; then
  echo "replacement monk-agent process ($new_pid) is not running" >&2
  exit 1
fi

echo "ensure-monk-agent.sh stale PID kill test passed."
