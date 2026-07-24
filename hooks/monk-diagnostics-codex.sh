#!/usr/bin/env sh
# Codex-only wrapper around monk-diagnostics.sh that hardcodes `--format codex`.
#
# codexHooksConfig()'s PostToolUse command must stay a single bare
# `$PLUGIN_ROOT`-relative path with no inline CLI arguments — whether Codex's
# hook-command tokenizer preserves a quoted, multi-word argument (needed to
# pass `--format codex` directly) is unconfirmed, while a single unquoted path
# is unambiguous under any reasonable tokenizer. See `codexPosixHook()` in
# plugin/src/metadata.ts.

set -eu
script_dir="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
exec "$script_dir/monk-diagnostics.sh" --format codex
