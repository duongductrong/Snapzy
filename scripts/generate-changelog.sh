#!/bin/bash
# generate-changelog.sh - Generates changelog from conventional commits between tags
# Usage: ./scripts/generate-changelog.sh [previous_tag]
# Env: EXCLUDE_PRERELEASE=1 — when no tag argument is given, skip v*-beta* tags
#      so the range starts at the last stable tag.
#
# Breaking changes (`BREAKING CHANGE:` subject/footer, `type!:`) get their own
# section at the top.
#
# Release-automation commits (version bumps, appcast/cask sync, release PR
# merges) are always filtered out of the Chore section — they are pipeline
# noise, not product changes.

set -euo pipefail

PREVIOUS_TAG="${1:-}"

# Find the previous tag if not provided
if [ -z "$PREVIOUS_TAG" ]; then
  if [ "${EXCLUDE_PRERELEASE:-0}" = "1" ]; then
    PREVIOUS_TAG=$(git describe --tags --abbrev=0 --exclude 'v*-beta*' 2>/dev/null || echo "")
  else
    PREVIOUS_TAG=$(git describe --tags --abbrev=0 2>/dev/null || echo "")
  fi
fi

# Build git log range
if [ -n "$PREVIOUS_TAG" ]; then
  RANGE="${PREVIOUS_TAG}..HEAD"
else
  RANGE="HEAD"
fi

# Collect commits by category, classifying on the subject line only (git's
# --grep also matches body lines, which misfiles squash merges whose body lists
# the original commits).
# Breaking changes: `BREAKING CHANGE: ...` subjects, `type!:` / `type(scope)!:`
# subjects, or a `BREAKING CHANGE:` footer in the body.
BREAKING=""
FEATURES=""
FIXES=""
CHORES=""

append() {
  # append <var> <line>
  if [ -n "${!1}" ]; then
    printf -v "$1" '%s\n%s' "${!1}" "$2"
  else
    printf -v "$1" '%s' "$2"
  fi
}

TYPE_RE='^([a-z]+)(\([^)]*\))?(!)?:[[:space:]]*(.*)$'
BREAKING_RE='^BREAKING[ -]CHANGE:[[:space:]]*(.*)$'

while IFS=$'\x1f' read -r -d $'\x1e' HASH SUBJECT BODY; do
  HASH="${HASH#$'\n'}"
  [ -z "$HASH" ] && continue

  if [[ "$SUBJECT" =~ $BREAKING_RE ]]; then
    append BREAKING "${BASH_REMATCH[1]} (${HASH})"
    continue
  fi

  if [[ "$SUBJECT" =~ $TYPE_RE ]]; then
    TYPE="${BASH_REMATCH[1]}"
    BANG="${BASH_REMATCH[3]}"
    DESC="${BASH_REMATCH[4]}"
    if [ -n "$BANG" ] || printf '%s\n' "$BODY" | grep -qE '^BREAKING[ -]CHANGE:'; then
      append BREAKING "${DESC} (${HASH})"
      continue
    fi
    case "$TYPE" in
      feat) append FEATURES "${DESC} (${HASH})" ;;
      fix) append FIXES "${DESC} (${HASH})" ;;
      chore | refactor | perf | style | ci | docs | build)
        if ! printf '%s\n' "$SUBJECT" | grep -qE '^chore: (bump version to v|release v|update appcast)'; then
          append CHORES "${SUBJECT} (${HASH})"
        fi
        ;;
    esac
  fi
done < <(git log "$RANGE" --pretty=format:'%h%x1f%s%x1f%b%x1e' 2>/dev/null || true)

# Collect contributors
# Prefer GitHub usernames when running in CI with gh CLI available
CONTRIBUTORS=""
if [ -n "${GITHUB_REPOSITORY:-}" ] && { [ -n "${GITHUB_TOKEN:-}" ] || [ -n "${GH_TOKEN:-}" ]; }; then
  export GH_TOKEN="${GH_TOKEN:-$GITHUB_TOKEN}"
  if command -v gh >/dev/null 2>&1; then
    if [ -n "$PREVIOUS_TAG" ] && git rev-parse "$PREVIOUS_TAG" >/dev/null 2>&1; then
      CONTRIBUTORS=$(gh api "repos/${GITHUB_REPOSITORY}/compare/${PREVIOUS_TAG}...HEAD" --jq '.commits[]? | select(.author != null) | "- @" + .author.login' 2>/dev/null | sort -u | grep -v '^- @$' || true)
    else
      CONTRIBUTORS=$(gh api "repos/${GITHUB_REPOSITORY}/commits?sha=HEAD&per_page=100" --jq '.[]? | select(.author != null) | "- @" + .author.login' 2>/dev/null | sort -u | grep -v '^- @$' || true)
    fi
  fi
fi

# Fallback to author names from git log
if [ -z "${CONTRIBUTORS:-}" ]; then
  CONTRIBUTORS=$(git log "$RANGE" --pretty=format:"%an" 2>/dev/null | sort -u | sed 's/^/- @/' || true)
fi

# Build changelog
CHANGELOG=""

if [ -n "$BREAKING" ]; then
  CHANGELOG+="### Breaking Changes"$'\n'
  while IFS= read -r line; do
    CHANGELOG+="- ${line}"$'\n'
  done <<< "$BREAKING"
  CHANGELOG+=$'\n'
fi

if [ -n "$FEATURES" ]; then
  CHANGELOG+="### Features"$'\n'
  while IFS= read -r line; do
    CHANGELOG+="- ${line}"$'\n'
  done <<< "$FEATURES"
  CHANGELOG+=$'\n'
fi

if [ -n "$FIXES" ]; then
  CHANGELOG+="### Bug Fixes"$'\n'
  while IFS= read -r line; do
    CHANGELOG+="- ${line}"$'\n'
  done <<< "$FIXES"
  CHANGELOG+=$'\n'
fi

if [ -n "$CHORES" ]; then
  CHANGELOG+="### Chore"$'\n'
  while IFS= read -r line; do
    CHANGELOG+="- ${line}"$'\n'
  done <<< "$CHORES"
  CHANGELOG+=$'\n'
fi

if [ -n "$CONTRIBUTORS" ]; then
  CHANGELOG+="### Contributors"$'\n'
  CHANGELOG+="${CONTRIBUTORS}"$'\n'
fi

# Fallback if no conventional commits found
if [ -z "$CHANGELOG" ]; then
  CHANGELOG="### Changes"$'\n'
  git log "$RANGE" --pretty=format:"- %s (%h)" 2>/dev/null | while IFS= read -r line; do
    CHANGELOG+="${line}"$'\n'
  done
fi

echo "$CHANGELOG"
