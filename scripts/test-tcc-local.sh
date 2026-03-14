#!/usr/bin/env bash
# test-tcc-local.sh — Test TCC permission persistence with self-signed cert
#
# Usage:
#   ./scripts/test-tcc-local.sh build-v1    # Build, sign, install v1
#   ./scripts/test-tcc-local.sh build-v2    # Build, sign, replace (simulates Sparkle update)
#   ./scripts/test-tcc-local.sh compare     # Build ad-hoc version for comparison
#
# Flow:
#   1. Run `build-v1`  → open app → grant Screen Recording + Microphone
#   2. Run `build-v2`  → open app → check permissions still granted ✅
#   3. (Optional) Run `compare` → open app → permissions lost ❌

set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TEST_DIR="/tmp/test-tcc-snapzy"
CERT_NAME="Snapzy Self-Signed"
ENTITLEMENTS="$PROJECT_DIR/Snapzy/Snapzy.entitlements"
INSTALL_PATH="/Applications/Snapzy.app"

sign_sparkle_framework() {
  local app_path="$1"
  local identity="$2"
  local sparkle="$app_path/Contents/Frameworks/Sparkle.framework"

  if [ ! -d "$sparkle" ]; then
    echo "  ⚠️  Sparkle.framework not found, skipping framework signing"
    return
  fi

  echo "  → Signing Sparkle components (inside-out)..."
  [ -d "$sparkle/Versions/B/XPCServices/Installer.xpc" ] && \
    codesign --force --sign "$identity" -o runtime --timestamp=none "$sparkle/Versions/B/XPCServices/Installer.xpc"
  [ -d "$sparkle/Versions/B/XPCServices/Downloader.xpc" ] && \
    codesign --force --sign "$identity" -o runtime --preserve-metadata=entitlements --timestamp=none "$sparkle/Versions/B/XPCServices/Downloader.xpc"
  [ -f "$sparkle/Versions/B/Autoupdate" ] && \
    codesign --force --sign "$identity" -o runtime --timestamp=none "$sparkle/Versions/B/Autoupdate"
  [ -d "$sparkle/Versions/B/Updater.app" ] && \
    codesign --force --sign "$identity" -o runtime --timestamp=none "$sparkle/Versions/B/Updater.app"
  [ -d "$sparkle" ] && \
    codesign --force --sign "$identity" -o runtime --timestamp=none "$sparkle"
}

build_archive() {
  local version_label="$1"
  local archive_path="$TEST_DIR/$version_label/Snapzy.xcarchive"

  echo "=== Building archive ($version_label) ==="
  mkdir -p "$TEST_DIR/$version_label"

  # Reuse existing archive if available (faster iteration)
  if [ -d "$archive_path" ]; then
    echo "  ♻️  Reusing existing archive at $archive_path"
    return
  fi

  echo "  → Building (this may take a few minutes)..."
  xcodebuild archive \
    -project "$PROJECT_DIR/Snapzy.xcodeproj" \
    -scheme Snapzy \
    -configuration Release \
    -archivePath "$archive_path" \
    -derivedDataPath "$TEST_DIR/DerivedData" \
    CODE_SIGN_IDENTITY="" \
    CODE_SIGNING_REQUIRED=NO \
    CODE_SIGNING_ALLOWED=NO \
    ONLY_ACTIVE_ARCH=NO \
    > "$TEST_DIR/$version_label/build.log" 2>&1

  if [ ! -d "$archive_path" ]; then
    echo "  ❌ Build failed! Check $TEST_DIR/$version_label/build.log"
    tail -20 "$TEST_DIR/$version_label/build.log"
    exit 1
  fi

  echo "  ✅ Archive built"
}

