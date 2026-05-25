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
  MonkScript/editor workflows.
- `scripts/ensure-monk-agent.sh` and `scripts/ensure-monk-agent.ps1`:
  bootstrap installers for the local `monk-agent` companion.
- `.claude-plugin/plugin.json`: Claude Code plugin manifest.
- `.codex-plugin/plugin.json`: Codex plugin manifest.
- `.cursor-plugin/plugin.json`: Cursor plugin manifest.
- `.github/plugin/plugin.json`: GitHub Copilot / VS Code manifest placeholder.
- `hooks/block-monk.sh`: Claude Code-only shell guard that blocks direct
  `monk ...` CLI calls from the agent.

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

### monk-agent bootstrap

The intended marketplace flow is:

1. The user installs the Monk plugin through the native host UI or command.
2. The host runs the bundled `monk-agent` bootstrap script if `monk-agent` is
   missing.
3. `monk-agent` starts locally, prompts the user to sign up or sign in, and
   exposes runtime install/status tools.
4. The agent waits while `monk-agent` installs or repairs Monk runtime
   components, then continues only after checks pass.

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

## Claude Code hook

The Claude Code hook is defense-in-depth. It blocks shell commands where
`monk` appears in command position, such as:

| Command              | Result  |
| -------------------- | ------- |
| `monk run foo`       | blocked |
| `cd /tmp && monk ps` | blocked |
| `sudo monk deploy`   | blocked |
| `monkey patch`       | allowed |
| `echo monk`          | allowed |

Other hosts do not use this hook yet. Their protection comes from the skill
instructions and `monk-agent` tool gates.

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
