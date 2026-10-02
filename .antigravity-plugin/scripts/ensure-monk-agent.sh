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
# connect_timeout bounds only reaching a response (DNS/TCP/TLS/headers);
# stall_timeout is the real guard (see download_checksum() below) and should
# stay generous -- it only fires on near-zero throughput, not a merely slow
# one, so widening it costs nothing on a healthy connection.
download_connect_timeout="${MONK_AGENT_DOWNLOAD_CONNECT_TIMEOUT:-15}"
download_stall_timeout="${MONK_AGENT_DOWNLOAD_STALL_TIMEOUT:-30}"
target="$install_dir/monk-agent"
# Line 1: the installed archive's sha256 and name, to tell when there's nothing new.
# Line 2: the installed binary's own sha256, for the offline fallback below. An
# install made before line 2 existed falls back only if line 1 happens to match.
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
# The signed release list: a `signature:` line, then every archive's sha256
# (scripts/sign_release_manifest.sh). It replaces trusting the `.sha256` file
# next to the archive, which whoever can change the archive can change too.
checksum_url="$download_base/checksums.signed.txt"
archive_tmp="$install_dir/.monk-agent.tmp.$$.tar.gz"
checksum_tmp="$install_dir/.monk-agent.tmp.$$.signed"
list_tmp="$install_dir/.monk-agent.tmp.$$.list"
sig_tmp="$install_dir/.monk-agent.tmp.$$.sig"
key_tmp="$install_dir/.monk-agent.tmp.$$.pem"
extract_dir="$install_dir/.monk-agent.extract.$$"
lock_file="$install_dir/.monk-agent.lock"
mkdir -p "$install_dir"

# Prints a file's SHA-256, or nothing. A tool that exists but can't run (inside a
# strictly confined snap, `shasum` is present but its Perl interpreter isn't)
# must fall through to the next one, so each result is checked, not just the
# tool's presence. sha256sum (coreutils) goes first as the most portable.
sha256_of() {
  for tool in sha256sum shasum openssl; do
    command -v "$tool" >/dev/null 2>&1 || continue
    case "$tool" in
      sha256sum) digest="$(sha256sum "$1" 2>/dev/null | awk '{print $1}')" ;;
      shasum) digest="$(shasum -a 256 "$1" 2>/dev/null | awk '{print $1}')" ;;
      openssl) digest="$(openssl dgst -sha256 "$1" 2>/dev/null | awk '{print $NF}')" ;;
    esac
    case "$digest" in
      *[!0-9a-fA-F]*|'') continue ;;
    esac
    if [ "${#digest}" -eq 64 ]; then
      printf '%s\n' "$digest"
      return 0
    fi
  done
  return 1
}

# The public half of the key Monk releases are signed with (keys/monk-release.pub.pem).
# Carried here rather than downloaded, so the download host can't swap it.
# @monk-release-key-begin
release_key_pem='-----BEGIN PUBLIC KEY-----
MIIBojANBgkqhkiG9w0BAQEFAAOCAY8AMIIBigKCAYEAqZvBwFF2qcg8QgQQdPFD
adR5dB0X+BcMSQmn/kz6liUAUiM93jK3Is+GOzTxGJT86PZXzo0E0NjLCCDvp9TR
AyHm4umRh/xUI6mA97LMOPTDau3sMzKiK/At+ijmgwS5Md7KPhNY8/tGtF9/iRcV
qQZ2k7fKtQ6RcUmXU30I/SNr0E/iJ8dDLxc7L6sPfbrV2qBNF08u06KysKnWwykw
7lJOkNcJFbWtN6op7r+Rq2lB6kHtnB6gjY1voRiUZWfWEHl2A5lKLVwQNh8MpGmt
85FBD58alUJOTXumIej7qz9IxWEi/vHjZfKDLrd9N9BH09MzzQGWnucZcgbUc5eN
4vMwkRW5VjWINb/cKKZ9vaADvXB+TI5Liu5lxIlaQAaxwVHzHe00Br+swZDmNK1C
M4bw4p9OecMBeNBpYvyfEvnqq2m9WHMEt0NnMppvPwAjnGxp6isghQDacB9arYHD
N/Urk4xWqRLWntpERA0/FKLQAA09Nkk/ut/sOmBmOYiHAgMBAAE=
-----END PUBLIC KEY-----'
# @monk-release-key-end

