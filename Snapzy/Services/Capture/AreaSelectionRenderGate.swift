//
//  AreaSelectionRenderGate.swift
//  Snapzy
//

import CoreGraphics

/// Whether a pooled overlay has to run a manual-selection render pass this pointer event.
///
/// `hasContentOnScreen` reports what the previous pass left drawn, so the pass that clears a
/// display always runs and only the ones after it are skipped.
enum AreaSelectionRenderGate {
  static func shouldRender(
    hasContentOnScreen: Bool,
    pointerIsOverView: Bool,
    selectionIntersectsView: Bool
  ) -> Bool {
    hasContentOnScreen || pointerIsOverView || selectionIntersectsView
  }
}
