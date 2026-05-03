#!/bin/bash
# Compile and run the local Vision QR detector timing probe.
#
# Usage:
#   ./scripts/run-qr-detection-performance-probe.sh

set -euo pipefail

if [ "$(uname -s)" != "Darwin" ]; then
  echo "::error::This probe requires macOS." >&2
  exit 1
fi

if ! command -v swiftc >/dev/null 2>&1; then
  echo "::error::swiftc not found. Install Xcode Command Line Tools first." >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
TMP_ROOT="${TMPDIR:-/tmp}"
BINARY_PATH="${TMP_ROOT%/}/snapzy-qr-detection-probe"
MODULE_CACHE_PATH="${TMP_ROOT%/}/snapzy-qr-probe-module-cache"
STDERR_PATH="${TMP_ROOT%/}/snapzy-qr-detection-probe.stderr"

cd "$REPO_ROOT"

swiftc -parse-as-library \
  -module-cache-path "$MODULE_CACHE_PATH" \
  -o "$BINARY_PATH" \
  scripts/swift-tools/qr/qr-detection-performance-probe.swift

: > "$STDERR_PATH"
set +e
"$BINARY_PATH" "$@" 2> "$STDERR_PATH"
STATUS=$?
set -e

grep -v '^sysctlbyname for kern.hv_vmm_present failed with status -1$' "$STDERR_PATH" >&2 || true
exit "$STATUS"
