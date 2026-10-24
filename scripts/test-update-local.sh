#!/usr/bin/env bash
# test-update-local.sh — E2E test for Sparkle in-app update flow
#
# Purpose: Validate that Sparkle updates work locally before pushing
# to production. Supports two signing strategies to compare.
#
# Prerequisites:
#   - Self-signed cert "Snapzy Self-Signed" in keychain
#   - Sparkle EdDSA private key file (set SPARKLE_PRIVATE_KEY_FILE env var)
#
# Usage:
#   export SPARKLE_PRIVATE_KEY_FILE=~/path/to/sparkle_private_key.pem
#
#   ./scripts/test-update-local.sh test-current   # All self-signed (expect error 4005)
#   ./scripts/test-update-local.sh test-hybrid     # Hybrid signing (expect success)
#   ./scripts/test-update-local.sh clean           # Remove test artifacts
#
# Flow:
#   1. Builds archive once (reuses if exists)
#   2. Creates v1 (99.0.0) → signs → installs to /Applications
#   3. Creates v2 (99.0.1) → signs → creates DMG → signs DMG (EdDSA)
#   4. Generates local appcast.xml
#   5. Starts local HTTP server on port 8089
#   6. User opens app → Check for Updates → observes result

set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TEST_DIR="/tmp/test-sparkle-update"
CERT_NAME="Snapzy Self-Signed"
ENTITLEMENTS="$PROJECT_DIR/Snapzy/Snapzy.entitlements"
INSTALL_PATH="/Applications/Snapzy.app"
SERVER_PORT=8089

V1_VERSION="99.0.0"
V1_BUILD="990"
V2_VERSION="99.0.1"
V2_BUILD="991"
V3_VERSION="99.0.2-beta.1"
V3_BUILD="992"

BUNDLE_ID="com.duongductrong.Snapzy"
FEED_URL="http://localhost:${SERVER_PORT}/appcast.xml"

# ─── Helpers ────────────────────────────────────────────────────────

find_sign_update() {
  local bin
  bin=$(find "$PROJECT_DIR/build" -name "sign_update" -not -path "*/old_dsa_scripts/*" -type f 2>/dev/null | head -1)
  if [ -z "$bin" ]; then
    echo ""
    return
  fi
  chmod +x "$bin" 2>/dev/null || true
  echo "$bin"
}

check_prereqs() {
  echo "→ Checking prerequisites..."

  # Check cert
  if ! security find-identity -v -p codesigning | grep -q "$CERT_NAME"; then
    echo "  ❌ Certificate '$CERT_NAME' not found!"
    echo "     Run: ./scripts/create-signing-cert.sh"
    exit 1
  fi
  echo "  ✅ Certificate '$CERT_NAME' found"

  # Check EdDSA key
  if [ -z "${SPARKLE_PRIVATE_KEY_FILE:-}" ]; then
    echo "  ❌ SPARKLE_PRIVATE_KEY_FILE env var not set"
    echo "     Export it: export SPARKLE_PRIVATE_KEY_FILE=~/path/to/sparkle_key.pem"
    exit 1
  fi
  if [ ! -f "$SPARKLE_PRIVATE_KEY_FILE" ]; then
    echo "  ❌ EdDSA key file not found: $SPARKLE_PRIVATE_KEY_FILE"
    exit 1
  fi
  echo "  ✅ EdDSA key file found"

  # Check sign_update
  SIGN_UPDATE=$(find_sign_update)
  if [ -z "$SIGN_UPDATE" ]; then
    echo "  ❌ sign_update binary not found in build/"
    echo "     Build the project first (Cmd+B in Xcode) to populate SPM artifacts"
    exit 1
  fi
  echo "  ✅ sign_update found: $SIGN_UPDATE"
}

