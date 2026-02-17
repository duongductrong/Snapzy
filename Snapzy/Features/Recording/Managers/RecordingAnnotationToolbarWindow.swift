//
//  RecordingAnnotationToolbarWindow.swift
//  Snapzy
//
//  Popover-style NSWindow for annotation tools during recording.
//  Anchors to the status bar's annotate button with an arrow indicator.
//  No longer independently draggable — moves with the status bar.
//

import AppKit
import Combine
import SwiftUI

// MARK: - Arrow Direction

enum AnnotationPopoverArrowEdge {
  case top    // Arrow points up (popover is below anchor)
  case bottom // Arrow points down (popover is above anchor)
}

// MARK: - Arrow View (drawn into the window's content view)

private class PopoverArrowView: NSView {
  var arrowEdge: AnnotationPopoverArrowEdge = .top
  var arrowCenterX: CGFloat = 0

  override func draw(_ dirtyRect: NSRect) {
    guard let ctx = NSGraphicsContext.current?.cgContext else { return }

    let arrowWidth: CGFloat = 16
    let arrowHeight: CGFloat = 8
    let cornerRadius: CGFloat = ToolbarConstants.toolbarCornerRadius

    let bodyRect: NSRect
    switch arrowEdge {
    case .top:
      bodyRect = NSRect(x: 0, y: 0, width: bounds.width, height: bounds.height - arrowHeight)
    case .bottom:
      bodyRect = NSRect(x: 0, y: arrowHeight, width: bounds.width, height: bounds.height - arrowHeight)
    }

    let path = CGMutablePath()

    // Body rounded rect
    path.addRoundedRect(in: bodyRect, cornerWidth: cornerRadius, cornerHeight: cornerRadius)

    // Arrow triangle
    let clampedCenter = max(cornerRadius + arrowWidth / 2, min(arrowCenterX, bounds.width - cornerRadius - arrowWidth / 2))
    let arrowLeft = clampedCenter - arrowWidth / 2
    let arrowRight = clampedCenter + arrowWidth / 2

    let arrowPath = CGMutablePath()
    switch arrowEdge {
    case .top:
      // Arrow points upward from top edge of body
      let baseY = bodyRect.maxY
      arrowPath.move(to: CGPoint(x: arrowLeft, y: baseY))
      arrowPath.addLine(to: CGPoint(x: clampedCenter, y: baseY + arrowHeight))
      arrowPath.addLine(to: CGPoint(x: arrowRight, y: baseY))
      arrowPath.closeSubpath()
    case .bottom:
      // Arrow points downward from bottom edge of body
      let baseY = bodyRect.minY
      arrowPath.move(to: CGPoint(x: arrowLeft, y: baseY))
      arrowPath.addLine(to: CGPoint(x: clampedCenter, y: baseY - arrowHeight))
      arrowPath.addLine(to: CGPoint(x: arrowRight, y: baseY))
      arrowPath.closeSubpath()
    }

    // Draw combined shape with subtle fill
    ctx.setFillColor(NSColor.windowBackgroundColor.withAlphaComponent(0.001).cgColor)
    ctx.addPath(path)
    ctx.addPath(arrowPath)
    ctx.fillPath()
  }
}

// MARK: - Popover Toolbar Window

@MainActor
final class RecordingAnnotationToolbarWindow: NSWindow {

  private let annotationState: RecordingAnnotationState
  private var hostingView: NSHostingView<AnyView>?
  private var effectView: NSVisualEffectView?
  private var arrowView: PopoverArrowView?
  private var enabledCancellable: AnyCancellable?

  /// The toolbar window this popover anchors to
  weak var anchorWindow: RecordingToolbarWindow?

  /// Offset of the annotate button's center X relative to the anchor window's left edge
  var anchorButtonCenterXOffset: CGFloat = 0

  private let arrowHeight: CGFloat = 8
  private let popoverGap: CGFloat = 6

  init(annotationState: RecordingAnnotationState) {
    self.annotationState = annotationState

    super.init(
      contentRect: .zero,
      styleMask: [.borderless],
      backing: .buffered,
      defer: false
    )

    configureWindow()
    rebuildContent()
    observeToggle()
  }

  // MARK: - Configuration

  private func configureWindow() {
    isOpaque = false
    backgroundColor = .clear
    level = .popUpMenu
    collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    hasShadow = true
    isReleasedWhenClosed = false
    appearance = ThemeManager.shared.nsAppearance
    isMovableByWindowBackground = false
  }

