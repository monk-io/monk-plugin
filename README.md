# Monk plugin for AI coding agents

Deploy and operate applications with [Monk](https://monk.io) from Claude,
Codex, and Cursor without installing the VS Code Monk extension.

This repository is the portable plugin layer. It contains the agent skill,
host manifests, Claude Code safety hook, and MVP subagent prompts. The local
runtime companion is developed in the sibling `../monk-agent` repository.

## MVP scope

The MVP target is intentionally narrow:

- **Hosts:** Claude Code, OpenAI Codex, and Cursor.
- **Runtime:** `monk-agent` plus Monk CLI/daemon (`monk` and `monkd`) installed
  locally.
- **Auth:** sign up/sign in through a localhost browser callback served by
  `monk-agent`.
- **Deploy:** local deploy and cloud deploy through Monk-supported providers.
- **Secrets:** entered through `monk-agent` web UI, never pasted into agent chat.
- **Safety:** privileged actions go through Monk/`monk-agent` approval flows.

Other Agent Skills clients may be able to use the skill text, but they are
best-effort until their MCP, hook, and subagent behavior is tested.

## Architecture

```text
Claude / Codex / Cursor
  -> monk plugin skill + subagents
  -> local monk-agent MCP endpoint (127.0.0.1)
  -> local monkd through @monk-io/monk (monk-ts2)
  -> Monk runtime, clusters, workloads, secrets, integrations
```

The coding agent should not operate live Monk-managed infrastructure with
shell commands. It should call `monk-agent` MCP tools and let Monk own runtime
state. Local source-code inspection, tests, and normal app edits remain the
coding agent's responsibility.

## What this repo ships today

- `skills/monk/SKILL.md`: portable Monk behavior instructions.
- `agents/`: MVP subagent prompts for frontman, install, deploy, docs, and
  MonkScript/editor workflows. Claude Code should use `monk-editor` for
  hands-on MANIFEST and Monk YAML changes.
- `scripts/ensure-monk-agent.sh` and `scripts/ensure-monk-agent.ps1`:
  bootstrap installers for the local `monk-agent` companion.
- `.claude-plugin/plugin.json`: Claude Code plugin manifest.
- `.codex-plugin/plugin.json`: Codex plugin manifest.
- `.cursor-plugin/plugin.json`: Cursor plugin manifest.
- `.github/plugin/plugin.json`: GitHub Copilot / VS Code manifest placeholder.
- `hooks/block-monk.sh`: Claude Code-only shell guard that blocks direct
  `monk ...` CLI calls from the agent.
- `hooks/monk-diagnostics.sh`: Claude Code-only post-edit diagnostics hook for
  MANIFEST and loaded Monk YAML files. It asks the local `monk-agent` MCP server
  for analyzer diagnostics.

## Requirements

- A host with plugin/skill support: Claude Code, Codex, or Cursor for MVP.
- `monk-agent` installed locally. Plugin-capable hosts should run the bundled
  bootstrap script during plugin installation or first activation.
- Monk CLI and daemon installed locally, or installable by `monk-agent`.
- `jq` on `PATH` only for the Claude Code hook.

## Install

Repo URL: <https://github.com/monk-io/monk-plugin>

Claude Code:

```text
/plugin marketplace add monk-io/monk-plugin
/plugin install monk@monk-plugins
```

If the plugin is already installed, update it after every plugin version bump:

```text
/plugin update monk@monk-plugins
/reload-plugins
```

Cursor:

```text
/add-plugin https://github.com/monk-io/monk-plugin
```

OpenAI Codex:

```text
codex plugin install monk-io/monk-plugin
```

For local development:

```text
/plugin install /path/to/monk-plugin
```

After installation, restart or reload the host so the skill and MCP discovery
refresh.

To refresh a local Claude Code development install from sibling working copies:

```sh
./scripts/dev-update-local.sh
```

This builds `../monk-agent`, installs it to `~/.monk/bin`, restarts the local
agent, and refreshes Claude's Monk plugin marketplace/cache copies. For
already-open Claude Code sessions, run `/reload-plugins` after the script
finishes.

### monk-agent bootstrap

The intended marketplace flow is:

1. The user installs the Monk plugin through the native host UI or command.
2. The host runs the bundled `monk-agent` bootstrap script if `monk-agent` is
   missing.
3. `monk-agent` starts locally, prompts the user to sign up or sign in, and
   exposes runtime install/status tools.
4. The agent waits while `monk-agent` installs or repairs Monk runtime
   components, then continues only after checks pass.

Claude Code integration details:

- `.mcp.json` registers the plugin-provided `monk` MCP server at
  `http://127.0.0.1:7419/mcp`.
- The `SessionStart` hook runs `scripts/start-monk-agent.sh`, which installs
  `monk-agent` if needed and starts it on `127.0.0.1:7419`.
- If the MCP server reports that authentication is required, run `/mcp` in
  Claude Code and complete the browser sign-in flow.

Unix bootstrap:

```bash
./scripts/ensure-monk-agent.sh
```

Windows bootstrap:

```powershell
.\scripts\ensure-monk-agent.ps1
```

The bootstrap scripts install `monk-agent` to `~/.monk/bin` by default and
download public, checksummed archives from `https://get.monk.io/nightly`.
Set `MONK_AGENT_CHANNEL` to use another release channel, or
`MONK_AGENT_DOWNLOAD_BASE` during development to point at local or staging
artifacts.

## Claude Code hooks

The Claude Code shell hook is defense-in-depth. It blocks shell commands where
`monk` appears in command position, such as:

| Command              | Result  |
| -------------------- | ------- |
| `monk run foo`       | blocked |
| `cd /tmp && monk ps` | blocked |
| `sudo monk deploy`   | blocked |
| `monkey patch`       | allowed |
| `echo monk`          | allowed |

The Claude Code diagnostics hook runs after `Edit`, `Write`, and `MultiEdit` for
MANIFEST or Monk YAML files. It is file-gated, best-effort, and feeds
`monk-agent` analyzer diagnostics back into Claude. Other hosts do not use these
hooks yet. Their protection and diagnostics come from the skill instructions and
`monk-agent` tool gates.

## Cluster operations

Agents must use `monk-agent` cluster tools for Monk-managed infrastructure:

- Inspect: `monk.cluster.status`, `monk.cluster.peers`,
  `monk.cluster.providers`, `monk.cluster.price`.
- Capacity: `monk.cluster.create`, `monk.cluster.grow`,
  `monk.cluster.shrink`.
- Peers: `monk.cluster.peer.remove`, `monk.cluster.peer.tag`.
- Registry: `monk.cluster.registry.status`,
  `monk.cluster.registry.ensure`, `monk.cluster.registry.reset`.
- Context/destruction: `monk.cluster.exit`, `monk.cluster.delete`.

Risky tools open the local feed approval UI themselves. Agents should not run
`monk cluster ...` shell commands or ask for separate chat approval first.

## Development notes

The MVP runtime is in `/Users/nooga/monk/monk-agent`.

Useful sibling checkouts:

- `/Users/nooga/monk/monk-agent`: local MCP/dashboard runtime.
- `/Users/nooga/monk/monk-ts2`: `@monk-io/monk` TypeScript client for local
  `monkd` communication.
- `/Users/nooga/monk/autospin`: hosted project analysis/build/deploy logic.
- `/Users/nooga/monk/vscode-monk`: existing IDE product to mine for frontman
  behavior, specialist agent routing, auth, install, onboarding, analytics,
  analyzer, and tool-gate behavior.

## License

MIT
