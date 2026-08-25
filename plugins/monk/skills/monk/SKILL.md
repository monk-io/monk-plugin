# Monk Skill Definition

This skill provides MCP tools for interacting with Monk.

## Tools

### Cluster Management

- `monk.cluster.new` - Create a new cluster
- `monk.cluster.join` - Join an existing cluster
- `monk.cluster.exit` - Leave current cluster and return to local mode
- `monk.cluster.status` - Get cluster status
- `monk.cluster.list` - List known clusters

### Ingress Management

- `monk.cluster.ingress.ensure` - Ensure ingress is configured and running
- `monk.cluster.ingress.ensure` (with `force: true`) - Force re-registration of all ingress routes (use after cluster exit to recover routing)
- `monk.cluster.ingress.status` - Get ingress status (note: may report enabled=false even when functional)
- `monk.cluster.ingress.routers` - List registered Traefik routers for debugging

### Workload Management

- `monk.workload.deploy` - Deploy a workload
- `monk.workload.redeploy` - Redeploy a workload
- `monk.workload.stop` - Stop a workload
- `monk.workload.start` - Start a workload
- `monk.workload.remove` - Remove a workload
- `monk.workload.logs` - Get workload logs
- `monk.workload.status` - Get workload status
- `monk.workload.describe` - Get detailed workload information

### System Management

- `monk.system.list` - List system components
- `monk.system.start` - Start a system component
- `monk.system.stop` - Stop a system component
- `monk.system.restart` - Restart a system component

### Diagnostics

- `monk.diagnostics.run` - Run full system diagnostics including ingress route verification
- `monk.diagnostics.ingress` - Run ingress-specific diagnostics and attempt auto-recovery

## Ingress Recovery After Cluster Exit

**Known Issue**: Entering and leaving a cluster can permanently destroy local ingress routing. Workloads remain healthy on their host ports but HTTPS routes return 404.

**Recovery Steps** (in order of preference):

1. Run ingress diagnostics: `monk.diagnostics.ingress {}`
2. Force re-ensure ingress: `monk.cluster.ingress.ensure {"force": true}`
3. If still failing, recreate Traefik: `monk.system.stop {"name": "monk/system/traefik"}` then `monk.system.start {"name": "monk/system/traefik"}`
4. Redeploy affected workloads after Traefik recreation

The `force: true` parameter on `ingress.ensure` bypasses the "already ready" check and forces route re-registration with Traefik.

## Workload Ingress Configuration

Workloads with ingress should define:
```yaml
ingress:
  host: "myapp.localhost"
  path: "/"
  tls: true
```

The host will be available at `https://<host>/` after deployment.

## Cluster Context

- Local mode: Default, single-node, ingress on 127.0.0.1
- Cluster mode: Multi-node, ingress on cluster load balancer
- Use `monk.cluster.exit` to return to local mode
- After cluster exit, run ingress diagnostics to verify routing is restored
