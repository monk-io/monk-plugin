#!/usr/bin/env sh
set -eu

repo="${REPO_UNDER_TEST:-$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)}"
hook="$repo/.antigravity-plugin/hooks/ensure-monk-agent.sh"
uninstall="$repo/scripts/uninstall-monk-agent.sh"
root="$(mktemp -d)"
agent_pid=""
system_path="$PATH"

cleanup() {
  if [ -n "$agent_pid" ]; then
    kill "$agent_pid" >/dev/null 2>&1 || true
  fi
  rm -rf "$root"
}
trap cleanup EXIT HUP INT TERM

make_launch_path() {
  mode="$1"
  bin="$root/bin-$mode"
  mkdir -p "$bin"
  for command_name in cat dirname grep mkdir mv rm sh sleep; do
    ln -s "$(command -v "$command_name")" "$bin/$command_name"
  done
  cat >"$bin/curl" <<'EOF'
#!/usr/bin/env sh
exit 1
EOF
  cat >"$bin/jq" <<'EOF'
#!/usr/bin/env sh
printf '%s\n' '{}'
EOF
  case "$mode" in
    setsid)
      cat >"$bin/setsid" <<'EOF'
#!/usr/bin/env sh
exec "$@"
EOF
      ;;
    nohup)
      cat >"$bin/nohup" <<'EOF'
#!/usr/bin/env sh
exec "$@"
EOF
      ;;
    direct) ;;
    *) printf 'unknown launch mode: %s\n' "$mode" >&2; return 2 ;;
  esac
  chmod 0755 "$bin/curl" "$bin/jq"
  if [ -e "$bin/setsid" ]; then chmod 0755 "$bin/setsid"; fi
  if [ -e "$bin/nohup" ]; then chmod 0755 "$bin/nohup"; fi
}

make_launch_path setsid
make_launch_path nohup
make_launch_path direct
mkdir -p "$root/bin-host"
cat >"$root/bin-host/curl" <<'EOF'
#!/usr/bin/env sh
exit 1
EOF
cat >"$root/bin-host/launchctl" <<'EOF'
#!/usr/bin/env sh
exit 0
EOF
chmod 0755 "$root/bin-host/curl" "$root/bin-host/launchctl"

wait_for_file() {
  path="$1"
  tries=0
  while [ ! -s "$path" ] && [ "$tries" -lt 100 ]; do
    tries=$((tries + 1))
    sleep .02
  done
  test -s "$path"
}

wait_for_exit() {
  pid="$1"
  tries=0
  while kill -0 "$pid" >/dev/null 2>&1 && [ "$tries" -lt 100 ]; do
    tries=$((tries + 1))
    sleep .02
  done
  ! kill -0 "$pid" >/dev/null 2>&1
}

run_case() {
  label="$1"
  seed="$2"
  mode="$3"
  case "$mode" in
    host) launch_path="$root/bin-host:$system_path" ;;
    *) launch_path="$root/bin-$mode" ;;
  esac
  case_root="$root/$label"
  home="$case_root/home"
  monk_home="$home/.monk"
  install="$case_root/install"
  target="$install/monk-agent"
  pid_capture="$case_root/agent.pid"
  pid_file="$monk_home/agent/launcher/run/monk-agent.pid"
  mkdir -p "$install" "$(dirname -- "$pid_file")"

  cat >"$target" <<'EOF'
