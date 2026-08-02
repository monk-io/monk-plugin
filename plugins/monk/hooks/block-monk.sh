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

# Fallback: binary unavailable. No jq here, so pull just the `command` string
# out of the raw JSON (best-effort key match, not a full parser — fine for a
# hook payload of known shape) rather than grepping the whole payload: the
# earlier version matched against the raw text, where a `"` right before
# "monk" is the JSON *string* delimiter, not shell quoting — stripping quotes
# from the whole payload destroyed that boundary and broke detection
# entirely. Once isolated, JSON's own `\"`/`\\` escaping and shell-level
# quoting/escaping ("monk", m\onk) both collapse under the same blunt
# backslash/quote strip (they compose additively here), so one pass handles
# both. Then match `monk`/`monkd` in command position, past a short
# wrapper-command list and an optional leading path — so `monkey` is not
# matched. This is a blunt, non-quote-aware strip, unlike the primary
# `monk-agent hook block-monk` path — good enough for a degraded fallback
# that only runs when the binary itself is missing.
# False positives only ever BLOCK, never allow, which is the safe direction.
raw_command="$(printf '%s' "$input" |
  grep -Eo '"command"[[:space:]]*:[[:space:]]*"([^"\\]|\\.)*"' |
  sed -E 's/^"command"[[:space:]]*:[[:space:]]*"//; s/"$//')"
# A real newline in the original command is JSON-encoded as the two-char
# escape `\n` (JSON strings can't contain a raw newline byte), so a
# multi-line "echo ok<newline>monk deploy" survives extraction as one text
# line with a literal backslash-n in it — invisible to the separator split
# below unless restored to a real newline first (same for \r).
raw_command="$(printf '%s' "$raw_command" | awk '{gsub(/\\n/, "\n"); gsub(/\\r/, "\r"); print}')"
normalized="$(printf '%s' "$raw_command" | tr -d '\\' | tr -d '"' | tr -d "'")"
if printf '%s' "$normalized" | grep -Eq '(^|[;&|`(){}])[[:space:]]*(sudo|command|env|exec|nohup|time|nice)?[[:space:]]*([^[:space:];&|`(){}]*[/\\])?monkd?(\.(exe|cmd|bat|ps1))?([[:space:]]|$)'; then
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
