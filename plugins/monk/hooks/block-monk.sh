#!/usr/bin/env sh
# PreToolUse hook for the Bash tool: block any shell-out to the `monk` CLI.
# Monk owns its own cluster state — running `monk ...` from a shell desyncs it.
# Use monk-agent MCP tools instead.
#
# The decision is made by `monk-agent hook block-monk` so the only dependency is
# the monk-agent binary the plugin already installs. If that binary is somehow
# missing we fall back to pure POSIX shell + grep, biased toward BLOCKING: a
# `monk` invocation is still caught with zero tooling, and non-monk commands are
# never blocked. The hook always exits 0 (the deny JSON is the block signal).

set -eu

# On Windows the .ps1 sibling owns this hook. A host may spawn .sh hooks in an
# interactive git-bash window (e.g. Cursor on Windows) whose stdin is a TTY,
# where `cat` would block forever. Bow out on Windows-flavored bash, or whenever
# stdin is not a pipe, so we never hang and never double up with the .ps1.
case "$(uname -s 2>/dev/null)" in MINGW* | MSYS* | CYGWIN*) exit 0 ;; esac
if [ -t 0 ]; then exit 0; fi

input="$(cat)"

agent="${MONK_AGENT_PATH:-${MONK_AGENT_INSTALL_DIR:-"$HOME/.monk/bin"}/monk-agent}"
if [ -x "$agent" ]; then
  if printf '%s' "$input" | "$agent" hook block-monk --format claude; then
    exit 0
  fi
fi

# Fallback: binary unavailable. Grep the raw hook payload for a `monk` command.
# Matches `monk` only in command position (start, or after a shell separator),
# optional `sudo`, followed by whitespace/quote/end — so `monkey` is not matched.
# False positives only ever BLOCK, never allow, which is the safe direction.
if printf '%s' "$input" | grep -Eq '(^|["[:space:];&|`(])(sudo[[:space:]]+)?monk([[:space:]"]|$)'; then
  cat <<'JSON'
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "deny",
    "permissionDecisionReason": "Blocked: do not shell out to the `monk` CLI — it desyncs the cluster state Monk manages. Use the monk-agent MCP tools instead."
  }
}
JSON
  exit 0
fi

exit 0
