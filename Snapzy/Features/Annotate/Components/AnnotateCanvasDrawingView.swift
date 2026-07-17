//
//  AnnotateCanvasDrawingView.swift
//  Snapzy
//
//  NSViewRepresentable wrapper for the drawing canvas
//

import AppKit
import Combine
import SwiftUI

/// NSViewRepresentable wrapper for the drawing canvas
struct CanvasDrawingView: NSViewRepresentable {
  let state: AnnotateState
  var displayScale: CGFloat = 1.0
  var canvasBounds: CGRect

  func makeNSView(context _: Context) -> DrawingCanvasNSView {
    let view = DrawingCanvasNSView(state: state)
    view.displayScale = displayScale
    view.canvasBounds = canvasBounds
    return view
  }

  func updateNSView(_ nsView: DrawingCanvasNSView, context _: Context) {
    if nsView.state !== state {
      nsView.state = state
    }
    if abs(nsView.displayScale - displayScale) > 0.0001 {
      nsView.displayScale = displayScale
      nsView.invalidateDrawing()
    }
    if nsView.canvasBounds != canvasBounds {
      nsView.canvasBounds = canvasBounds
      nsView.invalidateDrawing()
    }
  }
}

/// Handle types for resize operations
enum ResizeHandle: Equatable {
  case topLeft, topRight, bottomLeft, bottomRight
  case top, bottom, left, right
  case lineStart, lineEnd
  case textCalloutTail
}

/// NSView subclass handling mouse events and drawing
final class DrawingCanvasNSView: NSView {
  private static let drawingCommitDragThreshold: CGFloat = 2

  var state: AnnotateState {
    didSet {
      guard oldValue !== state else { return }
      observeStateChanges()
      invalidateDrawing()
    }
  }

  var displayScale: CGFloat = 1.0
  var canvasBounds: CGRect = .zero
  private let shortcutManager = AnnotateShortcutManager.shared
  private var currentPath: [CGPoint] = []
  private var isDrawing = false
  private var dragStart: CGPoint?
  private var drawingStartDisplayPoint: CGPoint?
  private var drawingDragDistance: CGFloat = 0

  // Selection and manipulation state
  private var isDraggingAnnotation = false
  private var draggingAnnotationId: UUID? // Local tracking to avoid async race
  private var draggingAnnotationIds: Set<UUID> = []
  private var isResizingAnnotation = false
  private var resizingAnnotationId: UUID? // Local tracking to avoid async race
  private var activeResizeHandle: ResizeHandle?
  private var dragOffset: CGPoint = .zero
  private var originalBounds: CGRect = .zero
  private var originalBoundsByAnnotationId: [UUID: CGRect] = [:]
  private var isSelectingArea = false
  private var selectionAreaStart: CGPoint?
  private var selectionAreaCurrent: CGPoint?

  // Crop interaction state
  private var isCropDragging = false
  private var isCropResizing = false
  private var activeCropHandle: CropHandle?
  private var originalCropRect: CGRect = .zero

  private let handleSize: CGFloat = 8

  // Blur cache manager for performance optimization
  private let blurCacheManager = BlurCacheManager()
  private var lastSourceImageIdentifier: ObjectIdentifier?
  private var stateObserver: AnyCancellable?
  private var isDisplayInvalidationScheduled = false

  init(state: AnnotateState) {
    self.state = state
    super.init(frame: .zero)
    setupView()
    observeStateChanges()
    blurCacheManager.onRenderCompleted = { [weak self] _, imageBounds in
      self?.invalidateDisplay(forImageRect: imageBounds)
    }
  }

