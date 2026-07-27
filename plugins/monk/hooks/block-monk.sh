#!/usr/bin/env sh
# PreToolUse hook for the Bash tool: block any shell-out to the `monk` CLI or
# `monkd` daemon. Monk owns its own cluster state — running these from a shell desyncs it.
# Use monk-agent MCP tools instead.
#
# The decision is made by `monk-agent hook block-monk` so the only dependency is
# the monk-agent binary the plugin already installs. If that binary is somehow
# missing we fall back to pure POSIX shell + grep, biased toward BLOCKING: a
# `monk`/`monkd` invocation is still caught with zero tooling, and non-monk
# commands are never blocked. The hook always exits 0 (the deny JSON is the block signal).

set -eu

# On Windows the .ps1 sibling owns this hook. A host may spawn .sh hooks in an
# interactive git-bash window (e.g. Cursor on Windows) whose stdin is a TTY,
# where `cat` would block forever. Bow out on Windows-flavored bash, or whenever
# stdin is not a pipe, so we never hang and never double up with the .ps1.
case "$(uname -s 2>/dev/null)" in MINGW* | MSYS* | CYGWIN*) exit 0 ;; esac
if [ -t 0 ]; then exit 0; fi

input="$(cat)"

should_block_monk_shellout() {
  payload=$1
  boundary='(^|[";&|`({]|\\n|\\r\\n)[[:space:]]*'
  monk_bin='((([A-Za-z]:\\\\|~[\\/]|/)([^[:space:]";&|(){}]+[\\/])*)?monkd?(\.exe)?)'
  prefix='((sudo|command)[[:space:]]+)*(env([[:space:]]+(-[^[:space:]]+|[A-Za-z_][A-Za-z0-9_]*=("[^"]*"|[^[:space:]]+)))*[[:space:]]+)?'

  # Direct command-position invocations and wrappers such as `command monk`,
  # `env monk`, absolute paths, and `monkd`.
  if printf '%s' "$payload" | grep -Eq "${boundary}${prefix}${monk_bin}([[:space:]\";&|)]|$)"; then
    return 0
  fi

  # Command substitution that resolves the binary and then executes it:
  # `$(which monk) deploy`.
  if printf '%s' "$payload" | grep -Eq "${boundary}\\\$\\([^)]*which[[:space:]]+monkd?[^)]*\\)[[:space:]]+[^[:space:]]"; then
    return 0
  fi

  # Nested shells where the inline script starts with a Monk command or reaches
  # one after a simple shell separator.
  if printf '%s' "$payload" | grep -Eq "${boundary}(sudo[[:space:]]+)?(bash|sh|zsh)(\\.exe)?[[:space:]]+-[A-Za-z]*c[[:space:]]+(\\\\?\")?[[:space:]]*([^\";&|]*[;&|][[:space:]]*)?${prefix}${monk_bin}([[:space:]\";&|)]|$)"; then
    return 0
  fi

  # PowerShell inline commands have the same bypass shape on Windows hosts.
  if printf '%s' "$payload" | grep -Eq "${boundary}(sudo[[:space:]]+)?(powershell|powershell\\.exe|pwsh|pwsh\\.exe)[^;&|]*[[:space:]]-(Command|c)[[:space:]]+(\\\\?\")?[[:space:]]*([^\";&|]*[;&|][[:space:]]*)?${prefix}${monk_bin}([[:space:]\";&|)]|$)"; then
    return 0
  fi

  return 1
}

emit_deny() {
  cat <<'JSON'
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "deny",
    "permissionDecisionReason": "Blocked: do not shell out to the `monk` CLI or `monkd` daemon — it desyncs the cluster state Monk manages. Use the monk-agent MCP tools instead."
  }
}
JSON
}

agent="${MONK_AGENT_PATH:-${MONK_AGENT_INSTALL_DIR:-"$HOME/.monk/bin"}/monk-agent}"
agent_output=
if [ -x "$agent" ]; then
  if agent_output="$(printf '%s' "$input" | "$agent" hook block-monk --format claude)"; then
    if printf '%s' "$agent_output" | grep -Eq '"permissionDecision"[[:space:]]*:[[:space:]]*"deny"'; then
      printf '%s' "$agent_output"
      exit 0
    fi
  fi
fi

# Post-filter the helper allow/no-output path and also cover the missing-helper
# fallback path with the same wrapper-aware local matcher.
if should_block_monk_shellout "$input"; then
  emit_deny
  exit 0
fi

if [ -n "$agent_output" ]; then
  printf '%s' "$agent_output"
fi

exit 0
