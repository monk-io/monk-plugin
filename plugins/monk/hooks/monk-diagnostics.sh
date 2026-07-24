#!/usr/bin/env sh
# PostToolUse hook for MANIFEST/MonkScript edits.
# Asks local monk-agent for analyzer diagnostics and feeds concise results back
# into Claude Code after template edits.
#
# All logic (path resolution, workspace discovery, the MCP call, and formatting)
# lives in `monk-agent hook diagnostics`, so this wrapper depends only on the
# binary the plugin already installs — no jq/curl/awk. The hook is best-effort:
# a missing binary, missing agent, auth issues, or unavailable analyzer support
# must never block the user's edit, so we always exit 0.

set -eu

# Output shape: "claude" (default, also Cursor) emits a superset; "codex" emits
# ONLY the documented PostToolUse fields (Codex drops output with any unknown
# top-level key). The Codex hook passes `--format codex`; others use the default.
fmt="claude"
if [ "${1:-}" = "--format" ] && [ -n "${2:-}" ]; then fmt="$2"; fi

# On Windows the .ps1 sibling owns this hook. A host may spawn .sh hooks in an
# interactive git-bash window (e.g. Cursor on Windows) whose stdin is a TTY,
# where `cat` would block forever. Bow out on Windows-flavored bash, or whenever
# stdin is not a pipe, so we never hang and never double up with the .ps1.
case "$(uname -s 2>/dev/null)" in MINGW* | MSYS* | CYGWIN*) exit 0 ;; esac
if [ -t 0 ]; then exit 0; fi

agent="${MONK_AGENT_PATH:-${MONK_AGENT_INSTALL_DIR:-"$HOME/.monk/bin"}/monk-agent}"
[ -x "$agent" ] || exit 0

cat | "$agent" hook diagnostics --format "$fmt" || exit 0

exit 0
