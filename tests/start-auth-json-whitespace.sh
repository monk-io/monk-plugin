#!/usr/bin/env sh
set -eu

repo="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
root="$(mktemp -d)"

cleanup() {
  if [ -d "$root" ]; then
    find "$root" -name monk-agent.pid -type f -exec sh -c '
      for pid_file do
        pid="$(cat "$pid_file" 2>/dev/null || true)"
        case "$pid" in
          ""|*[!0-9]*) ;;
          *) kill "$pid" 2>/dev/null || true ;;
        esac
      done
    ' sh {} +
    rm -rf "$root"
  fi
}
trap cleanup EXIT HUP INT TERM

write_fixtures() {
  mkdir -p "$root/bin" "$root/install"

  cat >"$root/install/monk-agent" <<'SH'
#!/usr/bin/env sh
sleep 60
SH
  chmod +x "$root/install/monk-agent"

  cat >"$root/bin/uname" <<'SH'
#!/usr/bin/env sh
printf Linux
SH
  chmod +x "$root/bin/uname"

  cat >"$root/bin/curl" <<'SH'
#!/usr/bin/env sh
url=""
for arg do
  url="$arg"
done

case "$url" in
  */.well-known/oauth-protected-resource)
    printf '{"resource":"http://127.0.0.1:%s/mcp"}\n' "${MONK_AGENT_PORT:-7419}"
    ;;
  */auth.json)
    printf '%s\n' "$TEST_AUTH_BODY"
    ;;
  */plugin/nudge*)
    printf '%s\n' "$url" > "$TEST_NUDGE_FILE"
    ;;
esac
SH
  chmod +x "$root/bin/curl"
}

run_case() {
  script="$1"
  auth_body="$2"
  expect_nudge="$3"

  case_dir="$root/case-$(basename "$(dirname "$script")")-$(basename "$script")-$$-$RANDOM"
  mkdir -p "$case_dir/home" "$case_dir/monk-home"
  nudge_file="$case_dir/nudge"
  output_file="$case_dir/out"

  TEST_AUTH_BODY="$auth_body" \
    TEST_NUDGE_FILE="$nudge_file" \
    LC_ALL=C \
    LANG=C \
    PATH="$root/bin:$PATH" \
    HOME="$case_dir/home" \
    MONK_AGENT_HOME="$case_dir/monk-home" \
    MONK_AGENT_INSTALL_DIR="$root/install" \
    MONK_AGENT_PORT=18741 \
    MONK_AGENT_SKIP_ENSURE=1 \
    sh "$script" >"$output_file"

  if [ "$expect_nudge" = "no" ]; then
    if [ -e "$nudge_file" ]; then
      echo "unexpected sign-in nudge for $script with auth body: $auth_body" >&2
      exit 1
    fi
    if grep -q "NOT signed in" "$output_file"; then
      echo "unexpected signed-out message for $script with auth body: $auth_body" >&2
      exit 1
    fi
  else
    if [ ! -e "$nudge_file" ]; then
      echo "missing sign-in nudge for $script with auth body: $auth_body" >&2
      exit 1
    fi
    if ! grep -q "NOT signed in" "$output_file"; then
      echo "missing signed-out message for $script with auth body: $auth_body" >&2
      exit 1
    fi
  fi
}

write_fixtures

for script in \
  "$repo/scripts/start-monk-agent.sh" \
  "$repo/plugins/monk/scripts/start-monk-agent.sh" \
  "$repo/.antigravity-plugin/scripts/start-monk-agent.sh"
do
  run_case "$script" '{"signedIn":true}' no
  run_case "$script" '{ "signedIn": true }' no
  run_case "$script" '{"signedIn":false}' yes
done

echo "auth.json signedIn whitespace handling is correct"
