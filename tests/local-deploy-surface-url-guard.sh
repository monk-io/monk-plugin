#!/usr/bin/env sh
# Coding agents currently assume project.deploy returns a URL (#300). It
# often does not. Local web services also need host-port; ingress-routes
# alone leaves the app unreachable. Every instruction surface must say so,
# and the two packaged SKILL copies must stay identical.
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
  "$repo/.antigravity-plugin/skills/monk/SKILL.md"
do
  require "$f" 'no URL'
done

require "$repo/agents/monk-editor.md" 'host-port'
require "$repo/agents/monk-editor.md" 'unreachable'
require "$repo/skills/monk/SKILL.md" 'http://127.0.0.1:'
require "$repo/plugins/monk/skills/monk/SKILL.md" 'http://127.0.0.1:'