build_archive() {
  local archive_path="$TEST_DIR/archive/Snapzy.xcarchive"

  echo ""
  echo "=== Building archive ==="

  if [ -d "$archive_path" ]; then
    echo "  ♻️  Reusing existing archive (delete $TEST_DIR/archive to rebuild)"
    return
  fi

  mkdir -p "$TEST_DIR/archive"
  echo "  → Building (this may take a few minutes)..."

  if ! xcodebuild archive \
    -project "$PROJECT_DIR/Snapzy.xcodeproj" \
    -scheme Snapzy \
    -configuration Release \
    -archivePath "$archive_path" \
    -derivedDataPath "$TEST_DIR/DerivedData" \
    CODE_SIGN_IDENTITY="" \
    CODE_SIGNING_REQUIRED=NO \
    CODE_SIGNING_ALLOWED=NO \
    ONLY_ACTIVE_ARCH=NO \
    > "$TEST_DIR/archive/build.log" 2>&1; then
    echo "  ❌ Build failed! Last 20 lines:"
    tail -20 "$TEST_DIR/archive/build.log"
    exit 1
  fi

  echo "  ✅ Archive built"
}

patch_info_plist() {
  local app_path="$1"
  local version="$2"
  local build="$3"
  local feed_url="$4"
  local plist="$app_path/Contents/Info.plist"

  /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $version" "$plist"
  /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $build" "$plist"
  /usr/libexec/PlistBuddy -c "Set :SUFeedURL $feed_url" "$plist"
}

sign_sparkle_selfsigned() {
  local app_path="$1"
  local sparkle="$app_path/Contents/Frameworks/Sparkle.framework"

  if [ ! -d "$sparkle" ]; then
    echo "  ⚠️  Sparkle.framework not found, skipping"
    return
  fi

  echo "  → Signing Sparkle components with self-signed cert (inside-out)..."
  [ -d "$sparkle/Versions/B/XPCServices/Installer.xpc" ] && \
    codesign --force --sign "$CERT_NAME" -o runtime --timestamp=none "$sparkle/Versions/B/XPCServices/Installer.xpc"
  [ -d "$sparkle/Versions/B/XPCServices/Downloader.xpc" ] && \
    codesign --force --sign "$CERT_NAME" -o runtime --preserve-metadata=entitlements --timestamp=none "$sparkle/Versions/B/XPCServices/Downloader.xpc"
  [ -f "$sparkle/Versions/B/Autoupdate" ] && \
    codesign --force --sign "$CERT_NAME" -o runtime --timestamp=none "$sparkle/Versions/B/Autoupdate"
  [ -d "$sparkle/Versions/B/Updater.app" ] && \
    codesign --force --sign "$CERT_NAME" -o runtime --timestamp=none "$sparkle/Versions/B/Updater.app"
  codesign --force --sign "$CERT_NAME" -o runtime --timestamp=none "$sparkle"
}

sign_sparkle_adhoc() {
  local app_path="$1"
  local sparkle="$app_path/Contents/Frameworks/Sparkle.framework"

  if [ ! -d "$sparkle" ]; then
    echo "  ⚠️  Sparkle.framework not found, skipping"
    return
  fi

  echo "  → Signing Sparkle components AD-HOC (inside-out)..."
  [ -d "$sparkle/Versions/B/XPCServices/Installer.xpc" ] && \
    codesign --force --sign - -o runtime --timestamp=none "$sparkle/Versions/B/XPCServices/Installer.xpc"
  [ -d "$sparkle/Versions/B/XPCServices/Downloader.xpc" ] && \
    codesign --force --sign - -o runtime --preserve-metadata=entitlements --timestamp=none "$sparkle/Versions/B/XPCServices/Downloader.xpc"
  [ -f "$sparkle/Versions/B/Autoupdate" ] && \
    codesign --force --sign - -o runtime --timestamp=none "$sparkle/Versions/B/Autoupdate"
  [ -d "$sparkle/Versions/B/Updater.app" ] && \
    codesign --force --sign - -o runtime --timestamp=none "$sparkle/Versions/B/Updater.app"
  codesign --force --sign - -o runtime --timestamp=none "$sparkle"
}

