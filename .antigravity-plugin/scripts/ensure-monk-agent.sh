#!/usr/bin/env sh
set -eu

script_dir="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
case "$(uname -s 2>/dev/null || printf unknown)" in
  MINGW*|MSYS*|CYGWIN*)
    exec powershell.exe -NoProfile -ExecutionPolicy Bypass \
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
mkdir -p "$install_dir"

if [ "$auto_update" = "0" ] || [ "$auto_update" = "false" ]; then
  if command -v monk-agent >/dev/null 2>&1; then
    command -v monk-agent
    exit 0
  fi
  if [ -x "$target" ]; then
    printf '%s\n' "$target"
    exit 0
  fi
fi

old_umask="$(umask)"
umask 077
staging_dir="$(mktemp -d "$install_dir/.monk-agent.stage.XXXXXX")"
umask "$old_umask"
archive_tmp="$staging_dir/monk-agent.tar.gz"
checksum_tmp="$staging_dir/monk-agent.sha256"
extract_dir="$staging_dir/extract"
checksum_publish="$staging_dir/monk-agent.installed.sha256"

cleanup() {
  status=$?
  trap - EXIT HUP INT TERM
  rm -rf "$staging_dir"
  exit "$status"
}

cleanup_signal() {
  status="$1"
  trap - EXIT HUP INT TERM
  rm -rf "$staging_dir"
  exit "$status"
}

trap cleanup EXIT
trap 'cleanup_signal 129' HUP
trap 'cleanup_signal 130' INT
trap 'cleanup_signal 143' TERM

if command -v curl >/dev/null 2>&1; then
  curl -fL "$checksum_url" -o "$checksum_tmp"
elif command -v wget >/dev/null 2>&1; then
  wget -O "$checksum_tmp" "$checksum_url"
else
  echo "curl or wget is required to install monk-agent." >&2
  exit 2
fi

expected="$(awk '{print $1}' "$checksum_tmp")"

if [ -x "$target" ] && [ -f "$checksum_installed" ]; then
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
printf '%s  %s\n' "$expected" "$artifact" >"$checksum_publish"
mv "$checksum_publish" "$checksum_installed"
printf '%s\n' "$target"
