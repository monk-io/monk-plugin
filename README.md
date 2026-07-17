# Monk plugin for AI coding agents

> ### 🐬 Bug bounty: July 17–August 1, 2026
>
> This plugin is new and we want it proven in anger. Install it, take a real
> app through build, deploy, and operate, and file what breaks as issues on
> this repo. Cash prizes and Monk Pro for the top hunters —
> **[rules and details](https://monk.io/bug-bounty)**.
>
> Security and data-loss findings: report privately to security@monk.io, _not
> in public issues._

Deploy and operate full applications with [Monk](https://monk.io) — cloud
infrastructure, SaaS integrations, and containerized workloads — directly from
Claude Code, Cursor, OpenAI Codex, and Google Antigravity.

Your agent writes the code. Monk deploys it and keeps it running on your own
cloud: infrastructure, databases, networking, TLS, CI/CD, monitoring. The
agent talks to a deterministic orchestrator instead of a shell — it never
sees your credentials, and destructive actions require your approval in
Monk's UI, below the agent.

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

Ask your coding agent to deploy and operate with Monk, for example:

- "Deploy this project with Monk."
- "Show my Monk workload status."
- "Diagnose my Monk deployment."

The plugin gives the agent Monk tools through a local MCP server. Privileged
operations such as deploys, cluster changes, and deletions ask for your
approval in the Monk approval UI, and secrets are entered through the local
Monk web UI — never pasted into agent chat.

## Reporting bugs

Found something broken, slow, or confusing? File an issue on this repo using
the [bug bounty report template](https://github.com/monk-io/monk-plugin/issues/new?template=bug_bounty_report.yml) —
during the bounty every valid report earns points toward the
[prizes](https://monk.io/bug-bounty). It asks for:

- **Stage**: install, connect, build, deploy, or operate
- **Coding agent**: Claude Code, Cursor, Codex, Antigravity + version
- **Repro steps**, expected vs. actual
- **Severity** (your guess): crash, blocker, major, minor
- **Setup**: OS, monkd version, target cloud, integration

One bug per issue. Duplicates are merged into the first report. Feature
requests and content about your run (blog, stream, tweet) earn points too —
open a regular issue with the details or the link.

To be scored you need a Monk account — sign in at [monk.io](https://monk.io)
with the same GitHub account you file from — and findings should come from
actually using the product. Reports without a linked account, and findings
from pure code analysis, are welcome but won't earn points.
**Security and data-loss findings go to security@monk.io** — please don't
post exploitable details publicly.

## What gets installed

On the first session the plugin bootstraps a local companion and the Monk
runtime:

- `monk-agent` is installed to `~/.monk/bin` and serves MCP on
  `127.0.0.1:7419`. Its state lives in `~/.monk/agent`.
- The Monk CLI and daemon (`monk`, `monkd`) are installed or upgraded with
  your package manager: Homebrew on macOS, apt or dnf on Linux, and a
  dedicated Ubuntu WSL distro on Windows.
- This plugin requires monkd v3.20.10 or newer and prompts to
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
