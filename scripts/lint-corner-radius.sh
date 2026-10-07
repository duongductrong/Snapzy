#!/bin/bash
# lint-corner-radius.sh - Flag hard-coded corner radii that bypass the `Radius` design scale.
#
# The scale lives in Snapzy/Shared/Styles/RadiusTokens.swift and is documented in
# docs/LIQUID_GLASS.md §4b. A literal radius is how the app drifted into three parallel ramps and
# a 32pt button with a 6pt corner; this check keeps new ones from landing.
#
# Usage:
#   ./scripts/lint-corner-radius.sh            # whole tree
#   ./scripts/lint-corner-radius.sh --staged   # staged Swift files only (pre-commit)
#
# Exit codes: 0 clean, 1 violations found.

set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$DIR/.."
cd "$ROOT_DIR"

STAGED_ONLY=0
[[ "${1:-}" == "--staged" ]] && STAGED_ONLY=1

if [[ $STAGED_ONLY -eq 1 ]]; then
  FILES=$(git diff --cached --name-only --diff-filter=ACM | grep '\.swift$' || true)
else
  FILES=$(find Snapzy -name '*.swift' | sort)
fi

[[ -z "$FILES" ]] && exit 0

# A literal radius in SwiftUI chrome. Data-driven radii (`cornerRadius: state.foo`) are fine —
# those are user content, not chrome.
PATTERN='(cornerRadius: *[0-9]|\.cornerRadius\( *[0-9])'

# Exempt paths.
#
#   RadiusTokens.swift  — defines the scale.
#   LiquidGlassPreview  — DEBUG playground; hand-drawn mockups of other surfaces.
#   Onboarding/Mockups  — miniature fake replicas of app windows, drawn at illustration scale.
#   Services/           — render pipelines that rasterise user content at export resolution.
EXEMPT='Snapzy/Shared/Styles/RadiusTokens.swift|LiquidGlassPreview.swift|Onboarding/Mockups/|/Services/'

# Line-level opt-out for a deliberate one-off, e.g. matching a real macOS window radius:
#   .cornerRadius(10) // radius-lint:allow — matches the live NSWindow corner
ALLOW='radius-lint:allow'

VIOLATIONS=0
REPORT=""

for file in $FILES; do
  [[ -f "$file" ]] || continue
  echo "$file" | grep -qE "$EXEMPT" && continue

  while IFS=: read -r lineno content; do
    [[ -z "$lineno" ]] && continue
    echo "$content" | grep -q "$ALLOW" && continue
    REPORT+="  $file:$lineno:$(echo "$content" | sed 's/^[[:space:]]*/ /')"$'\n'
    VIOLATIONS=$((VIOLATIONS + 1))
  done < <(grep -nE "$PATTERN" "$file" || true)
done

if [[ $VIOLATIONS -eq 0 ]]; then
  echo "corner-radius: clean"
  exit 0
fi

echo "corner-radius: $VIOLATIONS hard-coded radius/radii bypassing the \`Radius\` scale"
echo
echo "$REPORT"
cat <<'EOF'
Use the scale instead (Snapzy/Shared/Styles/RadiusTokens.swift, docs/LIQUID_GLASS.md §4b):

  Interactive control  →  Radius.controlRect(forHeight: <the control's height>)
                          Radius.control(forHeight: <height>)   // bare CGFloat
  Container            →  Radius.rect(Radius.card)   // or .tile / .panel / .window
  Ornament             →  Radius.rect(Radius.ornament)

Radius is derived from control height (~0.36 x h) so a 24pt chip and a 32pt button read as one
family. Do not pick a token by eye — state the height.

Deliberate one-off? Append a trailing `// radius-lint:allow <why>` on the line.
EOF
exit 1
