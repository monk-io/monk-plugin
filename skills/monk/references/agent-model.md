# Portable Monk Agent Model

The portable plugin should mirror the existing VS Code product shape without
depending on VS Code APIs.

## Frontman

`monk-frontman` is the default operator. It keeps state, chooses a specialist,
and explains progress. It should be status-aware: auth, install, runtime,
workspace, events, approvals, and workloads all affect the next action.

## Specialists

- `monk-installer`: install, upgrade, self-test, and remediation.
- `monk-deployer`: analyze/configure/deploy/verify loop and source-code
  remediation.
- `monk-editor`: MonkScript/MANIFEST diagnostics and template edits, using
  analyzer, Chroma-backed examples, Monk package browsing, and package dump
  access, and ArrowScript operator lookup exposed by `monk-agent`. Claude Code
  should route hands-on MANIFEST/template edits to this subagent instead of
  editing those files in the main agent.
- `monk-docs`: official docs, package/integration lookup, examples, and
  explanation.

## Future agent-served capabilities

`monk-agent` should eventually expose analyzer, Chroma, and Monk package/dump
access through stable tools, not autospin internals:

- `monk.analyzer.diagnose`
- `monk.docs.search`
- `monk.package.list`
- `monk.package.search`
- `monk.package.info`
- `monk.package.dump`
- `monk.dump`
- `monk.arrowscript.operator.groups`
- `monk.arrowscript.operator.list`
- `monk.arrowscript.operator.search`
- `monk.arrowscript.operator.doc`
- `monk://workspace/diagnostics`

Claude Code additionally has a PostToolUse hook that runs after edits to
MANIFEST or loaded Monk YAML files. The hook calls local `monk-agent` for
diagnostics and injects the result back into the model context. It is best-effort
and does not replace the MCP `monk.analyzer.diagnose` pull tool.

Early implementations may return `available:false` while preserving the public
contract.

See `monk-editor-tooling.md` for the detailed editor tool contract.
