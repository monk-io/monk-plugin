#!/usr/bin/env sh
# Antigravity-only wrapper around the shared monk-diagnostics.sh that hardcodes
# `--format antigravity`.
#
# antigravityHookCommand() in plugin/src/metadata.ts puts this script after the
# `||` of a cross-platform hook command. On Windows that tail can reach
# PowerShell as stray arguments, so it must carry no `-`-prefixed token that
# PowerShell would try to bind as a parameter.

set -eu
script_dir="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
exec "$script_dir/monk-diagnostics.sh" --format antigravity
