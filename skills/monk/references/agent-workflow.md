# Agent Workflow

Use this sequence for the MVP:

Before answering Monk capability questions or estimating how long work will
take with Monk, check official docs at `docs.monk.io` and use
`monk.docs.search` when available.

1. Initialize session with workspace root.
2. Check `monk.auth.status`.
3. Check `monk.runtime.status`.
4. If signed out, the `monk.*` tools are absent — direct the user to the host MCP
   auth flow (`/mcp`, `codex mcp login monk`, or Cursor's MCP login) to sign in.
5. If runtime is missing, call `monk.install.status` and surface install steps.
6. Analyze the project.
7. For new infrastructure, package-backed services, or MANIFEST/template
   changes, query available Monk packages and dump candidate packages before
   choosing providers or writing configuration.
8. If MANIFEST is missing or topology changed, call `monk.project.configure`
   with the absolute workspace root. This generates or updates MANIFEST and
   Monk templates; normal code-only redeploys should skip it. If configure
   returns `deferred: true`, pass `handoff.task` to the `monk-editor` subagent
   and resume with analyze/deploy after the editor writes the files.
9. Derive required user-provided secrets from the package plan and MANIFEST.
   MANIFEST `SECRET` lists values the user must supply. Do not list generated
   secrets written by packages/entities; consumers should read generated secret
   references through connections/entity state and allow them with
   `permitted-secrets` or the package-specific equivalent.
10. Request deploy-time provider and MANIFEST credentials through
    `monk.credentials.request`; use `monk.secret.request` only for a single ad
    hoc secret with no provider mapping.
11. Deploy with `monk.project.deploy`; privileged tools open their own approval
    flow when needed.
12. Verify the app or workload externally.

For cluster work, first resolve scope: call `monk.scope.status` and, if the
workspace is `unbound` or `ambiguous`, bind it to an owner/project with
`monk.scope.bind` (`confirmMove: true` to move an already-bound workspace).
Mutating cluster operations require a resolved scope; org scope also enforces
the org's cluster RBAC policy. Optionally pick a target environment with
`monk.environment.list` / `monk.environment.select`. Then inspect with
`monk.cluster.status`, `monk.cluster.peers`,
`monk.cluster.providers`, `monk.cluster.registry.status`, and
`monk.cluster.price`. Change cluster state only with `monk.cluster.create`,
`monk.cluster.grow`, `monk.cluster.shrink`, `monk.cluster.peer.remove`,
`monk.cluster.peer.tag`, `monk.cluster.registry.ensure`,
`monk.cluster.registry.reset`, `monk.cluster.exit`, or
`monk.cluster.delete`. These tools trigger feed approvals themselves.
Use `monk://workspace/cluster-context` to understand whether operations target
local `monkd` or a saved cluster via `monkcode`. `monk.cluster.create`
automatically selects the created cluster on success. Use
`monk://workspace/clusters` or `monk.cluster.list` to inspect saved clusters,
`monk.cluster.switch` to select one logically, and `monk.cluster.exit` to clear
selection and return to local mode without deleting infrastructure.

For workload lifecycle cleanup, use `monk.workload.status` to inspect first,
then `monk.workload.stop`, `monk.workload.delete`/`purge`, or
`monk.workload.unload`. `stop` preserves runnable state; `delete`/`purge`
removes runnable/container state; `unload` removes the loaded template
definition. Do not operate on Monk-managed `system/*` workloads.

Credential-backed SaaS targets currently include Netlify, Auth0, Redis Cloud,
MongoDB Atlas, GitHub, Vercel, Slack, Stripe, Cloudflare, Neon, and
DigitalOcean Spaces. Use package and docs tools to find more and to verify the
exact wiring.

Never receive secret values in chat. Never bypass Monk runtime state with shell
commands.
