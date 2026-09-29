#!/usr/bin/env sh
# launchd config matching must compare literal values. Regex metacharacters in
# a requested URL (notably dots) must not make a different stored value appear
# equal and suppress the required companion restart.
#
# Ported from the community PR for ENG-538 (monk-io/monk-plugin#268,
# monk-io/monk-plugin#256): launchd_configured() interpolated the requested
# value directly into a `grep` BRE pattern instead of comparing it literally
# (grep -Fq), so the default auth URL's dots acted as wildcards and matched an
# unrelated stored value, letting the fast path wrongly reuse a companion with
# drifted auth configuration.
set -eu

repo_root="${MONK_TEST_REPO_ROOT:-$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)}"
work_dir="$(mktemp -d)"
trap 'rm -rf "$work_dir"' EXIT HUP INT TERM

fake_bin="$work_dir/bin"
mkdir -p "$fake_bin"

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

# start-monk-agent.sh unconditionally sources scripts/plugin-version.sh (when
# present) and overwrites MONK_PLUGIN_VERSION with the real rendered version,
# regardless of what's passed in the environment -- so the stored plist value
# for that field must match whatever this build actually renders, or an
# unrelated plugin-version mismatch would mask the one thing this test is
# actually isolating (the auth_url comparison).
plugin_version="$(
  if [ -f "$repo_root/scripts/plugin-version.sh" ]; then
    # shellcheck disable=SC1090
    . "$repo_root/scripts/plugin-version.sh"
    printf '%s' "$MONK_PLUGIN_VERSION"
  fi
)"

# The requested default is https://auth.monk.io. This stored value is
# different, but the current unescaped grep pattern treats each dot as a
# wildcard and therefore matches it.
{
  printf '<plist><dict>\n'
  printf '<string>/usr/bin/true</string>\n'
  printf '<string>UW84YWcJME3buMSLfqLX8IbBsYdNWi47</string>\n'
  printf '<string>https://auth-monk-io</string>\n'
  printf '<string>oaknode.com</string>\n'
  printf '<string>wss://api.app.monk.io/autospin/</string>\n'
  printf '<string></string>\n'
  printf '<string>%s</string>\n' "$plugin_version"
  printf '<integer>8192</integer>\n'
  printf '</dict></plist>\n'
} >"$plist"

HOME="$home" \
PATH="$fake_bin:/usr/bin:/bin" \
MONK_AGENT_PATH=/usr/bin/true \
MONK_AGENT_HOME="$home/.monk" \
MONK_AGENT_SKIP_SIGNIN_NUDGE=1 \
MONK_DISABLE_ANALYTICS=1 \
MONK_TEST_LAUNCHCTL_LOG="$launchctl_log" \
  sh "$repo_root/scripts/start-monk-agent.sh"

if [ ! -s "$launchctl_log" ]; then
  echo "launchd fast path falsely accepted a different stored auth URL" >&2
  exit 1
fi

echo "launchd fast path detects literal auth URL drift."
