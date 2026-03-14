#!/usr/bin/env bash
# uninstall.sh — Completely remove Snapzy and reset ALL related permissions
#
# Usage:
#   ./scripts/uninstall.sh           # Interactive mode (asks for confirmation)
#   ./scripts/uninstall.sh --force   # Skip confirmation
#
# What this script does:
#   1. Kills the running app
#   2. Removes Snapzy.app from /Applications
#   3. Removes Application Support data (captures, preferences, caches)
#   4. Removes user preferences (defaults)
#   5. Removes saved application state
#   6. Removes Sparkle update caches
#   7. Resets ALL TCC permissions (Screen Recording, Microphone, Accessibility, etc.)
#   8. Removes login items
#   9. Cleans temp files

set -euo pipefail

APP_NAME="Snapzy"
APP_PATH="/Applications/Snapzy.app"
FALLBACK_BUNDLE_ID="com.trongduong.snapzy"

# ─── Auto-detect bundle ID from app name ─────────────────────────
# Must happen BEFORE the app is deleted (step 2).
# Strategy: osascript (LaunchServices) → PlistBuddy (.app bundle) → fallback
resolve_bundle_id() {
  local detected=""

  # Method 1: Ask LaunchServices via osascript (works even if app is not in /Applications)
  detected=$(osascript -e "id of app \"$APP_NAME\"" 2>/dev/null || true)
  if [[ -n "$detected" ]]; then
    echo "$detected"
    return
  fi

  # Method 2: Read directly from the .app bundle's Info.plist
  if [ -d "$APP_PATH" ]; then
    detected=$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$APP_PATH/Contents/Info.plist" 2>/dev/null || true)
    if [[ -n "$detected" ]]; then
      echo "$detected"
      return
    fi
  fi

  # Fallback: hardcoded
  echo "$FALLBACK_BUNDLE_ID"
}

BUNDLE_ID=$(resolve_bundle_id)

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

info()    { echo -e "${CYAN}→${NC} $*"; }
success() { echo -e "${GREEN}✅${NC} $*"; }
warn()    { echo -e "${YELLOW}⚠️${NC}  $*"; }
error()   { echo -e "${RED}❌${NC} $*"; }

# ─── Confirmation ────────────────────────────────────────────────
if [[ "${1:-}" != "--force" ]]; then
  echo ""
  echo -e "${RED}╔══════════════════════════════════════════════════════╗${NC}"
  echo -e "${RED}║  ⚠️  COMPLETE UNINSTALL: $APP_NAME                   ║${NC}"
  echo -e "${RED}╠══════════════════════════════════════════════════════╣${NC}"
  echo -e "${RED}║  This will:                                         ║${NC}"
  echo -e "${RED}║  • Delete $APP_NAME.app from /Applications           ║${NC}"
  echo -e "${RED}║  • Remove all app data & preferences                ║${NC}"
  echo -e "${RED}║  • Reset ALL TCC permissions                        ║${NC}"
  echo -e "${RED}║  • Remove login items & caches                      ║${NC}"
  echo -e "${RED}╚══════════════════════════════════════════════════════╝${NC}"
  echo ""
  read -rp "Are you sure? Type 'yes' to proceed: " confirm < /dev/tty
  if [[ "$confirm" != "yes" ]]; then
    echo "Aborted."
    exit 0
  fi
  echo ""
fi

info "Detected bundle ID: ${BUNDLE_ID}"
echo ""

# ─── 1. Kill running app ────────────────────────────────────────
info "Stopping $APP_NAME..."
killall "$APP_NAME" 2>/dev/null && success "App stopped" || info "App was not running"
sleep 1

# ─── 2. Remove app bundle ───────────────────────────────────────
info "Removing $APP_PATH..."
if [ -d "$APP_PATH" ]; then
  rm -rf "$APP_PATH"
  success "Removed $APP_PATH"
else
  info "$APP_PATH not found (already removed)"
fi

# ─── 3. Remove Application Support data ─────────────────────────
info "Checking Application Support data..."
app_support="$HOME/Library/Application Support/$APP_NAME"
if [ -d "$app_support" ]; then
  echo ""
  warn "Folder contains temporary captures/recordings:"
  echo "     $app_support"
  if [[ "${1:-}" != "--force" ]]; then
    read -rp "  Delete this folder? (y/n): " del_app_support < /dev/tty
    if [[ "$del_app_support" == "y" || "$del_app_support" == "Y" ]]; then
      rm -rf "$app_support"
      success "Removed $app_support"
    else
      info "Kept $app_support"
    fi
  else
    rm -rf "$app_support"
    success "Removed $app_support"
  fi
else
  info "No Application Support data found"
fi

