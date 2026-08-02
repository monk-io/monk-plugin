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

# On Windows the .ps1 sibling owns this hook. A host may spawn .sh hooks in an
# interactive git-bash window (e.g. Cursor on Windows) whose stdin is a TTY,
# where `cat` would block forever. Bow out on Windows-flavored bash, or whenever
# stdin is not a pipe, so we never hang and never double up with the .ps1.
case "$(uname -s 2>/dev/null)" in MINGW* | MSYS* | CYGWIN*) exit 0 ;; esac
if [ -t 0 ]; then exit 0; fi

input="$(cat)"

agent="${MONK_AGENT_PATH:-${MONK_AGENT_INSTALL_DIR:-"$HOME/.monk/bin"}/monk-agent}"
if [ -x "$agent" ]; then
  if printf '%s' "$input" | "$agent" hook block-monk --format antigravity; then
    exit 0
  fi
fi

# Fallback: binary unavailable. No jq here, so pull just the `CommandLine`
# string out of the raw JSON (best-effort key match, not a full parser) rather
# than grepping the whole payload: matching against the raw text means a `"`
# right before "monk" is the JSON *string* delimiter, not shell quoting —
# stripping quotes from the whole payload destroys that boundary. Once
# isolated, JSON's own `\"`/`\\` escaping and shell-level quoting/escaping
# ("monk", m\onk) both collapse under the same blunt backslash/quote strip
# (they compose additively here). Then match `monk`/`monkd` in command
# position, past a short wrapper-command list and an optional leading path.
# This is a blunt, non-quote-aware strip — see block-monk.ps1 for the
# tradeoff vs the quote-state-aware primary `monk-agent hook block-monk` path.
# False positives only ever BLOCK, never allow.
raw_command="$(printf '%s' "$input" |
  grep -Eo '"CommandLine"[[:space:]]*:[[:space:]]*"([^"\\]|\\.)*"' |
  sed -E 's/^"CommandLine"[[:space:]]*:[[:space:]]*"//; s/"$//')"
# A real newline in the original command is JSON-encoded as the two-char
# escape `\n` (JSON strings can't contain a raw newline byte), so a
# multi-line command survives extraction as one text line with a literal
# backslash-n in it — invisible to the separator split below unless restored
# to a real newline first (same for \r).
raw_command="$(printf '%s' "$raw_command" | awk '{gsub(/\\n/, "\n"); gsub(/\\r/, "\r"); print}')"
normalized="$(printf '%s' "$raw_command" | tr -d '\\' | tr -d '"' | tr -d "'")"
if printf '%s' "$normalized" | grep -Eq '(^|[;&|`(){}])[[:space:]]*(sudo|command|env|exec|nohup|time|nice)?[[:space:]]*([^[:space:];&|`(){}]*[/\\])?monkd?(\.(exe|cmd|bat|ps1))?([[:space:]]|$)'; then
  cat <<'JSON'
{
  "decision": "deny",
  "reason": "Blocked: do not shell out to the `monk` CLI — it desyncs the cluster state Monk manages. Use the monk-agent MCP tools instead."
}
JSON
  exit 0
fi

exit 0
