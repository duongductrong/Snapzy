#!/bin/bash
# update-docs-version-stamps.sh - Align docs HEAD version stamps with a release
# Usage: ./scripts/update-docs-version-stamps.sh <version> <build_number> [docs_dir]
#
# Example:
#   ./scripts/update-docs-version-stamps.sh "1.2.3" "999"

set -euo pipefail

VERSION_RAW="${1:?Usage: update-docs-version-stamps.sh <version> <build_number> [docs_dir]}"
BUILD_NUMBER="${2:?Usage: update-docs-version-stamps.sh <version> <build_number> [docs_dir]}"
DOCS_DIR="${3:-docs}"

VERSION="${VERSION_RAW#v}"

if [ ! -d "$DOCS_DIR" ]; then
  echo "::error::Docs directory not found: $DOCS_DIR"
  exit 1
fi

if ! [[ "$BUILD_NUMBER" =~ ^[0-9]+$ ]]; then
  echo "::error::Build number must be an integer: $BUILD_NUMBER"
  exit 1
fi

DEPLOYMENT_TARGET="13.0"
PROJ_FILE="Snapzy.xcodeproj/project.pbxproj"
if [ -f "$PROJ_FILE" ]; then
  DETECTED=$(grep -m1 'MACOSX_DEPLOYMENT_TARGET' "$PROJ_FILE" | sed 's/.*= //' | sed 's/;.*//' | tr -d ' ' || true)
  if [[ "$DETECTED" =~ ^[0-9]+(\.[0-9]+)*$ ]]; then
    DEPLOYMENT_TARGET="$DETECTED"
  fi
fi

updated=0
shopt -s nullglob
for file in "$DOCS_DIR"/*.md; do
  before=$(cksum <"$file")

  # Simple stamp: at HEAD (`v…`)
  sed -i '' -E \
    "s/at HEAD \(\`v[^\`]+\`\)/at HEAD (\`v${VERSION}\`)/g" \
    "$file"

  # Detailed stamp: Current as of HEAD (`v…`, build N, macOS X.Y+ deployment target)
  sed -i '' -E \
    "s/Current as of HEAD \(\`v[^\`]+\`, build [0-9]+, macOS [0-9]+(\.[0-9]+)*\+ deployment target\)/Current as of HEAD (\`v${VERSION}\`, build ${BUILD_NUMBER}, macOS ${DEPLOYMENT_TARGET}+ deployment target)/g" \
    "$file"

  after=$(cksum <"$file")
  if [ "$before" != "$after" ]; then
    echo "Updated stamps in $file"
    updated=$((updated + 1))
  fi
done

echo "Docs version stamps: v${VERSION}, build ${BUILD_NUMBER}, macOS ${DEPLOYMENT_TARGET}+ (${updated} file(s) changed)"
