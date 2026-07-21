#!/usr/bin/env sh
set -eu

repo_root="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT HUP INT TERM

fake_bin="$tmp/bin"
mkdir -p "$fake_bin"

for command_name in dirname grep mkdir mktemp mv python3 sh tr; do
  command_path="$(command -v "$command_name")"
  ln -s "$command_path" "$fake_bin/$command_name"
done

ln -s "$repo_root/tests/fixtures/start-monk-agent/curl" "$fake_bin/curl"
ln -s "$repo_root/tests/fixtures/start-monk-agent/uname" "$fake_bin/uname"

for launcher in \
  scripts/start-monk-agent.sh \
  plugins/monk/scripts/start-monk-agent.sh \
  .antigravity-plugin/scripts/start-monk-agent.sh
do
  launcher_name="$(printf '%s' "$launcher" | tr '/.' '__')"
  home="$tmp/$launcher_name/O'Connor"
  config="$home/.gemini/config/mcp_config.json"
  mkdir -p "$(dirname "$config")"
  printf '%s\n' '{"mcpServers":{},"preserved":{"value":"still here"}}' >"$config"

  HOME="$home" \
  PATH="$fake_bin" \
  MONK_AGENT_HOME="$home/.monk" \
  MONK_AGENT_PATH=/usr/bin/true \
  MONK_AGENT_SKIP_SIGNIN_NUDGE=1 \
    "$repo_root/$launcher"

  python3 - "$config" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as handle:
    config = json.load(handle)

assert config["mcpServers"]["monk"]["serverUrl"] == "http://127.0.0.1:7419/mcp"
assert config["preserved"] == {"value": "still here"}
PY
done

cmp "$repo_root/scripts/start-monk-agent.sh" \
  "$repo_root/plugins/monk/scripts/start-monk-agent.sh"
cmp "$repo_root/scripts/start-monk-agent.sh" \
  "$repo_root/.antigravity-plugin/scripts/start-monk-agent.sh"

echo "Antigravity Python fallback handles apostrophes in all rendered launchers"
