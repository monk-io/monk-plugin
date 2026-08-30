#!/usr/bin/env sh
set -eu
repo="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
image="${MONK_PWSH_IMAGE:-mcr.microsoft.com/powershell:latest}"
# Pull/start the runtime before timing the hook itself.
docker run --rm "$image" pwsh -NoProfile -Command 'exit 0' >/dev/null
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT HUP INT TERM
cat >"$tmp/wedged-agent.exe" <<'AGENT'
#!/bin/sh
exec sleep 30
AGENT
chmod +x "$tmp/wedged-agent.exe"
cat >"$tmp/success-agent.exe" <<'AGENT'
#!/bin/sh
cat >/dev/null
printf '%s\n' '{"decision":"deny","reason":"helper-control"}'
AGENT
chmod +x "$tmp/success-agent.exe"
printf '%s' '{"toolCall":{"name":"run_command","args":{"CommandLine":"monk deploy"}}}' >"$tmp/antigravity.json"
printf '%s' '{"tool_input":{"command":"monk deploy"}}' >"$tmp/claude.json"
run_case() {
  hook="$1"
  payload="$2"
  expected="$3"
  start="$(date +%s)"
  out="$(timeout 6s docker run --rm -i -e OS=Windows_NT -e MONK_AGENT_PATH=/fixture/wedged-agent.exe \
    -v "$repo:/repo:ro" -v "$tmp/wedged-agent.exe:/fixture/wedged-agent.exe:ro" \
    "$image" pwsh -NoProfile -File "/repo/$hook" <"$payload")"
  elapsed=$(( $(date +%s) - start ))
  [ "$elapsed" -lt 6 ] || { echo "$hook outlived helper deadline" >&2; exit 1; }
  printf '%s' "$out" | grep -F "$expected" >/dev/null || { echo "$hook did not fall back to deny" >&2; exit 1; }
}
run_case ".antigravity-plugin/hooks/block-monk.ps1" "$tmp/antigravity.json" '"decision":"deny"'
run_case "hooks/block-monk.ps1" "$tmp/claude.json" '"permissionDecision":"deny"'
out="$(docker run --rm -i -e OS=Windows_NT -e MONK_AGENT_PATH=/fixture/success-agent.exe \
  -v "$repo:/repo:ro" -v "$tmp/success-agent.exe:/fixture/success-agent.exe:ro" \
  "$image" pwsh -NoProfile -File /repo/.antigravity-plugin/hooks/block-monk.ps1 <"$tmp/antigravity.json")"
printf '%s' "$out" | grep -F 'helper-control' >/dev/null
echo block_monk_powershell_helper_timeout=pass
