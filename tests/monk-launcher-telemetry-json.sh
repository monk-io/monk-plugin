#!/usr/bin/env sh
# Regression coverage for #179: launcher telemetry must emit valid JSON without
# losing quotes, slashes, controls, or UTF-8 bytes from dynamic properties.
set -eu

repo_root="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
work_dir="$(mktemp -d)"
trap 'rm -rf "$work_dir"' EXIT HUP INT TERM
capture_path="$work_dir/payload.json"

curl() {
  _test_payload=""
  while [ "$#" -gt 0 ]; do
    if [ "$1" = "-d" ]; then
      shift
      _test_payload="$1"
    fi
    shift
  done
  printf '%s' "$_test_payload" >"$capture_path"
}

# shellcheck source=../scripts/monk-launcher-telemetry.sh
. "$repo_root/scripts/monk-launcher-telemetry.sh"

client="$(printf 'codex"\\\tline\nctrl\001<caf\303\251>&end')"
ide_version="$(printf 'v1\r\f\b\002done')"
plugin_version="$(printf 'plugin"\\\t\n\003<caf\303\251>')"
posthog_key="$(printf 'key"\\\t\004end')"

HOME="$work_dir/home"
MONK_AGENT_HOME="$work_dir/monk"
MONK_AGENT_INSTALL_DIR="$work_dir/bin"
MONK_POSTHOG_HOST="https://capture.invalid"
MONK_POSTHOG_KEY="$posthog_key"
MONK_PLUGIN_VERSION="$plugin_version"
export HOME MONK_AGENT_HOME MONK_AGENT_INSTALL_DIR
export MONK_POSTHOG_HOST MONK_POSTHOG_KEY MONK_PLUGIN_VERSION
export client ide_version plugin_version posthog_key capture_path

monk_emit_launcher_event "$client" "$ide_version"
wait
test -s "$capture_path"

if [ -z "${PYTHON:-}" ]; then
  if command -v python3 >/dev/null 2>&1; then
    PYTHON=python3
  elif command -v python >/dev/null 2>&1; then
    PYTHON=python
  else
    echo "python is required to validate the captured JSON" >&2
    exit 1
  fi
fi

"$PYTHON" - <<'PY'
import json
import os

with open(os.environ["capture_path"], encoding="utf-8") as stream:
    payload = json.load(stream)

properties = payload["properties"]
assert payload["api_key"] == os.environ["posthog_key"]
assert properties["launch_client"] == os.environ["client"]
assert properties["host_client"] == os.environ["client"]
assert properties["client"] == os.environ["client"]
assert properties["plugin_version"] == os.environ["plugin_version"]
assert properties["ide_version"] == os.environ["ide_version"]
assert properties["first_start"] is True
assert properties["agent_installed"] is False
PY

cmp "$repo_root/scripts/monk-launcher-telemetry.sh" \
  "$repo_root/plugins/monk/scripts/monk-launcher-telemetry.sh"
cmp "$repo_root/scripts/monk-launcher-telemetry.sh" \
  "$repo_root/.antigravity-plugin/scripts/monk-launcher-telemetry.sh"

printf 'launcher_telemetry_json_status=pass\n'
