#!/usr/bin/env sh
# Shared launcher telemetry, SOURCED (not executed) by the launcher scripts
# (start-monk-agent.sh) and the Antigravity PreInvocation hook. Defines
# monk_emit_launcher_event, which fires the earliest possible
# "plugin_launcher_started" beacon straight to PostHog — before ensure/serve — so
# plugin activity is visible even if the download fails or the agent crashes on
# init.
#
# Usage: monk_emit_launcher_event <launch_client> [ide_version]
#
# Contract: entirely best-effort. Callers invoke it as
# `monk_emit_launcher_event ... || true`; nothing here may abort the launch.
# Mirrors the agent's own telemetry config (MONK_POSTHOG_HOST/KEY and the
# MONK_DISABLE_ANALYTICS / MONK_TELEMETRY / MONK_AGENT_TELEMETRY opt-outs).
# Internals use _-prefixed names so sourcing cannot clobber the caller's vars.

monk_emit_launcher_event() {
  _mlc="${1:-unknown}"
  _mlc_ide="${2:-}"

  case "${MONK_DISABLE_ANALYTICS:-}" in 1) return 0 ;; esac
  case "${MONK_TELEMETRY:-}" in 0) return 0 ;; esac
  case "${MONK_AGENT_TELEMETRY:-}" in 0) return 0 ;; esac

  _ph_host="${MONK_POSTHOG_HOST:-https://us.i.posthog.com}"
  _ph_host="${_ph_host%/}"
  _ph_key="${MONK_POSTHOG_KEY:-phc_VQNP031TPUwNQcWy0RAaKl05b5g67l7rgyzfvk804fn}"

  _mh="${MONK_AGENT_HOME:-"$HOME/.monk"}"
  _dd="$_mh/agent/launcher"
  _managed="${MONK_AGENT_INSTALL_DIR:-"$HOME/.monk/bin"}/monk-agent"
  mkdir -p "$_dd" 2>/dev/null || true

  _now="$(date +%s 2>/dev/null || printf 0)"

  # Dedup the .ps1/.sh SessionStart double-fire (and any rapid re-run) into one
  # event per session: skip if the last emit was under ~15s ago. Genuine
  # restarts (minutes apart) still emit. The launch itself proceeds regardless.
  _marker="$_dd/last-launch-emit"
  if [ -f "$_marker" ]; then
    _last="$(cat "$_marker" 2>/dev/null || printf 0)"
    case "$_last" in
      "" | *[!0-9]*) _last=0 ;;
    esac
    if [ "$_now" != "0" ] && [ "$_last" != "0" ]; then
      _delta=$((_now - _last))
      if [ "$_delta" -ge 0 ] && [ "$_delta" -lt 15 ]; then
        return 0
      fi
    fi
  fi
  printf '%s\n' "$_now" >"$_marker" 2>/dev/null || true

  # first_start (once-ever, distinct from the per-session dedup above): true only
  # when neither this marker NOR a managed binary exists, so installs predating
  # the marker don't report a false first install.
  _first="$_dd/first-start"
  _first_start=false
  if [ ! -f "$_first" ] && [ ! -e "$_managed" ]; then
    _first_start=true
  fi
  if [ ! -f "$_first" ]; then
    { date -u +%Y-%m-%dT%H:%M:%SZ >"$_first" 2>/dev/null; } || true
  fi

  _agent_installed=false
  [ -e "$_managed" ] && _agent_installed=true

  # distinct_id: reuse the agent's stored anon client id so launcher and agent
  # events unify under one identity (later aliased to the signed-in user).
  # Absent (true first run, or the opt-in sqlite backend with no client.json) ⇒
  # ephemeral id, flagged so uncorrelated events are identifiable in PostHog.
  _cid=""
  _cid_file="$_mh/agent/store/global/telemetry/client.json"
  if [ -f "$_cid_file" ]; then
    _cid="$(sed -n 's/.*"clientId"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$_cid_file" 2>/dev/null | head -n 1)"
  fi
  _cid_src="store"
  if [ -z "$_cid" ]; then
    _cid_src="ephemeral"
    if command -v uuidgen >/dev/null 2>&1; then
      _cid="$(uuidgen 2>/dev/null || true)"
    fi
    if [ -z "$_cid" ] && [ -r /proc/sys/kernel/random/uuid ]; then
      _cid="$(cat /proc/sys/kernel/random/uuid 2>/dev/null || true)"
    fi
    [ -z "$_cid" ] && _cid="launcher-$_now-$$"
  fi

  _pv="${MONK_PLUGIN_VERSION:-}"
  _osn="$(uname -s 2>/dev/null || printf unknown)"
  _osa="$(uname -m 2>/dev/null || printf unknown)"
  _plat="$(printf '%s' "$_osn" | tr '[:upper:]' '[:lower:]')"

  # Encode a shell string as JSON string content. LC_ALL=C makes awk's %c
  # byte-preserving, so UTF-8 survives while every U+0000-U+001F byte that JSON
  # forbids is escaped. POSIX od/awk keep this usable before the agent exists.
  _mjson() {
    printf '%s' "$1" |
      LC_ALL=C od -An -v -t u1 2>/dev/null |
      LC_ALL=C awk '{
        for (i = 1; i <= NF; i++) {
          b = $i + 0
          if (b == 34)       printf "\\\""
          else if (b == 92)  printf "\\\\"
          else if (b == 8)   printf "\\b"
          else if (b == 9)   printf "\\t"
          else if (b == 10)  printf "\\n"
          else if (b == 12)  printf "\\f"
          else if (b == 13)  printf "\\r"
          else if (b < 32)   printf "\\u%04x", b
          else               printf "%c", b
        }
      }'
  }

  _payload="$(
    printf '{"api_key":"%s","event":"plugin_launcher_started","distinct_id":"%s","properties":{"launch_client":"%s","host_client":"%s","client":"%s","first_start":%s,"agent_installed":%s,"client_id_source":"%s","plugin_version":"%s","ide_version":"%s","platform":"%s","os_arch":"%s","source":"monk-plugin-launcher"}}' \
      "$(_mjson "$_ph_key")" "$(_mjson "$_cid")" \
      "$(_mjson "$_mlc")" "$(_mjson "$_mlc")" "$(_mjson "$_mlc")" \
      "$_first_start" "$_agent_installed" "$_cid_src" \
      "$(_mjson "$_pv")" "$(_mjson "$_mlc_ide")" \
      "$(_mjson "$_plat")" "$(_mjson "$_osa")"
  )"

  if command -v curl >/dev/null 2>&1; then
    curl -fsS --max-time 3 -X POST -H 'Content-Type: application/json' \
      -d "$_payload" "$_ph_host/capture/" >/dev/null 2>&1 &
  elif command -v wget >/dev/null 2>&1; then
    wget -q -T 3 -O - --header='Content-Type: application/json' \
      --post-data="$_payload" "$_ph_host/capture/" >/dev/null 2>&1 &
  fi
}
