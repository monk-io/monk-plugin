#!/usr/bin/env sh
set -eu

repo_root="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
tmp="$(mktemp -d)"
cleanup() {
  if [ -f "$tmp/old.pid" ]; then
    old_pid="$(cat "$tmp/old.pid" 2>/dev/null || true)"
    case "$old_pid" in ''|0|*[!0-9]*) ;; *) kill "$old_pid" >/dev/null 2>&1 || true ;; esac
  fi
  if [ -f "$tmp/new.pid" ]; then
    new_pid="$(cat "$tmp/new.pid" 2>/dev/null || true)"
    case "$new_pid" in ''|0|*[!0-9]*) ;; *) kill "$new_pid" >/dev/null 2>&1 || true ;; esac
  fi
  rm -rf "$tmp"
}
trap cleanup EXIT HUP INT TERM

cat >"$tmp/uname" <<'EOF'
#!/usr/bin/env sh
printf '%s\n' Linux
EOF
chmod +x "$tmp/uname"

cat >"$tmp/curl" <<'EOF'
#!/usr/bin/env sh
if [ -f "$TEST_NEW_STARTED_FILE" ]; then
  printf '{"resource":"http://127.0.0.1:7419/mcp"}\n'
  exit 0
fi
exit 7
EOF
chmod +x "$tmp/curl"

cat >"$tmp/monk-agent" <<'EOF'
#!/usr/bin/env sh
if [ ! -f "$TEST_OLD_EXIT_FILE" ]; then
  printf 'replacement started before old pid exited\n' >"$TEST_VIOLATION_FILE"
fi
printf '%s\n' "$$" >"$TEST_NEW_PID_FILE"
touch "$TEST_NEW_STARTED_FILE"
while :; do sleep 1; done
EOF
chmod +x "$tmp/monk-agent"

export TEST_OLD_EXIT_FILE="$tmp/old-exited"
export TEST_NEW_STARTED_FILE="$tmp/new-started"
export TEST_NEW_PID_FILE="$tmp/new.pid"
export TEST_VIOLATION_FILE="$tmp/violation"

(
  trap 'sleep 2; touch "$TEST_OLD_EXIT_FILE"; exit 0' TERM
  while :; do sleep 1; done
) &
old_pid="$!"
printf '%s\n' "$old_pid" >"$tmp/old.pid"

pid_dir="$tmp/home/agent/launcher/run"
mkdir -p "$pid_dir"
printf '%s\n' "$old_pid" >"$pid_dir/monk-agent.pid"

PATH="$tmp:$PATH" \
HOME="$tmp/user-home" \
MONK_AGENT_HOME="$tmp/home" \
MONK_AGENT_PATH="$tmp/monk-agent" \
MONK_AGENT_SKIP_ENSURE=1 \
MONK_AGENT_PORT=7419 \
MONK_AGENT_HOST=127.0.0.1 \
"$repo_root/scripts/start-monk-agent.sh" >/dev/null

if [ -f "$TEST_VIOLATION_FILE" ]; then
  cat "$TEST_VIOLATION_FILE" >&2
  exit 1
fi
if [ ! -f "$TEST_OLD_EXIT_FILE" ]; then
  echo "old pid did not receive SIGTERM and exit" >&2
  exit 1
fi
if [ ! -f "$TEST_NEW_STARTED_FILE" ]; then
  echo "replacement agent was not started" >&2
  exit 1
fi