# The embedded `snapzy` command line tool is signed before the app (inside-out).
sign_cli_helper() {
  local app_path="$1"
  local identity="$2"
  local helper="$app_path/Contents/Helpers/snapzy"

  if [ ! -f "$helper" ]; then
    echo "  ⚠️  snapzy command line tool not found, skipping"
    return
  fi

  echo "  → Signing snapzy command line tool with: $identity"
  codesign --force --sign "$identity" -o runtime --timestamp=none "$helper"
}

sign_main_app() {
  local app_path="$1"
  local identity="$2"

  # Pre-process entitlements: codesign does NOT substitute Xcode variables
  # like $(PRODUCT_BUNDLE_IDENTIFIER). We must do it manually or Sparkle's
  # XPC mach-lookup ports won't match (causes error 4005).
  local bundle_id
  bundle_id=$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$app_path/Contents/Info.plist")
  local processed="$TEST_DIR/processed-entitlements.plist"
  sed "s/\$(PRODUCT_BUNDLE_IDENTIFIER)/$bundle_id/g" "$ENTITLEMENTS" > "$processed"
  echo "  → Pre-processed entitlements with bundle ID: $bundle_id"

  echo "  → Signing main app with: $identity"
  codesign \
    --force \
    --sign "$identity" \
    --entitlements "$processed" \
    --timestamp=none \
    "$app_path"
}

prepare_version() {
  local label="$1"       # e.g. "v1" or "v2"
  local version="$2"     # e.g. "99.0.0"
  local build="$3"       # e.g. "990"
  local sign_mode="$4"   # "current" or "hybrid"
  local archive_path="$TEST_DIR/archive/Snapzy.xcarchive"
  local app_path="$TEST_DIR/$label/Snapzy.app"

  echo ""
  echo "=== Preparing $label (v$version, build $build, mode: $sign_mode) ==="

  rm -rf "$TEST_DIR/$label"
  mkdir -p "$TEST_DIR/$label"
  ditto "$archive_path/Products/Applications/Snapzy.app" "$app_path"

  # Patch version and feed URL
  echo "  → Patching Info.plist: v$version ($build), feed=$FEED_URL"
  patch_info_plist "$app_path" "$version" "$build" "$FEED_URL"

  # Sign Sparkle framework
  if [ "$sign_mode" = "hybrid" ]; then
    sign_sparkle_adhoc "$app_path"
  else
    sign_sparkle_selfsigned "$app_path"
  fi

  # Sign the CLI helper, then the main app (always self-signed for TCC)
  sign_cli_helper "$app_path" "$CERT_NAME"
  sign_main_app "$app_path" "$CERT_NAME"

  # Verify
  echo "  → Verifying signature..."
  codesign --verify --deep --strict "$app_path" 2>&1 && echo "  ✅ Signature valid" || echo "  ⚠️  Verification warning (may be ok for self-signed/hybrid)"

  echo "  → Signing identity:"
  codesign -dvv "$app_path" 2>&1 | grep -E "Authority|TeamIdentifier|CDHash" || true
}

install_v1() {
  echo ""
  echo "=== Installing v1 to $INSTALL_PATH ==="
  killall Snapzy 2>/dev/null || true
  sleep 1
  rm -rf "$INSTALL_PATH"
  ditto "$TEST_DIR/v1/Snapzy.app" "$INSTALL_PATH"
  echo "  ✅ v1 installed"
}

create_dmg() {
  local label="${1:-v2}"
  local dmg_name="${2:-Snapzy-test.dmg}"
  local dmg_path="$TEST_DIR/server/$dmg_name"

  echo ""
  echo "=== Creating DMG from $label ==="
  mkdir -p "$TEST_DIR/server"
  rm -f "$dmg_path"

  hdiutil create \
    -volname "Snapzy" \
    -srcfolder "$TEST_DIR/$label/Snapzy.app" \
    -ov -format UDZO \
    "$dmg_path" \
    > /dev/null 2>&1

  echo "  ✅ DMG created: $dmg_path"
}

