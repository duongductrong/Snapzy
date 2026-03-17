//
//  CanvasDrawingView.swift
//  Snapzy
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
  private let shortcutManager = AnnotateShortcutManager.shared
  private var currentPath: [CGPoint] = []
  private var isDrawing = false
  private var dragStart: CGPoint?

  // Selection and manipulation state
  private var isDraggingAnnotation = false
  private var isResizingAnnotation = false
  private var activeResizeHandle: ResizeHandle?
  private var dragOffset: CGPoint = .zero
  private var originalBounds: CGRect = .zero

  // Crop interaction state
  private var isCropDragging = false
  private var isCropResizing = false
  private var activeCropHandle: CropHandle?
  private var originalCropRect: CGRect = .zero

  private let handleSize: CGFloat = 8

  // Blur cache manager for performance optimization
  private let blurCacheManager = BlurCacheManager()

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
      // Cancel crop if active
      if state.selectedTool == .crop && state.isCropActive {
        Task { @MainActor in
          state.cancelCrop()
        }
        needsDisplay = true
        return
      }
      Task { @MainActor in
        state.deselectAnnotation()
      }
      needsDisplay = true

    case 36: // Enter - confirm crop
      if state.selectedTool == .crop && state.isCropActive {
        Task { @MainActor in
          state.applyCrop()
          state.selectedTool = .selection
        }
        needsDisplay = true
        return
      }

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

    case 6: // Z key - Undo/Redo
      if event.modifierFlags.contains(.command) {
        Task { @MainActor in
          if event.modifierFlags.contains(.shift) {
            state.redo()
          } else {
            state.undo()
          }
        }
        needsDisplay = true
      }

    default:
      // Tool shortcuts — use configured shortcuts from AnnotateShortcutManager
      if !event.modifierFlags.contains(.command),
         let char = event.characters?.lowercased().first,
         let matchedTool = shortcutManager.tool(for: char) {
        Task { @MainActor in
          // Commit any active text edit before switching
          if state.editingTextAnnotationId != nil {
            state.commitTextEditing()
          }
          state.selectedTool = matchedTool
        }
        needsDisplay = true
      } else {
        super.keyDown(with: event)
      }
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

  /// Clamp point to effective drawing bounds (crop rect if applied, otherwise full image)
  private func clampToImageBounds(_ point: CGPoint) -> CGPoint {
    // Use crop bounds if crop is applied (not actively editing)
    let bounds: CGRect
    if let cropRect = state.cropRect, !state.isCropActive {
      // Crop is applied - constrain to crop area
      bounds = cropRect
    } else {
      // No crop or crop is being edited - use full image bounds
      bounds = CGRect(origin: .zero, size: CGSize(width: state.imageWidth, height: state.imageHeight))
    }

    return CGPoint(
      x: max(bounds.minX, min(point.x, bounds.maxX)),
      y: max(bounds.minY, min(point.y, bounds.maxY))
    )
  }

  // MARK: - Mouse Events

  override func mouseDown(with event: NSEvent) {
    let displayPoint = convert(event.locationInWindow, from: nil)
    let rawImagePoint = displayToImage(displayPoint)
    let imagePoint = clampToImageBounds(rawImagePoint)  // Constrain to canvas
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

    // Commit text editing when clicking elsewhere
    if state.editingTextAnnotationId != nil {
      Task { @MainActor in
        state.commitTextEditing()
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

    // Handle crop tool
    if state.selectedTool == .crop {
      handleCropMouseDown(at: imagePoint)
      return
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

    // Allow move/resize of existing annotations when clicking on them
    // even in non-selection tool modes (acts like selection for that item)
    if state.selectedTool != .crop, let annotation = hitTestAnnotation(at: imagePoint) {
      Task { @MainActor in
        state.selectedAnnotationId = annotation.id
      }
      isDraggingAnnotation = true
      dragOffset = CGPoint(
        x: imagePoint.x - annotation.bounds.origin.x,
        y: imagePoint.y - annotation.bounds.origin.y
      )
      originalBounds = annotation.bounds
      NSCursor.closedHand.set()
      needsDisplay = true
      return
    }

    // Start drawing for other tools (in image coordinates)
    isDrawing = true
    switch state.selectedTool {
    case .pencil, .highlighter:
      currentPath = [imagePoint]
    case .text:
      // Only create new text annotation when not already editing one
      // (if we were editing, commitTextEditing() above already handled it)
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
    let rawImagePoint = displayToImage(displayPoint)
    let imagePoint = clampToImageBounds(rawImagePoint)  // Constrain to canvas

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

    // Handle crop resizing
    if isCropResizing, let handle = activeCropHandle {
      let shiftHeld = event.modifierFlags.contains(.shift)
      handleCropResize(handle: handle, currentPoint: imagePoint, shiftHeld: shiftHeld)
      Task { @MainActor in
        state.isCropResizing = true
        state.isCropShiftLocked = shiftHeld
      }
      needsDisplay = true
      return
    }

    // Handle crop dragging
    if isCropDragging {
      handleCropDrag(to: imagePoint)
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
    let rawImagePoint = displayToImage(displayPoint)
    let imagePoint = clampToImageBounds(rawImagePoint)  // Constrain to canvas

    // Finish resizing
    if isResizingAnnotation {
      // Invalidate blur cache if resizing a blur annotation
      if let selectedId = state.selectedAnnotationId,
         let annotation = state.annotations.first(where: { $0.id == selectedId }),
         case .blur = annotation.type {
        blurCacheManager.invalidate(id: selectedId)
      }
      Task { @MainActor in
        state.saveState()
      }
      isResizingAnnotation = false
      activeResizeHandle = nil
      needsDisplay = true
      return
    }

    // Finish crop resizing or dragging
    if isCropResizing || isCropDragging {
      isCropResizing = false
      isCropDragging = false
      activeCropHandle = nil
      Task { @MainActor in
        state.isCropResizing = false
        state.isCropShiftLocked = false
      }
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

    // Capture path before clearing to avoid race condition
    let pathToSave = currentPath

    Task { @MainActor in
      state.saveState()
      createAnnotation(from: start, to: imagePoint, path: pathToSave)
    }

    isDrawing = false
    dragStart = nil
    currentPath = []
    needsDisplay = true
  }

  private func calculateResizedBounds(handle: ResizeHandle, currentPoint: CGPoint) -> CGRect {
    let minSize: CGFloat = 20
    var newBounds = originalBounds

    switch handle {
    case .topLeft:
      let clampedX = min(currentPoint.x, originalBounds.maxX - minSize)
      let clampedY = max(currentPoint.y, originalBounds.minY + minSize)
      newBounds.origin.x = clampedX
      newBounds.size.width = originalBounds.maxX - clampedX
      newBounds.size.height = clampedY - originalBounds.minY
    case .topRight:
      let clampedX = max(currentPoint.x, originalBounds.minX + minSize)
      let clampedY = max(currentPoint.y, originalBounds.minY + minSize)
      newBounds.size.width = clampedX - originalBounds.minX
      newBounds.size.height = clampedY - originalBounds.minY
    case .bottomLeft:
      let clampedX = min(currentPoint.x, originalBounds.maxX - minSize)
      let clampedY = min(currentPoint.y, originalBounds.maxY - minSize)
      newBounds.origin.x = clampedX
      newBounds.origin.y = clampedY
      newBounds.size.width = originalBounds.maxX - clampedX
      newBounds.size.height = originalBounds.maxY - clampedY
    case .bottomRight:
      let clampedX = max(currentPoint.x, originalBounds.minX + minSize)
      let clampedY = min(currentPoint.y, originalBounds.maxY - minSize)
      newBounds.origin.y = clampedY
      newBounds.size.width = clampedX - originalBounds.minX
      newBounds.size.height = originalBounds.maxY - clampedY
    default:
      break
    }

    return newBounds
  }

  // MARK: - Annotation Creation

  private func createAnnotation(from start: CGPoint, to end: CGPoint, path: [CGPoint]) {
    let item = AnnotationFactory.createAnnotation(
      tool: state.selectedTool,
      from: start,
      to: end,
      path: path,
      state: state
    )
    if let item = item {
      state.annotations.append(item)
    }
  }

  private func createTextAnnotation(at point: CGPoint) {
    let fontSize: CGFloat = 16
    let properties = AnnotationProperties(
      strokeColor: state.strokeColor,
      fillColor: .clear,
      strokeWidth: state.strokeWidth,
      fontSize: fontSize,
      fontName: "SF Pro"
    )
    let initialBounds = AnnotateTextLayout.bounds(
      text: "",
      font: AnnotateTextLayout.font(size: fontSize, fontName: properties.fontName),
      origin: .zero,
      constrainedWidth: AnnotateTextLayout.defaultInitialWidth
    )
    let bounds = CGRect(
      x: point.x,
      y: point.y - initialBounds.height,
      width: initialBounds.width,
      height: initialBounds.height
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
    let renderer = AnnotationRenderer(
      context: context,
      editingTextId: state.editingTextAnnotationId,
      sourceImage: state.sourceImage,
      blurCacheManager: blurCacheManager
    )
    for annotation in state.annotations {
      renderer.draw(annotation)

      // Draw selection handles if selected
      if annotation.id == state.selectedAnnotationId {
        drawSelectionHandles(for: annotation.bounds, in: context)
      }
    }

    // Draw current stroke if drawing
    if isDrawing, let start = dragStart {
      // Special handling for blur tool preview
      if state.selectedTool == .blur, let lastPoint = currentPath.last {
        renderer.drawBlurPreview(
          start: start,
          currentPoint: lastPoint,
          strokeColor: state.strokeColor,
          blurType: state.blurType
        )
      } else {
        renderer.drawCurrentStroke(
          tool: state.selectedTool,
          start: start,
          currentPath: currentPath,
          strokeColor: state.strokeColor,
          strokeWidth: state.strokeWidth
        )
      }
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

    // Show hand cursor when hovering over any annotation (for move/resize in any tool mode)
    if hitTestAnnotation(at: imagePoint) != nil {
      NSCursor.pointingHand.set()
      return
    }

    // Check crop handles when crop tool is active
    if state.selectedTool == .crop, let cropRect = state.cropRect {
      if let handle = hitTestCropHandle(at: imagePoint, for: cropRect) {
        setCursorForCropHandle(handle)
        return
      }
      // Check if over crop body
      if cropRect.contains(imagePoint) {
        NSCursor.openHand.set()
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

  private func setCursorForCropHandle(_ handle: CropHandle) {
    // Note: In image coordinates, Y increases upward (bottom-left origin)
    // But visually on screen, Y increases downward (top-left origin)
    // So topLeft visually appears at top-left of screen
    switch handle {
    case .topLeft, .bottomRight:
      // NW-SE diagonal resize (↖↘)
      NSCursor(image: diagonalResizeCursorImage(nwse: true), hotSpot: NSPoint(x: 8, y: 8)).set()
    case .topRight, .bottomLeft:
      // NE-SW diagonal resize (↗↙)
      NSCursor(image: diagonalResizeCursorImage(nwse: false), hotSpot: NSPoint(x: 8, y: 8)).set()
    case .top, .bottom:
      NSCursor.resizeUpDown.set()
    case .left, .right:
      NSCursor.resizeLeftRight.set()
    case .body:
      NSCursor.openHand.set()
    }
  }

  /// Generate diagonal resize cursor image
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

    // Draw white outline for visibility
    NSColor.white.setStroke()
    path.lineWidth = 3
    path.stroke()

    // Draw black line
    NSColor.black.setStroke()
    path.lineWidth = 1.5
    path.stroke()

    image.unlockFocus()
    return image
  }

  // MARK: - Crop Handling

  private func handleCropMouseDown(at imagePoint: CGPoint) {
    // Initialize crop if not set
    if state.cropRect == nil {
      Task { @MainActor in
        state.initializeCrop()
      }
      return
    }

    // Re-enable crop editing if clicking on crop area when not active
    if !state.isCropActive {
      Task { @MainActor in
        state.isCropActive = true
      }
    }

    guard let cropRect = state.cropRect else { return }

    // Check for handle hit
    if let handle = hitTestCropHandle(at: imagePoint, for: cropRect) {
      if handle == .body {
        isCropDragging = true
        dragOffset = CGPoint(
          x: imagePoint.x - cropRect.origin.x,
          y: imagePoint.y - cropRect.origin.y
        )
      } else {
        isCropResizing = true
        activeCropHandle = handle
      }
      originalCropRect = cropRect
    } else if cropRect.contains(imagePoint) {
      // Clicked inside crop area - start dragging
      isCropDragging = true
      dragOffset = CGPoint(
        x: imagePoint.x - cropRect.origin.x,
        y: imagePoint.y - cropRect.origin.y
      )
      originalCropRect = cropRect
    }
  }

  private func hitTestCropHandle(at point: CGPoint, for cropRect: CGRect) -> CropHandle? {
    // Use a fixed handle radius in image coordinates (not scaled)
    let handleRadius: CGFloat = max(15, 12 / displayScale)

    // In image coordinates: origin is bottom-left, Y increases upward
    let handles: [(CropHandle, CGPoint)] = [
      (.topLeft, CGPoint(x: cropRect.minX, y: cropRect.maxY)),
      (.top, CGPoint(x: cropRect.midX, y: cropRect.maxY)),
      (.topRight, CGPoint(x: cropRect.maxX, y: cropRect.maxY)),
      (.left, CGPoint(x: cropRect.minX, y: cropRect.midY)),
      (.right, CGPoint(x: cropRect.maxX, y: cropRect.midY)),
      (.bottomLeft, CGPoint(x: cropRect.minX, y: cropRect.minY)),
      (.bottom, CGPoint(x: cropRect.midX, y: cropRect.minY)),
      (.bottomRight, CGPoint(x: cropRect.maxX, y: cropRect.minY)),
    ]

    for (handle, center) in handles {
      let distance = hypot(point.x - center.x, point.y - center.y)
      if distance <= handleRadius {
        return handle
      }
    }

    return nil
  }

  private func handleCropResize(handle: CropHandle, currentPoint: CGPoint, shiftHeld: Bool = false) {
    var newRect = originalCropRect

    // Clamp current point to image boundaries
    let imageWidth = state.imageWidth
    let imageHeight = state.imageHeight
    let clampedPoint = CGPoint(
      x: max(0, min(currentPoint.x, imageWidth)),
      y: max(0, min(currentPoint.y, imageHeight))
    )

    let minSize: CGFloat = 20

    // Determine target aspect ratio
    let aspectRatio: CGFloat?
    if shiftHeld {
      // Lock to current aspect ratio when Shift is held
      aspectRatio = originalCropRect.width / originalCropRect.height
    } else if state.cropAspectRatio != .free {
      aspectRatio = state.cropAspectRatio.ratio
    } else {
      aspectRatio = nil
    }

    switch handle {
    case .topLeft:
      let maxX = originalCropRect.maxX - minSize
      let minY = originalCropRect.minY + minSize
      newRect.origin.x = min(clampedPoint.x, maxX)
      newRect.size.width = originalCropRect.maxX - newRect.origin.x
      newRect.size.height = max(clampedPoint.y, minY) - originalCropRect.minY
    case .top:
      let minY = originalCropRect.minY + minSize
      newRect.size.height = max(clampedPoint.y, minY) - originalCropRect.minY
    case .topRight:
      let minX = originalCropRect.minX + minSize
      let minY = originalCropRect.minY + minSize
      newRect.size.width = max(clampedPoint.x, minX) - originalCropRect.minX
      newRect.size.height = max(clampedPoint.y, minY) - originalCropRect.minY
    case .left:
      let maxX = originalCropRect.maxX - minSize
      newRect.origin.x = min(clampedPoint.x, maxX)
      newRect.size.width = originalCropRect.maxX - newRect.origin.x
    case .right:
      let minX = originalCropRect.minX + minSize
      newRect.size.width = max(clampedPoint.x, minX) - originalCropRect.minX
    case .bottomLeft:
      let maxX = originalCropRect.maxX - minSize
      let maxY = originalCropRect.maxY - minSize
      newRect.origin.x = min(clampedPoint.x, maxX)
      newRect.origin.y = min(clampedPoint.y, maxY)
      newRect.size.width = originalCropRect.maxX - newRect.origin.x
      newRect.size.height = originalCropRect.maxY - newRect.origin.y
    case .bottom:
      let maxY = originalCropRect.maxY - minSize
      newRect.origin.y = min(clampedPoint.y, maxY)
      newRect.size.height = originalCropRect.maxY - newRect.origin.y
    case .bottomRight:
      let minX = originalCropRect.minX + minSize
      let maxY = originalCropRect.maxY - minSize
      newRect.origin.y = min(clampedPoint.y, maxY)
      newRect.size.width = max(clampedPoint.x, minX) - originalCropRect.minX
      newRect.size.height = originalCropRect.maxY - newRect.origin.y
    case .body:
      break
    }

    // Apply aspect ratio constraint if needed
    if let ratio = aspectRatio, handle != .body {
      newRect = applyAspectRatio(ratio, to: newRect, handle: handle, original: originalCropRect)
    }

    Task { @MainActor in
      state.updateCropRect(newRect)
    }
  }

  /// Apply aspect ratio constraint to crop rect based on resize handle
  private func applyAspectRatio(_ ratio: CGFloat, to rect: CGRect, handle: CropHandle, original: CGRect) -> CGRect {
    var result = rect

    // For edge handles, calculate the constrained dimension based on the handle direction
    // For corner handles, adjust based on which dimension changed more
    switch handle {
    case .left, .right:
      // Width is the primary dimension, calculate height from width
      let newHeight = rect.width / ratio
      let heightDiff = newHeight - rect.height
      // Center the height adjustment
      result.origin.y = rect.origin.y - heightDiff / 2
      result.size.height = newHeight
      // Clamp to image bounds
      if result.origin.y < 0 {
        result.origin.y = 0
      }
      if result.maxY > state.imageHeight {
        result.size.height = state.imageHeight - result.origin.y
        result.size.width = result.size.height * ratio
        if handle == .left {
          result.origin.x = original.maxX - result.size.width
        }
      }

    case .top, .bottom:
      // Height is the primary dimension, calculate width from height
      let newWidth = rect.height * ratio
      let widthDiff = newWidth - rect.width
      // Center the width adjustment
      result.origin.x = rect.origin.x - widthDiff / 2
      result.size.width = newWidth
      // Clamp to image bounds
      if result.origin.x < 0 {
        result.origin.x = 0
      }
      if result.maxX > state.imageWidth {
        result.size.width = state.imageWidth - result.origin.x
        result.size.height = result.size.width / ratio
        if handle == .bottom {
          result.origin.y = original.maxY - result.size.height
        }
      }

    case .topLeft, .topRight, .bottomLeft, .bottomRight:
      // For corners, adjust based on which dimension changed more
      let currentRatio = rect.width / rect.height
      if currentRatio > ratio {
        // Too wide, adjust width to match height
        let newWidth = rect.height * ratio
        switch handle {
        case .topLeft, .bottomLeft:
          result.origin.x = original.maxX - newWidth
          result.size.width = newWidth
        case .topRight, .bottomRight:
          result.size.width = newWidth
        default:
          break
        }
      } else {
        // Too tall, adjust height to match width
        let newHeight = rect.width / ratio
        switch handle {
        case .topLeft, .topRight:
          result.size.height = newHeight
        case .bottomLeft, .bottomRight:
          result.origin.y = original.maxY - newHeight
          result.size.height = newHeight
        default:
          break
        }
      }

    case .body:
      break
    }

    return result
  }

  private func handleCropDrag(to point: CGPoint) {
    let newOrigin = CGPoint(
      x: point.x - dragOffset.x,
      y: point.y - dragOffset.y
    )
    var newRect = originalCropRect
    newRect.origin = newOrigin

    Task { @MainActor in
      state.updateCropRect(newRect)
    }
  }
}
