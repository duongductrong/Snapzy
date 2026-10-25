#!/usr/bin/env bash
# Dry-run release build, signing, and verification script
# Allows testing the signing logic locally on a macOS machine without Apple Developer certificate secrets.
set -euo pipefail

APP_NAME="Snapzy"
PROJECT="Snapzy.xcodeproj"
BUILD_DIR="build"
ARCHIVE_PATH="$BUILD_DIR/Snapzy.xcarchive"
APP_PATH="$BUILD_DIR/Snapzy.app"
SPARKLE_FRAMEWORK="$APP_PATH/Contents/Frameworks/Sparkle.framework"

# Colors for output
if [[ -t 1 ]]; then
  BLUE=$'\033[0;34m'
  GREEN=$'\033[0;32m'
  RED=$'\033[0;31m'
  YELLOW=$'\033[0;33m'
  BOLD=$'\033[1m'
  NC=$'\033[0m'
else
  BLUE=""
  GREEN=""
  RED=""
  YELLOW=""
  BOLD=""
  NC=""
fi

info() { printf "%sinfo:%s %s\n" "$BLUE$BOLD" "$NC" "$1"; }
success() { printf "%ssuccess:%s %s\n" "$GREEN$BOLD" "$NC" "$1"; }
warn() { printf "%swarning:%s %s\n" "$YELLOW$BOLD" "$NC" "$1"; }
fail() { printf "%serror:%s %s\n" "$RED$BOLD" "$NC" "$1" >&2; exit 1; }

# Step 1: Requirements Check
[[ "$(uname -s)" == "Darwin" ]] || fail "This script only runs on macOS."
command -v xcodebuild >/dev/null 2>&1 || fail "Xcode Command Line Tools are required (xcodebuild not found)."
command -v codesign >/dev/null 2>&1 || fail "codesign utility is required."

# Clean previous build directories
info "Cleaning previous build output..."
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

# Step 2: Build Release Archive (Unsigned)
info "Archiving Snapzy app (without signing)..."
xcodebuild -project "$PROJECT" \
  -scheme "$APP_NAME" \
  -configuration Release \
  CODE_SIGN_IDENTITY="" \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGNING_ALLOWED=NO \
  archive -archivePath "$ARCHIVE_PATH" \
  > /dev/null || fail "xcodebuild archive failed."
success "Archive created at $ARCHIVE_PATH"

# Step 3: Ditto from archive
info "Extracting app bundle from archive..."
if [ ! -d "$ARCHIVE_PATH/Products/Applications/Snapzy.app" ]; then
  fail "Archive does not contain Snapzy.app at expected path."
fi
ditto "$ARCHIVE_PATH/Products/Applications/Snapzy.app" "$APP_PATH"
success "App bundle extracted to $APP_PATH"

# Step 4: Dry-Run Codesigning (using Ad-hoc identity "-" to test the CI pipeline structure)
info "Starting dry-run ad-hoc codesigning (simulating non-Developer ID environment)..."
SIGN_IDENTITY="-"
TIMESTAMP_FLAG="--timestamp=none"

# Clean extended attributes
info "Cleaning extended attributes..."
xattr -rc "$APP_PATH"

# Sign Sparkle components inside-out (exact same logic as CI)
info "Signing Sparkle framework sub-components..."
if [ -d "$SPARKLE_FRAMEWORK/Versions/B/XPCServices/Installer.xpc" ]; then
  info "Signing Installer.xpc..."
  codesign --force --sign "$SIGN_IDENTITY" -o runtime $TIMESTAMP_FLAG \
    "$SPARKLE_FRAMEWORK/Versions/B/XPCServices/Installer.xpc"
fi
if [ -d "$SPARKLE_FRAMEWORK/Versions/B/XPCServices/Downloader.xpc" ]; then
  info "Signing Downloader.xpc..."
  codesign --force --sign "$SIGN_IDENTITY" -o runtime --preserve-metadata=entitlements \
    $TIMESTAMP_FLAG "$SPARKLE_FRAMEWORK/Versions/B/XPCServices/Downloader.xpc"