sign_dmg_eddsa() {
  local dmg_name="${1:-Snapzy-test.dmg}"
  local dmg_path="$TEST_DIR/server/$dmg_name"

  echo ""
  echo "=== Signing DMG with Sparkle EdDSA ==="

  local SIGN_OUTPUT
  SIGN_OUTPUT=$("$SIGN_UPDATE" "$dmg_path" --ed-key-file "$SPARKLE_PRIVATE_KEY_FILE" 2>&1) || true
  ED_SIGNATURE=$(echo "$SIGN_OUTPUT" | grep 'sparkle:edSignature=' | cut -d'"' -f2)

  if [ -z "$ED_SIGNATURE" ]; then
    echo "  ⚠️  Could not extract EdDSA signature. sign_update output:"
    echo "  $SIGN_OUTPUT"
    echo "  Continuing without EdDSA (update may fail verification)..."
    ED_SIGNATURE=""
  else
    echo "  ✅ EdDSA signature: ${ED_SIGNATURE:0:40}..."
  fi
}

generate_appcast() {
  local dmg_path="$TEST_DIR/server/Snapzy-test.dmg"
  local appcast_path="$TEST_DIR/server/appcast.xml"

  echo ""
  echo "=== Generating local appcast.xml ==="

  local file_size
  file_size=$(stat -f%z "$dmg_path")
  local pub_date
  pub_date=$(date -u '+%a, %d %b %Y %H:%M:%S +0000')

  cat > "$appcast_path" <<EOF
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" xmlns:dc="http://purl.org/dc/elements/1.1/">
  <channel>
    <title>Snapzy Test Updates</title>
    <link>http://localhost:${SERVER_PORT}</link>
    <description>Local test appcast</description>
    <language>en</language>
    <item>
      <title>Version ${V2_VERSION}</title>
      <sparkle:version>${V2_BUILD}</sparkle:version>
      <sparkle:shortVersionString>${V2_VERSION}</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>
      <pubDate>${pub_date}</pubDate>
      <enclosure
        url="http://localhost:${SERVER_PORT}/Snapzy-test.dmg"
        sparkle:edSignature="${ED_SIGNATURE}"
        length="${file_size}"
        type="application/octet-stream"/>
    </item>
  </channel>
</rss>
EOF

  echo "  ✅ Appcast written to $appcast_path"
  echo "  → v${V2_VERSION} (build ${V2_BUILD}), size ${file_size} bytes"
}

generate_channel_appcast() {
  local stable_sig="$1"
  local beta_sig="$2"
  local appcast_path="$TEST_DIR/server/appcast.xml"

  echo ""
  echo "=== Generating local appcast.xml (stable + beta items) ==="

  local stable_size beta_size pub_date
  stable_size=$(stat -f%z "$TEST_DIR/server/Snapzy-test.dmg")
  beta_size=$(stat -f%z "$TEST_DIR/server/Snapzy-test-beta.dmg")
  pub_date=$(date -u '+%a, %d %b %Y %H:%M:%S +0000')

  cat > "$appcast_path" <<EOF
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" xmlns:dc="http://purl.org/dc/elements/1.1/">
  <channel>
    <title>Snapzy Test Updates</title>
    <link>http://localhost:${SERVER_PORT}</link>
    <description>Local test appcast</description>
    <language>en</language>
    <item>
      <title>Version ${V3_VERSION}</title>
      <sparkle:channel>beta</sparkle:channel>
      <sparkle:version>${V3_BUILD}</sparkle:version>
      <sparkle:shortVersionString>${V3_VERSION}</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>
      <pubDate>${pub_date}</pubDate>
      <enclosure
        url="http://localhost:${SERVER_PORT}/Snapzy-test-beta.dmg"
        sparkle:edSignature="${beta_sig}"
        length="${beta_size}"
        type="application/octet-stream"/>
    </item>
    <item>
      <title>Version ${V2_VERSION}</title>
      <sparkle:version>${V2_BUILD}</sparkle:version>
      <sparkle:shortVersionString>${V2_VERSION}</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>
      <pubDate>${pub_date}</pubDate>
      <enclosure
        url="http://localhost:${SERVER_PORT}/Snapzy-test.dmg"
        sparkle:edSignature="${stable_sig}"
        length="${stable_size}"
        type="application/octet-stream"/>
    </item>
  </channel>
</rss>
EOF

  echo "  ✅ Appcast written to $appcast_path"
  echo "  → stable: v${V2_VERSION} (build ${V2_BUILD}) | beta: v${V3_VERSION} (build ${V3_BUILD})"
}

