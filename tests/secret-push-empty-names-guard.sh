#!/usr/bin/env sh
# Coding agents read these files before calling monk.secret.push.
# names: [] is treated as "push every local vault secret" (#331), not a no-op.
# Every instruction surface must say so, and the two packaged SKILL copies
# must stay identical.
set -eu

repo="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"

cmp "$repo/skills/monk/SKILL.md" "$repo/plugins/monk/skills/monk/SKILL.md"
cmp "$repo/skills/monk/references/agent-workflow.md" \
  "$repo/plugins/monk/skills/monk/references/agent-workflow.md"

require() {
  file="$1"
  needle="$2"
  if ! grep -F -q "$needle" "$file"; then
    echo "missing '$needle' in $file" >&2
    exit 1
  fi
}

for f in \
  "$repo/skills/monk/SKILL.md" \
  "$repo/plugins/monk/skills/monk/SKILL.md" \
  "$repo/skills/monk/references/agent-workflow.md" \
  "$repo/plugins/monk/skills/monk/references/agent-workflow.md" \
  "$repo/agents/monk-deployer.md" \
  "$repo/agents/monk-frontman.md" \
  "$repo/.antigravity-plugin/skills/monk/SKILL.md" \
  "$repo/.antigravity-plugin/rules/monk-safety.md"
do
  require "$f" 'names: []'
  require "$f" 'entire local vault'
done
