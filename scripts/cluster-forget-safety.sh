#!/usr/bin/env sh
# cluster-forget-safety.sh — safety wrapper for monk.cluster.forget
#
# Usage: ./cluster-forget-safety.sh <cluster-id>
#
# This wrapper ensures the cluster forget operation only proceeds when the
# membership probe confirms the cluster is reachable. If the probe fails,
# the forget is blocked with a warning to prevent data loss.
#
# Fixes: Cluster forget safety guard fails open when membership probe errors (#204)

set -eu

cluster_id="${1:-}"
if [ -z "$cluster_id" ]; then
  echo "ERROR: cluster-forget-safety.sh requires a cluster ID argument." >&2
  echo "Usage: $(basename "$0") <cluster-id>" >&2
  exit 2
fi

agent="${MONK_AGENT_PATH:-${MONK_AGENT_INSTALL_DIR:-"$HOME/.monk/bin"}/monk-agent}"
if [ ! -x "$agent" ]; then
  echo "ERROR: monk-agent not found at $agent. Install Monk first." >&2
  exit 1
fi

# Safety guard — probe cluster membership BEFORE forget.
# The agent's cluster.status MCP tool returns connectivity state including
# IsConnected. If it errors or reports disconnected, refuse to forget.
echo "Checking cluster connectivity for '$cluster_id'..." >&2
status_output="$("$agent" cluster status "$cluster_id" 2>&1)" || {
  echo "WARNING: cluster status probe failed for '$cluster_id'." >&2
  echo "  Error: $status_output" >&2
  echo "  The cluster forget operation has been ABORTED to prevent data loss." >&2
  echo "  A still-joined cluster must not be forgotten when membership cannot be verified." >&2
  echo "  Verify the cluster is actually disconnected before retrying, or use the" >&2
  echo "  dashboard to manage cluster records manually." >&2
  exit 1
}

# Check for explicit connectivity errors in the JSON response.
# The agent returns a status with fields like "error", "IsConnected", etc.
if printf '%s' "$status_output" | grep -qiE '"error"|"IsConnected".*false|"membership"|"unavailable"'; then
  echo "WARNING: cluster '$cluster_id' reports errors or disconnected state." >&2
  echo "  Status: $status_output" >&2
  echo "  The cluster forget operation has been ABORTED to prevent data loss." >&2
  echo "  Ensure the cluster is fully detached before forgetting its record." >&2
  exit 1
fi

# Safety check passed — proceed with forget.
echo "Cluster '$cluster_id' is reachable. Proceeding with forget..." >&2
exec "$agent" cluster forget "$cluster_id"
