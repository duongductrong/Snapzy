//
//  VideoEditorTimelineViewport.swift
//  Snapzy
//
//  Viewport state for the editor timeline: zoom level (1 = fit) and the
//  horizontal scroll offset across the zoomed content. Pure UI state — not
//  undoable and not persisted.
//

import Combine
import Foundation
import SwiftUI

/// Owns the timeline zoom/scroll window so the container view, zoom controls,
/// and keyboard shortcuts share one source of truth.
///
/// The timeline maps the full duration onto `contentWidth`
/// (`viewportWidth * zoomLevel`); children keep their existing time→x math and
/// simply receive the scaled width.
@MainActor
final class VideoEditorTimelineViewport: ObservableObject {
  /// 1 = whole duration fits the viewport width.
  @Published private(set) var zoomLevel: CGFloat = 1
  /// Content points scrolled past the leading edge (≥ 0).
  @Published var scrollOffset: CGFloat = 0
  /// Visible width of the timeline container; pushed by the view.
  @Published var viewportWidth: CGFloat = 0
  /// Duration of the source video in seconds; pushed by the view.
  @Published var durationSeconds: TimeInterval = 0

  static let minZoom: CGFloat = 1
  static let maxZoom: CGFloat = 20
  /// Multiplicative step per zoom in/out action.
  static let step: CGFloat = 1.5
  /// Never show less than this much time across the viewport.
  static let minVisibleSeconds: TimeInterval = 1
  /// Scroll-wheel zoom sensitivity: exponent per delta unit. Precise deltas
  /// (trackpad) arrive in points; coarse deltas (mouse wheel) in notches.
  static let scrollZoomSensitivityPrecise: CGFloat = 0.004
  static let scrollZoomSensitivityCoarse: CGFloat = 0.12

  /// Explicit and nonisolated: the synthesized main-actor deinit hops through the
  /// back-deployed swift_task_deinitOnExecutor, which aborts on macOS 13-15 (#668).
  nonisolated deinit {}

  /// Effective width of the timeline content inside the scroll container.
  var contentWidth: CGFloat {
    max(0, viewportWidth * zoomLevel)
  }

  /// Seconds visible across the viewport at the current zoom.
  var visibleDuration: TimeInterval {
    pixelsPerSecond > 0 ? viewportWidth / pixelsPerSecond : durationSeconds
  }

  var pixelsPerSecond: CGFloat {
    guard durationSeconds > 0, zoomLevel > 0 else { return 0 }
    return contentWidth / CGFloat(durationSeconds)
  }

  var isFit: Bool {
    zoomLevel <= Self.minZoom + 0.001
  }

  var canZoomIn: Bool {
    zoomLevel < effectiveMaxZoom - 0.001
  }

  var canZoomOut: Bool {
    zoomLevel > Self.minZoom + 0.001
  }

  /// Zoom cap honoring both the absolute max and the min visible duration.
  var effectiveMaxZoom: CGFloat {
    guard durationSeconds > 0, viewportWidth > 0 else { return Self.maxZoom }
    let maxZoomForMinVisible = CGFloat(durationSeconds / Self.minVisibleSeconds)
    guard maxZoomForMinVisible >= Self.minZoom else { return Self.minZoom }
    return min(Self.maxZoom, maxZoomForMinVisible)
  }

  // MARK: - Mapping

  /// Content-space x for a time in seconds.
  func x(for time: TimeInterval) -> CGFloat {
    guard durationSeconds > 0 else { return 0 }
    let progress = max(0, min(time / durationSeconds, 1))
    return CGFloat(progress) * contentWidth
  }

  /// Time in seconds for a content-space x.
  func time(for x: CGFloat) -> TimeInterval {
    guard contentWidth > 0 else { return 0 }
    let progress = max(0, min(x / contentWidth, 1))
    return progress * durationSeconds
  }

  // MARK: - Zoom

  /// Set the zoom level, keeping `anchorTime` at the same viewport position.
  func setZoom(_ level: CGFloat, keepingTimeAtViewportX anchorTime: TimeInterval, anchorViewportX: CGFloat) {
    let clamped = clampedZoom(level)
    guard abs(clamped - zoomLevel) > 0.001 else { return }

    let viewportX = max(0, min(anchorViewportX, max(0, viewportWidth)))
    zoomLevel = clamped
    setScrollOffset(x(for: anchorTime) - viewportX)
  }

  /// Multiplicative zoom keeping `anchorTime` at the same viewport position.
  func zoom(by factor: CGFloat, anchorTime: TimeInterval, anchorViewportX: CGFloat) {
    setZoom(zoomLevel * factor, keepingTimeAtViewportX: anchorTime, anchorViewportX: anchorViewportX)
  }

  /// Zoom in one step, anchored at `anchorTime` (typically the playhead).
  func zoomIn(anchorTime: TimeInterval) {
    zoom(by: Self.step, anchorTime: anchorTime, anchorViewportX: anchorViewportX(for: anchorTime))
  }

