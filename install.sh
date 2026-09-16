#!/usr/bin/env sh
main() {
set -eu

repository="ackwest/sdd-toolkit"
version="${SDD_TOOLKIT_VERSION:-latest}"
install_dir="${SDD_TOOLKIT_INSTALL_DIR:-$HOME/.local/bin}"
no_input="${SDD_TOOLKIT_NO_INPUT:-0}"
skip_setup="${SDD_TOOLKIT_SKIP_SETUP:-0}"
agent="${SDD_TOOLKIT_AGENT:-}"
case "$agent" in ''|codex|claude) ;; *) echo 'Agent must be codex or claude.' >&2; exit 1;; esac
interactive=0
# curl | sh consumes stdin as program text. Prompts and child processes use the
# controlling terminal instead; never consume the rest of the installer as input.
if [ "$no_input" != 1 ] && ( : </dev/tty ) 2>/dev/null; then
  exec 3</dev/tty
  interactive=1
fi
confirm() {
  [ "$interactive" = 1 ] || return 1
  printf '%s [y/N] ' "$1" >&2
  IFS= read -r answer <&3 || return 1
  case "$answer" in y|Y|yes|YES) return 0;; *) return 1;; esac
}
echo 'SDD Toolkit setup'

case "$(uname -s)" in
  Linux) os=linux ;;
  Darwin) os=darwin ;;
  *) echo "Unsupported operating system: $(uname -s)" >&2; exit 1 ;;
esac
case "$(uname -m)" in
  x86_64|amd64) arch=amd64 ;;
  arm64|aarch64) arch=arm64 ;;
  *) echo "Unsupported architecture: $(uname -m)" >&2; exit 1 ;;
esac

archive="sdd-toolkit_${os}_${arch}.tar.gz"
if ! command -v gh >/dev/null 2>&1; then
  confirm 'Install GitHub CLI using your package manager?' || {
    echo 'GitHub CLI is required. Install it from https://cli.github.com and rerun this installer.' >&2
    exit 1
  }
  if command -v brew >/dev/null 2>&1; then
    brew install gh <&3
  else
    as_root() { if [ "$(id -u)" = 0 ]; then "$@"; else sudo "$@"; fi; }
    if command -v apt-get >/dev/null 2>&1; then as_root apt-get install -y gh <&3
    elif command -v dnf >/dev/null 2>&1; then as_root dnf install -y gh <&3
    elif command -v pacman >/dev/null 2>&1; then as_root pacman -S --needed --noconfirm github-cli <&3
    elif command -v zypper >/dev/null 2>&1; then as_root zypper --non-interactive install gh <&3
    else echo 'No supported package manager found. Install GitHub CLI from https://cli.github.com.' >&2; exit 1
    fi
  fi
  command -v gh >/dev/null 2>&1 || { echo 'GitHub CLI installation did not complete.' >&2; exit 1; }
fi
if ! gh auth status --active --hostname github.com >/dev/null 2>&1; then
  confirm 'Sign in to GitHub in your browser to download SDD Toolkit?' || {
    echo 'GitHub authentication is required. Run gh auth login or rerun this installer interactively.' >&2
    exit 1
  }
  gh auth login --hostname github.com --web --git-protocol https <&3 || {
    echo 'GitHub sign-in was not completed. Nothing was installed.' >&2; exit 1
  }
fi
gh api "repos/$repository" --silent || {
  echo 'Cannot access ackwest/sdd-toolkit. Check your active GitHub account, repository Read access, organization SSO authorization, and connectivity.' >&2
  exit 1
}
if [ "$version" = latest ]; then
  release_tag="$(gh release view --repo "$repository" --json tagName --jq .tagName)" || exit 1
else
  release_tag="v${version#v}"
fi
printf '%s\n' "$release_tag" | LC_ALL=C grep -Eq '^v[0-9]+\.[0-9]+\.[0-9]+([-+][0-9A-Za-z.-]+)?$' || {
  echo 'Invalid release version.' >&2; exit 1
}

temporary="$(mktemp -d "${TMPDIR:-/tmp}/sdd-toolkit.XXXXXX")"
trap 'rm -rf "$temporary"' EXIT INT TERM

