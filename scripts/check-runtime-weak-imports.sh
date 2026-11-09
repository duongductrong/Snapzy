#!/usr/bin/env bash
#
# Fails when a built Snapzy binary imports Swift runtime entry points that do
# not exist on the deployment target (macOS 13) and that optimized builds call
# without a NULL check. On older macOS the weak import resolves to NULL and the
# app jumps to address 0 (see issue #725).
#
# Usage: scripts/check-runtime-weak-imports.sh <path/to/Snapzy.app | Mach-O> [...]
#
# swift_getExtendedFunctionTypeMetadata is emitted for async closure types that
# are `nonisolated(nonsending)` (default under Approachable Concurrency) when
# they are used generically: stored in a Dictionary, an Optional, etc. Fix by
# marking the closure type `@concurrent` or giving it a global actor
# (`@MainActor`).

set -euo pipefail

FORBIDDEN_SYMBOLS=(
  "_swift_getExtendedFunctionTypeMetadata"
)

if [ "$#" -eq 0 ]; then
  echo "usage: $0 <Snapzy.app | binary> [...]" >&2
  exit 2
fi

binaries=()
for target in "$@"; do
  if [ -d "$target" ]; then
    while IFS= read -r -d '' file; do
      if file -b "$file" | grep -q "Mach-O"; then
        binaries+=("$file")
      fi
    done < <(find "$target/Contents/MacOS" "$target/Contents/Helpers" -type f -print0 2>/dev/null)
  else
    binaries+=("$target")
  fi
done

if [ "${#binaries[@]}" -eq 0 ]; then
  echo "::error::No Mach-O binaries found in: $*" >&2
  exit 1
fi

failed=0
for binary in "${binaries[@]}"; do
  imports=$(xcrun dyld_info -imports "$binary")
  for symbol in "${FORBIDDEN_SYMBOLS[@]}"; do
    if grep -qw -- "$symbol" <<<"$imports"; then
      echo "::error::$binary imports $symbol (macOS 15+ runtime only). It crashes on macOS 13/14. Mark the nonsending async closure type @concurrent or @MainActor."
      failed=1
    fi
  done
  echo "checked: $binary"
done

if [ "$failed" -ne 0 ]; then
  exit 1
fi

echo "OK: no forbidden Swift runtime imports"
