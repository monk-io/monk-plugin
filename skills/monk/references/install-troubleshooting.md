# Install Troubleshooting

The MVP requires:

- `monk-agent`
- Monk CLI: `monk`
- Monk daemon: `monkd`

Use `monk.install.status` first. If unavailable, bootstrap the local
`monk-agent` companion with the plugin script when the host allows it:

```text
scripts/ensure-monk-agent.sh
scripts/ensure-monk-agent.ps1
```

After `monk-agent` is available, inspect the full `monk.install.status` result:

- `humanExplanation`: current-platform summary suitable for the user.
- `relationships`: how `monk-agent`, auth, `monk`, `monkd`, and platform
  prerequisites fit together.
- `components`: installed/missing/outdated component state.
- `checks`: pass/fail runtime gates.
- `probes`: shell checks that produced the state.
- `troubleshootingHints`: likely causes and next diagnostics.
- `nextAction` and `actions`: recommended remediation.

Use `monk.install.run` only after explicit user or dashboard approval.

Claude Code and Codex can also surface native MCP OAuth for Streamable HTTP
servers. If Monk MCP appears as "needs authentication", use the host-native auth
flow first: `/mcp` in Claude Code, or `codex mcp login monk` in Codex CLI.

## macOS

Preferred path:

```text
scripts/ensure-monk-agent.sh
brew install monk-io/monk/monk
```

If Homebrew or Xcode Command Line Tools are missing, use the remediation action
reported by `monk.install.status`. The Homebrew installer may ask for the user's
password and should be run only with explicit approval.

Explain the graph clearly: `monk-agent` runs the local MCP/dashboard process;
Xcode Command Line Tools make Homebrew healthy; Homebrew installs Monk; `monk
machine` starts local `monkd`.

## Linux

Preferred path:

```text
scripts/ensure-monk-agent.sh
curl -fsSL https://install.monk.io/install.sh | sh
```

If package-manager setup fails, inspect the error and tell the user whether apt
or dnf repository setup failed.

Explain the graph clearly: `monk-agent` runs MCP/dashboard; apt/dnf installs
Monk; systemd starts and supervises `monkd`.

## Windows

Preferred path:

```text
scripts/ensure-monk-agent.ps1
WSL/Ubuntu-Monk runtime install through monk.install.run
```

MVP uses native `monk-agent.exe` and a WSL-based Monk runtime. Prefer a known
Ubuntu distro for Monk runtime work. If WSL is missing, ask the user to install
or enable WSL first.

Explain the graph clearly: native `monk-agent.exe` handles MCP/dashboard/auth;
WSL hosts the Linux Monk CLI and `monkd`; Ubuntu-Monk is preferred so Monk state
is isolated from the user's other distros.

## After install

Re-check:

- `monk.install.status`
- `monk.runtime.status`
- `monk.auth.status`

Only continue to deploy after runtime is reachable and the user is signed in.
