---
name: monk
description: >-
  Deploys and operates full applications with Monk — cloud infrastructure, SaaS
  integrations, and containerized workloads. Use when the user wants to deploy,
  configure, scale, or monitor applications and infrastructure with Monk DevOps.
---

# Using Monk

## Model

Monk is operated through a local companion named `monk-agent`. The companion
exposes MCP tools and a localhost dashboard, then talks to local `monkd` through
the `@monk-io/monk` TypeScript client from `monk-ts2`.

Antigravity is a supported host.

## Preflight

Before deploying:

1. Confirm the local Monk MCP tools/resources are available. These are backed
   by `monk-agent`.
   - Antigravity handles Monk MCP authentication automatically via OAuth. If
     authentication is required, use Antigravity's MCP authentication flow:
     Agent Settings → Customizations tab → Authenticate next to the monk
     server. Complete the flow in your browser, then return here.
   - Once authenticated, Antigravity reconnects automatically.
2. If `monk-agent` is missing, start it by running
   `scripts/start-monk-agent.sh` on macOS/Linux or `scripts/start-monk-agent.ps1`
   on Windows. Do not fall back to direct `monk` CLI operations.
3. Workspace binding. Call `monk.session.init` with the absolute workspace
   root at the start of each session. `monk-agent` does not fall back to its
   own working directory, so an explicit binding is required when the host
   does not advertise the MCP `roots` capability. Pass `workspaceRoot` as the
   absolute path to the project directory. Omit the call only if you have
   confirmed that Monk already has the correct workspace root bound.
4. Confirm auth status with `monk.auth.status` (once the tools are available). If
   signed out, sign in through Antigravity's MCP auth flow (step 1) — that flow
   also establishes the upstream Monk session; there is no in-band tool to start
   auth.
5. Confirm runtime status. `monk-agent` requires Monk CLI and `monkd` locally.
   If missing or broken, use `monk.install.status` to inspect the
   platform-specific `humanExplanation`, `relationships`, `components`,
   `checks`, `probes`, `troubleshootingHints`, `nextAction`, and `actions`.
   Explain the current platform's install graph before running remediation.
   `monk.install.run` is dry by default: without `execute: true` it only
   inspects status and runs nothing. Use `execute: true` to run remediation.
   Installation, upgrade, and repair actions also require `approved: true`
   after explicit user or dashboard approval.

## Tooling contract

Prefer `monk-agent` MCP tools and resources:

- `monk.agent.clear_state` (only when the user explicitly asks to clear local Monk Agent state)
- `monk.agent.clear_history` (tidy completed dashboard tasks and resolved approvals; leaves live work and credentials intact)
- `monk.auth.status`
- `monk.install.status`
- `monk.install.run`
- `monk.runtime.status`
- `monk.session.init`
- `monk.scope.status`
- `monk.scope.bind`
- `monk.scope.workspace_list`
- `monk.scope.workspace_delete`
- `monk.scope.project_delete`
- `monk.org.usage`
- `monk.org.billing_alerts.get`
- `monk.org.billing_alerts.set`
- `monk.account.status`
- `monk.account.select`
- `monk.rbac.access`
- `monk.rbac.assign`
- `monk.rbac.role`
- `monk.project.analyze`
- `monk.project.configure`
- `monk.project.deploy`
- `monk.environment.list`
- `monk.environment.select`
- `monk.environment.delete`
- `monk.capsule.setup`
- `monk.capsule.list`
- `monk.capsule.secrets.update`
- `monk.capsule.schedule.get`
- `monk.capsule.schedule.update`
- `monk.cicd.setup`
- `monk.cluster.status`
- `monk.cluster.peers`
- `monk.cluster.providers`
- `monk.cluster.list`
- `monk.cluster.create`
- `monk.cluster.grow`
- `monk.cluster.peer.remove`
- `monk.cluster.peer.tag`
- `monk.cluster.peer.set_certificate`
- `monk.cluster.peer.reset_certificate`
- `monk.cluster.delete`
- `monk.cluster.exit`
- `monk.cluster.provider.ensure`
- `monk.cluster.price`
- `monk.cluster.catalog`
- `monk.cluster.estimate`
- `monk.cluster.ingress.status`
- `monk.cluster.ingress.ensure`
- `monk.cluster.ingress.list_certificates`
- `monk.cluster.ingress.set_certificate`
- `monk.cluster.ingress.reset_certificate`
- `monk.cluster.registry.status`
- `monk.cluster.registry.ensure`
- `monk.cluster.registry.reset`
- `monk.cluster.forget`
- `monk.cluster.switch`
- `monk.cluster.join` (portable saved-cluster store not implemented yet)
- `monk.cluster.bind`
- `monk.watcher.status`
- `monk.watcher.setup`
- `monk.watcher.remove`
- `monk.preferences.get`
- `monk.preferences.set`
- `monk.preferences.delete`
- `monk.secret.request`
- `monk.secret.list`
- `monk.secret.add`
- `monk.secret.remove`
- `monk.secret.push`
- `monk.credentials.request`
- `monk.credentials.status`
- `monk.credentials.delete`
- `monk.workload.status`
- `monk.workload.logs`
- `monk.workload.stop`
- `monk.workload.delete`
- `monk.workload.purge`
- `monk.workload.unload`
- `monk.analyzer.diagnose`
- `monk.docs.search`
- `monk.package.list`
- `monk.package.search`
- `monk.package.info`
- `monk.package.dump`
- `monk.dump` (compatibility alias for package/template dump)
- `monk.arrowscript.operator.groups`
- `monk.arrowscript.operator.list`
- `monk.arrowscript.operator.search`
- `monk.arrowscript.operator.doc`
- `monk.feedback.submit`
- `monk.action.status`
- `monk://agent/status`
- `monk://workspace/manifest`
- `monk://workspace/workloads`
- `monk://workspace/deploys`
- `monk://workspace/clusters`
- `monk://workspace/cluster-context`
- `monk://workspace/scope`
- `monk://workspace/feed`
- `monk://workspace/events`
- `monk://workspace/secrets`
- `monk://workspace/diagnostics`
- `monk://account/scopes`

