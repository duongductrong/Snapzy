//
//  RecordingRegionOverlayWindow.swift
//  Snapzy
//
//  Persistent overlay window showing the recording region highlight
//

import AppKit

// MARK: - RecordingResizeHandle

/// Resize handle positions for edge and corner resizing
enum RecordingResizeHandle {
  case topLeft, top, topRight
  case left, right
  case bottomLeft, bottom, bottomRight
}

// MARK: - RecordingRegionOverlayDelegate

/// Delegate protocol for overlay interaction events
@MainActor
protocol RecordingRegionOverlayDelegate: AnyObject {
  func overlayDidRequestReselection(_ overlay: RecordingRegionOverlayWindow)
  func overlay(_ overlay: RecordingRegionOverlayWindow, didMoveRegionTo rect: CGRect)
  func overlayDidFinishMoving(_ overlay: RecordingRegionOverlayWindow)
  func overlay(_ overlay: RecordingRegionOverlayWindow, didReselectWithRect rect: CGRect)
  func overlay(_ overlay: RecordingRegionOverlayWindow, didResizeRegionTo rect: CGRect)
  func overlayDidFinishResizing(_ overlay: RecordingRegionOverlayWindow)
}

// MARK: - RecordingRegionOverlayWindow

/// Overlay panel showing the recording region highlight during recording
/// Uses NSPanel with .nonactivatingPanel to prevent background windows from deactivating
@MainActor
final class RecordingRegionOverlayWindow: NSPanel {

  weak var interactionDelegate: RecordingRegionOverlayDelegate?

  private let overlayView: RecordingRegionOverlayView

  init(screen: NSScreen, highlightRect: CGRect) {
    self.overlayView = RecordingRegionOverlayView(
      frame: screen.frame,
      highlightRect: highlightRect
    )

    super.init(
      contentRect: screen.frame,
      styleMask: [.borderless, .nonactivatingPanel],
      backing: .buffered,
      defer: false
    )

    configureWindow()
    contentView = overlayView
  }

  private func configureWindow() {
    isFloatingPanel = true
    isOpaque = false
    backgroundColor = .clear
    level = .floating
    ignoresMouseEvents = true
    hasShadow = false
    hidesOnDeactivate = false
    isReleasedWhenClosed = false
    collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
    animationBehavior = .none  // Disable window animations for instant appearance
  }

  func updateHighlightRect(_ rect: CGRect) {
    overlayView.highlightRect = rect
    overlayView.needsDisplay = true
  }

  /// Hide the border when recording starts (border would appear in video)
  func hideBorder() {
    overlayView.showBorder = false
    overlayView.needsDisplay = true
  }

  /// Show the border (for pre-record phase)
  func showBorder() {
    overlayView.showBorder = true
    overlayView.needsDisplay = true
  }

  /// Enable or disable mouse interaction (disabled during recording)
  func setInteractionEnabled(_ enabled: Bool) {
    ignoresMouseEvents = !enabled
    overlayView.isInteractionEnabled = enabled
    if enabled {
      overlayView.overlayWindow = self
    }
  }

  // Non-activating: prevent stealing focus from other apps
  override var canBecomeKey: Bool { false }
  override var canBecomeMain: Bool { false }
}

// MARK: - RecordingRegionOverlayView

/// View that draws the dimmed overlay with highlighted recording region
final class RecordingRegionOverlayView: NSView {

  var highlightRect: CGRect
  var showBorder: Bool = true
  var isInteractionEnabled: Bool = false
  weak var overlayWindow: RecordingRegionOverlayWindow?

  // Drag state
  private var isDragging = false
  private var dragOffset: CGPoint = .zero

  // Resize state
  private var isResizing = false
  private var activeHandle: RecordingResizeHandle?
  private var resizeStartRect: CGRect = .zero
  private var resizeStartPoint: CGPoint = .zero

