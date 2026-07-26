#!/usr/bin/env sh
# PreToolUse hook for the Bash tool: block any shell-out to the `monk` CLI.
# Monk owns its own cluster state — running `monk ...` from a shell desyncs it.
# Use monk-agent MCP tools instead.
#
# The decision is made by `monk-agent hook block-monk` so the only dependency is
# the monk-agent binary the plugin already installs. If that binary is somehow
# missing, we inspect the command payload locally and keep a grep last resort for
# hosts without python3. The hook always exits 0 (the deny JSON is the block
# signal).

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

monk_fallback_matches() {
  if command -v python3 >/dev/null 2>&1; then
    MONK_HOOK_PAYLOAD="$input" python3 - <<'PY'
import json
import os
import sys

payload = os.environ.get("MONK_HOOK_PAYLOAD", "")

try:
    data = json.loads(payload)
except Exception:
    command = payload
else:
    command = payload
    if isinstance(data, dict):
        tool_call = data.get("toolCall")
        if isinstance(tool_call, dict):
            args = tool_call.get("args")
            if isinstance(args, dict) and isinstance(args.get("CommandLine"), str):
                command = args["CommandLine"]
        tool_input = data.get("tool_input")
        if isinstance(tool_input, dict) and isinstance(tool_input.get("command"), str):
            command = tool_input["command"]


def command_parts(value):
    start = 0
    quote = ""
    escaped = False
    for index, char in enumerate(value):
        if escaped:
            escaped = False
            continue
        if char == "\\" and quote != "'":
            escaped = True
            continue
        if quote:
            if char == quote:
                quote = ""
            continue
        if char in ("'", '"'):
            quote = char
            continue
        if char in ";&|`\n\r":
            yield value[start:index]
            start = index + 1
    yield value[start:]


def next_token(value, index):
    while index < len(value) and (value[index].isspace() or value[index] == "("):
        index += 1
    token = []
    quote = ""
    escaped = False
    while index < len(value):
        char = value[index]
        if escaped:
            token.append(char)
            escaped = False
            index += 1
            continue
        if quote:
            if char == quote:
                quote = ""
                index += 1
                continue
            if char == "\\" and quote == '"':
                escaped = True
                index += 1
                continue
            token.append(char)
            index += 1
            continue
        if char == "\\":
            escaped = True
            index += 1
            continue
        if char in ("'", '"'):
            quote = char
            index += 1
            continue
        if char.isspace() or char in ";&|`":
            break
        token.append(char)
        index += 1
    return "".join(token), index


def monk_token(token):
    return token == "monk" or token.endswith("/monk") or token.endswith("/monk.exe")


def part_invokes_monk(part):
    index = 0
    in_env = False
    for _ in range(10):
        token, index = next_token(part, index)
        if not token:
            return False
        if token in ("sudo", "command"):
            continue
        if token == "env":
            in_env = True
            continue
        if in_env and (token.startswith("-") or ("=" in token and "/" not in token)):
            continue
        return monk_token(token)
    return False


sys.exit(0 if any(part_invokes_monk(part) for part in command_parts(command)) else 1)
PY
    return $?
  fi

  # Last-resort fallback: binary and python unavailable. Grep the raw hook
  # payload for a command-position `monk` form. False positives only ever block.
  printf '%s' "$input" | grep -Eq '(^|["'"'"'\\;;&|`(])[[:space:]]*(sudo[[:space:]]+)?["'"'"'\\]*monk(["'"'"'\\]*)([[:space:]"]|$)'
}

if monk_fallback_matches; then
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
