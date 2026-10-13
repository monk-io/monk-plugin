#!/usr/bin/env sh
# Regression coverage for ENG-401: the Antigravity MCP registration's python3
# fallback must treat the config path and server URL as data (argv), not
# interpolate them into generated Python source -- an apostrophe in the path
# (e.g. a home directory like "O'Connor") otherwise breaks the generated
# Python string and aborts session startup under `set -e`. PATH is isolated to
# exclude jq so the launcher is forced onto the python3 fallback being tested.
set -eu

repo_root="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
fixture_src="$repo_root/tests/fixtures/start-monk-agent"
work_dir="$(mktemp -d)"
trap 'rm -rf "$work_dir"' EXIT HUP INT TERM

if ! command -v python3 >/dev/null 2>&1; then
  echo "python3 not available; skipping Antigravity python-fallback regression" >&2
  exit 0
fi

fake_bin="$work_dir/bin"
mkdir -p "$fake_bin"
for command_name in cat date dirname grep head id kill mkdir mktemp mv python3 sed sh tr; do
  # Some shells provide commands like `kill` as builtins with no external
  # binary on PATH -- skip those rather than fail; the shell running this
  # launcher still has the builtin available regardless of PATH.
  command_path="$(command -v "$command_name" || true)"
  case "$command_path" in
    /*) ln -s "$command_path" "$fake_bin/$command_name" ;;
  esac
done
ln -s "$fixture_src/curl" "$fake_bin/curl"
ln -s "$fixture_src/uname" "$fake_bin/uname"

home="$work_dir/home/O'Connor"
config="$home/.gemini/config/mcp_config.json"
mkdir -p "$(dirname "$config")"
printf '%s\n' '{"mcpServers":{},"preserved":{"value":"still here"}}' >"$config"

HOME="$home" \
PATH="$fake_bin" \
MONK_AGENT_HOME="$home/.monk" \
MONK_AGENT_PATH=/usr/bin/true \
MONK_AGENT_SKIP_SIGNIN_NUDGE=1 \
  "$repo_root/scripts/start-monk-agent.sh"

python3 -c '
import json, sys

with open(sys.argv[1], encoding="utf-8") as handle:
    config = json.load(handle)

assert config["mcpServers"]["monk"] == {"command": "/usr/bin/true", "args": ["mcp-stdio", "--url", "http://127.0.0.1:7419/mcp"]}
assert config["preserved"] == {"value": "still here"}
' "$config"

echo "Antigravity Python fallback handles apostrophes in the config path."