sign_and_install() {
  local version_label="$1"
  local identity="$2"
  local archive_label="${3:-$version_label}"  # defaults to version_label if not specified
  local archive_path="$TEST_DIR/$archive_label/Snapzy.xcarchive"
  local app_path="$TEST_DIR/$version_label/Snapzy.app"

  echo "=== Signing ($version_label) with identity: $identity ==="

  # Copy from archive
  rm -rf "$app_path"
  ditto "$archive_path/Products/Applications/Snapzy.app" "$app_path"

  # Sign Sparkle framework
  sign_sparkle_framework "$app_path" "$identity"

  # Sign main app
  echo "  → Signing main app bundle..."
  codesign \
    --force \
    --sign "$identity" \
    --entitlements "$ENTITLEMENTS" \
    --timestamp=none \
    "$app_path"

  # Verify
  echo "  → Verifying signature..."
  codesign --verify --deep --strict "$app_path" 2>&1 && echo "  ✅ Signature valid" || echo "  ⚠️  Verification warning (may be ok for self-signed)"

  # Show signing info
  echo "  → Signing identity:"
  codesign -dvv "$app_path" 2>&1 | grep -E "Authority|TeamIdentifier|CDHash" || true

  # Install
  echo "  → Installing to $INSTALL_PATH..."
  # Kill app if running
  killall Snapzy 2>/dev/null || true
  sleep 1
  rm -rf "$INSTALL_PATH"
  ditto "$app_path" "$INSTALL_PATH"

  echo ""
  echo "============================================"
  echo "✅ $version_label installed to $INSTALL_PATH"
  echo "============================================"
}

check_cert() {
  echo "→ Checking for certificate '$CERT_NAME'..."
  if security find-identity -v -p codesigning | grep -q "$CERT_NAME"; then
    echo "  ✅ Certificate found"
  else
    echo "  ❌ Certificate '$CERT_NAME' not found in keychain!"
    echo ""
    echo "  Run this first to generate and import the cert:"
    echo "    ./scripts/create-signing-cert.sh"
    echo ""
    echo "  Then import the .p12 into your login keychain:"
    echo "    security import /path/to/signing-cert.p12 -P <password> -k ~/Library/Keychains/login.keychain-db"
    exit 1
  fi
}

cmd="${1:-help}"

case "$cmd" in
  build-v1)
    check_cert
    build_archive "v1"
    sign_and_install "v1" "$CERT_NAME"
    echo ""
    echo "📋 Next steps:"
    echo "   1. Open Snapzy from /Applications"
    echo "   2. Grant Screen Recording permission in System Settings"
    echo "   3. Grant Microphone permission (if prompted)"
    echo "   4. Run: ./scripts/test-tcc-local.sh build-v2"
    ;;

  build-v2)
    check_cert
    build_archive "v1"  # Reuse same archive (simulating same-source update)
    sign_and_install "v2" "$CERT_NAME" "v1"
    echo ""
    echo "📋 Check:"
    echo "   1. Open Snapzy from /Applications"
    echo "   2. Verify Screen Recording + Microphone permissions are STILL granted ✅"
    echo "   3. (Optional) Run: ./scripts/test-tcc-local.sh compare"
    ;;

  compare)
    echo "=== Ad-hoc comparison build ==="
    build_archive "v1"  # Reuse same archive
    sign_and_install "adhoc" "-" "v1"
    echo ""
    echo "📋 Check:"
    echo "   1. Open Snapzy from /Applications"
    echo "   2. Observe: permissions are LOST ❌ (expected with ad-hoc)"
    ;;

  clean)
    echo "Cleaning test artifacts..."
    rm -rf "$TEST_DIR"
    echo "✅ Cleaned $TEST_DIR"
    ;;

  help|*)
    echo "Usage: $0 <command>"
    echo ""
    echo "Commands:"
    echo "  build-v1   Build, sign with self-signed cert, install as v1"
    echo "  build-v2   Re-sign and replace (simulates Sparkle update)"
    echo "  compare    Build ad-hoc version to prove permissions are lost"
    echo "  clean      Remove test build artifacts"
    echo ""
    echo "Test flow:"
    echo "  1. ./scripts/test-tcc-local.sh build-v1"
    echo "     → Open app, grant permissions"
    echo "  2. ./scripts/test-tcc-local.sh build-v2"
    echo "     → Open app, verify permissions still granted ✅"
    echo "  3. ./scripts/test-tcc-local.sh compare"
    echo "     → Open app, verify permissions are LOST ❌"
    ;;
esac
