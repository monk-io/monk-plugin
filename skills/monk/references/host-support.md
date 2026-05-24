# Host Support

MVP support is limited to Claude Code, OpenAI Codex, and Cursor.

| Host | MVP status | Notes |
| --- | --- | --- |
| Claude Code | Target | Uses skill and Claude-only shell hook. |
| OpenAI Codex | Target | Uses skill and `monk-agent` MCP endpoint. |
| Cursor | Target | Uses skill/plugin manifest and `monk-agent` MCP endpoint. |
| GitHub Copilot / VS Code | Placeholder | Manifest exists, but MVP does not depend on `../vscode-monk`. |
| Other Agent Skills clients | Best effort | Skill text may work, but hooks/subagents/MCP behavior is untested. |

Do not claim full portability until each host has been tested with install,
auth, secure secret entry, local deploy, and cloud deploy approval.

