#!/usr/bin/env sh
# Regression coverage for plugin#472: Antigravity ensure-monk-agent.sh must
# invoke the managed bootstrap script on cold start so plugin upgrades refresh
# monk-agent automatically.
set -eu

repo_root="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
hook="$repo_root/.antigravity-plugin/hooks/ensure-monk-agent.sh"
bootstrap="$repo_root/.antigravity-plugin/scripts/ensure-monk-agent.sh"

if [ ! -f "$hook" ]; then
  echo "Hook not found: $hook" >&2
  exit 1
fi

if [ ! -x "$bootstrap" ]; then
  echo "Bootstrap script not found: $bootstrap" >&2
  exit 1
fi

# The hook must reference the managed bootstrap script and invoke it before
# falling back to the on-disk binary path.
if ! grep -q 'scripts/ensure-monk-agent.sh' "$hook"; then
  echo "ensure-monk-agent.sh does not reference the managed bootstrap script" >&2
  exit 1
fi

if ! grep -q 'bootstrap_script=' "$hook"; then
  echo "ensure-monk-agent.sh does not invoke the managed bootstrap" >&2
  exit 1
fi

echo "ensure-monk-agent.sh wiring for managed bootstrap is correct."
