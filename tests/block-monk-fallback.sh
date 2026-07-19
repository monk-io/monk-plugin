#!/bin/sh
set -eu

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
missing_agent="$repo_root/.definitely-missing-monk-agent"

run_case() {
  hook=$1
  format=$2
  name=$3
  command=$4
  expected=$5

  if [ "$format" = "antigravity" ]; then
    payload=$(COMMAND="$command" python3 - <<'PY'
import json
import os

print(json.dumps({
    "toolCall": {
        "name": "run_command",
        "args": {"CommandLine": os.environ["COMMAND"]},
    }
}))
PY
)
  else
    payload=$(COMMAND="$command" python3 - <<'PY'
import json
import os

print(json.dumps({"tool_input": {"command": os.environ["COMMAND"]}}))
PY
)
  fi

  output=$(MONK_AGENT_PATH="$missing_agent" "$repo_root/$hook" <<EOF
$payload
EOF
)

  case "$output" in
    *deny*) denied=yes ;;
    *) denied=no ;;
  esac

  if [ "$denied" != "$expected" ]; then
    printf '%s\n' "unexpected fallback decision for $hook / $name" >&2
    printf '%s\n' "command: $command" >&2
    printf '%s\n' "expected denied=$expected got denied=$denied" >&2
    printf '%s\n' "output: $output" >&2
    exit 1
  fi
}

for spec in \
  ".antigravity-plugin/hooks/block-monk.sh antigravity" \
  "hooks/block-monk.sh claude"
do
  set -- $spec
  hook=$1
  format=$2

  run_case "$hook" "$format" direct "monk status" yes
  run_case "$hook" "$format" double_quoted '"monk" status' yes
  run_case "$hook" "$format" single_quoted "'monk' status" yes
  run_case "$hook" "$format" backslash_escaped '\monk status' yes
  run_case "$hook" "$format" sudo "sudo monk status" yes
  run_case "$hook" "$format" after_separator "echo ok; monk status" yes
  run_case "$hook" "$format" harmless_argument "grep monk README.md" no
  run_case "$hook" "$format" harmless_word "monkey status" no
done

echo "block-monk fallback decisions are correct"
