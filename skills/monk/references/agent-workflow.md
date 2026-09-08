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
   To sign in as a different Monk user, `monk.auth.logout` first (a host-side
   logout leaves `monk-agent` signed in, so the next sign-in silently reuses the
   same account), then re-run the host auth flow — the host may still list the
   server as authenticated, so re-authenticate explicitly. Personal-vs-org
   context within the same user is `monk.account.select`, not a logout.
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
`monk.cluster.grow`, `monk.cluster.peer.remove`,
`monk.cluster.peer.tag`, `monk.cluster.registry.ensure`,
`monk.cluster.registry.reset`, `monk.cluster.exit`, or
`monk.cluster.delete`. These tools trigger feed approvals themselves.
Use `monk://workspace/cluster-context` to understand whether operations target
local `monkd` or a saved cluster via `monkcode`. `monk.cluster.create`
automatically selects the created cluster on success. Use
`monk://workspace/clusters` or `monk.cluster.list` to inspect saved clusters,
`monk.cluster.switch` to select one logically, and `monk.cluster.exit` to clear
selection and return to local mode without deleting infrastructure.

In local mode (nothing selected yet), `monk.cluster.status` reports a
`liveCluster` field when `monkd` is already connected to a cluster that isn't
in this workspace's saved list — created via the CLI, or before the plugin
was installed. `monk.cluster.list` alone won't show it. When you see it,
offer the user `monk.cluster.bind` (defaults to this workspace's own bound
org/project if it has one, personal otherwise; pass `orgSlug` to target a
different org) or `monk.cluster.switch` by that cluster's name to adopt it —
both trigger a dashboard approval before registering it, since its identity
is self-reported by the daemon and cannot be verified against the platform.
Do not register it silently or assume the user wants it adopted.

For workload lifecycle cleanup, use `monk.workload.status` to inspect first,
then `monk.workload.stop`, `monk.workload.delete`/`purge`, or
`monk.workload.unload`. `stop` preserves runnable state; `delete`/`purge`
removes runnable/container state; `unload` removes the loaded template
definition. Do not operate on Monk-managed `system/*` workloads.

Long-running cluster/deploy/configure calls (`monk.cluster.create`/`grow`/
`delete`, `monk.project.deploy`/`configure`, etc.) may return
`{ok: true, status: "running", actionId}` instead of a final result if they
outlast the tool call's own block budget — this is a normal, non-error
outcome, not a failure. Poll `monk.action.status` with that `actionId`
(`waitSeconds` to long-poll) until it reaches a terminal status, then continue
the workflow (e.g. `monk.cluster.list`/`status` to confirm a cluster now
exists). If the call instead surfaces a raw client-side timeout error with no
`actionId`, the operation may still be succeeding server-side — check
`monk.cluster.list`/`status` (or retry the same call, per the "do not
re-provision under a new name" guidance) before assuming it failed. Never fall
back to shell/local-file inspection to recover state that a `monk.*` tool
should provide (e.g. a cluster's `monkcode`, which `monk.cluster.create` and
`monk.cluster.bind` both return directly).

Credential-backed SaaS targets currently include Netlify, Auth0, Redis Cloud,
MongoDB Atlas, GitHub, Vercel, Slack, Stripe, Cloudflare, Neon, and
DigitalOcean Spaces. Use package and docs tools to find more and to verify the
exact wiring.

Never receive secret values in chat. Never bypass Monk runtime state with shell
commands.
