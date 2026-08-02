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

/// Transparent drawing layer of the annotate canvas. Renders via `drawBody`
/// only when invalidated; CoreAnimation composites the existing backing store
/// otherwise. All mouse/key events fall through to the container view.
final class CanvasLayerView: NSView {
  var drawBody: ((NSRect) -> Void)?

  init() {
    super.init(frame: .zero)
    wantsLayer = true
    layer?.backgroundColor = NSColor.clear.cgColor
  }

  @available(*, unavailable)
  required init?(coder _: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override func draw(_ dirtyRect: NSRect) {
    super.draw(dirtyRect)
    drawBody?(dirtyRect)
  }

  override func hitTest(_: NSPoint) -> NSView? {
    nil
  }

  override var acceptsFirstResponder: Bool {
    false
  }
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

  // Gesture-local manipulation state. Drag/resize gestures mutate these plain
  // copies instead of @Published state, so SwiftUI is not invalidated per mouse
  // event; final values are committed to state once on mouseUp.
  private var gestureOriginalItems: [UUID: AnnotationItem] = [:]
  private var gestureLocalItems: [UUID: AnnotationItem] = [:]
  private var gestureLastResizeBounds: CGRect?
  private var gestureLastPoint: CGPoint?
  private var gestureDidMutate = false

  // Layered canvas composition: stacked child views let CoreAnimation composite
  // unchanged content straight from their backing stores (a layer-backed view
  // only redraws when invalidated), so per-frame cost stays flat without any
  // manual bitmap or color-space management — rendering always goes through the
  // standard AppKit pipeline in the window's own color space.
  // Order (back → front): overlay → static-below → dragged → static-above → preview.
  private let overlayLayerView = CanvasLayerView()
  private let staticBelowLayerView = CanvasLayerView()
  private let draggedLayerView = CanvasLayerView()
  private let staticAboveLayerView = CanvasLayerView()
  private let previewLayerView = CanvasLayerView()

  private var layerViews: [CanvasLayerView] {
    [overlayLayerView, staticBelowLayerView, draggedLayerView, staticAboveLayerView, previewLayerView]
  }

  /// Views redrawn per frame while a gesture runs (cheap content only).
  private var liveLayerViews: [CanvasLayerView] {
    [overlayLayerView, draggedLayerView, previewLayerView]
  }

  private var stateObservers = Set<AnyCancellable>()

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

  override func setFrameSize(_ newSize: NSSize) {
    super.setFrameSize(newSize)
    // Resized layers keep scaled stale content until redrawn (.onSetNeedsDisplay).
    invalidateDrawing()
  }

  private func setupView() {
    wantsLayer = true
    layer?.backgroundColor = NSColor.clear.cgColor

    for layerView in layerViews {
      layerView.autoresizingMask = [.width, .height]
      layerView.frame = bounds
      addSubview(layerView)
    }
    overlayLayerView.drawBody = { [weak self] dirtyRect in self?.drawSpotlightOverlay(dirtyRect: dirtyRect) }
    staticBelowLayerView.drawBody = { [weak self] dirtyRect in self?.drawStaticBelow(dirtyRect: dirtyRect) }
    draggedLayerView.drawBody = { [weak self] dirtyRect in self?.drawDraggedItems(dirtyRect: dirtyRect) }
    staticAboveLayerView.drawBody = { [weak self] dirtyRect in self?.drawStaticAbove(dirtyRect: dirtyRect) }
    previewLayerView.drawBody = { [weak self] dirtyRect in self?.drawGesturePreview(dirtyRect: dirtyRect) }

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
    stateObservers.removeAll()
    // Content-driving publishers: redraw every layer.
    state.$annotations
      .sink { [weak self] _ in self?.scheduleAnnotationsInvalidation() }
      .store(in: &stateObservers)
    state.$selectedAnnotationIds
      .sink { [weak self] _ in self?.invalidateDrawing() }
      .store(in: &stateObservers)
    state.$selectedAnnotationId
      .sink { [weak self] _ in self?.invalidateDrawing() }
      .store(in: &stateObservers)
    state.$editingTextAnnotationId
      .sink { [weak self] _ in self?.invalidateDrawing() }
      .store(in: &stateObservers)
    state.$embeddedImageAssets
      .sink { [weak self] _ in self?.invalidateDrawing() }
      .store(in: &stateObservers)
    state.$sourceImage
      .sink { [weak self] _ in self?.invalidateDrawing() }
      .store(in: &stateObservers)
    state.$cutoutImage
      .sink { [weak self] _ in self?.invalidateDrawing() }
      .store(in: &stateObservers)

    // Everything else (crop flags, spotlight opacity, zoom/pan, ...) only needs
    // the cheap live layers; static annotation content is unaffected.
    state.objectWillChange
      .sink { [weak self] _ in self?.scheduleLiveLayerInvalidation() }
      .store(in: &stateObservers)
  }

  /// Redraw all layers (content changed).
  func invalidateDrawing() {
    for layerView in layerViews {
      layerView.needsDisplay = true
    }
  }

  /// Redraw only the per-frame layers (overlay/dragged/preview) — the static
  /// layers keep compositing their existing backing store.
  private func invalidateLiveLayers() {
    // When the manipulated items can't be split into the dragged layer
    // (multi-select drag, or a selected item outside the gesture), their
    // gesture-local copies live in the static layers, so everything must
    // redraw per frame for the gesture to be visible.
    if isDraggingAnnotation || isResizingAnnotation, !usesDragLayerSplit {
      invalidateDrawing()
      return
    }
    for layerView in liveLayerViews {
      layerView.needsDisplay = true
    }
  }

  private func invalidateDisplay(forImageRect imageRect: CGRect) {
    let imagePadding = max(12, 24 / max(displayScale, 0.0001))
    let dirtyRect = imageToDisplay(imageRect.insetBy(dx: -imagePadding, dy: -imagePadding)).intersection(bounds)
    for layerView in layerViews {
      if dirtyRect.isNull || dirtyRect.isEmpty {
        layerView.needsDisplay = true
      } else {
        layerView.setNeedsDisplay(dirtyRect)
      }
    }
  }

  private var isLiveInvalidationScheduled = false

  private func scheduleLiveLayerInvalidation() {
    guard !isLiveInvalidationScheduled else { return }
    isLiveInvalidationScheduled = true

    DispatchQueue.main.async { [weak self] in
      guard let self else { return }
      isLiveInvalidationScheduled = false
      invalidateLiveLayers()
    }
  }

  private var isAnnotationsInvalidationScheduled = false

  /// Coalesce bursts of annotation mutations (e.g. property slider drags) into
  /// one redraw per runloop. Property-only edits redraw just the edited
  /// annotations' dirty rects instead of every layer in full bounds (issue #335).
  private func scheduleAnnotationsInvalidation() {
    guard !isAnnotationsInvalidationScheduled else { return }
    isAnnotationsInvalidationScheduled = true

    DispatchQueue.main.async { [weak self] in
      guard let self else { return }
      isAnnotationsInvalidationScheduled = false
      let pending = state.consumePendingCanvasInvalidation()
      if pending.needsFullRedraw || pending.rects.isEmpty {
        invalidateDrawing()
      } else {
        for rect in pending.rects {
          invalidateDisplay(forImageRect: rect)
        }
      }
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
        invalidateDrawing()
      }

    case 53: // Escape
      // Cancel crop if active
      if state.isCropInteractionActive {
        Task { @MainActor in
          state.cancelCrop()
        }
        invalidateDrawing()
        return
      }
      Task { @MainActor in
        state.deselectAnnotation()
      }
      invalidateDrawing()

    case 36: // Enter - confirm crop
      if state.isCropInteractionActive {
        Task { @MainActor in
          state.confirmCropInteraction()
        }
        invalidateDrawing()
        return
      }

    case 126: // Arrow Up
      if state.hasSelectedAnnotations, state.editingTextAnnotationId == nil {
        Task { @MainActor in
          state.nudgeSelectedAnnotation(dx: 0, dy: nudgeAmount)
        }
        invalidateDrawing()
      }

    case 125: // Arrow Down
      if state.hasSelectedAnnotations, state.editingTextAnnotationId == nil {
        Task { @MainActor in
          state.nudgeSelectedAnnotation(dx: 0, dy: -nudgeAmount)
        }
        invalidateDrawing()
      }

    case 123: // Arrow Left
      if state.hasSelectedAnnotations, state.editingTextAnnotationId == nil {
        Task { @MainActor in
          state.nudgeSelectedAnnotation(dx: -nudgeAmount, dy: 0)
        }
        invalidateDrawing()
      }

    case 124: // Arrow Right
      if state.hasSelectedAnnotations, state.editingTextAnnotationId == nil {
        Task { @MainActor in
          state.nudgeSelectedAnnotation(dx: nudgeAmount, dy: 0)
        }
        invalidateDrawing()
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
        invalidateDrawing()
      }

    default:
      // Crop mode owns `A` (auto-crop to content) even if the user bound it to
      // a tool — same precedence as Enter/Esc while cropping.
      if state.isCropInteractionActive, !event.modifierFlags.contains(.command),
         event.characters?.lowercased().first == "a" {
        Task { @MainActor in
          await state.autoCropToContent()
        }
        invalidateDrawing()
        return
      }
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
            state.activateTool(matchedTool)
          }
        }
        invalidateDrawing()
      } else {
        super.keyDown(with: event)
      }
    }
  }

  // MARK: - Hit Testing

  /// Find annotation at given point (in image coordinates), topmost first
  private func hitTestAnnotation(at point: CGPoint) -> AnnotationItem? {
    for annotation in state.annotations.renderOrdered.reversed() {
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
        invalidateDrawing()
        return
      }
    }

    // Commit text editing when clicking elsewhere — just blur, don't create new
    if state.editingTextAnnotationId != nil {
      Task { @MainActor in
        state.commitTextEditing()
        state.selectedAnnotationId = nil
      }
      invalidateDrawing()
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
        gestureOriginalItems = [selectedId: annotation]
        gestureLocalItems = [selectedId: annotation]
        gestureLastResizeBounds = nil
        gestureLastPoint = nil
        gestureDidMutate = false
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
        invalidateDrawing()
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
      invalidateDrawing()
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
    let draggedItems = state.annotations.filter { activeIds.contains($0.id) }
    originalBoundsByAnnotationId = Dictionary(
      uniqueKeysWithValues: draggedItems.map { ($0.id, $0.resizeBounds) }
    )
    gestureOriginalItems = Dictionary(uniqueKeysWithValues: draggedItems.map { ($0.id, $0) })
    gestureLocalItems = gestureOriginalItems
    gestureLastResizeBounds = nil
    gestureLastPoint = nil
    gestureDidMutate = false
    NSCursor.closedHand.set()
    invalidateDrawing()
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

    // Handle resizing (in image coordinates). Mutates only the gesture-local
    // copy; the final geometry commits to state once on mouseUp.
    if isResizingAnnotation, let handle = activeResizeHandle,
       let resizeId = resizingAnnotationId {
      applyGestureResize(handle: handle, resizeId: resizeId, imagePoint: imagePoint, event: event)
      invalidateLiveLayers()
      return
    }

    // Handle crop resizing
    if isCropResizing, let handle = activeCropHandle {
      let shiftHeld = event.modifierFlags.contains(.shift)
      let commandHeld = event.modifierFlags.contains(.command)
      handleCropResize(handle: handle, currentPoint: imagePoint, shiftHeld: shiftHeld, commandHeld: commandHeld)
      Task { @MainActor in
        state.isCropResizing = true
        state.isCropShiftLocked = shiftHeld
      }
      invalidateLiveLayers()
      return
    }

    // Handle crop dragging
    if isCropDragging {
      handleCropDrag(to: imagePoint)
      invalidateLiveLayers()
      return
    }

    if isSelectingArea {
      selectionAreaCurrent = imagePoint
      invalidateLiveLayers()
      return
    }

    // Handle dragging annotation (in image coordinates). Mutates only
    // gesture-local copies; final bounds commit to state once on mouseUp.
    if isDraggingAnnotation {
      let activeIds = draggingAnnotationIds.isEmpty
        ? Set(draggingAnnotationId.map { [$0] } ?? [])
        : draggingAnnotationIds
      guard let start = dragStart, !activeIds.isEmpty else { return }
      let dx = imagePoint.x - start.x
      let dy = imagePoint.y - start.y

      for id in activeIds {
        guard let originalBounds = originalBoundsByAnnotationId[id],
              let original = gestureOriginalItems[id] else { continue }
        let newBounds = CGRect(
          origin: CGPoint(
            x: originalBounds.origin.x + dx,
            y: originalBounds.origin.y + dy
          ),
          size: originalBounds.size
        )
        gestureLocalItems[id] = original.applyingResizeBounds(newBounds)
        gestureDidMutate = true
      }

      // Combine free-canvas snapping resolves against the gesture-local copy
      // so the gesture stays state-free until mouseUp commits.
      if state.isCombineMode,
         state.combineMode == .freeCanvas,
         activeIds.count == 1,
         let draggedID = activeIds.first,
         let dragged = gestureLocalItems[draggedID],
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
          gestureLocalItems[draggedID] = dragged.applyingResizeBounds(snapped)
        }
      }
      invalidateLiveLayers()
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
      invalidateLiveLayers()
    default:
      guard let dragStart else {
        currentPath = [imagePoint]
        invalidateLiveLayers()
        return
      }
      let constrainedEndPoint = AnnotationDragConstraint.constrainedEndPoint(
        tool: state.selectedTool,
        arrowStyle: state.arrowStyle,
        start: dragStart,
        end: imagePoint,
        shiftHeld: event.modifierFlags.contains(.shift)
      )
      currentPath = [constrainedEndPoint]
      invalidateLiveLayers()
    }
  }

  /// Applies a resize gesture to the gesture-local copy only. Mirrors the
  /// state update methods (`updateArrowEndpoint`, `updateLineEndpoint`,
  /// `updateTextCalloutTail`, `updateAnnotationBounds`) so the commit on
  /// mouseUp produces the exact same final geometry.
  private func applyGestureResize(handle: ResizeHandle, resizeId: UUID, imagePoint: CGPoint, event: NSEvent) {
    guard let original = gestureOriginalItems[resizeId] else { return }
    gestureLastPoint = imagePoint
    gestureDidMutate = true

    switch handle {
    case .lineStart, .lineEnd:
      var item = original
      let isStart = handle == .lineStart
      switch item.type {
      case .arrow(let geometry):
        let updated = ArrowGeometry(
          start: isStart ? imagePoint : geometry.start,
          end: isStart ? geometry.end : imagePoint,
          style: geometry.style,
          arrowType: geometry.arrowType,
          startHead: geometry.startHead,
          endHead: geometry.endHead
        )
        item.type = .arrow(updated)
        item.bounds = updated.bounds()
      case .line(let start, let end):
        let updatedStart = isStart ? imagePoint : start
        let updatedEnd = isStart ? end : imagePoint
        item.type = .line(start: updatedStart, end: updatedEnd)
        item.bounds = CGRect(
          x: min(updatedStart.x, updatedEnd.x),
          y: min(updatedStart.y, updatedEnd.y),
          width: abs(updatedEnd.x - updatedStart.x),
          height: abs(updatedEnd.y - updatedStart.y)
        ).standardized
      default:
        return
      }
      gestureLocalItems[resizeId] = item

    case .textCalloutTail:
      var item = original
      guard case .text = item.type,
            item.properties.textPresentation == .callout else { return }
      item.properties.calloutTailTarget = TextBubbleGeometry.resolvedTailTarget(
        in: item.bounds,
        requestedTarget: imagePoint,
        fontSize: item.properties.fontSize
      )
      gestureLocalItems[resizeId] = item

    default:
      let isEmbeddedImage: Bool = {
        if case .embeddedImage = original.type { return true }
        return false
      }()
      let proportional = event.modifierFlags.contains(.shift)
        || (state.isCombineMode && isEmbeddedImage)
      let newBounds = calculateResizedBounds(
        handle: handle,
        currentPoint: imagePoint,
        proportional: proportional
      )
      gestureLastResizeBounds = newBounds
      gestureLocalItems[resizeId] = original.applyingResizeBounds(newBounds)
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
      // Commit the gesture-local result synchronously so the very next draw
      // shows the new geometry — a deferred Task would paint one stale frame
      // at the old bounds first (visible as old/new flicker on drop).
      if let resizeId = resizingAnnotationId, let handle = activeResizeHandle {
        let isArrow: Bool = {
          guard let item = gestureLocalItems[resizeId] ?? gestureOriginalItems[resizeId] else { return false }
          if case .arrow = item.type { return true }
          return false
        }()
        switch handle {
        case .lineStart:
          if let lastPoint = gestureLastPoint {
            if isArrow {
              state.updateArrowEndpoint(id: resizeId, start: lastPoint)
            } else {
              state.updateLineEndpoint(id: resizeId, start: lastPoint)
            }
          }
        case .lineEnd:
          if let lastPoint = gestureLastPoint {
            if isArrow {
              state.updateArrowEndpoint(id: resizeId, end: lastPoint)
            } else {
              state.updateLineEndpoint(id: resizeId, end: lastPoint)
            }
          }
        case .textCalloutTail:
          if let lastPoint = gestureLastPoint {
            state.updateTextCalloutTail(id: resizeId, target: lastPoint)
          }
        default:
          if let lastBounds = gestureLastResizeBounds {
            state.updateAnnotationBounds(id: resizeId, bounds: lastBounds)
          }
        }
      }
      state.saveState()
      isResizingAnnotation = false
      resizingAnnotationId = nil
      activeResizeHandle = nil
      clearGestureState()
      invalidateDrawing()
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
      invalidateDrawing()
      return
    }

    if isSelectingArea {
      finishAreaSelection()
      clearGestureState()
      updateCursor(for: event)
      invalidateDrawing()
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
      // Commit gesture-local bounds once, synchronously, so the next draw is
      // already at the final position (deferred commit caused old/new flicker).
      if gestureDidMutate {
        for id in activeIds {
          guard let local = gestureLocalItems[id] else { continue }
          state.updateAnnotationBounds(id: id, bounds: local.resizeBounds)
        }
      }
      state.saveState()
      isDraggingAnnotation = false
      draggingAnnotationId = nil
      draggingAnnotationIds = []
      originalBoundsByAnnotationId = [:]
      clearGestureState()
      updateCursor(for: event)
      invalidateDrawing()
      return
    }

    // Finish drawing (already in image coords)
    guard isDrawing, let start = dragStart else { return }

    // Capture path before clearing to avoid race condition
    let tool = state.selectedTool
    let pathToSave = currentPath
    let endPoint: CGPoint
    switch tool {
    case .pencil, .highlighter:
      endPoint = imagePoint
    default:
      endPoint = pathToSave.last ?? imagePoint
    }

    if shouldCommitDrawing(tool: tool, start: start, end: endPoint, path: pathToSave) {
      // Commit synchronously: deferring to a Task lets a frame render where the
      // stroke preview is already gone but the annotation is not yet appended,
      // which reads as a flicker on completion.
      createAnnotation(tool: tool, from: start, to: endPoint, path: pathToSave)
    }

    resetDrawingInteraction()
    invalidateDrawing()
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
    clearGestureState()
  }

  /// Drops gesture-local copies. Called when any gesture ends so the next
  /// gesture starts from pristine state.
  private func clearGestureState() {
    gestureOriginalItems = [:]
    gestureLocalItems = [:]
    gestureLastResizeBounds = nil
    gestureLastPoint = nil
    gestureDidMutate = false
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

  /// Current items for display: gesture-local copies shadow state items while
  /// a drag/resize is active.
  private func currentDisplayItems() -> [AnnotationItem] {
    gestureLocalItems.isEmpty
      ? state.annotations
      : state.annotations.map { gestureLocalItems[$0.id] ?? $0 }
  }

  /// Ids of annotations pulled out of the static layers because they are being
  /// manipulated. Empty unless exactly one item is dragged/resized.
  private var gestureExcludedIds: Set<UUID> {
    if isResizingAnnotation {
      return resizingAnnotationId.map { [$0] } ?? []
    }
    if isDraggingAnnotation {
      let ids = draggingAnnotationIds.isEmpty
        ? Set(draggingAnnotationId.map { [$0] } ?? [])
        : draggingAnnotationIds
      // Exact z-order is only guaranteed for a single dragged item; multi-item
      // drags keep everything in the static layer.
      return ids.count == 1 ? ids : []
    }
    return []
  }

  /// Whether the dragged item gets its own live layer between the static
  /// below/above layers (exact z-order during the gesture).
  private var usesDragLayerSplit: Bool {
    guard isResizingAnnotation || isDraggingAnnotation else { return false }
    if isDraggingAnnotation, gestureExcludedIds.isEmpty { return false } // multi-item drag
    let excluded = gestureExcludedIds
    // A selected item outside the gesture would keep stale selection visuals in
    // the static layers — keep everything static instead (exact same output).
    guard state.selectedAnnotationIds.allSatisfy({ excluded.contains($0) }),
          state.selectedAnnotationId.map({ excluded.contains($0) }) ?? true else { return false }
    return true
  }

  /// Splits display items into the three drawing layers, preserving the
  /// `renderOrdered` z-order around the dragged item.
  private func partitionedDisplayItems() -> (below: [AnnotationItem], dragged: [AnnotationItem], above: [AnnotationItem]) {
    let ordered = currentDisplayItems().renderOrdered
    guard usesDragLayerSplit else {
      return (ordered, [], [])
    }
    let excluded = gestureExcludedIds
    let splitIndex = ordered.firstIndex(where: { excluded.contains($0.id) }) ?? ordered.endIndex
    let below = Array(ordered[..<splitIndex])
    let dragged = ordered[splitIndex...].filter { excluded.contains($0.id) }
    let above = ordered[splitIndex...].filter { !excluded.contains($0.id) }
    return (below, dragged, above)
  }

  /// Resolves shared render inputs for one draw pass and drops the blur cache
  /// when the source image changed.
  private func prepareRenderInputs() -> (sourceImage: NSImage?, sourceCGImage: CGImage?) {
    let effectiveSourceImage = state.effectiveSourceImage
    let currentImageIdentifier = effectiveSourceImage.map(ObjectIdentifier.init)
    if currentImageIdentifier != lastSourceImageIdentifier {
      blurCacheManager.clearAll()
      lastSourceImageIdentifier = currentImageIdentifier
    }
    return (effectiveSourceImage, effectiveSourceImage?.cgImage(forProposedRect: nil, context: nil, hints: nil))
  }

  private func makeRenderer(sourceImage: NSImage?, sourceCGImage: CGImage?, in context: CGContext) -> AnnotationRenderer {
    AnnotationRenderer(
      context: context,
      editingTextId: state.editingTextAnnotationId,
      sourceImage: sourceImage,
      sourceCGImage: sourceCGImage,
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
  }

  // MARK: Layer draw bodies (invoked by CanvasLayerView, on that view's context)

  private func drawStaticBelow(dirtyRect: NSRect) {
    drawAnnotationItems(partitionedDisplayItems().below, dirtyRect: dirtyRect)
  }

  private func drawDraggedItems(dirtyRect: NSRect) {
    drawAnnotationItems(partitionedDisplayItems().dragged, dirtyRect: dirtyRect)
  }

  private func drawStaticAbove(dirtyRect: NSRect) {
    drawAnnotationItems(partitionedDisplayItems().above, dirtyRect: dirtyRect)
  }

  /// Draws annotations with selection visuals. Skips items that cannot
  /// intersect the dirty rect — AppKit clips to it anyway, output is identical.
  private func drawAnnotationItems(_ items: [AnnotationItem], dirtyRect: NSRect) {
    guard !items.isEmpty,
          let context = NSGraphicsContext.current?.cgContext else { return }

    let (sourceImage, sourceCGImage) = prepareRenderInputs()
    context.saveGState()
    context.scaleBy(x: displayScale, y: displayScale)
    context.translateBy(x: -effectiveCanvasBounds.minX, y: -effectiveCanvasBounds.minY)

    let renderer = makeRenderer(sourceImage: sourceImage, sourceCGImage: sourceCGImage, in: context)
    let cullingPadding = max(24, 8 / max(displayScale, 0.0001))
    let imageDirtyRect = displayToImage(dirtyRect).insetBy(dx: -cullingPadding, dy: -cullingPadding)

    for annotation in items {
      guard annotation.selectionBounds.intersects(imageDirtyRect) else { continue }

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

    context.restoreGState()
  }

  /// Unified Spotlight overlay pass (below annotations, above base image).
  /// Opacity is sourced from each item's own properties so slider changes reflect immediately.
  private func drawSpotlightOverlay(dirtyRect _: NSRect) {
    guard let context = NSGraphicsContext.current?.cgContext else { return }
    context.saveGState()
    context.scaleBy(x: displayScale, y: displayScale)
    context.translateBy(x: -effectiveCanvasBounds.minX, y: -effectiveCanvasBounds.minY)

    let spotlightCreationProps = state.annotationCreationProperties(for: .spotlight)
    let spotlightRegions = currentDisplayItems().compactMap { a -> SpotlightRegion? in
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

    context.restoreGState()
  }

  /// Live gesture previews: in-progress stroke and area-selection rect.
  private func drawGesturePreview(dirtyRect _: NSRect) {
    guard let context = NSGraphicsContext.current?.cgContext else { return }
    let (sourceImage, sourceCGImage) = prepareRenderInputs()
    context.saveGState()
    context.scaleBy(x: displayScale, y: displayScale)
    context.translateBy(x: -effectiveCanvasBounds.minX, y: -effectiveCanvasBounds.minY)
    drawCurrentStrokePreview(sourceImage: sourceImage, sourceCGImage: sourceCGImage, in: context)
    drawAreaSelectionPreview(in: context)
    context.restoreGState()
  }

  /// Live preview of the in-progress stroke while a drawing gesture is active.
  private func drawCurrentStrokePreview(sourceImage: NSImage?, sourceCGImage: CGImage?, in context: CGContext) {
    guard isDrawing, let start = dragStart else { return }
    let renderer = makeRenderer(sourceImage: sourceImage, sourceCGImage: sourceCGImage, in: context)

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
        lineStyle: previewProperties.lineStyle,
        rectangleCornerRadius: previewProperties.cornerRadius,
        watermarkText: state.watermarkText,
        watermarkStyle: previewProperties.watermarkStyle,
        watermarkOpacity: previewProperties.opacity,
        watermarkRotationDegrees: previewProperties.rotationDegrees,
        watermarkFontSize: previewProperties.fontSize
      )
    }
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

  private func handleCropResize(handle: CropHandle, currentPoint: CGPoint, shiftHeld: Bool = false, commandHeld: Bool = false) {
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

    // Snap the moving edge(s) to detected content borders (CleanShot X style).
    // Skipped while ⌘ is held (temporary override), while ⇧ aspect-lock is
    // active, or when a fixed aspect ratio owns the rect geometry.
    if state.isCropEdgeSnappingEnabled, !commandHeld, !shiftHeld,
       state.cropAspectRatio == .free, let profile = state.cropEdgeProfile {
      // Tolerance for ~10 screen px, in image points. The canvas NSView renders
      // 1 image point as `displayScale` view px (AnnotateCanvasView passes the
      // fit scale), and `.scaleEffect(state.zoomLevel)` is applied to the
      // ZStack *outside* the NSView — so screen px per image point is
      // displayScale × zoomLevel, and image points per screen px its inverse.
      let snapTolerance = 10 / max(displayScale * state.zoomLevel, 0.0001)
      newRect = CropEdgeSnapping.resolve(
        handle: handle,
        proposed: newRect,
        targets: profile,
        tolerance: snapTolerance
      )
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
