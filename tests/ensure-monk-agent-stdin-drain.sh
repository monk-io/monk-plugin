#!/usr/bin/env sh
# Regression coverage for plugin#408: Antigravity ensure-monk-agent.sh must
# drain stdin so the PreInvocation hook does not block Antigravity's writer.
set -eu

repo_root="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
hook="$repo_root/.antigravity-plugin/hooks/ensure-monk-agent.sh"

if [ ! -f "$hook" ]; then
  echo "Hook not found: $hook" >&2
  exit 1
fi

# Pipe a realistic Antigravity payload into the hook in the background and
# bound the wait. A missing monk-agent causes the hook to emit a JSON
# injectSteps message and exit; the regression is that it must not hang
# waiting for stdin.
work_dir="$(mktemp -d)"
trap 'rm -rf "$work_dir"; kill "$hook_pid" 2>/dev/null || true' EXIT HUP INT TERM

printf '%s' '{"invocationNum":1,"initialNumSteps":5,"workspacePaths":["/tmp"]}' >"$work_dir/stdin"
sh "$hook" <"$work_dir/stdin" >"$work_dir/stdout" 2>/dev/null &
hook_pid=$!

# Wait up to 5 seconds.
waited=0
while [ "$waited" -lt 5 ]; do
  if ! kill -0 "$hook_pid" 2>/dev/null; then
    break
  fi
  sleep 1
  waited=$((waited + 1))
done

if kill -0 "$hook_pid" 2>/dev/null; then
  echo "ensure-monk-agent.sh did not drain stdin within 5s" >&2
  exit 1
fi

# It should produce either an injectSteps payload or empty output.
output="$(cat "$work_dir/stdout" 2>/dev/null || true)"
case "$output" in
  *injectSteps*|'') ;;
  *)
    echo "Unexpected hook output: $output" >&2
    exit 1
    ;;
esac

echo "ensure-monk-agent.sh drains stdin without hanging."