  // New selection state (for immediate reselection on click outside)
  private var isNewSelecting = false
  private var newSelectionStart: CGPoint = .zero
  private var newSelectionEnd: CGPoint = .zero

  // Constants
  private let dimColor = NSColor.black.withAlphaComponent(0.4)
  private let borderColor = NSColor.white
  private let borderWidth: CGFloat = 1.5
  private let handleHitSize: CGFloat = 10.0
  private let cornerHandleLength: CGFloat = 20.0
  private let edgeHandleLength: CGFloat = 24.0
  private let handleThickness: CGFloat = 3.0
  private let minimumSelectionSize: CGFloat = 50.0

  init(frame: CGRect, highlightRect: CGRect) {
    self.highlightRect = highlightRect
    super.init(frame: frame)
    setupTrackingArea()
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  private func setupTrackingArea() {
    let trackingArea = NSTrackingArea(
      rect: bounds,
      options: [.activeAlways, .mouseMoved, .inVisibleRect],
      owner: self,
      userInfo: nil
    )
    addTrackingArea(trackingArea)
  }

  override func updateTrackingAreas() {
    super.updateTrackingAreas()
    for area in trackingAreas {
      removeTrackingArea(area)
    }
    setupTrackingArea()
  }

  // Accept first mouse click without requiring window activation
  override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
    return true
  }

  // MARK: - Coordinate Conversion

  private func localHighlightRect() -> CGRect {
    guard let window = window else { return .zero }
    let windowFrame = window.frame
    return CGRect(
      x: highlightRect.origin.x - windowFrame.origin.x,
      y: highlightRect.origin.y - windowFrame.origin.y,
      width: highlightRect.width,
      height: highlightRect.height
    )
  }

  private func convertToScreenCoords(_ localPoint: CGPoint) -> CGPoint {
    guard let window = window else { return localPoint }
    return CGPoint(
      x: localPoint.x + window.frame.origin.x,
      y: localPoint.y + window.frame.origin.y
    )
  }

  // MARK: - Resize Handle Detection

  private func handleAt(point: CGPoint) -> RecordingResizeHandle? {
    let rect = localHighlightRect()
    let hs = handleHitSize

    // Corner handles (check first, higher priority)
    if CGRect(x: rect.minX - hs, y: rect.maxY - hs, width: hs * 2, height: hs * 2).contains(point) {
      return .topLeft
    }
    if CGRect(x: rect.maxX - hs, y: rect.maxY - hs, width: hs * 2, height: hs * 2).contains(point) {
      return .topRight
    }
    if CGRect(x: rect.minX - hs, y: rect.minY - hs, width: hs * 2, height: hs * 2).contains(point) {
      return .bottomLeft
    }
    if CGRect(x: rect.maxX - hs, y: rect.minY - hs, width: hs * 2, height: hs * 2).contains(point) {
      return .bottomRight
    }

    // Edge handles
    if CGRect(x: rect.midX - hs, y: rect.maxY - hs, width: hs * 2, height: hs * 2).contains(point) {
      return .top
    }
    if CGRect(x: rect.midX - hs, y: rect.minY - hs, width: hs * 2, height: hs * 2).contains(point) {
      return .bottom
    }
    if CGRect(x: rect.minX - hs, y: rect.midY - hs, width: hs * 2, height: hs * 2).contains(point) {
      return .left
    }
    if CGRect(x: rect.maxX - hs, y: rect.midY - hs, width: hs * 2, height: hs * 2).contains(point) {
      return .right
    }

    return nil
  }

  private func cursorFor(handle: RecordingResizeHandle) -> NSCursor {
    switch handle {
    case .topLeft, .bottomRight:
      // NW-SE diagonal resize (↖↘)
      return NSCursor(image: diagonalResizeCursorImage(nwse: true), hotSpot: NSPoint(x: 8, y: 8))
    case .topRight, .bottomLeft:
      // NE-SW diagonal resize (↗↙)
      return NSCursor(image: diagonalResizeCursorImage(nwse: false), hotSpot: NSPoint(x: 8, y: 8))
    case .top, .bottom:
      return NSCursor.resizeUpDown
    case .left, .right:
      return NSCursor.resizeLeftRight
    }
  }

