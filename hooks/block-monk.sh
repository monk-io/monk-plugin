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
helper_timeout="${MONK_BLOCK_MONK_HELPER_TIMEOUT:-2}"
case "$helper_timeout" in
  *[!0-9]*|0*) helper_timeout=2 ;;
esac

run_agent_helper() {
  helper_dir="$(mktemp -d "${TMPDIR:-/tmp}/monk-block-monk.XXXXXX")" || return 1
  helper_input="$helper_dir/input"
  helper_output="$helper_dir/output"
  helper_error="$helper_dir/error"
  helper_timed_out="$helper_dir/timed-out"
  printf '%s' "$input" >"$helper_input"

  "$agent" hook block-monk --format claude \
    <"$helper_input" >"$helper_output" 2>"$helper_error" &
  helper_pid=$!
  (
    sleep "$helper_timeout"
    : >"$helper_timed_out"
    kill -TERM "$helper_pid" 2>/dev/null || true
  ) &
  watchdog_pid=$!

  if wait "$helper_pid"; then
    helper_status=0
  else
    helper_status=$?
  fi
  kill "$watchdog_pid" 2>/dev/null || true
  wait "$watchdog_pid" 2>/dev/null || true

  if [ "$helper_status" -eq 0 ]; then
    cat "$helper_error" >&2
    cat "$helper_output"
    rm -rf "$helper_dir"
    return 0
  fi
  if [ ! -f "$helper_timed_out" ]; then
    cat "$helper_error" >&2
  fi
  rm -rf "$helper_dir"
  return 1
}

if [ -x "$agent" ]; then
  if run_agent_helper; then
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
# both. Then match `monk`/`monkd` in command position, past an optional
# wrapper keyword (including `eval`/`xargs`/`awk`/`perl`/`python`/bare or
# `-c` `bash`/`sh`/`zsh` — ENG-494), an optional `timeout [flags] N` prefix
# (ENG-492), zero or more `NAME=value` assignment prefixes (ENG-492), and an
# optional leading path — so `monkey` is not matched. Unlike the primary
# `monk-agent hook block-monk` tokenizer, this single-shot ERE only strips one
# wrapper token (no stacking, e.g. `sudo env monk`) and never resolves the
# `find -exec monk ...` shape — a blunt, best-effort strip that is good enough
# for a degraded fallback that only runs when the binary itself is missing.
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
if printf '%s' "$normalized" | grep -Eq '(^|[;&|`(){}])[[:space:]]*(sudo|command|env|exec|nohup|time|nice|eval|xargs|awk|perl|python[0-9.]*|(bash|sh|zsh)([[:space:]]+-c)?)?[[:space:]]*(timeout([[:space:]]+-[A-Za-z]+([[:space:]]+[^[:space:]]+)?)*[[:space:]]+[0-9.]+[[:space:]]+)?([A-Za-z_][A-Za-z0-9_]*=[^[:space:]]*[[:space:]]+)*([^[:space:];&|`(){}]*[/\\])?monkd?(\.(exe|cmd|bat|ps1))?([[:space:]]|$)'; then
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
