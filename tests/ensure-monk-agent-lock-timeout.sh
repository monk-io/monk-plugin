#!/usr/bin/env sh
# Regression coverage for concurrent installers: every shipped POSIX bootstrap
# must stop at the lock deadline, while a lock released in time must recover.
set -eu

repo_root="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
fixture_bin="$repo_root/tests/fixtures/ensure-monk-agent-lock"
work_dir="$(mktemp -d)"
holder_pid=""
watchdog_pid=""

cleanup() {
  if [ -n "$watchdog_pid" ]; then
    kill "$watchdog_pid" 2>/dev/null || true
  fi
  if [ -n "$holder_pid" ]; then
    kill "$holder_pid" 2>/dev/null || true
  fi
  rm -rf "$work_dir"
}
trap cleanup EXIT HUP INT TERM

start_lock_holder() {
  lock_path="$1"
  ready_path="$2"
  release_path="${3:-}"

  python3 - "$lock_path" "$ready_path" "$release_path" <<'PY' &
import fcntl
import pathlib
import sys
import time

lock_path, ready_path, release_path = sys.argv[1:]
with open(lock_path, "w", encoding="utf-8") as lock_file:
    fcntl.flock(lock_file, fcntl.LOCK_EX)
    pathlib.Path(ready_path).touch()
    if not release_path:
        time.sleep(30)
    else:
        deadline = time.monotonic() + 5
        while not pathlib.Path(release_path).exists():
            if time.monotonic() >= deadline:
                raise TimeoutError("installer never began its bounded lock wait")
            time.sleep(0.02)
PY
  holder_pid=$!

  waited=0
  while [ ! -e "$ready_path" ]; do
    waited=$((waited + 1))
    if [ "$waited" -ge 50 ]; then
      echo "lock holder did not become ready for $lock_path" >&2
      exit 1
    fi
    sleep 0.1
  done
}

stop_lock_holder() {
  kill "$holder_pid" 2>/dev/null || true
  wait "$holder_pid" 2>/dev/null || true
  holder_pid=""
}

case_no=0
for ensure_script in \
  "$repo_root/scripts/ensure-monk-agent.sh" \
  "$repo_root/plugins/monk/scripts/ensure-monk-agent.sh" \
  "$repo_root/.antigravity-plugin/scripts/ensure-monk-agent.sh"
do
  case_no=$((case_no + 1))
  case_dir="$work_dir/case-$case_no"
  install_dir="$case_dir/install"
  ready_file="$case_dir/holder-ready"
  output_file="$case_dir/output"
  timeout_marker="$case_dir/watchdog-fired"
  mkdir -p "$install_dir"

  start_lock_holder "$install_dir/.monk-agent.lock" "$ready_file"

  set +e
  PATH="$fixture_bin:$PATH" \
  MONK_AGENT_INSTALL_DIR="$install_dir" \
  MONK_AGENT_INSTALL_LOCK_TIMEOUT=1 \
    "$ensure_script" >"$output_file" 2>&1 &
  ensure_pid=$!
  set -e

  (
    sleep 5
    : >"$timeout_marker"
    kill "$ensure_pid" 2>/dev/null || true
  ) &
  watchdog_pid=$!

  set +e
  wait "$ensure_pid"
  status=$?
  set -e
  kill "$watchdog_pid" 2>/dev/null || true
  wait "$watchdog_pid" 2>/dev/null || true
  watchdog_pid=""

  stop_lock_holder

  if [ -e "$timeout_marker" ]; then
    echo "$ensure_script waited indefinitely for the install lock" >&2
    exit 1
  fi
  if [ "$status" -eq 0 ]; then
    echo "$ensure_script unexpectedly succeeded while the install lock was held" >&2
    exit 1
  fi
  if ! grep -Fq "Timed out after 1s waiting for another monk-agent install." "$output_file"; then
    echo "$ensure_script did not explain the bounded lock failure" >&2
    cat "$output_file" >&2
    exit 1
  fi
done

# Also prove that the bounded wait does not reject an ordinary concurrent
# install that finishes before the deadline. A pre-existing executable keeps
# this path network-free after the lock is acquired.
recovery_dir="$work_dir/recovery"
install_dir="$recovery_dir/install"
ready_file="$recovery_dir/holder-ready"
wait_started="$recovery_dir/wait-started"
stdout_file="$recovery_dir/stdout"
stderr_file="$recovery_dir/stderr"
target="$install_dir/monk-agent"
mkdir -p "$install_dir"
printf '#!/usr/bin/env sh\nexit 0\n' >"$target"
chmod +x "$target"

start_lock_holder "$install_dir/.monk-agent.lock" "$ready_file" "$wait_started"

set +e
PATH="$fixture_bin:$PATH" \
MONK_AGENT_INSTALL_DIR="$install_dir" \
MONK_AGENT_INSTALL_LOCK_TIMEOUT=3 \
MONK_AGENT_AUTO_UPDATE=0 \
MONK_TEST_FLOCK_WAIT_STARTED="$wait_started" \
  "$repo_root/scripts/ensure-monk-agent.sh" >"$stdout_file" 2>"$stderr_file"
status=$?
set -e
stop_lock_holder

if [ "$status" -ne 0 ]; then
  echo "installer did not recover after the lock was released" >&2
  cat "$stderr_file" >&2
  exit 1
fi
if [ "$(cat "$stdout_file")" != "$target" ]; then
  echo "installer returned the wrong managed binary after lock recovery" >&2
  cat "$stdout_file" >&2
  exit 1
fi
if ! grep -Fq "Another monk-agent install is in progress; waiting up to 3s..." "$stderr_file"; then
  echo "installer did not report the bounded lock wait before recovery" >&2
  cat "$stderr_file" >&2
  exit 1
fi

echo "ensure-monk-agent lock-timeout tests passed."