  /// Zoom out one step, anchored at `anchorTime` (typically the playhead).
  func zoomOut(anchorTime: TimeInterval) {
    zoom(by: 1 / Self.step, anchorTime: anchorTime, anchorViewportX: anchorViewportX(for: anchorTime))
  }

  /// Multiplicative zoom factor for one scroll-wheel zoom event.
  ///
  /// Positive `deltaY` zooms in, matching the app-wide scroll-zoom convention
  /// (area magnifier, Quick Access pin window). Precise deltas (trackpad) are
  /// points, coarse deltas (mouse wheel) are notches, so each gets its own
  /// sensitivity.
  static func scrollZoomFactor(
    deltaY: CGFloat,
    hasPreciseScrollingDeltas: Bool
  ) -> CGFloat? {
    guard deltaY.isFinite, deltaY != 0 else { return nil }
    let sensitivity = hasPreciseScrollingDeltas
      ? scrollZoomSensitivityPrecise
      : scrollZoomSensitivityCoarse
    return CGFloat(exp(Double(deltaY * sensitivity)))
  }

  /// Pan the window by a content-movement delta from a scroll gesture.
  ///
  /// Scroll deltas already encode the user's scrolling preference: positive
  /// `contentDeltaX` means the content moved right (scroll back), positive
  /// `contentDeltaY` means the content moved down, which reads as moving
  /// forward along the timeline (wheel down reveals later content).
  func pan(byContentDeltaX deltaX: CGFloat, contentDeltaY deltaY: CGFloat) {
    guard deltaX.isFinite, deltaY.isFinite else { return }
    setScrollOffset(scrollOffset + deltaY - deltaX)
  }

  private func anchorViewportX(for time: TimeInterval) -> CGFloat {
    let x = x(for: time) - scrollOffset
    return max(0, min(x, max(0, viewportWidth)))
  }

  /// Reset to fit; clears the scroll offset.
  func fit() {
    if zoomLevel != Self.minZoom { zoomLevel = Self.minZoom }
    setScrollOffset(0)
  }

  /// Clamp the zoom so at least `minVisibleSeconds` stays visible.
  private func clampedZoom(_ level: CGFloat) -> CGFloat {
    max(Self.minZoom, min(level, effectiveMaxZoom))
  }

  /// Clamp the scroll offset to the scrollable range.
  func clampScroll() {
    setScrollOffset(scrollOffset)
  }

  /// Clamp once and publish only a real change. Every write re-renders the timeline
  /// container, and scroll events arrive at 60–120 Hz (pinned at an edge or at fit zoom,
  /// most of them change nothing).
  func setScrollOffset(_ offset: CGFloat) {
    let maxOffset = max(0, contentWidth - viewportWidth)
    let clamped = max(0, min(offset, maxOffset))
    if scrollOffset != clamped { scrollOffset = clamped }
  }

  /// Size and duration pushed by the view; publish only real changes.
  func setGeometry(viewportWidth width: CGFloat, durationSeconds duration: TimeInterval) {
    if viewportWidth != width { viewportWidth = width }
    if durationSeconds != duration { durationSeconds = duration }
    clampScroll()
  }

  // MARK: - Render range

  /// Content range the tracks draw: the visible window plus one viewport of overscan each
  /// side, snapped outward to whole viewport widths. Snapping keeps the value constant
  /// while scrolling or auto-following inside a band, so the equatable tracks (ruler, clip
  /// strip, zoom, speed) skip their bodies; scrolling itself is just the container offset.
  /// Always contains `[scrollOffset - viewportWidth, scrollOffset + 2 * viewportWidth]`.
  var renderRange: ClosedRange<CGFloat> {
    let width = contentWidth
    guard viewportWidth > 0 else {
      let leading = min(width, max(0, scrollOffset))
      return leading ... leading
    }
    let band = viewportWidth
    let rawLeading = scrollOffset - viewportWidth
    let rawTrailing = scrollOffset + 2 * viewportWidth
    let leading = min(width, max(0, (rawLeading / band).rounded(.down) * band))
    let trailing = max(leading, min(width, (rawTrailing / band).rounded(.up) * band))
    return leading ... trailing
  }

  // MARK: - Playhead follow

  /// Target scroll offset that keeps the playhead visible while playing.
  /// Returns `nil` when no scroll is needed.
  func targetScrollToKeepVisible(contentX: CGFloat, margin: CGFloat) -> CGFloat? {
    let maxOffset = max(0, contentWidth - viewportWidth)
    guard maxOffset > 0 else { return nil }

    if contentX < scrollOffset + margin {
      return max(0, contentX - margin)
    }
    if contentX > scrollOffset + viewportWidth - margin {
      return min(maxOffset, contentX - viewportWidth + margin)
    }
    return nil
  }
}