start_server() {
  echo ""
  echo "=== Starting local HTTP server on port $SERVER_PORT ==="

  # Kill any existing server on this port
  lsof -ti:$SERVER_PORT | xargs kill 2>/dev/null || true
  sleep 0.5

  cd "$TEST_DIR/server"
  python3 -m http.server $SERVER_PORT &
  SERVER_PID=$!
  cd "$PROJECT_DIR"

  sleep 1

  if kill -0 $SERVER_PID 2>/dev/null; then
    echo "  ✅ Server running (PID: $SERVER_PID)"
    echo "  → Appcast: http://localhost:$SERVER_PORT/appcast.xml"
    echo "  → DMG:     http://localhost:$SERVER_PORT/Snapzy-test.dmg"
  else
    echo "  ❌ Server failed to start"
    exit 1
  fi
}

stop_server() {
  lsof -ti:$SERVER_PORT | xargs kill 2>/dev/null || true
}

# ─── Commands ───────────────────────────────────────────────────────

run_test() {
  local mode="$1"  # "current" or "hybrid"
  local mode_label
  if [ "$mode" = "current" ]; then
    mode_label="ALL SELF-SIGNED (should reproduce error 4005)"
  else
    mode_label="HYBRID — Sparkle ad-hoc + main self-signed (should work)"
  fi

  echo ""
  echo "╔══════════════════════════════════════════════════════════╗"
  echo "║  Sparkle Update E2E Test — $mode signing"
  echo "║  $mode_label"
  echo "╚══════════════════════════════════════════════════════════╝"

  check_prereqs
  build_archive

  prepare_version "v1" "$V1_VERSION" "$V1_BUILD" "$mode"
  prepare_version "v2" "$V2_VERSION" "$V2_BUILD" "$mode"

  install_v1
  create_dmg
  sign_dmg_eddsa
  generate_appcast
  start_server

  echo ""
  echo "╔══════════════════════════════════════════════════════════╗"
  echo "║  ✅ Ready for testing!                                  ║"
  echo "╠══════════════════════════════════════════════════════════╣"
  echo "║                                                          ║"
  echo "║  Mode: $mode"
  echo "║  Installed: v$V1_VERSION (build $V1_BUILD)"
  echo "║  Available: v$V2_VERSION (build $V2_BUILD)"
  echo "║                                                          ║"
  echo "║  Steps:                                                  ║"
  echo "║  1. Open Snapzy from /Applications                      ║"
  echo "║  2. Click menu bar icon → Preferences → About           ║"
  echo "║  3. Click 'Check for Updates'                            ║"
  echo "║  4. Observe: does the update install or error?           ║"
  echo "║                                                          ║"
  if [ "$mode" = "current" ]; then
  echo "║  Expected: ❌ Error 4005 (XPC connection invalidated)   ║"
  else
  echo "║  Expected: ✅ Update installs successfully              ║"
  fi
  echo "║                                                          ║"
  echo "║  Press Ctrl+C to stop the server when done.             ║"
  echo "╚══════════════════════════════════════════════════════════╝"
  echo ""

  # Keep server running until Ctrl+C
  trap 'echo ""; echo "→ Stopping server..."; stop_server; echo "✅ Done"; exit 0' INT TERM
  wait $SERVER_PID 2>/dev/null || true
}