  /// Generate diagonal resize cursor image (matches Annotate crop cursors)
  private func diagonalResizeCursorImage(nwse: Bool) -> NSImage {
    let size = NSSize(width: 16, height: 16)
    let image = NSImage(size: size)
    image.lockFocus()

    let path = NSBezierPath()
    path.lineWidth = 1.5
    path.lineCapStyle = .round

    if nwse {
      // NW-SE diagonal (↖↘)
      // Arrow pointing to top-left
      path.move(to: NSPoint(x: 3, y: 13))
      path.line(to: NSPoint(x: 3, y: 8))
      path.move(to: NSPoint(x: 3, y: 13))
      path.line(to: NSPoint(x: 8, y: 13))
      // Main diagonal line
      path.move(to: NSPoint(x: 3, y: 13))
      path.line(to: NSPoint(x: 13, y: 3))
      // Arrow pointing to bottom-right
      path.move(to: NSPoint(x: 13, y: 3))
      path.line(to: NSPoint(x: 13, y: 8))
      path.move(to: NSPoint(x: 13, y: 3))
      path.line(to: NSPoint(x: 8, y: 3))
    } else {
      // NE-SW diagonal (↗↙)
      // Arrow pointing to top-right
      path.move(to: NSPoint(x: 13, y: 13))
      path.line(to: NSPoint(x: 13, y: 8))
      path.move(to: NSPoint(x: 13, y: 13))
      path.line(to: NSPoint(x: 8, y: 13))
      // Main diagonal line
      path.move(to: NSPoint(x: 13, y: 13))
      path.line(to: NSPoint(x: 3, y: 3))
      // Arrow pointing to bottom-left
      path.move(to: NSPoint(x: 3, y: 3))
      path.line(to: NSPoint(x: 3, y: 8))
      path.move(to: NSPoint(x: 3, y: 3))
      path.line(to: NSPoint(x: 8, y: 3))
    }

    // Draw white outline for visibility on dark backgrounds
    NSColor.white.withAlphaComponent(0.5).setStroke()
    path.lineWidth = 2.5
    path.stroke()

    // Draw black arrow
    NSColor.black.setStroke()
    path.lineWidth = 1.5
    path.stroke()

    image.unlockFocus()
    return image
  }

  private func calculateResizedRect(handle: RecordingResizeHandle, delta: CGPoint) -> CGRect {
    var rect = resizeStartRect
    let minSize = minimumSelectionSize

    switch handle {
    case .topLeft:
      rect.origin.x += delta.x
      rect.size.width -= delta.x
      rect.size.height += delta.y
    case .top:
      rect.size.height += delta.y
    case .topRight:
      rect.size.width += delta.x
      rect.size.height += delta.y
    case .left:
      rect.origin.x += delta.x
      rect.size.width -= delta.x
    case .right:
      rect.size.width += delta.x
    case .bottomLeft:
      rect.origin.x += delta.x
      rect.origin.y += delta.y
      rect.size.width -= delta.x
      rect.size.height -= delta.y
    case .bottom:
      rect.origin.y += delta.y
      rect.size.height -= delta.y
    case .bottomRight:
      rect.origin.y += delta.y
      rect.size.width += delta.x
      rect.size.height -= delta.y
    }

    // Enforce minimum size with origin adjustment
    if rect.width < minSize {
      if handle == .left || handle == .topLeft || handle == .bottomLeft {
        rect.origin.x = resizeStartRect.maxX - minSize
      }
      rect.size.width = minSize
    }
    if rect.height < minSize {
      if handle == .bottom || handle == .bottomLeft || handle == .bottomRight {
        rect.origin.y = resizeStartRect.maxY - minSize
      }
      rect.size.height = minSize
    }

    return rect
  }

