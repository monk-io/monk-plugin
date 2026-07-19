#!/usr/bin/env sh
set -eu

repo_root="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT HUP INT TERM

home="$tmp/home & <monk>"
stub_bin="$tmp/bin"
install_dir="$tmp/install & <monk>"
agent_path="$install_dir/monk-agent"
mkdir -p "$home" "$stub_bin" "$install_dir"

cat >"$stub_bin/uname" <<'EOF'
#!/usr/bin/env sh
printf 'Darwin\n'
EOF

cat >"$stub_bin/launchctl" <<'EOF'
#!/usr/bin/env sh
printf '%s\n' "$*" >>"$HOME/.launchctl-calls"
if [ "${1:-}" = "bootstrap" ]; then
  : >"$HOME/.monk-agent-ready"
fi
EOF

cat >"$stub_bin/curl" <<'EOF'
#!/usr/bin/env sh
[ -f "$HOME/.monk-agent-ready" ] || exit 1
printf '{"resource":"test"}\n'
EOF

cat >"$stub_bin/sleep" <<'EOF'
#!/usr/bin/env sh
exit 0
EOF

cat >"$agent_path" <<'EOF'
#!/usr/bin/env sh
exit 0
EOF
chmod +x "$stub_bin/uname" "$stub_bin/launchctl" "$stub_bin/curl" \
  "$stub_bin/sleep" "$agent_path"

auth_url="https://auth.example.test/oauth?client=one&redirect=<callback>"
auth_client_id="client&<id>\"'"
auth_audience="audience&<prod>\"'"
autospin_url="wss://example.test/socket?one=1&two=<2>"
agent_local="local&<value>\"'"

HOME="$home" \
PATH="$stub_bin:$PATH" \
MONK_AGENT_PATH="$agent_path" \
MONK_AGENT_INSTALL_DIR="$install_dir" \
MONK_AGENT_SKIP_ENSURE=1 \
MONK_AGENT_SKIP_SIGNIN_NUDGE=1 \
MONK_AUTH_URL="$auth_url" \
MONK_AGENT_AUTH_CLIENT_ID="$auth_client_id" \
MONK_AUTH_AUDIENCE="$auth_audience" \
MONK_AUTOSPIN_URL="$autospin_url" \
MONK_AGENT_LOCAL="$agent_local" \
  "$repo_root/scripts/start-monk-agent.sh"

rm -f "$home/.launchctl-calls"
HOME="$home" \
PATH="$stub_bin:$PATH" \
MONK_AGENT_PATH="$agent_path" \
MONK_AGENT_INSTALL_DIR="$install_dir" \
MONK_AGENT_SKIP_SIGNIN_NUDGE=1 \
MONK_AUTH_URL="$auth_url" \
MONK_AGENT_AUTH_CLIENT_ID="$auth_client_id" \
MONK_AUTH_AUDIENCE="$auth_audience" \
MONK_AUTOSPIN_URL="$autospin_url" \
MONK_AGENT_LOCAL="$agent_local" \
  "$repo_root/scripts/start-monk-agent.sh"

[ ! -s "$home/.launchctl-calls" ] || {
  echo "unchanged escaped launchd configuration triggered a restart" >&2
  exit 1
}

plist="$home/Library/LaunchAgents/io.monk.agent.plist"
python3 - "$plist" "$agent_path" "$auth_url" "$auth_client_id" \
  "$auth_audience" "$autospin_url" "$agent_local" <<'PY'
import plistlib
import sys

plist_path, agent_path, auth_url, client_id, audience, autospin_url, agent_local = sys.argv[1:]
with open(plist_path, "rb") as plist_file:
    data = plistlib.load(plist_file)

assert data["ProgramArguments"][0] == agent_path
environment = data["EnvironmentVariables"]
assert environment["MONK_AUTH_URL"] == auth_url
assert environment["MONK_AGENT_AUTH_CLIENT_ID"] == client_id
assert environment["MONK_AUTH_AUDIENCE"] == audience
assert environment["MONK_AUTOSPIN_URL"] == autospin_url
assert environment["MONK_AGENT_LOCAL"] == agent_local
assert data["StandardOutPath"] == data["StandardErrorPath"]
assert "home & <monk>" in data["StandardOutPath"]
PY

printf 'launchd plist XML escaping: ok\n'
