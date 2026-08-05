//
//  InlineAreaMagnifierHostView.swift
//  Snapzy
//
//  Hosts the shared `AreaSelectionMagnifier` inside the SwiftUI-based inline area annotate
//  flow, so screenshot-and-annotate (⌘⇧7) renders the exact same magnifier/color-picker as
//  plain area screenshot (⌘⇧4) instead of a second reimplementation.
//

import AppKit

/// Pure-display host: never participates in hit-testing, so the selection drag gesture
/// underneath (driven by SwiftUI) is unaffected. Scroll-wheel zoom and the "C" copy shortcut
/// are driven externally via `InlineAreaAnnotateSession`'s own event monitors — mirroring how
/// `AreaSelectionOverlayView` handles them for plain screenshot capture — rather than through
/// this view's own event handlers, since a hit-testable view would block the gesture.
final class InlineAreaMagnifierHostView: NSView {
  let magnifier = AreaSelectionMagnifier()
  var backdropImage: CGImage?

  private var lastPoint: CGPoint?

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    wantsLayer = true
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override func hitTest(_ point: NSPoint) -> NSView? {
    nil
  }

  /// `point` is in this view's local (AppKit, bottom-left origin) coordinate space.
  func update(at point: CGPoint) {
    lastPoint = point
    render()
  }

  func hide() {
    lastPoint = nil
    magnifier.removeLayers()
  }

  @discardableResult
  func applyScroll(delta: CGFloat, hasPreciseScrollingDeltas: Bool) -> Bool {
    guard magnifier.handleScroll(delta: delta, hasPreciseScrollingDeltas: hasPreciseScrollingDeltas) else {
      return false
    }
    render()
    return true
  }

  private func render() {
    guard let layer, let point = lastPoint else { return }
    magnifier.update(
      at: point,
      bounds: bounds,
      backdropImage: backdropImage,
      contentsScale: window?.backingScaleFactor ?? 2.0,
      in: layer
    )
  }
}