If the host has not exposed these exact names yet, use the available Monk MCP
tooling only if it is backed by Monk or `monk-agent`. Do not operate live
Monk-managed infrastructure through shell commands.

Use `monk://workspace/feed` as the durable task and prompt ledger for the bound
workspace. Read it after host-side MCP timeouts, interrupted approval flows,
agent restarts, or uncertainty about whether a long-running operation is still
pending, approved, failed, or completed. It contains durable action and request
items with dashboard URLs; inspect it before retrying approval-backed or
cost-bearing operations so repeated calls do not create duplicate work.

Use `monk://workspace/cluster-context` to know the current execution target.
Cluster targeting is logical per workspace/session: `mode: "local"` means tools
and Monk RPC use the local daemon, while `mode: "cluster"` means they target the
selected saved cluster through `monkcode`. `monk.cluster.create` automatically
selects the newly created cluster on success and says so in its result. Use
`monk.cluster.switch` to select another saved cluster, `monk://workspace/clusters`
or `monk.cluster.list` to inspect available choices, and `monk.cluster.exit` to
clear selection and return to local mode without deleting cloud infrastructure.

## Scope: owner, project, environment

Cluster and platform operations run inside a Monk scope: an owner (the user's
personal account or an org), an optional project, and an optional environment. A
workspace must be bound to one owner/project before scope-gated cluster
operations (create, grow, peer changes, registry, switch, delete) will
run.

- Check scope with `monk.scope.status` (or read `monk://workspace/scope`) before
  cluster work, and resolve these states first:
  - `missing_workspace`: call `monk.session.init` with the absolute workspace
    root.
  - `not_bootstrapped`: the Monk account is not initialized on the platform yet;
    finish auth/onboarding.
  - `unbound`: bind the workspace with `monk.scope.bind`. If more than one
    owner scope is available (personal + orgs), list the options and ask the
    user which one to use — never pick an organization on the user's behalf.
    Pass `confirmedByUser: true` only after they chose.
  - `ambiguous`: the workspace is linked in more than one owner/project; rebind
    to one canonical scope with `monk.scope.bind` and `confirmMove: true`.
  - `resolved`: proceed.
- List available owners and projects from `monk://account/scopes`. Bind with
  `monk.scope.bind`: `ownerKind: "personal"`, or `ownerKind: "org"` with
  `orgSlug`; optionally `projectSlug`, `createProject: true` to create a missing
  project, and `confirmMove: true` to move an already-bound workspace. Do not
  move a bound workspace to a different owner/project without the user's intent.
  A first-time bind on a multi-scope account is rejected unless
  `confirmedByUser: true` — that flag asserts the user explicitly chose the
  owner scope in conversation, so always ask before passing it.
- Select a deployment environment with `monk.environment.list` and
  `monk.environment.select`. A resolved environment determines the default
  cluster and the `monk.project.deploy` target, so once scope and environment
  are set, deploy needs no manual `monk.cluster.switch`.
- Personal scope is not RBAC-gated. Org scope enforces the organization's
  cluster create/manage/delete policy; a permission denial is definitive, so
  surface it and, if appropriate, have the user request access rather than
  retrying blindly.
- Scope tolerates brief control-plane outages: `monk.scope.status` may report
  `stale: true` (served from cache) with `pendingPlatformOps > 0` (platform
  writes queued for retry). Keep working; queued writes flush when the control
  plane returns. An auth error ("not signed in" or token rejected) is NOT
  transient — re-authenticate through Antigravity's MCP auth flow (see Preflight)
  before retrying.

