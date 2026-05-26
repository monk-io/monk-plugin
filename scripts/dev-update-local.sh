#!/usr/bin/env sh
set -eu

usage() {
  cat <<'USAGE'
Usage: scripts/dev-update-local.sh [options]

Build and install monk-agent from the sibling working copy, restart the local
agent, and refresh Claude Code's local Monk plugin copies from this checkout.

Options:
  --agent-root PATH       monk-agent checkout path (default: ../monk-agent)
  --install-dir PATH      monk-agent install dir (default: ~/.monk/bin)
  --port PORT             monk-agent port (default: 7419)
  --host HOST             monk-agent host (default: 127.0.0.1)
  --skip-agent-build      Do not build/install monk-agent
  --skip-agent-restart    Do not restart monk-agent
  --skip-claude-plugin    Do not update Claude plugin marketplace/cache copies
  --help                  Show this help

Claude Code does not currently expose a non-interactive plugin reload command.
After this script finishes, run /reload-plugins in any already-open Claude Code
session. New Claude sessions will read the refreshed plugin files immediately.
USAGE
}

script_dir="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
plugin_root="$(CDPATH= cd -- "$script_dir/.." && pwd)"
agent_root="$(CDPATH= cd -- "$plugin_root/../monk-agent" 2>/dev/null && pwd || true)"
install_dir="${MONK_AGENT_INSTALL_DIR:-"$HOME/.monk/bin"}"
host="${MONK_AGENT_HOST:-127.0.0.1}"
port="${MONK_AGENT_PORT:-7419}"
skip_agent_build=0
skip_agent_restart=0
skip_claude_plugin=0

while [ "$#" -gt 0 ]; do
  case "$1" in
    --agent-root)
      [ "$#" -ge 2 ] || { echo "--agent-root requires a path" >&2; exit 2; }
      agent_root="$(CDPATH= cd -- "$2" && pwd)"
      shift 2
      ;;
    --install-dir)
      [ "$#" -ge 2 ] || { echo "--install-dir requires a path" >&2; exit 2; }
      install_dir="$2"
      shift 2
      ;;
    --host)
      [ "$#" -ge 2 ] || { echo "--host requires a value" >&2; exit 2; }
      host="$2"
      shift 2
      ;;
    --port)
      [ "$#" -ge 2 ] || { echo "--port requires a value" >&2; exit 2; }
      port="$2"
      shift 2
      ;;
    --skip-agent-build)
      skip_agent_build=1
      shift
      ;;
    --skip-agent-restart)
      skip_agent_restart=1
      shift
      ;;
    --skip-claude-plugin)
      skip_claude_plugin=1
      shift
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if [ -z "$agent_root" ] || [ ! -f "$agent_root/deno.json" ]; then
  echo "monk-agent checkout not found. Pass --agent-root PATH." >&2
  exit 2
fi

need_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "$1 is required." >&2
    exit 2
  fi
}

hash_file() {
  path="$1"
  if [ ! -f "$path" ]; then
    printf 'missing'
    return
  fi
  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$path" | awk '{print $1}'
    return
  fi
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$path" | awk '{print $1}'
    return
  fi
  printf 'unknown'
}

current_compile_task() {
  os="$(uname -s)"
  arch="$(uname -m)"
  case "$os:$arch" in
    Darwin:arm64|Darwin:aarch64) printf 'compile:darwin-arm64:dist/monk-agent-aarch64-apple-darwin' ;;
    Darwin:x86_64|Darwin:amd64) printf 'compile:darwin-x64:dist/monk-agent-x86_64-apple-darwin' ;;
    Linux:arm64|Linux:aarch64) printf 'compile:linux-arm64:dist/monk-agent-aarch64-unknown-linux-gnu' ;;
    Linux:x86_64|Linux:amd64) printf 'compile:linux-x64:dist/monk-agent-x86_64-unknown-linux-gnu' ;;
    *)
      echo "Unsupported local platform for dev compile: $os/$arch" >&2
      exit 2
      ;;
  esac
}

