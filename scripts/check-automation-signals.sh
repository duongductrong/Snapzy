#!/bin/bash
# Universal Automations success signals (roadmap §7, milestone 6 phase 06).
#
#   ./scripts/check-automation-signals.sh
#
# Fails when a capture path grows its own pasteboard-link writer or upload
# call, or when a GlobalShortcutKind is added for a combination (automations
# cover those; no kind added since milestone 1).

set -euo pipefail
cd "$(dirname "$0")/.."

status=0

check() {
  local title="$1"
  local output="$2"
  if [[ -n "$output" ]]; then
    echo "✗ $title"
    echo "$output" | sed 's/^/    /'
    status=1
  else
    echo "✓ $title"
  fi
}

check "One pasteboard text writer (ClipboardHelper.copyText)" \
  "$(grep -rn "NSPasteboard.general.setString" Snapzy | grep -v "ClipboardHelper.swift" || true)"

check "One upload path (CloudShareService)" \
  "$(grep -rn "CloudManager.shared.upload" Snapzy | grep -v "CloudShareService.swift" || true)"

check "No upload or pasteboard code in the Quick Access card view" \
  "$(grep -nE "NSPasteboard|ClipboardHelper|CloudShareService|CloudManager\.shared\.upload" Snapzy/Features/QuickAccess/Components/QuickAccessCardView.swift || true)"

# GlobalShortcutKind cases as of milestone 1 (12c076b2).
allowed="fullscreen area repeatArea areaAnnotate activeWindow scrollingCapture recording pauseResumeRecording togglePenRecording restartRecording deleteRecording delayedCapture delayedFullscreen annotate videoEditor cloudUploads shortcutList ocr translate smartElement objectCutout history pickColor measureScreen"
cases=$(awk '/^enum GlobalShortcutKind/{flag=1; next} flag && /^  var /{flag=0} flag && /^  case /{print $2}' Snapzy/Services/Shortcuts/KeyboardShortcutManager.swift)
unexpected=""
for kind in $cases; do
  [[ " $allowed " == *" $kind "* ]] || unexpected+="$kind "
done
check "No GlobalShortcutKind added for combinations" "$unexpected"

check "Legacy after-capture executor only behind the default automation fallback" \
  "$(grep -rn "executeActions(" Snapzy | grep -v "PostCaptureActionHandler.swift" || true)"

exit $status
