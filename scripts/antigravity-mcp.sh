# Register monk in Antigravity's global MCP config, ~/.gemini/config/mcp_config.json.
# Sourced by scripts/start-monk-agent.sh (any host's session start) and by
# Antigravity's own hooks/ensure-monk-agent.sh, so the one entry has one writer
# here. Windows counterpart: antigravity-mcp.ps1.
#
# Usage: register_antigravity_mcp <monk-agent path> <agent MCP URL>
#
# The entry runs monk-agent's stdio bridge rather than pointing serverUrl at the
# agent: through serverUrl, Antigravity's sign-in ends on a Google page showing a
# code the user has to paste back, while the bridge signs in with a loopback
# redirect like every other agent (ENG-852). `monk-agent setup` writes the same
# entry (registry.ts); keep them identical or each rewrites the other's.
#
# Idempotent — skips if the entry is already current, and replaces a stale one
# (a prior host/port or binary, or an older serverUrl entry). Uses jq or python3
# when available; prints manual instructions otherwise. Writes only to stderr.
register_antigravity_mcp() {
  mcp_agent_path="$1"
  server_url="$2"
  gemini_cfg="$HOME/.gemini/config"
  [ -d "$gemini_cfg" ] || return 0
  mcp_cfg="$gemini_cfg/mcp_config.json"
  json_agent_path="$(printf '%s' "$mcp_agent_path" | sed 's/\\/\\\\/g; s/"/\\"/g')"
  entry_json="{\"command\":\"$json_agent_path\",\"args\":[\"mcp-stdio\",\"--url\",\"$server_url\"]}"
  # Treat an empty file the same as a missing file to avoid jq/python parse errors.
  has_existing=0
  if [ -f "$mcp_cfg" ] && [ -s "$mcp_cfg" ]; then
    has_existing=1
  fi
  if [ "$has_existing" = "1" ]; then
    # Validate before touching the file — a malformed unrelated config must
    # produce a warning, not abort the launcher after the health check passed.
    valid=1
    if command -v jq >/dev/null 2>&1; then
      jq -e 'type == "object"' "$mcp_cfg" >/dev/null 2>&1 || valid=0
    elif command -v python3 >/dev/null 2>&1; then
      python3 -c 'import json, sys
with open(sys.argv[1], encoding="utf-8") as handle:
    cfg = json.load(handle)
raise SystemExit(0 if isinstance(cfg, dict) else 1)' "$mcp_cfg" >/dev/null 2>&1 || valid=0
    fi
    if [ "$valid" = "0" ]; then
      echo "Warning: $mcp_cfg is not a valid JSON object; skipping automatic Antigravity MCP registration." >&2
      printf '  Add manually if desired: {"mcpServers":{"monk":%s}}\n' "$entry_json" >&2
      return 0
    fi
    # Compare the whole .mcpServers.monk entry with the current one, not just
    # presence of the key — a stale registration (prior host/port or binary, or
    # an older serverUrl entry) must be replaced, not mistaken for current.
    already_registered=0
    if command -v jq >/dev/null 2>&1; then
      jq -e --arg c "$mcp_agent_path" --arg u "$server_url" \
        '.mcpServers.monk == {command: $c, args: ["mcp-stdio", "--url", $u]}' \
        "$mcp_cfg" >/dev/null 2>&1 && already_registered=1
    elif command -v python3 >/dev/null 2>&1; then
      python3 -c '
import json, sys
with open(sys.argv[1], encoding="utf-8") as handle:
    cfg = json.load(handle)
servers = cfg.get("mcpServers")
monk = servers.get("monk") if isinstance(servers, dict) else None
want = {"command": sys.argv[2], "args": ["mcp-stdio", "--url", sys.argv[3]]}
sys.exit(0 if monk == want else 1)
' "$mcp_cfg" "$mcp_agent_path" "$server_url" >/dev/null 2>&1 && already_registered=1
    else
      # No JSON tool available to parse structurally; fall back to the
      # conservative substring guard rather than risk corrupting the file.
      grep -Fq "\"$server_url\"" "$mcp_cfg" 2>/dev/null &&
        grep -Fq '"mcp-stdio"' "$mcp_cfg" 2>/dev/null && already_registered=1
    fi
    [ "$already_registered" = "1" ] && return 0
  fi
  tmp="$(mktemp)"
  if command -v jq >/dev/null 2>&1; then
    if [ "$has_existing" = "1" ]; then
      jq --arg c "$mcp_agent_path" --arg u "$server_url" \
        '.mcpServers.monk = {command: $c, args: ["mcp-stdio", "--url", $u]}' "$mcp_cfg" >"$tmp"
    else
      jq -n --arg c "$mcp_agent_path" --arg u "$server_url" \
        '{mcpServers: {monk: {command: $c, args: ["mcp-stdio", "--url", $u]}}}' >"$tmp"
    fi
  elif command -v python3 >/dev/null 2>&1; then
    if [ "$has_existing" = "1" ]; then
      python3 -c '
import json, sys
with open(sys.argv[1], encoding="utf-8") as handle:
    cfg = json.load(handle)
servers = cfg.get("mcpServers")
if not isinstance(servers, dict):
    servers = {}
cfg["mcpServers"] = servers
servers["monk"] = {"command": sys.argv[2], "args": ["mcp-stdio", "--url", sys.argv[3]]}
json.dump(cfg, sys.stdout, indent=2)
print()
' "$mcp_cfg" "$mcp_agent_path" "$server_url" >"$tmp"
    else
      printf '{"mcpServers":{"monk":%s}}\n' "$entry_json" >"$tmp"
    fi
  else
    rm -f "$tmp"
    echo "Add monk to $mcp_cfg to enable Antigravity MCP (jq or python3 required to auto-write):" >&2
    printf '  {"mcpServers":{"monk":%s}}\n' "$entry_json" >&2
    return 0
  fi
  mv "$tmp" "$mcp_cfg"
  echo "Registered monk MCP server in $mcp_cfg" >&2
}
