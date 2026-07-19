#!/usr/bin/env sh
# PreToolUse hook for the run_command tool: block any shell-out to the `monk` CLI.
# Monk owns its own cluster state — running `monk ...` from a shell desyncs it.
# Use monk-agent MCP tools instead.
#
# Antigravity PreToolUse I/O:
#   stdin:  {"toolCall":{"name":"run_command","args":{"CommandLine":"..."}},...}
#   stdout: {"decision":"deny","reason":"..."} to block, or exit 0 to allow
#
# The decision is made by `monk-agent hook block-monk` so the only dependency is
# the monk-agent binary the plugin already installs. If that binary is missing we
# fall back to pure POSIX shell + grep, biased toward BLOCKING. The hook always
# exits 0 (the deny JSON is the block signal).

set -eu

input="$(cat)"

agent="${MONK_AGENT_PATH:-${MONK_AGENT_INSTALL_DIR:-"$HOME/.monk/bin"}/monk-agent}"
if [ -x "$agent" ]; then
  if printf '%s' "$input" | "$agent" hook block-monk --format antigravity; then
    exit 0
  fi
fi

# Fallback: binary unavailable. Normalize common JSON/shell quoting first, then
# look only at command starts or shell command separators. This catches
# `"monk"`, `'monk'`, and `\monk` without blocking harmless arguments like
# `grep monk README.md`.
fallback_input="$(printf '%s' "$input" | sed "s/\\\\\"/\"/g; s/\\\\\\\\//g; s/[\"']//g")"
if printf '%s' "$fallback_input" | grep -Eq '(^|CommandLine:[[:space:]]*|command:[[:space:]]*|[;&|`(][[:space:]]*)(sudo[[:space:]]+)?monk([[:space:];&|`)}]|$)'; then
  cat <<'JSON'
{
  "decision": "deny",
  "reason": "Blocked: do not shell out to the `monk` CLI — it desyncs the cluster state Monk manages. Use the monk-agent MCP tools instead."
}
JSON
  exit 0
fi

exit 0
