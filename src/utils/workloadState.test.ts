import { formatWorkloadLogResponse } from './workloadState';

describe('Workload Log Response Formatting', () => {
  it('should include running state for active workload', () => {
    const res = formatWorkloadLogResponse('test/app', 'log line 1', { running: true, state: 'running' });
    expect(res.ok).toBe(true);
    expect(res.running).toBe(true);
    expect(res.state).toBe('running');
  });

  it('should surface exited state for stopped workload', () => {
    const res = formatWorkloadLogResponse('test/app', 'probe line', { running: false, state: 'exited' });
    expect(res.ok).toBe(true);
    expect(res.running).toBe(false);
    expect(res.state).toBe('exited');
  });
});
