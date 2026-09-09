#!/bin/bash
# Run the Snapzy XCTest suite with CI-like local settings.
#
# Usage:
#   ./scripts/run-tests.sh
#   ./scripts/run-tests.sh -only-testing:SnapzyTests/SomeTests
#   ./scripts/run-tests.sh --open-result

set -euo pipefail

PROJECT="${PROJECT:-Snapzy.xcodeproj}"
SCHEME="${SCHEME:-Snapzy}"
CONFIGURATION="${CONFIGURATION:-Debug}"
DESTINATION="${DESTINATION:-platform=macOS}"
BUILD_DIR="${BUILD_DIR:-build}"
DERIVED_DATA_PATH="${DERIVED_DATA_PATH:-${BUILD_DIR}/DerivedData}"
# If running in CI, default to local package cache to avoid caching issues on CI runners.
# Otherwise, default to empty to let xcodebuild use the user's global SwiftPM cache for speed.
if [[ -n "${CI:-}" || -n "${GITHUB_ACTIONS:-}" ]]; then
  SOURCE_PACKAGES_PATH="${SOURCE_PACKAGES_PATH:-${BUILD_DIR}/SourcePackages}"
else
  SOURCE_PACKAGES_PATH="${SOURCE_PACKAGES_PATH:-}"
fi
MODULE_CACHE_PATH="${MODULE_CACHE_PATH:-${BUILD_DIR}/swift-module-cache}"
RESULT_BUNDLE_PATH="${RESULT_BUNDLE_PATH:-${BUILD_DIR}/ci-test.xcresult}"
LOG_PATH="${LOG_PATH:-${BUILD_DIR}/ci-test.log}"
KEEP_RESULT=0
OPEN_RESULT=0
XCODEBUILD_ARGS=()

if [ -t 1 ]; then
  BOLD=$'\033[1m'
  BLUE=$'\033[0;34m'
  GREEN=$'\033[0;32m'
  RED=$'\033[0;31m'
  YELLOW=$'\033[0;33m'
  RESET=$'\033[0m'
else
  BOLD=""
  BLUE=""
  GREEN=""
  RED=""
  YELLOW=""
  RESET=""
fi

info() { printf "%binfo:%b %s\n" "${BLUE}${BOLD}" "$RESET" "$*"; }
success() { printf "%bsuccess:%b %s\n" "${GREEN}${BOLD}" "$RESET" "$*"; }
warn() { printf "%bwarning:%b %s\n" "${YELLOW}${BOLD}" "$RESET" "$*" >&2; }
error() { printf "%berror:%b %s\n" "${RED}${BOLD}" "$RESET" "$*" >&2; }
die() {
  error "$*"
  exit 1
}

usage() {
  cat <<EOF
Usage: $0 [OPTIONS] [XCODEBUILD_TEST_OPTIONS]

Runs xcodebuild test with local build artifacts under ./build.

Options:
  --configuration NAME   Xcode configuration. Default: ${CONFIGURATION}
  --destination VALUE    Xcode destination. Default: ${DESTINATION}
  --derived-data PATH    DerivedData path. Default: ${DERIVED_DATA_PATH}
  --log PATH             Test log path. Default: ${LOG_PATH}
  --open-result          Open the .xcresult bundle when done.
  --result-bundle PATH   Result bundle path. Default: ${RESULT_BUNDLE_PATH}
  --source-packages PATH SwiftPM package cache path. Default: ${SOURCE_PACKAGES_PATH}
  --keep-result          Do not remove the previous result bundle before running.
  -h, --help             Show this help.

Examples:
  $0
  $0 -only-testing:SnapzyTests/CaptureOutputNamingTests
  SNAPZY_RUN_MICROPHONE_INTEGRATION=1 $0 -only-testing:SnapzyTests/MicrophoneAudioCapturerTests/testMicrophoneAudioCapturerStartStopRealMicrophoneIntegration
EOF
}

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    die "$1 not found. Install Xcode Command Line Tools first."
  fi
}

