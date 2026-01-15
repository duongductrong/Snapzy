//
//  AnnotateState.swift
//  ZapShot
//
//  Central state management for annotation window
//

import AppKit
import Combine
import SwiftUI

/// Central state for annotation window
@MainActor
final class AnnotateState: ObservableObject {

  // MARK: - Source Image

  let sourceImage: NSImage
  let sourceURL: URL

  // MARK: - Tool State

  @Published var selectedTool: AnnotationToolType = .selection
  @Published var strokeWidth: CGFloat = 3
  @Published var strokeColor: Color = .red
  @Published var fillColor: Color = .clear

  // MARK: - UI State

  @Published var showSidebar: Bool = true
  @Published var zoomLevel: CGFloat = 1.0

  // MARK: - Background Settings

  @Published var backgroundStyle: BackgroundStyle = .none
  @Published var padding: CGFloat = 0
  @Published var inset: CGFloat = 0
  @Published var autoBalance: Bool = true
  @Published var shadowIntensity: CGFloat = 0.3
  @Published var cornerRadius: CGFloat = 8
  @Published var imageAlignment: ImageAlignment = .center
  @Published var aspectRatio: AspectRatioOption = .auto

  // MARK: - Display Metrics (for inset padding layout)

  /// Original image dimensions (points, not pixels)
  var imageWidth: CGFloat { sourceImage.size.width }
  var imageHeight: CGFloat { sourceImage.size.height }
  var imageAspectRatio: CGFloat { imageWidth / imageHeight }

  /// Calculate display scale for given container size
  /// Image shrinks to fit within (container - padding*2)
  func displayScale(for containerSize: CGSize, margin: CGFloat = 40) -> CGFloat {
    let availableWidth = containerSize.width - margin * 2
    let availableHeight = containerSize.height - margin * 2

    // Available space for image after padding
    let imageAreaWidth = max(availableWidth - padding * 2, 1)
    let imageAreaHeight = max(availableHeight - padding * 2, 1)

    let scaleX = imageAreaWidth / imageWidth
    let scaleY = imageAreaHeight / imageHeight

    return min(scaleX, scaleY, 1.0) // Don't scale up
  }

  /// Calculate image offset within container based on alignment
  /// Note: ZStack centers children, so offset is relative to center (not top-left)
  /// - containerSize: The background size (already scaled)
  /// - imageDisplaySize: The image size (already scaled)
  /// - displayPadding: The padding in display coordinates (already scaled)
  func imageOffset(for containerSize: CGSize, imageDisplaySize: CGSize, displayPadding: CGFloat) -> CGPoint {
    // Extra space after accounting for scaled padding and image
    let extraWidth = containerSize.width - displayPadding * 2 - imageDisplaySize.width
    let extraHeight = containerSize.height - displayPadding * 2 - imageDisplaySize.height

    // In ZStack, children are centered. Offset is relative to center.
    // For center: offset = 0
    // For edges: offset = +/- extraSpace/2
    let xOffset: CGFloat
    let yOffset: CGFloat

    switch imageAlignment {
    case .center:
      xOffset = 0
      yOffset = 0
    case .topLeft:
      xOffset = -extraWidth / 2
      yOffset = extraHeight / 2  // SwiftUI Y is inverted (positive = down)
    case .top:
      xOffset = 0
      yOffset = extraHeight / 2
    case .topRight:
      xOffset = extraWidth / 2
      yOffset = extraHeight / 2
    case .left:
      xOffset = -extraWidth / 2
      yOffset = 0
    case .right:
      xOffset = extraWidth / 2
      yOffset = 0
    case .bottomLeft:
      xOffset = -extraWidth / 2
      yOffset = -extraHeight / 2
    case .bottom:
      xOffset = 0
      yOffset = -extraHeight / 2
    case .bottomRight:
      xOffset = extraWidth / 2
      yOffset = -extraHeight / 2
    }

    return CGPoint(x: xOffset, y: yOffset)
  }

  // MARK: - Annotations

  @Published var annotations: [AnnotationItem] = []
  @Published var selectedAnnotationId: UUID?
  @Published var editingTextAnnotationId: UUID?

  // MARK: - Counter Tool State

  @Published var counterValue: Int = 1

  // MARK: - Undo/Redo

  @Published var canUndo: Bool = false
  @Published var canRedo: Bool = false

  private var undoStack: [[AnnotationItem]] = []
  private var redoStack: [[AnnotationItem]] = []

  init(image: NSImage, url: URL) {
    self.sourceImage = image
    self.sourceURL = url
  }

  // MARK: - Undo/Redo Methods

  func saveState() {
    undoStack.append(annotations)
    redoStack.removeAll()
    canUndo = true
    canRedo = false
  }

  func undo() {
    guard let previous = undoStack.popLast() else { return }
    redoStack.append(annotations)
    annotations = previous
    canUndo = !undoStack.isEmpty
    canRedo = true
  }

  func redo() {
    guard let next = redoStack.popLast() else { return }
    undoStack.append(annotations)
    annotations = next
    canUndo = true
    canRedo = !redoStack.isEmpty
  }

  // MARK: - Counter

  func nextCounterValue() -> Int {
    let value = counterValue
    counterValue += 1
    return value
  }

  func resetCounter() {
    counterValue = 1
  }

  // MARK: - Annotation Selection

  func selectAnnotation(at point: CGPoint) -> AnnotationItem? {
    // Find annotation at point (in reverse order to select topmost)
    for annotation in annotations.reversed() {
      if annotation.bounds.contains(point) {
        selectedAnnotationId = annotation.id
        return annotation
      }
    }
    selectedAnnotationId = nil
    return nil
  }

  func updateAnnotationBounds(id: UUID, bounds: CGRect) {
    if let index = annotations.firstIndex(where: { $0.id == id }) {
      annotations[index].bounds = bounds
    }
  }

  func updateAnnotationText(id: UUID, text: String) {
    if let index = annotations.firstIndex(where: { $0.id == id }) {
      annotations[index].type = .text(text)
    }
  }

  func deleteSelectedAnnotation() {
    guard let selectedId = selectedAnnotationId else { return }
    saveState()
    annotations.removeAll { $0.id == selectedId }
    selectedAnnotationId = nil
  }
}
