#!/usr/bin/env sh
set -eu

PATH="/usr/bin:/bin:$PATH"

repo="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
root="$(mktemp -d)"
cleanup() {
  rm -rf "$root"
}
trap cleanup EXIT HUP INT TERM

fakebin="$root/fakebin"
mkdir -p "$fakebin" "$root/home" "$root/monk"

cat >"$fakebin/uname" <<'EOF'
#!/usr/bin/env sh
printf '%s\n' 'Linux'
EOF

cat >"$fakebin/curl" <<'EOF'
#!/usr/bin/env sh
printf '%s\n' "$*" >> "$CURL_ARGS_LOG"
printf '%s\n' "$NO_PROXY" >> "$NO_PROXY_LOG"
case " $* " in
  *" --noproxy "*) ;;
  *) exit 43 ;;
esac
case ",$NO_PROXY," in
  *,127.0.0.1,*) ;;
  *) exit 44 ;;
esac
printf '{"resource":"http://127.0.0.1:7419/mcp"}\n'
EOF

cat >"$root/monk-agent" <<'EOF'
#!/usr/bin/env sh
printf 'started\n' > "$START_MARKER"
exit 70
EOF

PATH="$fakebin:$PATH" \
HOME="$root/home" \
MONK_AGENT_HOME="$root/monk" \
MONK_AGENT_PATH="$root/monk-agent" \
MONK_AGENT_SKIP_SIGNIN_NUDGE=1 \
http_proxy="http://127.0.0.1:9" \
https_proxy="http://127.0.0.1:9" \
all_proxy="socks5://127.0.0.1:9" \
CURL_ARGS_LOG="$root/curl.args" \
NO_PROXY_LOG="$root/no_proxy.log" \
START_MARKER="$root/started" \
  "$repo/scripts/start-monk-agent.sh"

if [ -e "$root/started" ]; then
  echo "expected healthy loopback probe to skip agent start" >&2
  exit 1
fi

grep -q -- '--noproxy' "$root/curl.args"
grep -q '127.0.0.1' "$root/no_proxy.log"
