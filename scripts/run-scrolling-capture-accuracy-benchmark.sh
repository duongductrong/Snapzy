#!/bin/bash
# Compile and run the deterministic Scroll Capture accuracy benchmark.
#
# Usage:
#   ./scripts/run-scrolling-capture-accuracy-benchmark.sh
#   ./scripts/run-scrolling-capture-accuracy-benchmark.sh --strict

set -euo pipefail

if [ "$(uname -s)" != "Darwin" ]; then
  echo "::error::This benchmark requires macOS." >&2
  exit 1
fi

if ! command -v swiftc >/dev/null 2>&1; then
  echo "::error::swiftc not found. Install Xcode Command Line Tools first." >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
TMP_ROOT="${TMPDIR:-/tmp}"
BINARY_PATH="${TMP_ROOT%/}/snapzy-scroll-capture-accuracy-benchmark"
MODULE_CACHE_PATH="${TMP_ROOT%/}/snapzy-scroll-benchmark-module-cache"
STDERR_PATH="${TMP_ROOT%/}/snapzy-scroll-capture-accuracy-benchmark.stderr"

cd "$REPO_ROOT"

swiftc -parse-as-library \
  -module-cache-path "$MODULE_CACHE_PATH" \
  -o "$BINARY_PATH" \
  scripts/swift-tools/scrolling-capture-accuracy/scrolling-capture-accuracy-benchmark.swift \
  scripts/swift-tools/scrolling-capture-accuracy/scrolling-capture-accuracy-metrics.swift \
  scripts/swift-tools/scrolling-capture-accuracy/scrolling-capture-accuracy-support.swift \
  Snapzy/Services/Capture/ScrollingCapture/ScrollingCaptureStitcher.swift

: > "$STDERR_PATH"
set +e
"$BINARY_PATH" "$@" 2> "$STDERR_PATH"
STATUS=$?
set -e

grep -v '^sysctlbyname for kern.hv_vmm_present failed with status -1$' "$STDERR_PATH" >&2 || true
exit "$STATUS"