  // MARK: - Mouse Events

  override func mouseDown(with event: NSEvent) {
    guard isInteractionEnabled, overlayWindow != nil else { return }

    let point = convert(event.locationInWindow, from: nil)
    let localRect = localHighlightRect()

    // Check for resize handle first
    if let handle = handleAt(point: point) {
      isResizing = true
      activeHandle = handle
      resizeStartRect = highlightRect
      resizeStartPoint = point
      cursorFor(handle: handle).set()
      return
    }

    if localRect.contains(point) {
      // Start dragging existing selection
      isDragging = true
      dragOffset = CGPoint(
        x: point.x - localRect.origin.x,
        y: point.y - localRect.origin.y
      )
      NSCursor.closedHand.set()
    } else {
      // Click outside - start new selection immediately
      isNewSelecting = true
      newSelectionStart = point
      newSelectionEnd = point
      NSCursor.crosshair.set()
    }
  }

  override func mouseDragged(with event: NSEvent) {
    guard isInteractionEnabled, let overlayWindow = overlayWindow else { return }

    let point = convert(event.locationInWindow, from: nil)

    if isResizing, let handle = activeHandle {
      // Calculate resize delta and new rect
      let delta = CGPoint(x: point.x - resizeStartPoint.x, y: point.y - resizeStartPoint.y)
      let newRect = calculateResizedRect(handle: handle, delta: delta)
      overlayWindow.interactionDelegate?.overlay(overlayWindow, didResizeRegionTo: newRect)
      return
    }

    if isNewSelecting {
      // Update new selection rect
      newSelectionEnd = point
      needsDisplay = true
    } else if isDragging {
      // Calculate new local origin for dragging
      var newLocalOrigin = CGPoint(
        x: point.x - dragOffset.x,
        y: point.y - dragOffset.y
      )

      // Clamp to screen bounds
      newLocalOrigin.x = max(0, min(newLocalOrigin.x, bounds.width - highlightRect.width))
      newLocalOrigin.y = max(0, min(newLocalOrigin.y, bounds.height - highlightRect.height))

      // Convert to screen coordinates
      let screenOrigin = convertToScreenCoords(newLocalOrigin)
      let newRect = CGRect(origin: screenOrigin, size: highlightRect.size)

      // Notify delegate
      overlayWindow.interactionDelegate?.overlay(overlayWindow, didMoveRegionTo: newRect)
    }
  }

  override func mouseUp(with event: NSEvent) {
    guard let overlayWindow = overlayWindow else { return }

    if isResizing {
      isResizing = false
      activeHandle = nil
      overlayWindow.interactionDelegate?.overlayDidFinishResizing(overlayWindow)
      // Update cursor based on current position
      let point = convert(event.locationInWindow, from: nil)
      updateCursorFor(point: point)
      return
    }

    if isNewSelecting {
      // Complete new selection
      isNewSelecting = false
      let newRect = calculateNewSelectionRect()

      // Only accept if selection is large enough
      if newRect.width > 5 && newRect.height > 5 {
        // Convert to screen coordinates
        let screenRect = CGRect(
          origin: convertToScreenCoords(newRect.origin),
          size: newRect.size
        )
        overlayWindow.interactionDelegate?.overlay(overlayWindow, didReselectWithRect: screenRect)
      }
      needsDisplay = true
    } else if isDragging {
      isDragging = false
      NSCursor.openHand.set()
      overlayWindow.interactionDelegate?.overlayDidFinishMoving(overlayWindow)
    }
  }

  private func calculateNewSelectionRect() -> CGRect {
    let minX = min(newSelectionStart.x, newSelectionEnd.x)
    let maxX = max(newSelectionStart.x, newSelectionEnd.x)
    let minY = min(newSelectionStart.y, newSelectionEnd.y)
    let maxY = max(newSelectionStart.y, newSelectionEnd.y)
    return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
  }

