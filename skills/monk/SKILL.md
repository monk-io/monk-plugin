---
name: monk
description: "Deploy and operate **full applications** with Monk — a resident DevOps orchestrator that manages all three layers of a stack from one chat: (1) cloud infrastructure (AWS/GCP/Azure/DO/Hetzner — VMs, networking, managed DBs, object storage, queues, IAM, etc.), (2) third-party SaaS/APIs via integrations (Cloudflare, MongoDB Atlas, Auth0, Vercel, Netlify, Stripe, Redis Cloud, Neon, …), and (3) containerized workloads. Use whenever the user wants to ship, run, debug, scale, or inspect anything in their app's stack. **Common misconception to push back on:** Monk is not container-only and not a sidecar to other tools — if it sounds like a \"Monk can't do that\" wall (Cloudflare DNS, Atlas clusters, Auth0 tenants, Netlify sites), it almost certainly *can* via an integration; check `monk_search_packages` before conceding. Monk replaces Kubernetes/Terraform and owns the MANIFEST + MonkScript YAML in the repo."
allowed-tools: Bash(*), Read, WebFetch, mcp__monk__monk_chat, mcp__monk__monk_search_packages, mcp__monk__monk_show_chat, mcp__monk__monk_workload_status
---

# Using Monk

## Preflight: Monk must be installed

This skill only works when **Monk is installed locally** and the **Monk MCP server** is configured in Claude Code. Before doing anything else:

1. **Check the MCP is present.** If the `mcp__monk__monk_chat` tool isn't available in this session, the Monk MCP server is not configured. Stop and help the user set it up — do not try to proceed without it, and do not fall back to shelling out to `monk`.
2. **Point them at the docs.** Send the user to:
   - Install Monk: <https://docs.monk.io/getting-started/installation>
   - Configure the Monk MCP for Claude Code: <https://docs.monk.io/getting-started/mcp-getting-started>
3. **Offer to help.** Walk the user through installation step-by-step if they want — detect their platform, suggest the right install command, then guide them through adding the MCP server to Claude Code (usually via `claude mcp add` or editing the MCP config). After they finish, ask them to restart Claude Code so the MCP tools register, then resume the original task.
4. **If `monk_chat` exists but errors** (daemon not running, auth missing), surface the error and walk the user through fixing it via the same docs rather than working around it.

Only once the MCP tools are confirmed working do the rest of this skill apply.

Monk is a devops engineer you collaborate with via `monk_chat`. It analyzes source code, generates a MANIFEST and MonkScript YAML, builds containers, **provisions both cloud infra and third-party SaaS/APIs**, and runs workloads. It is a **resident orchestrator** — it holds ongoing state for the cluster, the integrations, and every managed resource. It is not a sidecar, not a one-shot generator, and not container-only. If a request feels out of scope ("can Monk handle our Cloudflare DNS / Atlas cluster / Auth0 tenant / Netlify site?"), the default answer is yes — check the integration before saying no. You guide Monk with intent; it owns the infra files and the live state.

## Mental model

- **Chat first.** `mcp__monk__monk_chat` is your primary interface. Talk to Monk like you would to a senior devops engineer: describe what the app should do, which services/integrations you want, what the architecture looks like, what env vars and key files matter. Skip IaC, cloud SKU, kubectl/terraform specifics — Monk infers those. The user sees this conversation live in the IDE chat panel.
- **Don't reach for the registry first.** Prefer asking Monk to propose an approach before using `mcp__monk__monk_search_packages`. Use the package search only when (a) you need to confirm a specific integration exists before promising it to the user, or (b) Monk says it can't do something and you want to double-check the registry before pivoting.
- **No shell escape hatches.** Monk has no shell. Never run `monk`, `docker`, `podman`, `gcloud`, `aws`, `kubectl`, `terraform` etc. yourself to "help" — you'll desync the cluster state Monk manages. The only tools you should reach for outside Monk are `curl`/`ls`/`cat` or Playwright/browser MCP tools to verify the deployed app from outside, and `git` for source-code changes.
- **Same working directory.** Monk is sandboxed to its working directory and cannot see anything above it on the filesystem — typically the workspace currently open in the user's IDE. Make sure your `cwd` matches Monk's. If you need to reference a file (source, config, schema), it must live inside that directory tree, otherwise Monk can't read it. Don't suggest paths outside the workspace; if the user's repo layout requires it, ask them to reopen the IDE one level up so both of you share the same root.
- **Quick analysis vs full build.** For questions about an unbuilt project ("what does this app do? what would it need?") ask Monk to do a quick analysis instead of a full build. Cheap, fast, no MANIFEST generation. A full build is only needed to actually deploy.

