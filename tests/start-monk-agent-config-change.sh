#!/usr/bin/env sh
set -eu

repo="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
root="$(mktemp -d)"
server_pid=""

cleanup() {
  if [ -n "$server_pid" ]; then
    kill "$server_pid" >/dev/null 2>&1 || true
  fi
  rm -rf "$root"
}
trap cleanup EXIT HUP INT TERM

home="$root/home"
install="$root/install"
fake_bin="$root/bin"
capture="$root/starts.log"
port_file="$root/port"
mkdir -p "$home" "$install" "$fake_bin"

cat >"$fake_bin/uname" <<'EOF'
#!/usr/bin/env sh
case "${1:-}" in
  -m) printf '%s\n' x86_64 ;;
  *) printf '%s\n' Linux ;;
esac
EOF
chmod +x "$fake_bin/uname"

cat >"$install/monk-agent" <<'EOF'
#!/usr/bin/env sh
printf 'auth=%s\n' "${MONK_AUTH_URL:-}" >>"$MONK_CAPTURE_PATH"
exit 0
EOF
chmod +x "$install/monk-agent"

python3 - "$port_file" <<'PY' &
import http.server
import pathlib
import sys

class Handler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        body = ('{"resource":"http://127.0.0.1:%d/mcp","signedIn":true}'
                % self.server.server_port).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *_args):
        pass

server = http.server.HTTPServer(("127.0.0.1", 0), Handler)
pathlib.Path(sys.argv[1]).write_text(str(server.server_port))
server.serve_forever()
PY
server_pid="$!"

tries=0
while [ ! -s "$port_file" ]; do
  tries=$((tries + 1))
  [ "$tries" -lt 50 ] || { echo "Health fixture did not start." >&2; exit 1; }
  sleep 0.1
done
port="$(cat "$port_file")"

run_launcher() {
  auth_url="$1"
  PATH="$fake_bin:$PATH" \
  HOME="$home" \
  MONK_AGENT_HOME="$home/.monk" \
  MONK_AGENT_INSTALL_DIR="$install" \
  MONK_AGENT_AUTO_UPDATE=0 \
  MONK_AGENT_PORT="$port" \
  MONK_AGENT_SKIP_SIGNIN_NUDGE=1 \
  MONK_DISABLE_ANALYTICS=1 \
  MONK_CAPTURE_PATH="$capture" \
  MONK_AUTH_URL="$auth_url" \
    "$repo/scripts/start-monk-agent.sh"
  sleep 0.2
}

run_launcher https://auth-one.invalid
run_launcher https://auth-one.invalid
run_launcher https://auth-two.invalid
run_launcher https://auth-two.invalid

expected="$(printf 'auth=%s\nauth=%s' https://auth-one.invalid https://auth-two.invalid)"
actual="$(cat "$capture")"
[ "$actual" = "$expected" ] || {
  echo "Unexpected launch configurations:" >&2
  printf '%s\n' "$actual" >&2
  exit 1
}

config_file="$home/.monk/agent/launcher/run/monk-agent.config"
[ -s "$config_file" ] || { echo "Launcher configuration fingerprint was not persisted." >&2; exit 1; }

echo "POSIX launcher configuration-change regression passed."
