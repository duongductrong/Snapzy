#!/usr/bin/env bash
# test-keychain-update-local.sh — Verify keychain "Always Allow" persistence across app updates
#
# Usage:
#   ./scripts/test-keychain-update-local.sh verify-stable
#   ./scripts/test-keychain-update-local.sh verify-adhoc-control
#   ./scripts/test-keychain-update-local.sh probe
#   ./scripts/test-keychain-update-local.sh clean
#
# Notes:
# - Uses the app launch argument: --keychain-probe-cloud
# - Writes machine-readable reports to:
#   plans/260404-0843-cloud-keychain-persistence/reports/

set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TEST_DIR="/tmp/test-keychain-snapzy"
CERT_NAME="Snapzy Self-Signed"
ENTITLEMENTS="$PROJECT_DIR/Snapzy/Snapzy.entitlements"
INSTALL_PATH="/Applications/Snapzy.app"
REPORT_DIR="$PROJECT_DIR/plans/260404-0843-cloud-keychain-persistence/reports"
APP_BINARY="$INSTALL_PATH/Contents/MacOS/Snapzy"

mkdir -p "$REPORT_DIR"

check_cert() {
  echo "→ Checking for certificate '$CERT_NAME'..."
  if security find-identity -v -p codesigning | grep -q "$CERT_NAME"; then
    echo "  OK: Certificate found"
  else
    echo "  ERROR: Certificate '$CERT_NAME' not found in keychain"
    echo "  Run: ./scripts/create-signing-cert.sh"
    exit 1
  fi
}

sign_sparkle_framework() {
  local app_path="$1"
  local identity="$2"
  local sparkle="$app_path/Contents/Frameworks/Sparkle.framework"

  if [ ! -d "$sparkle" ]; then
    echo "  WARN: Sparkle.framework not found, skipping framework signing"
    return
  fi

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
  local archive_label="$1"
  local archive_path="$TEST_DIR/$archive_label/Snapzy.xcarchive"

  echo "=== Building archive ($archive_label) ==="
  mkdir -p "$TEST_DIR/$archive_label"

  if [ -d "$archive_path" ]; then
    echo "  Reusing existing archive at $archive_path"
    return
  fi

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
    > "$TEST_DIR/$archive_label/build.log" 2>&1

  if [ ! -d "$archive_path" ]; then
    echo "  ERROR: Build failed. Check $TEST_DIR/$archive_label/build.log"
    tail -20 "$TEST_DIR/$archive_label/build.log"
    exit 1
  fi

  echo "  OK: Archive built"
}

sign_and_install() {
  local build_label="$1"
  local identity="$2"
  local archive_label="${3:-$build_label}"
  local archive_path="$TEST_DIR/$archive_label/Snapzy.xcarchive"
  local app_path="$TEST_DIR/$build_label/Snapzy.app"

  echo "=== Signing $build_label (identity: $identity) ==="
  rm -rf "$app_path"
  ditto "$archive_path/Products/Applications/Snapzy.app" "$app_path"

  sign_sparkle_framework "$app_path" "$identity"

  local bundle_id
  local processed
  bundle_id=$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$app_path/Contents/Info.plist")
  processed="$TEST_DIR/processed-entitlements.plist"
  sed "s/\$(PRODUCT_BUNDLE_IDENTIFIER)/$bundle_id/g" "$ENTITLEMENTS" > "$processed"

  codesign \
    --force \
    --sign "$identity" \
    --entitlements "$processed" \
    --timestamp=none \
    "$app_path"

  codesign --verify --deep --strict "$app_path" >/dev/null 2>&1 || {
    echo "  ERROR: Signature verify failed for $build_label"
    exit 1
  }

  echo "=== Installing $build_label to $INSTALL_PATH ==="
  killall Snapzy 2>/dev/null || true
  sleep 1
  rm -rf "$INSTALL_PATH"
  ditto "$app_path" "$INSTALL_PATH"
}

probe_installed_app() {
  if [ ! -x "$APP_BINARY" ]; then
    echo "KC_ERROR_APP_BINARY_MISSING"
    return
  fi

  local output
  output=$("$APP_BINARY" --keychain-probe-cloud 2>&1 || true)
  local status
  status=$(printf '%s\n' "$output" | sed -n 's/^SNAPZY_KEYCHAIN_PROBE_STATUS=//p' | tail -1)

  if [ -z "$status" ]; then
    echo "KC_ERROR_NO_STATUS_OUTPUT"
    return
  fi

  echo "$status"
}

yes_no_to_bool() {
  local answer="$1"
  case "${answer,,}" in
    y|yes) echo "true" ;;
    *) echo "false" ;;
  esac
}

