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

# Buffer the payload before the helper is backgrounded below. POSIX requires a
# shell with job control disabled (i.e. every non-interactive hook invocation)
# to point the standard input of an asynchronous list at /dev/null, and dash --
# `/bin/sh` on Ubuntu, so the shell every Linux host actually runs this under --
# does exactly that for the first process of a backgrounded pipeline. So a
# backgrounded `cat`-into-helper pipeline reads /dev/null instead of the host's
# payload, and the helper exits immediately with no diagnostics (confirmed live
# 2026-09-02: e2e-smoke's diagnosticsVerified stayed false at every watchdog
# budget, because the failure is instant and has nothing to do with timing).
# Reading stdin here, in the foreground, and feeding the helper from a variable
# is the same shape block-monk.sh already uses -- and why block-monk kept
# working through the same incident.
input="$(cat)"

agent="${MONK_AGENT_PATH:-${MONK_AGENT_INSTALL_DIR:-"$HOME/.monk/bin"}/monk-agent}"
[ -x "$agent" ] || exit 0

# A wedged (not merely failing) helper must not block the edit indefinitely:
# background it under a watchdog that TERMs then KILLs it after
# MONK_AGENT_HOOK_TIMEOUT_MS (default 20s). Unlike block-monk's 2s default
# (which must stay well under every host's tight 5s PreToolUse budget), this
# hook's host budget is a generous 30s and the analyzer call itself can
# legitimately take several seconds on a cold/first-request agent -- an
# aggressive bound here was confirmed live (2026-09-02 e2e-smoke) to truncate
# real, still-in-flight analyzer responses before they ever came back, so a
# working call was silently discarded exactly like a genuinely wedged one.
# 20s leaves the watchdog's own TERM/KILL grace (~1s) safely inside the 30s
# budget while giving a slow-but-healthy call real room to finish.
timeout_ms="${MONK_AGENT_HOOK_TIMEOUT_MS:-20000}"
timeout_s=$(((timeout_ms + 999) / 1000))
printf '%s' "$input" | "$agent" hook diagnostics --format "$fmt" &
helper_pid=$!
(sleep "$timeout_s"; kill -TERM "$helper_pid" 2>/dev/null; sleep 1; kill -KILL "$helper_pid" 2>/dev/null) &
watchdog_pid=$!
wait "$helper_pid" 2>/dev/null || true
kill "$watchdog_pid" 2>/dev/null || true
wait "$watchdog_pid" 2>/dev/null || true

exit 0
