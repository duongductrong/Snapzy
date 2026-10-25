#!/usr/bin/env bash
# install.sh — Install Snapzy from GitHub Releases
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/duongductrong/Snapzy/master/install.sh | bash
#   curl -fsSL https://raw.githubusercontent.com/duongductrong/Snapzy/v1.2.3/install.sh | bash
#   VERSION=1.2.3 bash install.sh
#
# The script downloads the DMG from GitHub Releases, mounts it,
# copies Snapzy.app to /Applications, and cleans up.

set -euo pipefail

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

has_color() {
  [[ -z "${NO_COLOR:-}" ]] && [[ -t 1 || "${FORCE_COLOR:-}" == "1" ]]
}

if has_color; then
  BOLD='\033[1m'
  GREEN='\033[1;32m'
  CYAN='\033[1;36m'
  RED='\033[1;31m'
  YELLOW='\033[1;33m'
  RESET='\033[0m'
else
  BOLD='' GREEN='' CYAN='' RED='' YELLOW='' RESET=''
fi

info()  { printf "${CYAN}▸${RESET} %s\n" "$*"; }
ok()    { printf "${GREEN}✔${RESET} %s\n" "$*"; }
warn()  { printf "${YELLOW}⚠${RESET} %s\n" "$*" >&2; }
fail()  { printf "${RED}✖${RESET} %s\n" "$*" >&2; exit 1; }

# ---------------------------------------------------------------------------
# Pre-flight checks
# ---------------------------------------------------------------------------

[[ "$(uname -s)" == "Darwin" ]] || fail "Snapzy is a macOS app. This script only works on macOS."

for cmd in curl hdiutil; do
  command -v "$cmd" &>/dev/null || fail "Required command not found: $cmd"
done

# ---------------------------------------------------------------------------
# Resolve version
# ---------------------------------------------------------------------------

REPO="duongductrong/Snapzy"

if [[ -z "${VERSION:-}" ]]; then
  info "Fetching latest release version…"
  VERSION=$(curl -fsSL "https://api.github.com/repos/${REPO}/releases/latest" \
    | grep '"tag_name"' \
    | head -1 \
    | sed -E 's/.*"v([^"]+)".*/\1/')
  [[ -n "$VERSION" ]] || fail "Could not determine the latest release version."
fi

# Strip leading "v" if present
VERSION="${VERSION#v}"

DMG_NAME="Snapzy-v${VERSION}.dmg"
DOWNLOAD_URL="https://github.com/${REPO}/releases/download/v${VERSION}/${DMG_NAME}"

printf "\n${BOLD}Snapzy Installer${RESET}  •  v%s\n\n" "$VERSION"

# ---------------------------------------------------------------------------
# Download
# ---------------------------------------------------------------------------

TMPDIR_INSTALL="$(mktemp -d)"
trap 'rm -rf "$TMPDIR_INSTALL"' EXIT

DMG_PATH="${TMPDIR_INSTALL}/${DMG_NAME}"

info "Downloading ${DMG_NAME}…"
if ! curl -fSL --progress-bar -o "$DMG_PATH" "$DOWNLOAD_URL"; then
  fail "Download failed. Check the version number and your network connection."
fi
ok "Downloaded ${DMG_NAME}"

# ---------------------------------------------------------------------------
# Mount, copy, unmount
# ---------------------------------------------------------------------------

MOUNT_POINT="${TMPDIR_INSTALL}/snapzy-dmg"
mkdir -p "$MOUNT_POINT"

info "Mounting disk image…"
hdiutil attach "$DMG_PATH" -nobrowse -quiet -mountpoint "$MOUNT_POINT" \
  || fail "Failed to mount the DMG."

INSTALL_DIR="/Applications"

info "Copying Snapzy.app to ${INSTALL_DIR}…"

# Remove existing installation if present
if [[ -d "${INSTALL_DIR}/Snapzy.app" ]]; then
  warn "Existing Snapzy.app found — replacing."
  rm -rf "${INSTALL_DIR}/Snapzy.app"
fi

cp -R "${MOUNT_POINT}/Snapzy.app" "${INSTALL_DIR}/" \
  || fail "Failed to copy Snapzy.app. You may need to run with sudo."

info "Unmounting disk image…"
hdiutil detach "$MOUNT_POINT" -quiet 2>/dev/null || true

ok "Installed Snapzy.app to ${INSTALL_DIR}"

# ---------------------------------------------------------------------------
# Command line tool
# ---------------------------------------------------------------------------

# Releases that ship the `snapzy` CLI embed it in the app; link it onto PATH.
# Never replace a file that is not a symlink, and never use sudo here.
CLI_HELPER="${INSTALL_DIR}/Snapzy.app/Contents/Helpers/snapzy"
CLI_LINK="/usr/local/bin/snapzy"
CLI_LINK_TARGET=""
[[ -L "$CLI_LINK" ]] && CLI_LINK_TARGET="$(readlink "$CLI_LINK")"
if [[ -x "$CLI_HELPER" ]]; then
  if [[ -d /opt/homebrew/Caskroom/snapzy || -d /usr/local/Caskroom/snapzy ]]; then
    # The Homebrew cask owns the link; one made here would block `brew reinstall` on Intel Macs.
    warn "Snapzy is also installed with Homebrew, which links the snapzy command. Run:"
    printf "    brew reinstall --cask snapzy\n"
  elif [[ -e "$CLI_LINK" && ! -L "$CLI_LINK" ]]; then
    warn "${CLI_LINK} exists and is not a symlink — leaving it alone."
  elif [[ -n "$CLI_LINK_TARGET" && -e "$CLI_LINK" && "$CLI_LINK_TARGET" != */Snapzy*.app/Contents/Helpers/snapzy ]]; then
    warn "${CLI_LINK} links to ${CLI_LINK_TARGET} — leaving it alone."
  elif mkdir -p "$(dirname "$CLI_LINK")" 2>/dev/null && ln -sfn "$CLI_HELPER" "$CLI_LINK" 2>/dev/null; then
    ok "Linked the snapzy command to ${CLI_LINK}"
  else
    warn "Could not link the snapzy command. To use it from any terminal, run:"
    printf "    sudo mkdir -p /usr/local/bin && sudo ln -sfn '%s' '%s'\n" "$CLI_HELPER" "$CLI_LINK"
  fi
fi

# ---------------------------------------------------------------------------
# Post-install
# ---------------------------------------------------------------------------

# ---------------------------------------------------------------------------
# NOTE: Snapzy is now notarized by Apple (Developer ID).
# macOS automatically verifies the notarization ticket and removes quarantine.
# The xattr bypass below is intentionally kept commented — uncomment if a
# future build is ad-hoc signed or unsigned (e.g., local CI test builds).
# ---------------------------------------------------------------------------
# info "Removing quarantine attribute…"
# xattr -cr "${INSTALL_DIR}/Snapzy.app" 2>/dev/null || true
# ok "Quarantine attribute removed"

printf "\n${GREEN}${BOLD}Installation complete!${RESET}\n\n"
printf "  Launch Snapzy from your Applications folder or Spotlight.\n"
printf "  Snapzy is notarized by Apple — no quarantine bypass needed.\n"
printf "  On first launch, grant ${BOLD}Screen Recording${RESET} permission when prompted.\n\n"
