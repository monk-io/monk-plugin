#!/usr/bin/env sh
set -eu

repo="${MONK_TEST_REPO_ROOT:-"$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)"}"
expect="${MONK_TEST_EXPECT:-patched}"
launchers="
scripts/start-monk-agent.sh
plugins/monk/scripts/start-monk-agent.sh
.antigravity-plugin/scripts/start-monk-agent.sh
"

root="$(mktemp -d)"
cleanup() {
  rm -rf "$root"
}
trap cleanup EXIT HUP INT TERM

run_launcher() {
  launcher="$1"
  case_root="$2"
  os="$3"
  curl_mode="$4"
  sleep_log="$5"

  HOME="$case_root/home" \
  MONK_AGENT_HOME="$case_root/monk" \
  MONK_AGENT_PATH=/usr/bin/false \
  MONK_AGENT_SKIP_ENSURE=1 \
  MONK_AGENT_SKIP_SIGNIN_NUDGE=1 \
  MONK_TEST_UNAME="$os" \
  MONK_TEST_CURL_MODE="$curl_mode" \
  MONK_TEST_SLEEP_LOG="$sleep_log" \
  /bin/sh -c '
    uname() {
      printf "%s\n" "$MONK_TEST_UNAME"
    }

    setsid() {
      "$@"
    }

    curl() {
      if [ "$MONK_TEST_CURL_MODE" = "healthy" ]; then
        printf "{\"resource\":\"http://127.0.0.1:7419\"}\n"
        return 0
      fi

      pid_file="$MONK_AGENT_HOME/agent/launcher/run/monk-agent.pid"
      while :; do
        pid="$(cat "$pid_file" 2>/dev/null || true)"
        if [ -n "$pid" ] && ! kill -0 "$pid" 2>/dev/null; then
          return 7
        fi
      done
    }

    sleep() {
      pid_file="$MONK_AGENT_HOME/agent/launcher/run/monk-agent.pid"
      pid="$(cat "$pid_file" 2>/dev/null || true)"
      if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
        printf "%s\n" ALIVE >>"$MONK_TEST_SLEEP_LOG"
      else
        printf "%s\n" DEAD >>"$MONK_TEST_SLEEP_LOG"
      fi
    }

    launchctl() {
      return 0
    }

    . "$0"
  ' "$launcher"
}

run_failed_child() {
  rel="$1"
  case_name="$(printf '%s' "$rel" | tr '/.' '__')"
  case_root="$root/failed-$case_name"
  sleep_log="$case_root/sleeps"
  mkdir -p "$case_root/home"
  : >"$sleep_log"

  set +e
  output="$(run_launcher "$repo/$rel" "$case_root" Linux failed "$sleep_log" 2>&1)"
  status=$?
  set -e

  sleep_count="$(wc -l <"$sleep_log" | tr -d ' ')"
  test "$status" -eq 1

  if [ "$expect" = "base" ]; then
    test "$sleep_count" -eq 180
    printf '%s\n' "$output" |
      grep -F "monk-agent did not become ready at http://127.0.0.1:7419/.well-known/oauth-protected-resource within 180s." >/dev/null
  else
    test "$sleep_count" -eq 0
    printf '%s\n' "$output" |
      grep -E '^monk-agent process [0-9]+ exited before becoming ready\.$' >/dev/null
    printf '%s\n' "$output" |
      grep -F "Log: $case_root/monk/agent/launcher/logs/monk-agent.log" >/dev/null
  fi
}

run_healthy() {
  rel="$1"
  os="$2"
  case_name="$(printf '%s-%s' "$rel" "$os" | tr '/.' '__')"
  case_root="$root/healthy-$case_name"
  sleep_log="$case_root/sleeps"
  mkdir -p "$case_root/home"
  : >"$sleep_log"

  set +e
  output="$(run_launcher "$repo/$rel" "$case_root" "$os" healthy "$sleep_log" 2>&1)"
  status=$?
  set -e

  test "$status" -eq 0
  if printf '%s\n' "$output" | grep -E 'parameter not set|unbound variable' >/dev/null; then
    printf '%s\n' "$output" >&2
    return 1
  fi
}

for rel in $launchers; do
  run_failed_child "$rel"
  if [ "$expect" != "base" ]; then
    run_healthy "$rel" Linux
    run_healthy "$rel" Darwin
  fi
done

if [ "$expect" != "base" ]; then
  cmp "$repo/scripts/start-monk-agent.sh" \
    "$repo/plugins/monk/scripts/start-monk-agent.sh"
  cmp "$repo/scripts/start-monk-agent.sh" \
    "$repo/.antigravity-plugin/scripts/start-monk-agent.sh"
fi

printf 'launcher child-exit regression passed (%s)\n' "$expect"
