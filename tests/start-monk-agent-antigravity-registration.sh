#!/usr/bin/env sh
set -eu

repo="${MONK_TEST_REPO_ROOT:-"$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)"}"
expect="${MONK_TEST_EXPECT:-patched}"
launchers="
scripts/start-monk-agent.sh
plugins/monk/scripts/start-monk-agent.sh
.antigravity-plugin/scripts/start-monk-agent.sh
"

root="$(mktemp -d)"
cleanup() {
  rm -rf "$root"
}
trap cleanup EXIT HUP INT TERM

make_bin() {
  mode="$1"
  bin="$root/bin-$mode"
  mkdir -p "$bin"

  for name in dirname grep mkdir mktemp mv sh; do
    source_path="$(command -v "$name")"
    [ -n "$source_path" ]
    ln -s "$source_path" "$bin/$name"
  done

  case "$mode" in
    jq)
      source_path="$(command -v jq)"
      [ -n "$source_path" ]
      ln -s "$source_path" "$bin/jq"
      ;;
    python)
      source_path="$(command -v python3)"
      [ -n "$source_path" ]
      ln -s "$source_path" "$bin/python3"
      ;;
  esac

  cat >"$bin/uname" <<'EOF'
#!/usr/bin/env sh
printf '%s\n' Linux
EOF
  cat >"$bin/curl" <<'EOF'
#!/usr/bin/env sh
printf '%s\n' '{"resource":"http://127.0.0.1:17419"}'
EOF
  cat >"$bin/monk-agent" <<'EOF'
#!/usr/bin/env sh
exit 0
EOF
  chmod +x "$bin/uname" "$bin/curl" "$bin/monk-agent"
}

run_case() {
  rel="$1"
  mode="$2"
  fixture="$3"
  case_name="$(printf '%s-%s-%s' "$rel" "$mode" "$fixture" | tr '/.' '__')"
  case_root="$root/$case_name"
  home="$case_root/home"
  config_dir="$home/.gemini/config"
  config="$config_dir/mcp_config.json"
  before="$case_root/before.json"
  bin="$root/bin-$mode"
  mkdir -p "$config_dir"

  case "$fixture" in
    unrelated)
      printf '%s\n' '{"displayName":"monk","metadata":{"monk":"unrelated"},"mcpServers":{"other":{"serverUrl":"http://other.invalid/mcp"}}}' >"$config"
      ;;
    existing)
      printf '%s\n' '{"displayName":"monk","mcpServers":{"monk":{"serverUrl":"http://existing.invalid/mcp","extra":true},"other":{"serverUrl":"http://other.invalid/mcp"}}}' >"$config"
      cp "$config" "$before"
      ;;
    missing)
      rm -f "$config"
      ;;
  esac

  set +e
  PATH="$bin" \
  HOME="$home" \
  TMPDIR="$case_root" \
  MONK_AGENT_HOME="$home/.monk" \
  MONK_AGENT_HOST=127.0.0.1 \
  MONK_AGENT_PORT=17419 \
  MONK_AGENT_PATH="$bin/monk-agent" \
  MONK_AGENT_SKIP_SIGNIN_NUDGE=1 \
    "$repo/$rel" >"$case_root/stdout" 2>"$case_root/stderr"
  status=$?
  set -e
  test "$status" -eq 0

  python3 - "$config" "$fixture" "$expect" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as handle:
    config = json.load(handle)

fixture = sys.argv[2]
expect = sys.argv[3]
servers = config.get("mcpServers", {})

if fixture == "unrelated":
    assert config["displayName"] == "monk"
    assert config["metadata"] == {"monk": "unrelated"}
    assert servers["other"] == {"serverUrl": "http://other.invalid/mcp"}
    if expect == "patched":
        assert servers["monk"] == {"serverUrl": "http://127.0.0.1:17419/mcp"}
    else:
        assert "monk" not in servers
elif fixture == "missing":
    assert servers["monk"] == {"serverUrl": "http://127.0.0.1:17419/mcp"}
else:
    assert servers["monk"] == {
        "serverUrl": "http://existing.invalid/mcp",
        "extra": True,
    }
PY

  if [ "$fixture" = "existing" ]; then
    cmp "$before" "$config"
  fi
}

make_bin jq
make_bin python

for rel in $launchers; do
  for mode in jq python; do
    run_case "$rel" "$mode" unrelated
    run_case "$rel" "$mode" existing
    run_case "$rel" "$mode" missing
  done
done

if [ "$expect" = "patched" ]; then
  cmp "$repo/scripts/start-monk-agent.sh" \
    "$repo/plugins/monk/scripts/start-monk-agent.sh"
  cmp "$repo/scripts/start-monk-agent.sh" \
    "$repo/.antigravity-plugin/scripts/start-monk-agent.sh"
fi

printf 'Antigravity structured-registration regression passed (%s)\n' "$expect"