  override func mouseMoved(with event: NSEvent) {
    guard isInteractionEnabled else { return }
    let point = convert(event.locationInWindow, from: nil)
    updateCursorFor(point: point)
  }

  private func updateCursorFor(point: CGPoint) {
    // Check for resize handle first
    if let handle = handleAt(point: point) {
      cursorFor(handle: handle).set()
      return
    }

    let localRect = localHighlightRect()
    if localRect.contains(point) {
      NSCursor.openHand.set()
    } else {
      NSCursor.crosshair.set()
    }
  }

  // MARK: - Drawing

  override func draw(_ dirtyRect: NSRect) {
    super.draw(dirtyRect)

    // Draw dim overlay
    dimColor.setFill()
    bounds.fill()

    // If actively making new selection, draw that instead
    if isNewSelecting {
      drawNewSelection()
      return
    }

    // Convert screen coords to view coords
    guard let window = window else { return }
    let windowFrame = window.frame
    let localRect = CGRect(
      x: highlightRect.origin.x - windowFrame.origin.x,
      y: highlightRect.origin.y - windowFrame.origin.y,
      width: highlightRect.width,
      height: highlightRect.height
    )

    // Only draw highlight if rect intersects this screen
    guard localRect.intersects(bounds) else { return }

    // Clamp to bounds
    let clampedRect = localRect.intersection(bounds)

    // Clear the highlight area
    NSColor.clear.setFill()
    clampedRect.fill(using: .copy)

    // Draw border around highlight (only in pre-record phase)
    if showBorder {
      let borderPath = NSBezierPath(rect: clampedRect)
      borderPath.lineWidth = borderWidth
      borderColor.setStroke()
      borderPath.stroke()

      // Draw resize handles
      drawRecordingResizeHandles(for: clampedRect)
    }
  }

  private func drawRecordingResizeHandles(for rect: CGRect) {
    // Draw L-shaped corner handles (CleanShot X style)
    drawCornerHandle(at: CGPoint(x: rect.minX, y: rect.maxY), corner: .topLeft)
    drawCornerHandle(at: CGPoint(x: rect.maxX, y: rect.maxY), corner: .topRight)
    drawCornerHandle(at: CGPoint(x: rect.minX, y: rect.minY), corner: .bottomLeft)
    drawCornerHandle(at: CGPoint(x: rect.maxX, y: rect.minY), corner: .bottomRight)

    // Draw edge handles (subtle lines)
    drawEdgeHandle(at: CGPoint(x: rect.midX, y: rect.maxY), edge: .top)
    drawEdgeHandle(at: CGPoint(x: rect.midX, y: rect.minY), edge: .bottom)
    drawEdgeHandle(at: CGPoint(x: rect.minX, y: rect.midY), edge: .left)
    drawEdgeHandle(at: CGPoint(x: rect.maxX, y: rect.midY), edge: .right)
  }