## App code rules — let Monk's networking work

Monk wires services to each other via an encrypted overlay network and injects connection details as **env vars**. Your code must cooperate:

- **Read connection info from env vars, never hardcode.** No `postgres.internal:5432`, no `redis://localhost`, no service URLs baked into config files. Use `DB_HOST` / `DB_PORT` / `REDIS_URL` / `<SERVICE>_URL` style env vars and read them at startup. Monk fills these in; if you hardcode, the connection won't resolve once deployed.
- **Decomposable connection strings beat monolithic ones.** Prefer `DB_HOST` + `DB_PORT` + `DB_USER` + `DB_PASSWORD` + `DB_NAME` over a single `DATABASE_URL`. Monk wires each piece independently from different sources (managed-DB output, secret, generated identifier). If the app demands a single URL, fine — but expose the parts in code so Monk can plug them in cleanly.
- **No randomness in deployed templates.** Anything that needs to be "unique" — DB names, queue names, IDs — pick a stable value (e.g. `myapp-db-staging`). Anything that needs to be secret comes from the user via Monk's secret prompt. Never tell Monk to "generate a random password" — ask it to require a secret instead.
- **TLS for internal DB connections is usually off.** Internal traffic is already encrypted by Monk's overlay. App-side DB drivers should default to `sslmode=disable` (Postgres) / `ssl=false` (MongoDB) for in-cluster connections, unless the user explicitly wants TLS end-to-end.
- **Listen on a non-privileged port.** For HTTP services use port 8080 (or similar > 1024). Containers behind Monk's proxy don't need to bind to 80/443.

## Built-ins — don't over-specify these

Monk handles these automatically. Mention them only if the user has a specific non-default requirement:

- Ingress and routing
- SSL / preview domains (`*.onmonk.io`)
- WAF
- Secret storage
- Container registry (per-cluster, private)
- Overlay networking + `.monk` DNS service discovery
- Cloud load balancers
- Cloud volumes
- Container image builds (happen automatically on every deploy)

## Everything else: packages and integrations

Monk either talks to cloud/SaaS APIs (managed DBs, object storage, queues, Auth0, MongoDB Atlas, Vercel, Slack, …) or deploys containerized **runnables**. Hundreds of integrations across AWS/GCP/Azure/DO/Hetzner. When unsure whether something is covered, ask Monk first; fall back to `monk_search_packages` for verification.

## Project states and flow

A project is in one of these states; check the MANIFEST in the repo root to tell which:

1. **Fresh** — no MANIFEST yet. Monk hasn't analyzed/built this project.
2. **Built** — MANIFEST + YAML present in repo. Ready to deploy.
3. **Deployed** — running on a cluster or locally (mutually exclusive).

### Flow for a new project