take_value() {
  local option="$1"
  local value="${2:-}"
  if [ -z "$value" ]; then
    die "$option requires a value"
  fi
  printf "%s" "$value"
}

while [ $# -gt 0 ]; do
  case "$1" in
    --configuration)
      CONFIGURATION="$(take_value "$1" "${2:-}")"
      shift 2
      ;;
    --destination)
      DESTINATION="$(take_value "$1" "${2:-}")"
      shift 2
      ;;
    --derived-data)
      DERIVED_DATA_PATH="$(take_value "$1" "${2:-}")"
      shift 2
      ;;
    --log)
      LOG_PATH="$(take_value "$1" "${2:-}")"
      shift 2
      ;;
    --open-result)
      OPEN_RESULT=1
      shift
      ;;
    --result-bundle)
      RESULT_BUNDLE_PATH="$(take_value "$1" "${2:-}")"
      shift 2
      ;;
    --source-packages)
      SOURCE_PACKAGES_PATH="$(take_value "$1" "${2:-}")"
      shift 2
      ;;
    --keep-result)
      KEEP_RESULT=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    --)
      shift
      while [ $# -gt 0 ]; do
        XCODEBUILD_ARGS+=("$1")
        shift
      done
      ;;
    *)
      XCODEBUILD_ARGS+=("$1")
      shift
      ;;
  esac
done

if [ "$(uname -s)" != "Darwin" ]; then
  die "This script requires macOS."
fi

require_command xcodebuild
require_command grep
require_command tail

mkdir_paths=("$BUILD_DIR" "$DERIVED_DATA_PATH" "$MODULE_CACHE_PATH")
if [[ -n "$SOURCE_PACKAGES_PATH" ]]; then
  mkdir_paths+=("$SOURCE_PACKAGES_PATH")
fi
mkdir -p "${mkdir_paths[@]}"

if [ "$KEEP_RESULT" -eq 0 ]; then
  rm -rf "$RESULT_BUNDLE_PATH"
fi

info "Running ${SCHEME} tests"
info "Log: ${LOG_PATH}"
info "Result bundle: ${RESULT_BUNDLE_PATH}"

set +e
set +u
XCODEBUILD_CMD=(
  xcodebuild
  -project "$PROJECT"
  -scheme "$SCHEME"
  -configuration "$CONFIGURATION"
  -destination "$DESTINATION"
  -derivedDataPath "$DERIVED_DATA_PATH"
  -resultBundlePath "$RESULT_BUNDLE_PATH"
)

if [[ -n "${CI:-}" || -n "${GITHUB_ACTIONS:-}" ]]; then
  XCODEBUILD_CMD+=(
    CODE_SIGN_IDENTITY=
    CODE_SIGNING_REQUIRED=NO
    CODE_SIGNING_ALLOWED=NO
  )
fi

if [[ -n "$SOURCE_PACKAGES_PATH" ]]; then
  XCODEBUILD_CMD+=(-clonedSourcePackagesDirPath "$SOURCE_PACKAGES_PATH")
fi

CLANG_MODULE_CACHE_PATH="$MODULE_CACHE_PATH" "${XCODEBUILD_CMD[@]}" "${XCODEBUILD_ARGS[@]}" test > "$LOG_PATH" 2>&1
STATUS=$?
set -u
set -e

if [ "$STATUS" -ne 0 ]; then
  error "Tests failed with status ${STATUS}."
  if [ -f "$LOG_PATH" ]; then
    warn "Likely failures:"
    grep -E "Test [Cc]ase '.*' (failed|skipped)|Test crashed|malloc:|Failing tests:|\\*\\* TEST FAILED \\*\\*|error:" "$LOG_PATH" || true
    warn "Last 200 log lines:"
    tail -200 "$LOG_PATH"
  fi
  exit "$STATUS"
fi

if [ -f "$LOG_PATH" ]; then
  tail -20 "$LOG_PATH"
fi

success "Tests passed."

if [ "$OPEN_RESULT" -eq 1 ]; then
  open "$RESULT_BUNDLE_PATH"
fi
