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
  private struct AnnotationSnapshot {
    var annotations: [AnnotationItem]
    var embeddedImageAssets: [UUID: NSImage]
  }

  private static let importedImageMaxCoverage: CGFloat = 0.7
  private static let importedImageCascadeStep: CGFloat = 24
  private static let importedImageCountWarningThreshold: Int = 8
  private static let importedImagePixelBudgetWarningThreshold: Int64 = 40_000_000
  private static let canvasPresetLimit: Int = 20
  private let canvasPresetStore = AnnotateCanvasPresetStore.shared
  private var suppressCanvasEffectChangeTracking = false

  // MARK: - Source Image

  @Published var sourceImage: NSImage?
  @Published var sourceURL: URL?
  @Published private(set) var cutoutImage: NSImage?
  @Published private(set) var isCutoutApplied: Bool = false
  @Published private(set) var isCutoutProcessing: Bool = false
  @Published var cutoutErrorMessage: String?
  private var activeCutoutOperationID: UUID?

  /// QuickAccess item ID if opened from quick access card (nil for drag-drop workflow)
  let quickAccessItemId: UUID?

  /// Cloud URL if file was already uploaded (passed from QuickAccessItem)
  @Published var cloudURL: URL?
  /// Cloud object key for overwrite re-uploads
  @Published var cloudKey: String?
  /// True when image has changed since last cloud upload (synced from QuickAccessItem)
  @Published var isCloudStale: Bool = false

  /// Whether an image is loaded
  var hasImage: Bool { sourceImage != nil }

  /// Image currently used by preview/export. Cutout is non-destructive and overlays the original source image.
  var effectiveSourceImage: NSImage? {
    if isCutoutApplied {
      return cutoutImage ?? sourceImage
    }
    return sourceImage
  }

  var canUseBackgroundCutout: Bool {
    if #available(macOS 14.0, *) {
      return true
    }
    return false
  }

  var isBackgroundCutoutAutoCropEnabled: Bool {
    UserDefaults.standard.object(forKey: PreferencesKeys.backgroundCutoutAutoCropEnabled) as? Bool ?? true
  }

  // MARK: - Tool State

  @Published var selectedTool: AnnotationToolType = .selection {
    didSet {
      // If user leaves crop by switching tool, restore sidebar if crop had auto-collapsed it.
      if oldValue == .crop, selectedTool != .crop {
        restoreSidebarAfterCropInteractionIfNeeded()
      }
    }
  }
  @Published var strokeWidth: CGFloat = 3
  @Published var strokeColor: Color = .red
  @Published var fillColor: Color = .clear
  @Published var blurType: BlurType = .pixelated
  @Published var arrowStyle: ArrowStyle = .straight

  // MARK: - Editor Mode

  /// Editor mode determines whether user is annotating or applying mockup transforms
  enum EditorMode: String, CaseIterable {
    case annotate  // Normal annotation editing (flat image)
    case mockup    // 3D perspective transforms with controls
    case preview   // Preview combined result (hides all editing UI)
  }

  enum QuickPropertiesMode: Equatable {
    case hidden
    case toolDefaults
    case selectedItem
  }

  @Published var editorMode: EditorMode = .annotate

  // MARK: - UI State

  @Published var showSidebar: Bool = false
  @Published var zoomLevel: CGFloat = 1.0
  @Published var isPinned: Bool = false

  static let minimumZoomLevel: CGFloat = 0.25
  static let defaultMaximumZoomLevel: CGFloat = 4.0
  static let hardMaximumZoomLevel: CGFloat = 16.0
  static let zoomPresetPercents = [25, 50, 75, 100, 125, 150, 200, 300, 400, 600, 800, 1200, 1600]

  /// Base fitted canvas size before zoom is applied.
  @Published private(set) var baseCanvasDisplaySize: CGSize = .zero

  /// Fit scale used to derive a dynamic max zoom for very long captures.
  @Published private(set) var fitScale: CGFloat = 1.0

  var effectiveMaximumZoomLevel: CGFloat {
    guard fitScale > 0 else { return Self.defaultMaximumZoomLevel }
    return min(Self.hardMaximumZoomLevel, max(Self.defaultMaximumZoomLevel, 1.0 / fitScale))
  }

  var effectiveZoomRange: ClosedRange<CGFloat> {
    Self.minimumZoomLevel...effectiveMaximumZoomLevel
  }

  var zoomMenuPresetPercents: [Int] {
    var options = Self.zoomPresetPercents.filter {
      CGFloat($0) / 100 <= effectiveMaximumZoomLevel + 0.001
    }

    let roundedCap = max(25, Int((effectiveMaximumZoomLevel * 100).rounded(.down) / 25) * 25)
    if roundedCap > (options.last ?? 0) {
      options.append(roundedCap)
    }

    return options
  }

  /// Clamp a zoom level to the valid range
  func clampedZoom(_ level: CGFloat) -> CGFloat {
    min(max(level, effectiveZoomRange.lowerBound), effectiveZoomRange.upperBound)
  }

  // MARK: - Pan State (for zoomed canvas navigation)

  /// Viewport pan offset (points). Applied alongside scaleEffect.
  @Published var panOffset: CGSize = .zero

  /// Whether Space key is currently held (hand tool active)
  @Published var isSpacePanning: Bool = false

  /// Canvas container size for pan bounds calculation (updated by GeometryReader)
  var canvasContainerSize: CGSize = .zero

  var canPanInteractively: Bool {
    let overflow = panOverflow(at: zoomLevel)
    return overflow.width > 0.5 || overflow.height > 0.5
  }

  func updateViewportMetrics(containerSize: CGSize, baseCanvasSize: CGSize, fitScale: CGFloat) {
    let normalizedFitScale = max(fitScale, 0.0001)
    let metricsChanged = canvasContainerSize != containerSize
      || baseCanvasDisplaySize != baseCanvasSize
      || abs(self.fitScale - normalizedFitScale) > 0.0001

    canvasContainerSize = containerSize
    if baseCanvasDisplaySize != baseCanvasSize {
      baseCanvasDisplaySize = baseCanvasSize
    }
    if abs(self.fitScale - normalizedFitScale) > 0.0001 {
      self.fitScale = normalizedFitScale
    }

    guard metricsChanged else { return }

    let clampedLevel = clampedZoom(zoomLevel)
    if abs(clampedLevel - zoomLevel) > 0.0001 {
      zoomLevel = clampedLevel
    } else {
      resetPanIfNeeded()
    }
  }

  func pan(by delta: CGSize) {
    guard canPanInteractively else {
      panOffset = .zero
      return
    }

    panOffset.width += delta.width
    panOffset.height += delta.height
    clampPanOffset()
  }

  /// Reset pan when content no longer overflows.
  func resetPanIfNeeded() {
    if !canPanInteractively {
      panOffset = .zero
    } else {
      clampPanOffset()
    }
  }

  /// Clamp pan offset to keep content partially visible.
  /// At least ~40% of the canvas remains in the viewport at all times.
  func clampPanOffset() {
    let overflow = panOverflow(at: zoomLevel)
    guard overflow.width > 0 || overflow.height > 0 else {
      panOffset = .zero
      return
    }

    let marginX = overflow.width > 0 ? canvasContainerSize.width * 0.1 : 0
    let marginY = overflow.height > 0 ? canvasContainerSize.height * 0.1 : 0
    let maxPanX = overflow.width + marginX
    let maxPanY = overflow.height + marginY

    panOffset.width = min(max(panOffset.width, -maxPanX), maxPanX)
    panOffset.height = min(max(panOffset.height, -maxPanY), maxPanY)
  }

  private func panOverflow(at zoomLevel: CGFloat) -> CGSize {
    guard canvasContainerSize.width > 0,
          canvasContainerSize.height > 0,
          baseCanvasDisplaySize.width > 0,
          baseCanvasDisplaySize.height > 0 else {
      return .zero
    }

    let renderedWidth = baseCanvasDisplaySize.width * zoomLevel
    let renderedHeight = baseCanvasDisplaySize.height * zoomLevel

    return CGSize(
      width: max((renderedWidth - canvasContainerSize.width) / 2, 0),
      height: max((renderedHeight - canvasContainerSize.height) / 2, 0)
    )
  }

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
      handleCanvasEffectDidChange()
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

  @Published var padding: CGFloat = 0 {
    didSet {
      handleCanvasEffectDidChange()
    }
  }
  @Published var inset: CGFloat = 0
  @Published var autoBalance: Bool = true
  @Published var shadowIntensity: CGFloat = 0.3 {
    didSet {
      handleCanvasEffectDidChange()
    }
  }
  @Published var cornerRadius: CGFloat = 8 {
    didSet {
      handleCanvasEffectDidChange()
    }
  }
  @Published var imageAlignment: ImageAlignment = .center
  @Published var aspectRatio: AspectRatioOption = .auto
  @Published private(set) var canvasPresets: [AnnotateCanvasPreset] = []
  @Published var selectedCanvasPresetId: UUID?
  @Published private(set) var isSelectedCanvasPresetDirty: Bool = false

  enum CanvasPresetMutationResult {
    case success
    case invalidName
    case limitReached
    case unavailablePayload
    case missingSelection
  }

  var selectedCanvasPreset: AnnotateCanvasPreset? {
    guard let selectedCanvasPresetId else { return nil }
    return canvasPresets.first(where: { $0.id == selectedCanvasPresetId })
  }

  var canUpdateSelectedCanvasPreset: Bool {
    selectedCanvasPresetId != nil && isSelectedCanvasPresetDirty
  }

  var canDeleteSelectedCanvasPreset: Bool {
    selectedCanvasPresetId != nil
  }

  var isCanvasPresetLimitReached: Bool {
    canvasPresets.count >= Self.canvasPresetLimit
  }

  var nextSuggestedCanvasPresetName: String {
    "Preset \(canvasPresets.count + 1)"
  }

  var isNoneCanvasEffectsActive: Bool {
    backgroundStyle == .none
      && abs(padding) <= 0.0001
      && abs(shadowIntensity) <= 0.0001
      && abs(cornerRadius) <= 0.0001
  }

  var canvasEffectsSnapshot: AnnotationCanvasEffects {
    AnnotationCanvasEffects(
      backgroundStyle: backgroundStyle,
      padding: padding,
      inset: inset,
      autoBalance: autoBalance,
      shadowIntensity: shadowIntensity,
      cornerRadius: cornerRadius,
      imageAlignment: imageAlignment,
      aspectRatio: aspectRatio
    )
  }

  func applyCanvasEffects(
    _ effects: AnnotationCanvasEffects,
    preferredSelectedCanvasPresetId: UUID? = nil,
    preferredPresetDirtyState: Bool? = nil
  ) {
    withCanvasEffectChangeTrackingSuspended {
      backgroundStyle = effects.backgroundStyle
      padding = effects.padding
      inset = effects.inset
      autoBalance = effects.autoBalance
      shadowIntensity = effects.shadowIntensity
      cornerRadius = effects.cornerRadius
      imageAlignment = effects.imageAlignment
      aspectRatio = effects.aspectRatio
    }

    restoreCanvasPresetSelection(
      preferredSelectedCanvasPresetId: preferredSelectedCanvasPresetId,
      preferredPresetDirtyState: preferredPresetDirtyState
    )

    previewPadding = nil
    previewInset = nil
    previewShadowIntensity = nil
    previewCornerRadius = nil
  }

  func loadCanvasPresets() {
    canvasPresets = canvasPresetStore.loadPresets()
    if let selectedCanvasPresetId,
       canvasPresets.contains(where: { $0.id == selectedCanvasPresetId }) == false {
      self.selectedCanvasPresetId = nil
    }
    recomputeCanvasPresetDirtyState()
  }

  func resetCanvasEffectsToNone() {
    let beforePayload = currentCanvasPresetPayload()
    withCanvasEffectChangeTrackingSuspended {
      backgroundStyle = .none
      padding = 0
      shadowIntensity = 0
      cornerRadius = 0
      previewPadding = nil
      previewShadowIntensity = nil
      previewCornerRadius = nil
    }
    selectedCanvasPresetId = nil
    isSelectedCanvasPresetDirty = false

    if let beforePayload,
       let afterPayload = currentCanvasPresetPayload(),
       beforePayload.approximatelyEquals(afterPayload) == false {
      hasUnsavedChanges = true
    }
  }

  func applyCanvasPreset(_ preset: AnnotateCanvasPreset) {
    let beforePayload = currentCanvasPresetPayload()
    withCanvasEffectChangeTrackingSuspended {
      backgroundStyle = preset.payload.backgroundStyle.toBackgroundStyle()
      padding = preset.payload.padding
      shadowIntensity = preset.payload.shadowIntensity
      cornerRadius = preset.payload.cornerRadius
      previewPadding = nil
      previewShadowIntensity = nil
      previewCornerRadius = nil
    }
    selectedCanvasPresetId = preset.id
    isSelectedCanvasPresetDirty = false

    if let beforePayload,
       let afterPayload = currentCanvasPresetPayload(),
       beforePayload.approximatelyEquals(afterPayload) == false {
      hasUnsavedChanges = true
    }
  }

  @discardableResult
  func saveCurrentCanvasAsPreset(name: String) -> CanvasPresetMutationResult {
    let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
    guard trimmedName.isEmpty == false else {
      return .invalidName
    }

    guard canvasPresets.count < Self.canvasPresetLimit else {
      return .limitReached
    }

    guard let payload = currentCanvasPresetPayload() else {
      return .unavailablePayload
    }

    let uniqueName = uniqueCanvasPresetName(from: trimmedName)
    let preset = AnnotateCanvasPreset(name: uniqueName, payload: payload)
    canvasPresets.insert(preset, at: 0)
    selectedCanvasPresetId = preset.id
    isSelectedCanvasPresetDirty = false
    persistCanvasPresets()
    return .success
  }

  @discardableResult
  func updateSelectedCanvasPreset() -> CanvasPresetMutationResult {
    guard let selectedCanvasPresetId,
          let index = canvasPresets.firstIndex(where: { $0.id == selectedCanvasPresetId }) else {
      return .missingSelection
    }

    guard let payload = currentCanvasPresetPayload() else {
      return .unavailablePayload
    }

    var updatedPreset = canvasPresets[index]
    updatedPreset.payload = payload
    updatedPreset.updatedAt = Date()
    canvasPresets.remove(at: index)
    canvasPresets.insert(updatedPreset, at: 0)
    self.selectedCanvasPresetId = updatedPreset.id
    isSelectedCanvasPresetDirty = false
    persistCanvasPresets()
    return .success
  }

  @discardableResult
  func deleteSelectedCanvasPreset() -> Bool {
    guard let selectedCanvasPresetId else {
      return false
    }
    return deleteCanvasPreset(id: selectedCanvasPresetId)
  }

  @discardableResult
  func deleteCanvasPreset(id: UUID) -> Bool {
    let isDeletingSelectedPreset = selectedCanvasPresetId == id

    let countBefore = canvasPresets.count
    canvasPresets.removeAll(where: { $0.id == id })
    guard canvasPresets.count != countBefore else {
      return false
    }

    if isDeletingSelectedPreset {
      selectedCanvasPresetId = nil
      isSelectedCanvasPresetDirty = false
    } else {
      recomputeCanvasPresetDirtyState()
    }
    persistCanvasPresets()
    return true
  }

  func recomputeCanvasPresetDirtyState() {
    guard let selectedPreset = selectedCanvasPreset else {
      isSelectedCanvasPresetDirty = false
      return
    }

    guard let currentPayload = currentCanvasPresetPayload() else {
      isSelectedCanvasPresetDirty = true
      return
    }

    isSelectedCanvasPresetDirty = currentPayload.approximatelyEquals(selectedPreset.payload) == false
  }

  private func handleCanvasEffectDidChange() {
    recomputeCanvasPresetDirtyState()
    guard !suppressCanvasEffectChangeTracking else { return }
    hasUnsavedChanges = true
  }

  private func withCanvasEffectChangeTrackingSuspended(_ operation: () -> Void) {
    suppressCanvasEffectChangeTracking = true
    operation()
    suppressCanvasEffectChangeTracking = false
    recomputeCanvasPresetDirtyState()
  }

  private func currentCanvasPresetPayload() -> AnnotateCanvasPresetPayload? {
    guard let codableStyle = CodableBackgroundStyle(from: backgroundStyle) else {
      return nil
    }

    return AnnotateCanvasPresetPayload(
      backgroundStyle: codableStyle,
      padding: padding,
      shadowIntensity: shadowIntensity,
      cornerRadius: cornerRadius
    )
  }

  private func restoreCanvasPresetSelection(
    preferredSelectedCanvasPresetId: UUID?,
    preferredPresetDirtyState: Bool?
  ) {
    if let preferredSelectedCanvasPresetId,
       canvasPresets.contains(where: { $0.id == preferredSelectedCanvasPresetId }) {
      selectedCanvasPresetId = preferredSelectedCanvasPresetId
      if let preferredPresetDirtyState {
        isSelectedCanvasPresetDirty = preferredPresetDirtyState
      } else {
        recomputeCanvasPresetDirtyState()
      }
      return
    }

    guard let currentPayload = currentCanvasPresetPayload(),
          let matchingPreset = canvasPresets.first(where: { $0.payload.approximatelyEquals(currentPayload) }) else {
      selectedCanvasPresetId = nil
      isSelectedCanvasPresetDirty = false
      return
    }

    selectedCanvasPresetId = matchingPreset.id
    isSelectedCanvasPresetDirty = false
  }

  private func uniqueCanvasPresetName(
    from baseName: String,
    excludingId: UUID? = nil
  ) -> String {
    let normalizedBaseName = baseName.trimmingCharacters(in: .whitespacesAndNewlines)
    guard normalizedBaseName.isEmpty == false else {
      return nextSuggestedCanvasPresetName
    }

    let existingNames = Set(
      canvasPresets
        .filter({ preset in
          guard let excludingId else { return true }
          return preset.id != excludingId
        })
        .map { $0.name.lowercased() }
    )

    if existingNames.contains(normalizedBaseName.lowercased()) == false {
      return normalizedBaseName
    }

    var suffix = 2
    while suffix < 1_000 {
      let candidate = "\(normalizedBaseName) \(suffix)"
      if existingNames.contains(candidate.lowercased()) == false {
        return candidate
      }
      suffix += 1
    }

    return "\(normalizedBaseName) \(UUID().uuidString.prefix(4))"
  }

  private func persistCanvasPresets() {
    canvasPresetStore.savePresets(canvasPresets)
  }

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
  var imageWidth: CGFloat { effectiveSourceImage?.size.width ?? Self.defaultCanvasWidth }
  var imageHeight: CGFloat { effectiveSourceImage?.size.height ?? Self.defaultCanvasHeight }
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
  /// Imported image assets referenced by `.embeddedImage(assetId)` annotations.
  @Published private(set) var embeddedImageAssets: [UUID: NSImage] = [:]
  /// Non-blocking warning for large multi-image imports.
  @Published private(set) var importWarningMessage: String?
  /// Original bytes for imported assets when available (file drop/paste raw data).
  /// Reused for session snapshot to avoid expensive re-encode on save/copy path.
  private var embeddedImageSourceData: [UUID: Data] = [:]
  /// Cached serialized bytes for imported assets that did not have direct source data.
  private var embeddedImageSnapshotCacheData: [UUID: Data] = [:]
  /// Cached decoded CGImage for faster repeated canvas/export draws.
  private var embeddedImageCGImageCache: [UUID: CGImage] = [:]
  private var lastImportWarningSignature: String?
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
  /// Restore sidebar when leaving crop if it was auto-collapsed on crop entry.
  private var shouldRestoreSidebarAfterCropInteraction: Bool = false
  /// True when current crop was auto-applied from the latest background cutout.
  private var didCutoutAutoApplyCrop: Bool = false
  /// Tracks the exact crop rect auto-applied by background cutout for safe revert behavior.
  private var cutoutAutoAppliedCropRect: CGRect?

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
    DiagnosticLogger.shared.log(.info, .annotate, "Mockup preset applied", context: ["id": preset.id.uuidString])
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
    DiagnosticLogger.shared.log(.info, .annotate, "Mockup reset")
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

  private var undoStack: [AnnotationSnapshot] = []
  private var redoStack: [AnnotationSnapshot] = []

  init(image: NSImage, url: URL, quickAccessItemId: UUID? = nil, cloudURL: URL? = nil, cloudKey: String? = nil, isCloudStale: Bool = false) {
    self.sourceImage = image
    self.sourceURL = url
    self.quickAccessItemId = quickAccessItemId
    self.cloudURL = cloudURL
    self.cloudKey = cloudKey
    self.isCloudStale = isCloudStale
    loadCanvasPresets()
  }

  /// Empty initializer for drag-drop workflow
  init() {
    self.sourceImage = nil
    self.sourceURL = nil
    self.quickAccessItemId = nil
    self.cloudURL = nil
    self.cloudKey = nil
    loadCanvasPresets()
  }

  // MARK: - Image Loading

  /// Load image from URL with Retina scaling
  func loadImage(from url: URL) {
    DiagnosticLogger.shared.log(.info, .annotate, "Loading image from URL", context: ["file": url.lastPathComponent])
    guard let image = Self.loadImageWithCorrectScale(from: url) else {
      DiagnosticLogger.shared.log(.error, .annotate, "Failed to load image", context: ["file": url.lastPathComponent])
      return
    }
    resetCanvasForNewBaseImage(image: image, url: url)
  }

  /// Load image directly
  func loadImage(_ image: NSImage, url: URL? = nil) {
    DiagnosticLogger.shared.log(.info, .annotate, "Loading image directly", context: [
      "size": "\(Int(image.size.width))x\(Int(image.size.height))",
      "url": url?.lastPathComponent ?? "nil"
    ])
    resetCanvasForNewBaseImage(image: image, url: url)
  }

  /// Import an image from a file URL.
  /// - Returns: true if import succeeded.
  @discardableResult
  func importImage(from url: URL) -> Bool {
    guard let image = Self.loadImageWithCorrectScale(from: url) else { return false }
    if !hasImage {
      loadImage(image, url: url)
      return true
    }

    addImportedImage(image, sourceData: Self.readImageData(from: url))
    return true
  }

  /// Import an image object. If the editor has no base image, this becomes the base image.
  /// Otherwise it is appended as a movable embedded-image layer.
  /// - Returns: true if import succeeded.
  @discardableResult
  func importImage(_ image: NSImage, sourceURL: URL? = nil, sourceData: Data? = nil) -> Bool {
    if !hasImage {
      loadImage(image, url: sourceURL)
      return true
    }

    addImportedImage(image, sourceData: sourceData)
    return true
  }

  /// Append an additional image layer into the current annotation canvas.
  func addImportedImage(_ image: NSImage, sourceData: Data? = nil) {
    guard hasImage else {
      loadImage(image, url: nil)
      return
    }

    let imageSize = normalizedCanvasImageSize(for: image)
    guard imageSize.width > 0, imageSize.height > 0 else { return }

    let placementBounds = importedImagePlacementBounds(for: imageSize)
    let assetId = UUID()

    saveState()
    embeddedImageAssets[assetId] = image
    if let sourceData {
      embeddedImageSourceData[assetId] = sourceData
      embeddedImageSnapshotCacheData[assetId] = sourceData
    }
    embeddedImageCGImageCache.removeValue(forKey: assetId)
    let item = AnnotationItem(
      type: .embeddedImage(assetId),
      bounds: placementBounds,
      properties: AnnotationProperties(strokeColor: .clear, fillColor: .clear, strokeWidth: 1)
    )
    annotations.append(item)
    selectedAnnotationId = item.id
    editingTextAnnotationId = nil
    selectedTool = .selection
    hasUnsavedChanges = true
    updateImportWarningIfNeeded()
  }

  func embeddedImage(for assetId: UUID) -> NSImage? {
    embeddedImageAssets[assetId]
  }

  func embeddedCGImage(for assetId: UUID) -> CGImage? {
    if let cached = embeddedImageCGImageCache[assetId] {
      return cached
    }
    guard let image = embeddedImageAssets[assetId],
          let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
      return nil
    }
    embeddedImageCGImageCache[assetId] = cgImage
    return cgImage
  }

  func restoreEmbeddedImageAssets(from snapshot: [UUID: Data]) {
    var restored: [UUID: NSImage] = [:]
    for (assetId, data) in snapshot {
      guard let image = NSImage(data: data) else { continue }
      restored[assetId] = image
    }
    embeddedImageAssets = restored
    embeddedImageSourceData = snapshot
    embeddedImageSnapshotCacheData = snapshot
    embeddedImageCGImageCache.removeAll()
    pruneUnusedEmbeddedAssets()
    updateImportWarningIfNeeded()
  }

  func embeddedImageAssetsSnapshotData() -> [UUID: Data] {
    let startedAt = CFAbsoluteTimeGetCurrent()
    pruneUnusedEmbeddedAssets()
    var result: [UUID: Data] = [:]
    let usedAssetIds = usedEmbeddedImageAssetIDs()
    for assetId in usedAssetIds {
      if let sourceData = embeddedImageSourceData[assetId] {
        result[assetId] = sourceData
        continue
      }
      if let cachedData = embeddedImageSnapshotCacheData[assetId] {
        result[assetId] = cachedData
        continue
      }
      guard let image = embeddedImageAssets[assetId] else { continue }
      if let tiffData = image.tiffRepresentation {
        embeddedImageSnapshotCacheData[assetId] = tiffData
        result[assetId] = tiffData
        continue
      }
      guard let pngData = Self.pngData(from: image) else { continue }
      embeddedImageSnapshotCacheData[assetId] = pngData
      result[assetId] = pngData
    }

    let durationMs = Int((CFAbsoluteTimeGetCurrent() - startedAt) * 1_000)
    let totalBytes = result.values.reduce(0) { $0 + $1.count }
    DiagnosticLogger.shared.log(.debug, .annotate, "Embedded image snapshot serialized", context: [
      "assets": "\(result.count)",
      "bytes": "\(totalBytes)",
      "durationMs": "\(durationMs)"
    ])
    return result
  }

  func pruneUnusedEmbeddedAssets() {
    let usedAssetIds = usedEmbeddedImageAssetIDs()
    embeddedImageAssets = embeddedImageAssets.filter { usedAssetIds.contains($0.key) }
    embeddedImageSourceData = embeddedImageSourceData.filter { usedAssetIds.contains($0.key) }
    embeddedImageSnapshotCacheData = embeddedImageSnapshotCacheData.filter { usedAssetIds.contains($0.key) }
    embeddedImageCGImageCache = embeddedImageCGImageCache.filter { usedAssetIds.contains($0.key) }
  }

  func consumeImportWarningMessage() {
    importWarningMessage = nil
  }

  private func resetCanvasForNewBaseImage(image: NSImage, url: URL?) {
    resetBackgroundCutoutState(markUnsaved: false)
    sourceImage = image
    sourceURL = url
    // Reset annotations for new image
    annotations.removeAll()
    embeddedImageAssets.removeAll()
    embeddedImageSourceData.removeAll()
    embeddedImageSnapshotCacheData.removeAll()
    embeddedImageCGImageCache.removeAll()
    selectedAnnotationId = nil
    editingTextAnnotationId = nil
    undoStack.removeAll()
    redoStack.removeAll()
    canUndo = false
    canRedo = false

    // Reset crop for new image
    cropRect = nil
    isCropActive = false
    editorMode = .annotate
    hasUnsavedChanges = false
    importWarningMessage = nil
    lastImportWarningSignature = nil
  }

  // MARK: - Background Cutout

  func toggleBackgroundCutout() {
    if isCutoutApplied {
      resetBackgroundCutoutState(markUnsaved: true)
    } else {
      applyBackgroundCutout()
    }
  }

  func applyBackgroundCutout() {
    guard !isCutoutProcessing else { return }

    guard canUseBackgroundCutout else {
      cutoutErrorMessage = ForegroundCutoutError.unsupportedOS.localizedDescription
      return
    }

    guard let sourceImage,
          let sourceCGImage = sourceImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
      cutoutErrorMessage = "Unable to load image data for background cutout."
      return
    }

    let operationID = UUID()
    activeCutoutOperationID = operationID
    clearCutoutAutoCropTracking()
    isCutoutProcessing = true
    cutoutErrorMessage = nil

    Task {
      do {
        let cutoutResult = try await ForegroundCutoutService.shared.extractForegroundResult(from: sourceCGImage)

        guard activeCutoutOperationID == operationID else { return }
        cutoutImage = NSImage(cgImage: cutoutResult.fullCanvasImage, size: sourceImage.size)
        isCutoutApplied = true
        isCutoutProcessing = false
        applyCutoutSuggestedAutoCropIfNeeded(
          cutoutResult: cutoutResult,
          sourceCGImage: sourceCGImage,
          autoCropEnabled: isBackgroundCutoutAutoCropEnabled
        )
        hasUnsavedChanges = true
      } catch {
        guard activeCutoutOperationID == operationID else { return }
        isCutoutProcessing = false

        if let localizedError = error as? LocalizedError, let message = localizedError.errorDescription {
          cutoutErrorMessage = message
        } else {
          cutoutErrorMessage = error.localizedDescription
        }
      }
    }
  }

  func resetBackgroundCutoutState(markUnsaved: Bool) {
    activeCutoutOperationID = nil
    isCutoutProcessing = false
    revertCutoutAutoCropIfNeeded()
    clearCutoutAutoCropTracking()
    cutoutImage = nil
    isCutoutApplied = false
    cutoutErrorMessage = nil

    if markUnsaved {
      hasUnsavedChanges = true
    }
  }

  /// Snapshot cutout state for Quick Access session caching.
  func cutoutSnapshot() -> (
    isApplied: Bool,
    cutoutImageData: Data?,
    didAutoApplyCrop: Bool,
    autoAppliedCropRect: CGRect?
  ) {
    guard isCutoutApplied, let cutoutImage else { return (false, nil, false, nil) }
    guard let cutoutImageData = Self.pngData(from: cutoutImage) else {
      DiagnosticLogger.shared.log(.warning, .annotate, "Cutout snapshot skipped: PNG encoding failed")
      return (false, nil, false, nil)
    }
    return (
      true,
      cutoutImageData,
      didCutoutAutoApplyCrop,
      didCutoutAutoApplyCrop ? cutoutAutoAppliedCropRect : nil
    )
  }

  /// Restore cutout state from Quick Access session cache.
  func restoreBackgroundCutout(
    isApplied: Bool,
    cutoutImageData: Data?,
    didAutoApplyCrop: Bool = false,
    autoAppliedCropRect: CGRect? = nil
  ) {
    activeCutoutOperationID = nil
    isCutoutProcessing = false
    cutoutErrorMessage = nil

    guard isApplied,
          let cutoutImageData,
          let restoredImage = NSImage(data: cutoutImageData) else {
      cutoutImage = nil
      isCutoutApplied = false
      clearCutoutAutoCropTracking()
      return
    }

    if let sourceImage {
      restoredImage.size = sourceImage.size
    }
    cutoutImage = restoredImage
    isCutoutApplied = true
    if didAutoApplyCrop, let autoAppliedCropRect {
      didCutoutAutoApplyCrop = true
      cutoutAutoAppliedCropRect = autoAppliedCropRect
    } else {
      clearCutoutAutoCropTracking()
    }
  }

  private func applyCutoutSuggestedAutoCropIfNeeded(
    cutoutResult: ForegroundCutoutResult,
    sourceCGImage: CGImage,
    autoCropEnabled: Bool
  ) {
    guard autoCropEnabled else { return }
    guard cropRect == nil, !isCropActive else { return }
    guard cutoutResult.autoCropDecision == .suggested,
          let suggestedPixelRect = cutoutResult.suggestedAutoCropRect else { return }

    let convertedRect = Self.convertAutoCropRectToImageCoordinates(
      pixelRectTopLeft: suggestedPixelRect,
      sourceImageSize: sourceImage?.size ?? .zero,
      sourcePixelSize: CGSize(width: sourceCGImage.width, height: sourceCGImage.height)
    )
    guard !convertedRect.isEmpty else { return }

    let clampedRect = constrainCropToImageBounds(convertedRect)
    cropRect = clampedRect
    didCutoutAutoApplyCrop = true
    cutoutAutoAppliedCropRect = clampedRect
  }

  private func revertCutoutAutoCropIfNeeded() {
    guard didCutoutAutoApplyCrop,
          let autoCropRect = cutoutAutoAppliedCropRect,
          let currentCropRect = cropRect else { return }
    if Self.rectApproximatelyEqual(currentCropRect, autoCropRect) {
      cropRect = nil
      isCropActive = false
    }
  }

  private func clearCutoutAutoCropTracking() {
    didCutoutAutoApplyCrop = false
    cutoutAutoAppliedCropRect = nil
  }

  private static func rectApproximatelyEqual(_ lhs: CGRect, _ rhs: CGRect, tolerance: CGFloat = 0.5) -> Bool {
    abs(lhs.origin.x - rhs.origin.x) <= tolerance &&
      abs(lhs.origin.y - rhs.origin.y) <= tolerance &&
      abs(lhs.width - rhs.width) <= tolerance &&
      abs(lhs.height - rhs.height) <= tolerance
  }

  private static func convertAutoCropRectToImageCoordinates(
    pixelRectTopLeft: CGRect,
    sourceImageSize: CGSize,
    sourcePixelSize: CGSize
  ) -> CGRect {
    guard sourceImageSize.width > 0,
          sourceImageSize.height > 0,
          sourcePixelSize.width > 0,
          sourcePixelSize.height > 0 else { return .zero }

    let scaleX = sourceImageSize.width / sourcePixelSize.width
    let scaleY = sourceImageSize.height / sourcePixelSize.height

    let x = pixelRectTopLeft.origin.x * scaleX
    let width = pixelRectTopLeft.width * scaleX
    let height = pixelRectTopLeft.height * scaleY
    let topY = pixelRectTopLeft.origin.y * scaleY
    let y = sourceImageSize.height - topY - height

    return CGRect(x: x, y: y, width: width, height: height)
  }

  private static func pngData(from image: NSImage) -> Data? {
    guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
    let bitmap = NSBitmapImageRep(cgImage: cgImage)
    return bitmap.representation(using: .png, properties: [:])
  }

  /// Load image and adjust size for Retina displays
  private static func loadImageWithCorrectScale(from url: URL) -> NSImage? {
    guard let image = SandboxFileAccessManager.shared.withScopedAccess(to: url, {
      NSImage(contentsOf: url)
    }) else { return nil }

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

  private static func readImageData(from url: URL) -> Data? {
    SandboxFileAccessManager.shared.withScopedAccess(to: url) {
      try? Data(contentsOf: url, options: .mappedIfSafe)
    }
  }

  private func usedEmbeddedImageAssetIDs() -> Set<UUID> {
    Set(annotations.compactMap { annotation -> UUID? in
      guard case .embeddedImage(let assetId) = annotation.type else { return nil }
      return assetId
    })
  }

  private func totalEmbeddedImagePixelCount(for assetIds: Set<UUID>) -> Int64 {
    assetIds.reduce(into: Int64(0)) { total, assetId in
      guard let image = embeddedImageAssets[assetId] else { return }
      if let rep = image.representations.first {
        total += Int64(rep.pixelsWide) * Int64(rep.pixelsHigh)
        return
      }
      if let cgImage = embeddedCGImage(for: assetId) {
        total += Int64(cgImage.width) * Int64(cgImage.height)
        return
      }
      total += Int64(max(image.size.width, 0) * max(image.size.height, 0))
    }
  }

  private func updateImportWarningIfNeeded() {
    let usedAssetIds = usedEmbeddedImageAssetIDs()
    let layerCount = usedAssetIds.count
    let totalPixelCount = totalEmbeddedImagePixelCount(for: usedAssetIds)

    let shouldWarnByCount = layerCount > Self.importedImageCountWarningThreshold
    let shouldWarnByPixels = totalPixelCount > Self.importedImagePixelBudgetWarningThreshold
    guard shouldWarnByCount || shouldWarnByPixels else {
      lastImportWarningSignature = nil
      importWarningMessage = nil
      return
    }

    let totalMegaPixels = Double(totalPixelCount) / 1_000_000
    let warning = "Performance warning: imported layers \(layerCount), total ~\(String(format: "%.1f", totalMegaPixels))MP. Canvas may be less smooth."
    let signature = "\(layerCount)-\(totalPixelCount)"

    guard signature != lastImportWarningSignature else { return }
    lastImportWarningSignature = signature
    importWarningMessage = warning
    DiagnosticLogger.shared.log(.warning, .annotate, "Imported image budget warning", context: [
      "layers": "\(layerCount)",
      "pixels": "\(totalPixelCount)",
      "thresholdPixels": "\(Self.importedImagePixelBudgetWarningThreshold)"
    ])
  }

  private func normalizedCanvasImageSize(for image: NSImage) -> CGSize {
    if image.size.width > 0, image.size.height > 0 {
      return image.size
    }

    guard let rep = image.representations.first else { return .zero }
    return CGSize(width: rep.pixelsWide, height: rep.pixelsHigh)
  }

  private func importedImagePlacementBounds(for imageSize: CGSize) -> CGRect {
    let drawingBounds: CGRect
    if let cropRect = cropRect, !isCropActive {
      drawingBounds = cropRect
    } else {
      drawingBounds = CGRect(origin: .zero, size: CGSize(width: imageWidth, height: imageHeight))
    }

    let maxWidth = max(1, drawingBounds.width * Self.importedImageMaxCoverage)
    let maxHeight = max(1, drawingBounds.height * Self.importedImageMaxCoverage)
    let scale = min(maxWidth / imageSize.width, maxHeight / imageSize.height, 1)
    let targetSize = CGSize(
      width: max(1, imageSize.width * scale),
      height: max(1, imageSize.height * scale)
    )

    let existingEmbeddedCount = annotations.reduce(into: 0) { count, annotation in
      if case .embeddedImage = annotation.type {
        count += 1
      }
    }
    let cascade = CGFloat(existingEmbeddedCount) * Self.importedImageCascadeStep
    let baseX = drawingBounds.midX - targetSize.width / 2 + cascade
    let baseY = drawingBounds.midY - targetSize.height / 2 - cascade

    let minX = drawingBounds.minX
    let maxX = drawingBounds.maxX - targetSize.width
    let minY = drawingBounds.minY
    let maxY = drawingBounds.maxY - targetSize.height

    let clampedX = min(max(baseX, minX), maxX)
    let clampedY = min(max(baseY, minY), maxY)

    return CGRect(origin: CGPoint(x: clampedX, y: clampedY), size: targetSize)
  }

  // MARK: - Undo/Redo Methods

  func saveState() {
    DiagnosticLogger.shared.log(.debug, .annotate, "Undo checkpoint", context: ["annotations": "\(annotations.count)"])
    undoStack.append(currentSnapshot())
    redoStack.removeAll()
    canUndo = true
    canRedo = false
    hasUnsavedChanges = true
  }

  func undo() {
    DiagnosticLogger.shared.log(.debug, .annotate, "Undo", context: ["stackDepth": "\(undoStack.count)"])
    guard let previous = undoStack.popLast() else { return }
    redoStack.append(currentSnapshot())
    applySnapshot(previous)
    canUndo = !undoStack.isEmpty
    canRedo = true
  }

  func redo() {
    DiagnosticLogger.shared.log(.debug, .annotate, "Redo", context: ["stackDepth": "\(redoStack.count)"])
    guard let next = redoStack.popLast() else { return }
    undoStack.append(currentSnapshot())
    applySnapshot(next)
    canUndo = true
    canRedo = !redoStack.isEmpty
  }

  private func currentSnapshot() -> AnnotationSnapshot {
    AnnotationSnapshot(
      annotations: annotations,
      embeddedImageAssets: embeddedImageAssets
    )
  }

  private func applySnapshot(_ snapshot: AnnotationSnapshot) {
    annotations = snapshot.annotations
    embeddedImageAssets = snapshot.embeddedImageAssets
    pruneUnusedEmbeddedAssets()
    updateImportWarningIfNeeded()

    if let selectedAnnotationId,
       !annotations.contains(where: { $0.id == selectedAnnotationId }) {
      self.selectedAnnotationId = nil
    }

    if let editingTextAnnotationId,
       !annotations.contains(where: { $0.id == editingTextAnnotationId }) {
      self.editingTextAnnotationId = nil
    }
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

  /// Collapse sidebar when user starts interacting with crop UI.
  func collapseSidebarForCropInteraction() {
    guard showSidebar else { return }
    shouldRestoreSidebarAfterCropInteraction = true
    withAnimation(.easeInOut(duration: 0.2)) {
      showSidebar = false
    }
  }

  /// Restore sidebar when crop interaction ends.
  func restoreSidebarAfterCropInteractionIfNeeded() {
    guard shouldRestoreSidebarAfterCropInteraction else { return }
    shouldRestoreSidebarAfterCropInteraction = false

    guard !showSidebar else { return }
    withAnimation(.easeInOut(duration: 0.2)) {
      showSidebar = true
    }
  }

  /// Activate crop tool from direct user interaction (toolbar/shortcut/canvas).
  func beginCropInteraction() {
    collapseSidebarForCropInteraction()
    selectedTool = .crop

    if cropRect == nil, hasImage {
      initializeCrop()
    } else if cropRect != nil {
      isCropActive = true
    }
  }

  /// Initialize crop to full image bounds
  func initializeCrop() {
    DiagnosticLogger.shared.log(.info, .annotate, "Crop initialized", context: ["imageSize": "\(Int(imageWidth))x\(Int(imageHeight))"])
    let fullImageRect = CGRect(origin: .zero, size: CGSize(width: imageWidth, height: imageHeight))
    cropRect = fullImageRect
    originalCropRect = fullImageRect  // Save original for aspect ratio calculations
    isCropActive = true
  }

  /// Apply crop (confirm) - keeps cropRect for export
  func applyCrop() {
    DiagnosticLogger.shared.log(.info, .annotate, "Crop applied", context: [
      "rect": cropRect.map { "\(Int($0.width))x\(Int($0.height))" } ?? "nil"
    ])
    if didCutoutAutoApplyCrop,
       let currentCropRect = cropRect,
       let autoCropRect = cutoutAutoAppliedCropRect,
       !Self.rectApproximatelyEqual(currentCropRect, autoCropRect) {
      clearCutoutAutoCropTracking()
    }
    isCropActive = false
    hasUnsavedChanges = true
    restoreSidebarAfterCropInteractionIfNeeded()
  }

  /// Reset unsaved changes flag after successful save
  func markAsSaved() {
    hasUnsavedChanges = false
  }

  /// Cancel crop and reset
  func cancelCrop() {
    DiagnosticLogger.shared.log(.info, .annotate, "Crop cancelled")
    cropRect = nil
    isCropActive = false
    clearCutoutAutoCropTracking()
    selectedTool = .selection
    restoreSidebarAfterCropInteractionIfNeeded()
  }

  /// Reset crop to nil
  func resetCrop() {
    cropRect = nil
    isCropActive = false
    clearCutoutAutoCropTracking()
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

    let constrainedRect = constrainCropToImageBounds(rect)
    if didCutoutAutoApplyCrop,
       let autoCropRect = cutoutAutoAppliedCropRect,
       !Self.rectApproximatelyEqual(constrainedRect, autoCropRect) {
      clearCutoutAutoCropTracking()
    }
    cropRect = constrainedRect
  }

  /// Update crop rect with bounds constraint
  func updateCropRect(_ newRect: CGRect) {
    let constrainedRect = constrainCropToImageBounds(newRect)
    if didCutoutAutoApplyCrop,
       let autoCropRect = cutoutAutoAppliedCropRect,
       !Self.rectApproximatelyEqual(constrainedRect, autoCropRect) {
      clearCutoutAutoCropTracking()
    }
    cropRect = constrainedRect
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
    case .arrow(let geometry):
      let updated = geometry.remapped(from: oldBounds, to: bounds)
      annotations[index].type = .arrow(updated)
      annotations[index].bounds = updated.bounds()
    case .line(let start, let end):
      annotations[index].type = .line(
        start: remapPoint(start, from: oldBounds, to: bounds),
        end: remapPoint(end, from: oldBounds, to: bounds)
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
      // Auto-size height based on wrapped text content, preserve width
      let currentBounds = annotations[index].bounds
      let currentWidth = currentBounds.width
      var newBounds = calculateTextBounds(
        text: text,
        fontSize: annotations[index].properties.fontSize,
        origin: currentBounds.origin,
        constrainedWidth: currentWidth
      )
      newBounds.origin.y = currentBounds.maxY - newBounds.height
      annotations[index].bounds = newBounds
    }
  }

  func updateArrowStyle(id: UUID, style: ArrowStyle) {
    guard let index = annotations.firstIndex(where: { $0.id == id }),
          case .arrow(let geometry) = annotations[index].type else { return }

    let updated = geometry.withStyle(style)
    annotations[index].type = .arrow(updated)
    annotations[index].bounds = updated.bounds()
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
        let currentBounds = annotations[index].bounds
        let currentWidth = currentBounds.width
        var newBounds = calculateTextBounds(
          text: content,
          fontSize: fontSize,
          origin: currentBounds.origin,
          constrainedWidth: currentWidth
        )
        newBounds.origin.y = currentBounds.maxY - newBounds.height
        annotations[index].bounds = newBounds
      }
    }
    if let strokeColor = strokeColor {
      annotations[index].properties.strokeColor = strokeColor
    }
    if let fillColor = fillColor {
      annotations[index].properties.fillColor = fillColor
    }
  }

  /// Calculate text bounds based on content and font size with word wrapping
  /// - Parameters:
  ///   - text: The text content
  ///   - fontSize: Desired font size (will be clamped to 8-144pt range)
  ///   - origin: Origin point for the text bounds
  ///   - constrainedWidth: Width to constrain text wrapping to (nil = auto-width from content)
  /// - Returns: Bounded CGRect with enforced maximum dimensions
  private func calculateTextBounds(
    text: String,
    fontSize: CGFloat,
    origin: CGPoint,
    constrainedWidth: CGFloat? = nil
  ) -> CGRect {
    AnnotateTextLayout.bounds(
      text: text,
      font: AnnotateTextLayout.font(size: fontSize),
      origin: origin,
      constrainedWidth: constrainedWidth
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

  var selectedArrowAnnotation: AnnotationItem? {
    guard let annotation = selectedAnnotation,
          case .arrow = annotation.type else {
      return nil
    }
    return annotation
  }

  var activeArrowStyle: ArrowStyle {
    if let annotation = selectedArrowAnnotation,
       case .arrow(let geometry) = annotation.type {
      return geometry.style
    }
    return arrowStyle
  }

  func setActiveArrowStyle(_ style: ArrowStyle) {
    if let annotation = selectedArrowAnnotation {
      updateArrowStyle(id: annotation.id, style: style)
    } else {
      arrowStyle = style
    }
  }

  var quickPropertiesSupportsArrowStyle: Bool {
    guard editorMode == .annotate,
          selectedTool != .crop else {
      return false
    }

    if let annotation = quickPropertiesAnnotation,
       case .arrow = annotation.type {
      return true
    }

    return quickPropertiesTool == .arrow
  }

  var quickArrowStyleBinding: Binding<ArrowStyle> {
    Binding(
      get: { [weak self] in
        self?.activeArrowStyle ?? .straight
      },
      set: { [weak self] newStyle in
        self?.setActiveArrowStyle(newStyle)
      }
    )
  }

  var quickPropertiesAnnotation: AnnotationItem? {
    guard editorMode == .annotate,
          selectedTool != .crop,
          let annotation = selectedAnnotation,
          annotation.type.supportsQuickPropertiesBar else {
      return nil
    }
    return annotation
  }

  var quickPropertiesMode: QuickPropertiesMode {
    if quickPropertiesAnnotation != nil {
      return .selectedItem
    }
    if quickPropertiesTool != nil {
      return .toolDefaults
    }
    return .hidden
  }

  var quickPropertiesTool: AnnotationToolType? {
    if let annotation = quickPropertiesAnnotation {
      return annotation.type.toolType
    }

    guard editorMode == .annotate,
          selectedTool != .crop,
          selectedTool.supportsQuickPropertiesBar else {
      return nil
    }
    return selectedTool
  }

  var showsQuickPropertiesBar: Bool {
    quickPropertiesMode != .hidden
  }

  var quickPropertiesContextTitle: String {
    guard let tool = quickPropertiesTool else { return "" }
    switch quickPropertiesMode {
    case .selectedItem:
      return "Selected \(tool.displayName)"
    case .toolDefaults:
      return "\(tool.displayName) Defaults"
    case .hidden:
      return ""
    }
  }

  var quickPropertiesSupportsStrokeColor: Bool {
    if let annotation = quickPropertiesAnnotation {
      return annotation.type.supportsQuickStrokeColor
    }
    return quickPropertiesTool?.supportsQuickStrokeColor ?? false
  }

  var quickPropertiesSupportsFill: Bool {
    if let annotation = quickPropertiesAnnotation {
      return annotation.type.supportsQuickFillColor
    }
    return quickPropertiesTool?.supportsQuickFillColor ?? false
  }

  var quickPropertiesSupportsStrokeWidth: Bool {
    if let annotation = quickPropertiesAnnotation {
      return annotation.type.supportsQuickStrokeWidth
    }
    return quickPropertiesTool?.supportsQuickStrokeWidth ?? false
  }

  var quickStrokeColorBinding: Binding<Color> {
    Binding(
      get: { [weak self] in
        guard let self else { return .red }
        return self.quickPropertiesAnnotation?.properties.strokeColor ?? self.strokeColor
      },
      set: { [weak self] newColor in
        guard let self else { return }
        if let selectedId = self.quickPropertiesAnnotation?.id {
          self.updateAnnotationProperties(id: selectedId, strokeColor: newColor)
        } else {
          self.strokeColor = newColor
        }
      }
    )
  }

  var quickFillColorBinding: Binding<Color> {
    Binding(
      get: { [weak self] in
        guard let self else { return .clear }
        return self.quickPropertiesAnnotation?.properties.fillColor ?? self.fillColor
      },
      set: { [weak self] newColor in
        guard let self else { return }
        if let selectedId = self.quickPropertiesAnnotation?.id {
          self.updateAnnotationProperties(id: selectedId, fillColor: newColor)
        } else {
          self.fillColor = newColor
        }
      }
    )
  }

  var quickStrokeWidthBinding: Binding<CGFloat> {
    Binding(
      get: { [weak self] in
        guard let self else { return 3 }
        return self.quickPropertiesAnnotation?.properties.strokeWidth ?? self.strokeWidth
      },
      set: { [weak self] newWidth in
        guard let self else { return }
        if let selectedId = self.quickPropertiesAnnotation?.id {
          self.updateAnnotationProperties(id: selectedId, strokeWidth: newWidth)
        } else {
          self.strokeWidth = newWidth
        }
      }
    )
  }

  func activateTool(_ tool: AnnotationToolType) {
    if editingTextAnnotationId != nil {
      commitTextEditing()
    }
    if tool != .selection {
      selectedAnnotationId = nil
    }
    selectedTool = tool
  }

  func deleteSelectedAnnotation() {
    guard let selectedId = selectedAnnotationId else { return }
    let annotation = annotations.first { $0.id == selectedId }
    DiagnosticLogger.shared.log(.debug, .annotate, "Delete annotation", context: [
      "id": selectedId.uuidString,
      "type": annotation.map { "\($0.type)" } ?? "unknown"
    ])
    saveState()
    annotations.removeAll { $0.id == selectedId }
    pruneUnusedEmbeddedAssets()
    updateImportWarningIfNeeded()
    selectedAnnotationId = nil
  }

  /// Commit the current text editing and exit edit mode
  func commitTextEditing() {
    guard let editingId = editingTextAnnotationId else { return }

    if let annotation = annotations.first(where: { $0.id == editingId }),
       case .text(let text) = annotation.type {
      let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
      if trimmed.isEmpty {
        saveState()
        annotations.removeAll { $0.id == editingId }
        selectedAnnotationId = nil
      } else {
        saveState()
        updateAnnotationText(id: editingId, text: trimmed)
      }
    }
    editingTextAnnotationId = nil
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
    case .arrow(let geometry):
      let updated = geometry.translatedBy(dx: dx, dy: dy)
      annotations[index].type = .arrow(updated)
      annotations[index].bounds = updated.bounds()
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

  private func remapPoint(_ point: CGPoint, from oldBounds: CGRect, to newBounds: CGRect) -> CGPoint {
    CGPoint(
      x: remapCoordinate(point.x, oldMin: oldBounds.minX, oldSize: oldBounds.width, newMin: newBounds.minX, newSize: newBounds.width),
      y: remapCoordinate(point.y, oldMin: oldBounds.minY, oldSize: oldBounds.height, newMin: newBounds.minY, newSize: newBounds.height)
    )
  }

  private func remapCoordinate(
    _ value: CGFloat,
    oldMin: CGFloat,
    oldSize: CGFloat,
    newMin: CGFloat,
    newSize: CGFloat
  ) -> CGFloat {
    guard oldSize != 0 else {
      return newMin + newSize / 2
    }

    let progress = (value - oldMin) / oldSize
    return newMin + progress * newSize
  }
}

enum AnnotateTextLayout {
  static let horizontalPadding: CGFloat = 4
  static let verticalPadding: CGFloat = 4
  static let minWidth: CGFloat = 30
  static let minContentWidth: CGFloat = 20
  static let defaultInitialWidth: CGFloat = 200
  static let maxWidth: CGFloat = 2000
  static let maxHeight: CGFloat = 2000

  static func font(size: CGFloat, fontName: String? = nil) -> NSFont {
    let clampedSize = min(max(size, 8), 144)

    if let fontName,
       let namedFont = NSFont(name: fontName, size: clampedSize) {
      return namedFont
    }

    return NSFont.systemFont(ofSize: clampedSize)
  }

  static func bounds(
    text: String,
    font: NSFont,
    origin: CGPoint,
    constrainedWidth: CGFloat? = nil
  ) -> CGRect {
    let finalWidth: CGFloat

    if let constrainedWidth = constrainedWidth {
      finalWidth = min(max(constrainedWidth, minWidth), maxWidth)
    } else {
      let measuredWidth = ceil(singleLineSize(for: text, font: font).width) + horizontalPadding * 2
      finalWidth = min(max(measuredWidth, defaultInitialWidth), maxWidth)
    }

    let contentWidth = max(finalWidth - horizontalPadding * 2, minContentWidth)
    let contentHeight = ceil(contentSize(for: text, font: font, constrainedWidth: contentWidth).height)
    let finalHeight = min(max(contentHeight + verticalPadding * 2, minimumHeight(for: font)), maxHeight)

    return CGRect(
      x: origin.x,
      y: origin.y,
      width: finalWidth,
      height: finalHeight
    )
  }

  static func textRect(for text: String, font: NSFont, in bounds: CGRect) -> CGRect {
    let contentWidth = max(bounds.width - horizontalPadding * 2, minContentWidth)
    let contentHeight = ceil(contentSize(for: text, font: font, constrainedWidth: contentWidth).height)
    let drawHeight = min(contentHeight, max(bounds.height, 0))
    let verticalInset = max((bounds.height - drawHeight) / 2, 0)

    return CGRect(
      x: bounds.minX + horizontalPadding,
      y: bounds.minY + verticalInset,
      width: contentWidth,
      height: drawHeight
    )
  }

  static func measuredHeight(text: String, font: NSFont, constrainedWidth: CGFloat) -> CGFloat {
    bounds(
      text: text,
      font: font,
      origin: .zero,
      constrainedWidth: constrainedWidth
    ).height
  }

  static func minimumHeight(for font: NSFont) -> CGFloat {
    ceil(font.ascender - font.descender + font.leading) + verticalPadding * 2
  }

  private static func singleLineSize(for text: String, font: NSFont) -> CGSize {
    (measurementText(for: text) as NSString).size(withAttributes: textAttributes(font: font))
  }

  private static func contentSize(for text: String, font: NSFont, constrainedWidth: CGFloat) -> CGSize {
    let rect = (measurementText(for: text) as NSString).boundingRect(
      with: CGSize(width: constrainedWidth, height: maxHeight),
      options: [.usesLineFragmentOrigin, .usesFontLeading],
      attributes: textAttributes(font: font)
    )
    return rect.size
  }

  private static func measurementText(for text: String) -> String {
    text.isEmpty ? " " : text
  }

  private static func textAttributes(font: NSFont) -> [NSAttributedString.Key: Any] {
    let paragraphStyle = NSMutableParagraphStyle()
    paragraphStyle.lineBreakMode = .byWordWrapping

    return [
      .font: font,
      .paragraphStyle: paragraphStyle
    ]
  }
}
