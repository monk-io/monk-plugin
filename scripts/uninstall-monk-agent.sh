#!/usr/bin/env sh
set -eu

script_dir="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
case "$(uname -s 2>/dev/null || printf unknown)" in
  MINGW*|MSYS*|CYGWIN*)
    exec powershell.exe -NoProfile -ExecutionPolicy Bypass \
      -File "$script_dir/uninstall-monk-agent.ps1" "$@"
    ;;
esac

remove_runtime=0
remove_data=1
assume_yes=0
from_hook=0

usage() {
  cat <<'EOF'
Usage: scripts/uninstall-monk-agent.sh [options]

Stops and removes the local monk-agent companion. Runtime removal is opt-in.

Options:
  --runtime      Also remove or stop/uninstall the Monk CLI/daemon runtime.
  --all          Remove monk-agent, monk-agent data, and Monk runtime.
  --keep-data    Keep ~/.monk/agent state/logs.
  -y, --yes      Do not prompt.
  --from-hook    Run only when MONK_PLUGIN_UNINSTALL=1 is set.
  -h, --help     Show this help.
EOF
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --runtime) remove_runtime=1 ;;
    --all) remove_runtime=1; remove_data=1 ;;
    --keep-data) remove_data=0 ;;
    -y|--yes) assume_yes=1 ;;
    --from-hook) from_hook=1 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage >&2; exit 2 ;;
  esac
  shift
done

if [ "$from_hook" = "1" ] && [ "${MONK_PLUGIN_UNINSTALL:-0}" != "1" ]; then
  exit 0
fi

if [ "${MONK_UNINSTALL_RUNTIME:-0}" = "1" ]; then
  remove_runtime=1
fi

home_dir="${HOME:-}"
if [ -z "$home_dir" ]; then
  echo "HOME is not set." >&2
  exit 2
fi

install_dir="${MONK_AGENT_INSTALL_DIR:-"$home_dir/.monk/bin"}"
monk_home="${MONK_AGENT_HOME:-"$home_dir/.monk"}"
agent_data_dir="$monk_home/agent"
pid_file="$agent_data_dir/launcher/run/monk-agent.pid"
target="$install_dir/monk-agent"
checksum="$install_dir/monk-agent.sha256"
launchd_label="io.monk.agent"
launchd_plist="$home_dir/Library/LaunchAgents/$launchd_label.plist"

if [ "$assume_yes" != "1" ]; then
  if [ ! -t 0 ]; then
    echo "Refusing to uninstall non-interactively without --yes." >&2
    exit 2
  fi
  printf 'Remove monk-agent%s? [y/N] ' "$([ "$remove_runtime" = "1" ] && printf ' and Monk runtime' || true)"
  read answer
  case "$answer" in
    y|Y|yes|YES) ;;
    *) echo "Cancelled."; exit 0 ;;
  esac
fi

resolve_executable_path() {
  path="$1"
  if command -v readlink >/dev/null 2>&1; then
    readlink -f "$path" 2>/dev/null && return 0
  fi
  if command -v realpath >/dev/null 2>&1; then
    realpath "$path" 2>/dev/null && return 0
  fi
  return 1
}

pid_matches_executable() {
  pid="$1"
  expected_path="$2"
  case "$pid" in
    ''|*[!0-9]*) return 1 ;;
  esac
  [ "$(uname -s 2>/dev/null || printf unknown)" = "Linux" ] || return 1
  actual_path="$(readlink "/proc/$pid/exe" 2>/dev/null)" || return 1
  case "$actual_path" in
    *" (deleted)") actual_path="${actual_path% *}" ;;
  esac
  expected_path="$(resolve_executable_path "$expected_path")" || return 1
  [ "$actual_path" = "$expected_path" ]
}

stop_agent() {
  os="$(uname -s 2>/dev/null || printf unknown)"
  if [ "$os" = "Darwin" ] && command -v launchctl >/dev/null 2>&1; then
    uid="$(id -u)"
    launchctl bootout "gui/$uid/$launchd_label" >/dev/null 2>&1 || true
    rm -f "$launchd_plist"
  fi

  if [ -f "$pid_file" ]; then
    pid="$(cat "$pid_file" 2>/dev/null || true)"
    case "$pid" in
      ''|*[!0-9]*) ;;
      *)
        if kill -0 "$pid" >/dev/null 2>&1 && pid_matches_executable "$pid" "$target"; then
          kill "$pid" >/dev/null 2>&1 || true
        fi
        ;;
    esac
    rm -f "$pid_file"
  fi
}

remove_agent_files() {
  rm -f "$target" "$checksum"
  rm -rf "$install_dir/.monk-agent.extract" \
    "$install_dir/.monk-agent.tmp.tar.gz" \
    "$install_dir/.monk-agent.tmp.sha256"
  if [ "$remove_data" = "1" ]; then
    rm -rf "$agent_data_dir"
  fi
}

remove_runtime_macos() {
  if command -v monk >/dev/null 2>&1; then
    monk machine stop >/dev/null 2>&1 || true
  fi
  if command -v brew >/dev/null 2>&1; then
    brew uninstall monk-io/monk/monk >/dev/null 2>&1 ||
      brew uninstall monk >/dev/null 2>&1 ||
      true
  fi
}

remove_runtime_linux() {
  if command -v systemctl >/dev/null 2>&1; then
    sudo systemctl stop monkd >/dev/null 2>&1 || true
    sudo systemctl disable monkd >/dev/null 2>&1 || true
    sudo rm -rf /etc/systemd/system/monkd.service.d >/dev/null 2>&1 || true
    sudo systemctl daemon-reload >/dev/null 2>&1 || true
  fi
  if command -v apt-get >/dev/null 2>&1 && dpkg-query -W monk >/dev/null 2>&1; then
    sudo apt-get remove -y monk
  elif command -v dnf >/dev/null 2>&1 && rpm -q monk >/dev/null 2>&1; then
    sudo dnf remove -y monk
  fi
}

remove_runtime() {
  os="$(uname -s 2>/dev/null || printf unknown)"
  case "$os" in
    Darwin) remove_runtime_macos ;;
    Linux) remove_runtime_linux ;;
    *) echo "Runtime uninstall is not supported by this shell script on $os." >&2; return 2 ;;
  esac
}

stop_agent
remove_agent_files
if [ "$remove_runtime" = "1" ]; then
  remove_runtime
fi

echo "monk-agent uninstall complete."
