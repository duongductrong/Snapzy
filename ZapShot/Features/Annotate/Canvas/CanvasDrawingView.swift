//
//  CanvasDrawingView.swift
//  ZapShot
//
//  NSViewRepresentable wrapper for the drawing canvas
//

import AppKit
import SwiftUI

/// NSViewRepresentable wrapper for the drawing canvas
struct CanvasDrawingView: NSViewRepresentable {
  @ObservedObject var state: AnnotateState
  var displayScale: CGFloat = 1.0

  func makeNSView(context: Context) -> DrawingCanvasNSView {
    let view = DrawingCanvasNSView(state: state)
    view.displayScale = displayScale
    return view
  }

  func updateNSView(_ nsView: DrawingCanvasNSView, context: Context) {
    nsView.state = state
    nsView.displayScale = displayScale
    nsView.needsDisplay = true
  }
}

/// Handle types for resize operations
enum ResizeHandle: Equatable {
  case topLeft, topRight, bottomLeft, bottomRight
  case top, bottom, left, right
}

/// NSView subclass handling mouse events and drawing
final class DrawingCanvasNSView: NSView {
  var state: AnnotateState
  var displayScale: CGFloat = 1.0
  private var currentPath: [CGPoint] = []
  private var isDrawing = false
  private var dragStart: CGPoint?

  // Selection and manipulation state
  private var isDraggingAnnotation = false
  private var isResizingAnnotation = false
  private var activeResizeHandle: ResizeHandle?
  private var dragOffset: CGPoint = .zero
  private var originalBounds: CGRect = .zero

  private let handleSize: CGFloat = 8