ask_prompt_seen() {
  local question="$1"
  local answer=""
  read -r -p "$question [y/N]: " answer
  yes_no_to_bool "$answer"
}

write_reports() {
  local scenario="$1"
  local signing_mode_v1="$2"
  local signing_mode_v2="$3"
  local status_before="$4"
  local status_after="$5"
  local prompt_reappeared="$6"
  local pass="$7"

  local json_path="$REPORT_DIR/phase-03-keychain-update-verification.json"
  local md_path="$REPORT_DIR/phase-03-keychain-update-verification.md"
  local generated_at
  generated_at=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

  cat > "$json_path" <<JSON
{
  "scenario": "$scenario",
  "generated_at": "$generated_at",
  "signing_mode_v1": "$signing_mode_v1",
  "signing_mode_v2": "$signing_mode_v2",
  "status_before_update": "$status_before",
  "status_after_update": "$status_after",
  "prompt_reappeared": $prompt_reappeared,
  "pass": $pass
}
JSON

  cat > "$md_path" <<MD
# Phase 03 Keychain Verification Report

- scenario: \`$scenario\`
- generated_at: \`$generated_at\`
- signing_mode_v1: \`$signing_mode_v1\`
- signing_mode_v2: \`$signing_mode_v2\`
- status_before_update: \`$status_before\`
- status_after_update: \`$status_after\`
- prompt_reappeared: \`$prompt_reappeared\`
- pass: \`$pass\`
MD

  echo "Report JSON: $json_path"
  echo "Report MD:   $md_path"
}

verify_stable() {
  check_cert
  build_archive "v1"

  sign_and_install "v1-stable" "$CERT_NAME" "v1"
  echo "Run probe on v1. If keychain prompt appears, choose 'Always Allow'."
  local status_before
  status_before=$(probe_installed_app)
  echo "Probe v1 status: $status_before"

  sign_and_install "v2-stable" "$CERT_NAME" "v1"
  echo "Run probe on v2. Expect no new keychain prompt."
  local status_after
  status_after=$(probe_installed_app)
  echo "Probe v2 status: $status_after"

  local prompt_reappeared
  prompt_reappeared=$(ask_prompt_seen "Did keychain prompt reappear on v2?")

  local pass="false"
  if [ "$status_before" = "KC_OK" ] && [ "$status_after" = "KC_OK" ] && [ "$prompt_reappeared" = "false" ]; then
    pass="true"
  fi

  write_reports "stable_identity_upgrade" "self-signed" "self-signed" "$status_before" "$status_after" "$prompt_reappeared" "$pass"

  if [ "$pass" = "true" ]; then
    echo "PASS: Stable identity keeps keychain trust across update."
  else
    echo "FAIL: Stable identity scenario did not meet expectations."
    exit 1
  fi
}

verify_adhoc_control() {
  check_cert
  build_archive "v1"

  sign_and_install "v1-stable" "$CERT_NAME" "v1"
  echo "Run probe on v1. If keychain prompt appears, choose 'Always Allow'."
  local status_before
  status_before=$(probe_installed_app)
  echo "Probe v1 status: $status_before"

  sign_and_install "v2-adhoc" "-" "v1"
  echo "Run probe on v2 ad-hoc. A prompt reappearance is expected."
  local status_after
  status_after=$(probe_installed_app)
  echo "Probe v2 status: $status_after"

  local prompt_reappeared
  prompt_reappeared=$(ask_prompt_seen "Did keychain prompt reappear on v2 ad-hoc?")

  local pass="false"
  if [ "$prompt_reappeared" = "true" ] || [ "$status_after" != "KC_OK" ]; then
    pass="true"
  fi

  write_reports "adhoc_negative_control" "self-signed" "ad-hoc" "$status_before" "$status_after" "$prompt_reappeared" "$pass"

  if [ "$pass" = "true" ]; then
    echo "PASS: Ad-hoc control reproduced expected regression behavior."
  else
    echo "FAIL: Ad-hoc control did not reproduce expected behavior."
    exit 1
  fi
}

cmd="${1:-help}"
case "$cmd" in
  verify-stable)
    verify_stable
    ;;
  verify-adhoc-control)
    verify_adhoc_control
    ;;
  probe)
    probe_installed_app
    ;;
  clean)
    echo "Cleaning test artifacts..."
    rm -rf "$TEST_DIR"
    echo "Done: $TEST_DIR removed"
    ;;
  help|*)
    echo "Usage: $0 <command>"
    echo ""
    echo "Commands:"
    echo "  verify-stable         Verify stable signing keeps keychain trust"
    echo "  verify-adhoc-control  Negative control with ad-hoc update"
    echo "  probe                 Run installed app keychain probe once"
    echo "  clean                 Remove local test artifacts"
    ;;
esac
