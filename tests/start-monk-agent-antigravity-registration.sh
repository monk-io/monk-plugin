#!/usr/bin/env sh
set -eu

repo_root="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
tmp_root="$(mktemp -d)"
cleanup() {
  rm -rf "$tmp_root"
}
trap cleanup EXIT INT TERM

fake_bin="$tmp_root/bin"
home_dir="$tmp_root/home"
install_dir="$tmp_root/install"
monk_home="$tmp_root/monk-home"
config_dir="$home_dir/.gemini/config"
mkdir -p "$fake_bin" "$install_dir" "$monk_home" "$config_dir"

cat >"$fake_bin/curl" <<'SH'
#!/usr/bin/env sh
case "$*" in
  *'.well-known/oauth-protected-resource'*)
    printf '{"resource":"http://127.0.0.1:7419/mcp"}\n'
    ;;
  *)
    printf '{}\n'
    ;;
esac
SH
chmod +x "$fake_bin/curl"

cat >"$fake_bin/uname" <<'SH'
#!/usr/bin/env sh
printf 'Linux\n'
SH
chmod +x "$fake_bin/uname"

cat >"$fake_bin/jq" <<'SH'
#!/usr/bin/env sh
if [ "$1" = "-e" ]; then
  cfg_path="$3"
  [ -n "$cfg_path" ] || exit 1
  [ -e "$cfg_path" ] || exit 1
  if command -v cygpath >/dev/null 2>&1; then
    cfg_path="$(cygpath -w "$cfg_path")"
  fi
  python - "$cfg_path" <<'PY'
import json
import sys

path = sys.argv[1]
try:
    with open(path, encoding="utf-8") as fh:
        cfg = json.load(fh)
except Exception:
    sys.exit(1)
servers = cfg.get("mcpServers") if isinstance(cfg, dict) else None
sys.exit(0 if isinstance(servers, dict) and "monk" in servers else 1)
PY
  exit $?
fi

if [ "$1" = "--arg" ] && [ "$2" = "u" ]; then
  server_url="$3"
  expression="$4"
  if [ "$expression" = ".mcpServers.monk = {serverUrl: \$u}" ]; then
    cfg_path="$5"
    if command -v cygpath >/dev/null 2>&1; then
      cfg_path="$(cygpath -w "$cfg_path")"
    fi
    python - "$server_url" "$cfg_path" <<'PY'
import json
import sys

server_url, path = sys.argv[1], sys.argv[2]
with open(path, encoding="utf-8") as fh:
    cfg = json.load(fh)
servers = cfg.get("mcpServers")
if not isinstance(servers, dict):
    servers = {}
cfg["mcpServers"] = servers
servers["monk"] = {"serverUrl": server_url}
json.dump(cfg, sys.stdout, indent=2)
print()
PY
    exit $?
  fi
fi

if [ "$1" = "-n" ] && [ "$2" = "--arg" ] && [ "$3" = "u" ]; then
  server_url="$4"
  python - "$server_url" <<'PY'
import json
import sys

json.dump({"mcpServers": {"monk": {"serverUrl": sys.argv[1]}}}, sys.stdout)
print()
PY
  exit $?
fi

echo "unsupported fake jq invocation: $*" >&2
exit 2
SH
chmod +x "$fake_bin/jq"

cat >"$fake_bin/python3" <<'SH'
#!/usr/bin/env sh
if command -v cygpath >/dev/null 2>&1; then
  case "$#" in
    2)
      if [ "$2" != "-" ] && [ -e "$2" ]; then
        exec python "$1" "$(cygpath -w "$2")"
      fi
      ;;
    3)
      if [ "$3" != "-" ] && [ -e "$3" ]; then
        exec python "$1" "$2" "$(cygpath -w "$3")"
      fi
      ;;
  esac
fi
exec python "$@"
SH
chmod +x "$fake_bin/python3"

cat >"$install_dir/monk-agent" <<'SH'
#!/usr/bin/env sh
exit 0
SH
chmod +x "$install_dir/monk-agent"

cat >"$config_dir/mcp_config.json" <<'JSON'
{
  "preferences": {
    "notes": "monk"
  },
  "mcpServers": {
    "existing": {
      "serverUrl": "http://127.0.0.1:9000/mcp"
    }
  }
}
JSON

PATH="$fake_bin:$PATH" \
HOME="$home_dir" \
MONK_AGENT_INSTALL_DIR="$install_dir" \
MONK_AGENT_PATH="$install_dir/monk-agent" \
MONK_AGENT_HOME="$monk_home" \
MONK_AGENT_SKIP_SIGNIN_NUDGE=1 \
PLUGIN_ROOT="$repo_root/.antigravity-plugin" \
"$repo_root/scripts/start-monk-agent.sh" >/dev/null

PATH="$fake_bin:$PATH" python3 - "$config_dir/mcp_config.json" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as fh:
    cfg = json.load(fh)

assert cfg["preferences"]["notes"] == "monk"
assert cfg["mcpServers"]["existing"]["serverUrl"] == "http://127.0.0.1:9000/mcp"
assert cfg["mcpServers"]["monk"]["serverUrl"] == "http://127.0.0.1:7419/mcp"
PY

before_second_run="$(PATH="$fake_bin:$PATH" python3 - "$config_dir/mcp_config.json" <<'PY'
import pathlib
import sys

print(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"))
PY
)"

PATH="$fake_bin:$PATH" \
HOME="$home_dir" \
MONK_AGENT_INSTALL_DIR="$install_dir" \
MONK_AGENT_PATH="$install_dir/monk-agent" \
MONK_AGENT_HOME="$monk_home" \
MONK_AGENT_SKIP_SIGNIN_NUDGE=1 \
PLUGIN_ROOT="$repo_root/.antigravity-plugin" \
"$repo_root/scripts/start-monk-agent.sh" >/dev/null

after_second_run="$(PATH="$fake_bin:$PATH" python3 - "$config_dir/mcp_config.json" <<'PY'
import pathlib
import sys

print(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"))
PY
)"

if [ "$before_second_run" != "$after_second_run" ]; then
  echo "expected existing monk registration to be idempotent" >&2
  exit 1
fi

echo "Antigravity MCP structured registration test passed."