  private func observeToggle() {
    enabledCancellable = annotationState.$isAnnotationEnabled
      .receive(on: RunLoop.main)
      .sink { [weak self] enabled in
        if enabled {
          self?.showPopover()
        } else {
          self?.detachFromAnchor()
          self?.orderOut(nil)
        }
      }
  }

  // MARK: - Content

  private func rebuildContent() {
    // Always horizontal for popover style
    let result = AnnotationToolbarContentBuilder.build(
      state: annotationState,
      direction: .horizontal
    )

    // Create a container view that holds the effect view + arrow
    let arrowEdge = computeArrowEdge()
    let bodySize = result.fittingSize
    let totalHeight = bodySize.height + arrowHeight

    let container = NSView(frame: CGRect(origin: .zero, size: CGSize(width: bodySize.width, height: totalHeight)))
    container.wantsLayer = true

    // Position effect view based on arrow edge
    let effectOriginY: CGFloat
    switch arrowEdge {
    case .top:
      effectOriginY = 0
    case .bottom:
      effectOriginY = arrowHeight
    }

    result.effectView.frame = CGRect(
      origin: CGPoint(x: 0, y: effectOriginY),
      size: bodySize
    )
    container.addSubview(result.effectView)

    // Arrow background view (visual effect for arrow)
    let arrow = PopoverArrowView(frame: CGRect(origin: .zero, size: CGSize(width: bodySize.width, height: totalHeight)))
    arrow.arrowEdge = arrowEdge
    arrow.arrowCenterX = bodySize.width / 2
    arrow.wantsLayer = true
    arrow.layer?.compositingFilter = nil
    container.addSubview(arrow, positioned: .below, relativeTo: result.effectView)

    contentView = container
    hostingView = result.hostingView
    effectView = result.effectView
    arrowView = arrow

    setContentSize(CGSize(width: bodySize.width, height: totalHeight))
  }

  // MARK: - Positioning

  private func computeArrowEdge() -> AnnotationPopoverArrowEdge {
    guard let anchor = anchorWindow, let screen = anchor.screen ?? NSScreen.main else {
      return .top
    }
    let anchorFrame = anchor.frame
    let screenMidY = screen.visibleFrame.midY

    // If anchor is in top half, popover goes below (arrow points up)
    // If anchor is in bottom half, popover goes above (arrow points down)
    return anchorFrame.midY > screenMidY ? .top : .bottom
  }

  func showPopover() {
    rebuildContent()
    positionRelativeToAnchor()
    orderFrontRegardless()
    attachToAnchor()
  }

  /// Attach as child window so macOS composites both windows atomically —
  /// the popover moves with the parent in the same compositor frame (zero lag).
  private func attachToAnchor() {
    guard let anchor = anchorWindow else { return }
    if let parent = self.parent { parent.removeChildWindow(self) }
    anchor.addChildWindow(self, ordered: .above)
  }

  /// Detach from parent before hiding
  private func detachFromAnchor() {
    if let parent = self.parent { parent.removeChildWindow(self) }
  }

  func positionRelativeToAnchor() {
    guard let anchor = anchorWindow else {
      positionDefault()
      return
    }

    let anchorFrame = anchor.frame
    let popoverSize = frame.size
    let arrowEdge = computeArrowEdge()

    // Compute X: center popover's arrow on the annotate button
    let anchorButtonScreenX = anchorFrame.origin.x + anchorButtonCenterXOffset
    var popoverX = anchorButtonScreenX - popoverSize.width / 2

    // Clamp X to screen bounds
    if let screen = anchor.screen ?? NSScreen.main {
      let sf = screen.visibleFrame
      popoverX = max(sf.minX + 10, min(popoverX, sf.maxX - popoverSize.width - 10))
    }

    // Update arrow center relative to popover (after clamping)
    let arrowLocalX = anchorButtonScreenX - popoverX
    arrowView?.arrowCenterX = arrowLocalX
    arrowView?.arrowEdge = arrowEdge
    arrowView?.needsDisplay = true

    // Compute Y
    let popoverY: CGFloat
    switch arrowEdge {
    case .top:
      // Popover below status bar: arrow points up toward the bar
      popoverY = anchorFrame.origin.y - popoverSize.height - popoverGap
    case .bottom:
      // Popover above status bar: arrow points down toward the bar
      popoverY = anchorFrame.maxY + popoverGap
    }

    setFrameOrigin(CGPoint(x: popoverX, y: popoverY))
  }

  private func positionDefault() {
    guard let screen = NSScreen.main else { return }
    let sf = screen.visibleFrame
    let size = frame.size
    let x = sf.midX - size.width / 2
    let y = sf.minY + 60
    setFrameOrigin(CGPoint(x: x, y: y))
  }

  override var canBecomeKey: Bool { true }
}
