#!/usr/bin/env sh
set -eu

repo_root="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
test_root="$(mktemp -d)"
old_pid=""
old_reaper_pid=""

cleanup() {
  pid_file="$test_root/monk-home/agent/launcher/run/monk-agent.pid"
  if [ -f "$pid_file" ]; then
    replacement_pid="$(cat "$pid_file" 2>/dev/null || true)"
    case "$replacement_pid" in
      ''|*[!0-9]*) ;;
      *) kill "$replacement_pid" 2>/dev/null || true ;;
    esac
  fi
  if [ -n "$old_pid" ]; then
    kill "$old_pid" 2>/dev/null || true
  fi
  if [ -n "$old_reaper_pid" ]; then
    wait "$old_reaper_pid" 2>/dev/null || true
  fi
  rm -rf "$test_root"
}
trap cleanup EXIT HUP INT TERM

fake_bin="$test_root/bin"
plugin_root="$test_root/plugin"
install_dir="$test_root/install"
home_dir="$test_root/home"
monk_home="$test_root/monk-home"
old_marker="$test_root/old-alive"
new_marker="$test_root/new-alive"
attempt_log="$test_root/replacement-attempts"
new_agent_source="$test_root/new-monk-agent"

mkdir -p "$fake_bin" "$plugin_root/scripts" "$install_dir" "$home_dir"

cat >"$fake_bin/uname" <<'SH'
#!/usr/bin/env sh
printf 'Linux\n'
SH
chmod 0755 "$fake_bin/uname"

cat >"$fake_bin/curl" <<'SH'
#!/usr/bin/env sh
if [ -f "$OLD_MARKER" ] || [ -f "$NEW_MARKER" ]; then
  printf '%s\n' '{"resource":"http://127.0.0.1:17419/mcp"}'
  exit 0
fi
exit 7
SH
chmod 0755 "$fake_bin/curl"

cat >"$test_root/old-monk-agent" <<'SH'
#!/usr/bin/env sh
set -eu
trap 'sleep 2; rm -f "$OLD_MARKER"; exit 0' TERM HUP INT
: >"$OLD_MARKER"
while :; do
  sleep 1
done
SH
chmod 0755 "$test_root/old-monk-agent"

cat >"$new_agent_source" <<'SH'
#!/usr/bin/env sh
set -eu
printf 'attempt\n' >>"$ATTEMPT_LOG"
if [ -f "$OLD_MARKER" ]; then
  # Match monk-agent's healthy-port-conflict behavior: the replacement defers
  # to the process that still owns the port and exits cleanly.
  exit 0
fi
: >"$NEW_MARKER"
trap 'rm -f "$NEW_MARKER"; exit 0' TERM HUP INT
while :; do
  sleep 1
done
SH
chmod 0755 "$new_agent_source"

cat >"$install_dir/monk-agent" <<'SH'
#!/usr/bin/env sh
exit 0
SH
chmod 0755 "$install_dir/monk-agent"

cat >"$plugin_root/scripts/ensure-monk-agent.sh" <<'SH'
#!/usr/bin/env sh
set -eu
target="$MONK_AGENT_INSTALL_DIR/monk-agent"
cp "$NEW_AGENT_SOURCE" "$target"
chmod 0755 "$target"
printf '%s\n' "$target"
SH
chmod 0755 "$plugin_root/scripts/ensure-monk-agent.sh"

old_pid_file="$test_root/old-pid"
(
  OLD_MARKER="$old_marker" "$test_root/old-monk-agent" &
  printf '%s\n' "$!" >"$old_pid_file"
  wait "$!"
) &
old_reaper_pid="$!"

i=0
while [ "$i" -lt 20 ] && [ ! -f "$old_pid_file" ]; do
  sleep 1
  i=$((i + 1))
done
[ -f "$old_pid_file" ] || {
  echo "old companion fixture did not start" >&2
  exit 1
}
old_pid="$(cat "$old_pid_file")"
pid_dir="$monk_home/agent/launcher/run"
mkdir -p "$pid_dir"
printf '%s\n' "$old_pid" >"$pid_dir/monk-agent.pid"

i=0
while [ "$i" -lt 20 ] && [ ! -f "$old_marker" ]; do
  sleep 1
  i=$((i + 1))
done
[ -f "$old_marker" ] || {
  echo "old companion fixture did not become healthy" >&2
  exit 1
}

export OLD_MARKER="$old_marker"
export NEW_MARKER="$new_marker"
export ATTEMPT_LOG="$attempt_log"
export NEW_AGENT_SOURCE="$new_agent_source"
export PATH="$fake_bin:/usr/bin:/bin"
export HOME="$home_dir"
export CLAUDE_PLUGIN_ROOT="$plugin_root"
export MONK_AGENT_HOME="$monk_home"
export MONK_AGENT_INSTALL_DIR="$install_dir"
export MONK_AGENT_HOST="127.0.0.1"
export MONK_AGENT_PORT="17419"
export MONK_AGENT_SKIP_SIGNIN_NUDGE="1"
export MONK_DISABLE_ANALYTICS="1"

"$repo_root/scripts/start-monk-agent.sh"

# The old process deliberately takes two seconds to release its simulated
# health endpoint. Once it is gone, the successful launcher must have left a
# replacement companion running.
i=0
while [ "$i" -lt 10 ] && [ -f "$old_marker" ]; do
  sleep 1
  i=$((i + 1))
done

if [ -f "$old_marker" ]; then
  echo "old companion did not stop" >&2
  exit 1
fi
if [ ! -f "$new_marker" ]; then
  replacement_attempts="0"
  if [ -f "$attempt_log" ]; then
    replacement_attempts="$(wc -l <"$attempt_log" | tr -d ' ')"
  fi
  printf '%s\n' \
    "launcher_exit=0" \
    "old_companion_alive=no" \
    "replacement_companion_alive=no" \
    "replacement_start_attempts=$replacement_attempts"
  log_file="$monk_home/agent/launcher/logs/monk-agent.log"
  if [ -s "$log_file" ]; then
    sed -n '1,80p' "$log_file"
  fi
  echo "launcher returned success before the replacement companion was running" >&2
  exit 1
fi
if [ "$(wc -l <"$attempt_log" | tr -d ' ')" != "1" ]; then
  echo "expected exactly one replacement start attempt" >&2
  exit 1
fi

echo "POSIX restart handoff test passed."
