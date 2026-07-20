#!/usr/bin/env sh
set -eu

repo_root="${MONK_TEST_REPO_ROOT:-"$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)"}"
[ -x "$repo_root/scripts/start-monk-agent.sh" ]
cmp -s \
  "$repo_root/scripts/start-monk-agent.sh" \
  "$repo_root/plugins/monk/scripts/start-monk-agent.sh"
cmp -s \
  "$repo_root/scripts/start-monk-agent.sh" \
  "$repo_root/.antigravity-plugin/scripts/start-monk-agent.sh"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT HUP INT TERM

home="$tmp/O'Connor"
fake_bin="$tmp/bin"
install_dir="$tmp/install"
config="$home/.gemini/config/mcp_config.json"
mkdir -p "$(dirname -- "$config")" "$fake_bin" "$install_dir"

printf '%s\n' \
  '{"existing":{"owner":"O'"'"'Connor"},"mcpServers":{"other":{"serverUrl":"http://other.invalid/mcp"}}}' \
  >"$config"

for name in dirname grep mkdir mktemp mv python3 sh; do
  source_path="$(command -v "$name")"
  [ -n "$source_path" ]
  ln -s "$source_path" "$fake_bin/$name"
done

cat >"$fake_bin/uname" <<'EOF'
#!/usr/bin/env sh
printf '%s\n' Linux
EOF

cat >"$fake_bin/curl" <<'EOF'
#!/usr/bin/env sh
printf '%s\n' '{"resource":"http://127.0.0.1:17419/mcp"}'
EOF

cat >"$install_dir/monk-agent" <<'EOF'
#!/usr/bin/env sh
exit 0
EOF

chmod +x "$fake_bin/uname" "$fake_bin/curl" "$install_dir/monk-agent"

if PATH="$fake_bin" command -v jq >/dev/null 2>&1; then
  echo "test fixture unexpectedly exposes jq" >&2
  exit 1
fi

PATH="$fake_bin" \
HOME="$home" \
TMPDIR="$tmp" \
MONK_AGENT_HOME="$home/.monk" \
MONK_AGENT_HOST=127.0.0.1 \
MONK_AGENT_PORT=17419 \
MONK_AGENT_INSTALL_DIR="$install_dir" \
MONK_AGENT_PATH="$install_dir/monk-agent" \
MONK_AGENT_SKIP_SIGNIN_NUDGE=1 \
  "$repo_root/scripts/start-monk-agent.sh"

"$fake_bin/python3" - "$config" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as handle:
    config = json.load(handle)

assert config["existing"] == {"owner": "O'Connor"}
assert config["mcpServers"]["other"] == {
    "serverUrl": "http://other.invalid/mcp"
}
assert config["mcpServers"]["monk"] == {
    "serverUrl": "http://127.0.0.1:17419/mcp"
}
PY

printf '%s\n' \
  "antigravity_python_fallback=ok apostrophe_path=ok existing_json=preserved server_url=exact"
