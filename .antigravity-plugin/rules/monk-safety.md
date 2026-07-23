# Monk Safety Rules

## Do not bypass Monk tooling

Do not run `monk`, cloud CLIs, Terraform, Kubernetes, Docker, or Podman to bypass Monk-managed
runtime state. The `block-monk` hook enforces this for shell commands — respect it for all execution
paths.

## Approvals

Approvals are owned by privileged `monk-agent` tools. Do not request approval as a standalone
action; call the tool that performs the operation and let it open the required approval flow when
needed.

- Cloud deploys, destructive actions, workload shells, and credential changes require approval
  through `monk-agent`.
- Cluster creation, grow, peer removal, peer retagging, registry changes, exit, and delete must go
  through `monk.cluster.*` tools.
- Never target Monk-managed `system/*` workloads.

## Secrets

Never ask the user to paste secrets into chat.

- For deploy-time provider or MANIFEST credentials, use `monk.credentials.request` so the user gets
  one typed feed form for all required values.
- Use `monk.secret.request` only for a single ad hoc secret with no known provider mapping.
- Secrets, tokens, auth state, authorization codes, and raw secret values must never be sent in
  telemetry or included in tool arguments beyond the dedicated secret tools.

## MANIFEST and MonkScript

Generated MANIFEST and MonkScript YAML belong to Monk. Before editing either:

1. Read `monk://workspace/manifest`
2. Call `monk.analyzer.diagnose`
3. Query docs with `monk.docs.search` and packages with `monk.package.dump`

After editing, run `monk.analyzer.diagnose` again before deploying.

## State reset

If the user asks to reset or clear Monk Agent local state, use `monk.agent.clear_state` with
`confirm:true`. Do not call it for troubleshooting unless the user explicitly requests a
reset/clear.
