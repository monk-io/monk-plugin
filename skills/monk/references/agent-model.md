# Portable Monk Agent Model

The portable plugin should mirror the existing VS Code product shape without
depending on VS Code APIs.

## Frontman

`monk-frontman` is the default operator. It keeps state, chooses a specialist,
and explains progress. It should be status-aware: auth, install, runtime,
workspace, events, approvals, and workloads all affect the next action.

## Specialists

- `monk-installer`: install, upgrade, self-test, and remediation.
- `monk-deployer`: analyze/build/deploy/verify loop and source-code remediation.
- `monk-editor`: MonkScript/MANIFEST diagnostics and template edits, using
  analyzer and Chroma-backed examples exposed by `monk-agent`.
- `monk-docs`: official docs, package/integration lookup, examples, and
  explanation.

## Future agent-served capabilities

`monk-agent` should eventually expose analyzer and Chroma access through stable
tools, not autospin internals:

- `monk.analyzer.diagnose`
- `monk.docs.search`
- `monk://workspace/diagnostics`

Early implementations may return `available:false` while preserving the public
contract.
