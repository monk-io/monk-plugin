#!/usr/bin/env sh
# Dynamic launchd values must be serialized as XML text. Valid paths and URLs
# containing XML metacharacters must round-trip through the generated plist.
set -eu

repo_root="${MONK_TEST_REPO_ROOT:-$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)}"
work_dir="$(mktemp -d)"
trap 'rm -rf "$work_dir"' EXIT HUP INT TERM

python_cmd="$(command -v python3 || command -v python || true)"
if [ -z "$python_cmd" ]; then
  echo "python is required to validate the generated plist" >&2
  exit 2
fi

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
exit 0
EOF
chmod +x "$fake_bin/uname" "$fake_bin/curl" "$fake_bin/launchctl"

home_root="$work_dir"
case "$(uname -s 2>/dev/null || printf unknown)" in
  MINGW*|MSYS*|CYGWIN*) home_root="$(cygpath -m "$work_dir")" ;;
esac
home="$home_root/home&fixture"
agent_path="$home_root/agent&fixture/monk-agent"
auth_url='https://auth.monk.io/oauth?tenant=a&mode=<test>'
agent_local="local<&>\"'"
plist="$home/Library/LaunchAgents/io.monk.agent.plist"
expected_log="$home/.monk/agent/launcher/logs/monk-agent.log"
mkdir -p "$(dirname "$agent_path")"
printf '#!/usr/bin/sh\nexit 0\n' >"$agent_path"
chmod +x "$agent_path"

HOME="$home" \
PATH="$fake_bin" \
MONK_AGENT_PATH="$agent_path" \
MONK_AGENT_HOME="$home/.monk" \
MONK_AUTH_URL="$auth_url" \
MONK_AGENT_LOCAL="$agent_local" \
MONK_AGENT_SKIP_SIGNIN_NUDGE=1 \
MONK_DISABLE_ANALYTICS=1 \
MONK_PLUGIN_VERSION=0.1.58 \
  /usr/bin/sh "$repo_root/scripts/start-monk-agent.sh"

"$python_cmd" - "$plist" "$agent_path" "$auth_url" "$agent_local" "$expected_log" <<'PY'
import plistlib
import sys

(
    plist_path,
    expected_agent_path,
    expected_auth_url,
    expected_agent_local,
    expected_log,
) = sys.argv[1:]
with open(plist_path, "rb") as handle:
    config = plistlib.load(handle)

assert config["ProgramArguments"][0] == expected_agent_path
assert config["EnvironmentVariables"]["MONK_AUTH_URL"] == expected_auth_url
assert config["EnvironmentVariables"]["MONK_AGENT_LOCAL"] == expected_agent_local
assert config["StandardOutPath"] == expected_log
assert config["StandardErrorPath"] == expected_log
PY

# XML serialization is launchd-only. Guard against accidentally paying for the
# escaping subprocesses on the Linux fast path by counting sed invocations.
cat >"$fake_bin/uname" <<'EOF'
#!/usr/bin/sh
printf '%s\n' Linux
EOF
real_sed="$(command -v sed)"
printf '#!/usr/bin/sh\nprintf "%%s\\n" "$*" >>"$MONK_TEST_SED_LOG"\nexec "%s" "$@"\n' \
  "$real_sed" >"$fake_bin/sed"
chmod +x "$fake_bin/uname" "$fake_bin/sed"

linux_home="$home_root/linux-home"
linux_run_dir="$linux_home/.monk/agent/launcher/run"
sed_log="$home_root/linux-sed.log"
mkdir -p "$linux_run_dir"
{
  printf 'agent_path=%s\n' "$agent_path"
  printf 'auth_url=%s\n' "$auth_url"
  printf 'auth_client_id=UW84YWcJME3buMSLfqLX8IbBsYdNWi47\n'
  printf 'auth_audience=oaknode.com\n'
  printf 'autospin_url=wss://api.app.monk.io/autospin/\n'
} >"$linux_run_dir/monk-agent.state"

HOME="$linux_home" \
PATH="$fake_bin" \
MONK_AGENT_PATH="$agent_path" \
MONK_AGENT_HOME="$linux_home/.monk" \
MONK_AUTH_URL="$auth_url" \
MONK_AGENT_SKIP_SIGNIN_NUDGE=1 \
MONK_DISABLE_ANALYTICS=1 \
MONK_PLUGIN_VERSION=0.1.58 \
MONK_TEST_SED_LOG="$sed_log" \
  /usr/bin/sh "$repo_root/scripts/start-monk-agent.sh"

sed_calls=0
while IFS= read -r _line; do
  sed_calls=$((sed_calls + 1))
done <"$sed_log"
if [ "$sed_calls" -ne 1 ]; then
  echo "Linux fast path ran $sed_calls sed commands; expected only the health parser" >&2
  exit 1
fi

echo "launchd plist values round-trip XML metacharacters."