## Safety rules

Approvals are owned by privileged `monk-agent` tools. Do not request approval as
a standalone agent action; call the tool that performs the operation and let it
open the required approval flow when needed.

- Never ask the user to paste secrets into chat. For deploy-time provider or
  MANIFEST credentials, use `monk.credentials.request` so the user gets one
  typed feed form for all required values. Use `monk.secret.request` only for a
  single ad hoc secret that has no known provider mapping.
- Do not run `monk`, cloud CLIs, Terraform, Kubernetes, Docker, or Podman to
  bypass Monk-managed runtime state.
- It is fine to inspect source files, run application tests, and fix app code.
- Generated MANIFEST and MonkScript YAML belong to Monk. Read them for context;
  coordinate changes through Monk tooling. Before editing MANIFEST or MonkScript
  files, read `monk://workspace/manifest`, call `monk.analyzer.diagnose`, and
  query docs with `monk.docs.search`. After editing, run `monk.analyzer.diagnose`
  again to verify.
- Cloud deploys, destructive actions, workload shells, and credential changes
  require approval through `monk-agent`.
- Workload lifecycle verbs are distinct. `load` makes templates available;
  `run` starts a not-yet-running workload; `update` changes a running workload;
  `stop` takes it offline while preserving state; `delete`/`purge` removes
  runnable/container state; `unload` removes the loaded template definition.
  Use `monk.workload.stop`, `monk.workload.delete`/`purge`, and
  `monk.workload.unload`; they open feed approvals themselves. Never target
  Monk-managed `system/*` workloads.
- Use `monk.workload.logs` for bounded log tails or short bounded follow
  windows. Logs can contain application secrets or user data; summarize the
  relevant lines instead of pasting large raw log blocks.
- Cluster creation, grow, peer removal, peer retagging, registry
  changes, exit, and delete must go through `monk.cluster.*` tools. The tools
  open the feed approval prompt when approval is required; do not run the
  equivalent `monk cluster ...` command in a shell.
