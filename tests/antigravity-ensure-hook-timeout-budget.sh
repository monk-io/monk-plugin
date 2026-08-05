#!/usr/bin/env bash
set -euo pipefail

repo_root="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
hook="$repo_root/.antigravity-plugin/hooks/ensure-monk-agent.sh"
hooks_json="$repo_root/.antigravity-plugin/hooks.json"

tmp="$(mktemp -d)"
agent_pid=""
cleanup() {
  if [ -f "$tmp/home/.monk/agent/launcher/run/monk-agent.pid" ]; then
    agent_pid="$(cat "$tmp/home/.monk/agent/launcher/run/monk-agent.pid" 2>/dev/null || true)"
  fi
  if [ -n "$agent_pid" ]; then
    kill "$agent_pid" 2>/dev/null || true
  fi
  rm -rf "$tmp"
}
trap cleanup EXIT

mkdir -p "$tmp/bin" "$tmp/home"

# Keep the launched process alive while making every readiness probe use its
# full two-second request budget. This exposes the difference between retry
# count and elapsed wall-clock time without using the network or monk-agent.
cat >"$tmp/monk-agent" <<'EOF'
#!/usr/bin/env sh
exec sleep 60
EOF
chmod +x "$tmp/monk-agent"

cat >"$tmp/bin/curl" <<'EOF'
#!/usr/bin/env sh
sleep 2
exit 1
EOF
chmod +x "$tmp/bin/curl"

configured_timeout="$(sed -n 's/.*"timeout"[[:space:]]*:[[:space:]]*\([0-9][0-9]*\).*/\1/p' "$hooks_json" | head -n 1)"
if [ -z "$configured_timeout" ]; then
  echo "fixture assumption failed: could not read Antigravity ensure hook timeout" >&2
  exit 2
fi

set +e
PATH="$tmp/bin:$PATH" \
HOME="$tmp/home" \
MONK_AGENT_PATH="$tmp/monk-agent" \
MONK_AGENT_HOME="$tmp/home/.monk" \
timeout "${configured_timeout}s" sh "$hook" </dev/null >"$tmp/stdout" 2>"$tmp/stderr"
status=$?
set -e

if [ "$status" -eq 124 ]; then
  if [ -s "$tmp/stdout" ]; then
    echo "unexpected stdout before the host timeout:" >&2
    cat "$tmp/stdout" >&2
  fi
  echo "FAIL: Antigravity's declared ${configured_timeout}-second timeout kills the cold-start hook before it emits readiness JSON" >&2
  exit 1
fi

if [ "$status" -ne 0 ]; then
  echo "FAIL: ensure hook exited with status $status" >&2
  cat "$tmp/stderr" >&2
  exit 1
fi

if ! grep -q 'did not become ready' "$tmp/stdout"; then
  echo "FAIL: ensure hook completed without the expected readiness diagnostic" >&2
  cat "$tmp/stdout" >&2
  exit 1
fi

echo "PASS: Antigravity cold-start hook completes within its declared timeout"
