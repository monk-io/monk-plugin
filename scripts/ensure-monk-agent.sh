#!/usr/bin/env sh
set -eu

install_dir="${MONK_AGENT_INSTALL_DIR:-"$HOME/.monk/bin"}"
channel="${MONK_AGENT_CHANNEL:-nightly}"
download_base="${MONK_AGENT_DOWNLOAD_BASE:-"https://get.monk.io/$channel"}"

if command -v monk-agent >/dev/null 2>&1; then
  command -v monk-agent
  exit 0
fi

if [ -x "$install_dir/monk-agent" ]; then
  printf '%s\n' "$install_dir/monk-agent"
  exit 0
fi

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
archive_tmp="$install_dir/.monk-agent.tmp.tar.gz"
checksum_tmp="$install_dir/.monk-agent.tmp.sha256"
extract_dir="$install_dir/.monk-agent.extract"
mkdir -p "$install_dir"

echo "Installing monk-agent from $url" >&2
if command -v curl >/dev/null 2>&1; then
  curl -fL "$url" -o "$archive_tmp"
  curl -fL "$checksum_url" -o "$checksum_tmp"
elif command -v wget >/dev/null 2>&1; then
  wget -O "$archive_tmp" "$url"
  wget -O "$checksum_tmp" "$checksum_url"
else
  echo "curl or wget is required to install monk-agent." >&2
  exit 2
fi

expected="$(awk '{print $1}' "$checksum_tmp")"
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
mv "$extract_dir/monk-agent" "$install_dir/monk-agent"
rm -rf "$extract_dir" "$archive_tmp" "$checksum_tmp"
printf '%s\n' "$install_dir/monk-agent"
