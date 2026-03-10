#!/bin/bash
# update-changelog.sh - Prepends a versioned changelog entry to CHANGELOG.md
# Usage: ./scripts/update-changelog.sh <version> <changelog_content_file>
#
# Example:
#   ./scripts/update-changelog.sh "1.2.3" "build/changelog.md"

set -euo pipefail

VERSION="${1:?Usage: update-changelog.sh <version> <changelog_content_file>}"
CONTENT_FILE="${2:?Usage: update-changelog.sh <version> <changelog_content_file>}"
CHANGELOG_FILE="${3:-CHANGELOG.md}"

if [ ! -f "$CONTENT_FILE" ]; then
  echo "::error::Changelog content file not found: $CONTENT_FILE"
  exit 1
fi

if [ ! -f "$CHANGELOG_FILE" ]; then
  echo "::error::CHANGELOG.md not found: $CHANGELOG_FILE"
  exit 1
fi

CONTENT=$(cat "$CONTENT_FILE")

if [ -z "$CONTENT" ]; then
  echo "::warning::Changelog content is empty, skipping update"
  exit 0
fi

DATE=$(date +%Y-%m-%d)

# Build the new entry
NEW_ENTRY="## [${VERSION}] - ${DATE}

${CONTENT}"

# Find the line number of the first "## " heading (previous entry) or end of file
# We insert after the file header (first 5 lines: title + blank + description + blank + format line)
HEADER_END=$(awk '/^## \[/ { print NR; exit }' "$CHANGELOG_FILE")

if [ -n "$HEADER_END" ]; then
  # Insert before the first existing version entry
  {
    head -n $((HEADER_END - 1)) "$CHANGELOG_FILE"
    echo ""
    echo "$NEW_ENTRY"
    echo ""
    tail -n +$((HEADER_END)) "$CHANGELOG_FILE"
  } > "${CHANGELOG_FILE}.tmp"
else
  # No existing entries — append after the entire file
  {
    cat "$CHANGELOG_FILE"
    echo ""
    echo "$NEW_ENTRY"
  } > "${CHANGELOG_FILE}.tmp"
fi

mv "${CHANGELOG_FILE}.tmp" "$CHANGELOG_FILE"

echo "Updated $CHANGELOG_FILE with v${VERSION} entry"
