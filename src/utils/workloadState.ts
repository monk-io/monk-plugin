export interface WorkloadLogStatus {
  ok: boolean;
  workload: string;
  running: boolean;
  state: string;
  logs: string;
}

export function formatWorkloadLogResponse(
  workload: string,
  logs: string,
  containerStatus?: { running?: boolean; state?: string }
): WorkloadLogStatus {
  const running = containerStatus?.running ?? true;
  const state = containerStatus?.state ?? (running ? 'running' : 'exited');

  return {
    ok: true,
    workload,
    running,
    state,
    logs
  };
}
