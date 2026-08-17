//
//  AreaSelectionRenderGate.swift
//  Snapzy
//
//  Decides whether a pooled area-selection overlay has to render on a given pointer event.
//  Extracted so the skip decision can be tested without a multi-display rig.
//

import CoreGraphics

/// Whether a pooled overlay has to run a manual-selection render pass this pointer event.
///
/// `renderManualSelectionIfNeeded()` fans every pointer event out to all pooled windows, so the
/// per-event cost scales with display count: a skipped view still pays a coordinate conversion and
/// a `CATransaction` round-trip only to re-hide layers that are already hidden.
///
/// `hasContentOnScreen` reports what the previous pass left drawn, which is what makes skipping
/// safe — the pass that clears a display always runs, and only the ones after it are skipped.
enum AreaSelectionRenderGate {
  static func shouldRender(
    hasContentOnScreen: Bool,
    pointerIsOverView: Bool,
    selectionIntersectsView: Bool
  ) -> Bool {
    hasContentOnScreen || pointerIsOverView || selectionIntersectsView
  }
}
