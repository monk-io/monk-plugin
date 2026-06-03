# Monk Editor Tooling Contract

This captures the portable tool surface for a normal `monk-editor` subagent
that edits MANIFEST and Monk YAML files with analyzer, Chroma, Monk package
browsing, dump access, and ArrowScript operator lookup.

## Subagent Behavior

- Claude routes hands-on MANIFEST and Monk YAML changes to `monk-editor`.
- The subagent uses normal file tools for reads and edits.
- The subagent uses Monk MCP tools for analyzer diagnostics, Chroma docs/example
  retrieval, package browsing, package/template dumps, and ArrowScript operator
  lookup.
- Before planning new infrastructure or package-backed services, the subagent
  searches/lists packages and dumps candidate packages to understand variables,
  services, connections, generated state, generated secret references, and
  examples instead of guessing package names or wiring.
- The subagent keeps user-provided secrets separate from generated secret
  references. MANIFEST `SECRET` lists only values the user must supply; generated
  secrets are read by reference through connections/entity state and must be
  allowed with `permitted-secrets` or the package-specific equivalent.
- After meaningful edits, the subagent reruns analyzer diagnostics and keeps
  fixing errors before handoff.
- The subagent does not deploy, rebuild, collect secrets, create clusters, or
  modify application source code unless explicitly asked.

## Portable MCP Tools

`monk-agent` should expose these stable tools to the subagent:

- `monk.analyzer.diagnose`
  - Input: `workspaceRoot`
  - Output: analyzer availability plus diagnostics with file, line, severity,
    code, message, and source line when available.
- `monk.docs.search`
  - Input: `query`, optional `collection`
  - Collections: `docs`, `templates`, `entity-examples`
  - Output: Chroma search results with trimmed documents, metadata, URI, and
    distance.
- `monk.package.list`
  - Input: optional `prefix`, optional `all`
  - Output: available Monk package paths grouped or typed.
- `monk.package.search`
  - Input: free-form `query`
  - Output: ranked package paths. Multiple query words are AND-matched.
- `monk.package.info`
  - Input: package/template path, with or without `monk/` prefix.
  - Output: brief metadata and type.
- `monk.package.dump`
  - Input: package/template path, with or without `monk/` prefix.
  - Output: cleaned YAML dump suitable for schema and example inspection.
- `monk.dump`
  - Compatibility alias for `monk.package.dump`.
- `monk.arrowscript.operator.groups`
  - Input: none.
  - Output: available ArrowScript operator groups/categories and counts.
- `monk.arrowscript.operator.list`
  - Input: optional `group`.
  - Output: operators in the requested group, or a grouped overview when no
    group is provided.
- `monk.arrowscript.operator.search`
  - Input: `query`.
  - Output: matching operators by name, description, or documentation.
- `monk.arrowscript.operator.doc`
  - Input: operator `name`, for example `connection-hostname`.
  - Output: detailed operator documentation including category, description,
    stack effect, call-form arguments, examples, aliases, runtime-only note, and
    deprecation note when applicable.

The ArrowScript tool data should come from the same operator registry used by
the analyzer, equivalent to Autospin's `analysis/operators.ts`.

## Claude Hook

`hooks/monk-diagnostics.sh` is the push path for Claude Code. It runs after
`Edit`, `Write`, or `MultiEdit` on MANIFEST or loaded Monk YAML files, then
calls local `monk-agent` for analyzer diagnostics. The hook is best-effort and
should fail silently when `monk-agent` or analyzer support is unavailable.

The hook does not replace `monk.analyzer.diagnose`; the editor subagent should
still call the pull tool before editing, after meaningful edits, and before
handoff.
