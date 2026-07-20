#!/usr/bin/env sh
set -eu

repo="$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)"
ensure="$repo/scripts/ensure-monk-agent.sh"
root="$(mktemp -d)"
cleanup() {
  rm -rf "$root"
}
trap cleanup EXIT HUP INT TERM

mkdir -p "$root/fakebin" "$root/payload" "$root/install"
printf '#!/usr/bin/env sh\nprintf "fixture-agent\\n"\n' >"$root/payload/monk-agent"
chmod 0755 "$root/payload/monk-agent"
tar -czf "$root/agent.tar.gz" -C "$root/payload" monk-agent
archive_sum="$(shasum -a 256 "$root/agent.tar.gz" | awk '{print $1}')"
printf '%s  monk-agent-test.tar.gz\n' "$archive_sum" >"$root/agent.tar.gz.sha256"

cat >"$root/barrier.py" <<'PY'
import fcntl
import pathlib
import sys
import time

path = pathlib.Path(sys.argv[1])
path.touch(exist_ok=True)
with path.open("r+") as handle:
    fcntl.flock(handle, fcntl.LOCK_EX)
    count = int(handle.read().strip() or "0") + 1
    handle.seek(0)
    handle.truncate()
    handle.write(str(count))
    handle.flush()
    fcntl.flock(handle, fcntl.LOCK_UN)

deadline = time.time() + 10
while time.time() < deadline:
    with path.open("r") as handle:
        fcntl.flock(handle, fcntl.LOCK_SH)
        count = int(handle.read().strip() or "0")
        fcntl.flock(handle, fcntl.LOCK_UN)
    if count >= 2:
        break
    time.sleep(0.01)
else:
    raise SystemExit("barrier timeout")
PY

cat >"$root/fakebin/curl" <<'EOF'
#!/usr/bin/env sh
set -eu
url=""
out=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    -o) out="$2"; shift 2 ;;
    -*) shift ;;
    *) url="$1"; shift ;;
  esac
done
if [ "${TEST_SIGNAL_PAUSE:-0}" = "1" ]; then
  printf '%s\n' "$$" >"$TEST_ROOT/signal-child"
  : >"$TEST_ROOT/signal-ready"
  while :; do
    sleep 1
  done
fi
case "$url" in
  *.sha256)
    cp "$TEST_ROOT/agent.tar.gz.sha256" "$out"
    ;;
  *)
    cp "$TEST_ROOT/agent.tar.gz" "$out"
    if [ "${TEST_BAD_ARCHIVE:-0}" = "1" ]; then
      printf 'corrupt\n' >>"$out"
    fi
    ;;
esac
EOF

cat >"$root/fakebin/mv" <<'EOF'
#!/usr/bin/env sh
set -eu
case "${1:-}" in
  */extract/monk-agent|*/.monk-agent.extract/monk-agent)
    if [ "${TEST_CONCURRENT:-0}" = "1" ]; then
      /usr/bin/python3 "$TEST_ROOT/barrier.py" "$TEST_ROOT/publish-count"
    fi
    ;;
esac
exec /bin/mv "$@"
EOF
chmod 0755 "$root/fakebin/curl" "$root/fakebin/mv"

set +e
TEST_ROOT="$root" TEST_CONCURRENT=1 PATH="$root/fakebin:/usr/bin:/bin" \
  HOME="$root/home" MONK_AGENT_INSTALL_DIR="$root/install" \
  MONK_AGENT_DOWNLOAD_BASE=https://invalid.example.test/stable \
  /bin/sh "$ensure" >"$root/one.out" 2>"$root/one.err" & p1=$!
TEST_ROOT="$root" TEST_CONCURRENT=1 PATH="$root/fakebin:/usr/bin:/bin" \
  HOME="$root/home" MONK_AGENT_INSTALL_DIR="$root/install" \
  MONK_AGENT_DOWNLOAD_BASE=https://invalid.example.test/stable \
  /bin/sh "$ensure" >"$root/two.out" 2>"$root/two.err" & p2=$!
wait "$p1"; s1=$?
wait "$p2"; s2=$?
set -e

target="$root/install/monk-agent"
sidecar="$root/install/monk-agent.sha256"
if [ "$s1" -ne 0 ] || [ "$s2" -ne 0 ]; then
  printf 'unexpected concurrent statuses: %s,%s\n' "$s1" "$s2" >&2
  cat "$root/one.err" "$root/two.err" >&2
  exit 1
fi
test "$(cat "$root/one.out")" = "$target"
test "$(cat "$root/two.out")" = "$target"
test -x "$target"
cmp -s "$target" "$root/payload/monk-agent"
test "$(awk '{print $1}' "$sidecar")" = "$archive_sum"
test -z "$(find "$root/install" -maxdepth 1 -name '.monk-agent.stage.*' -print -quit)"

mkdir -p "$root/bad-install"
set +e
TEST_ROOT="$root" TEST_BAD_ARCHIVE=1 PATH="$root/fakebin:/usr/bin:/bin" \
  HOME="$root/home" MONK_AGENT_INSTALL_DIR="$root/bad-install" \
  MONK_AGENT_DOWNLOAD_BASE=https://invalid.example.test/stable \
  /bin/sh "$ensure" >"$root/bad.out" 2>"$root/bad.err"
bad_status=$?
set -e
test "$bad_status" -eq 1
grep -q 'Checksum verification failed for monk-agent.' "$root/bad.err"
test ! -e "$root/bad-install/monk-agent"
test -z "$(find "$root/bad-install" -maxdepth 1 -name '.monk-agent.stage.*' -print -quit)"

mkdir -p "$root/signal-install"
set +e
TEST_ROOT="$root" TEST_SIGNAL_PAUSE=1 PATH="$root/fakebin:/usr/bin:/bin" \
  HOME="$root/home" MONK_AGENT_INSTALL_DIR="$root/signal-install" \
  MONK_AGENT_DOWNLOAD_BASE=https://invalid.example.test/stable \
  /bin/sh "$ensure" >"$root/signal.out" 2>"$root/signal.err" & signal_pid=$!
/usr/bin/python3 - "$root/signal-ready" <<'PY'
import pathlib
import sys
import time

ready = pathlib.Path(sys.argv[1])
deadline = time.time() + 10
while not ready.exists() and time.time() < deadline:
    time.sleep(0.01)
if not ready.exists():
    raise SystemExit("signal fixture timeout")
PY
signal_child="$(cat "$root/signal-child")"
kill -TERM "$signal_pid" "$signal_child" 2>/dev/null
wait "$signal_pid"
signal_status=$?
set -e
test "$signal_status" -eq 143
test ! -e "$root/signal-install/monk-agent"
test -z "$(find "$root/signal-install" -maxdepth 1 -name '.monk-agent.stage.*' -print -quit)"

cmp -s "$repo/scripts/ensure-monk-agent.sh" "$repo/plugins/monk/scripts/ensure-monk-agent.sh"
cmp -s "$repo/scripts/ensure-monk-agent.sh" "$repo/.antigravity-plugin/scripts/ensure-monk-agent.sh"

printf 'concurrent_statuses=%s,%s failure_status=%s signal_status=%s parity=ok cleanup=ok\n' \
  "$s1" "$s2" "$bad_status" "$signal_status"