  init(state: AnnotateState) {
    self.state = state
    super.init(frame: .zero)
    setupView()
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  private func setupView() {
    wantsLayer = true
    layer?.backgroundColor = NSColor.clear.cgColor

    // Enable mouse tracking for cursor updates
    let trackingArea = NSTrackingArea(
      rect: .zero,
      options: [.activeInKeyWindow, .inVisibleRect, .mouseMoved],
      owner: self,
      userInfo: nil
    )
    addTrackingArea(trackingArea)
  }

  // MARK: - First Responder

  override var acceptsFirstResponder: Bool { true }

  override func keyDown(with event: NSEvent) {
    let shift = event.modifierFlags.contains(.shift)
    let nudgeAmount: CGFloat = shift ? 10 : 1

    switch event.keyCode {
    case 51, 117: // Delete, Forward Delete
      if state.selectedAnnotationId != nil && state.editingTextAnnotationId == nil {
        Task { @MainActor in
          state.deleteSelectedAnnotation()
        }
        needsDisplay = true
      }

    case 53: // Escape
      Task { @MainActor in
        state.deselectAnnotation()
      }
      needsDisplay = true

    case 126: // Arrow Up
      if state.selectedAnnotationId != nil && state.editingTextAnnotationId == nil {
        Task { @MainActor in
          state.nudgeSelectedAnnotation(dx: 0, dy: nudgeAmount)
        }
        needsDisplay = true
      }

    case 125: // Arrow Down
      if state.selectedAnnotationId != nil && state.editingTextAnnotationId == nil {
        Task { @MainActor in
          state.nudgeSelectedAnnotation(dx: 0, dy: -nudgeAmount)
        }
        needsDisplay = true
      }

    case 123: // Arrow Left
      if state.selectedAnnotationId != nil && state.editingTextAnnotationId == nil {
        Task { @MainActor in
          state.nudgeSelectedAnnotation(dx: -nudgeAmount, dy: 0)
        }
        needsDisplay = true
      }

    case 124: // Arrow Right
      if state.selectedAnnotationId != nil && state.editingTextAnnotationId == nil {
        Task { @MainActor in
          state.nudgeSelectedAnnotation(dx: nudgeAmount, dy: 0)
        }
        needsDisplay = true
      }

    case 9: // V key
      Task { @MainActor in
        state.selectedTool = .selection
      }

    default:
      super.keyDown(with: event)
    }
  }

  // MARK: - Hit Testing

  /// Find annotation at given point (in image coordinates), topmost first
  private func hitTestAnnotation(at point: CGPoint) -> AnnotationItem? {
    for annotation in state.annotations.reversed() {
      // Quick bounds check first (optimization)
      let expandedBounds = annotation.bounds.insetBy(dx: -10, dy: -10)
      guard expandedBounds.contains(point) else { continue }

      // Precise hit test
      if annotation.containsPoint(point) {
        return annotation
      }
    }
    return nil
  }

  private func hitTestHandle(at point: CGPoint, for bounds: CGRect) -> ResizeHandle? {
    let handles: [(ResizeHandle, CGRect)] = [
      (.topLeft, handleRect(at: CGPoint(x: bounds.minX, y: bounds.maxY))),
      (.topRight, handleRect(at: CGPoint(x: bounds.maxX, y: bounds.maxY))),
      (.bottomLeft, handleRect(at: CGPoint(x: bounds.minX, y: bounds.minY))),
      (.bottomRight, handleRect(at: CGPoint(x: bounds.maxX, y: bounds.minY))),
    ]

    for (handle, rect) in handles {
      if rect.contains(point) {
        return handle
      }
    }
    return nil
  }

  private func handleRect(at center: CGPoint) -> CGRect {
    // Handle size in display coordinates (constant visual size)
    let displayHandleSize = handleSize / displayScale
    return CGRect(
      x: center.x - displayHandleSize / 2,
      y: center.y - displayHandleSize / 2,
      width: displayHandleSize,
      height: displayHandleSize
    )
  }

  // MARK: - Coordinate Transformation

  /// Convert display point to image coordinates (for storage)
  private func displayToImage(_ point: CGPoint) -> CGPoint {
    guard displayScale > 0 else { return point }
    return CGPoint(
      x: point.x / displayScale,
      y: point.y / displayScale
    )
  }

  /// Convert image point to display coordinates (for rendering)
  private func imageToDisplay(_ point: CGPoint) -> CGPoint {
    return CGPoint(
      x: point.x * displayScale,
      y: point.y * displayScale
    )
  }

  /// Convert image rect to display coordinates
  private func imageToDisplay(_ rect: CGRect) -> CGRect {
    return CGRect(
      x: rect.origin.x * displayScale,
      y: rect.origin.y * displayScale,
      width: rect.width * displayScale,
      height: rect.height * displayScale
    )
  }

  /// Convert display rect to image coordinates
  private func displayToImage(_ rect: CGRect) -> CGRect {
    guard displayScale > 0 else { return rect }
    return CGRect(
      x: rect.origin.x / displayScale,
      y: rect.origin.y / displayScale,
      width: rect.width / displayScale,
      height: rect.height / displayScale
    )
  }

  // MARK: - Mouse Events

  override func mouseDown(with event: NSEvent) {
    let displayPoint = convert(event.locationInWindow, from: nil)
    let imagePoint = displayToImage(displayPoint)
    dragStart = imagePoint  // Store in image coords

    // Handle double-click on text annotations to enter edit mode
    if event.clickCount == 2 {
      if let annotation = hitTestAnnotation(at: imagePoint),
         case .text = annotation.type {
        Task { @MainActor in
          state.editingTextAnnotationId = annotation.id
          state.selectedAnnotationId = annotation.id
        }
        needsDisplay = true
        return
      }
    }

    // Clear editing mode when clicking elsewhere
    if state.editingTextAnnotationId != nil {
      Task { @MainActor in
        state.editingTextAnnotationId = nil
      }
    }

    // Check if clicking on a selected annotation's handle (use display coords for handles)
    if let selectedId = state.selectedAnnotationId,
       let annotation = state.annotations.first(where: { $0.id == selectedId }) {
      let displayBounds = imageToDisplay(annotation.bounds)
      if let handle = hitTestHandle(at: displayPoint, for: displayBounds) {
        isResizingAnnotation = true
        activeResizeHandle = handle
        originalBounds = annotation.bounds  // Store in image coords
        return
      }
    }

    // Selection uses image coordinates
    if state.selectedTool == .selection {
      if let annotation = state.selectAnnotation(at: imagePoint) {
        isDraggingAnnotation = true
        dragOffset = CGPoint(
          x: imagePoint.x - annotation.bounds.origin.x,
          y: imagePoint.y - annotation.bounds.origin.y
        )
        originalBounds = annotation.bounds
        NSCursor.closedHand.set()
        needsDisplay = true
        return
      } else {
        // Clicked empty space in selection mode - just deselect
        Task { @MainActor in
          state.deselectAnnotation()
        }
        needsDisplay = true
        return
      }
    }

    // Start drawing for other tools (in image coordinates)
    isDrawing = true
    switch state.selectedTool {
    case .pencil, .highlighter:
      currentPath = [imagePoint]
    case .text:
      // Create text annotation immediately and enter edit mode
      Task { @MainActor in
        state.saveState()
        createTextAnnotation(at: imagePoint)
      }
      isDrawing = false
    default:
      break
    }
  }

  override func mouseDragged(with event: NSEvent) {
    let displayPoint = convert(event.locationInWindow, from: nil)
    let imagePoint = displayToImage(displayPoint)

    // Handle resizing (in image coordinates)
    if isResizingAnnotation, let handle = activeResizeHandle,
       let selectedId = state.selectedAnnotationId {
      let newBounds = calculateResizedBounds(handle: handle, currentPoint: imagePoint)
      Task { @MainActor in
        state.updateAnnotationBounds(id: selectedId, bounds: newBounds)
      }
      needsDisplay = true
      return
    }

    // Handle dragging annotation (in image coordinates)
    if isDraggingAnnotation, let selectedId = state.selectedAnnotationId {
      let newOrigin = CGPoint(
        x: imagePoint.x - dragOffset.x,
        y: imagePoint.y - dragOffset.y
      )
      let newBounds = CGRect(origin: newOrigin, size: originalBounds.size)
      Task { @MainActor in
        state.updateAnnotationBounds(id: selectedId, bounds: newBounds)
      }
      needsDisplay = true
      return
    }

    // Handle drawing (in image coordinates)
    guard isDrawing else { return }

    switch state.selectedTool {
    case .pencil, .highlighter:
      currentPath.append(imagePoint)
      needsDisplay = true
    default:
      currentPath = [imagePoint]
      needsDisplay = true
    }
  }

  override func mouseUp(with event: NSEvent) {
    let displayPoint = convert(event.locationInWindow, from: nil)
    let imagePoint = displayToImage(displayPoint)

    // Finish resizing
    if isResizingAnnotation {
      Task { @MainActor in
        state.saveState()
      }
      isResizingAnnotation = false
      activeResizeHandle = nil
      needsDisplay = true
      return
    }

    // Finish dragging
    if isDraggingAnnotation {
      Task { @MainActor in
        state.saveState()
      }
      isDraggingAnnotation = false
      updateCursor(for: event)
      needsDisplay = true
      return
    }

    // Finish drawing (already in image coords)
    guard isDrawing, let start = dragStart else { return }

    Task { @MainActor in
      state.saveState()
      createAnnotation(from: start, to: imagePoint)
    }

    isDrawing = false
    dragStart = nil
    currentPath = []
    needsDisplay = true
  }

  private func calculateResizedBounds(handle: ResizeHandle, currentPoint: CGPoint) -> CGRect {
    var newBounds = originalBounds

    switch handle {
    case .topLeft:
      newBounds.origin.x = currentPoint.x
      newBounds.size.width = originalBounds.maxX - currentPoint.x
      newBounds.size.height = currentPoint.y - originalBounds.minY
    case .topRight:
      newBounds.size.width = currentPoint.x - originalBounds.minX
      newBounds.size.height = currentPoint.y - originalBounds.minY
    case .bottomLeft:
      newBounds.origin.x = currentPoint.x
      newBounds.origin.y = currentPoint.y
      newBounds.size.width = originalBounds.maxX - currentPoint.x
      newBounds.size.height = originalBounds.maxY - currentPoint.y
    case .bottomRight:
      newBounds.origin.y = currentPoint.y
      newBounds.size.width = currentPoint.x - originalBounds.minX
      newBounds.size.height = originalBounds.maxY - currentPoint.y
    default:
      break
    }

    // Ensure minimum size
    if newBounds.width < 20 { newBounds.size.width = 20 }
    if newBounds.height < 20 { newBounds.size.height = 20 }

    return newBounds
  }

  // MARK: - Annotation Creation

  private func createAnnotation(from start: CGPoint, to end: CGPoint) {
    let item = AnnotationFactory.createAnnotation(
      tool: state.selectedTool,
      from: start,
      to: end,
      path: currentPath,
      state: state
    )
    if let item = item {
      state.annotations.append(item)
    }
  }

  private func createTextAnnotation(at point: CGPoint) {
    let bounds = CGRect(x: point.x, y: point.y - 24, width: 100, height: 28)
    let properties = AnnotationProperties(
      strokeColor: state.strokeColor,
      fillColor: .clear,
      strokeWidth: state.strokeWidth,
      fontSize: 16,
      fontName: "SF Pro"
    )
    // Start with empty text - user will type in the overlay
    let item = AnnotationItem(type: .text(""), bounds: bounds, properties: properties)
    state.annotations.append(item)
    state.selectedAnnotationId = item.id
    state.editingTextAnnotationId = item.id  // Enter edit mode immediately
  }

  // MARK: - Drawing

  override func draw(_ dirtyRect: NSRect) {
    super.draw(dirtyRect)
    guard let context = NSGraphicsContext.current?.cgContext else { return }

    // Apply scale transform for rendering
    context.saveGState()
    context.scaleBy(x: displayScale, y: displayScale)

    // Draw existing annotations (at image coordinates - transform handles scaling)
    let renderer = AnnotationRenderer(context: context, editingTextId: state.editingTextAnnotationId)
    for annotation in state.annotations {
      renderer.draw(annotation)

      // Draw selection handles if selected
      if annotation.id == state.selectedAnnotationId {
        drawSelectionHandles(for: annotation.bounds, in: context)
      }
    }

    // Draw current stroke if drawing
    if isDrawing, let start = dragStart {
      renderer.drawCurrentStroke(
        tool: state.selectedTool,
        start: start,
        currentPath: currentPath,
        strokeColor: state.strokeColor,
        strokeWidth: state.strokeWidth
      )
    }

    context.restoreGState()
  }

  private func drawSelectionHandles(for bounds: CGRect, in context: CGContext) {
    // Draw selection border
    context.setStrokeColor(NSColor.systemBlue.cgColor)
    context.setLineWidth(1)
    context.setLineDash(phase: 0, lengths: [4, 4])
    context.stroke(bounds)
    context.setLineDash(phase: 0, lengths: [])

    // Draw corner handles
    let corners = [
      CGPoint(x: bounds.minX, y: bounds.minY),
      CGPoint(x: bounds.maxX, y: bounds.minY),
      CGPoint(x: bounds.minX, y: bounds.maxY),
      CGPoint(x: bounds.maxX, y: bounds.maxY),
    ]

    context.setFillColor(NSColor.white.cgColor)
    context.setStrokeColor(NSColor.systemBlue.cgColor)
    context.setLineWidth(1)

    for corner in corners {
      let rect = handleRect(at: corner)
      context.fill(rect)
      context.stroke(rect)
    }
  }

  // MARK: - Cursor Management

  override func mouseMoved(with event: NSEvent) {
    updateCursor(for: event)
  }

  private func updateCursor(for event: NSEvent) {
    let displayPoint = convert(event.locationInWindow, from: nil)
    let imagePoint = displayToImage(displayPoint)

    // Check resize handles first
    if let selectedId = state.selectedAnnotationId,
       let annotation = state.annotations.first(where: { $0.id == selectedId }) {
      let displayBounds = imageToDisplay(annotation.bounds)
      if let handle = hitTestHandle(at: displayPoint, for: displayBounds) {
        setCursorForHandle(handle)
        return
      }

      // Check if over selected annotation body
      if annotation.containsPoint(imagePoint) {
        NSCursor.openHand.set()
        return
      }
    }

    // Check if over any annotation in selection mode
    if state.selectedTool == .selection {
      if hitTestAnnotation(at: imagePoint) != nil {
        NSCursor.pointingHand.set()
        return
      }
    }

    // Default cursor
    NSCursor.arrow.set()
  }

  private func setCursorForHandle(_ handle: ResizeHandle) {
    switch handle {
    case .topLeft, .bottomRight:
      NSCursor.crosshair.set()
    case .topRight, .bottomLeft:
      NSCursor.crosshair.set()
    case .top, .bottom:
      NSCursor.resizeUpDown.set()
    case .left, .right:
      NSCursor.resizeLeftRight.set()
    }
  }
}
