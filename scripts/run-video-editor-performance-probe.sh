#!/bin/bash
# Measure actual editor camera math, or capture a native gesture trace.
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage:
  ./scripts/run-video-editor-performance-probe.sh [--quick]
  ./scripts/run-video-editor-performance-probe.sh --attach PID [--duration SECONDS]
    [--template 'Time Profiler'|'SwiftUI'|'Animation Hitches'] [--output PATH.trace]

The CPU probe compiles current repository algorithms with optimization. It reports
p50/p95 for 60/600/1800-second recordings with 1/20/100 clips and checks that cached
and uncached camera outputs are identical. --quick reduces repetitions, not cases.
Timing is diagnostic: correctness mismatches fail; noisy timings do not.

Native capture attaches to an already running app for 1..60 seconds (default 30).
Time Profiler is the default; alternate templates must be installed in Xcode.
Prepare the Video Editor, then repeat click/select, zoom settings, move, resize,
scrub, and timeline zoom/scroll gestures while recording. Speed preview remains
parked until release; zoom preview stays live. This script does not operate the UI.
Editor signpost intervals require a Debug build and the perf.signposts user default
enabled in that build's bundle domain before relaunching. For the standard Debug
bundle: defaults write com.trongduong.snapzy.debug perf.signposts -bool true
The gate is read once at launch. Other builds still support native CPU/SwiftUI/hitch
profiling without the editor signpost intervals.
USAGE
}

fail() {
  printf 'Error: %s\n' "$1" >&2
  exit 2
}

QUICK=0
ATTACH_PID=""
ATTACH_REQUESTED=0
DURATION=30
TEMPLATE="Time Profiler"
OUTPUT=""
NATIVE_OPTION_SET=0
while [ "$#" -gt 0 ]; do
  case "$1" in
    --quick) QUICK=1; shift ;;
    --attach)
      [ "$#" -ge 2 ] || fail '--attach requires a process ID.'
      ATTACH_PID="$2"; ATTACH_REQUESTED=1; shift 2 ;;
    --duration)
      [ "$#" -ge 2 ] || fail '--duration requires seconds.'
      DURATION="$2"; NATIVE_OPTION_SET=1; shift 2 ;;
    --template)
      [ "$#" -ge 2 ] || fail '--template requires a template name.'
      TEMPLATE="$2"; NATIVE_OPTION_SET=1; shift 2 ;;
    --output)
      [ "$#" -ge 2 ] || fail '--output requires a .trace path.'
      OUTPUT="$2"; NATIVE_OPTION_SET=1; shift 2 ;;
    --help|-h) usage; exit 0 ;;
    *) fail "Unknown argument: $1" ;;
  esac
done

[ "$(uname -s)" = Darwin ] || fail 'This probe requires macOS.'
command -v xcrun >/dev/null 2>&1 || fail 'Install Xcode Command Line Tools first.'

if [ "$ATTACH_REQUESTED" -eq 1 ]; then
  [ "$QUICK" -eq 0 ] || fail '--quick applies only to the CPU probe.'
  [[ "$ATTACH_PID" =~ ^[1-9][0-9]*$ ]] || fail '--attach requires a positive process ID.'
  [[ "$DURATION" =~ ^([1-9]|[1-5][0-9]|60)$ ]] || fail '--duration must be an integer from 1 to 60.'
  case "$TEMPLATE" in
    'Time Profiler'|'SwiftUI'|'Animation Hitches') ;;
    *) fail "Unsupported template: $TEMPLATE" ;;
  esac
  kill -0 "$ATTACH_PID" 2>/dev/null || fail "Process $ATTACH_PID is unavailable."
  xcrun --find xctrace >/dev/null 2>&1 || fail 'Native capture requires full Xcode and Instruments.'
  AVAILABLE_TEMPLATES="$(xcrun xctrace list templates)"
  if ! printf '%s\n' "$AVAILABLE_TEMPLATES" | awk -v wanted="$TEMPLATE" '$0 == wanted { found = 1 } END { exit !found }'; then
    fail "Template '$TEMPLATE' is unavailable. Run xcrun xctrace list templates."
  fi
  if [ -z "$OUTPUT" ]; then
    OUTPUT="${TMPDIR:-/tmp}/snapzy-video-editor-$(date +%Y%m%d-%H%M%S)-$$.trace"
  fi
  [[ "$OUTPUT" = *.trace ]] || fail '--output must end with .trace.'
  [ ! -e "$OUTPUT" ] || fail "Output already exists: $OUTPUT"
  [ -d "$(dirname "$OUTPUT")" ] || fail 'The trace output directory must already exist.'

  printf 'Capture: PID %s, template %s, %ss, output %s\n' "$ATTACH_PID" "$TEMPLATE" "$DURATION" "$OUTPUT"
  printf 'Repeat the prepared Video Editor gestures after Instruments reports recording started.\n'
  xcrun xctrace record --template "$TEMPLATE" --attach "$ATTACH_PID" \
    --time-limit "${DURATION}s" --output "$OUTPUT"
  printf 'Trace saved: %s\nInspect main-thread stacks and editor signposts alongside the gesture timestamps.\n' "$OUTPUT"
  exit 0
fi

[ "$NATIVE_OPTION_SET" -eq 0 ] || fail '--duration, --template, and --output require --attach.'
command -v python3 >/dev/null 2>&1 || fail 'python3 is required to assemble current repository sources.'
xcrun --find swiftc >/dev/null 2>&1 || fail 'The Swift compiler is unavailable.'
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
BUILD_DIR="$(mktemp -d "${TMPDIR:-/tmp}/snapzy-video-editor-probe.XXXXXX")"
trap 'rm -rf "$BUILD_DIR"' EXIT

printf 'CPU-only probe; timings exclude SwiftUI rendering, AVPlayer, input delivery, and file I/O.\n'
printf 'Hardware: %s; memory bytes: %s\n' "$(sysctl -n machdep.cpu.brand_string)" "$(sysctl -n hw.memsize)"
xcrun swiftc --version
python3 "$SCRIPT_DIR/swift-tools/video-editor-performance/assemble-probe.py" "$REPO_ROOT" | \
  xcrun swiftc -O -whole-module-optimization -parse-as-library \
    -default-isolation MainActor -o "$BUILD_DIR/probe" -

if [ "$QUICK" -eq 1 ]; then
  "$BUILD_DIR/probe" --quick
else
  "$BUILD_DIR/probe"
fi
