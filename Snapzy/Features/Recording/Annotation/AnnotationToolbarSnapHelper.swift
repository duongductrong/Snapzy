//
//  AnnotationToolbarSnapHelper.swift
//  Snapzy
//
//  Snap calculation and ghost placeholder window for the annotation toolbar.
//  Shows a translucent preview at the snap destination while dragging.
//

import AppKit

// MARK: - Snap Result

struct AnnotationToolbarSnapResult {
  let origin: CGPoint
  let direction: AnnotationToolbarDirection
}

// MARK: - Snap Helper

@MainActor
final class AnnotationToolbarSnapHelper {

  static let edgeThreshold: CGFloat = 0.30
  static let margin: CGFloat = 20

  private var placeholderWindow: NSWindow?

  /// Compute snap destination for a toolbar frame
  func computeSnap(
    for windowFrame: CGRect,
    currentDirection: AnnotationToolbarDirection,
    sizeProvider: (_ direction: AnnotationToolbarDirection) -> CGSize
  ) -> AnnotationToolbarSnapResult {
    guard let screen = NSScreen.main else {
      return AnnotationToolbarSnapResult(origin: windowFrame.origin, direction: currentDirection)
    }
    let sf = screen.visibleFrame
    let center = CGPoint(x: windowFrame.midX, y: windowFrame.midY)

    let relX = (center.x - sf.minX) / sf.width
    let relY = (center.y - sf.minY) / sf.height

    let snapDir: AnnotationToolbarDirection
    if relX < Self.edgeThreshold || relX > (1 - Self.edgeThreshold) {
      snapDir = .vertical
    } else {
      snapDir = .horizontal
    }

    let size = sizeProvider(snapDir)
    let margin = Self.margin
    var snapX: CGFloat
    var snapY: CGFloat

    if relX < 0.5 {
      snapX = sf.minX + margin
    } else {
      snapX = sf.maxX - size.width - margin
    }

    if relY < 0.35 {
      snapY = sf.minY + margin
    } else if relY > 0.65 {
      snapY = sf.maxY - size.height - margin
    } else {
      snapY = center.y - size.height / 2
    }

    snapX = max(sf.minX + margin, min(snapX, sf.maxX - size.width - margin))
    snapY = max(sf.minY + margin, min(snapY, sf.maxY - size.height - margin))

    return AnnotationToolbarSnapResult(origin: CGPoint(x: snapX, y: snapY), direction: snapDir)
  }

  // MARK: - Placeholder Lifecycle

  func showPlaceholder(snap: AnnotationToolbarSnapResult, size: CGSize) {
    let rect = CGRect(origin: snap.origin, size: size)
    let w = makePlaceholderWindow(frame: rect)
    w.orderFront(nil)
    placeholderWindow = w
  }

  func updatePlaceholder(snap: AnnotationToolbarSnapResult, size: CGSize) {
    guard let placeholder = placeholderWindow else { return }
    let newFrame = CGRect(origin: snap.origin, size: size)
    placeholder.setFrame(newFrame, display: true)
  }

  func hidePlaceholder() {
    placeholderWindow?.orderOut(nil)
    placeholderWindow = nil
  }


  // MARK: - Private

  private func makePlaceholderWindow(frame rect: CGRect) -> NSWindow {
    let w = NSWindow(
      contentRect: rect,
      styleMask: [.borderless],
      backing: .buffered,
      defer: false
    )
    w.isOpaque = false
    w.backgroundColor = .clear
    w.hasShadow = false
    w.ignoresMouseEvents = true
    w.level = NSWindow.Level(rawValue: NSWindow.Level.popUpMenu.rawValue - 1)
    w.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

    let ghostView = NSView(frame: CGRect(origin: .zero, size: rect.size))
    ghostView.wantsLayer = true
    ghostView.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.12).cgColor
    ghostView.layer?.cornerRadius = ToolbarConstants.toolbarCornerRadius
    ghostView.layer?.borderWidth = 1.5
    ghostView.layer?.borderColor = NSColor.white.withAlphaComponent(0.25).cgColor
    ghostView.autoresizingMask = [.width, .height]
    w.contentView = ghostView

    return w
  }
}
