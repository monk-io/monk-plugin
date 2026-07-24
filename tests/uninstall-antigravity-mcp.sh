#!/usr/bin/env sh
set -eu

repo_root="${1:-$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)}"
root="$(mktemp -d)"
trap 'rm -rf "$root"' EXIT HUP INT TERM

scripts="
$repo_root/scripts/uninstall-monk-agent.sh
$repo_root/plugins/monk/scripts/uninstall-monk-agent.sh
$repo_root/.antigravity-plugin/scripts/uninstall-monk-agent.sh
"

index=0
printf '%s\n' "$scripts" | while IFS= read -r script; do
  [ -n "$script" ] || continue
  case_root="$root/copy-$index"
  config="$case_root/config/mcp_config.json"
  mkdir -p "$(dirname "$config")" "$case_root/install" "$case_root/monk-home"
  cat >"$config" <<'JSON'
{
  "theme": "dark",
  "mcpServers": {
    "existing": { "serverUrl": "http://127.0.0.1:9000/mcp" },
    "monk": { "serverUrl": "http://127.0.0.1:7419/mcp" }
  }
}
JSON

  HOME="$case_root/home" \
    MONK_AGENT_INSTALL_DIR="$case_root/install" \
    MONK_AGENT_HOME="$case_root/monk-home" \
    MONK_ANTIGRAVITY_CONFIG="$config" \
    "$script" --yes --keep-data >/dev/null

  python3 - "$config" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as source:
    config = json.load(source)
assert config["theme"] == "dark"
assert config["mcpServers"]["existing"]["serverUrl"] == "http://127.0.0.1:9000/mcp"
assert "monk" not in config["mcpServers"]
PY
  index=$((index + 1))
done

case_root="$root/empty-servers"
config="$case_root/config/mcp_config.json"
mkdir -p "$(dirname "$config")" "$case_root/install" "$case_root/monk-home"
printf '%s\n' '{"other":true,"mcpServers":{"monk":{"serverUrl":"http://127.0.0.1:7419/mcp"}}}' >"$config"
HOME="$case_root/home" \
  MONK_AGENT_INSTALL_DIR="$case_root/install" \
  MONK_AGENT_HOME="$case_root/monk-home" \
  MONK_ANTIGRAVITY_CONFIG="$config" \
  "$repo_root/scripts/uninstall-monk-agent.sh" --yes --keep-data >/dev/null
python3 - "$config" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as source:
    config = json.load(source)
assert config == {"other": True}
PY

case_root="$root/malformed"
config="$case_root/config/mcp_config.json"
mkdir -p "$(dirname "$config")" "$case_root/install" "$case_root/monk-home"
printf '%s' '{not-json' >"$config"
cp "$config" "$config.before"
HOME="$case_root/home" \
  MONK_AGENT_INSTALL_DIR="$case_root/install" \
  MONK_AGENT_HOME="$case_root/monk-home" \
  MONK_ANTIGRAVITY_CONFIG="$config" \
  "$repo_root/scripts/uninstall-monk-agent.sh" --yes --keep-data >/dev/null
cmp "$config.before" "$config"

cmp "$repo_root/scripts/uninstall-monk-agent.sh" "$repo_root/plugins/monk/scripts/uninstall-monk-agent.sh"
cmp "$repo_root/scripts/uninstall-monk-agent.sh" "$repo_root/.antigravity-plugin/scripts/uninstall-monk-agent.sh"

echo "POSIX Antigravity MCP uninstall tests passed."
