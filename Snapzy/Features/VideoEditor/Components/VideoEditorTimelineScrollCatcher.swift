//
//  VideoEditorTimelineScrollCatcher.swift
//  Snapzy
//
//  Scroll-wheel interaction for the video editor timeline: plain scroll pans,
//  ⌘+scroll zooms anchored at the cursor. Installed as a non-hit-testable
//  background view; a local NSEvent monitor consumes scroll events whose
//  location lands inside the timeline's bounds.
//

import AppKit
import SwiftUI

/// Background view that owns the timeline's scroll-event monitor. Invisible to
/// hit testing so mouse clicks keep reaching the SwiftUI content above it.
struct TimelineScrollCatcher: NSViewRepresentable {
  let viewport: VideoEditorTimelineViewport

  func makeNSView(context _: Context) -> TimelineScrollEventCatcherView {
    let view = TimelineScrollEventCatcherView()
    view.viewport = viewport
    return view
  }

  func updateNSView(_ nsView: TimelineScrollEventCatcherView, context _: Context) {
    nsView.viewport = viewport
  }

  static func dismantleNSView(_ nsView: TimelineScrollEventCatcherView, coordinator _: ()) {
    nsView.cleanup()
  }
}

@MainActor
final class TimelineScrollEventCatcherView: NSView {
  weak var viewport: VideoEditorTimelineViewport?

  private var monitor: Any?
  /// Whether the in-flight scroll gesture is a zoom; the momentum tail is
  /// swallowed after a zoom so releasing ⌘ mid-glide doesn't start a pan.
  private var isZoomGesture = false

  private static let coarseScrollMultiplier: CGFloat = 18

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    installMonitorIfNeeded()
  }

  @available(*, unavailable)
  required init?(coder _: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  func cleanup() {
    if let monitor {
      NSEvent.removeMonitor(monitor)
      self.monitor = nil
    }
  }

  override func hitTest(_: NSPoint) -> NSView? {
    nil
  }

  // MARK: - Monitor

  private func installMonitorIfNeeded() {
    guard monitor == nil else { return }

    monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
      guard let self, handleScroll(event) else { return event }
      return nil
    }
  }

  // MARK: - Event Handling

  private func handleScroll(_ event: NSEvent) -> Bool {
    guard viewport != nil, event.window === window else { return false }

    let location = convert(event.locationInWindow, from: nil)
    guard bounds.contains(location) else { return false }
    guard event.scrollingDeltaX.isFinite, event.scrollingDeltaY.isFinite else { return false }

    if event.modifierFlags.contains(.command),
       let factor = VideoEditorTimelineViewport.scrollZoomFactor(
         deltaY: event.scrollingDeltaY,
         hasPreciseScrollingDeltas: event.hasPreciseScrollingDeltas
       ) {
      isZoomGesture = true
      zoom(by: factor, cursorX: location.x)
      return true
    }

    if isZoomGesture, !event.momentumPhase.isEmpty {
      return true
    }
    isZoomGesture = false

    pan(event: event)
    return true
  }

  /// Zoom keeping the time under the cursor pinned at the cursor position.
  private func zoom(by factor: CGFloat, cursorX: CGFloat) {
    guard let viewport else { return }

    let anchorViewportX = max(0, min(cursorX, max(0, viewport.viewportWidth)))
    let anchorTime = viewport.time(for: viewport.scrollOffset + anchorViewportX)
    viewport.zoom(by: factor, anchorTime: anchorTime, anchorViewportX: anchorViewportX)
  }

  private func pan(event: NSEvent) {
    guard let viewport else { return }

    let multiplier: CGFloat = event.hasPreciseScrollingDeltas ? 1 : Self.coarseScrollMultiplier
    viewport.pan(
      byContentDeltaX: event.scrollingDeltaX * multiplier,
      contentDeltaY: event.scrollingDeltaY * multiplier
    )
  }
}
