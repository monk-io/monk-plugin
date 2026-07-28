#!/usr/bin/env sh
set -eu

repo_root=${1:-$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)}
tmp_dir=$(mktemp -d)
trap 'rm -rf "$tmp_dir"' EXIT

stub_agent=$tmp_dir/monk-agent
printf '%s\n' '#!/usr/bin/env sh' 'cat >/dev/null' 'exit 0' > "$stub_agent"
chmod +x "$stub_agent"
export MONK_AGENT_PATH=$stub_agent

assert_denied() {
  name=$1
  payload=$2
  hook=$3
  deny_pattern=$4

  output=$(printf '%s' "$payload" | sh "$hook")
  if ! printf '%s' "$output" | grep -Eq "$deny_pattern"; then
    printf 'expected denial for %s, got: %s\n' "$name" "$output" >&2
    exit 1
  fi
}

assert_allowed() {
  name=$1
  payload=$2
  hook=$3
  deny_pattern=$4

  output=$(printf '%s' "$payload" | sh "$hook")
  if printf '%s' "$output" | grep -Eq "$deny_pattern"; then
    printf 'expected allow for %s, got denial: %s\n' "$name" "$output" >&2
    exit 1
  fi
}

claude_hook=$repo_root/hooks/block-monk.sh
antigravity_hook=$repo_root/.antigravity-plugin/hooks/block-monk.sh

claude_deny='"permissionDecision"[[:space:]]*:[[:space:]]*"deny"'
antigravity_deny='"decision"[[:space:]]*:[[:space:]]*"deny"'

assert_denied direct-monk '{"tool_input":{"command":"monk deploy"}}' "$claude_hook" "$claude_deny"
assert_denied command-wrapper '{"tool_input":{"command":"command monk deploy"}}' "$claude_hook" "$claude_deny"
assert_denied env-wrapper '{"tool_input":{"command":"env monk deploy"}}' "$claude_hook" "$claude_deny"
assert_denied nested-shell '{"tool_input":{"command":"bash -lc \"monk deploy\""}}' "$claude_hook" "$claude_deny"
assert_denied which-substitution '{"tool_input":{"command":"$(which monk) deploy"}}' "$claude_hook" "$claude_deny"
assert_denied absolute-posix '{"tool_input":{"command":"/usr/local/bin/monk deploy"}}' "$claude_hook" "$claude_deny"
assert_denied windows-absolute '{"tool_input":{"command":"C:\\Users\\PC\\.monk\\bin\\monk.exe deploy"}}' "$claude_hook" "$claude_deny"
assert_denied direct-daemon '{"tool_input":{"command":"monkd version"}}' "$claude_hook" "$claude_deny"
assert_denied daemon-separator '{"tool_input":{"command":"echo ok; monkd"}}' "$claude_hook" "$claude_deny"
assert_denied daemon-home '{"tool_input":{"command":"~/.monk/bin/monkd"}}' "$claude_hook" "$claude_deny"
assert_denied powershell-inline '{"tool_input":{"command":"powershell.exe -Command monk deploy"}}' "$claude_hook" "$claude_deny"

assert_allowed similar-command '{"tool_input":{"command":"monkey deploy"}}' "$claude_hook" "$claude_deny"
assert_allowed data-argument '{"tool_input":{"command":"grep monk README.md"}}' "$claude_hook" "$claude_deny"
assert_allowed echo-data '{"tool_input":{"command":"echo monk"}}' "$claude_hook" "$claude_deny"
assert_allowed nested-data '{"tool_input":{"command":"bash -lc \"grep monk README.md\""}}' "$claude_hook" "$claude_deny"

assert_denied antigravity-direct-daemon '{"toolCall":{"name":"run_command","args":{"CommandLine":"monkd version"}}}' "$antigravity_hook" "$antigravity_deny"
assert_denied antigravity-command-wrapper '{"toolCall":{"name":"run_command","args":{"CommandLine":"command monk deploy"}}}' "$antigravity_hook" "$antigravity_deny"
assert_denied antigravity-nested-shell '{"toolCall":{"name":"run_command","args":{"CommandLine":"bash -lc \"monk deploy\""}}}' "$antigravity_hook" "$antigravity_deny"
assert_denied antigravity-powershell-inline '{"toolCall":{"name":"run_command","args":{"CommandLine":"powershell.exe -Command monkd"}}}' "$antigravity_hook" "$antigravity_deny"
assert_allowed antigravity-data-argument '{"toolCall":{"name":"run_command","args":{"CommandLine":"grep monk README.md"}}}' "$antigravity_hook" "$antigravity_deny"

printf 'POSIX block-monk post-filter tests passed.\n'
