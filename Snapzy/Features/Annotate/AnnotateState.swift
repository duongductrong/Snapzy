//
//  AnnotateState.swift
//  Snapzy
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

  @Published var sourceImage: NSImage?
  @Published var sourceURL: URL?

  /// Whether an image is loaded
  var hasImage: Bool { sourceImage != nil }

  // MARK: - Tool State

  @Published var selectedTool: AnnotationToolType = .selection
  @Published var strokeWidth: CGFloat = 3
  @Published var strokeColor: Color = .red
  @Published var fillColor: Color = .clear
  @Published var blurType: BlurType = .pixelated

  // MARK: - Editor Mode

  /// Editor mode determines whether user is annotating or applying mockup transforms
  enum EditorMode: String, CaseIterable {
    case annotate  // Normal annotation editing (flat image)
    case mockup    // 3D perspective transforms with controls
    case preview   // Preview combined result (hides all editing UI)
  }

  @Published var editorMode: EditorMode = .annotate

  // MARK: - UI State

  @Published var showSidebar: Bool = false
  @Published var zoomLevel: CGFloat = 1.0

  // MARK: - Background Settings

  @Published var backgroundStyle: BackgroundStyle = .none {
    didSet {
      // Pre-cache wallpaper/blurred image when style changes
      switch backgroundStyle {
      case .wallpaper(let url), .blurred(let url):
        loadBackgroundImage(from: url)
      default:
        cachedBackgroundImage = nil
      }
    }
  }

  /// Cached background image for performance (avoids disk reads during slider drag)
  /// IMPORTANT: @Published to trigger SwiftUI re-render when async load completes
  @Published private(set) var cachedBackgroundImage: NSImage?

  /// Cached pre-computed blurred image (avoids real-time blur on every frame)
  @Published private(set) var cachedBlurredImage: NSImage?

  /// Track the URL being loaded to prevent race conditions
  private var loadingBackgroundURL: URL?

  private func loadBackgroundImage(from url: URL) {
    // Skip preset URLs (handled via gradient)
    guard url.scheme != "preset" else {
      cachedBackgroundImage = nil
      cachedBlurredImage = nil
      loadingBackgroundURL = nil
      return
    }

    // Track which URL we're loading to prevent race conditions
    loadingBackgroundURL = url

    // Use preview cache (2048px) instead of full resolution for performance
    SystemWallpaperManager.shared.loadPreviewImage(for: url) { [weak self] image in
      Task { @MainActor in
        // Race condition guard: only apply if this is still the intended URL
        guard self?.loadingBackgroundURL == url else { return }

        self?.cachedBackgroundImage = image
        self?.loadingBackgroundURL = nil

        // Pre-compute blurred variant if .blurred style is active
        if case .blurred = self?.backgroundStyle {
          self?.cachedBlurredImage = self?.applyGaussianBlur(
            to: image,
            radius: WallpaperQualityConfig.blurRadius
          )
        } else {
          self?.cachedBlurredImage = nil
        }
      }
    }
  }

  /// Apply CIGaussianBlur to NSImage (one-time computation, GPU-accelerated)
  private func applyGaussianBlur(to image: NSImage?, radius: CGFloat) -> NSImage? {
    guard let image = image,
          let tiffData = image.tiffRepresentation,
          let ciImage = CIImage(data: tiffData) else { return nil }

    let filter = CIFilter(name: "CIGaussianBlur")
    filter?.setValue(ciImage, forKey: kCIInputImageKey)
    filter?.setValue(radius, forKey: kCIInputRadiusKey)

    guard let output = filter?.outputImage else { return nil }

    // Crop to original bounds (blur extends edges)
    let croppedOutput = output.cropped(to: ciImage.extent)

    let rep = NSCIImageRep(ciImage: croppedOutput)
    let blurred = NSImage(size: rep.size)
    blurred.addRepresentation(rep)
    return blurred
  }

  @Published var padding: CGFloat = 0
  @Published var inset: CGFloat = 0
  @Published var autoBalance: Bool = true
  @Published var shadowIntensity: CGFloat = 0.3
  @Published var cornerRadius: CGFloat = 8
  @Published var imageAlignment: ImageAlignment = .center
  @Published var aspectRatio: AspectRatioOption = .auto

  // MARK: - Preview Values (for smooth slider dragging)

  /// Preview values during slider drag - nil when not dragging
  @Published var previewPadding: CGFloat?
  @Published var previewInset: CGFloat?
  @Published var previewShadowIntensity: CGFloat?
  @Published var previewCornerRadius: CGFloat?

  /// Effective values for canvas rendering (preview overrides actual during drag)
  var effectivePadding: CGFloat { previewPadding ?? padding }
  var effectiveInset: CGFloat { previewInset ?? inset }
  var effectiveShadowIntensity: CGFloat { previewShadowIntensity ?? shadowIntensity }
  var effectiveCornerRadius: CGFloat { previewCornerRadius ?? cornerRadius }

  // MARK: - Display Metrics (for inset padding layout)

  /// Default canvas size when no image loaded
  private static let defaultCanvasWidth: CGFloat = 400
  private static let defaultCanvasHeight: CGFloat = 300

  /// Original image dimensions (points, not pixels)
  var imageWidth: CGFloat { sourceImage?.size.width ?? Self.defaultCanvasWidth }
  var imageHeight: CGFloat { sourceImage?.size.height ?? Self.defaultCanvasHeight }
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
  /// - displayPadding: The padding in display coordinates (already scaled) - unused for seamless alignment
  func imageOffset(for containerSize: CGSize, imageDisplaySize: CGSize, displayPadding: CGFloat) -> CGPoint {
    // For SEAMLESS edge alignment: use total extra space (container - image)
    // This moves image to touch the background edge with NO gap
    let totalExtraWidth = containerSize.width - imageDisplaySize.width
    let totalExtraHeight = containerSize.height - imageDisplaySize.height

    // In ZStack, children are centered. Offset is relative to center.
    // For center: offset = 0
    // For edges: offset = +/- totalExtraSpace/2 (moves image to touch edge)
    let xOffset: CGFloat
    let yOffset: CGFloat

    switch imageAlignment {
    case .center:
      xOffset = 0
      yOffset = 0
    case .topLeft:
      xOffset = -totalExtraWidth / 2
      yOffset = -totalExtraHeight / 2  // Negative Y = move up toward top
    case .top:
      xOffset = 0
      yOffset = -totalExtraHeight / 2
    case .topRight:
      xOffset = totalExtraWidth / 2
      yOffset = -totalExtraHeight / 2
    case .left:
      xOffset = -totalExtraWidth / 2
      yOffset = 0
    case .right:
      xOffset = totalExtraWidth / 2
      yOffset = 0
    case .bottomLeft:
      xOffset = -totalExtraWidth / 2
      yOffset = totalExtraHeight / 2  // Positive Y = move down toward bottom
    case .bottom:
      xOffset = 0
      yOffset = totalExtraHeight / 2
    case .bottomRight:
      xOffset = totalExtraWidth / 2
      yOffset = totalExtraHeight / 2
    }

    return CGPoint(x: xOffset, y: yOffset)
  }

  // MARK: - Annotations

  @Published var annotations: [AnnotationItem] = []
  @Published var selectedAnnotationId: UUID?
  @Published var editingTextAnnotationId: UUID?

  // MARK: - Counter Tool State (derived from annotations, not stored)

  // MARK: - Crop State

  /// Current crop rectangle in image coordinates (nil = no crop, full image)
  @Published var cropRect: CGRect?
  /// Original crop rect when crop mode started (used as base for aspect ratio calculations)
  private var originalCropRect: CGRect?
  /// Whether crop mode is actively being edited
  @Published var isCropActive: Bool = false
  /// Selected aspect ratio for crop
  @Published var cropAspectRatio: CropAspectRatio = .free
  /// Whether to show rule of thirds grid
  @Published var showCropGrid: Bool = true
  /// Whether currently resizing (for dimension display)
  @Published var isCropResizing: Bool = false
  /// Whether Shift is held (for aspect ratio lock)
  @Published var isCropShiftLocked: Bool = false

  // MARK: - Mockup State

  @Published var mockupRotationX: Double = 0
  @Published var mockupRotationY: Double = 0
  @Published var mockupRotationZ: Double = 0
  @Published var mockupPerspective: Double = 0.5
  @Published var mockupShadowIntensity: Double = 0.3
  @Published var mockupCornerRadius: Double = 12
  @Published var mockupPadding: CGFloat = 40
  @Published var selectedMockupPresetId: UUID?

  /// Computed shadow properties for mockup
  var mockupShadowOffsetX: CGFloat { CGFloat(mockupRotationY) * 0.8 }
  var mockupShadowOffsetY: CGFloat { CGFloat(mockupRotationX) * 0.5 + 8 }
  var mockupShadowRadius: CGFloat { CGFloat(20 * (1.1 - mockupPerspective) * mockupShadowIntensity * 2) }

  /// Apply mockup preset
  func applyMockupPreset(_ preset: MockupPreset) {
    mockupRotationX = preset.rotationX
    mockupRotationY = preset.rotationY
    mockupRotationZ = preset.rotationZ
    mockupPerspective = preset.perspective
    mockupPadding = preset.padding
    selectedMockupPresetId = preset.id
    hasUnsavedChanges = true
  }

  /// Reset mockup to defaults
  func resetMockup() {
    mockupRotationX = 0
    mockupRotationY = 0
    mockupRotationZ = 0
    mockupPerspective = 0.5
    mockupShadowIntensity = 0.3
    mockupCornerRadius = 12
    mockupPadding = 40
    selectedMockupPresetId = nil
  }

  // MARK: - Unsaved Changes Tracking

  /// Whether canvas has modifications not yet saved to disk
  @Published var hasUnsavedChanges: Bool = false

  // MARK: - Undo/Redo

  @Published var canUndo: Bool = false
  @Published var canRedo: Bool = false

  private var undoStack: [[AnnotationItem]] = []
  private var redoStack: [[AnnotationItem]] = []

  init(image: NSImage, url: URL) {
    self.sourceImage = image
    self.sourceURL = url
  }

  /// Empty initializer for drag-drop workflow
  init() {
    self.sourceImage = nil
    self.sourceURL = nil
  }

  // MARK: - Image Loading

  /// Load image from URL with Retina scaling
  func loadImage(from url: URL) {
    guard let image = Self.loadImageWithCorrectScale(from: url) else { return }
    self.sourceImage = image
    self.sourceURL = url
    // Reset annotations for new image
    annotations.removeAll()
    undoStack.removeAll()
    redoStack.removeAll()
    canUndo = false
    canRedo = false

    // Reset crop for new image
    cropRect = nil
    isCropActive = false
    editorMode = .annotate  // Reset to annotate mode
    hasUnsavedChanges = false
  }

  /// Load image directly
  func loadImage(_ image: NSImage, url: URL? = nil) {
    self.sourceImage = image
    self.sourceURL = url
    // Reset annotations for new image
    annotations.removeAll()
    undoStack.removeAll()
    redoStack.removeAll()
    canUndo = false
    canRedo = false

    // Reset crop for new image
    cropRect = nil
    isCropActive = false
    editorMode = .annotate  // Reset to annotate mode
    hasUnsavedChanges = false
  }

  /// Load image and adjust size for Retina displays
  private static func loadImageWithCorrectScale(from url: URL) -> NSImage? {
    guard let image = NSImage(contentsOf: url) else { return nil }

    // Get the actual pixel dimensions from the bitmap representation
    guard let bitmapRep = image.representations.first as? NSBitmapImageRep else {
      // If no bitmap rep, try to get pixel size from any representation
      if let rep = image.representations.first {
        let pixelWidth = rep.pixelsWide
        let pixelHeight = rep.pixelsHigh
        if pixelWidth > 0 && pixelHeight > 0 {
          // Assume Retina (2x) - divide by main screen's backing scale
          let scaleFactor = NSScreen.main?.backingScaleFactor ?? 2.0
          image.size = NSSize(
            width: CGFloat(pixelWidth) / scaleFactor,
            height: CGFloat(pixelHeight) / scaleFactor
          )
        }
      }
      return image
    }

    let pixelWidth = bitmapRep.pixelsWide
    let pixelHeight = bitmapRep.pixelsHigh

    // Get the screen's backing scale factor (2.0 for Retina)
    let scaleFactor = NSScreen.main?.backingScaleFactor ?? 2.0

    // Set the image size to point dimensions (pixels / scale factor)
    image.size = NSSize(
      width: CGFloat(pixelWidth) / scaleFactor,
      height: CGFloat(pixelHeight) / scaleFactor
    )

    return image
  }

  // MARK: - Undo/Redo Methods

  func saveState() {
    undoStack.append(annotations)
    redoStack.removeAll()
    canUndo = true
    canRedo = false
    hasUnsavedChanges = true
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

  /// Derive next counter value from existing annotations.
  /// This ensures undo/redo correctly adjusts future counter values.
  func nextCounterValue() -> Int {
    let maxExisting = annotations.compactMap { annotation -> Int? in
      if case .counter(let v) = annotation.type { return v }
      return nil
    }.max() ?? 0
    return maxExisting + 1
  }

  // MARK: - Crop Methods

  /// Initialize crop to full image bounds
  func initializeCrop() {
    let fullImageRect = CGRect(origin: .zero, size: CGSize(width: imageWidth, height: imageHeight))
    cropRect = fullImageRect
    originalCropRect = fullImageRect  // Save original for aspect ratio calculations
    isCropActive = true
  }

  /// Apply crop (confirm) - keeps cropRect for export
  func applyCrop() {
    isCropActive = false
    hasUnsavedChanges = true
  }

  /// Reset unsaved changes flag after successful save
  func markAsSaved() {
    hasUnsavedChanges = false
  }

  /// Cancel crop and reset
  func cancelCrop() {
    cropRect = nil
    isCropActive = false
    selectedTool = .selection
  }

  /// Reset crop to nil
  func resetCrop() {
    cropRect = nil
    isCropActive = false
    cropAspectRatio = .free
    isCropResizing = false
    isCropShiftLocked = false
  }

  /// Apply aspect ratio to current crop rect
  func applyCropAspectRatio(_ ratio: CropAspectRatio) {
    cropAspectRatio = ratio

    // Use original crop rect as base to prevent shrinking
    guard var rect = originalCropRect ?? cropRect, ratio != .free else { return }

    let targetRatio = ratio.ratio
    let currentRatio = rect.width / rect.height

    if currentRatio > targetRatio {
      // Too wide, reduce width
      let newWidth = rect.height * targetRatio
      rect.origin.x += (rect.width - newWidth) / 2
      rect.size.width = newWidth
    } else {
      // Too tall, reduce height
      let newHeight = rect.width / targetRatio
      rect.origin.y += (rect.height - newHeight) / 2
      rect.size.height = newHeight
    }

    cropRect = constrainCropToImageBounds(rect)
  }

  /// Update crop rect with bounds constraint
  func updateCropRect(_ newRect: CGRect) {
    cropRect = constrainCropToImageBounds(newRect)
  }

  /// Constrain crop rect to image bounds with minimum size
  private func constrainCropToImageBounds(_ rect: CGRect) -> CGRect {
    var constrained = rect

    // Enforce minimum size
    let minSize: CGFloat = 20
    if constrained.width < minSize { constrained.size.width = minSize }
    if constrained.height < minSize { constrained.size.height = minSize }

    // Constrain to image bounds
    constrained.origin.x = max(0, constrained.origin.x)
    constrained.origin.y = max(0, constrained.origin.y)

    if constrained.maxX > imageWidth {
      constrained.origin.x = imageWidth - constrained.width
    }
    if constrained.maxY > imageHeight {
      constrained.origin.y = imageHeight - constrained.height
    }

    // Final clamp for edge cases
    constrained.origin.x = max(0, constrained.origin.x)
    constrained.origin.y = max(0, constrained.origin.y)

    return constrained
  }

  // MARK: - Annotation Selection

  func selectAnnotation(at point: CGPoint) -> AnnotationItem? {
    // Find annotation at point (in reverse order to select topmost)
    for annotation in annotations.reversed() {
      // Quick bounds check first (optimization)
      let expandedBounds = annotation.bounds.insetBy(dx: -10, dy: -10)
      guard expandedBounds.contains(point) else { continue }

      // Precise hit test
      if annotation.containsPoint(point) {
        selectedAnnotationId = annotation.id
        return annotation
      }
    }
    selectedAnnotationId = nil
    return nil
  }

  func updateAnnotationBounds(id: UUID, bounds: CGRect) {
    guard let index = annotations.firstIndex(where: { $0.id == id }) else { return }

    let oldBounds = annotations[index].bounds
    let dx = bounds.origin.x - oldBounds.origin.x
    let dy = bounds.origin.y - oldBounds.origin.y

    annotations[index].bounds = bounds

    // Also update embedded coordinates for arrows/lines/paths
    switch annotations[index].type {
    case .arrow(let start, let end):
      annotations[index].type = .arrow(
        start: CGPoint(x: start.x + dx, y: start.y + dy),
        end: CGPoint(x: end.x + dx, y: end.y + dy)
      )
    case .line(let start, let end):
      annotations[index].type = .line(
        start: CGPoint(x: start.x + dx, y: start.y + dy),
        end: CGPoint(x: end.x + dx, y: end.y + dy)
      )
    case .path(let points):
      annotations[index].type = .path(points.map { CGPoint(x: $0.x + dx, y: $0.y + dy) })
    case .highlight(let points):
      annotations[index].type = .highlight(points.map { CGPoint(x: $0.x + dx, y: $0.y + dy) })
    default:
      break
    }
  }

  func updateAnnotationText(id: UUID, text: String) {
    if let index = annotations.firstIndex(where: { $0.id == id }) {
      annotations[index].type = .text(text)
      // Auto-size bounds based on text content
      let newBounds = calculateTextBounds(
        text: text,
        fontSize: annotations[index].properties.fontSize,
        origin: annotations[index].bounds.origin
      )
      annotations[index].bounds = newBounds
    }
  }

  /// Update annotation properties (strokeWidth, fontSize, colors)
  func updateAnnotationProperties(
    id: UUID,
    strokeWidth: CGFloat? = nil,
    fontSize: CGFloat? = nil,
    strokeColor: Color? = nil,
    fillColor: Color? = nil
  ) {
    guard let index = annotations.firstIndex(where: { $0.id == id }) else { return }

    if let strokeWidth = strokeWidth {
      annotations[index].properties.strokeWidth = strokeWidth
    }
    if let fontSize = fontSize {
      annotations[index].properties.fontSize = fontSize
      // Recalculate bounds for new font size
      if case .text(let content) = annotations[index].type {
        annotations[index].bounds = calculateTextBounds(
          text: content,
          fontSize: fontSize,
          origin: annotations[index].bounds.origin
        )
      }
    }
    if let strokeColor = strokeColor {
      annotations[index].properties.strokeColor = strokeColor
    }
    if let fillColor = fillColor {
      annotations[index].properties.fillColor = fillColor
    }
  }

  /// Calculate text bounds based on content and font size
  /// - Parameters:
  ///   - text: The text content
  ///   - fontSize: Desired font size (will be clamped to 8-144pt range)
  ///   - origin: Origin point for the text bounds
  /// - Returns: Bounded CGRect with enforced maximum dimensions
  private func calculateTextBounds(text: String, fontSize: CGFloat, origin: CGPoint) -> CGRect {
    // Clamp font size to reasonable range (prevent extreme values)
    let clampedFontSize = min(max(fontSize, 8), 144)

    let attributes: [NSAttributedString.Key: Any] = [
      .font: NSFont.systemFont(ofSize: clampedFontSize)
    ]
    let displayText = text.isEmpty ? "Text" : text
    let size = (displayText as NSString).size(withAttributes: attributes)
    let padding: CGFloat = 4

    // Enforce maximum bounds to prevent performance issues
    let maxWidth: CGFloat = 2000  // ~reasonable for 4K displays
    let maxHeight: CGFloat = 500  // ~15 lines of large text

    return CGRect(
      x: origin.x,
      y: origin.y,
      width: min(size.width + padding * 2, maxWidth),
      height: min(size.height + padding * 2, maxHeight)
    )
  }

  /// Get selected annotation if it's a text type
  var selectedTextAnnotation: AnnotationItem? {
    guard let id = selectedAnnotationId,
          let annotation = annotations.first(where: { $0.id == id }),
          case .text = annotation.type else {
      return nil
    }
    return annotation
  }

  /// Get selected annotation (any type)
  var selectedAnnotation: AnnotationItem? {
    guard let id = selectedAnnotationId else { return nil }
    return annotations.first { $0.id == id }
  }

  func deleteSelectedAnnotation() {
    guard let selectedId = selectedAnnotationId else { return }
    saveState()
    annotations.removeAll { $0.id == selectedId }
    selectedAnnotationId = nil
  }

  /// Deselect current annotation
  func deselectAnnotation() {
    selectedAnnotationId = nil
    editingTextAnnotationId = nil
  }

  /// Nudge selected annotation by delta
  func nudgeSelectedAnnotation(dx: CGFloat, dy: CGFloat) {
    guard let selectedId = selectedAnnotationId,
          let index = annotations.firstIndex(where: { $0.id == selectedId }) else { return }

    saveState()
    annotations[index].bounds.origin.x += dx
    annotations[index].bounds.origin.y += dy

    // Also update embedded points for arrows/lines/paths
    switch annotations[index].type {
    case .arrow(let start, let end):
      annotations[index].type = .arrow(
        start: CGPoint(x: start.x + dx, y: start.y + dy),
        end: CGPoint(x: end.x + dx, y: end.y + dy)
      )
    case .line(let start, let end):
      annotations[index].type = .line(
        start: CGPoint(x: start.x + dx, y: start.y + dy),
        end: CGPoint(x: end.x + dx, y: end.y + dy)
      )
    case .path(let points):
      annotations[index].type = .path(points.map { CGPoint(x: $0.x + dx, y: $0.y + dy) })
    case .highlight(let points):
      annotations[index].type = .highlight(points.map { CGPoint(x: $0.x + dx, y: $0.y + dy) })
    default:
      break
    }
  }
}