copy_plugin_tree() {
  dest="$1"
  mkdir -p "$dest"
  if command -v rsync >/dev/null 2>&1; then
    rsync -r --delete \
      --exclude '.git/' \
      --exclude '.claude/' \
      --exclude 'AGENTS.md' \
      "$plugin_root/" "$dest/"
    return
  fi

  tmp="$dest.tmp.$$"
  mkdir -p "$tmp"
  (cd "$plugin_root" && tar \
    --exclude './.git' \
    --exclude './.claude' \
    --exclude './AGENTS.md' \
    -cf - .) | (cd "$tmp" && tar -xf -)
  if [ -d "$dest" ]; then
    find "$dest" -mindepth 1 -maxdepth 1 -exec rm -rf {} +
  fi
  (cd "$tmp" && tar -cf - .) | (cd "$dest" && tar -xf -)
  rm -rf "$tmp"
}

if [ "$skip_agent_build" = "0" ]; then
  need_cmd deno
  need_cmd npm
  compile_spec="$(current_compile_task)"
  compile_task="$(printf '%s' "$compile_spec" | cut -d: -f1-2)"
  compiled_rel="$(printf '%s' "$compile_spec" | cut -d: -f3-)"
  compiled_path="$agent_root/$compiled_rel"
  target="$install_dir/monk-agent"

  echo "Building monk-agent dashboard..."
  (cd "$agent_root" && npm --prefix web install)
  (cd "$agent_root" && deno task web:build)
  echo "Compiling monk-agent with deno task $compile_task..."
  (cd "$agent_root" && deno task "$compile_task")

  mkdir -p "$install_dir"
  before_hash="$(hash_file "$target")"
  cp "$compiled_path" "$target"
  chmod 0755 "$target"
  after_hash="$(hash_file "$target")"
  echo "Installed $target"
  echo "monk-agent sha256: $before_hash -> $after_hash"
fi

if [ "$skip_agent_restart" = "0" ]; then
  echo "Restarting monk-agent on http://$host:$port ..."
  CLAUDE_PLUGIN_ROOT="$plugin_root" \
  MONK_AGENT_HOST="$host" \
  MONK_AGENT_PORT="$port" \
  MONK_AGENT_INSTALL_DIR="$install_dir" \
  MONK_AGENT_SKIP_ENSURE=1 \
    "$plugin_root/scripts/start-monk-agent.sh"
  echo "monk-agent restarted."
fi

if [ "$skip_claude_plugin" = "0" ]; then
  claude_root="${CLAUDE_CONFIG_DIR:-"$HOME/.claude"}"
  marketplace_dest="$claude_root/plugins/marketplaces/monk-plugins"

  echo "Refreshing Claude marketplace copy: $marketplace_dest"
  copy_plugin_tree "$marketplace_dest"

  version="$(deno eval "console.log(JSON.parse(await Deno.readTextFile('$plugin_root/.claude-plugin/plugin.json')).version)" 2>/dev/null || true)"
  cache_root="$claude_root/plugins/cache/monk-plugins/monk"
  if [ -n "$version" ]; then
    cache_dest="$cache_root/$version"
    echo "Refreshing Claude cache copy: $cache_dest"
    copy_plugin_tree "$cache_dest"
  else
    echo "Could not read plugin version; skipped cache copy." >&2
  fi

  echo "Claude plugin files refreshed."
  if command -v claude >/dev/null 2>&1; then
    echo "Installed Claude plugin status:"
    claude plugin list | sed -n '/monk@monk-plugins/,+3p' || true
  fi
fi

cat <<EOF

Local Monk dev update complete.

For already-open Claude Code sessions, run:
  /reload-plugins

If Claude still shows an old plugin version, run:
  /plugin update monk@monk-plugins
  /reload-plugins

For one-off Claude testing without touching the installed plugin, you can also start Claude with:
  claude --plugin-dir "$plugin_root"
EOF
