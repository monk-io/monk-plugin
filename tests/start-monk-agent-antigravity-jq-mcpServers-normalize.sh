#!/usr/bin/env sh
# Regression coverage for plugin#380: the Antigravity MCP registration's jq path
# must normalise a non-object mcpServers value to an object instead of aborting.
set -eu

repo_root="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
fixture_src="$repo_root/tests/fixtures/start-monk-agent"
work_dir="$(mktemp -d)"
trap 'rm -rf "$work_dir"' EXIT HUP INT TERM

if ! command -v jq >/dev/null 2>&1; then
  echo "jq not available; skipping Antigravity jq normalisation regression" >&2
  exit 0
fi

fake_bin="$work_dir/bin"
mkdir -p "$fake_bin"
for command_name in cat date dirname grep head id kill mkdir mktemp mv sed sh tr; do
  command_path="$(command -v "$command_name" || true)"
  case "$command_path" in
    /*) ln -s "$command_path" "$fake_bin/$command_name" ;;
  esac
done
ln -s "$fixture_src/curl" "$fake_bin/curl"
ln -s "$fixture_src/uname" "$fake_bin/uname"

home="$work_dir/home"
config="$home/.gemini/config/mcp_config.json"
mkdir -p "$(dirname "$config")"
printf '%s\n' '{"mcpServers":"legacy-string-value","preserved":{"value":"still here"}}' >"$config"

HOME="$home" \
PATH="$fake_bin" \
MONK_AGENT_HOME="$home/.monk" \
MONK_AGENT_PATH=/usr/bin/true \
MONK_AGENT_SKIP_SIGNIN_NUDGE=1 \
  "$repo_root/scripts/start-monk-agent.sh"

jq -e '
  .mcpServers | type == "object" and
  .mcpServers.monk.serverUrl == "http://127.0.0.1:7419/mcp" and
  .preserved == {"value":"still here"}
' "$config" >/dev/null

echo "Antigravity jq fallback normalises non-object mcpServers."