  private func drawCornerHandle(at point: CGPoint, corner: RecordingResizeHandle) {
    let length = cornerHandleLength
    let thickness = handleThickness
    let halfThickness = thickness / 2

    // Calculate offsets to center handles on the outline
    // Horizontal bar: centered vertically on the horizontal edge
    // Vertical bar: centered horizontally on the vertical edge
    let hRect: CGRect
    let vRect: CGRect

    switch corner {
    case .topLeft:
      // Horizontal bar extends right from corner, centered on top edge
      hRect = CGRect(
        x: point.x - halfThickness,
        y: point.y - halfThickness,
        width: length,
        height: thickness
      )
      // Vertical bar extends down from corner, centered on left edge
      vRect = CGRect(
        x: point.x - halfThickness,
        y: point.y - length + halfThickness,
        width: thickness,
        height: length
      )
    case .topRight:
      // Horizontal bar extends left from corner, centered on top edge
      hRect = CGRect(
        x: point.x - length + halfThickness,
        y: point.y - halfThickness,
        width: length,
        height: thickness
      )
      // Vertical bar extends down from corner, centered on right edge
      vRect = CGRect(
        x: point.x - halfThickness,
        y: point.y - length + halfThickness,
        width: thickness,
        height: length
      )
    case .bottomLeft:
      // Horizontal bar extends right from corner, centered on bottom edge
      hRect = CGRect(
        x: point.x - halfThickness,
        y: point.y - halfThickness,
        width: length,
        height: thickness
      )
      // Vertical bar extends up from corner, centered on left edge
      vRect = CGRect(
        x: point.x - halfThickness,
        y: point.y - halfThickness,
        width: thickness,
        height: length
      )
    case .bottomRight:
      // Horizontal bar extends left from corner, centered on bottom edge
      hRect = CGRect(
        x: point.x - length + halfThickness,
        y: point.y - halfThickness,
        width: length,
        height: thickness
      )
      // Vertical bar extends up from corner, centered on right edge
      vRect = CGRect(
        x: point.x - halfThickness,
        y: point.y - halfThickness,
        width: thickness,
        height: length
      )
    default:
      return
    }

    drawHandleBar(hRect)
    drawHandleBar(vRect)
  }

  private func drawEdgeHandle(at point: CGPoint, edge: RecordingResizeHandle) {
    let length = edgeHandleLength
    let thickness = handleThickness
    let halfLength = length / 2
    let halfThickness = thickness / 2

    let handleRect: CGRect
    switch edge {
    case .top, .bottom:
      handleRect = CGRect(
        x: point.x - halfLength,
        y: point.y - halfThickness,
        width: length,
        height: thickness
      )
    case .left, .right:
      handleRect = CGRect(
        x: point.x - halfThickness,
        y: point.y - halfLength,
        width: thickness,
        height: length
      )
    default:
      return
    }
    drawHandleBar(handleRect)
  }

  private func drawHandleBar(_ rect: CGRect) {
    // Draw shadow
    let shadowPath = NSBezierPath(rect: rect.offsetBy(dx: 0, dy: -1))
    NSColor.black.withAlphaComponent(0.5).setFill()
    shadowPath.fill()

    // Draw white bar
    let path = NSBezierPath(rect: rect)
    NSColor.white.setFill()
    path.fill()
  }

  private func drawNewSelection() {
    let selectionRect = calculateNewSelectionRect()
    guard selectionRect.width > 0 && selectionRect.height > 0 else { return }

    // Clear the selection area
    NSColor.clear.setFill()
    selectionRect.fill(using: .copy)

    // Draw border
    let borderPath = NSBezierPath(rect: selectionRect)
    borderPath.lineWidth = borderWidth
    borderColor.setStroke()
    borderPath.stroke()

    // Draw size indicator
    let sizeText = "\(Int(selectionRect.width)) x \(Int(selectionRect.height))"
    let attributes: [NSAttributedString.Key: Any] = [
      .font: NSFont.systemFont(ofSize: 12, weight: .medium),
      .foregroundColor: NSColor.white,
    ]
    let textSize = sizeText.size(withAttributes: attributes)
    var textRect = CGRect(
      x: selectionRect.maxX - textSize.width - 8,
      y: selectionRect.minY - textSize.height - 8,
      width: textSize.width + 8,
      height: textSize.height + 4
    )
    if textRect.minY < 0 { textRect.origin.y = selectionRect.maxY + 4 }
    if textRect.maxX > bounds.maxX { textRect.origin.x = selectionRect.minX }

    NSColor.black.withAlphaComponent(0.7).setFill()
    NSBezierPath(roundedRect: textRect, xRadius: 4, yRadius: 4).fill()
    sizeText.draw(at: CGPoint(x: textRect.minX + 4, y: textRect.minY + 2), withAttributes: attributes)
  }
}
