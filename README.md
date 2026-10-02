# Monk plugin for AI coding agents

## What is Monk?

[Monk](https://monk.io) is a DevOps agent that works alongside your coding
agent. Your agent writes the code; Monk takes it to production and keeps it
running — on your own cloud accounts (AWS, GCP, Azure, DigitalOcean,
Hetzner), with infrastructure, databases, networking, TLS, CI/CD, and
monitoring handled for you.

This plugin connects Claude Code, Cursor, OpenAI Codex and other coding agents
to Monk. Once installed, you deploy and operate in plain language:
"deploy this app", "show me the logs", "set up CI/CD", "what is this costing
me?" — no Dockerfiles, no Terraform, no cloud consoles.

**Watch it work** (2 minutes):
[Give Your Coding Agent a DevOps Engineer](https://www.youtube.com/watch?v=8-oLii4qrWg) ·
[One Prompt to Production](https://www.youtube.com/watch?v=O4qZoTZVyhg) ·
[Your App Runs Itself](https://www.youtube.com/watch?v=jzIex2_J6bM)

Monk is built for safety around AI agents: your coding agent talks to a
deterministic orchestrator instead of a shell. It never sees your cloud
credentials, and destructive actions (deploys, deletions, cluster changes)
require your explicit approval in Monk's UI — not the agent's chat.

A Monk account is required: [create one at monk.io](https://monk.io). The
plugin opens a browser sign-in on first use.

## Installation

Run this in a terminal:

```bash
curl -fsSL https://get.monk.io/stable/plugin | sh
```

On Windows, in PowerShell:

```powershell
irm https://get.monk.io/stable/plugin.ps1 | iex
```

It installs Monk, finds the coding agents on this computer, shows what it will
change and asks before changing anything, then offers to sign you in. Run it
again to update. Add `--dry-run` to see the plan without changing anything:

```bash
curl -fsSL https://get.monk.io/stable/plugin | sh -s -- --dry-run
```

Every download is checked against a list signed with Monk's release key.

### Setting up one agent

To add Monk to a single agent yourself instead:

**Claude Code**

```text
/plugin marketplace add monk-io/monk-plugin
/plugin install monk@monk-plugins
/reload-plugins
```

Sign in with `/mcp`, then authenticate the `monk` server. To update later:
`/plugin update monk@monk-plugins`, then `/reload-plugins`.

**OpenAI Codex**

```bash
codex plugin marketplace add monk-io/monk-plugin
codex plugin add monk@monk-plugins
```

Restart Codex, then sign in with `codex mcp login monk`.

**Cursor**

Install from the [Cursor marketplace](https://cursor.com/marketplace/monk-io),
or straight from this repository:

```text
/add-plugin https://github.com/monk-io/monk-plugin
```

Restart Cursor, then log in to the `monk` server in Cursor's MCP settings.

**Google Antigravity**

```bash
agy plugin install https://github.com/monk-io/monk-plugin/tree/main/.antigravity-plugin
```

Restart Antigravity, then open **Agent Settings → Customizations** and choose
**Authenticate** next to `monk`.

**Devin**

```bash
devin plugins install -y --local monk-io/monk-plugin
```

Restart Devin, then sign in with `devin mcp login monk`.

**Other agents** (VS Code, Copilot CLI, Gemini CLI, OpenCode, Kilo Code, Goose,
Zed, Cline, Roo Code, Amp, Warp, JetBrains Junie): the installer above adds the
`monk` MCP server to their config. To do it by hand, see
[the agent guide](https://docs.monk.io/getting-started/agents).

## Basic usage

Prompts start with `/monk` followed by what you want, for example:

- `/monk describe this project`
- `/monk deploy this project`
- `/monk show workload status`
- `/monk diagnose my deployment`

The plugin gives the agent Monk tools through a local MCP server. Privileged
operations such as deploys, cluster changes, and deletions ask for your
approval in the Monk approval UI, and secrets are entered through the local
Monk web UI — never pasted into agent chat.

## Reporting bugs

Found something broken, slow, or confusing?

Three ways to report it:

- [Open an issue on this repo](https://github.com/monk-io/monk-plugin/issues/new)
- Prompt `/monk report bug: ...` in your agent, and describe what went wrong.
- Use the bug icon in the top-right corner of the [Monk Dashboard](https://monk.io/dashboard) to report a bug or request a feature.

## What gets installed

The installer, or the plugin's first session, sets up a local companion and
the Monk runtime:

- `monk-agent` is installed to `~/.monk/bin` and serves MCP on
  `127.0.0.1:7419`. Its state lives in `~/.monk/agent`.
- The Monk CLI and daemon (`monk`, `monkd`) are installed or upgraded with
  your package manager: Homebrew on macOS, apt or dnf on Linux, and a
  dedicated Ubuntu WSL distro on Windows.
- This plugin requires monkd v3.21.5 or newer and prompts to
  upgrade older installs.

To remove everything later:

```bash
./scripts/uninstall-monk-agent.sh --yes            # remove monk-agent
./scripts/uninstall-monk-agent.sh --runtime --yes  # also remove Monk CLI/daemon
```

```powershell
.\scripts\uninstall-monk-agent.ps1 -Yes
.\scripts\uninstall-monk-agent.ps1 -Runtime -Yes
```

## Help

- Documentation: <https://docs.monk.io>
- Accounts and product: <https://monk.io>

## License

Apache License 2.0 — see [LICENSE](LICENSE).
