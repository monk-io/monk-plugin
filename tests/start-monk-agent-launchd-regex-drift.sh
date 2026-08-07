#!/usr/bin/env sh
# launchd config matching must compare literal values. Regex metacharacters in
# a requested URL (notably dots) must not make a different stored value appear
# equal and suppress the required companion restart.
set -eu

repo_root="${MONK_TEST_REPO_ROOT:-$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)}"
work_dir="$(mktemp -d)"
trap 'rm -rf "$work_dir"' EXIT HUP INT TERM

fake_bin="$work_dir/bin"
mkdir -p "$fake_bin"
for command_name in cat date dirname grep head id kill mkdir mktemp mv sed sh sleep tr; do
  command_path="$(command -v "$command_name" || true)"
  case "$command_path" in
    /*)
      printf '#!/usr/bin/sh\nexec "%s" "$@"\n' "$command_path" >"$fake_bin/$command_name"
      chmod +x "$fake_bin/$command_name"
      ;;
  esac
done

cat >"$fake_bin/uname" <<'EOF'
#!/usr/bin/sh
printf '%s\n' Darwin
EOF
cat >"$fake_bin/curl" <<'EOF'
#!/usr/bin/sh
printf '%s\n' '{"resource":"http://127.0.0.1:7419/mcp"}'
EOF
cat >"$fake_bin/launchctl" <<'EOF'
#!/usr/bin/sh
printf '%s\n' "$*" >>"$MONK_TEST_LAUNCHCTL_LOG"
EOF
chmod +x "$fake_bin/uname" "$fake_bin/curl" "$fake_bin/launchctl"

home_root="$work_dir"
case "$(uname -s 2>/dev/null || printf unknown)" in
  MINGW*|MSYS*|CYGWIN*) home_root="$(cygpath -m "$work_dir")" ;;
esac
home="$home_root/home"
plist="$home/Library/LaunchAgents/io.monk.agent.plist"
launchctl_log="$home_root/launchctl.log"
mkdir -p "$(dirname "$plist")"

# The requested default is https://auth.monk.io. This stored value is
# different, but the current unescaped grep pattern treats each dot as a
# wildcard and therefore matches it.
cat >"$plist" <<'EOF'
<plist><dict>
<string>/usr/bin/true</string>
<string>UW84YWcJME3buMSLfqLX8IbBsYdNWi47</string>
<string>https://auth-monk-io</string>
<string>oaknode.com</string>
<string>wss://api.app.monk.io/autospin/</string>
<string></string>
<string>0.1.54</string>
</dict></plist>
EOF

HOME="$home" \
PATH="$fake_bin" \
MONK_AGENT_PATH=/usr/bin/true \
MONK_AGENT_HOME="$home/.monk" \
MONK_AGENT_SKIP_SIGNIN_NUDGE=1 \
MONK_DISABLE_ANALYTICS=1 \
MONK_PLUGIN_VERSION=0.1.54 \
MONK_TEST_LAUNCHCTL_LOG="$launchctl_log" \
  /usr/bin/sh "$repo_root/scripts/start-monk-agent.sh"

if [ ! -s "$launchctl_log" ]; then
  echo "launchd fast path falsely accepted a different stored auth URL" >&2
  exit 1
fi

echo "launchd fast path detects literal auth URL drift."
