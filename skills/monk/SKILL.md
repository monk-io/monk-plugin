---
name: monk
description: "Deploy and operate applications with Monk through the local monk-agent MCP companion. Use when the user wants to install Monk, sign in, analyze a project, deploy locally or to cloud, inspect workloads, provide secrets securely, or troubleshoot Monk-managed infrastructure. MVP hosts are Claude Code, Codex, and Cursor."
allowed-tools: Bash(*), Read, WebFetch, mcp__monk__monk_chat, mcp__monk__monk_search_packages, mcp__monk__monk_show_chat, mcp__monk__monk_workload_status
---

# Using Monk

## MVP model

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
3. Initialize a session with `monk.session.init`. Include the host/client name
   and plugin version when the host exposes them; `monk-agent` uses this for
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
- `monk.project.deploy`
- `monk.secret.request`
- `monk.approval.request`
- `monk.workload.status`
- `monk.analyzer.diagnose`
- `monk.docs.search`
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

- Never ask the user to paste secrets into chat. Use `monk.secret.request`.
- Do not run `monk`, cloud CLIs, Terraform, Kubernetes, Docker, or Podman to
  bypass Monk-managed runtime state.
- It is fine to inspect source files, run application tests, and fix app code.
- Generated MANIFEST and MonkScript YAML belong to Monk. Read them for context;
  coordinate changes through Monk tooling.
- Cloud deploys, destructive actions, workload shells, and credential changes
  require approval through `monk-agent`.
- Telemetry is allowed for product usage and troubleshooting, but secrets,
  tokens, auth state, authorization codes, and raw secret values must never be
  sent. `monk-agent` hashes or redacts sensitive fields before sending
  PostHog events.

## Deployment flow

For a first deploy:

1. Initialize the session with the workspace root.
2. Check auth and runtime status.
3. Ask Monk to analyze the project.
4. If secrets are required, request them through the local secure web form.
5. If deploying to cloud or making a risky change, request approval.
6. Deploy with `monk.project.deploy`.
7. Verify the returned endpoint/status from outside the deploy operation.

For MonkScript, MANIFEST, template diagnostics, or schema/example questions, use
the editor workflow and call `monk.analyzer.diagnose` / `monk.docs.search` when
available. If those tools report that analyzer or Chroma support is not wired
yet, state that clearly and fall back to local files plus official docs.

For an existing Monk-built project:

- Code-only changes usually need deploy, not a full re-analysis.
- Major architecture changes need analyze/build before deploy.
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
