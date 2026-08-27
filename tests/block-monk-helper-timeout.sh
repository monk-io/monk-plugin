#!/usr/bin/env sh
# A wedged monk-agent hook helper must not consume the host's PreToolUse budget.
# Both Claude/Codex and Antigravity POSIX wrappers must fall back and deny monk.
set -eu
repo_root="${1:-$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)}"
work_dir="$(mktemp -d)"
cleanup() { rm -rf "$work_dir"; }
trap cleanup EXIT HUP INT TERM

cat >"$work_dir/hang-agent" <<'AGENT'
#!/usr/bin/env sh
exec sleep 30
AGENT
chmod +x "$work_dir/hang-agent"

cat >"$work_dir/success-agent" <<'AGENT'
#!/usr/bin/env sh
cat >/dev/null
case "$*" in
  *antigravity*) printf '%s\n' '{"decision":"deny","reason":"helper decision"}' ;;
  *) printf '%s\n' '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"helper decision"}}' ;;
esac
AGENT
chmod +x "$work_dir/success-agent"

run_variant() {
  name="$1"
  hook="$2"
  payload="$3"
  deny_pattern="$4"

  printf '%s' "$payload" |
    MONK_AGENT_PATH="$work_dir/hang-agent" \
    MONK_BLOCK_MONK_HELPER_TIMEOUT=1 \
    "$hook" >"$work_dir/$name-hang.out" 2>"$work_dir/$name-hang.err" &
  hook_pid=$!

  finished=0
  for _ in 1 2 3; do
    if ! kill -0 "$hook_pid" 2>/dev/null; then
      finished=1
      break
    fi
    sleep 1
  done
  if [ "$finished" -ne 1 ]; then
    kill "$hook_pid" 2>/dev/null || true
    wait "$hook_pid" 2>/dev/null || true
    echo "$name block-monk hook outlived its helper timeout" >&2
    exit 1
  fi
  wait "$hook_pid"
  grep -q "$deny_pattern" "$work_dir/$name-hang.out"

  printf '%s' "$payload" |
    MONK_AGENT_PATH="$work_dir/success-agent" \
    "$hook" >"$work_dir/$name-success.out" 2>"$work_dir/$name-success.err"
  grep -q 'helper decision' "$work_dir/$name-success.out"
}

run_variant claude \
  "$repo_root/hooks/block-monk.sh" \
  '{"tool_name":"Bash","tool_input":{"command":"monk status"}}' \
  '"permissionDecision": "deny"'

run_variant antigravity \
  "$repo_root/.antigravity-plugin/hooks/block-monk.sh" \
  '{"toolCall":{"name":"run_command","args":{"CommandLine":"monk status"}}}' \
  '"decision": "deny"'

cmp "$repo_root/hooks/block-monk.sh" "$repo_root/plugins/monk/hooks/block-monk.sh"
printf 'block_monk_helper_timeout=pass variants=2\n'