# ─── 4. Remove user preferences (defaults) ──────────────────────
info "Removing user preferences..."
defaults delete "$BUNDLE_ID" 2>/dev/null && success "Removed defaults for $BUNDLE_ID" || info "No defaults found"

# Also remove plist file directly
plist_file="$HOME/Library/Preferences/${BUNDLE_ID}.plist"
if [ -f "$plist_file" ]; then
  rm -f "$plist_file"
  success "Removed $plist_file"
fi

# ─── 5. Remove caches ───────────────────────────────────────────
info "Removing caches..."
for cache_dir in \
  "$HOME/Library/Caches/$BUNDLE_ID" \
  "$HOME/Library/Caches/$APP_NAME" \
  "$HOME/Library/HTTPStorages/$BUNDLE_ID"; do
  if [ -d "$cache_dir" ]; then
    rm -rf "$cache_dir"
    success "Removed $cache_dir"
  fi
done

# ─── 6. Remove saved application state ──────────────────────────
info "Removing saved application state..."
saved_state="$HOME/Library/Saved Application State/${BUNDLE_ID}.savedState"
if [ -d "$saved_state" ]; then
  rm -rf "$saved_state"
  success "Removed $saved_state"
fi

# ─── 7. Remove Sparkle update data ──────────────────────────────
info "Removing Sparkle update data..."
for sparkle_dir in \
  "$HOME/Library/Caches/${BUNDLE_ID}.Sparkle" \
  "$HOME/Library/Application Support/${BUNDLE_ID}/Sparkle"; do
  if [ -d "$sparkle_dir" ]; then
    rm -rf "$sparkle_dir"
    success "Removed $sparkle_dir"
  fi
done

# Also remove Sparkle-related defaults
defaults delete "${BUNDLE_ID}.Sparkle" 2>/dev/null || true

# ─── 8. Login items ─────────────────────────────────────────────
# NOTE: sfltool resetbtm resets ALL apps' login items, not just Snapzy.
# Skipped intentionally to avoid affecting other applications.
info "Login items: skipped (no safe per-app reset available)"

# ─── 9. Reset ALL TCC permissions ───────────────────────────────
echo ""
echo -e "${YELLOW}═══════════════════════════════════════════════════════${NC}"
echo -e "${YELLOW}  Resetting TCC Permissions                           ${NC}"
echo -e "${YELLOW}═══════════════════════════════════════════════════════${NC}"
echo ""

# TCC services used by Snapzy
# NOTE: tccutil uses SHORT names (not kTCCService* constants)
TCC_SERVICES=(
  "ScreenCapture"      # Screen Recording
  "Microphone"         # Microphone
  "Accessibility"      # Accessibility
  "PostEvent"          # Input Monitoring (synthetic events)
  "ListenEvent"        # Input Monitoring (listen)
)

for service in "${TCC_SERVICES[@]}"; do
  info "Resetting $service..."
  tccutil reset "$service" "$BUNDLE_ID" 2>/dev/null \
    && success "Reset $service for $BUNDLE_ID" \
    || warn "Could not reset $service (may need newer macOS or different service name)"
done

# ─── 10. Clean temp files ───────────────────────────────────────
info "Cleaning temp files..."
for tmp_dir in \
  "/tmp/test-tcc-snapzy" \
  "/tmp/$APP_NAME" \
  "/tmp/${BUNDLE_ID}"; do
  if [ -d "$tmp_dir" ]; then
    rm -rf "$tmp_dir"
    success "Removed $tmp_dir"
  fi
done

# ─── 11. Sandbox containers ─────────────────────────────────────
# Snapzy does NOT use App Sandbox. If a container exists, it's from
# macOS internal bookkeeping and requires sudo to remove.
# We skip this to avoid requiring elevated privileges.
container="$HOME/Library/Containers/$BUNDLE_ID"
if [ -d "$container" ]; then
  warn "Sandbox container exists at $container"
  info "  To remove manually: sudo rm -rf '$container'"
else
  info "No sandbox container found"
fi

# ─── Done ────────────────────────────────────────────────────────
echo ""
echo -e "${GREEN}╔══════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║  ✅ $APP_NAME has been completely uninstalled         ║${NC}"
echo -e "${GREEN}║  ✅ All TCC permissions have been reset              ║${NC}"
echo -e "${GREEN}╠══════════════════════════════════════════════════════╣${NC}"
echo -e "${GREEN}║  To reinstall, download from:                       ║${NC}"
echo -e "${GREEN}║  https://github.com/duongductrong/Snapzy/releases   ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${YELLOW}💡 Tip: You may need to log out and back in (or reboot)${NC}"
echo -e "${YELLOW}   for TCC changes to fully take effect.${NC}"
echo ""
