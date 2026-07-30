#!/usr/bin/env sh
set -eu

repo="$(cd "$(dirname "$0")/.." && pwd)"
root="$(mktemp -d)"
cleanup() {
  if [ -f "$root/monk/agent/launcher/run/monk-agent.pid" ]; then
    pid="$(sed -n '1p' "$root/monk/agent/launcher/run/monk-agent.pid")"
    case "$pid" in
      ''|*[!0-9]*) ;;
      *) kill "$pid" 2>/dev/null || true ;;
    esac
  fi
  rm -rf "$root"
}
trap cleanup EXIT HUP INT TERM

mkdir -p "$root/home/.gemini/config" "$root/monk" "$root/install" "$root/fakebin"

cat >"$root/install/monk-agent" <<'SH'
#!/usr/bin/env sh
trap 'exit 0' TERM INT HUP
while :; do sleep 1; done
SH
chmod 0755 "$root/install/monk-agent"

cat >"$root/fakebin/curl" <<'SH'
#!/usr/bin/env sh
printf '%s\n' '{"resource":"http://127.0.0.1:7419/mcp"}'
SH
chmod 0755 "$root/fakebin/curl"

test_case() {
  name="$1"
  initial_json="$2"
  expected_has_mcp="$3"

  echo "$initial_json" > "$root/home/.gemini/config/mcp_config.json"

  status=0
  PATH="$root/fakebin:/usr/bin:/bin" \
  HOME="$root/home" \
  MONK_AGENT_HOME="$root/monk" \
  MONK_AGENT_INSTALL_DIR="$root/install" \
  MONK_AGENT_PATH="$root/install/monk-agent" \
  MONK_AGENT_SKIP_ENSURE=1 \
  MONK_AGENT_SKIP_SIGNIN_NUDGE=1 \
    sh "$repo/scripts/start-monk-agent.sh" >/dev/null 2>&1 || status=$?

  has_mcp="$(python3 - "$root/home/.gemini/config/mcp_config.json" <<'PY'
import json, sys
with open(sys.argv[1], "r", encoding="utf-8") as f:
    cfg = json.load(f)
print("yes" if isinstance(cfg.get("mcpServers"), dict) and "monk" in cfg["mcpServers"] else "no")
PY
)"

  if [ "$status" -ne 0 ]; then
    echo "FAIL: $name - launcher exited $status"
    return 1
  fi

  if [ "$has_mcp" != "$expected_has_mcp" ]; then
    echo "FAIL: $name - expected has_mcp=$expected_has_mcp, got $has_mcp"
    cat "$root/home/.gemini/config/mcp_config.json"
    return 1
  fi

  echo "PASS: $name"
}

test_case "unrelated monk string" '{"notes":"monk"}' "yes"
test_case "monk in array" '{"tags":["monk","other"]}' "yes"
test_case "monk in nested object" '{"metadata":{"author":"monk"}}' "yes"
test_case "empty config" '{}' "yes"
test_case "existing mcpServers empty" '{"mcpServers":{}}' "yes"
test_case "existing monk server" '{"mcpServers":{"monk":{"serverUrl":"http://existing"}}}' "yes"
test_case "mcpServers with other servers" '{"mcpServers":{"other":{"serverUrl":"http://other"}}}' "yes"

echo ""
echo "All tests passed"
