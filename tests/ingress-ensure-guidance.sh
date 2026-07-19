#!/bin/sh
set -eu

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)

check_contains() {
  file=$1
  pattern=$2

  if ! grep -Fq "$pattern" "$repo_root/$file"; then
    echo "missing expected ingress guidance in $file: $pattern" >&2
    exit 1
  fi
}

check_contains "agents/monk-deployer.md" "After calling \`monk.cluster.ingress.ensure\`, treat the action result as"
check_contains "agents/monk-deployer.md" "still shows \`enabled=false\`, unhealthy, zero ready instances"
check_contains "agents/monk-editor.md" "reports a succeeded action but"
check_contains "agents/monk-editor.md" "treat ingress as disabled"

for file in \
  "skills/monk/references/agent-workflow.md" \
  "plugins/monk/skills/monk/references/agent-workflow.md"
do
  check_contains "$file" "do not treat \`monk.cluster.ingress.ensure\`"
  check_contains "$file" "call \`monk.cluster.ingress.status\`"
  check_contains "$file" "surface that ingress remains"
done

echo "ingress ensure guidance is present"
