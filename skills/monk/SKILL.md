---
name: monk
description: "Deploy and operate applications with Monk through the local monk-agent MCP companion. Use when the user wants to install Monk, sign in, analyze a project, deploy locally or to cloud, inspect workloads, provide secrets securely, or troubleshoot Monk-managed infrastructure. MVP hosts are Claude Code, Codex, and Cursor."
allowed-tools: Bash(*), Read, WebFetch, Task, mcp__monk__monk_auth_status, mcp__monk__monk_auth_start, mcp__monk__monk_install_status, mcp__monk__monk_install_run, mcp__monk__monk_runtime_status, mcp__monk__monk_session_init, mcp__monk__monk_project_analyze, mcp__monk__monk_project_configure, mcp__monk__monk_project_deploy, mcp__monk__monk_cluster_status, mcp__monk__monk_cluster_peers, mcp__monk__monk_cluster_providers, mcp__monk__monk_cluster_create, mcp__monk__monk_cluster_grow, mcp__monk__monk_cluster_shrink, mcp__monk__monk_cluster_peer_remove, mcp__monk__monk_cluster_peer_tag, mcp__monk__monk_cluster_delete, mcp__monk__monk_cluster_exit, mcp__monk__monk_cluster_price, mcp__monk__monk_cluster_registry_status, mcp__monk__monk_cluster_registry_ensure, mcp__monk__monk_cluster_registry_reset, mcp__monk__monk_cluster_forget, mcp__monk__monk_cluster_switch, mcp__monk__monk_cluster_join, mcp__monk__monk_secret_request, mcp__monk__monk_credentials_request, mcp__monk__monk_workload_status, mcp__monk__monk_analyzer_diagnose, mcp__monk__monk_docs_search, mcp__monk__monk_package_list, mcp__monk__monk_package_search, mcp__monk__monk_package_info, mcp__monk__monk_package_dump, mcp__monk__monk_dump, mcp__monk__monk_arrowscript_operator_groups, mcp__monk__monk_arrowscript_operator_list, mcp__monk__monk_arrowscript_operator_search, mcp__monk__monk_arrowscript_operator_doc
---

# Using Monk

## Model

Monk is operated through a local companion named `monk-agent`. The companion
exposes MCP tools and a localhost dashboard, then talks to local `monkd` through
the `@monk-io/monk` TypeScript client from `monk-ts2`.

Target hosts for the MVP are Claude Code, Codex, and Cursor. Other Agent Skills
clients are best-effort until tested.

## Preflight

Before deploying:

1. Confirm the local Monk MCP tools/resources are available. In the MVP these
   are backed by `monk-agent`.
   - Claude Code and Codex can show native MCP auth for Streamable HTTP
     servers. If the host reports Monk MCP authentication is required, use the
     host auth flow before falling back to `monk.auth.start`.
   - Claude Code: use `/mcp`.
   - Codex CLI: use `codex mcp login monk`.
2. If they are missing, use the installer workflow. Host install hooks should
   run `scripts/ensure-monk-agent.sh` on macOS/Linux or
   `scripts/ensure-monk-agent.ps1` on Windows. Do not fall back to direct `monk`
   CLI operations.
3. Initialize a session with `monk.session.init`. Always pass the absolute
   current project directory as `workspaceRoot`; do not let it default to the
   MCP server process working directory. Include the host/client name and
   plugin version when the host exposes them; `monk-agent` uses this for
   first-use plugin install and activation telemetry.
4. Confirm auth status. If signed out, start Monk auth and send the user to the
   local sign-in URL returned by `monk.auth.start`.
5. Confirm runtime status. `monk-agent` requires Monk CLI and `monkd` locally.
   If missing or broken, use `monk.install.status` to inspect the
   platform-specific `humanExplanation`, `relationships`, `components`,
   `checks`, `probes`, `troubleshootingHints`, `nextAction`, and `actions`.
   Explain the current platform's install graph before running remediation.
   Use `monk.install.run` only after approval, or send the user to the local
   dashboard install page returned by the host/tooling.

## Tooling contract

Prefer `monk-agent` MCP tools and resources:

- `monk.auth.status`
- `monk.auth.start`
- `monk.install.status`
- `monk.install.run`
- `monk.runtime.status`
- `monk.session.init`
- `monk.project.analyze`
- `monk.project.configure`
- `monk.project.deploy`
- `monk.cluster.status`
- `monk.cluster.peers`
- `monk.cluster.providers`
- `monk.cluster.create`
- `monk.cluster.grow`
- `monk.cluster.shrink`
- `monk.cluster.peer.remove`
- `monk.cluster.peer.tag`
- `monk.cluster.delete`
- `monk.cluster.exit`
- `monk.cluster.price`
- `monk.cluster.registry.status`
- `monk.cluster.registry.ensure`
- `monk.cluster.registry.reset`
- `monk.cluster.forget` (portable saved-cluster store not implemented yet)
- `monk.cluster.switch` (portable saved-cluster store not implemented yet)
- `monk.cluster.join` (portable saved-cluster store not implemented yet)
- `monk.secret.request`
- `monk.credentials.request`
- `monk.workload.status`
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
- `monk://agent/status`
- `monk://workspace/manifest`
- `monk://workspace/workloads`
- `monk://workspace/deploys`
- `monk://workspace/events`
- `monk://workspace/secrets`
- `monk://workspace/diagnostics`

If the host has not exposed these exact names yet, use the available Monk MCP
tooling only if it is backed by Monk or `monk-agent`. Do not operate live
Monk-managed infrastructure through shell commands.

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
  coordinate changes through Monk tooling. In Claude Code, use the
  `monk-editor` subagent for MANIFEST or MonkScript edits instead of editing
  them directly in the main agent.
- Cloud deploys, destructive actions, workload shells, and credential changes
  require approval through `monk-agent`.
- Cluster creation, grow, shrink, peer removal, peer retagging, registry
  changes, exit, and delete must go through `monk.cluster.*` tools. The tools
  open the feed approval prompt when approval is required; do not run the
  equivalent `monk cluster ...` command in a shell.
- Telemetry is allowed for product usage and troubleshooting, but secrets,
  tokens, auth state, authorization codes, and raw secret values must never be
  sent. `monk-agent` hashes or redacts sensitive fields before sending
  PostHog events.

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
targets, cloud resources, or SaaS integrations when a Monk package exists.

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
   Do not call it just to rebuild container images for a normal redeploy.
6. If user-provided secrets or provider credentials are required, request them
   through the local secure web form.
7. If deploying to cloud or making a risky change, request approval.
8. Deploy with `monk.project.deploy`.
9. Verify the returned endpoint/status from outside the deploy operation.

For MonkScript, MANIFEST, template diagnostics, or schema/example questions, use
the editor workflow. In Claude Code, delegate hands-on MANIFEST and template
edits to the `monk-editor` subagent. The editor should read
`monk://workspace/manifest`, call `monk.analyzer.diagnose`, query Chroma-backed
docs/examples with `monk.docs.search`, browse Monk packages with
`monk.package.list` / `monk.package.search` / `monk.package.info`, and inspect
package schemas with `monk.package.dump` / `monk.dump` before changing files.
For ArrowScript expressions, the editor should use
`monk.arrowscript.operator.*` tools to verify operators, stack effects,
arguments, aliases, runtime-only behavior, and deprecations. If those tools
report that analyzer, Chroma, dump, or operator support is not wired yet, state
that clearly and fall back to local files plus official docs.

For an existing Monk-built project:

- Code-only changes usually need deploy, not a full re-analysis.
- Major architecture changes need analyze/configure before deploy.
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
