# Monk plugin for AI coding agents

> ### 🐬 Bug bounty: July 17–August 10, 2026
>
> This plugin is new and we want it proven in anger. Install it, take a real
> app through build, deploy, and operate, and file what breaks as issues on
> this repo. Cash prizes and Monk Pro for the top hunters —
> **[rules and details](https://monk.io/bug-bounty)**.
>
> Security and data-loss findings: report privately to security@monk.io, _not
> in public issues._

## What is Monk?

[Monk](https://monk.io) is a DevOps agent that works alongside your coding
agent. Your agent writes the code; Monk takes it to production and keeps it
running — on your own cloud accounts (AWS, GCP, Azure, DigitalOcean,
Hetzner), with infrastructure, databases, networking, TLS, CI/CD, and
monitoring handled for you.

This plugin connects Claude Code, Cursor, OpenAI Codex, or Google Antigravity
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

### Claude Code

```text
/plugin marketplace add monk-io/monk-plugin
/plugin install monk@monk-plugins
```

To update an existing install:

```text
/plugin update monk@monk-plugins
/reload-plugins
```

### Cursor

Install from the [Cursor marketplace](https://cursor.com/marketplace/monk-io),
or from the command palette:

```text
/add-plugin monk
```

Or, pointing directly at the plugin repo:

```text
/add-plugin https://github.com/monk-io/monk-plugin
```

### OpenAI Codex

```text
codex plugin marketplace add monk-io/monk-plugin
```

Then start `codex`, run `/plugins`, open the `monk-plugins` marketplace, and
install Monk.

### Google Antigravity

Clone or download this repository, then copy the `.antigravity-plugin` directory
to one of:

- **Workspace** (this project only): `.agents/plugins/monk/`
- **Global** (all workspaces): `~/.gemini/config/plugins/monk/`

```bash
cp -r .antigravity-plugin/ ~/.gemini/config/plugins/monk
~/.gemini/config/plugins/monk/scripts/start-monk-agent.sh
```

The second command is a one-time setup step that installs `monk-agent`, starts
it, and registers it in `~/.gemini/config/mcp_config.json` (Antigravity reads
MCP servers from the global config, not from the plugin directory). After that,
`monk-agent` starts automatically via the `PreInvocation` hook at the start of
each Antigravity conversation. To authenticate with Monk, open a project in
Antigravity, then go to **Agent Settings → Customizations → Authenticate** next
to the `monk` server and complete the browser sign-in.

After installation, restart or reload the host so the skill and MCP server are
picked up. If the `monk` MCP server reports that authentication is required,
complete the browser sign-in flow: `/mcp` in Claude Code,
`codex mcp login monk` in Codex, Cursor's MCP login for the `monk` server, or
**Agent Settings → Customizations → Authenticate** in Antigravity.

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

On the first session the plugin bootstraps a local companion and the Monk
runtime:

- `monk-agent` is installed to `~/.monk/bin` and serves MCP on
  `127.0.0.1:7419`. Its state lives in `~/.monk/agent`.
- The Monk CLI and daemon (`monk`, `monkd`) are installed or upgraded with
  your package manager: Homebrew on macOS, apt or dnf on Linux, and a
  dedicated Ubuntu WSL distro on Windows.
- This plugin requires monkd v3.21.1 or newer and prompts to
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
