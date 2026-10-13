#!/bin/bash
# update-contributors.sh - Updates static AboutContributor model from GitHub contributors API
# Usage: ./scripts/update-contributors.sh [--dry-run]

set -euo pipefail

REPO="${GITHUB_REPOSITORY:-duongductrong/Snapzy}"
TARGET_FILE="Snapzy/Features/Preferences/Models/AboutContributor.swift"
DRY_RUN=0

if [[ "${1:-}" == "--dry-run" ]]; then
  DRY_RUN=1
fi

if ! command -v gh >/dev/null 2>&1; then
  echo "Error: gh (GitHub CLI) is required to run this script." >&2
  exit 1
fi

echo "Fetching contributors for $REPO..."

RAW_CONTRIBUTORS=$(gh api "repos/${REPO}/contributors?per_page=100" --jq '.[] | select(.type != "Bot" and .login != "duongductrong" and .login != "github-actions[bot]") | {login: .login, contributions: .contributions}')

if [[ -z "$RAW_CONTRIBUTORS" ]]; then
  echo "Error: No contributors found or API error." >&2
  exit 1
fi

LOGINS=$(echo "$RAW_CONTRIBUTORS" | jq -r '.login')

get_display_name() {
  local login="$1"
  case "$login" in
    "omarshahine") echo "Omar Shahine" ;;
    "vxirau") echo "Victor Xirau" ;;
    "YuriNachos") echo "Yuri Chukhlib" ;;
    "motoish") echo "Yuan Zhang" ;;
    "tukuyomil032") echo "tukuyomi032" ;;
    "lcopilot") echo "Aurora" ;;
    "gengjiawen") echo "Jiawen Geng" ;;
    "williamcachamwri") echo "William Cachamwri" ;;
    "kawarimidoll") echo "カワリミ人形" ;;
    "chkzz") echo "chk" ;;
    "st1020") echo "Stone" ;;
    "RaviMaru20") echo "Ravi Maru" ;;
    "singularitti") echo "Qi Zhang" ;;
    "vnixx") echo "Phoenix" ;;
    "okadriu") echo "Oltian Kadriu" ;;
    "mukhtharcm") echo "Muhammed Mukhthar CM" ;;
    "justsrc") echo "Justin Jacob" ;;
    "j178") echo "Jo" ;;
    "jjoanna2-debug") echo "Jean-Claude Joanna" ;;
    "BenjaminD2023") echo "Benjamin Dai" ;;
    "menmer0859") echo "HaomengKang" ;;
    *)
      local api_name
      api_name=$(gh api "users/$login" --jq '.name // empty' 2>/dev/null || true)
      if [[ -n "$api_name" ]]; then
        echo "$api_name"
      else
        echo "$login"
      fi
      ;;
  esac
}

echo "Resolving contributor display names..."
TMP_FILE=$(mktemp)
cat << 'HEADER_EOF' > "$TMP_FILE"
//
//  AboutContributor.swift
//  Snapzy
//
//  Static metadata for contributors displayed in About preferences.
//

import Foundation

struct AboutContributor: Identifiable, Hashable {
  let id: String
  let name: String
  let username: String

  var profileURL: URL {
    URL(string: "https://github.com/\(username)")!
  }

  init(name: String, username: String) {
    self.id = username
    self.name = name
    self.username = username
  }
}

extension AboutContributor {
  /// Featured contributors displayed in the default collapsed view.
  static let featured: [AboutContributor] = [
    AboutContributor(name: "Omar Shahine", username: "omarshahine"),
    AboutContributor(name: "Victor Xirau", username: "vxirau"),
    AboutContributor(name: "Yuri Chukhlib", username: "YuriNachos"),
    AboutContributor(name: "Yuan Zhang", username: "motoish"),
    AboutContributor(name: "tukuyomi032", username: "tukuyomil032"),
    AboutContributor(name: "Aurora", username: "lcopilot"),
    AboutContributor(name: "Jiawen Geng", username: "gengjiawen"),
    AboutContributor(name: "William Cachamwri", username: "williamcachamwri")
  ]

  /// All-time contributors displayed when expanded.
  static let all: [AboutContributor] = [
HEADER_EOF

TOTAL_COUNT=$(echo "$LOGINS" | wc -w | tr -d ' ')
CURRENT_INDEX=0

for login in $LOGINS; do
  CURRENT_INDEX=$((CURRENT_INDEX + 1))
  display_name=$(get_display_name "$login")
  if [[ "$CURRENT_INDEX" -lt "$TOTAL_COUNT" ]]; then
    echo "    AboutContributor(name: \"${display_name}\", username: \"${login}\")," >> "$TMP_FILE"
  else
    echo "    AboutContributor(name: \"${display_name}\", username: \"${login}\")" >> "$TMP_FILE"
  fi
done

cat << 'FOOTER_EOF' >> "$TMP_FILE"
  ]
}
FOOTER_EOF

if [[ "$DRY_RUN" -eq 1 ]]; then
  echo "--- DRY RUN OUTPUT ---"
  cat "$TMP_FILE"
  rm -f "$TMP_FILE"
else
  mv "$TMP_FILE" "$TARGET_FILE"
  echo "Successfully updated $TARGET_FILE with $TOTAL_COUNT contributors."
fi
