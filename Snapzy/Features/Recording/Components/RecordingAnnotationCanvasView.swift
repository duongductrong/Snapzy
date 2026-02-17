//
//  RecordingAnnotationCanvasView.swift
//  Snapzy
//
//  NSView handling mouse events and rendering annotations
//  during screen recording on a transparent overlay
//

import AppKit
import SwiftUI

@MainActor
final class RecordingAnnotationCanvasView: NSView {

  let state: RecordingAnnotationState
  private let shortcutManager = AnnotateShortcutManager.shared

  private var isDrawing = false
  private var drawStart: CGPoint = .zero
  private var currentPath: [CGPoint] = []
  private var trackingArea: NSTrackingArea?

  init(state: RecordingAnnotationState) {
    self.state = state
    super.init(frame: .zero)
    wantsLayer = true
    layer?.backgroundColor = .clear
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError() }

  override var acceptsFirstResponder: Bool { true }
  override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

  override func updateTrackingAreas() {
    super.updateTrackingAreas()
    if let existing = trackingArea { removeTrackingArea(existing) }
    let area = NSTrackingArea(
      rect: bounds,
      options: [.activeAlways, .mouseMoved, .mouseEnteredAndExited],
      owner: self
    )
    addTrackingArea(area)
    trackingArea = area
  }

  // MARK: - Drawing

  override func draw(_ dirtyRect: NSRect) {
    guard let context = NSGraphicsContext.current?.cgContext else { return }
    context.clear(bounds)

    let renderer = AnnotationRenderer(context: context)

    // Draw completed annotations with opacity
    for entry in state.annotations {
      context.saveGState()
      context.setAlpha(entry.opacity)
      renderer.draw(entry.item)
      context.restoreGState()
    }

    // Draw in-progress stroke
    if isDrawing {
      renderer.drawCurrentStroke(
        tool: state.selectedTool,
        start: drawStart,
        currentPath: currentPath,
        strokeColor: state.strokeColor,
        strokeWidth: state.strokeWidth
      )
    }
  }

  // MARK: - Mouse Events

  override func mouseDown(with event: NSEvent) {
    let point = convert(event.locationInWindow, from: nil)

    if state.selectedTool == .selection {
      handleSelectionDown(at: point)
      return
    }

    isDrawing = true
    drawStart = point
    currentPath = [point]
    needsDisplay = true
  }

  override func mouseDragged(with event: NSEvent) {
    let point = convert(event.locationInWindow, from: nil)

    if state.selectedTool == .selection {
      handleSelectionDrag(to: point)
      return
    }

    guard isDrawing else { return }
    currentPath.append(point)
    needsDisplay = true
  }

  override func mouseUp(with event: NSEvent) {
    let point = convert(event.locationInWindow, from: nil)

    if state.selectedTool == .selection {
      handleSelectionUp()
      return
    }

    guard isDrawing else { return }
    isDrawing = false

    let end = currentPath.last ?? point
    if let item = RecordingAnnotationFactory.createAnnotation(
      tool: state.selectedTool,
      from: drawStart,
      to: end,
      path: currentPath,
      strokeColor: state.strokeColor,
      strokeWidth: state.strokeWidth
    ) {
      state.appendAnnotation(item, tool: state.selectedTool)
    }

    currentPath.removeAll()
    needsDisplay = true
  }

  override func keyDown(with event: NSEvent) {
    // Tool shortcuts — only when shortcut mode is active (modifier held)
    if state.isShortcutModeActive,
       let char = event.characters?.lowercased().first {
      let tools = RecordingAnnotationState.availableTools
      if let matchedTool = shortcutManager.tool(for: char),
         tools.contains(matchedTool) {
        state.selectedTool = matchedTool
        needsDisplay = true
        return
      }
    }

    switch event.keyCode {
    case 51, 117:  // Delete / Forward Delete
      state.deleteSelected()
      needsDisplay = true
    case 53:  // Escape — deselect
      state.selectedAnnotationId = nil
      needsDisplay = true
    default:
      super.keyDown(with: event)
    }
  }

  // MARK: - Selection Handling

  private var isDraggingAnnotation = false
  private var dragOffset: CGPoint = .zero

  private func handleSelectionDown(at point: CGPoint) {
    // Hit test annotations (reverse order for topmost)
    for entry in state.annotations.reversed() {
      if entry.item.containsPoint(point) {
        state.selectedAnnotationId = entry.id
        isDraggingAnnotation = true
        dragOffset = CGPoint(
          x: point.x - entry.item.bounds.origin.x,
          y: point.y - entry.item.bounds.origin.y
        )
        needsDisplay = true
        return
      }
    }
    state.selectedAnnotationId = nil
    isDraggingAnnotation = false
    needsDisplay = true
  }

  private func handleSelectionDrag(to point: CGPoint) {
    guard isDraggingAnnotation, let selectedId = state.selectedAnnotationId,
          let index = state.annotations.firstIndex(where: { $0.id == selectedId })
    else { return }

    let newOrigin = CGPoint(x: point.x - dragOffset.x, y: point.y - dragOffset.y)
    state.annotations[index].item.bounds.origin = newOrigin
    needsDisplay = true
  }

  private func handleSelectionUp() {
    isDraggingAnnotation = false
  }

  // MARK: - Refresh

  func refresh() {
    needsDisplay = true
  }
}
