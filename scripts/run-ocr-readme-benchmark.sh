#!/bin/bash
# Compile and run the reproducible OCR README benchmark.
#
# Usage:
#   ./scripts/run-ocr-readme-benchmark.sh

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
BINARY_PATH="${TMP_ROOT%/}/snapzy-ocr-readme-benchmark"
MODULE_CACHE_PATH="${TMP_ROOT%/}/snapzy-ocr-readme-benchmark-module-cache"
STDERR_PATH="${TMP_ROOT%/}/snapzy-ocr-readme-benchmark.stderr"

cd "$REPO_ROOT"

swiftc -module-cache-path "$MODULE_CACHE_PATH" \
  -o "$BINARY_PATH" \
  scripts/swift-tools/ocr/ocr-readme-benchmark.swift \
  Snapzy/Services/Media/OCRService.swift \
  Snapzy/Services/Media/OCR/OCRRequest.swift \
  Snapzy/Services/Media/OCR/OCRResult.swift \
  Snapzy/Services/Media/OCR/VisionOCRProfile.swift \
  Snapzy/Services/Media/OCR/OCRBenchmarkMetrics.swift \
  Snapzy/Services/Media/OCR/OCRBenchmarkHarness.swift

: > "$STDERR_PATH"
set +e
"$BINARY_PATH" "$@" 2> "$STDERR_PATH"
STATUS=$?
set -e

grep -v '^sysctlbyname for kern.hv_vmm_present failed with status -1$' "$STDERR_PATH" >&2 || true
exit "$STATUS"
