#!/bin/bash
# update-appcast.sh - Prepends a new <item> to appcast.xml for Sparkle updates
# Usage: ./scripts/update-appcast.sh <version> <build_number> <dmg_path> [appcast_file] [ed_signature] [release_notes_html]
#
# Example:
#   ./scripts/update-appcast.sh "1.2.3" "42" "build/Snapzy-v1.2.3.dmg" "appcast.xml" "abc123..." "<h3>Features</h3><ul><li>New feature</li></ul>"
#
# The release_notes_html argument should contain the inner HTML for the release notes
# (everything inside the <body> tag). A default style block is automatically prepended.

set -euo pipefail

VERSION="${1:?Usage: update-appcast.sh <version> <build_number> <dmg_path> [appcast_file] [ed_signature] [release_notes_html]}"
BUILD_NUMBER="${2:?Usage: update-appcast.sh <version> <build_number> <dmg_path> [appcast_file] [ed_signature] [release_notes_html]}"
DMG_PATH="${3:?Usage: update-appcast.sh <version> <build_number> <dmg_path> [appcast_file] [ed_signature] [release_notes_html]}"
APPCAST_FILE="${4:-appcast.xml}"
ED_SIGNATURE="${5:-}"
RELEASE_NOTES_HTML="${6:-}"

if [ ! -f "$DMG_PATH" ]; then
  echo "::error::DMG file not found: $DMG_PATH"
  exit 1
fi

if [ ! -f "$APPCAST_FILE" ]; then
  echo "::error::Appcast file not found: $APPCAST_FILE"
  exit 1
fi

# Get file size in bytes
if [[ "$OSTYPE" == "darwin"* ]]; then
  FILE_SIZE=$(stat -f%z "$DMG_PATH")
else
  FILE_SIZE=$(stat -c%s "$DMG_PATH")
fi

# Generate RFC 2822 date
PUB_DATE=$(date -u '+%a, %d %b %Y %H:%M:%S +0000')

# Download URL
DOWNLOAD_URL="https://github.com/duongductrong/Snapzy/releases/download/v${VERSION}/Snapzy-v${VERSION}.dmg"

# Default release notes if none provided
if [ -z "$RELEASE_NOTES_HTML" ]; then
  RELEASE_NOTES_HTML="<h3>🔧 Maintenance</h3><ul><li>Bug fixes and improvements</li></ul>"
fi

# Common style block for release notes
STYLE_BLOCK='<style>body { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Helvetica, Arial, sans-serif; font-size: 13px; line-height: 1.5; color: #1d1d1f; padding: 8px 16px; } h3 { font-size: 14px; margin: 12px 0 6px; color: #1d1d1f; } ul { padding-left: 20px; margin: 4px 0; } li { margin: 3px 0; }</style>'

# Build the new <item> block into a temp file
ITEM_FILE="${APPCAST_FILE}.item.tmp"
cat > "$ITEM_FILE" << EOF
    <item>
      <title>Version ${VERSION}</title>
      <sparkle:version>${BUILD_NUMBER}</sparkle:version>
      <sparkle:shortVersionString>${VERSION}</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>
      <pubDate>${PUB_DATE}</pubDate>
      <description><![CDATA[
        ${STYLE_BLOCK}
        ${RELEASE_NOTES_HTML}
      ]]></description>
      <enclosure
        url="${DOWNLOAD_URL}"
        sparkle:edSignature="${ED_SIGNATURE}"
        length="${FILE_SIZE}"
        type="application/octet-stream"/>
    </item>
EOF

# Insert new item after the <language> line (before existing items)
# Find the line number of <language> and insert after it
LANG_LINE=$(grep -n '<language>' "$APPCAST_FILE" | head -1 | cut -d: -f1)

if [ -z "$LANG_LINE" ]; then
  echo "::error::Could not find <language> tag in $APPCAST_FILE"
  rm -f "$ITEM_FILE"
  exit 1
fi

{
  head -n "$LANG_LINE" "$APPCAST_FILE"
  cat "$ITEM_FILE"
  tail -n +"$((LANG_LINE + 1))" "$APPCAST_FILE"
} > "${APPCAST_FILE}.tmp" && mv "${APPCAST_FILE}.tmp" "$APPCAST_FILE"

rm -f "$ITEM_FILE"

echo "Updated $APPCAST_FILE with v${VERSION} (build ${BUILD_NUMBER}, size ${FILE_SIZE} bytes)"