#!/usr/bin/env sh
printf '%s\n' "$$" >"$TEST_PID_CAPTURE"
trap 'exit 0' TERM INT HUP
while :; do sleep .1; done
EOF
  chmod 0755 "$target"

  case "$seed" in
    missing) ;;
    stale)
      /bin/sh -c 'exit 0' & stale_pid=$!
      wait "$stale_pid"
      printf '%s\n' "$stale_pid" >"$pid_file"
      ;;
    *) printf 'unknown seed: %s\n' "$seed" >&2; return 2 ;;
  esac

  hook_output="$(
    PATH="$launch_path" \
    HOME="$home" MONK_AGENT_HOME="$monk_home" \
    MONK_AGENT_INSTALL_DIR="$install" TEST_PID_CAPTURE="$pid_capture" \
      /bin/sh "$hook"
  )"
  case "$mode" in
    host)
      printf '%s\n' "$hook_output" | jq -e \
        '.injectSteps[0].ephemeralMessage | contains("has been started")' >/dev/null
      ;;
    *) test "$hook_output" = '{}' ;;
  esac
  wait_for_file "$pid_capture"
  wait_for_file "$pid_file"

  agent_pid="$(cat "$pid_capture")"
  test "$agent_pid" = "$(cat "$pid_file")"
  kill -0 "$agent_pid" >/dev/null 2>&1

  uninstall_output="$(
    PATH="$launch_path" \
    HOME="$home" MONK_AGENT_HOME="$monk_home" \
    MONK_AGENT_INSTALL_DIR="$install" \
      /bin/sh "$uninstall" --yes
  )"
  test "$uninstall_output" = 'monk-agent uninstall complete.'
  wait_for_exit "$agent_pid"
  agent_pid=""
  test ! -e "$target"
  test ! -e "$pid_file"
}

run_publication_failure_case() {
  case_root="$root/publication-failure"
  home="$case_root/home"
  monk_home="$home/.monk"
  install="$case_root/install"
  target="$install/monk-agent"
  pid_capture="$case_root/agent.pid"
  pid_file="$monk_home/agent/launcher/run/monk-agent.pid"
  failure_bin="$root/bin-publication-failure"
  mkdir -p "$install" "$(dirname -- "$pid_file")" "$failure_bin"

  for command_name in cat dirname grep mkdir rm sh sleep; do
    ln -s "$(command -v "$command_name")" "$failure_bin/$command_name"
  done
  cat >"$failure_bin/curl" <<'EOF'
#!/usr/bin/env sh
exit 1
EOF
  cat >"$failure_bin/jq" <<'EOF'
#!/usr/bin/env sh
printf '%s\n' '{}'
EOF
  cat >"$failure_bin/nohup" <<'EOF'
#!/usr/bin/env sh
exec "$@"
EOF
  cat >"$failure_bin/mv" <<'EOF'
#!/usr/bin/env sh
tries=0
while [ ! -s "$TEST_PID_CAPTURE" ] && [ "$tries" -lt 100 ]; do
  tries=$((tries + 1))
  sleep .01
done
exit 1
EOF
  chmod 0755 "$failure_bin/curl" "$failure_bin/jq" "$failure_bin/nohup" "$failure_bin/mv"

  cat >"$target" <<'EOF'
#!/usr/bin/env sh
printf '%s\n' "$$" >"$TEST_PID_CAPTURE"
trap 'exit 0' TERM INT HUP
while :; do sleep .1; done
EOF
  chmod 0755 "$target"

  set +e
  PATH="$failure_bin" \
  HOME="$home" MONK_AGENT_HOME="$monk_home" \
  MONK_AGENT_INSTALL_DIR="$install" TEST_PID_CAPTURE="$pid_capture" \
    /bin/sh "$hook" >"$case_root/hook.out" 2>"$case_root/hook.err"
  hook_status=$?
  set -e

  test "$hook_status" -eq 1
  wait_for_file "$pid_capture"
  failed_pid="$(cat "$pid_capture")"
  wait_for_exit "$failed_pid"
  test ! -e "$pid_file"
  test -z "$(find "$(dirname -- "$pid_file")" -name '.monk-agent.pid.*' -print -quit)"
}

run_case setsid-missing missing setsid
run_case setsid-stale stale setsid
run_case nohup-missing missing nohup
run_case nohup-stale stale nohup
run_case direct-missing missing direct
run_case direct-stale stale direct
run_case host-missing missing host
run_publication_failure_case

case "$(uname -s)" in
  Linux) real_host_mode='setsid' ;;
  Darwin) real_host_mode='nohup' ;;
  *) real_host_mode='direct' ;;
esac
printf 'antigravity_hook_uninstall_cases=7 synthetic_modes=setsid,nohup,direct real_host_mode=%s publication_failure=ok real_json=ok pid_capture=exact process_exit=ok cleanup=ok\n' "$real_host_mode"
