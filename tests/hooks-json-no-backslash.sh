#!/usr/bin/env sh
# Regression coverage for plugin#466: Antigravity hooks.json must not contain
# literal Windows backslashes in command strings, because POSIX /bin/sh consumes
# them as escape characters and breaks the path.
set -eu

repo_root="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
hook_json="$repo_root/.antigravity-plugin/hooks.json"

if [ ! -f "$hook_json" ]; then
  echo "hooks.json not found: $hook_json" >&2
  exit 1
fi

if grep -F '\\' "$hook_json" >/dev/null 2>&1; then
  echo "found unescaped backslash in $hook_json" >&2
  exit 1
fi

echo "hooks.json contains no unescaped Windows backslashes."
