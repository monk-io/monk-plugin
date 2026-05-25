#!/usr/bin/env bash
# PreToolUse hook for the Bash tool: block any shell-out to the `monk` CLI.
# Monk owns its own cluster state — running `monk ...` from a shell desyncs it.
# Use monk-agent MCP tools instead.

set -euo pipefail

input="$(cat)"
command="$(printf '%s' "$input" | jq -r '.tool_input.command // ""')"

# Match `monk` only in *command position*:
#   - at start of line, or after a shell separator (`;`, `&&`, `||`, `|`, `(`, backtick)
#   - optional leading whitespace, optional `sudo `
#   - followed by whitespace or end-of-string (so `monkey` doesn't match)
# Blocked:  `monk run`, `  monk status`, `cd /tmp && monk ps`, `sudo monk deploy`
# Allowed:  `monkey patch`, `echo monk`, `grep monk file`, `ls`
if printf '%s' "$command" | grep -Eq '(^|[;&|`(])[[:space:]]*(sudo[[:space:]]+)?monk([[:space:]]|$)'; then
  jq -n '{
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "deny",
      permissionDecisionReason: "Blocked: do not shell out to the `monk` CLI — it desyncs the cluster state Monk manages. Use the monk-agent MCP tools instead."
    }
  }'
  exit 0
fi

exit 0
