#!/usr/bin/env sh
set -eu

repo="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
root="$(mktemp -d)"
trap 'rm -rf "$root"' EXIT HUP INT TERM

mkdir -p "$root/bin" "$root/home/.gemini/config" "$root/install"

cat >"$root/bin/uname" <<'EOF'
#!/usr/bin/env sh
printf '%s\n' Linux
EOF

cat >"$root/bin/curl" <<'EOF'
#!/usr/bin/env sh
set -eu
url=""
for arg in "$@"; do
  case "$arg" in
    http://*) url="$arg" ;;
  esac
done
printf '%s\n' "$url" >>"$TEST_URL_LOG"
if [ "$url" = 'http://[::1]:17419/.well-known/oauth-protected-resource' ]; then
  printf '%s\n' '{"resource":"http://[::1]:17419/mcp"}'
elif [ "$url" = 'http://[::1]:17419/auth.json' ]; then
  printf '%s\n' '{"signedIn":false}'
elif [ "$url" = 'http://[::1]:17419/plugin/nudge?type=signin&client=codex' ]; then
  printf '%s\n' '{}'
else
  printf 'unexpected URL: %s\n' "$url" >&2
  exit 22
fi
EOF

cat >"$root/install/monk-agent" <<'EOF'
#!/usr/bin/env sh
exit 0
EOF

chmod +x "$root/bin/uname" "$root/bin/curl" "$root/install/monk-agent"

PATH="$root/bin:$PATH" \
HOME="$root/home" \
MONK_AGENT_HOME="$root/home/.monk" \
MONK_AGENT_INSTALL_DIR="$root/install" \
MONK_AGENT_PATH="$root/install/monk-agent" \
MONK_AGENT_SKIP_ENSURE=1 \
MONK_AGENT_HOST='::1' \
MONK_AGENT_PORT=17419 \
PLUGIN_ROOT="$repo" \
TEST_URL_LOG="$root/urls" \
  "$repo/scripts/start-monk-agent.sh" >/dev/null

grep -Fx 'http://[::1]:17419/.well-known/oauth-protected-resource' "$root/urls"
grep -Fx 'http://[::1]:17419/auth.json' "$root/urls"
grep -Fx 'http://[::1]:17419/plugin/nudge?type=signin&client=codex' "$root/urls"
if grep -F 'http://::1:' "$root/urls"; then
  echo "launcher emitted an unbracketed IPv6 URL" >&2
  exit 1
fi

jq -e '.mcpServers.monk.serverUrl == "http://[::1]:17419/mcp"' \
  "$root/home/.gemini/config/mcp_config.json" >/dev/null

PATH="$root/bin:$PATH" \
HOME="$root/home" \
MONK_AGENT_PATH="$root/install/monk-agent" \
MONK_AGENT_HOST='::1' \
MONK_AGENT_PORT=17419 \
TEST_URL_LOG="$root/hook-urls" \
  "$repo/.antigravity-plugin/hooks/ensure-monk-agent.sh" >/dev/null

grep -Fx 'http://[::1]:17419/.well-known/oauth-protected-resource' "$root/hook-urls"

cmp "$repo/scripts/start-monk-agent.sh" "$repo/plugins/monk/scripts/start-monk-agent.sh"
cmp "$repo/scripts/start-monk-agent.sh" "$repo/.antigravity-plugin/scripts/start-monk-agent.sh"
cmp "$repo/scripts/start-monk-agent.ps1" "$repo/plugins/monk/scripts/start-monk-agent.ps1"
cmp "$repo/scripts/start-monk-agent.ps1" "$repo/.antigravity-plugin/scripts/start-monk-agent.ps1"
