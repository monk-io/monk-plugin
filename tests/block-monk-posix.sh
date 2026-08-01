#!/usr/bin/env sh

set -eu

repo_root="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
missing_agent="${TMPDIR:-/tmp}/missing-monk-agent-$$"

run_case() {
  hook=$1
  format=$2
  name=$3
  command=$4
  expected=$5

  if [ "$format" = "claude" ]; then
    payload=$(printf '{"tool_input":{"command":"%s"}}' "$command")
    deny_marker='"permissionDecision": "deny"'
  else
    payload=$(printf '{"toolCall":{"name":"run_command","args":{"CommandLine":"%s"}}}' "$command")
    deny_marker='"decision": "deny"'
  fi

  output=$(printf '%s' "$payload" |
    MONK_AGENT_PATH="$missing_agent" sh "$hook")
  if printf '%s' "$output" | grep -Fq "$deny_marker"; then
    actual=deny
  else
    actual=allow
  fi

  if [ "$actual" != "$expected" ]; then
    printf '%s\n' "$format hook case '$name' expected $expected, got $actual" >&2
    printf '%s\n' "$output" >&2
    exit 1
  fi
}

run_suite() {
  hook=$1
  format=$2

  run_case "$hook" "$format" direct 'monk deploy' deny
  run_case "$hook" "$format" assignment 'MONK_X=1 monk deploy' deny
  run_case "$hook" "$format" empty-assignment 'MONK_X= monk deploy' deny
  run_case "$hook" "$format" repeated-assignments 'A=1 B=2 monk deploy' deny
  run_case "$hook" "$format" wrapper-assignment 'env MONK_X=1 monk deploy' deny
  run_case "$hook" "$format" repeated-wrappers 'command env MONK_X=1 monk deploy' deny
  run_case "$hook" "$format" assignment-path 'MONK_X=1 /usr/local/bin/monk deploy' deny
  run_case "$hook" "$format" lookalike 'MONK_X=1 monkey deploy' allow
  run_case "$hook" "$format" assignment-as-argument 'printf MONK_X=1 monk deploy' allow
  run_case "$hook" "$format" invalid-assignment-name '1MONK=1 monk deploy' allow
}

run_suite "$repo_root/hooks/block-monk.sh" claude
run_suite "$repo_root/plugins/monk/hooks/block-monk.sh" claude
run_suite "$repo_root/.antigravity-plugin/hooks/block-monk.sh" antigravity

printf '%s\n' 'POSIX block-monk fallback tests passed.'
