# Agent Workflow

Use this sequence for the MVP:

1. Initialize session with workspace root.
2. Check `monk.auth.status`.
3. Check `monk.runtime.status`.
4. If signed out, call `monk.auth.start` and send the returned local URL.
5. If runtime is missing, call `monk.install.status` and surface install steps.
6. Analyze the project.
7. Request deploy-time provider and MANIFEST credentials through
   `monk.credentials.request`; use `monk.secret.request` only for a single ad
   hoc secret with no provider mapping.
8. Deploy with `monk.project.deploy`; privileged tools open their own approval
   flow when needed.
9. Verify the app or workload externally.

Never receive secret values in chat. Never bypass Monk runtime state with shell
commands.