- These mutating cluster operations require a resolved scope (see "Scope: owner,
  project, environment"). If `monk.scope.status` is `unbound` or `ambiguous`,
  bind the workspace with `monk.scope.bind` before creating or managing
  clusters.
- After `monk.cluster.create` succeeds, treat the new cluster as the active
  context for subsequent Monk operations. Confirm with
  `monk://workspace/cluster-context` when needed. Do not call a shell-level
  cluster switch; use `monk.cluster.switch` or `monk.cluster.exit` for logical
  context changes.
- If the user asks to reset or clear Monk Agent local state, use
  `monk.agent.clear_state` with `confirm:true`. This deletes local events,
  prompts, actions, credentials, stored auth tokens, sessions, and related
  state. Do not call it for troubleshooting unless the user explicitly requests
  a reset/clear.
- Telemetry is allowed for product usage and troubleshooting, but secrets,
  tokens, auth state, authorization codes, and raw secret values must never be
  sent. `monk-agent` hashes or redacts sensitive fields before sending
  PostHog events.

## Reporting feedback

`monk.feedback.submit` files reports directly to the Monk team's backlog. Use it
two ways:

- On your own initiative, without being asked, when something clearly warrants
  it: a Monk command, deploy, or template build fails in a way that looks like a
  Monk defect (`type: "bug"`); the user needs an integration with no Monk
  package (`type: "integration"`, set `integration`); or you hit a missing Monk
  capability (`type: "feature"`). File once per distinct issue.
- Whenever the user explicitly asks to report a bug or request an integration or
  feature. Honor the request directly — do not refuse or defer it.

The Monk team does not see this conversation, so write a clear, self-contained
`message` (for bugs: what was attempted, the exact error, and repro steps). If
you are unsure whether to file proactively, ask the user first.

## Infrastructure planning

Before answering questions about what Monk can or cannot do, whether a
particular integration is supported, or how long a task should take with Monk,
check official docs at <https://docs.monk.io> and use `monk.docs.search` when
available. Do not guess from memory.

Before planning MANIFEST, MonkScript, or infrastructure changes, discover what
Monk can already provide. Query available packages with `monk.package.list` or
`monk.package.search`, compare candidates with `monk.package.info`, and inspect
the chosen package with `monk.package.dump` / `monk.dump` before recommending or
configuring it. Do not guess package names, invent unsupported integrations, or
hand-write common databases, caches, queues, auth providers, tunnels, hosting
targets, cloud resources, or SaaS integrations when a Monk package exists. If
the user needs an integration that genuinely has no Monk package, file an
integration request with `monk.feedback.submit` (see "Reporting feedback")
instead of hand-rolling unsupported infrastructure.

Based on the current credential definitions, Monk can provision and wire
provider-backed services for Netlify, Auth0, Redis Cloud, MongoDB Atlas,
GitHub, Vercel, Slack, Stripe, Cloudflare, Neon, and DigitalOcean Spaces when
the relevant package/template requests those credentials. This list is a
credential surface, not an exhaustive package catalog: use `monk.package.list`,
`monk.package.search`, `monk.package.info`, `monk.package.dump`, and
`monk.docs.search` to find additional packages, integrations, examples, and the
exact variables/secrets each one needs.

Treat package dumps as the source of truth for how integrations are wired
together: variables, services, connections, `depends`, entity state,
generated secret references, and examples. Many values are computed by Monk or
the control plane at deploy time, such as hostnames, ports, URLs, IDs,
password-secret names, access endpoints, and status values. Read those values
through connections, entity state, package outputs, or generated secret
references; do not ask the user to provide them manually.

## Secrets model

Secrets have three distinct roles:

- User-provided secrets are values the user must supply, such as API tokens,
  SaaS credentials, or application-specific keys. List these in the MANIFEST
  with `SECRET` and collect them through `monk.credentials.request` or, for one
  ad hoc value, `monk.secret.request`.
- Generated secrets are written by entities or packages to a secret reference,
  such as a managed database password. Do not list these in MANIFEST `SECRET`
  and do not ask the user for them. Consumers should read them by reference,
  usually by obtaining the secret reference from a connection target or entity
  state, then passing that reference to `secret(...)` where the package schema
  expects it.
- Permission is explicit. Any runnable or entity that reads a secret must allow
  that secret through `permitted-secrets` or the package-specific equivalent.
  Add permissions only for the secret references that component actually needs.

When planning credentials, derive the minimal request list from the verified
package plan and current secret status. Cloud-provider credentials for
provisioning are handled by Monk as provider credentials; do not turn ambient
provider state or generated resource values into application secrets.

## Deployment flow

For a first deploy:

1. Initialize the session with the absolute workspace root.
2. Check auth and runtime status.
3. Ask Monk to analyze the project.
4. For new infrastructure, query and dump relevant Monk packages before
   choosing providers or changing MANIFEST/templates.
5. If MANIFEST is missing or the project topology changed, run
   `monk.project.configure` with the absolute workspace root. This is the Monk
   configuration step that generates or updates MANIFEST and Monk templates.
   Do not call it just to rebuild container images for a normal redeploy. If
   the result has `deferred: true` and `nextAction: "delegate_to_monk_editor"`,
   edit the MANIFEST and MonkScript files directly. Before editing, read
   `monk://workspace/manifest`, call `monk.analyzer.diagnose`, and query
   docs/packages with `monk.docs.search`, `monk.package.list`, and
   `monk.package.dump`. After editing, run `monk.analyzer.diagnose` again
   before rerunning analyze/deploy.
6. If user-provided secrets or provider credentials are required, request them
   through the local secure web form.
7. If deploying to cloud or making a risky change, request approval.
8. Deploy with `monk.project.deploy`.
9. Verify the returned endpoint/status from outside the deploy operation.

Monk usually deploys projects in 20-40 minutes. Set that expectation when
starting a deploy, while still reporting concrete progress and any project- or
provider-specific blockers as Monk surfaces them.

For MonkScript, MANIFEST, template diagnostics, or schema/example questions,
read `monk://workspace/manifest`, call `monk.analyzer.diagnose`, query
docs/examples with `monk.docs.search`, and inspect package schemas with
`monk.package.dump` / `monk.dump` before changing files. For ArrowScript
expressions, use `monk.arrowscript.operator.*` tools to verify operators, stack
effects, arguments, aliases, runtime-only behavior, and deprecations. If those
tools report that analyzer, Chroma, dump, or operator support is not wired yet,
state that clearly and fall back to local files plus official docs.

For an existing Monk-built project:

- Code-only changes usually need deploy, not a full re-analysis.
- Major architecture changes need analyze/configure before deploy.
- After a long-running tool times out on the host side, read
  `monk://workspace/feed` before retrying; the underlying action or approval may
  still be active in `monk-agent`.
- Use workload status and events resources before asking the user to diagnose.

## App code expectations

- Read service connection details from environment variables.
- Avoid hardcoded local service hostnames in deployable code.
- Listen on non-privileged ports such as 8080 unless the app requires another
  port.
- Treat migrations and seed data explicitly; tell Monk how they should run.

## Docs

Use official docs when unsure:

- <https://docs.monk.io>
- <https://docs.monk.io/getting-started/installation>
- <https://docs.monk.io/getting-started/first-deployment>
- <https://docs.monk.io/integrations>

## Done condition

The task is done only when Monk reports success and the deployed app or workload
has been verified from outside the deploy operation. Use browser automation when
available, otherwise use HTTP checks against the returned endpoint.