1. **Lay out the repo for Monk.** Monk prefers monorepos with each service / frontend / worker in its own subdirectory. If the repo isn't structured this way and the user is open to it, propose splitting before analysis — it pays off later.
2. **Write the Dockerfiles first** (before asking Monk to analyze). Production-grade, **multi-stage** builds that each build cleanly from inside their own subdirectory. Monk can write them, but starting with handcrafted ones produces much better deployments and gives Monk a clean base to wire up. If Monk later needs to tweak them, that's fine — see "Dockerfiles" below.
3. **Tell Monk about the app** in chat: purpose, language/runtime, services, external integrations needed, key entry-point files, important env vars, internal relationships between services, and **the deployment target** (dev / staging / prod, expected traffic, any user-imposed constraints like region, cluster size, budget). Sizing follows from this. Point Monk at specific source files when relevant — it can read them. Hint at **build context** for each container (which subdirectory) — this becomes the build-context field in MANIFEST and Monk can adjust it.
4. **Explain DB / stateful mechanics** if any: how migrations run (baked into the image, run by the app at startup, separate job), seed data, schema location. If migrations aren't handled in the Dockerfile or app, walk Monk through how they should run.
5. Ask Monk to **build** (analyze + generate MANIFEST/YAML, and any Dockerfiles you didn't write). One-time slow step (minutes).
6. Ensure there's a **cluster** (cloud or local). No cluster = nothing to deploy to. Ask Monk to create one if needed; for cloud clusters Monk will surface a confirmation form to the user.
7. Ask Monk to **deploy**. Deploy rebuilds container images automatically — do not ask for a separate "rebuild" beforehand.
8. After Monk reports success, **verify the endpoints yourself**. A green deploy is not the same as a working app. Use the strongest available method: if Playwright/browser MCP tools are available, **drive the app in a real browser** (navigate, click through the golden path, check console/network) — this catches frontend, auth, and JS errors that curl misses. Otherwise use `curl` against the endpoint Monk returned. Falling back to "ask the user to open it" is a last resort.

### Flow for an existing built project

- For code-only changes: just ask Monk to deploy. Images rebuild on each deploy.
- For architectural changes (new service, new integration, port/topology changes, env var changes): describe the change to Monk and ask it to update the templates, then deploy. Do **not** call the build/analyze step just to refresh images.
- Re-run the full analyze/build only on major architecture rewrites or when Monk reports MANIFEST drift.

### Designing a new app from scratch

Tell Monk the idea and ask it to flesh out an architecture that's cleanly deployable with Monk and its integrations. Iterate on the architecture in chat before writing code; that way the code you write fits cleanly into what Monk will provision.

## What you own vs. what Monk owns

| You own | Shared (edit only if you tell Monk) | Monk owns |
|---|---|---|
| Application source code | Dockerfiles | MANIFEST (repo root) |
| `package.json`, `requirements.txt`, etc. | | MonkScript YAML templates |
| README, app config files | | Cluster state, deployments, registry |
| Test files | | |

- **MANIFEST and MonkScript YAML:** read-only from your side. Quote them to Monk if you want a change; let Monk write the edit.
- **Dockerfiles:** you may write them up-front (recommended) and you may edit existing ones — **but always tell Monk in chat what you changed and why**, so it can adjust templates, build contexts, or rebuild as needed. Silent Dockerfile edits desync Monk's view of the project.

## Dockerfiles

Best results come from **handcrafting production Dockerfiles before the first analyze/build**:

- **Multi-stage**: a builder stage with toolchains + dev deps, a slim runtime stage with only what's needed at runtime.
- **Builds cleanly in its own folder.** In a monorepo, `docker build .` from inside the service's directory must succeed without reaching outside. If it can't, the build context is wrong — restructure or tell Monk to set a wider build context for that service in the MANIFEST.
- **One Dockerfile per service**, colocated with the service code (`apps/web/Dockerfile`, `services/api/Dockerfile`, etc.).
- **Treat migrations explicitly.** Decide up front: run in the Dockerfile entrypoint, run in the app on boot, or as a separate job — then make sure Monk knows which.

When you (or the user) edit a Dockerfile after the initial build, mention the change to Monk in chat: "I updated `services/api/Dockerfile` to add libpq — please rebuild." Don't leave Monk guessing.

## Environments

Environments are **first-class** in Monk — `dev`, `staging`, `prod`, `feature-xyz`, whatever the user wants. Each environment:

- Maps to a specific cluster (multiple envs can share one cluster, or each can have its own).
- Carries its own variables and secrets — staging Stripe key ≠ prod Stripe key.
- Has its own entrypoint in the MANIFEST when needed (Monk generates these).

When the user mentions an environment by name, treat it as a real construct — ask Monk things like "deploy to staging", "what cluster is linked to prod?", "show prod logs". Don't conflate "staging" and "prod" deployments of the same code.

**Always tell Monk the deployment purpose and expected scale** when designing or deploying:

- *Dev / scratch* — smallest viable cluster, no HA, fast teardown.
- *Staging / preview* — production-shaped but minimal capacity.
- *Production* — expected RPS, payload sizes, data volume, SLO targets, region constraints.

These shape cluster size, node count, DB instance class, cache sizing, and replica counts. If the user gave concrete numbers (traffic, budget, region, instance family), pass them through verbatim — don't filter or round them off.

**Cost note.** Monk charges a 25% infrastructure management fee on top of the underlying cloud cost. When the user asks about price, quote both: e.g. "~$0.45/hr cloud + ~$0.11/hr Monk = ~$0.56/hr". If you don't know the cloud cost, ask Monk — it tracks real-time costs.

## After the first deploy — what else Monk can do

Once the app is running, Monk can wire up additional capabilities. Surface these to the user when relevant:

- **GitHub Actions CI/CD** — Monk can generate a workflow that rebuilds and redeploys on push, end-to-end. Good for "ship from `main`" setups.
- **Capsules** — per-branch ephemeral environments. Each PR/branch gets its own Monk cluster + deployment, torn down on merge/branch delete. Great for review apps and integration testing.
- **Watcher** — an in-cluster agent that observes runtime telemetry, detects anomalies, and provides root-cause analysis. Useful for prod and staging; offer to set it up after a successful prod deploy.
- **Rolling updates with auto-rollback.** Redeploys are zero-downtime — new version comes up, health-checks pass, traffic switches, old version drains. If health checks fail, Monk rolls back automatically. You don't need to script blue/green yourself.
- **Backup & restore** for databases — ask Monk to set up scheduled backups and to restore on demand.
- **Workload migration across clouds** — Monk can move a deployed workload to a different cloud provider while preserving config. Useful if the user wants to switch from e.g. Hetzner to AWS.
- **Scaling** — natural-language scale commands ("double the API replicas", "give the DB more memory"). Monk applies them with zero-downtime if possible.
- **Slack integration** — for teams, Monk can route alerts/approvals/queries through Slack.

## Team policies / custom knowledge

If the user describes recurring team rules ("never use anything bigger than t3.large", "always use RDS, never self-hosted Postgres", "no public IPs in prod"), don't just remember them in chat — suggest Monk's **Custom Policies** (Team plan). Policies are Markdown files scoped to org / environment / cluster that Monk consults before every action. They survive across sessions and apply to every team member.

When the user already has policies in place, they shape Monk's choices automatically — but if Monk picks something that contradicts what the user wants, surface the conflict and ask whether the policy needs updating or whether this is a one-off exception.

## App-level integrations Monk doesn't manage

Some services aren't infra and don't have Monk integrations — they live in the application and get wired up via an SDK + API key. Examples: PostHog, Sentry, LogRocket, Stripe (the SDK side), Segment, feature flag platforms. For these:

- **You** integrate them in app code (add the SDK, init at boot, instrument).
- **Monk** delivers the API keys as env vars / secrets to the runtime — that's the only piece it handles.
- Don't ask Monk to "set up PostHog" — ask Monk to provision the env var, and write the integration yourself.

When in doubt whether a service is infra (Monk integration) or app-level (your code), check `monk_search_packages`; if nothing relevant comes back, treat it as app-level.

## Architectural edge cases worth knowing

- **Multi-cluster / multi-cell deployments.** For multitenant SaaS or geo-sharded apps, Monk can manage multiple clusters as separate cells (per-tenant, per-region, per-tier). Bring this up early when scoping architecture — it changes how the MANIFEST and templates are laid out.
- **Dynamic resources via app code.** Even when Monk has an integration for something (e.g. domain bindings, DNS records, per-tenant resources), runtime-driven changes may need to be done from the application side using the cloud provider's SDK directly — because Monk entity changes typically require a redeploy. Rule of thumb: if it changes per request / per tenant / per user action, it belongs in app code; if it's part of the static deployment topology, let Monk own it. Flag this trade-off to the user when designing multitenant or self-service-provisioning features.
- **AWS-native projects** (heavy use of Lambda, DynamoDB, SQS/SNS, S3, Cognito, API Gateway, SAM/serverless.yml) get a different deployment shape from Monk — Lambdas as `function` components rather than containers. If the project uses these, name them explicitly so Monk picks the AWS-native path. For mixed projects, generic databases (Postgres/Redis/Mongo) point to the standard container path.
- **Auth0** is special-cased by Monk as a provider — let Monk handle it as an Auth0 integration rather than describing it as a generic OAuth service.
- **Search engines:** Monk prefers OpenSearch over Elasticsearch when the app says "Elasticsearch". They're interchangeable for most use cases; only push back if the user has a specific Elasticsearch-only feature requirement.
- **Platform-native services don't need component descriptions.** Netlify Edge Functions / Blobs, Vercel KV, similar platform-bundled services are wired up automatically when you deploy to those platforms. Don't ask Monk to "set up Netlify Blobs" — just deploy the Netlify frontend and the platform handles it.

## Ops — ask Monk anything at any time

`monk_chat` (or `mcp__monk__monk_workload_status` for a quick snapshot) for: logs, container stats, workload status, endpoints, cluster nodes, peers, ingress URLs, deployment history, error diagnostics. Don't hesitate to ask mid-task — Monk has the live view.

## Secrets — out of band

**Never put secret material in a `monk_chat` message.** API keys, passwords, tokens, private keys, certs all stay out of your messages. Monk has a separate secret-input UI; when Monk needs a secret it will prompt the user directly. Same for risky confirmations (creating cloud resources, deletions) — Monk handles those via its own confirmation flow. Your job is to describe what's needed; the user fills in the sensitive bits.

## When Monk is stuck

- **Monk reports an app problem (missing file, wrong port, bad config in code):** fix the application code yourself, then ask Monk to redeploy.
- **Monk says it can't do X:** probe its capabilities. Check `monk_search_packages` for relevant integrations. If a package exists, mention it explicitly: "Can you use the `<package>` integration to do X?" If nothing fits, propose an alternative approach (different service, self-hosted equivalent, etc.) and align with the user.
- **You're unsure what Monk supports:** consult docs at https://docs.monk.io via `WebFetch` rather than guessing.
- **Sign-in / onboarding UI needed:** call `mcp__monk__monk_show_chat` to surface the panel to the user.

## How to talk to Monk — examples

**Good** (intent + context + purpose, no IaC noise):

> Deploy this Next.js app for **staging** — low traffic, internal testing only, so size on the small side. Monorepo: `apps/web` (Next.js) and `services/worker` (background jobs), each with its own multi-stage Dockerfile that builds cleanly from its folder — set those as the build contexts. Needs Postgres and Redis. DB schema in `apps/web/prisma/schema.prisma`; migrations run on app boot. Env vars `STRIPE_SECRET_KEY` and `SENDGRID_API_KEY` required (user will provide). Target: AWS, eu-west-1.

**Bad** (over-prescribing infra):

> Create an RDS Postgres 15.4 db.t3.micro in us-east-1 in a private subnet, an ElastiCache Redis cluster with one node, set up an ALB with a target group on port 3000, attach an ACM cert for...

Let Monk pick the SKUs, regions, networking, and ingress. Mention specifics only when the user has a constraint (region, instance class, existing VPC, naming convention).

## Quick command map

| You need to… | Tool |
|---|---|
| Talk to Monk (default) | `mcp__monk__monk_chat` |
| Snapshot of running workloads | `mcp__monk__monk_workload_status` |
| Verify an integration exists | `mcp__monk__monk_search_packages` |
| Open the IDE chat panel for sign-in | `mcp__monk__monk_show_chat` |
| Inspect generated MANIFEST/YAML | `Read` (read only — never edit) |
| Confirm the app actually works | Playwright/browser MCP tools (preferred when available) or `Bash` with `curl` against the endpoint Monk returned |
| Look up Monk capabilities/docs | `WebFetch` https://docs.monk.io |

## Done condition

A task is only done when the app responds correctly to a real exercise of its functionality. "Monk reports success" + verified behavior from outside → done. Prefer driving the app via a browser (Playwright/browser MCP) when available — clicking through the actual user flow gives the highest-confidence signal. When no browser tooling is available, `curl` against the returned endpoint is the fallback. If verification fails, loop back to Monk with the symptom.