fi
if [ -f "$SPARKLE_FRAMEWORK/Versions/B/Autoupdate" ]; then
  info "Signing Autoupdate tool..."
  codesign --force --sign "$SIGN_IDENTITY" -o runtime $TIMESTAMP_FLAG \
    "$SPARKLE_FRAMEWORK/Versions/B/Autoupdate"
fi
if [ -d "$SPARKLE_FRAMEWORK/Versions/B/Updater.app" ]; then
  info "Signing Updater.app..."
  codesign --force --sign "$SIGN_IDENTITY" -o runtime $TIMESTAMP_FLAG \
    "$SPARKLE_FRAMEWORK/Versions/B/Updater.app"
fi
if [ -d "$SPARKLE_FRAMEWORK" ]; then
  info "Signing Sparkle.framework main bundle..."
  codesign --force --sign "$SIGN_IDENTITY" -o runtime $TIMESTAMP_FLAG \
    "$SPARKLE_FRAMEWORK"
fi

# Sign the embedded `snapzy` command line tool before the app (inside-out)
CLI_HELPER="$APP_PATH/Contents/Helpers/snapzy"
[ -f "$CLI_HELPER" ] || fail "snapzy command line tool not found at $CLI_HELPER"
info "Signing embedded snapzy command line tool..."
codesign --force --sign "$SIGN_IDENTITY" -o runtime $TIMESTAMP_FLAG "$CLI_HELPER"

# Pre-process entitlements
info "Substituting entitlements template..."
BUNDLE_ID=$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$APP_PATH/Contents/Info.plist")
PROCESSED_ENTITLEMENTS="$BUILD_DIR/processed-entitlements-dryrun.plist"
sed "s/\$(PRODUCT_BUNDLE_IDENTIFIER)/$BUNDLE_ID/g" Snapzy/Snapzy.entitlements > "$PROCESSED_ENTITLEMENTS"
info "Processed entitlements created with bundle ID: $BUNDLE_ID"

# Sign main app bundle
info "Signing Snapzy.app main bundle (with hardened runtime)..."
codesign --force --sign "$SIGN_IDENTITY" \
  -o runtime \
  --entitlements "$PROCESSED_ENTITLEMENTS" \
  $TIMESTAMP_FLAG \
  "$APP_PATH"

success "App bundle signed successfully"

# Step 5: Verify App Bundle
info "Verifying signature and deep constraints..."
codesign --verify --deep --strict --verbose=4 "$APP_PATH"
codesign -dv --verbose=4 "$APP_PATH"

# Verify hardened runtime flag
info "Verifying hardened runtime..."
HR_FLAGS=$(codesign -dvvv "$APP_PATH" 2>&1 | grep "flags=" || true)
if ! echo "$HR_FLAGS" | grep -q "runtime"; then
  fail "Hardened runtime flag (0x10000) not found in signed binary."
fi
success "Hardened runtime verified: $HR_FLAGS"

# Step 6: Create DMG (optional preview)
if command -v create-dmg >/dev/null 2>&1; then
  info "create-dmg found. Generating preview DMG..."
  create-dmg \
    --volname "Snapzy" \
    --background "assets/dmg-background.png" \
    --window-size 660 400 \
    --icon-size 120 \
    --icon "Snapzy.app" 180 170 \
    --app-drop-link 480 170 \
    --no-internet-enable \
    "$BUILD_DIR/Snapzy-dryrun.dmg" \
    "$APP_PATH"
  success "Preview DMG created at $BUILD_DIR/Snapzy-dryrun.dmg"
else
  warn "create-dmg not installed. Skipping DMG packaging preview (install with 'brew install create-dmg' to test)."
fi

success "Dry-run release and signing validation complete. All commands ran perfectly."