set -- release download --repo "$repository" --pattern "$archive" --pattern checksums.txt --dir "$temporary" "$release_tag"
if ! gh "$@"; then
  echo "Release download failed. Check GitHub connectivity and gh authentication/access to ackwest/sdd-toolkit; no binary was replaced." >&2
  exit 1
fi
expected="$(awk -v name="$archive" '{ sub(/\r$/, "") } $2 == name { print $1; exit }' "$temporary/checksums.txt")"
[ -n "$expected" ] || { echo "No checksum published for $archive" >&2; exit 1; }
printf '%s\n' "$expected" | LC_ALL=C grep -Eq '^[0-9a-fA-F]{64}$' || { echo 'Invalid release checksum.' >&2; exit 1; }
if command -v sha256sum >/dev/null 2>&1; then
  actual="$(sha256sum "$temporary/$archive" | awk '{print $1}')"
else
  actual="$(shasum -a 256 "$temporary/$archive" | awk '{print $1}')"
fi
[ "$actual" = "$expected" ] || { echo "Checksum mismatch for $archive" >&2; exit 1; }

tar -xzf "$temporary/$archive" -C "$temporary"
binary_version="$("$temporary/sdd-toolkit" version)" || exit 1
[ "$binary_version" = "${release_tag#v}" ] || { echo 'Downloaded executable does not match the requested release; no binary was replaced.' >&2; exit 1; }
mkdir -p "$install_dir"
install -m 0755 "$temporary/sdd-toolkit" "$install_dir/sdd-toolkit.new"
mv -f "$install_dir/sdd-toolkit.new" "$install_dir/sdd-toolkit"
echo "Installed SDD Toolkit ${release_tag#v} for this user."

case ":$PATH:" in
  *":$install_dir:"*) ;;
  *)
    if [ "${SDD_TOOLKIT_NO_PATH_UPDATE:-0}" != 1 ]; then
      case "${SHELL:-/bin/sh}" in
        */zsh) profile="${ZDOTDIR:-$HOME}/.zshenv" ;;
        */bash)
          if [ -f "$HOME/.bash_profile" ]; then profile="$HOME/.bash_profile"
          elif [ -f "$HOME/.bash_login" ]; then profile="$HOME/.bash_login"
          else profile="$HOME/.profile"; fi ;;
        */sh) profile="$HOME/.profile" ;;
        *) profile='' ;;
      esac
      if [ -n "$profile" ]; then
        # Quote the literal path, including spaces/apostrophes, without evaluating it.
        quoted_dir="$(printf '%s' "$install_dir" | sed "s/'/'\\\\''/g")"
        path_line="export PATH='$quoted_dir':\"\$PATH\""
        if ! grep -Fqx "$path_line" "$profile" 2>/dev/null; then
          if [ -f "$profile" ] && [ ! -e "$profile.sdd-toolkit-backup" ]; then cp -p "$profile" "$profile.sdd-toolkit-backup"; fi
          mkdir -p "$(dirname "$profile")"
          printf '\n# SDD Toolkit executable\n%s\n' "$path_line" >> "$profile"
        fi
        echo "Added SDD Toolkit to $profile. Open a new terminal after setup."
      else
        echo "Add $install_dir to PATH in your shell configuration before restarting your coding agent."
      fi
    fi ;;
esac
PATH="$install_dir:$PATH"
export PATH
if [ "$skip_setup" = 1 ]; then
  echo "Setup skipped. Next: $install_dir/sdd-toolkit install"
else
  set -- install
  if [ -n "$agent" ]; then set -- "$@" --agent "$agent"; fi
  setup_code=0
  if [ "$interactive" = 1 ]; then
    "$install_dir/sdd-toolkit" "$@" <&3 || setup_code=$?
  else
    "$install_dir/sdd-toolkit" "$@" --no-input --json || setup_code=$?
  fi
  if [ "$setup_code" != 0 ]; then
    echo "The executable is installed, but setup needs attention (code $setup_code). Resolve the message above, then run sdd-toolkit install." >&2
    exit "$setup_code"
  fi
  echo 'Setup complete. Restart your coding agent to load Lifecycle.'
fi
}

main "$@"