  @available(*, unavailable)
  required init?(coder _: NSCoder) {
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

  private func observeStateChanges() {
    stateObserver = state.objectWillChange.sink { [weak self] _ in
      self?.scheduleDisplayInvalidation()
    }
  }

  func invalidateDrawing() {
    needsDisplay = true
  }

  private func invalidateDisplay(forImageRect imageRect: CGRect) {
    let imagePadding = max(12, 24 / max(displayScale, 0.0001))
    let dirtyRect = imageToDisplay(imageRect.insetBy(dx: -imagePadding, dy: -imagePadding)).intersection(bounds)
    if dirtyRect.isNull || dirtyRect.isEmpty {
      needsDisplay = true
    } else {
      setNeedsDisplay(dirtyRect)
    }
  }

  private func scheduleDisplayInvalidation() {
    guard !isDisplayInvalidationScheduled else { return }
    isDisplayInvalidationScheduled = true

    DispatchQueue.main.async { [weak self] in
      guard let self else { return }
      isDisplayInvalidationScheduled = false
      invalidateDrawing()
    }
  }

  // MARK: - First Responder

  override var acceptsFirstResponder: Bool {
    true
  }

  override func keyDown(with event: NSEvent) {
    let shift = event.modifierFlags.contains(.shift)
    let nudgeAmount: CGFloat = shift ? 10 : 1

    switch event.keyCode {
    case 51, 117: // Delete, Forward Delete
      if state.hasSelectedAnnotations, state.editingTextAnnotationId == nil {
        Task { @MainActor in
          state.deleteSelectedAnnotation()
        }
        needsDisplay = true
      }

    case 53: // Escape
      // Cancel crop if active
      if state.isCropInteractionActive {
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
      if state.isCropInteractionActive {
        Task { @MainActor in
          state.confirmCropInteraction()
        }
        needsDisplay = true
        return
      }

    case 126: // Arrow Up
      if state.hasSelectedAnnotations, state.editingTextAnnotationId == nil {
        Task { @MainActor in
          state.nudgeSelectedAnnotation(dx: 0, dy: nudgeAmount)
        }
        needsDisplay = true
      }

    case 125: // Arrow Down
      if state.hasSelectedAnnotations, state.editingTextAnnotationId == nil {
        Task { @MainActor in
          state.nudgeSelectedAnnotation(dx: 0, dy: -nudgeAmount)
        }
        needsDisplay = true
      }

    case 123: // Arrow Left
      if state.hasSelectedAnnotations, state.editingTextAnnotationId == nil {
        Task { @MainActor in
          state.nudgeSelectedAnnotation(dx: -nudgeAmount, dy: 0)
        }
        needsDisplay = true
      }

    case 124: // Arrow Right
      if state.hasSelectedAnnotations, state.editingTextAnnotationId == nil {
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
          if matchedTool == .crop {
            state.beginCropInteraction()
          } else {
            // Commit any active text edit before switching
            if state.editingTextAnnotationId != nil {
              state.commitTextEditing()
            }
            // Deselect active annotation when switching tools
            state.deselectAnnotation()
            state.selectedTool = matchedTool
          }
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
      let expandedBounds = annotation.selectionBounds.insetBy(dx: -10, dy: -10)
      guard expandedBounds.contains(point) else { continue }

      // Precise hit test
      if annotation.containsPoint(point) {
        return annotation
      }
    }
    return nil
  }

  private func hitTestHandle(
    at point: CGPoint,
    for annotation: AnnotationItem,
    inDisplayCoordinates: Bool
  ) -> ResizeHandle? {
    for (handle, rect) in resizeHandleRects(for: annotation, inDisplayCoordinates: inDisplayCoordinates) {
      if rect.contains(point) {
        return handle
      }
    }
    return nil
  }

  private func resizeHandleRects(
    for annotation: AnnotationItem,
    inDisplayCoordinates: Bool
  ) -> [(ResizeHandle, CGRect)] {
    switch annotation.type {
    case .line(let start, let end):
      let startPoint = inDisplayCoordinates ? imageToDisplay(start) : start
      let endPoint = inDisplayCoordinates ? imageToDisplay(end) : end
      return [
        (.lineStart, handleRect(at: startPoint)),
        (.lineEnd, handleRect(at: endPoint)),
      ]

    case .text:
      let bounds = inDisplayCoordinates ? imageToDisplay(annotation.resizeBounds) : annotation.resizeBounds
      var handles: [(ResizeHandle, CGRect)] = [
        (.topLeft, handleRect(at: CGPoint(x: bounds.minX, y: bounds.maxY))),
        (.topRight, handleRect(at: CGPoint(x: bounds.maxX, y: bounds.maxY))),
        (.bottomLeft, handleRect(at: CGPoint(x: bounds.minX, y: bounds.minY))),
        (.bottomRight, handleRect(at: CGPoint(x: bounds.maxX, y: bounds.minY))),
      ]
      if annotation.properties.textPresentation == .callout,
         let tailTarget = annotation.properties.calloutTailTarget {
        let point = inDisplayCoordinates ? imageToDisplay(tailTarget) : tailTarget
        handles.append((.textCalloutTail, handleRect(at: point)))
      }
      return handles

    case .arrow(let geometry):
      // Figma-style endpoint editing: two draggable endpoints instead of a bounding box.
      let startPoint = inDisplayCoordinates ? imageToDisplay(geometry.start) : geometry.start
      let endPoint = inDisplayCoordinates ? imageToDisplay(geometry.end) : geometry.end
      return [
        (.lineStart, handleRect(at: startPoint)),
        (.lineEnd, handleRect(at: endPoint)),
      ]

    default:
      let bounds = inDisplayCoordinates ? imageToDisplay(annotation.resizeBounds) : annotation.resizeBounds
      return [
        (.topLeft, handleRect(at: CGPoint(x: bounds.minX, y: bounds.maxY))),
        (.topRight, handleRect(at: CGPoint(x: bounds.maxX, y: bounds.maxY))),
        (.bottomLeft, handleRect(at: CGPoint(x: bounds.minX, y: bounds.minY))),
        (.bottomRight, handleRect(at: CGPoint(x: bounds.maxX, y: bounds.minY))),
      ]
    }
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
      x: point.x / displayScale + effectiveCanvasBounds.minX,
      y: point.y / displayScale + effectiveCanvasBounds.minY
    )
  }

  /// Convert image point to display coordinates (for rendering)
  private func imageToDisplay(_ point: CGPoint) -> CGPoint {
    CGPoint(
      x: (point.x - effectiveCanvasBounds.minX) * displayScale,
      y: (point.y - effectiveCanvasBounds.minY) * displayScale
    )
  }

  /// Convert image rect to display coordinates
  private func imageToDisplay(_ rect: CGRect) -> CGRect {
    CGRect(
      x: (rect.origin.x - effectiveCanvasBounds.minX) * displayScale,
      y: (rect.origin.y - effectiveCanvasBounds.minY) * displayScale,
      width: rect.width * displayScale,
      height: rect.height * displayScale
    )
  }

  /// Convert display rect to image coordinates
  private func displayToImage(_ rect: CGRect) -> CGRect {
    guard displayScale > 0 else { return rect }
    return CGRect(
      x: rect.origin.x / displayScale + effectiveCanvasBounds.minX,
      y: rect.origin.y / displayScale + effectiveCanvasBounds.minY,
      width: rect.width / displayScale,
      height: rect.height / displayScale
    )
  }

  private var effectiveCanvasBounds: CGRect {
    guard canvasBounds.width > 0, canvasBounds.height > 0 else {
      return state.sourceImageBounds
    }
    return canvasBounds.standardized
  }

  /// Clamp point to the active drawing bounds. Applied expanded crops become drawable canvas.
  private func clampToCanvasBounds(_ point: CGPoint) -> CGPoint {
    let bounds = state.isCombineMode
      ? state.effectiveContentBounds.standardized
      : state.activeAnnotationBounds.standardized
    return CGPoint(
      x: max(bounds.minX, min(point.x, bounds.maxX)),
      y: max(bounds.minY, min(point.y, bounds.maxY))
    )
  }

  private func interactionPoint(from displayPoint: CGPoint) -> CGPoint {
    let rawImagePoint = displayToImage(displayPoint)
    guard state.selectedTool != .crop else { return rawImagePoint }
    return clampToCanvasBounds(rawImagePoint)
  }

  // MARK: - Mouse Events

  override func mouseDown(with event: NSEvent) {
    if state.isCombineMode {
      state.frozenCombineContentBounds = state.combineContentBounds
    }
    let displayPoint = convert(event.locationInWindow, from: nil)
    let imagePoint = interactionPoint(from: displayPoint)
    dragStart = imagePoint // Store in image coords

    // Handle double-click on text annotations to enter edit mode
    if event.clickCount == 2 {
      if let annotation = hitTestAnnotation(at: imagePoint),
         case .text = annotation.type {
        Task { @MainActor in
          state.selectedAnnotationId = annotation.id
          state.beginTextEditing(id: annotation.id)
        }
        needsDisplay = true
        return
      }
    }

    // Commit text editing when clicking elsewhere — just blur, don't create new
    if state.editingTextAnnotationId != nil {
      Task { @MainActor in
        state.commitTextEditing()
        state.selectedAnnotationId = nil
      }
      needsDisplay = true
      return
    }

    // Check if clicking on a selected annotation's handle (use display coords for handles)
    if let selectedId = state.selectedAnnotationId,
       let annotation = state.annotations.first(where: { $0.id == selectedId }),
       annotation.supportsResize,
       canResizeAnnotation(annotation) {
      if let handle = hitTestHandle(at: displayPoint, for: annotation, inDisplayCoordinates: true) {
        isResizingAnnotation = true
        resizingAnnotationId = selectedId
        activeResizeHandle = handle
        originalBounds = annotation.resizeBounds // Store in image coords
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
      if let annotation = hitTestAnnotation(at: imagePoint) {
        if !state.isAnnotationSelected(annotation.id) {
          _ = state.selectAnnotation(at: imagePoint)
          // Reflect clicked annotation's tool type in toolbar
          Task { @MainActor in
            state.selectedTool = annotation.type.toolType
          }
        }
        beginAnnotationDrag(anchor: annotation, at: imagePoint)
        return
      } else {
        beginAreaSelection(at: imagePoint)
        needsDisplay = true
        return
      }
    }

    // A combined image is a canvas surface while a markup tool is active.
    // Only the selection tool may claim its clicks for layer manipulation;
    // otherwise secondary images would block drawing on every image but the base.
    if state.selectedTool != .crop,
       let annotation = hitTestAnnotation(at: imagePoint),
       !Self.shouldPrioritizeCanvasMarkup(over: annotation, selectedTool: state.selectedTool) {
      // Set local tracking synchronously to avoid race condition with mouseDragged
      beginAnnotationDrag(anchor: annotation, at: imagePoint)
      // Update state asynchronously (for UI reflection)
      Task { @MainActor in
        state.selectedAnnotationId = annotation.id
        state.selectedTool = annotation.type.toolType
      }
      return
    }

    // Blank-canvas clicks should blur the active item while leaving the
    // current drawing tool active, matching toolbar reactivation semantics.
    state.deselectAnnotation()

    // Start drawing for other tools (in image coordinates)
    isDrawing = true
    drawingStartDisplayPoint = displayPoint
    drawingDragDistance = 0
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
      resetDrawingInteraction()
    default:
      break
    }
  }

  /// Secondary images are movable layers in selection mode, but behave like
  /// the base image when the user is adding a markup annotation.
  static func shouldPrioritizeCanvasMarkup(
    over annotation: AnnotationItem,
    selectedTool: AnnotationToolType
  ) -> Bool {
    guard selectedTool != .selection else { return false }
    if case .embeddedImage = annotation.type { return true }
    return false
  }

  private func beginAnnotationDrag(anchor annotation: AnnotationItem, at imagePoint: CGPoint) {
    if state.isCombineMode, state.combineMode == .autoStitch,
       case .embeddedImage = annotation.type {
      state.setSelectedAnnotationIds([annotation.id])
      needsDisplay = true
      return
    }

    let activeIds: Set<UUID> = if state.isAnnotationSelected(annotation.id), !state.selectedAnnotationIds.isEmpty {
      state.selectedAnnotationIds
    } else {
      [annotation.id]
    }

    isDraggingAnnotation = true
    draggingAnnotationId = annotation.id
    draggingAnnotationIds = activeIds
    let anchorBounds = annotation.resizeBounds
    dragOffset = CGPoint(
      x: imagePoint.x - anchorBounds.origin.x,
      y: imagePoint.y - anchorBounds.origin.y
    )
    originalBounds = anchorBounds
    originalBoundsByAnnotationId = Dictionary(
      uniqueKeysWithValues: state.annotations
        .filter { activeIds.contains($0.id) }
        .map { ($0.id, $0.resizeBounds) }
    )
    NSCursor.closedHand.set()
    needsDisplay = true
  }

  private func canResizeAnnotation(_ annotation: AnnotationItem) -> Bool {
    guard state.isCombineMode, state.combineMode == .autoStitch else { return true }
    if case .embeddedImage = annotation.type { return false }
    return true
  }

  private func beginAreaSelection(at imagePoint: CGPoint) {
    state.deselectAnnotation()
    isSelectingArea = true
    selectionAreaStart = imagePoint
    selectionAreaCurrent = imagePoint
    NSCursor.crosshair.set()
  }

  private func finishAreaSelection() {
    defer {
      isSelectingArea = false
      selectionAreaStart = nil
      selectionAreaCurrent = nil
    }

    guard let start = selectionAreaStart,
          let current = selectionAreaCurrent else {
      state.deselectAnnotation()
      return
    }

    let selectionRect = CGRect(
      x: min(start.x, current.x),
      y: min(start.y, current.y),
      width: abs(current.x - start.x),
      height: abs(current.y - start.y)
    )

    guard selectionRect.width >= 3 || selectionRect.height >= 3 else {
      state.deselectAnnotation()
      return
    }

    let selected = state.selectAnnotations(in: selectionRect)
    if selected.count == 1, let annotation = selected.first {
      state.selectedTool = annotation.type.toolType
    } else if selected.count > 1 {
      state.selectedTool = .selection
    }
  }

  override func mouseDragged(with event: NSEvent) {
    let displayPoint = convert(event.locationInWindow, from: nil)
    let imagePoint = interactionPoint(from: displayPoint)

    // Handle resizing (in image coordinates)
    if isResizingAnnotation, let handle = activeResizeHandle,
       let resizeId = resizingAnnotationId {
      Task { @MainActor in
        let isArrow: Bool = {
          if case .arrow = state.annotations.first(where: { $0.id == resizeId })?.type { return true }
          return false
        }()
        switch handle {
        case .lineStart:
          if isArrow {
            state.updateArrowEndpoint(id: resizeId, start: imagePoint)
          } else {
            state.updateLineEndpoint(id: resizeId, start: imagePoint)
          }
        case .lineEnd:
          if isArrow {
            state.updateArrowEndpoint(id: resizeId, end: imagePoint)
          } else {
            state.updateLineEndpoint(id: resizeId, end: imagePoint)
          }
        case .textCalloutTail:
          state.updateTextCalloutTail(id: resizeId, target: imagePoint)
        default:
          let isEmbeddedImage = state.annotations.first(where: { $0.id == resizeId }).map {
            if case .embeddedImage = $0.type { return true }
            return false
          } ?? false
          let proportional = event.modifierFlags.contains(.shift)
            || (state.isCombineMode && isEmbeddedImage)
          let newBounds = calculateResizedBounds(
            handle: handle,
            currentPoint: imagePoint,
            proportional: proportional
          )
          state.updateAnnotationBounds(id: resizeId, bounds: newBounds)
        }
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

    if isSelectingArea {
      selectionAreaCurrent = imagePoint
      needsDisplay = true
      return
    }

    // Handle dragging annotation (in image coordinates)
    if isDraggingAnnotation {
      let activeIds = draggingAnnotationIds.isEmpty
        ? Set(draggingAnnotationId.map { [$0] } ?? [])
        : draggingAnnotationIds
      guard let start = dragStart, !activeIds.isEmpty else { return }
      let dx = imagePoint.x - start.x
      let dy = imagePoint.y - start.y
      Task { @MainActor in
        for id in activeIds {
          guard let originalBounds = originalBoundsByAnnotationId[id] else { continue }
          let newBounds = CGRect(
            origin: CGPoint(
              x: originalBounds.origin.x + dx,
              y: originalBounds.origin.y + dy
            ),
            size: originalBounds.size
          )
          state.updateAnnotationBounds(id: id, bounds: newBounds)
        }

        if state.isCombineMode,
           state.combineMode == .freeCanvas,
           activeIds.count == 1,
           let draggedID = activeIds.first,
           let dragged = state.annotations.first(where: { $0.id == draggedID }),
           case .embeddedImage = dragged.type {
          let candidates = [state.sourceImageBounds] + state.annotations.compactMap { annotation -> CGRect? in
            guard annotation.id != draggedID, case .embeddedImage = annotation.type else { return nil }
            return annotation.bounds
          }
          if let snapped = CombineSnapping.resolve(
            draggedBounds: dragged.bounds,
            candidateBounds: candidates,
            gap: state.combineGap,
            tolerance: state.combineSnapTolerance
          ) {
            state.updateAnnotationBounds(id: draggedID, bounds: snapped)
          }
        }
      }
      needsDisplay = true
      return
    }

    // Handle drawing (in image coordinates)
    guard isDrawing else { return }

    if let startDisplayPoint = drawingStartDisplayPoint {
      let distance = hypot(
        displayPoint.x - startDisplayPoint.x,
        displayPoint.y - startDisplayPoint.y
      )
      drawingDragDistance = max(drawingDragDistance, distance)
    }

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
    if state.isCombineMode {
      state.frozenCombineContentBounds = nil
    }
    let displayPoint = convert(event.locationInWindow, from: nil)
    let imagePoint = interactionPoint(from: displayPoint)

    // Finish resizing
    if isResizingAnnotation {
      // Invalidate blur cache if resizing a blur annotation
      if let resizeId = resizingAnnotationId,
         let annotation = state.annotations.first(where: { $0.id == resizeId }),
         case .blur = annotation.type {
        blurCacheManager.invalidate(id: resizeId)
      }
      Task { @MainActor in
        state.saveState()
      }
      isResizingAnnotation = false
      resizingAnnotationId = nil
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

    if isSelectingArea {
      finishAreaSelection()
      updateCursor(for: event)
      needsDisplay = true
      return
    }

    // Finish dragging
    if isDraggingAnnotation {
      let activeIds = draggingAnnotationIds.isEmpty
        ? Set(draggingAnnotationId.map { [$0] } ?? [])
        : draggingAnnotationIds
      for id in activeIds {
        if let annotation = state.annotations.first(where: { $0.id == id }),
           case .blur = annotation.type {
          blurCacheManager.invalidate(id: id)
        }
      }
      Task { @MainActor in
        state.saveState()
      }
      isDraggingAnnotation = false
      draggingAnnotationId = nil
      draggingAnnotationIds = []
      originalBoundsByAnnotationId = [:]
      updateCursor(for: event)
      needsDisplay = true
      return
    }

    // Finish drawing (already in image coords)
    guard isDrawing, let start = dragStart else { return }

    // Capture path before clearing to avoid race condition
    let tool = state.selectedTool
    let pathToSave = currentPath

    if shouldCommitDrawing(tool: tool, start: start, end: imagePoint, path: pathToSave) {
      Task { @MainActor in
        createAnnotation(tool: tool, from: start, to: imagePoint, path: pathToSave)
      }
    }

    resetDrawingInteraction()
    needsDisplay = true
  }

  private func calculateResizedBounds(
    handle: ResizeHandle,
    currentPoint: CGPoint,
    proportional: Bool = false
  ) -> CGRect {
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
    case .lineStart, .lineEnd:
      break
    default:
      break
    }

    guard proportional, originalBounds.width > 0, originalBounds.height > 0 else {
      return newBounds
    }

    let aspectRatio = originalBounds.width / originalBounds.height
    if newBounds.width / max(newBounds.height, 1) > aspectRatio {
      newBounds.size.width = newBounds.height * aspectRatio
    } else {
      newBounds.size.height = newBounds.width / aspectRatio
    }

    switch handle {
    case .topLeft:
      newBounds.origin.x = originalBounds.maxX - newBounds.width
      newBounds.origin.y = originalBounds.minY
    case .topRight:
      newBounds.origin.x = originalBounds.minX
      newBounds.origin.y = originalBounds.minY
    case .bottomLeft:
      newBounds.origin.x = originalBounds.maxX - newBounds.width
      newBounds.origin.y = originalBounds.maxY - newBounds.height
    case .bottomRight:
      newBounds.origin.x = originalBounds.minX
      newBounds.origin.y = originalBounds.maxY - newBounds.height
    default:
      break
    }
    return newBounds.standardized
  }

  // MARK: - Annotation Creation

  private func shouldCommitDrawing(
    tool: AnnotationToolType,
    start: CGPoint,
    end: CGPoint,
    path: [CGPoint]
  ) -> Bool {
    guard tool.requiresDragToCreateAnnotation else { return true }
    return maxDrawingDistance(from: start, to: end, path: path) >= Self.drawingCommitDragThreshold
  }

  private func maxDrawingDistance(from start: CGPoint, to end: CGPoint, path: [CGPoint]) -> CGFloat {
    let points = path + [end]
    let scale = max(displayScale, 0.0001)
    let imageDistance = points.reduce(CGFloat.zero) { maxDistance, point in
      let distance = hypot(point.x - start.x, point.y - start.y) * scale
      return max(maxDistance, distance)
    }
    return max(drawingDragDistance, imageDistance)
  }

  private func resetDrawingInteraction() {
    isDrawing = false
    dragStart = nil
    drawingStartDisplayPoint = nil
    drawingDragDistance = 0
    currentPath = []
  }

  @MainActor
  private func createAnnotation(tool: AnnotationToolType, from start: CGPoint, to end: CGPoint, path: [CGPoint]) {
    let item = AnnotationFactory.createAnnotation(
      tool: tool,
      from: start,
      to: end,
      path: path,
      state: state
    )
    if let item {
      state.saveState()
      state.annotations.append(item)
      if case .highlight = item.type {
        state.deselectAnnotation()
      } else {
        state.selectedAnnotationId = item.id
      }
    }
  }

  private func createTextAnnotation(at point: CGPoint) {
    let properties = state.annotationCreationProperties(for: .text)
    let initialBounds = AnnotateTextLayout.bounds(
      text: "",
      font: AnnotateTextLayout.font(size: properties.fontSize, fontName: properties.fontName),
      origin: .zero,
      constrainedWidth: AnnotateTextLayout.minWidth,
      presentation: properties.textPresentation
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
    state.useAutomaticTextWidth(for: item.id)
    state.prepareTextCalloutTail(for: item.id)
    state.selectedAnnotationId = item.id
    state.beginTextEditing(id: item.id, recordsUndo: false) // Enter edit mode immediately
  }

  // MARK: - Drawing

  override func draw(_ dirtyRect: NSRect) {
    super.draw(dirtyRect)
    guard let context = NSGraphicsContext.current?.cgContext else { return }

    let effectiveSourceImage = state.effectiveSourceImage
    let currentImageIdentifier = effectiveSourceImage.map(ObjectIdentifier.init)
    if currentImageIdentifier != lastSourceImageIdentifier {
      blurCacheManager.clearAll()
      lastSourceImageIdentifier = currentImageIdentifier
    }

    // Apply scale transform for rendering
    context.saveGState()
    context.scaleBy(x: displayScale, y: displayScale)
    context.translateBy(x: -effectiveCanvasBounds.minX, y: -effectiveCanvasBounds.minY)

    // Draw existing annotations (at image coordinates - transform handles scaling)
    let renderer = AnnotationRenderer(
      context: context,
      editingTextId: state.editingTextAnnotationId,
      sourceImage: effectiveSourceImage,
      blurCacheManager: blurCacheManager,
      interactiveBlurAnnotationIds: activeInteractiveBlurAnnotationIds(),
      interactiveEmbeddedImageAnnotationId: activeInteractiveEmbeddedImageAnnotationId(),
      embeddedImageProvider: { [state] assetId in
        state.embeddedImage(for: assetId)
      },
      embeddedCGImageProvider: { [state] assetId in
        state.embeddedCGImage(for: assetId)
      }
    )

    // Unified Spotlight overlay pass (draws overlay below other annotations, above base image).
    // Opacity is sourced from each item's own properties so slider changes reflect immediately.
    let spotlightCreationProps = state.annotationCreationProperties(for: .spotlight)
    let spotlightRegions = state.annotations.compactMap { a -> SpotlightRegion? in
      guard case .spotlight = a.type else { return nil }
      return SpotlightRegion(
        rect: a.bounds,
        cornerRadius: a.properties.cornerRadius,
        opacity: a.properties.spotlightOpacity
      )
    }
    let spotlightPreview: SpotlightRegion? = (isDrawing && state.selectedTool == .spotlight)
      ? dragStart.flatMap { s in
        currentPath.last.map {
          SpotlightRegion(
            rect: CGRect(x: min(s.x, $0.x), y: min(s.y, $0.y), width: abs($0.x - s.x), height: abs($0.y - s.y)),
            cornerRadius: spotlightCreationProps.cornerRadius,
            opacity: spotlightCreationProps.spotlightOpacity
          )
        }
      }
      : nil
    SpotlightCompositor.drawOverlay(
      regions: spotlightRegions,
      previewRegion: spotlightPreview,
      canvasRect: effectiveCanvasBounds,
      in: context
    )

    for annotation in state.annotations {
      // Freeform strokes show selection as a soft glow painted *beneath* the body,
      // so the highlight frames the ink without a line or box crossing over it.
      if state.isAnnotationSelected(annotation.id) {
        drawSelectionUnderlay(for: annotation, in: context)
      }

      renderer.draw(annotation)

      // Draw selection affordance if selected. Single selections can also show resize handles.
      if state.isAnnotationSelected(annotation.id) {
        drawSelectionAffordance(
          for: annotation,
          in: context,
          showsHandles: state.selectedAnnotationIds.count == 1 && annotation.supportsResize
        )
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
          blurType: state.blurType,
          controlValue: state.annotationCreationProperties(for: .blur).strokeWidth
        )
      } else if state.selectedTool == .spotlight {
        // Spotlight preview is handled in the unified overlay pass above.
      } else {
        let previewProperties = state.annotationCreationProperties(for: state.selectedTool)
        renderer.drawCurrentStroke(
          tool: state.selectedTool,
          start: start,
          currentPath: currentPath,
          strokeColor: previewProperties.strokeColor,
          strokeWidth: previewProperties.strokeWidth,
          fillColor: previewProperties.fillColor,
          arrowStyle: state.arrowStyle,
          arrowType: state.arrowType,
          arrowBendDirection: state.arrowBendDirection,
          arrowStartHead: state.arrowStartHead,
          arrowEndHead: state.arrowEndHead,
          rectangleCornerRadius: previewProperties.cornerRadius,
          watermarkText: state.watermarkText,
          watermarkStyle: previewProperties.watermarkStyle,
          watermarkOpacity: previewProperties.opacity,
          watermarkRotationDegrees: previewProperties.rotationDegrees,
          watermarkFontSize: previewProperties.fontSize
        )
      }
    }

    drawAreaSelectionPreview(in: context)

    context.restoreGState()
  }

  private func activeInteractiveBlurAnnotationIds() -> Set<UUID> {
    let candidateIds: Set<UUID> = if isResizingAnnotation {
      Set(resizingAnnotationId.map { [$0] } ?? [])
    } else if isDraggingAnnotation {
      draggingAnnotationIds.isEmpty
        ? Set(draggingAnnotationId.map { [$0] } ?? [])
        : draggingAnnotationIds
    } else {
      []
    }

    return Set(candidateIds.filter { id in
      guard let annotation = state.annotations.first(where: { $0.id == id }),
            case .blur = annotation.type else { return false }
      return true
    })
  }

  private func activeInteractiveEmbeddedImageAnnotationId() -> UUID? {
    let candidateId: UUID? = if isResizingAnnotation {
      resizingAnnotationId
    } else if isDraggingAnnotation {
      draggingAnnotationId
    } else {
      nil
    }

    guard let id = candidateId,
          let annotation = state.annotations.first(where: { $0.id == id }),
          case .embeddedImage = annotation.type else {
      return nil
    }
    return id
  }

  private func drawSelectionAffordance(for annotation: AnnotationItem, in context: CGContext, showsHandles: Bool) {
    switch annotation.type {
    case .line, .arrow:
      // Endpoint-editable items: a single selection is indicated purely by its
      // draggable endpoint grips (drawn below), so nothing is painted over the
      // body. Multi-selection falls back to a bounding box so the item still
      // reads as part of the group.
      if !showsHandles {
        drawSelectionBounds(annotation.selectionDecorationBounds, in: context)
      }
    case .path, .highlight:
      // Freeform strokes are indicated by the glow underlay only (drawn beneath
      // the body); nothing is painted over or boxed around the stroke here.
      break
    default:
      // Every other type reads as selected via a bounding box that frames the
      // annotation instead of overlapping its body.
      drawSelectionBounds(annotation.selectionDecorationBounds, in: context)
    }

    guard showsHandles else { return }
    drawResizeHandles(for: annotation, in: context)
  }

  private func drawSelectionBounds(_ bounds: CGRect, in context: CGContext) {
    context.setStrokeColor(NSColor.systemBlue.cgColor)
    context.setLineWidth(1)
    context.setLineDash(phase: 0, lengths: [4, 4])
    context.stroke(bounds)
    context.setLineDash(phase: 0, lengths: [])
  }

  /// Selection underlay for freeform strokes: a soft accent-colored glow painted
  /// beneath the annotation body so the body sits on top untouched. The glow is
  /// wider than the ink, so it reads as a halo hugging the stroke's silhouette
  /// rather than a line through it or a box around it.
  private func drawSelectionUnderlay(for annotation: AnnotationItem, in context: CGContext) {
    switch annotation.type {
    case .path(let points):
      drawSelectionGlow(points: points, bodyWidth: annotation.properties.strokeWidth, in: context)
    case .highlight(let points):
      // Highlighter renders at 3× stroke width; match it so the halo hugs the bar.
      drawSelectionGlow(points: points, bodyWidth: annotation.properties.strokeWidth * 3, in: context)
    default:
      break
    }
  }

  private func drawSelectionGlow(points: [CGPoint], bodyWidth: CGFloat, in context: CGContext) {
    guard points.count > 1 else { return }

    // Constant ~4pt halo ring in screen space regardless of zoom.
    let haloRing = 4 / max(displayScale, 0.0001)

    context.saveGState()
    context.setLineCap(.round)
    context.setLineJoin(.round)
    context.setStrokeColor(NSColor.systemBlue.withAlphaComponent(0.85).cgColor)
    context.setLineWidth(bodyWidth + haloRing * 2)
    strokePolyline(points, in: context)
    context.restoreGState()
  }

  private func strokePolyline(_ points: [CGPoint], in context: CGContext) {
    guard let first = points.first else { return }

    context.beginPath()
    context.move(to: first)
    for point in points.dropFirst() {
      context.addLine(to: point)
    }
    context.strokePath()
  }

  private func drawResizeHandles(for annotation: AnnotationItem, in context: CGContext) {
    context.setFillColor(NSColor.white.cgColor)
    context.setStrokeColor(NSColor.systemBlue.cgColor)
    context.setLineWidth(1)

    for (handle, rect) in resizeHandleRects(for: annotation, inDisplayCoordinates: false) {
      switch handle {
      case .lineStart, .lineEnd:
        // Circular endpoint grips for line/arrow endpoint editing.
        context.fillEllipse(in: rect)
        context.strokeEllipse(in: rect)
      default:
        context.fill(rect)
        context.stroke(rect)
      }
    }
  }

  private func drawAreaSelectionPreview(in context: CGContext) {
    guard isSelectingArea,
          let start = selectionAreaStart,
          let current = selectionAreaCurrent else { return }

    let rect = CGRect(
      x: min(start.x, current.x),
      y: min(start.y, current.y),
      width: abs(current.x - start.x),
      height: abs(current.y - start.y)
    ).standardized
    guard rect.width > 0 || rect.height > 0 else { return }

    context.setFillColor(NSColor.systemBlue.withAlphaComponent(0.12).cgColor)
    context.fill(rect)
    context.setStrokeColor(NSColor.systemBlue.cgColor)
    context.setLineWidth(1)
    context.setLineDash(phase: 0, lengths: [5, 3])
    context.stroke(rect)
    context.setLineDash(phase: 0, lengths: [])
  }

  // MARK: - Cursor Management

  override func mouseMoved(with event: NSEvent) {
    updateCursor(for: event)
  }

  private func updateCursor(for event: NSEvent) {
    let displayPoint = convert(event.locationInWindow, from: nil)
    let imagePoint = displayToImage(displayPoint)

    // Check resize handles first for single selection.
    if state.selectedAnnotationIds.count == 1,
       let selectedId = state.selectedAnnotationIds.first,
       let annotation = state.annotations.first(where: { $0.id == selectedId }) {
      if annotation.supportsResize,
         let handle = hitTestHandle(at: displayPoint, for: annotation, inDisplayCoordinates: true) {
        setCursorForHandle(handle)
        return
      }

      // Check if over selected annotation body
      if annotation.containsPoint(imagePoint) {
        NSCursor.openHand.set()
        return
      }
    }

    if state.selectedAnnotations.contains(where: { $0.containsPoint(imagePoint) }) {
      NSCursor.openHand.set()
      return
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
    case .topLeft, .bottomRight, .lineStart, .lineEnd, .textCalloutTail:
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
    state.collapseSidebarForCropInteraction()

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

    let minSize: CGFloat = 20

    // Determine target aspect ratio
    let aspectRatio: CGFloat? = if shiftHeld {
      // Lock to current aspect ratio when Shift is held
      originalCropRect.width / originalCropRect.height
    } else if state.cropAspectRatio != .free {
      state.cropAspectRatio.effectiveRatio(isPortrait: state.isCropPortraitOrientation)
    } else {
      nil
    }

    switch handle {
    case .topLeft:
      let maxX = originalCropRect.maxX - minSize
      let minY = originalCropRect.minY + minSize
      newRect.origin.x = min(currentPoint.x, maxX)
      newRect.size.width = originalCropRect.maxX - newRect.origin.x
      newRect.size.height = max(currentPoint.y, minY) - originalCropRect.minY
    case .top:
      let minY = originalCropRect.minY + minSize
      newRect.size.height = max(currentPoint.y, minY) - originalCropRect.minY
    case .topRight:
      let minX = originalCropRect.minX + minSize
      let minY = originalCropRect.minY + minSize
      newRect.size.width = max(currentPoint.x, minX) - originalCropRect.minX
      newRect.size.height = max(currentPoint.y, minY) - originalCropRect.minY
    case .left:
      let maxX = originalCropRect.maxX - minSize
      newRect.origin.x = min(currentPoint.x, maxX)
      newRect.size.width = originalCropRect.maxX - newRect.origin.x
    case .right:
      let minX = originalCropRect.minX + minSize
      newRect.size.width = max(currentPoint.x, minX) - originalCropRect.minX
    case .bottomLeft:
      let maxX = originalCropRect.maxX - minSize
      let maxY = originalCropRect.maxY - minSize
      newRect.origin.x = min(currentPoint.x, maxX)
      newRect.origin.y = min(currentPoint.y, maxY)
      newRect.size.width = originalCropRect.maxX - newRect.origin.x
      newRect.size.height = originalCropRect.maxY - newRect.origin.y
    case .bottom:
      let maxY = originalCropRect.maxY - minSize
      newRect.origin.y = min(currentPoint.y, maxY)
      newRect.size.height = originalCropRect.maxY - newRect.origin.y
    case .bottomRight:
      let minX = originalCropRect.minX + minSize
      let maxY = originalCropRect.maxY - minSize
      newRect.origin.y = min(currentPoint.y, maxY)
      newRect.size.width = max(currentPoint.x, minX) - originalCropRect.minX
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

    case .top, .bottom:
      // Height is the primary dimension, calculate width from height
      let newWidth = rect.height * ratio
      let widthDiff = newWidth - rect.width
      // Center the width adjustment
      result.origin.x = rect.origin.x - widthDiff / 2
      result.size.width = newWidth

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
