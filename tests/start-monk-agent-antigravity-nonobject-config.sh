#!/usr/bin/env sh
# A syntactically valid Antigravity config with a non-object root must be
# rejected as an incompatible config shape, not abort an otherwise healthy
# launcher while trying to access or assign mcpServers.
set -eu

repo_root="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
fixture_src="$repo_root/tests/fixtures/start-monk-agent"
work_dir="$(mktemp -d)"
trap 'rm -rf "$work_dir"' EXIT HUP INT TERM

if ! command -v python3 >/dev/null 2>&1; then
  echo "python3 not available; skipping non-object config regression" >&2
  exit 0
fi

fake_bin="$work_dir/bin"
mkdir -p "$fake_bin"
for command_name in cat date dirname grep head id kill mkdir mktemp mv python3 sed sh tr; do
  command_path="$(command -v "$command_name" || true)"
  case "$command_path" in
    /*)
      printf '#!/usr/bin/sh\nexec "%s" "$@"\n' "$command_path" >"$fake_bin/$command_name"
      chmod +x "$fake_bin/$command_name"
      ;;
  esac
done
for fixture_name in curl uname; do
  printf '#!/usr/bin/sh\nexec "%s" "$@"\n' "$fixture_src/$fixture_name" >"$fake_bin/$fixture_name"
  chmod +x "$fake_bin/$fixture_name"
done

home_root="$work_dir"
case "$(uname -s 2>/dev/null || printf unknown)" in
  MINGW*|MSYS*|CYGWIN*) home_root="$(cygpath -m "$work_dir")" ;;
esac
home="$home_root/home"
config="$home/.gemini/config/mcp_config.json"
mkdir -p "$(dirname "$config")"
printf '%s\n' '[{"preserved":"still here"}]' >"$config"

HOME="$home" \
PATH="$fake_bin" \
MONK_AGENT_HOME="$home/.monk" \
MONK_AGENT_PATH=/usr/bin/true \
MONK_AGENT_SKIP_SIGNIN_NUDGE=1 \
  /usr/bin/sh "$repo_root/scripts/start-monk-agent.sh"

python3 -c '
import json, sys
with open(sys.argv[1], encoding="utf-8") as handle:
    config = json.load(handle)
assert config == [{"preserved": "still here"}]
' "$config"

echo "Antigravity launcher preserves and skips a non-object JSON config."
