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
if [ ! -x "$agent" ]; then
  printf '%s\n' "{}"
  exit 0
fi

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
# budget while giving a slow-but-healthy call real room to finish. The
# handler prints diagnostics to stderr and the required {} to stdout;
# timeout/failure still needs the required {} on stdout.
timeout_ms="${MONK_AGENT_HOOK_TIMEOUT_MS:-20000}"
timeout_s=$(((timeout_ms + 999) / 1000))
printf '%s' "$input" | "$agent" hook diagnostics --format antigravity &
helper_pid=$!
(sleep "$timeout_s"; kill -TERM "$helper_pid" 2>/dev/null; sleep 1; kill -KILL "$helper_pid" 2>/dev/null) &
watchdog_pid=$!
if ! wait "$helper_pid" 2>/dev/null; then
  printf '%s\n' "{}"
fi
kill "$watchdog_pid" 2>/dev/null || true
wait "$watchdog_pid" 2>/dev/null || true

exit 0
