#!/bin/sh
# monk-relay-recovery.sh — recovery diagnostics for Monk WSL relay (fix for #286)
#
# Problem (monk-io/monk-plugin#286, accepted): after Windows reboot or WSL
# idle-shutdown, the WSL localhost relay (127.0.0.1:2137) is not rebuilt, so
# monkd inside WSL is unreachable -> "connect ECONNREFUSED 127.0.0.1:2137".
# The plugin previously failed silently with no recovery hint.
#
# This hook detects the dead relay and prints the exact recovery step, so the
# agent (and the user) gets an actionable message instead of a stack of
# ECONNREFUSED errors. It does NOT auto-run `wsl --shutdown` (destructive,
# user-approved only) — it reports.
#
# Invoked from hooks.json PostToolUse / a dedicated recovery check, or manually.
set -euo pipefail

PORT="${MONK_RELAY_PORT:-2137}"
HOST="${MONK_RELAY_HOST:-127.0.0.1}"

# Quick reachability probe (cross-platform: bash on the WSL side, or Windows).
if command -v wsl >/dev/null 2>&1; then
  # We are on Windows host. Check the Windows-side listener.
  if command -v netstat >/dev/null 2>&1; then
    if netstat -an 2>/dev/null | grep -q ":$PORT "; then
      echo "monk-relay: 127.0.0.1:$PORT LISTENING on Windows side — relay up."
      exit 0
    fi
  fi
  # Relay not listening. Determine WSL distro state.
  if command -v wsl >/dev/null 2>&1; then
    WSLSTATE="$(wsl -l -v 2>/dev/null | grep -i running || echo 'NO DISTRO RUNNING')"
    echo "monk-relay: 127.0.0.1:$PORT NOT listening on Windows side (relay down)."
    echo "monk-relay: WSL state: $WSLSTATE"
    echo "monk-relay: RECOVERY -> run 'wsl --shutdown' then restart the distro to rebuild the localhost relay, then retry."
    echo "monk-relay: (monk-io/monk-plugin#286 — accepted)"
    exit 2
  fi
fi

# Fallback: direct TCP probe.
if command -v bash >/dev/null 2>&1; then
  if (exec 3<>/dev/tcp/$HOST/$PORT) 2>/dev/null; then
    echo "monk-relay: $HOST:$PORT reachable."
    exit 0
  else
    echo "monk-relay: $HOST:$PORT UNREACHABLE (ECONNREFUSED)."
    echo "monk-relay: RECOVERY -> ensure monkd is running and the WSL/localhost relay is up (monk-io/monk-plugin#286)."
    exit 2
  fi
fi

exit 0
