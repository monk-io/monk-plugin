#!/usr/bin/env sh
# Regression coverage for launchers running inside a strictly confined snap,
# where tools exist on PATH but fail when run: `shasum` (its Perl interpreter is
# not visible) and `setsid` (refused). The launchers must fall through to a
# working alternative rather than trusting a tool's mere presence.
set -eu

repo_root="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
fixture_bin="$repo_root/tests/fixtures/start-monk-agent"
work_dir="$(mktemp -d)"
trap 'rm -rf "$work_dir"' EXIT HUP INT TERM

broken_bin="$work_dir/broken-bin"
mkdir -p "$broken_bin"
broken_tool() {
  printf '#!/bin/sh\necho "%s: cannot run in this sandbox" >&2\nexit 126\n' "$1" >"$broken_bin/$1"
  chmod +x "$broken_bin/$1"
}

real_sha256() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  else
    shasum -a 256 "$1" | awk '{print $1}'
  fi
}

# ensure-monk-agent.sh's offline fallback: the update check can't reach the
# download host, so it verifies the installed binary against the checksum
# recorded at install time. That must still work when `shasum` is broken.
run_ensure_offline() {
  label="$1"
  shift
  install_dir="$work_dir/$label/install"
  mkdir -p "$install_dir"
  printf '#!/bin/sh\ntrue\n' >"$install_dir/monk-agent"
  chmod +x "$install_dir/monk-agent"
  printf '%s  monk-agent-linux-latest.tar.gz\n' "$(real_sha256 "$install_dir/monk-agent")" \
    >"$install_dir/monk-agent.sha256"
  out="$(
    PATH="$broken_bin:/usr/bin:/bin" \
    MONK_AGENT_INSTALL_DIR="$install_dir" \
    MONK_AGENT_DOWNLOAD_BASE="http://127.0.0.1:9" \
    MONK_AGENT_DOWNLOAD_CONNECT_TIMEOUT=2 \
      "$repo_root/scripts/ensure-monk-agent.sh" 2>"$work_dir/$label/stderr"
  )" || {
    echo "$label: ensure-monk-agent.sh failed to verify the installed binary" >&2
    cat "$work_dir/$label/stderr" >&2
    exit 1
  }
  if [ "$out" != "$install_dir/monk-agent" ]; then
    echo "$label: expected $install_dir/monk-agent, got: $out" >&2
    exit 1
  fi
}

# Case 1: shasum present but broken; sha256sum must be used instead.
broken_tool shasum
run_ensure_offline broken-shasum

# Case 2: both shasum and sha256sum broken; openssl is the last resort.
if command -v openssl >/dev/null 2>&1; then
  broken_tool sha256sum
  run_ensure_offline broken-shasum-and-sha256sum
  rm -f "$broken_bin/sha256sum"
fi

# Case 3: start-monk-agent.sh with setsid present but refused must still start
# the agent (via nohup). A drifted state file forces a (re)start; the fixture
# curl reports healthy, so the marker is what proves the agent actually ran.
broken_tool setsid
agent_home="$work_dir/setsid/monk"
run_dir="$agent_home/agent/launcher/run"
mkdir -p "$run_dir"
marker="$work_dir/setsid/agent-started"
agent="$work_dir/setsid/fake-agent"
printf '#!/bin/sh\ntouch "%s"\n' "$marker" >"$agent"
chmod +x "$agent"
{
  printf 'agent_path=%s\n' "$agent"
  printf 'auth_url=https://auth-one.invalid\n'
} >"$run_dir/monk-agent.state"

HOME="$work_dir/home" \
PATH="$broken_bin:$fixture_bin:/usr/bin:/bin" \
MONK_AGENT_PATH="$agent" \
MONK_AGENT_HOME="$agent_home" \
MONK_AUTH_URL="https://auth-two.invalid" \
MONK_AGENT_SKIP_SIGNIN_NUDGE=1 \
  "$repo_root/scripts/start-monk-agent.sh" >/dev/null

waited=0
while [ ! -e "$marker" ]; do
  waited=$((waited + 1))
  if [ "$waited" -ge 50 ]; then
    echo "agent never started when setsid was present but refused" >&2
    exit 1
  fi
  sleep 0.1
done

echo "start-monk-agent snap-tools tests passed."
