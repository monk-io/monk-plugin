#!/usr/bin/env sh
# Regression coverage for the Antigravity MCP cleanup's python3 fallback.
# An apostrophe in HOME must be treated as data rather than interpolated into
# generated Python source. PATH is isolated to exclude jq and force the
# fallback under test.
set -eu

repo_root="${MONK_TEST_REPO_ROOT:-$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)}"
fixture_src="$repo_root/tests/fixtures/start-monk-agent"
work_dir="$(mktemp -d)"
trap 'rm -rf "$work_dir"' EXIT HUP INT TERM

if ! command -v python3 >/dev/null 2>&1; then
  echo "python3 not available; skipping Antigravity uninstall regression" >&2
  exit 0
fi

fake_bin="$work_dir/bin"
mkdir -p "$fake_bin"
for command_name in cat dirname id kill mktemp mv python3 ps rm sh tr; do
  command_path="$(command -v "$command_name" || true)"
  case "$command_path" in
    /*)
      printf '#!/usr/bin/sh\nexec "%s" "$@"\n' "$command_path" >"$fake_bin/$command_name"
      chmod +x "$fake_bin/$command_name"
      ;;
  esac
done
printf '#!/usr/bin/sh\nexec "%s" "$@"\n' "$fixture_src/uname" >"$fake_bin/uname"
chmod +x "$fake_bin/uname"

home_root="$work_dir"
case "$(uname -s 2>/dev/null || printf unknown)" in
  MINGW*|MSYS*|CYGWIN*) home_root="$(cygpath -m "$work_dir")" ;;
esac
home="$home_root/home/O'Connor"
config="$home/.gemini/config/mcp_config.json"
mkdir -p "$(dirname "$config")"
printf '%s\n' '{"mcpServers":{"monk":{"serverUrl":"http://127.0.0.1:7419/mcp"},"preserved":{"serverUrl":"http://127.0.0.1:9999/mcp"}},"preserved":{"value":"still here"}}' >"$config"

HOME="$home" \
PATH="$fake_bin" \
MONK_AGENT_HOME="$home/.monk" \
MONK_AGENT_INSTALL_DIR="$home/.monk/bin" \
  /usr/bin/sh "$repo_root/scripts/uninstall-monk-agent.sh" --yes

python3 -c '
import json, sys

with open(sys.argv[1], encoding="utf-8") as handle:
    config = json.load(handle)

assert "monk" not in config.get("mcpServers", {})
assert config["mcpServers"]["preserved"] == {"serverUrl": "http://127.0.0.1:9999/mcp"}
assert config["preserved"] == {"value": "still here"}
' "$config"

echo "Antigravity uninstall Python fallback handles apostrophes in the config path."
