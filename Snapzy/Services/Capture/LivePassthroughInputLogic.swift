//
//  LivePassthroughInputLogic.swift
//  Snapzy
//
//  Pure decision logic for the live-capture passthrough input path, extracted
//  from AreaSelectionController so it can be unit-tested without a session.
//  See plans/260723-2112-live-capture-passthrough.
//

import CoreGraphics
import Foundation

enum LivePassthroughInputLogic {
  /// CGEvent locations arrive in global Quartz coordinates (top-left origin); the selection
  /// machinery works in AppKit global coordinates (bottom-left) — flip against the main
  /// display's height once at the boundary.
  static func appKitScreenPoint(
    fromQuartzGlobalPoint point: CGPoint,
    mainScreenHeight: CGFloat
  ) -> CGPoint {
    CGPoint(x: point.x, y: mainScreenHeight - point.y)
  }

  /// Coalesced hover gate: process at most the latest point per run-loop pass (handled by
  /// the caller's scheduling) and skip sub-pixel movement — but always process when the
  /// pointer crossed onto a different display, however small the move, so the crosshair
  /// never lingers on the wrong display.
  static func shouldProcessHover(
    newPoint: CGPoint,
    lastProcessedPoint: CGPoint?,
    containingDisplayChanged: Bool
  ) -> Bool {
    if containingDisplayChanged { return true }
    guard let lastProcessedPoint else { return true }
    return abs(newPoint.x - lastProcessedPoint.x) >= 1 || abs(newPoint.y - lastProcessedPoint.y) >= 1
  }

  /// Dim visibility in passthrough sessions, mirroring the legacy window-event appearance:
  /// window-selection mode always shows the dim (the hovered window gets a cutout via the
  /// existing mask); manual region shows it from session start when the selection-area-overlay
  /// preference is on (`showsDimFromStart`), otherwise the first drag reveals it. When the
  /// preference is off the dim layer is colorless, so revealing it is a visual no-op — the gate
  /// only keeps the semantics honest.
  static func showsDim(
    interactionMode: AreaSelectionInteractionMode,
    hasRevealedDim: Bool,
    isDragging: Bool,
    showsDimFromStart: Bool
  ) -> Bool {
    switch interactionMode {
    case .applicationWindow, .fullDisplay:
      // `.fullDisplay` is recording-only and recording never runs the tap; grouped here so
      // the switch stays exhaustive.
      true
    case .manualRegion:
      showsDimFromStart || hasRevealedDim || isDragging
    }
  }
}

/// Tracks `CGDisplayHideCursor`/`CGDisplayShowCursor` balance per display. Hide and show
/// are per-display counters at the WindowServer level — hiding a display twice would
/// require showing it twice — so the set guards against double-hides (session start plus
/// mid-session display attach) and guarantees every hidden display gets exactly one show
/// on teardown. Effect closures are injectable for tests.
///
/// `CGDisplayHideCursor` only takes effect for the FOREGROUND application, and Snapzy
/// must never activate mid-capture (activating would itself dismiss the hover UI this
/// feature preserves). That foreground restriction is lifted by `BackgroundCursorControl`,
/// which grants this background agent cursor control via the private `SetsCursorInBackground`
/// connection property — so the hides here actually apply and only the drawn crosshair
/// proxy shows. The show-balance bookkeeping still matters: it guarantees the cursor is
/// never left hidden where a hide took effect. (Residual edge: while the pointer is over
/// the Dock the WindowServer keeps the Dock in cursor control, so the arrow can briefly
/// reappear there; if `BackgroundCursorControl` is ever unavailable the hide silently
/// no-ops and the old arrow-visible behavior returns.)
struct LivePassthroughCursorHider {
  private(set) var hiddenDisplayIDs: Set<CGDirectDisplayID> = []

  var isHidden: Bool {
    !hiddenDisplayIDs.isEmpty
  }

  mutating func hide(
    displayIDs: Set<CGDirectDisplayID>,
    hider: (CGDirectDisplayID) -> Void = { CGDisplayHideCursor($0) }
  ) {
    for displayID in displayIDs where !hiddenDisplayIDs.contains(displayID) {
      hider(displayID)
      hiddenDisplayIDs.insert(displayID)
    }
  }

  mutating func showAll(shower: (CGDirectDisplayID) -> Void = { CGDisplayShowCursor($0) }) {
    for displayID in hiddenDisplayIDs {
      shower(displayID)
    }
    hiddenDisplayIDs.removeAll()
  }
}

/// Restores the real cursor position when a live-passthrough session ends. While the
/// consuming tap ran, the WindowServer's tracked cursor position went stale (consumed
/// moves never reached it), so the cursor is warped to the last tap-observed location
/// before it is revealed.
///
/// Warp pitfall: after any warp, macOS suppresses local hardware mouse events for the
/// event source's suppression interval — 0.25 seconds by default (see
/// `CGEventSource.localEventsSuppressionInterval`). Physical movement inside that
/// window never moves the cursor (a visible freeze/stutter right after capture mode
/// ends), and the backed-up movement then lands as a jump to an unexpected position.
/// Zeroing the interval on the combined session state before the warp keeps hardware
/// movement flowing continuously from the restored position.
/// `CGAssociateMouseAndMouseCursorPosition(1)` alone does NOT cancel that suppression —
/// it is kept only as a harmless safety (no-op while already associated). Effect
/// closures are injectable for tests, mirroring `LivePassthroughCursorHider`.
struct LivePassthroughCursorRestorer {
  private let setSuppressionInterval: (CFTimeInterval) -> Void
  private let warp: (CGPoint) -> Void
  private let reassociate: () -> Void

  init(
    setSuppressionInterval: @escaping (CFTimeInterval) -> Void = LivePassthroughCursorRestorer
      .liveSetSuppressionInterval,
    warp: @escaping (CGPoint) -> Void = { CGWarpMouseCursorPosition($0) },
    // boolean_t: 1 == connected/associated
    reassociate: @escaping () -> Void = { CGAssociateMouseAndMouseCursorPosition(1) }
  ) {
    self.setSuppressionInterval = setSuppressionInterval
    self.warp = warp
    self.reassociate = reassociate
  }

  /// Zero the post-warp suppression window first, then move the cursor to `location`
  /// and re-associate the mouse with it. The order matters: the suppression window
  /// opens at warp time, so the interval must already be zero when the warp lands.
  func restore(to location: CGPoint) {
    setSuppressionInterval(0)
    warp(location)
    reassociate()
  }

  /// System seam: zero the suppression interval on the shared combined-session event
  /// source state — the state the WindowServer consults when suppressing local events
  /// after a warp. Fails soft (no-op) if the source cannot be created.
  private nonisolated static func liveSetSuppressionInterval(_ seconds: CFTimeInterval) {
    guard let source = CGEventSource(stateID: .combinedSessionState) else { return }
    source.localEventsSuppressionInterval = seconds
  }
}
