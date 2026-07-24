#!/usr/bin/env sh
# PostToolUse hook for MANIFEST/MonkScript edits.
# Runs monk-agent analyzer diagnostics after file edits and logs results to
# stderr. Antigravity PostToolUse stdout must be an empty JSON object — results
# cannot be injected back into the conversation from this event type.
#
# Antigravity PostToolUse I/O:
#   stdin:  {"stepIdx":N,"transcriptPath":"...","workspacePaths":[...],...}
#   stdout: {}
#
# All logic lives in `monk-agent hook diagnostics`, so this wrapper depends only
# on the binary the plugin already installs — no jq/curl/awk. Best-effort: if the
# binary is missing we still emit {} and exit 0 so the edit is never blocked.

set -eu

# On Windows the .ps1 sibling owns this hook. A host may spawn .sh hooks in an
# interactive git-bash window (e.g. Cursor on Windows) whose stdin is a TTY,
# where `cat` would block forever. Bow out on Windows-flavored bash, or whenever
# stdin is not a pipe, so we never hang and never double up with the .ps1. Still
# emit the required empty JSON object on stdout.
case "$(uname -s 2>/dev/null)" in MINGW* | MSYS* | CYGWIN*) printf '%s\n' "{}"; exit 0 ;; esac
if [ -t 0 ]; then printf '%s\n' "{}"; exit 0; fi

agent="${MONK_AGENT_PATH:-${MONK_AGENT_INSTALL_DIR:-"$HOME/.monk/bin"}/monk-agent}"
if [ ! -x "$agent" ]; then
  printf '%s\n' "{}"
  exit 0
fi

# The handler prints diagnostics to stderr and the required {} to stdout.
cat | "$agent" hook diagnostics --format antigravity || printf '%s\n' "{}"

exit 0
