# Monk plugin for AI coding agents

Deploy and operate full applications with [Monk](https://monk.io) — cloud
infrastructure (AWS/GCP/Azure/DO/Hetzner), third-party SaaS integrations
(Cloudflare, MongoDB Atlas, Auth0, Vercel, Stripe, …), and containerized
workloads — from a single chat with your agent.

The skill follows the open [Agent Skills](https://agentskills.io)
specification, so it works in any compliant client — Claude Code, Cursor,
OpenAI Codex, GitHub Copilot, VS Code, Gemini CLI, Amp, Goose, OpenHands,
Junie, Kiro, and more. The repo ships plugin manifests for the major hosts
so it can be installed natively in each.

This plugin bundles:

- The **`monk` skill** (`skills/monk/SKILL.md`) — instructions that teach the
  agent how to talk to Monk via the Monk MCP server (build, deploy, inspect,
  debug), what conventions to follow for app code, and how to verify deployed
  apps end-to-end. Portable across all Agent Skills clients.
- A **`PreToolUse` Bash hook** (Claude Code only) that blocks accidental
  shell-outs to the `monk` CLI. Monk owns its own cluster state; running
  `monk …` from a shell desyncs what Monk thinks is deployed from what
  actually is. The hook denies these calls with a message redirecting Claude
  to the `mcp__monk__monk_chat` tool. Other hosts rely on the prose rule in
  the skill body to enforce the same constraint.

## Requirements

- **Monk installed and running.** This plugin only works when Monk is installed
  locally. See the [Monk installation guide](https://docs.monk.io/getting-started/installation).
- **Monk MCP server configured** in Claude Code, so `mcp__monk__monk_chat` and
  friends are available. Follow the
  [Monk MCP getting-started guide](https://docs.monk.io/getting-started/mcp-getting-started).
  If the MCP server is missing, Claude will help you install it on first use.
- Claude Code with plugin support
- `jq` on `PATH` (used by the hook script)

## Install

Repo URL: <https://github.com/monk-io/monk-plugin>

**Claude Code:**

```text
/plugin install monk-io/monk-plugin
```

**Cursor** — install from Git or via marketplace (`/add-plugin`):

```text
/add-plugin https://github.com/monk-io/monk-plugin
```

**OpenAI Codex** — add to a marketplace catalog or install directly:

```text
codex plugin install monk-io/monk-plugin
```

**GitHub Copilot CLI / VS Code**:

```text
copilot plugin install monk-io/monk-plugin
```

In VS Code, run **Chat: Install Plugin From Source** and point at this repo.

For any client that supports the [Agent Skills](https://agentskills.io) format
but doesn't have a plugin install command, copy `skills/monk/` into the
client's skills directory (typically `~/.<client>/skills/` or
`<project>/.<client>/skills/`).

For local development:

```text
/plugin install /path/to/monk-plugin
```

After install, restart Claude Code (or reload plugins) so the skill registers
and the hook activates.

## What the hook blocks

The hook fires on every `Bash` tool call and inspects the command string. It
denies the call when `monk` appears in **command position**:

| Command                          | Result  |
| -------------------------------- | ------- |
| `monk run foo`                   | blocked |
| `  monk status`                  | blocked |
| `cd /tmp && monk ps`             | blocked |
| `sudo monk deploy`               | blocked |
| `x=1; monk go`                   | blocked |
| `(monk init)`                    | blocked |
| `monkey patch`                   | allowed |
| `echo monk`                      | allowed |
| `grep monk file`                 | allowed |
| `ls`                             | allowed |

Claude receives a denial message pointing it back to the Monk MCP tool, so it
self-corrects without surfacing an error to you.

## Layout

```text
monk-plugin/
├── .claude-plugin/plugin.json       # Claude Code manifest
├── .cursor-plugin/plugin.json       # Cursor manifest
├── .codex-plugin/plugin.json        # OpenAI Codex manifest
├── .github/plugin/plugin.json       # GitHub Copilot / VS Code manifest
├── skills/monk/SKILL.md             # Portable Agent Skill (agentskills.io)
├── hooks/                           # Claude Code only
│   ├── hooks.json
│   └── block-monk.sh
└── README.md
```

All manifests point at the same `skills/monk/` directory — the skill itself
is the single source of truth. Each tool reads the manifest it recognizes and
ignores the others.

## License

MIT
