#!/usr/bin/env sh
set -eu

script_dir="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
case "$(uname -s 2>/dev/null || printf unknown)" in
  MINGW*|MSYS*|CYGWIN*)
    # Pin to the absolute Windows PowerShell path. A bare `powershell.exe` is
    # resolved with the current directory searched before PATH, so a workspace
    # could plant its own; SYSTEMROOT is OS-controlled and non-writable (ENG-441).
    ps_exe="$(printf '%s' "${SYSTEMROOT:-${WINDIR:-C:/Windows}}" | tr '\\' '/')/System32/WindowsPowerShell/v1.0/powershell.exe"
    exec "$ps_exe" -NoProfile -ExecutionPolicy Bypass \
      -File "$script_dir/ensure-monk-agent.ps1" "$@"
    ;;
esac

install_dir="${MONK_AGENT_INSTALL_DIR:-"$HOME/.monk/bin"}"
channel="${MONK_AGENT_CHANNEL:-stable}"
download_base="${MONK_AGENT_DOWNLOAD_BASE:-"https://get.monk.io/$channel"}"
auto_update="${MONK_AGENT_AUTO_UPDATE:-1}"
target="$install_dir/monk-agent"
checksum_installed="$install_dir/monk-agent.sha256"

os="$(uname -s)"
arch="$(uname -m)"

case "$os" in
  Darwin) platform_path="macos" ;;
  Linux) platform_path="linux" ;;
  *) echo "Unsupported OS for monk-agent bootstrap: $os" >&2; exit 2 ;;
esac

case "$os:$arch" in
  Darwin:arm64|Darwin:aarch64) artifact="monk-agent-arm-darwin-latest.tar.gz" ;;
  Darwin:x86_64|Darwin:amd64) artifact="monk-agent-darwin-latest.tar.gz" ;;
  Linux:arm64|Linux:aarch64) artifact="monk-agent-arm-linux-latest.tar.gz" ;;
  Linux:x86_64|Linux:amd64) artifact="monk-agent-linux-latest.tar.gz" ;;
  *) echo "Unsupported platform for monk-agent bootstrap: $os/$arch" >&2; exit 2 ;;
esac

url="$download_base/$platform_path/$artifact"
checksum_url="$url.sha256"
archive_tmp="$install_dir/.monk-agent.tmp.$$.tar.gz"
checksum_tmp="$install_dir/.monk-agent.tmp.$$.sha256"
extract_dir="$install_dir/.monk-agent.extract.$$"
lock_file="$install_dir/.monk-agent.lock"
mkdir -p "$install_dir"

cleanup() {
  rm -rf "$extract_dir" "$archive_tmp" "$checksum_tmp"
}
trap cleanup EXIT

# Serialize concurrent installs so they don't race on the shared install dir.
# flock is standard on Linux; macOS lacks it by default, so skip locking there
# rather than fail -- per-PID scratch paths below still keep each invocation's
# download/extract isolated even without the lock.
if command -v flock >/dev/null 2>&1; then
  install_lock_timeout="${MONK_AGENT_INSTALL_LOCK_TIMEOUT:-60}"
  case "$install_lock_timeout" in
    ''|*[!0-9]*)
      echo "MONK_AGENT_INSTALL_LOCK_TIMEOUT must be a non-negative integer." >&2
      exit 2
      ;;
  esac
  exec 3>"$lock_file"
  if ! flock -n 3; then
    echo "Another monk-agent install is in progress; waiting up to ${install_lock_timeout}s..." >&2
    if ! flock -w "$install_lock_timeout" 3; then
      echo "Timed out after ${install_lock_timeout}s waiting for another monk-agent install." >&2
      exit 1
    fi
  fi
fi

if [ "$auto_update" = "0" ] || [ "$auto_update" = "false" ]; then
  if [ -x "$target" ]; then
    printf '%s\n' "$target"
    exit 0
  fi
  if command -v monk-agent >/dev/null 2>&1; then
    command -v monk-agent
    exit 0
  fi
fi

download_checksum() {
  if command -v curl >/dev/null 2>&1; then
    curl -fL "$checksum_url" -o "$checksum_tmp"
  elif command -v wget >/dev/null 2>&1; then
    wget -O "$checksum_tmp" "$checksum_url"
  else
    echo "curl or wget is required to check for monk-agent updates." >&2
    return 2
  fi
}

# A transient failure fetching the update-check sidecar must not abort a cold
# start when a previously-verified local binary is already installed
# (ENG-422) -- only fall back when that binary's hash still matches the
# checksum recorded at install time.
if ! download_checksum; then
  if [ -x "$target" ] && [ -s "$target" ] && [ -f "$checksum_installed" ]; then
    installed="$(awk '{print $1}' "$checksum_installed")"
    actual_installed=""
    if command -v shasum >/dev/null 2>&1; then
      actual_installed="$(shasum -a 256 "$target" | awk '{print $1}')"
    elif command -v sha256sum >/dev/null 2>&1; then
      actual_installed="$(sha256sum "$target" | awk '{print $1}')"
    fi
    case "$installed" in
      *[!0-9a-fA-F]*|'') ;;
      *)
        if [ "${#installed}" -eq 64 ] &&
           [ "$(printf '%s' "$installed" | tr 'A-F' 'a-f')" = "$(printf '%s' "$actual_installed" | tr 'A-F' 'a-f')" ]; then
          rm -f "$checksum_tmp"
          echo "Warning: unable to check for monk-agent updates; using the previously checksummed installation at $target." >&2
          printf '%s\n' "$target"
          exit 0
        fi
        ;;
    esac
  fi
  echo "Unable to check for monk-agent updates and no verified local installation is available." >&2
  exit 1
fi

expected="$(awk '{print $1}' "$checksum_tmp")"

if [ -x "$target" ] && [ -s "$target" ] && [ -f "$checksum_installed" ]; then
  installed="$(awk '{print $1}' "$checksum_installed")"
  if [ "$installed" = "$expected" ]; then
    rm -f "$checksum_tmp"
    printf '%s\n' "$target"
    exit 0
  fi
fi

echo "Installing monk-agent from $url" >&2
if command -v curl >/dev/null 2>&1; then
  curl -fL "$url" -o "$archive_tmp"
elif command -v wget >/dev/null 2>&1; then
  wget -O "$archive_tmp" "$url"
fi

if command -v shasum >/dev/null 2>&1; then
  actual="$(shasum -a 256 "$archive_tmp" | awk '{print $1}')"
elif command -v sha256sum >/dev/null 2>&1; then
  actual="$(sha256sum "$archive_tmp" | awk '{print $1}')"
else
  echo "shasum or sha256sum is required to verify monk-agent." >&2
  exit 2
fi

if [ "$actual" != "$expected" ]; then
  echo "Checksum verification failed for monk-agent." >&2
  exit 1
fi

rm -rf "$extract_dir"
mkdir -p "$extract_dir"
tar -xzf "$archive_tmp" -C "$extract_dir"
chmod 0755 "$extract_dir/monk-agent"
mv "$extract_dir/monk-agent" "$target"
printf '%s  %s\n' "$expected" "$artifact" >"$checksum_installed"
printf '%s\n' "$target"