# Prints the sha256 the signed release list gives for $artifact. Fails, saying
# why, if the list isn't signed by Monk's key or doesn't name the artifact.
verified_digest() {
  header="$(head -n 1 "$1")"
  case "$header" in
    "signature: "*) ;;
    *) echo "The Monk release list is not signed." >&2; return 1 ;;
  esac
  tail -n +2 "$1" >"$list_tmp"
  # openssl can be present but unable to run (inside a strictly confined snap),
  # which is the same as absent here, not a bad signature.
  if command -v openssl >/dev/null 2>&1 && openssl version >/dev/null 2>&1; then
    printf '%s\n' "$release_key_pem" >"$key_tmp"
    if ! printf '%s' "${header#signature: }" | openssl base64 -d -A >"$sig_tmp" 2>/dev/null ||
       ! openssl dgst -sha256 -verify "$key_tmp" -signature "$sig_tmp" "$list_tmp" >/dev/null 2>&1; then
      echo "The Monk release list is not signed by Monk's release key; not installing from it." >&2
      return 1
    fi
  else
    echo "Warning: openssl is not available, so the release signature can't be checked; using the checksum alone." >&2
  fi
  digest="$(awk -v name="$artifact" '$2 == name { print $1; exit }' "$list_tmp")"
  case "$digest" in
    *[!0-9a-fA-F]*|'') echo "The Monk release list does not include $artifact." >&2; return 1 ;;
  esac
  [ "${#digest}" -eq 64 ] || { echo "The Monk release list has no valid checksum for $artifact." >&2; return 1; }
  printf '%s\n' "$digest"
}

cleanup() {
  rm -rf "$extract_dir" "$archive_tmp" "$checksum_tmp" "$list_tmp" "$sig_tmp" "$key_tmp"
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

# wget's -T mirrors --speed-time (its read timeout resets on every chunk
# received); -t 1 stops it from retrying past our own
# fallback-to-installed-binary logic below.
download_checksum() {
  if command -v curl >/dev/null 2>&1; then
    curl -fL --connect-timeout "$download_connect_timeout" \
      --speed-limit 1 --speed-time "$download_stall_timeout" \
      "$checksum_url" -o "$checksum_tmp"
  elif command -v wget >/dev/null 2>&1; then
    wget -O "$checksum_tmp" -t 1 -T "$download_stall_timeout" "$checksum_url"
  else
    echo "curl or wget is required to check for monk-agent updates." >&2
    return 2
  fi
}

# A transient failure fetching the release list, or a list that fails its
# signature check, must not abort a cold start when a previously-verified local
# binary is already installed (ENG-422) -- only fall back when that binary's
# hash still matches the checksum recorded at install time. Nothing new is
# installed from an unverified list.
if ! download_checksum || ! expected="$(verified_digest "$checksum_tmp")"; then
  if [ -x "$target" ] && [ -s "$target" ] && [ -f "$checksum_installed" ]; then
    # The binary's own hash (line 2), not the archive's: comparing the archive
    # hash with the binary meant this fallback never matched after an install.
    installed="$(awk 'NR == 1 { first = $1 } NR == 2 { second = $1 } END { print (second != "" ? second : first) }' "$checksum_installed")"
    actual_installed="$(sha256_of "$target" || true)"
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

if [ -x "$target" ] && [ -s "$target" ] && [ -f "$checksum_installed" ]; then
  installed="$(awk 'NR == 1 { print $1 }' "$checksum_installed")"
  if [ "$installed" = "$expected" ]; then
    rm -f "$checksum_tmp"
    printf '%s\n' "$target"
    exit 0
  fi
fi

echo "Installing monk-agent from $url" >&2
if command -v curl >/dev/null 2>&1; then
  curl -fL --connect-timeout "$download_connect_timeout" \
    --speed-limit 1 --speed-time "$download_stall_timeout" \
    "$url" -o "$archive_tmp"
elif command -v wget >/dev/null 2>&1; then
  wget -O "$archive_tmp" -t 1 -T "$download_stall_timeout" "$url"
fi

if ! actual="$(sha256_of "$archive_tmp")"; then
  echo "sha256sum, shasum or openssl is required to verify monk-agent." >&2
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
printf '%s  %s\n%s  monk-agent\n' "$expected" "$artifact" "$(sha256_of "$target" || true)" >"$checksum_installed"
printf '%s\n' "$target"
