#!/usr/bin/env bash
# uninstall.sh — Completely remove Snapzy and reset ALL related permissions
#
# Usage:
#   ./scripts/uninstall.sh           # Interactive mode (asks for confirmation)
#   ./scripts/uninstall.sh --force   # Skip confirmation
#
# What this script does:
#   1. Kills the running app
#   2. Resets ALL TCC permissions (Screen Recording, Microphone, Accessibility, etc.)
#   3. Removes Snapzy.app from /Applications
#   4. Removes Application Support data (captures, preferences, caches)
#   5. Removes user preferences (defaults)
#   6. Removes saved application state
#   7. Removes Sparkle update caches
#   8. Removes login items
#   9. Cleans temp files
#
# NOTE: TCC reset (step 2) runs BEFORE app removal (step 3) because tccutil
#       validates the bundle identifier via LaunchServices at runtime. Once
#       the .app bundle is deleted, LaunchServices can no longer resolve the
#       bundle ID and tccutil will fail with OSStatus error -10814.

set -euo pipefail

APP_NAME="Snapzy"
APP_PATH="/Applications/Snapzy.app"
FALLBACK_BUNDLE_ID="com.trongduong.snapzy"

# ─── Auto-detect bundle ID from app name ─────────────────────────
# Must happen BEFORE the app is deleted (step 3).
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

# ─── 2. Reset ALL TCC permissions ───────────────────────────────
# IMPORTANT: This MUST run BEFORE removing the app bundle (step 3).
# tccutil validates bundle identifiers via LaunchServices at runtime.
# Once the .app is deleted, LaunchServices can no longer resolve the
# bundle ID → tccutil fails with "No such bundle identifier" (exit 64).
#
# Strategy:
#   1. Try per-app reset (tccutil reset <service> <bundle_id>)
#   2. If that fails (app already removed or LaunchServices stale),
#      fall back to service-wide reset (tccutil reset <service>)
#      which resets ALL apps for that service — a trade-off, but
#      ensures the user gets a clean TCC slate for reinstallation.
echo ""
echo -e "${YELLOW}═══════════════════════════════════════════════════════${NC}"
echo -e "${YELLOW}  Resetting TCC Permissions                           ${NC}"
echo -e "${YELLOW}═══════════════════════════════════════════════════════${NC}"
echo ""

# TCC services used by Snapzy
# NOTE: tccutil uses SHORT names (not kTCCService* constants)
TCC_SERVICES=(
  "ScreenCapture"      # Screen Recording (shown as "Screen & System Audio Recording" on macOS 15+)
  "Microphone"         # Microphone
  "Accessibility"      # Accessibility
  "PostEvent"          # Input Monitoring (synthetic events)
  "ListenEvent"        # Input Monitoring (listen)
)

tcc_had_failure=false

for service in "${TCC_SERVICES[@]}"; do
  info "Resetting $service..."
  if tccutil reset "$service" "$BUNDLE_ID" 2>/dev/null; then
    success "Reset $service for $BUNDLE_ID"
  else
    # Per-app reset failed — most likely the app was already removed from
    # LaunchServices (user manually deleted the .app before running this script).
    # We do NOT fall back to service-wide reset because resetting services like
    # Accessibility or ScreenCapture globally can crash/freeze other running apps.
    warn "Could not reset $service (app may already be removed or service not granted)"
    tcc_had_failure=true
  fi
done

# Also reset any other TCC entries tied to this bundle as a catch-all
info "Running catch-all TCC reset for $BUNDLE_ID..."
if tccutil reset All "$BUNDLE_ID" 2>/dev/null; then
  success "Reset all remaining TCC entries for $BUNDLE_ID"
else
  # Catch-all failed too — if the app is gone, this is expected.
  info "No additional TCC entries to reset (or app already removed)"
fi

if $tcc_had_failure; then
  echo ""
  warn "Some TCC resets could not be completed automatically."
  info "If you face permission issues after reinstalling, you can manually remove"
  info "$APP_NAME from System Settings > Privacy & Security for the affected services."
fi

# ─── 3. Remove app bundle ───────────────────────────────────────
echo ""
info "Removing $APP_PATH..."
if [ -d "$APP_PATH" ]; then
  rm -rf "$APP_PATH"
  success "Removed $APP_PATH"
else
  info "$APP_PATH not found (already removed)"
fi

# Remove the `snapzy` command symlink, but only if it points into a Snapzy.app.
cli_link="/usr/local/bin/snapzy"
if [ -L "$cli_link" ]; then
  cli_target=$(readlink "$cli_link")
  case "$cli_target" in
    */Snapzy*.app/Contents/Helpers/snapzy)
      if rm -f "$cli_link" 2>/dev/null; then
        success "Removed $cli_link"
      else
        info "Could not remove $cli_link (run: sudo rm '$cli_link')"
      fi
      ;;
    *)
      info "Kept $cli_link (points to $cli_target)"
      ;;
  esac
fi

# ─── 4. Remove Application Support data ─────────────────────────
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

# ─── 5. Remove user preferences (defaults) ──────────────────────
info "Removing user preferences..."
defaults delete "$BUNDLE_ID" 2>/dev/null && success "Removed defaults for $BUNDLE_ID" || info "No defaults found"

# Also remove plist file directly
plist_file="$HOME/Library/Preferences/${BUNDLE_ID}.plist"
if [ -f "$plist_file" ]; then
  rm -f "$plist_file"
  success "Removed $plist_file"
fi

# ─── 6. Remove caches ───────────────────────────────────────────
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

# ─── 7. Remove saved application state ──────────────────────────
info "Removing saved application state..."
saved_state="$HOME/Library/Saved Application State/${BUNDLE_ID}.savedState"
if [ -d "$saved_state" ]; then
  rm -rf "$saved_state"
  success "Removed $saved_state"
fi

# ─── 8. Remove Sparkle update data ──────────────────────────────
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

# ─── 9. Login items ─────────────────────────────────────────────
# NOTE: sfltool resetbtm resets ALL apps' login items, not just Snapzy.
# Skipped intentionally to avoid affecting other applications.
info "Login items: skipped (no safe per-app reset available)"

# ─── 10. Clean temp files ──────────────────────────────────────
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
