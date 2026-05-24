# Agent Workflow

Use this sequence for the MVP:

1. Initialize session with workspace root.
2. Check `monk.auth.status`.
3. Check `monk.runtime.status`.
4. If signed out, call `monk.auth.start` and send the returned local URL.
5. If runtime is missing, call `monk.install.status` and surface install steps.
6. Analyze the project.
7. Request secrets through `monk.secret.request`.
8. Request approvals through `monk.approval.request`.
9. Deploy with `monk.project.deploy`.
10. Verify the app or workload externally.

Never receive secret values in chat. Never bypass Monk runtime state with shell
commands.
