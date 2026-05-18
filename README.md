# Monk plugin for Claude Code

Deploy and operate full applications with [Monk](https://monk.io) — cloud
infrastructure (AWS/GCP/Azure/DO/Hetzner), third-party SaaS integrations
(Cloudflare, MongoDB Atlas, Auth0, Vercel, Stripe, …), and containerized
workloads — from a single chat with Claude Code.

This plugin bundles:

- The **`monk` skill** — instructions that teach Claude how to talk to Monk via
  the Monk MCP server (build, deploy, inspect, debug), what conventions to
  follow for app code, and how to verify deployed apps end-to-end.
- A **`PreToolUse` Bash hook** that blocks accidental shell-outs to the `monk`
  CLI. Monk owns its own cluster state; running `monk …` from a shell desyncs
  what Monk thinks is deployed from what actually is. The hook denies these
  calls with a message redirecting Claude to the `mcp__monk__monk_chat` tool.

## Requirements

- Claude Code with plugin support
- The Monk MCP server configured (so `mcp__monk__monk_chat` and friends are
  available). See [docs.monk.io](https://docs.monk.io) for setup.
- `jq` on `PATH` (used by the hook script)

## Install

```text
/plugin install <git-url-of-this-repo>
```

Or, for local development:

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
├── .claude-plugin/plugin.json
├── skills/monk/SKILL.md
├── hooks/
│   ├── hooks.json
│   └── block-monk.sh
└── README.md
```

## License

MIT
