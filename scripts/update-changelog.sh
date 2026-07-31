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

# Print lines without trailing blank lines (used for the file header).
print_without_trailing_blanks() {
  awk '
    { lines[NR] = $0 }
    END {
      end = NR
      while (end > 0 && lines[end] == "") end--
      for (i = 1; i <= end; i++) print lines[i]
    }
  '
}

# Find the first version entry (Keep a Changelog "## [x.y.z]" heading).
HEADER_END=$(awk '/^## \[/ { print NR; exit }' "$CHANGELOG_FILE")

{
  if [ -n "$HEADER_END" ]; then
    # Keep the preamble only; drop any blank lines that accumulated before
    # the first version heading, then insert the new entry.
    head -n $((HEADER_END - 1)) "$CHANGELOG_FILE" | print_without_trailing_blanks
  else
    # No existing entries — keep the whole file, minus trailing blanks.
    print_without_trailing_blanks < "$CHANGELOG_FILE"
  fi

  echo ""
  printf '%s\n' "$NEW_ENTRY"

  if [ -n "$HEADER_END" ]; then
    echo ""
    tail -n +$((HEADER_END)) "$CHANGELOG_FILE"
  fi
} > "${CHANGELOG_FILE}.tmp"

mv "${CHANGELOG_FILE}.tmp" "$CHANGELOG_FILE"

echo "Updated $CHANGELOG_FILE with v${VERSION} entry"