run_channel_test() {
  echo ""
  echo "╔══════════════════════════════════════════════════════════╗"
  echo "║  Sparkle Update Channel Test — stable vs beta            ║"
  echo "╚══════════════════════════════════════════════════════════╝"

  check_prereqs
  build_archive

  prepare_version "v1" "$V1_VERSION" "$V1_BUILD" "hybrid"
  prepare_version "v2" "$V2_VERSION" "$V2_BUILD" "hybrid"
  prepare_version "v3" "$V3_VERSION" "$V3_BUILD" "hybrid"

  install_v1

  create_dmg "v2" "Snapzy-test.dmg"
  sign_dmg_eddsa "Snapzy-test.dmg"
  local stable_sig="$ED_SIGNATURE"

  create_dmg "v3" "Snapzy-test-beta.dmg"
  sign_dmg_eddsa "Snapzy-test-beta.dmg"
  local beta_sig="$ED_SIGNATURE"

  generate_channel_appcast "$stable_sig" "$beta_sig"
  start_server

  echo ""
  echo "╔══════════════════════════════════════════════════════════╗"
  echo "║  ✅ Ready for channel testing!                           ║"
  echo "╠══════════════════════════════════════════════════════════╣"
  echo "║                                                          ║"
  echo "║  Installed: v$V1_VERSION (build $V1_BUILD)"
  echo "║  Stable item: v$V2_VERSION (build $V2_BUILD)"
  echo "║  Beta item:   v$V3_VERSION (build $V3_BUILD, <sparkle:channel>beta)"
  echo "║                                                          ║"
  echo "║  Scenario A — stable channel (default):                  ║"
  echo "║    defaults delete $BUNDLE_ID updates.channel            ║"
  echo "║    Open Snapzy → About → Check for Updates               ║"
  echo "║    Expected: offered v$V2_VERSION, NEVER v$V3_VERSION"
  echo "║                                                          ║"
  echo "║  Scenario B — beta channel:                              ║"
  echo "║    In About tab set Update Channel = Beta, or:           ║"
  echo "║    defaults write $BUNDLE_ID updates.channel -string beta║"
  echo "║    Check for Updates                                     ║"
  echo "║    Expected: offered v$V3_VERSION"
  echo "║    Diagnostics log shows: Allowed channels: [beta]       ║"
  echo "║                                                          ║"
  echo "║  Teardown: defaults delete $BUNDLE_ID updates.channel    ║"
  echo "║  Press Ctrl+C to stop the server when done.              ║"
  echo "╚══════════════════════════════════════════════════════════╝"
  echo ""

  # Keep server running until Ctrl+C
  trap 'echo ""; echo "→ Stopping server..."; stop_server; echo "✅ Done"; exit 0' INT TERM
  wait $SERVER_PID 2>/dev/null || true
}

# ─── Main ───────────────────────────────────────────────────────────

cmd="${1:-help}"

case "$cmd" in
  test-current)
    run_test "current"
    ;;

  test-hybrid)
    run_test "hybrid"
    ;;

  test-channel)
    run_channel_test
    ;;

  clean)
    echo "Cleaning test artifacts..."
    stop_server
    killall Snapzy 2>/dev/null || true
    rm -rf "$TEST_DIR"
    defaults delete "$BUNDLE_ID" updates.channel 2>/dev/null || true
    echo "✅ Cleaned $TEST_DIR (and reset updates.channel pref)"
    echo ""
    echo "Note: /Applications/Snapzy.app was NOT removed."
    echo "Re-install from DMG or run test-tcc-local.sh to restore."
    ;;

  help|*)
    echo "Usage: $0 <command>"
    echo ""
    echo "Environment:"
    echo "  SPARKLE_PRIVATE_KEY_FILE   Path to Sparkle EdDSA private key (required)"
    echo ""
    echo "Commands:"
    echo "  test-current   Sign everything with self-signed cert (expect error 4005)"
    echo "  test-hybrid    Sparkle helpers ad-hoc + main app self-signed (expect success)"
    echo "  test-channel   Stable + beta appcast items; verify channel filtering"
    echo "  clean          Remove test artifacts, stop server, reset channel pref"
    echo ""
    echo "Test flow:"
    echo "  1. export SPARKLE_PRIVATE_KEY_FILE=~/path/to/key"
    echo "  2. ./scripts/test-update-local.sh test-current"
    echo "     → Open app → Check for Updates → observe error 4005"
    echo "  3. ./scripts/test-update-local.sh test-hybrid"
    echo "     → Open app → Check for Updates → observe successful update"
    ;;
esac
