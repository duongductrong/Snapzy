//
//  AnnotateState.swift
//  Snapzy
//
//  Central state management for annotation window
//

import AppKit
import Combine
import CoreImage
import SwiftUI

/// Central state for annotation window
@MainActor
final class AnnotateState: ObservableObject {
  private struct AnnotationSnapshot {
    var annotations: [AnnotationItem]
    var embeddedImageAssets: [UUID: NSImage]
  }

  /// Snapshot of every piece of state mutated by an image rotation. Used as a dedicated
  /// undo entry so rotation undo never disturbs the annotation-only undo path.
  private struct RotationSnapshot {
    var sourceImage: NSImage?
    var cutoutImage: NSImage?
    var isCutoutApplied: Bool
    var embeddedImageAssets: [UUID: NSImage]
    var embeddedImageSourceData: [UUID: Data]
    var embeddedImageSnapshotCacheData: [UUID: Data]
    var annotations: [AnnotationItem]
    var cropRect: CGRect?
    var originalCropRect: CGRect?
    var cropAspectRatio: CropAspectRatio
    var isCropPortraitOrientation: Bool
    var didCutoutAutoApplyCrop: Bool
    var cutoutAutoAppliedCropRect: CGRect?
  }

  private enum UndoEntry {
    case annotations(AnnotationSnapshot)
    case rotation(RotationSnapshot)
  }

  private struct TextEditingUndoTransaction {
    let annotationId: UUID
    let snapshotBeforeEdit: AnnotationSnapshot
    let originalText: String
    var didRecordUndo: Bool = false
  }

  private struct CropInteractionContext {
    let selectedTool: AnnotationToolType
    let selectedAnnotationIds: Set<UUID>
    let cropRect: CGRect?
    let didCutoutAutoApplyCrop: Bool
    let cutoutAutoAppliedCropRect: CGRect?
  }

  private struct SharedAnnotationParameterDefaults: Codable {
    var strokeWidth: CGFloat?
    var cornerRadius: CGFloat?
    var fontSize: CGFloat?
    var watermarkOpacity: CGFloat?
    var watermarkRotationDegrees: CGFloat?
    var spotlightCornerRadius: CGFloat?
    var arrowStyle: String?
    var arrowType: String?
    var arrowBendDirection: String?
    var arrowStartHead: String?
    var arrowEndHead: String?
  }

  private struct PersistedAnnotationProperties: Codable {
    var strokeColor: RGBAColor
    var fillColor: RGBAColor
    var strokeWidth: CGFloat
    var cornerRadius: CGFloat
    var fontSize: CGFloat
    var fontName: String
    var opacity: CGFloat
    var rotationDegrees: CGFloat
    var watermarkStyle: String
    var spotlightOpacity: CGFloat?

    init?(_ properties: AnnotationProperties) {
      guard let strokeColor = RGBAColor(color: properties.strokeColor),
            let fillColor = RGBAColor(color: properties.fillColor) else {
        return nil
      }

      self.strokeColor = strokeColor
      self.fillColor = fillColor
      self.strokeWidth = properties.strokeWidth
      self.cornerRadius = properties.cornerRadius
      self.fontSize = properties.fontSize
      self.fontName = properties.fontName
      self.opacity = properties.opacity
      self.rotationDegrees = properties.rotationDegrees
      self.watermarkStyle = properties.watermarkStyle.rawValue
      self.spotlightOpacity = properties.spotlightOpacity
    }

    var annotationProperties: AnnotationProperties {
      AnnotationProperties(
        strokeColor: strokeColor.color,
        fillColor: fillColor.color,
        strokeWidth: strokeWidth,
        cornerRadius: cornerRadius,
        fontSize: fontSize,
        fontName: fontName,
        opacity: opacity,
        rotationDegrees: rotationDegrees,
        watermarkStyle: WatermarkStyle(rawValue: watermarkStyle) ?? .single,
        spotlightOpacity: spotlightOpacity ?? 0.5
      )
    }
  }

  private static let importedImageMaxCoverage: CGFloat = 0.7
  private static let importedImageCascadeStep: CGFloat = 24
  private static let importedImageCountWarningThreshold: Int = 8
  private static let importedImagePixelBudgetWarningThreshold: Int64 = 40_000_000
  private static let canvasPresetLimit: Int = 20
  private let canvasPresetStore: AnnotateCanvasPresetStore
  private let defaults: UserDefaults
  private let appliesDefaultCanvasPresetOnNewImages: Bool
  private var suppressCanvasEffectChangeTracking = false

  // MARK: - Source Image

  @Published var sourceImage: NSImage?
  @Published var sourceURL: URL?
  @Published private(set) var cutoutImage: NSImage?
  @Published private(set) var isCutoutApplied: Bool = false
  @Published private(set) var isCutoutProcessing: Bool = false
  @Published var cutoutErrorMessage: String?
  private var activeCutoutOperationID: UUID?
  @Published private(set) var isSensitiveRedactionScanning: Bool = false
  private var activeSensitiveRedactionOperationID: UUID?
  private var sensitiveRedactionToast: AppToastHandle?

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

  private var isQuickPropertiesSyncEnabled: Bool {
    AnnotateQuickPropertiesSyncPreference.isEnabled(userDefaults: defaults)
  }

  // MARK: - Tool State

  @Published var selectedTool: AnnotationToolType = .selection {
    didSet {
      // If user leaves crop by switching tool, restore sidebar if crop had auto-collapsed it.
      if oldValue == .crop, selectedTool != .crop {
        restoreSidebarAfterCropInteractionIfNeeded()
      }
      syncActiveToolProperties()
    }
  }
  @Published var strokeWidth: CGFloat = 3
  @Published var strokeColor: Color = .red
  @Published var fillColor: Color = .clear
  @Published var rectangleCornerRadius: CGFloat = 0
  @Published var blurType: BlurType = .pixelated
  @Published var arrowStyle: ArrowStyle = .straight
  @Published var arrowType: ArrowType = .tapered
  @Published var arrowBendDirection: ArrowBendDirection = .primary
  @Published var arrowStartHead: ArrowEndpointStyle = .none
  @Published var arrowEndHead: ArrowEndpointStyle = .arrow
  @Published var watermarkText: String = "Snapzy"
  @Published var spotlightOpacity: CGFloat = 0.5
  @Published private var annotationToolProperties: [AnnotationToolType: AnnotationProperties] = [:]
  private var isQuickPropertiesGestureEditing = false
  private var quickPropertiesGestureUndoSnapshot: AnnotationSnapshot?
  private var sharedAnnotationColor: Color?
  private var sharedAnnotationParameterDefaults = SharedAnnotationParameterDefaults()
  /// New text starts as a natural-width line. Resizing it switches that item
  /// to a fixed width so deliberate wrapping is never overwritten while typing.
  private var autoSizingTextAnnotationIDs: Set<UUID> = []

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

  enum DragToAppPreparationState: Equatable {
    case unavailable
    case preparing
    case ready

    var isInteractive: Bool {
      self == .ready
    }
  }

  @Published var editorMode: EditorMode = .annotate

  // MARK: - UI State

  @Published var showSidebar: Bool = false
  @Published var zoomLevel: CGFloat = 1.0
  @Published var isPinned: Bool = false
  @Published private(set) var dragToAppPreparationState: DragToAppPreparationState

  // MARK: - Combine Images

  static let combineBaseLayerID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!

  @Published private(set) var isCombineMode = false
  @Published private(set) var combineMode: CombineImagesMode = .autoStitch
  @Published private(set) var combineDirection: CombineImagesDirection = .smart
  @Published private(set) var combineResolvedDirection: CombineImagesDirection = .horizontal
  @Published private(set) var combineGap: CGFloat = 0
  @Published private(set) var combineContentBounds: CGRect = .zero
  @Published var frozenCombineContentBounds: CGRect?
  let combineSnapTolerance: CGFloat = 14

  /// True when this editor session was opened manually (empty window / Combine picker).
  /// Its sourceURL points at a user-picked file, not a Snapzy capture, so combine saves
  /// must never silently overwrite it. Set once at window init; not an image property.
  var isManualImportSession = false

  private var freeCombineBoundsByAnnotationID: [UUID: CGRect] = [:]

  var effectiveContentBounds: CGRect {
    guard isCombineMode else { return sourceImageBounds }
    return frozenCombineContentBounds ?? combineContentBounds
  }

  var combineImageCount: Int {
    1 + annotations.reduce(into: 0) { count, annotation in
      if case .embeddedImage = annotation.type { count += 1 }
    }
  }

  func moveCombineImage(at index: Int, by offset: Int) {
    guard isCombineMode, offset != 0, let sourceImage else { return }
    let slots = annotations.compactMap { annotation -> UUID? in
      guard case .embeddedImage(let assetID) = annotation.type else { return nil }
      return assetID
    }
    var orderedImages = [sourceImage] + slots.compactMap { embeddedImageAssets[$0] }
    guard orderedImages.count == slots.count + 1,
          orderedImages.indices.contains(index) else { return }
    let destination = index + offset
    guard orderedImages.indices.contains(destination) else { return }

    pushRotationUndo(currentRotationSnapshot())
    let moved = orderedImages.remove(at: index)
    orderedImages.insert(moved, at: destination)
    self.sourceImage = orderedImages[0]
    for (slotIndex, assetID) in slots.enumerated() {
      embeddedImageAssets[assetID] = orderedImages[slotIndex + 1]
      embeddedImageSourceData.removeValue(forKey: assetID)
      embeddedImageSnapshotCacheData.removeValue(forKey: assetID)
      embeddedImageCGImageCache.removeValue(forKey: assetID)
    }
    hasUnsavedChanges = true
    refreshCombineLayout()
  }

  func activateCombineMode(preferredMode: CombineImagesMode = .autoStitch) {
    guard hasImage else { return }
    if !isCombineMode {
      isCombineMode = true
      showSidebar = true
      selectedTool = .selection
      captureCurrentFreeCombineBounds()
    }
    setCombineMode(preferredMode)
  }

  func deactivateCombineMode() {
    guard isCombineMode else { return }
    isCombineMode = false
    combineContentBounds = sourceImageBounds
    frozenCombineContentBounds = nil
  }

  func setCombineMode(_ mode: CombineImagesMode) {
    guard isCombineMode else { return }
    guard combineMode != mode else {
      refreshCombineLayout()
      return
    }

    if combineMode == .freeCanvas {
      captureCurrentFreeCombineBounds()
    }
    combineMode = mode
    switch mode {
    case .autoStitch:
      applyAutomaticCombineLayout()
    case .freeCanvas:
      restoreFreeCombineBounds()
    }
  }

  func setCombineDirection(_ direction: CombineImagesDirection) {
    combineDirection = direction
    if isCombineMode, combineMode == .autoStitch {
      applyAutomaticCombineLayout()
    }
  }

  func setCombineGap(_ gap: CGFloat) {
    combineGap = max(0, gap)
    if isCombineMode, combineMode == .autoStitch {
      applyAutomaticCombineLayout()
    } else if isCombineMode {
      updateCombineContentBounds()
    }
  }

  func refreshCombineLayout() {
    guard isCombineMode else { return }
    if combineMode == .autoStitch {
      applyAutomaticCombineLayout()
    } else {
      updateCombineContentBounds()
    }
  }

  /// Capture the active combine session's layout flags for persistence.
  /// Returns nil when not in combine mode. Source pixels persist separately via
  /// embedded image assets, so only the layout flags are captured here.
  func combineSessionSnapshot() -> CombineSessionSnapshot? {
    guard isCombineMode else { return nil }
    return CombineSessionSnapshot(
      mode: combineMode,
      direction: combineDirection,
      gap: combineGap,
      freeBoundsByAnnotationID: freeCombineBoundsByAnnotationID
    )
  }

  /// Restore a persisted combine session. Must run AFTER annotations and embedded assets
  /// are restored. Bypasses `activateCombineMode()` on purpose — that method's side effects
  /// (capturing current bounds, sidebar/tool changes) are for interactive activation, not
  /// deterministic rehydration. Does not touch `hasUnsavedChanges` or the undo stack.
  func restoreCombineSession(_ snapshot: CombineSessionSnapshot) {
    guard hasImage else { return }
    isCombineMode = true
    // Surface the sidebar so the combine controls (mode/direction/gap) are visible on
    // reopen — matches interactive activation and lets the user keep adjusting the stitch.
    showSidebar = true
    combineMode = snapshot.mode
    combineDirection = snapshot.direction
    combineGap = max(0, snapshot.gap)
    freeCombineBoundsByAnnotationID = snapshot.freeBoundsByAnnotationID
    // Deterministic: autoStitch recomputes layout from annotation order/direction/gap;
    // freeCanvas derives content bounds from the restored annotation bounds.
    refreshCombineLayout()
  }

  static let minimumZoomLevel: CGFloat = 0.25
  static let defaultMaximumZoomLevel: CGFloat = 4.0
  static let hardMaximumZoomLevel: CGFloat = 16.0
  static let zoomPresetPercents = [25, 50, 75, 100, 125, 150, 200, 300, 400, 600, 800, 1200, 1600]

  func toggleSidebarVisibility() {
    guard editorMode != .preview else { return }
    withAnimation(.easeInOut(duration: 0.2)) {
      showSidebar.toggle()
    }
  }

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

  var actualPixelZoomLevel: CGFloat {
    guard fitScale > 0 else { return 1.0 }
    return clampedZoom(1.0 / fitScale)
  }

  var currentDisplayedZoomPercent: Int {
    Int((fitScale * zoomLevel * 100).rounded())
  }

  var zoomMenuPresetPercents: [Int] {
    let maxDisplayedPercent = max(
      25,
      Int((effectiveMaximumZoomLevel * fitScale * 100).rounded(.down) / 25) * 25
    )

    var options = Self.zoomPresetPercents.filter {
      $0 <= maxDisplayedPercent
    }

    if maxDisplayedPercent > (options.last ?? 0) {
      options.append(maxDisplayedPercent)
    }

    return options
  }

  func zoomLevel(forDisplayedPercent percent: Int) -> CGFloat {
    let normalizedFitScale = max(fitScale, 0.0001)
    return clampedZoom(CGFloat(percent) / 100 / normalizedFitScale)
  }

  /// Clamp a zoom level to the valid range
  func clampedZoom(_ level: CGFloat) -> CGFloat {
    min(max(level, effectiveZoomRange.lowerBound), effectiveZoomRange.upperBound)
  }

  // MARK: - Pan State (for zoomed canvas navigation)

  /// Viewport pan offset (points). Applied alongside scaleEffect.
  @Published var panOffset: CGSize = .zero

  /// Keeps the canvas in a direct manipulation mode while the hand button is active.
  @Published var isCanvasPanningMode = false

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
      isCanvasPanningMode = false
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
      // Pre-cache image-backed backgrounds when style changes.
      switch backgroundStyle {
      case .wallpaper(let url), .blurred(let url):
        loadBackgroundImage(from: url)
      default:
        cachedBackgroundImage = nil
        cachedBlurredImage = nil
        cachedBackgroundURL = nil
        loadingBackgroundURL = nil
      }

      if backgroundStyle.supportsBlurredBackgroundEffect == false && isBlurredBackgroundEnabled {
        isBlurredBackgroundEnabled = false
      } else {
        refreshCachedBlurredBackgroundImage()
      }
      handleCanvasEffectDidChange()
    }
  }

  @Published var isBlurredBackgroundEnabled: Bool = false {
    didSet {
      refreshCachedBlurredBackgroundImage()
      handleCanvasEffectDidChange()
    }
  }

  @Published var blurredBackgroundEffect: BlurredBackgroundEffect = .soft {
    didSet {
      refreshCachedBlurredBackgroundImage()
      handleCanvasEffectDidChange()
    }
  }

  /// Cached background image for performance (avoids disk reads during slider drag)
  /// IMPORTANT: @Published to trigger SwiftUI re-render when async load completes
  @Published private(set) var cachedBackgroundImage: NSImage?

  /// Cached pre-computed blurred image (avoids real-time blur on every frame)
  @Published private(set) var cachedBlurredImage: NSImage?

  /// URL represented by the current cached background image.
  private var cachedBackgroundURL: URL?

  /// Track the URL being loaded to prevent race conditions
  private var loadingBackgroundURL: URL?

  var isBlurredBackgroundEffectActive: Bool {
    guard backgroundStyle.supportsBlurredBackgroundEffect else { return false }
    if case .blurred = backgroundStyle {
      return true
    }
    return isBlurredBackgroundEnabled
  }

  private var activeBlurredBackgroundURL: URL? {
    guard isBlurredBackgroundEffectActive else { return nil }
    return backgroundStyle.blurredEffectImageURL
  }

  private func loadBackgroundImage(from url: URL) {
    // Skip preset URLs (handled via gradient)
    guard url.scheme != "preset" else {
      cachedBackgroundImage = nil
      cachedBlurredImage = nil
      cachedBackgroundURL = nil
      loadingBackgroundURL = nil
      return
    }

    // Track which URL we're loading to prevent race conditions
    loadingBackgroundURL = url
    cachedBackgroundImage = nil
    cachedBlurredImage = nil
    cachedBackgroundURL = nil

    // Use preview cache (2048px) instead of full resolution for performance
    SystemWallpaperManager.shared.loadPreviewImage(for: url) { [weak self] image in
      Task { @MainActor in
        // Race condition guard: only apply if this is still the intended URL
        guard self?.loadingBackgroundURL == url else { return }

        self?.cachedBackgroundImage = image
        self?.cachedBackgroundURL = url
        self?.loadingBackgroundURL = nil

        // Pre-compute blurred variant if the selected background uses this effect.
        if self?.activeBlurredBackgroundURL == url {
          self?.cachedBlurredImage = self?.makeBlurredBackgroundImage(from: image)
        } else {
          self?.cachedBlurredImage = nil
        }
      }
    }
  }

  private func refreshCachedBlurredBackgroundImage() {
    guard let url = activeBlurredBackgroundURL else {
      cachedBlurredImage = nil
      return
    }
    guard let cachedBackgroundImage = cachedBackgroundImage(for: url) else {
      cachedBlurredImage = nil
      return
    }
    cachedBlurredImage = makeBlurredBackgroundImage(from: cachedBackgroundImage)
  }

  func backgroundImage(for url: URL) -> NSImage? {
    if cachedBackgroundURL == url, let cachedBackgroundImage {
      return cachedBackgroundImage
    }
    return SandboxFileAccessManager.shared.withScopedAccess(to: url, {
      NSImage(contentsOf: url)
    })
  }

  func cachedBackgroundImage(for url: URL) -> NSImage? {
    guard cachedBackgroundURL == url else { return nil }
    return cachedBackgroundImage
  }

  func cachedBlurredBackgroundImage(for url: URL) -> NSImage? {
    guard activeBlurredBackgroundURL == url else { return nil }
    return cachedBlurredImage
  }

  func blurredBackgroundImage(for url: URL) -> NSImage? {
    if activeBlurredBackgroundURL == url,
       let cachedBlurredImage {
      return cachedBlurredImage
    }
    return makeBlurredBackgroundImage(from: backgroundImage(for: url))
  }

  /// Apply CI filters to an NSImage once, then cache the result for preview/export reuse.
  func makeBlurredBackgroundImage(from image: NSImage?) -> NSImage? {
    guard let image = image,
          let tiffData = image.tiffRepresentation,
          let ciImage = CIImage(data: tiffData) else { return nil }

    let blurFilter = CIFilter(name: "CIGaussianBlur")
    blurFilter?.setValue(ciImage.clampedToExtent(), forKey: kCIInputImageKey)
    blurFilter?.setValue(blurredBackgroundEffect.blurRadius, forKey: kCIInputRadiusKey)

    guard let blurredOutput = blurFilter?.outputImage else { return nil }

    let colorFilter = CIFilter(name: "CIColorControls")
    colorFilter?.setValue(blurredOutput, forKey: kCIInputImageKey)
    colorFilter?.setValue(blurredBackgroundEffect.saturation, forKey: kCIInputSaturationKey)
    colorFilter?.setValue(blurredBackgroundEffect.brightness, forKey: kCIInputBrightnessKey)

    guard let output = colorFilter?.outputImage else { return nil }

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
  @Published var cornerRadius: CGFloat = AnnotateCanvasDefaults.cornerRadius {
    didSet {
      handleCanvasEffectDidChange()
    }
  }
  @Published var imageAlignment: ImageAlignment = .center {
    didSet {
      handleCanvasEffectDidChange()
    }
  }
  @Published var aspectRatio: AspectRatioOption = .auto {
    didSet {
      handleCanvasEffectDidChange()
    }
  }
  @Published var aspectRatioOrientation: AspectRatioOrientation = .horizontal {
    didSet {
      handleCanvasEffectDidChange()
    }
  }
  @Published private(set) var canvasPresets: [AnnotateCanvasPreset] = []
  @Published var selectedCanvasPresetId: UUID?
  @Published private(set) var isSelectedCanvasPresetDirty: Bool = false
  @Published private(set) var defaultCanvasPresetId: UUID?
  @Published private(set) var isDefaultCanvasPresetAutoApplied = false

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

  var defaultCanvasPreset: AnnotateCanvasPreset? {
    guard let defaultCanvasPresetId else { return nil }
    return canvasPresets.first(where: { $0.id == defaultCanvasPresetId })
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

  var requiresRenderedOutputForSharing: Bool {
    hasUnsavedChanges || isDefaultCanvasPresetAutoApplied
  }

  var nextSuggestedCanvasPresetName: String {
    "Preset \(canvasPresets.count + 1)"
  }

  var isNoneCanvasEffectsActive: Bool {
    backgroundStyle == .none
      && abs(padding) <= 0.0001
      && abs(shadowIntensity) <= 0.0001
      && abs(cornerRadius) <= 0.0001
      && aspectRatio == .auto
  }

  var canvasEffectsSnapshot: AnnotationCanvasEffects {
    AnnotationCanvasEffects(
      backgroundStyle: backgroundStyle,
      isBlurredBackgroundEnabled: isBlurredBackgroundEnabled,
      blurredBackgroundEffect: blurredBackgroundEffect,
      padding: padding,
      inset: inset,
      autoBalance: autoBalance,
      shadowIntensity: shadowIntensity,
      cornerRadius: cornerRadius,
      imageAlignment: imageAlignment,
      aspectRatio: aspectRatio,
      aspectRatioOrientation: aspectRatioOrientation
    )
  }

  func applyCanvasEffects(
    _ effects: AnnotationCanvasEffects,
    preferredSelectedCanvasPresetId: UUID? = nil,
    preferredPresetDirtyState: Bool? = nil
  ) {
    withCanvasEffectChangeTrackingSuspended {
      backgroundStyle = effects.backgroundStyle
      isBlurredBackgroundEnabled = effects.isBlurredBackgroundEnabled && effects.backgroundStyle.supportsBlurredBackgroundEffect
      blurredBackgroundEffect = effects.blurredBackgroundEffect
      padding = effects.padding
      inset = effects.inset
      autoBalance = effects.autoBalance
      shadowIntensity = effects.shadowIntensity
      cornerRadius = effects.cornerRadius
      imageAlignment = effects.imageAlignment
      aspectRatio = effects.aspectRatio
      aspectRatioOrientation = effects.aspectRatioOrientation
    }

    restoreCanvasPresetSelection(
      preferredSelectedCanvasPresetId: preferredSelectedCanvasPresetId,
      preferredPresetDirtyState: preferredPresetDirtyState
    )
    isDefaultCanvasPresetAutoApplied = false

    previewPadding = nil
    previewInset = nil
    previewShadowIntensity = nil
    previewCornerRadius = nil
  }

  func loadCanvasPresets() {
    canvasPresets = canvasPresetStore.loadPresets()
    defaultCanvasPresetId = canvasPresetStore.loadDefaultPresetId(validating: canvasPresets)
    if let selectedCanvasPresetId,
       canvasPresets.contains(where: { $0.id == selectedCanvasPresetId }) == false {
      self.selectedCanvasPresetId = nil
    }
    recomputeCanvasPresetDirtyState()
  }

  func isDefaultCanvasPreset(_ preset: AnnotateCanvasPreset) -> Bool {
    defaultCanvasPresetId == preset.id
  }

  func toggleDefaultCanvasPreset(id: UUID) {
    if defaultCanvasPresetId == id {
      clearDefaultCanvasPreset()
    } else {
      setDefaultCanvasPreset(id: id)
    }
  }

  func setDefaultCanvasPreset(id: UUID) {
    guard canvasPresets.contains(where: { $0.id == id }) else { return }
    defaultCanvasPresetId = id
    canvasPresetStore.saveDefaultPresetId(id)
  }

  func clearDefaultCanvasPreset() {
    defaultCanvasPresetId = nil
    canvasPresetStore.clearDefaultPresetId()
  }

  func resetCanvasEffectsToNone() {
    let beforePayload = currentCanvasPresetPayload()
    withCanvasEffectChangeTrackingSuspended {
      backgroundStyle = .none
      isBlurredBackgroundEnabled = false
      blurredBackgroundEffect = .soft
      padding = 0
      shadowIntensity = 0
      cornerRadius = 0
      aspectRatio = .auto
      aspectRatioOrientation = .horizontal
      previewPadding = nil
      previewShadowIntensity = nil
      previewCornerRadius = nil
    }
    selectedCanvasPresetId = nil
    isSelectedCanvasPresetDirty = false
    isDefaultCanvasPresetAutoApplied = false

    if let beforePayload,
       let afterPayload = currentCanvasPresetPayload(),
       beforePayload.approximatelyEquals(afterPayload) == false {
      hasUnsavedChanges = true
    }
  }

  func applyCanvasPreset(_ preset: AnnotateCanvasPreset, marksUnsaved: Bool = true) {
    let beforePayload = currentCanvasPresetPayload()
    withCanvasEffectChangeTrackingSuspended {
      let presetBackgroundStyle = preset.payload.backgroundStyle.toBackgroundStyle()
      backgroundStyle = presetBackgroundStyle
      isBlurredBackgroundEnabled = preset.payload.isBlurredBackgroundEnabled &&
        presetBackgroundStyle.supportsBlurredBackgroundEffect
      blurredBackgroundEffect = preset.payload.blurredBackgroundEffect
      padding = preset.payload.padding
      shadowIntensity = preset.payload.shadowIntensity
      cornerRadius = preset.payload.cornerRadius
      aspectRatio = preset.payload.aspectRatio
      aspectRatioOrientation = preset.payload.aspectRatioOrientation
      previewPadding = nil
      previewShadowIntensity = nil
      previewCornerRadius = nil
    }
    selectedCanvasPresetId = preset.id
    isSelectedCanvasPresetDirty = false

    let afterPayload = currentCanvasPresetPayload()
    let didChange: Bool
    if let beforePayload, let afterPayload {
      didChange = beforePayload.approximatelyEquals(afterPayload) == false
    } else {
      didChange = beforePayload != nil || afterPayload != nil
    }

    if marksUnsaved && didChange {
      isDefaultCanvasPresetAutoApplied = false
    } else if !marksUnsaved {
      isDefaultCanvasPresetAutoApplied = didChange
    }

    if marksUnsaved && didChange {
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

    if defaultCanvasPresetId == id {
      clearDefaultCanvasPreset()
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
    isDefaultCanvasPresetAutoApplied = false
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
      isBlurredBackgroundEnabled: isBlurredBackgroundEffectActive,
      blurredBackgroundEffect: blurredBackgroundEffect,
      padding: padding,
      shadowIntensity: shadowIntensity,
      cornerRadius: cornerRadius,
      aspectRatio: aspectRatio,
      aspectRatioOrientation: aspectRatioOrientation
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

  private func applyDefaultCanvasPresetForNewImageIfNeeded() {
    guard appliesDefaultCanvasPresetOnNewImages,
          let defaultCanvasPreset else { return }
    applyCanvasPreset(defaultCanvasPreset, marksUnsaved: false)
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
  var sourceImageBounds: CGRect {
    CGRect(origin: .zero, size: CGSize(width: imageWidth, height: imageHeight))
  }
  var activeAnnotationBounds: CGRect {
    cropRect?.standardized ?? sourceImageBounds
  }

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
  private var isSynchronizingSelection = false
  @Published var selectedAnnotationId: UUID? {
    didSet {
      guard !isSynchronizingSelection else { return }
      selectedAnnotationIds = selectedAnnotationId.map { Set([$0]) } ?? []
    }
  }
  @Published private(set) var selectedAnnotationIds: Set<UUID> = []
  @Published var editingTextAnnotationId: UUID? {
    didSet {
      if editingTextAnnotationId == nil {
        textEditingUndoTransaction = nil
      }
    }
  }

  // MARK: - Counter Tool State (derived from annotations, not stored)

  // MARK: - Crop State

  /// Current crop rectangle in image coordinates (nil = no crop, full image)
  @Published var cropRect: CGRect?
  /// Original crop rect when crop mode started (used as base for aspect ratio calculations)
  private var originalCropRect: CGRect?
  /// Context to restore after leaving crop mode.
  private var cropInteractionContext: CropInteractionContext?
  /// Whether crop mode is actively being edited
  @Published var isCropActive: Bool = false
  /// Selected aspect ratio for crop
  @Published var cropAspectRatio: CropAspectRatio = .free
  /// Whether crop aspect ratio is in portrait orientation
  @Published var isCropPortraitOrientation: Bool = false
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
  var isCropInteractionActive: Bool { selectedTool == .crop && isCropActive }

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

  private var undoStack: [UndoEntry] = []
  private var redoStack: [UndoEntry] = []
  private var textEditingUndoTransaction: TextEditingUndoTransaction?

  init(
    image: NSImage,
    url: URL,
    quickAccessItemId: UUID? = nil,
    cloudURL: URL? = nil,
    cloudKey: String? = nil,
    isCloudStale: Bool = false,
    defaults: UserDefaults = .standard,
    canvasPresetStore: AnnotateCanvasPresetStore? = nil,
    appliesDefaultCanvasPresetOnNewImages: Bool = true
  ) {
    self.defaults = defaults
    self.canvasPresetStore = canvasPresetStore ?? AnnotateCanvasPresetStore.shared
    self.appliesDefaultCanvasPresetOnNewImages = appliesDefaultCanvasPresetOnNewImages
    self.sourceImage = image
    self.sourceURL = url
    self.quickAccessItemId = quickAccessItemId
    self.cloudURL = cloudURL
    self.cloudKey = cloudKey
    self.isCloudStale = isCloudStale
    self.dragToAppPreparationState = .ready
    loadSharedAnnotationColor()
    loadSharedAnnotationParameterDefaults()
    loadAnnotationToolProperties()
    loadCanvasPresets()
    applyDefaultCanvasPresetForNewImageIfNeeded()
  }

  /// Empty initializer for drag-drop workflow
  init(
    defaults: UserDefaults = .standard,
    canvasPresetStore: AnnotateCanvasPresetStore? = nil,
    appliesDefaultCanvasPresetOnNewImages: Bool = true
  ) {
    self.defaults = defaults
    self.canvasPresetStore = canvasPresetStore ?? AnnotateCanvasPresetStore.shared
    self.appliesDefaultCanvasPresetOnNewImages = appliesDefaultCanvasPresetOnNewImages
    self.sourceImage = nil
    self.sourceURL = nil
    self.quickAccessItemId = nil
    self.cloudURL = nil
    self.cloudKey = nil
    self.dragToAppPreparationState = .unavailable
    loadSharedAnnotationColor()
    loadSharedAnnotationParameterDefaults()
    loadAnnotationToolProperties()
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

  /// Replace the backing screenshot while keeping editable annotations.
  /// Used by inline area annotate when the selected region moves or resizes.
  func replaceSourceImagePreservingAnnotations(_ image: NSImage, annotationOffset: CGPoint = .zero) {
    sourceImage = image
    if annotationOffset != .zero {
      translateAnnotations(dx: annotationOffset.x, dy: annotationOffset.y)
    }
    cutoutImage = nil
    isCutoutApplied = false
    isCutoutProcessing = false
    cutoutErrorMessage = nil
    activeCutoutOperationID = nil
    cropRect = nil
    originalCropRect = nil
    cropInteractionContext = nil
    isCropActive = false
    selectedTool = selectedTool == .crop ? .selection : selectedTool
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

    activateCombineMode(preferredMode: combineMode)

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
    freeCombineBoundsByAnnotationID[item.id] = placementBounds
    refreshCombineLayout()
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
    // Prune only when annotations are already populated. Controllers restore assets BEFORE
    // assigning annotations, so pruning here would key off an empty annotation list and wipe
    // every restored asset — collapsing a stitched combine session back to the base image.
    // The persisted snapshot only ever contains in-use assets, so skipping prune is safe.
    if !annotations.isEmpty {
      pruneUnusedEmbeddedAssets()
    }
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

  func setDragToAppPreparationState(_ newState: DragToAppPreparationState) {
    guard dragToAppPreparationState != newState else { return }
    dragToAppPreparationState = newState
  }

  private func resetCanvasForNewBaseImage(image: NSImage, url: URL?) {
    let shouldApplyDefaultPreset = !hasImage
    resetBackgroundCutoutState(markUnsaved: false)
    cancelSensitiveRedactionScan()
    sourceImage = image
    sourceURL = url
    // Reset annotations for new image
    annotations.removeAll()
    embeddedImageAssets.removeAll()
    embeddedImageSourceData.removeAll()
    embeddedImageSnapshotCacheData.removeAll()
    embeddedImageCGImageCache.removeAll()
    isCombineMode = false
    combineMode = .autoStitch
    combineDirection = .smart
    combineResolvedDirection = .horizontal
    combineGap = 0
    combineContentBounds = CGRect(origin: .zero, size: image.size)
    frozenCombineContentBounds = nil
    freeCombineBoundsByAnnotationID.removeAll()
    selectedAnnotationId = nil
    editingTextAnnotationId = nil
    undoStack.removeAll()
    redoStack.removeAll()
    canUndo = false
    canRedo = false

    // Reset crop for new image
    cropRect = nil
    originalCropRect = nil
    cropInteractionContext = nil
    isCropActive = false
    editorMode = .annotate
    hasUnsavedChanges = false
    isDefaultCanvasPresetAutoApplied = false
    importWarningMessage = nil
    lastImportWarningSignature = nil
    dragToAppPreparationState = url == nil ? .preparing : .ready

    if shouldApplyDefaultPreset {
      applyDefaultCanvasPresetForNewImageIfNeeded()
    }
  }

  // MARK: - Background Cutout

  func autoRedactSensitiveData() {
    guard !isSensitiveRedactionScanning else { return }
    guard let image = effectiveSourceImage else {
      showSensitiveRedactionToast(message: L10n.AnnotateUI.autoRedactionImageUnavailable, style: .warning)
      return
    }

    if editingTextAnnotationId != nil {
      commitTextEditing()
    }

    let operationID = UUID()
    activeSensitiveRedactionOperationID = operationID
    isSensitiveRedactionScanning = true
    sensitiveRedactionToast = AppToastManager.shared.show(
      message: L10n.AnnotateUI.autoRedactionScanning,
      style: .info,
      duration: nil,
      variant: .compact,
      iconMode: .spinner
    )

    Task {
      do {
        let result = try await AnnotateSensitiveRedactionService.shared.detectRegions(in: image)
        guard activeSensitiveRedactionOperationID == operationID else { return }

        isSensitiveRedactionScanning = false
        activeSensitiveRedactionOperationID = nil

        let insertedCount = applySensitiveRedactionRegions(result.regions)
        if insertedCount == 0 {
          updateSensitiveRedactionToast(message: L10n.AnnotateUI.autoRedactionNoMatches, style: .warning)
        } else {
          updateSensitiveRedactionToast(
            message: L10n.AnnotateUI.autoRedactionComplete(insertedCount),
            style: .success
          )
        }

        DiagnosticLogger.shared.log(.info, .annotate, "Sensitive redaction scan completed", context: [
          "regions": "\(insertedCount)"
        ])
      } catch {
        guard activeSensitiveRedactionOperationID == operationID else { return }

        isSensitiveRedactionScanning = false
        activeSensitiveRedactionOperationID = nil
        let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        updateSensitiveRedactionToast(message: message, style: .error)
        DiagnosticLogger.shared.log(.error, .annotate, "Sensitive redaction scan failed", context: [
          "error": String(describing: type(of: error))
        ])
      }
    }
  }

  @discardableResult
  func applySensitiveRedactionRegions(_ regions: [AnnotateSensitiveRedactionRegion]) -> Int {
    let clampedRegions = regions
      .map { region in
        AnnotateSensitiveRedactionRegion(
          kind: region.kind,
          bounds: region.bounds.standardized.intersection(sourceImageBounds).standardized,
          confidence: region.confidence
        )
      }
      .filter { !$0.bounds.isEmpty && $0.bounds.width >= 2 && $0.bounds.height >= 2 }

    guard !clampedRegions.isEmpty else { return 0 }

    saveState()
    let blurProperties = annotationCreationProperties(for: .blur)
    let redactionBlurType = blurType
    let newAnnotations = clampedRegions.map { region in
      AnnotationItem(
        type: .blur(redactionBlurType),
        bounds: region.bounds,
        properties: blurProperties
      )
    }

    annotations.append(contentsOf: newAnnotations)
    setSelectedAnnotationIds(Set(newAnnotations.map(\.id)))
    selectedTool = .selection
    finishTextEditing()
    return newAnnotations.count
  }

  private func cancelSensitiveRedactionScan() {
    activeSensitiveRedactionOperationID = nil
    isSensitiveRedactionScanning = false
    if let toast = sensitiveRedactionToast {
      AppToastManager.shared.dismiss(toast)
      sensitiveRedactionToast = nil
    }
  }

  private func showSensitiveRedactionToast(message: String, style: AppToastStyle) {
    AppToastManager.shared.show(
      message: message,
      style: style,
      variant: .compact
    )
  }

  private func updateSensitiveRedactionToast(message: String, style: AppToastStyle) {
    if let toast = sensitiveRedactionToast {
      AppToastManager.shared.update(
        toast,
        message: message,
        style: style,
        duration: 2.5,
        variant: .compact
      )
      sensitiveRedactionToast = nil
    } else {
      showSensitiveRedactionToast(message: message, style: style)
    }
  }

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
  static func loadImageWithCorrectScale(from url: URL) -> NSImage? {
    guard let image = SandboxFileAccessManager.shared.withScopedAccess(to: url, {
      NSImage(contentsOf: url)
    }) else { return nil }

    let scaleFactor = NSScreen.main?.backingScaleFactor ?? 2.0
    if let normalizedSize = normalizedRetinaLogicalSizeIfNeeded(for: image, scaleFactor: scaleFactor) {
      image.size = normalizedSize
    }

    return image
  }

  private static func normalizedRetinaLogicalSizeIfNeeded(
    for image: NSImage,
    scaleFactor: CGFloat
  ) -> NSSize? {
    guard scaleFactor > 1 else { return nil }
    guard let rep = image.representations.first, rep.pixelsWide > 0, rep.pixelsHigh > 0 else {
      return nil
    }

    let pixelWidth = CGFloat(rep.pixelsWide)
    let pixelHeight = CGFloat(rep.pixelsHigh)
    let currentSize = image.size
    let expectedSize = NSSize(
      width: pixelWidth / scaleFactor,
      height: pixelHeight / scaleFactor
    )

    let isAlreadyScaled =
      abs(currentSize.width - expectedSize.width) < 0.5 &&
      abs(currentSize.height - expectedSize.height) < 0.5
    if isAlreadyScaled {
      return nil
    }

    let isUnscaledLogicalSize =
      abs(currentSize.width - pixelWidth) < 0.5 &&
      abs(currentSize.height - pixelHeight) < 0.5
    return isUnscaledLogicalSize ? expectedSize : nil
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

  private func combineLayoutItems() -> [CombineImagesLayoutItem] {
    var items = [
      CombineImagesLayoutItem(
        id: Self.combineBaseLayerID,
        size: CGSize(width: imageWidth, height: imageHeight)
      )
    ]
    for annotation in annotations {
      guard case .embeddedImage(let assetID) = annotation.type,
            let image = embeddedImageAssets[assetID] else { continue }
      let size = normalizedCanvasImageSize(for: image)
      guard size.width > 0, size.height > 0 else { continue }
      items.append(CombineImagesLayoutItem(id: annotation.id, size: size))
    }
    return items
  }

  private func applyAutomaticCombineLayout() {
    guard isCombineMode, hasImage else { return }
    let result = CombineImagesLayout.layout(
      items: combineLayoutItems(),
      direction: combineDirection,
      gap: combineGap
    )
    combineResolvedDirection = result.direction
    for index in annotations.indices {
      guard case .embeddedImage = annotations[index].type,
            let bounds = result.boundsByID[annotations[index].id] else { continue }
      annotations[index].bounds = bounds
    }
    combineContentBounds = result.contentBounds.isEmpty ? sourceImageBounds : result.contentBounds
  }

  private func captureCurrentFreeCombineBounds() {
    for annotation in annotations {
      guard case .embeddedImage = annotation.type else { continue }
      freeCombineBoundsByAnnotationID[annotation.id] = annotation.bounds
    }
  }

  private func restoreFreeCombineBounds() {
    for index in annotations.indices {
      guard case .embeddedImage = annotations[index].type else { continue }
      if let bounds = freeCombineBoundsByAnnotationID[annotations[index].id] {
        annotations[index].bounds = bounds
      } else {
        freeCombineBoundsByAnnotationID[annotations[index].id] = annotations[index].bounds
      }
    }
    updateCombineContentBounds()
  }

  private func updateCombineContentBounds() {
    guard isCombineMode else {
      combineContentBounds = sourceImageBounds
      return
    }
    let imageBounds = annotations.compactMap { annotation -> CGRect? in
      guard case .embeddedImage = annotation.type else { return nil }
      return annotation.bounds
    }
    combineContentBounds = imageBounds.reduce(sourceImageBounds) { $0.union($1) }
  }

  private func importedImagePlacementBounds(for imageSize: CGSize) -> CGRect {
    if isCombineMode {
      let baseHeight = max(imageHeight, 1)
      let scale = baseHeight / max(imageSize.height, 1)
      let targetSize = CGSize(width: imageSize.width * scale, height: baseHeight)
      return CGRect(
        origin: CGPoint(x: combineContentBounds.maxX + combineGap, y: combineContentBounds.minY),
        size: targetSize
      )
    }

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
    pushUndoSnapshot(currentSnapshot(), annotationCount: annotations.count)
  }

  private func pushUndoSnapshot(_ snapshot: AnnotationSnapshot, annotationCount: Int) {
    DiagnosticLogger.shared.log(.debug, .annotate, "Undo checkpoint", context: ["annotations": "\(annotationCount)"])
    undoStack.append(.annotations(snapshot))
    redoStack.removeAll()
    canUndo = true
    canRedo = false
    hasUnsavedChanges = true
  }

  private func pushRotationUndo(_ snapshot: RotationSnapshot) {
    DiagnosticLogger.shared.log(.debug, .annotate, "Undo checkpoint", context: ["kind": "rotation"])
    undoStack.append(.rotation(snapshot))
    redoStack.removeAll()
    canUndo = true
    canRedo = false
    hasUnsavedChanges = true
  }

  func undo() {
    if editingTextAnnotationId != nil {
      commitTextEditing()
    }
    DiagnosticLogger.shared.log(.debug, .annotate, "Undo", context: ["stackDepth": "\(undoStack.count)"])
    guard let previous = undoStack.popLast() else { return }
    switch previous {
    case .annotations(let snapshot):
      redoStack.append(.annotations(currentSnapshot()))
      applySnapshot(snapshot)
    case .rotation(let snapshot):
      redoStack.append(.rotation(currentRotationSnapshot()))
      applyRotationSnapshot(snapshot)
    }
    canUndo = !undoStack.isEmpty
    canRedo = true
  }

  func redo() {
    if editingTextAnnotationId != nil {
      commitTextEditing()
    }
    DiagnosticLogger.shared.log(.debug, .annotate, "Redo", context: ["stackDepth": "\(redoStack.count)"])
    guard let next = redoStack.popLast() else { return }
    switch next {
    case .annotations(let snapshot):
      undoStack.append(.annotations(currentSnapshot()))
      applySnapshot(snapshot)
    case .rotation(let snapshot):
      undoStack.append(.rotation(currentRotationSnapshot()))
      applyRotationSnapshot(snapshot)
    }
    canUndo = true
    canRedo = !redoStack.isEmpty
  }

  private func currentSnapshot() -> AnnotationSnapshot {
    AnnotationSnapshot(
      annotations: annotations,
      embeddedImageAssets: embeddedImageAssets
    )
  }

  private func currentRotationSnapshot() -> RotationSnapshot {
    RotationSnapshot(
      sourceImage: sourceImage,
      cutoutImage: cutoutImage,
      isCutoutApplied: isCutoutApplied,
      embeddedImageAssets: embeddedImageAssets,
      embeddedImageSourceData: embeddedImageSourceData,
      embeddedImageSnapshotCacheData: embeddedImageSnapshotCacheData,
      annotations: annotations,
      cropRect: cropRect,
      originalCropRect: originalCropRect,
      cropAspectRatio: cropAspectRatio,
      isCropPortraitOrientation: isCropPortraitOrientation,
      didCutoutAutoApplyCrop: didCutoutAutoApplyCrop,
      cutoutAutoAppliedCropRect: cutoutAutoAppliedCropRect
    )
  }

  func beginTextEditing(id: UUID, recordsUndo: Bool = true) {
    if let activeId = editingTextAnnotationId, activeId != id {
      commitTextEditing()
    }

    if recordsUndo,
       let annotation = annotations.first(where: { $0.id == id }),
       case .text(let text) = annotation.type {
      textEditingUndoTransaction = TextEditingUndoTransaction(
        annotationId: id,
        snapshotBeforeEdit: currentSnapshot(),
        originalText: text
      )
    } else {
      textEditingUndoTransaction = nil
    }

    editingTextAnnotationId = id
  }

  func useAutomaticTextWidth(for id: UUID) {
    guard let annotation = annotations.first(where: { $0.id == id }),
          case .text = annotation.type else { return }
    autoSizingTextAnnotationIDs.insert(id)
  }

  func finishTextEditing() {
    editingTextAnnotationId = nil
  }

  private func recordTextEditingUndoIfNeeded(id: UUID, newText: String) {
    guard var transaction = textEditingUndoTransaction,
          transaction.annotationId == id,
          !transaction.didRecordUndo,
          transaction.originalText != newText else { return }

    pushUndoSnapshot(
      transaction.snapshotBeforeEdit,
      annotationCount: transaction.snapshotBeforeEdit.annotations.count
    )
    transaction.didRecordUndo = true
    textEditingUndoTransaction = transaction
  }

  private func applySnapshot(_ snapshot: AnnotationSnapshot) {
    annotations = snapshot.annotations
    embeddedImageAssets = snapshot.embeddedImageAssets
    pruneUnusedEmbeddedAssets()
    updateImportWarningIfNeeded()

    let validAnnotationIds = Set(annotations.map(\.id))
    setSelectedAnnotationIds(selectedAnnotationIds.intersection(validAnnotationIds))

    if let editingTextAnnotationId,
       !annotations.contains(where: { $0.id == editingTextAnnotationId }) {
      self.editingTextAnnotationId = nil
    }
    refreshCombineLayout()
  }

  private func applyRotationSnapshot(_ snapshot: RotationSnapshot) {
    sourceImage = snapshot.sourceImage
    cutoutImage = snapshot.cutoutImage
    isCutoutApplied = snapshot.isCutoutApplied
    embeddedImageAssets = snapshot.embeddedImageAssets
    embeddedImageSourceData = snapshot.embeddedImageSourceData
    embeddedImageSnapshotCacheData = snapshot.embeddedImageSnapshotCacheData
    embeddedImageCGImageCache.removeAll()
    annotations = snapshot.annotations
    cropRect = snapshot.cropRect
    originalCropRect = snapshot.originalCropRect
    cropAspectRatio = snapshot.cropAspectRatio
    isCropPortraitOrientation = snapshot.isCropPortraitOrientation
    didCutoutAutoApplyCrop = snapshot.didCutoutAutoApplyCrop
    cutoutAutoAppliedCropRect = snapshot.cutoutAutoAppliedCropRect

    // Rotation is gated on `!isCropActive` (see `canRotateImage`), so any rotation snapshot
    // by definition represents a non-crop state. If the user enters crop mode and then
    // undoes the rotation, we must clear the crop interaction so it doesn't keep editing
    // against the differently-sized restored image with stale bounds.
    if isCropActive {
      isCropActive = false
      isCropResizing = false
      isCropShiftLocked = false
      cropInteractionContext = nil
      shouldRestoreSidebarAfterCropInteraction = false
      if selectedTool == .crop {
        selectedTool = .selection
      }
    }

    pruneUnusedEmbeddedAssets()
    updateImportWarningIfNeeded()

    let validAnnotationIds = Set(annotations.map(\.id))
    setSelectedAnnotationIds(selectedAnnotationIds.intersection(validAnnotationIds))

    if let editingTextAnnotationId,
       !annotations.contains(where: { $0.id == editingTextAnnotationId }) {
      self.editingTextAnnotationId = nil
    }
  }

  // MARK: - Rotation

  /// True when the user can rotate the source image 90°. Disabled while no image is loaded,
  /// while crop is being actively edited, or while a background-cutout request is in flight.
  var canRotateImage: Bool {
    hasImage && !isCropActive && !isCutoutProcessing
  }

  /// Rotate the source image 90° clockwise (or counter-clockwise) and bring all annotations,
  /// crop bounds, embedded image layers, and cutout state along for the ride. Pushes a
  /// dedicated rotation undo entry so this transform can be reversed without touching the
  /// annotation-only undo path.
  func rotateImage(clockwise: Bool) {
    guard canRotateImage,
          let source = sourceImage,
          let rotatedSource = source.rotated90(clockwise: clockwise) else {
      return
    }

    if editingTextAnnotationId != nil {
      commitTextEditing()
    }

    DiagnosticLogger.shared.log(.info, .annotate, "Image rotated", context: [
      "direction": clockwise ? "clockwise" : "counterclockwise",
      "oldSize": "\(Int(imageWidth))x\(Int(imageHeight))"
    ])

    let oldSize = CGSize(width: imageWidth, height: imageHeight)
    pushRotationUndo(currentRotationSnapshot())

    sourceImage = rotatedSource
    if let cutoutImage {
      self.cutoutImage = cutoutImage.rotated90(clockwise: clockwise)
    }

    // Rotate each embedded image asset so the rendered bitmap matches the rotated bounds, and
    // invalidate the serialised data caches so persistence re-encodes from the rotated NSImage.
    for (assetId, image) in embeddedImageAssets {
      guard let rotatedAsset = image.rotated90(clockwise: clockwise) else { continue }
      embeddedImageAssets[assetId] = rotatedAsset
      embeddedImageSourceData.removeValue(forKey: assetId)
      embeddedImageSnapshotCacheData.removeValue(forKey: assetId)
    }
    embeddedImageCGImageCache.removeAll()

    annotations = annotations.map { rotateAnnotation($0, oldSize: oldSize, clockwise: clockwise) }

    cropRect = cropRect.map { AnnotateImageRotation.rotateRect($0, oldSize: oldSize, clockwise: clockwise) }
    originalCropRect = originalCropRect.map { AnnotateImageRotation.rotateRect($0, oldSize: oldSize, clockwise: clockwise) }
    cutoutAutoAppliedCropRect = cutoutAutoAppliedCropRect.map {
      AnnotateImageRotation.rotateRect($0, oldSize: oldSize, clockwise: clockwise)
    }

    // Aspect-ratio presets such as 16:9 keep their identity but the physical orientation flips.
    if cropAspectRatio != .free, cropAspectRatio != .square {
      isCropPortraitOrientation.toggle()
    }

    hasUnsavedChanges = true
  }

  private func rotateAnnotation(
    _ annotation: AnnotationItem,
    oldSize: CGSize,
    clockwise: Bool
  ) -> AnnotationItem {
    var rotated = annotation
    rotated.bounds = AnnotateImageRotation.rotateRect(annotation.bounds, oldSize: oldSize, clockwise: clockwise)

    switch annotation.type {
    case .arrow(let geometry):
      let newStart = AnnotateImageRotation.rotatePoint(geometry.start, oldSize: oldSize, clockwise: clockwise)
      let newEnd = AnnotateImageRotation.rotatePoint(geometry.end, oldSize: oldSize, clockwise: clockwise)
      let newControl = geometry.resolvedControlPoint.map {
        AnnotateImageRotation.rotatePoint($0, oldSize: oldSize, clockwise: clockwise)
      }
      let newGeometry = ArrowGeometry(
        start: newStart,
        end: newEnd,
        style: geometry.style,
        controlPoint: newControl,
        arrowType: geometry.arrowType,
        startHead: geometry.startHead,
        endHead: geometry.endHead
      )
      rotated.type = .arrow(newGeometry)
      rotated.bounds = newGeometry.bounds()

    case .line(let start, let end):
      let newStart = AnnotateImageRotation.rotatePoint(start, oldSize: oldSize, clockwise: clockwise)
      let newEnd = AnnotateImageRotation.rotatePoint(end, oldSize: oldSize, clockwise: clockwise)
      rotated.type = .line(start: newStart, end: newEnd)

    case .path(let points):
      rotated.type = .path(points.map {
        AnnotateImageRotation.rotatePoint($0, oldSize: oldSize, clockwise: clockwise)
      })

    case .highlight(let points):
      rotated.type = .highlight(points.map {
        AnnotateImageRotation.rotatePoint($0, oldSize: oldSize, clockwise: clockwise)
      })

    case .text:
      rotated.bounds = AnnotateImageRotation.rotateLayoutRectPreservingSize(
        annotation.bounds,
        oldSize: oldSize,
        clockwise: clockwise
      )

    case .rectangle, .filledRectangle, .oval, .blur, .counter, .watermark, .embeddedImage, .spotlight:
      // Bounds-only annotations: the rotated `bounds` above is the full transform we need.
      // Watermark `rotationDegrees` is user-controlled and clamped to ±45°, so we leave it
      // unchanged while moving the watermark region with the canvas.
      break
    }

    return rotated
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
    if editingTextAnnotationId != nil {
      commitTextEditing()
    }
    if cropInteractionContext == nil {
      cropInteractionContext = CropInteractionContext(
        selectedTool: selectedTool == .crop ? .selection : selectedTool,
        selectedAnnotationIds: selectedAnnotationIds,
        cropRect: cropRect,
        didCutoutAutoApplyCrop: didCutoutAutoApplyCrop,
        cutoutAutoAppliedCropRect: cutoutAutoAppliedCropRect
      )
    }

    collapseSidebarForCropInteraction()
    deselectAnnotation()
    selectedTool = .crop

    guard hasImage else { return }

    if cropRect == nil {
      initializeCrop()
    } else if let cropRect {
      originalCropRect = cropRect
      isCropActive = true
    }

    isCropResizing = false
    isCropShiftLocked = false
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

  /// Apply crop and return to the context active before crop mode.
  func confirmCropInteraction() {
    applyCrop()
    restoreContextAfterCropInteraction()
  }

  /// Reset unsaved changes flag after successful save
  func markAsSaved() {
    hasUnsavedChanges = false
    isDefaultCanvasPresetAutoApplied = false
  }

  /// Cancel crop and reset
  func cancelCrop() {
    DiagnosticLogger.shared.log(.info, .annotate, "Crop cancelled")

    if let context = cropInteractionContext {
      cropRect = context.cropRect
      didCutoutAutoApplyCrop = context.didCutoutAutoApplyCrop
      cutoutAutoAppliedCropRect = context.cutoutAutoAppliedCropRect
    } else {
      cropRect = nil
      clearCutoutAutoCropTracking()
    }

    originalCropRect = nil
    isCropActive = false
    isCropResizing = false
    isCropShiftLocked = false
    restoreSidebarAfterCropInteractionIfNeeded()
    restoreContextAfterCropInteraction()
  }

  /// Reset crop to nil
  func resetCrop() {
    cropRect = nil
    originalCropRect = nil
    cropInteractionContext = nil
    isCropActive = false
    clearCutoutAutoCropTracking()
    cropAspectRatio = .free
    isCropPortraitOrientation = false
    isCropResizing = false
    isCropShiftLocked = false
  }

  /// Revert the active crop rect to the original image bounds while staying in crop mode.
  func revertCropToOriginalBounds() {
    guard hasImage else { return }

    DiagnosticLogger.shared.log(.info, .annotate, "Crop reverted to original bounds")
    let fullImageRect = sourceImageBounds
    cropRect = fullImageRect
    originalCropRect = fullImageRect
    cropAspectRatio = .free
    isCropPortraitOrientation = false
    isCropActive = true
    isCropResizing = false
    isCropShiftLocked = false
    clearCutoutAutoCropTracking()
  }

  /// Apply aspect ratio to current crop rect
  func applyCropAspectRatio(_ ratio: CropAspectRatio) {
    cropAspectRatio = ratio

    // Use original crop rect as base to prevent shrinking
    guard var rect = originalCropRect ?? cropRect, ratio != .free else { return }

    let targetRatio = ratio.effectiveRatio(isPortrait: isCropPortraitOrientation)
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

  /// Toggle crop orientation between landscape and portrait
  func toggleCropOrientation() {
    guard cropAspectRatio != .free, cropAspectRatio != .square else { return }
    isCropPortraitOrientation.toggle()
    applyCropAspectRatio(cropAspectRatio)
  }

  private func restoreContextAfterCropInteraction() {
    let context = cropInteractionContext
    cropInteractionContext = nil
    originalCropRect = nil

    let restoredTool = context?.selectedTool == .crop ? AnnotationToolType.selection : (context?.selectedTool ?? .selection)
    selectedTool = restoredTool
    setSelectedAnnotationIds(context?.selectedAnnotationIds ?? [])
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

  /// Normalize crop rect with minimum size. Crop expansion outside the source image is allowed.
  private func constrainCropToImageBounds(_ rect: CGRect) -> CGRect {
    var constrained = rect.standardized

    // Enforce minimum size
    let minSize: CGFloat = 20
    if constrained.width < minSize { constrained.size.width = minSize }
    if constrained.height < minSize { constrained.size.height = minSize }

    return constrained
  }

  // MARK: - Annotation Selection

  var selectedAnnotations: [AnnotationItem] {
    annotations.filter { selectedAnnotationIds.contains($0.id) }
  }

  var hasSelectedAnnotations: Bool {
    !selectedAnnotationIds.isEmpty
  }

  func isAnnotationSelected(_ id: UUID) -> Bool {
    selectedAnnotationIds.contains(id)
  }

  func selectAnnotation(at point: CGPoint) -> AnnotationItem? {
    // Find annotation at point (in reverse order to select topmost)
    for annotation in annotations.reversed() {
      // Quick bounds check first (optimization)
      let expandedBounds = annotation.selectionBounds.insetBy(dx: -10, dy: -10)
      guard expandedBounds.contains(point) else { continue }

      // Precise hit test
      if annotation.containsPoint(point) {
        setSelectedAnnotationIds([annotation.id])
        return annotation
      }
    }
    deselectAnnotation()
    return nil
  }

  @discardableResult
  func selectAnnotations(in rect: CGRect) -> [AnnotationItem] {
    let selectionRect = rect.standardized
    guard selectionRect.width > 0, selectionRect.height > 0 else {
      deselectAnnotation()
      return []
    }

    let selected = annotations.filter { annotation in
      let annotationBounds = annotation.selectionBounds
      return selectionRect.intersects(annotationBounds)
        || selectionRect.contains(annotationBounds)
    }
    setSelectedAnnotationIds(Set(selected.map(\.id)))
    return selected
  }

  func setSelectedAnnotationIds(_ ids: Set<UUID>) {
    let validIds = Set(annotations.map(\.id))
    let filteredIds = ids.intersection(validIds)
    let primaryId = filteredIds.count == 1 ? filteredIds.first : nil

    isSynchronizingSelection = true
    selectedAnnotationIds = filteredIds
    selectedAnnotationId = primaryId
    isSynchronizingSelection = false
  }

  func updateAnnotationBounds(id: UUID, bounds: CGRect) {
    guard let index = annotations.firstIndex(where: { $0.id == id }) else { return }

    let oldBounds = annotations[index].resizeBounds
    let normalizedBounds = bounds.standardized

    if case .text = annotations[index].type,
       annotations[index].properties.textPresentation == .callout,
       let tailTarget = annotations[index].properties.calloutTailTarget {
      if TextBubbleGeometry.isDefaultTail(tailTarget, for: oldBounds, fontSize: annotations[index].properties.fontSize) {
        annotations[index].properties.calloutTailTarget = defaultCalloutTailTarget(for: normalizedBounds, fontSize: annotations[index].properties.fontSize)
      } else if oldBounds.size == normalizedBounds.size {
        annotations[index].properties.calloutTailTarget = CGPoint(
          x: tailTarget.x + normalizedBounds.minX - oldBounds.minX,
          y: tailTarget.y + normalizedBounds.minY - oldBounds.minY
        )
      }
    }
    annotations[index].bounds = normalizedBounds

    if case .text = annotations[index].type,
       abs(oldBounds.width - normalizedBounds.width) > 0.5 {
      autoSizingTextAnnotationIDs.remove(id)
    }

    // Also update embedded coordinates for arrows/lines/paths
    switch annotations[index].type {
    case .arrow(let geometry):
      let updated = geometry.remapped(from: oldBounds, to: normalizedBounds)
      annotations[index].type = .arrow(updated)
      annotations[index].bounds = updated.bounds()
    case .line(let start, let end):
      annotations[index].type = .line(
        start: remapPoint(start, from: oldBounds, to: normalizedBounds),
        end: remapPoint(end, from: oldBounds, to: normalizedBounds)
      )
    case .path(let points):
      annotations[index].type = .path(points.map { remapPoint($0, from: oldBounds, to: normalizedBounds) })
    case .highlight(let points):
      annotations[index].type = .highlight(points.map { remapPoint($0, from: oldBounds, to: normalizedBounds) })
    case .counter:
      let diameter = max(normalizedBounds.width, normalizedBounds.height)
      let updatedCounterBounds = counterBounds(center: CGPoint(x: normalizedBounds.midX, y: normalizedBounds.midY), controlValue: AnnotationProperties.controlValue(forCounterDiameter: diameter))
      annotations[index].bounds = updatedCounterBounds
      annotations[index].properties.strokeWidth = AnnotationProperties.controlValue(forCounterDiameter: diameter)
    default:
      break
    }

    if isCombineMode, combineMode == .freeCanvas,
       case .embeddedImage = annotations[index].type {
      freeCombineBoundsByAnnotationID[id] = annotations[index].bounds
      updateCombineContentBounds()
    }
  }

  func updateLineEndpoint(id: UUID, start newStart: CGPoint? = nil, end newEnd: CGPoint? = nil) {
    guard let index = annotations.firstIndex(where: { $0.id == id }),
          case .line(let start, let end) = annotations[index].type else { return }

    let updatedStart = newStart ?? start
    let updatedEnd = newEnd ?? end
    annotations[index].type = .line(start: updatedStart, end: updatedEnd)
    annotations[index].bounds = CGRect(
      x: min(updatedStart.x, updatedEnd.x),
      y: min(updatedStart.y, updatedEnd.y),
      width: abs(updatedEnd.x - updatedStart.x),
      height: abs(updatedEnd.y - updatedStart.y)
    ).standardized
  }

  /// Move an arrow's start/end endpoint (Figma-style line editing).
  /// Style, display type, and heads are preserved; the curve control point is
  /// re-derived from the new endpoints so curved arrows follow the drag.
  func updateArrowEndpoint(id: UUID, start newStart: CGPoint? = nil, end newEnd: CGPoint? = nil) {
    guard let index = annotations.firstIndex(where: { $0.id == id }),
          case .arrow(let geometry) = annotations[index].type else { return }

    let updatedStart = newStart ?? geometry.start
    let updatedEnd = newEnd ?? geometry.end
    let updated = ArrowGeometry(
      start: updatedStart,
      end: updatedEnd,
      style: geometry.style,
      arrowType: geometry.arrowType,
      startHead: geometry.startHead,
      endHead: geometry.endHead
    )
    annotations[index].type = .arrow(updated)
    annotations[index].bounds = updated.bounds()
    hasUnsavedChanges = true
  }

  func updateAnnotationText(id: UUID, text: String) {
    guard let index = annotations.firstIndex(where: { $0.id == id }),
          case .text(let currentText) = annotations[index].type else { return }

    let currentBounds = annotations[index].bounds
    let newBounds = resizedTextBounds(
      id: id,
      text: text,
      properties: annotations[index].properties,
      currentBounds: currentBounds
    )

    let textChanged = currentText != text
    let boundsChanged = annotations[index].bounds != newBounds
    guard textChanged || boundsChanged else { return }

    if textChanged {
      recordTextEditingUndoIfNeeded(id: id, newText: text)
      annotations[index].type = .text(text)
    }
    annotations[index].bounds = newBounds
    if annotations[index].properties.textPresentation == .callout,
       let tailTarget = annotations[index].properties.calloutTailTarget,
       TextBubbleGeometry.isDefaultTail(tailTarget, for: currentBounds, fontSize: annotations[index].properties.fontSize) {
      annotations[index].properties.calloutTailTarget = defaultCalloutTailTarget(for: newBounds, fontSize: annotations[index].properties.fontSize)
    }
    hasUnsavedChanges = true
  }

  func updateWatermarkText(id: UUID, text: String) {
    guard let index = annotations.firstIndex(where: { $0.id == id }),
          case .watermark = annotations[index].type else { return }

    annotations[index].type = .watermark(text)
  }

  func updateArrowStyle(id: UUID, style: ArrowStyle) {
    guard let index = annotations.firstIndex(where: { $0.id == id }),
          case .arrow(let geometry) = annotations[index].type else { return }

    let updated = geometry.withStyle(style)
    guard updated != geometry else { return }

    annotations[index].type = .arrow(updated)
    annotations[index].bounds = updated.bounds()
    hasUnsavedChanges = true
  }

  func updateArrowType(id: UUID, arrowType: ArrowType) {
    guard let index = annotations.firstIndex(where: { $0.id == id }),
          case .arrow(let geometry) = annotations[index].type else { return }

    let updated = geometry.withArrowType(arrowType)
    guard updated != geometry else { return }

    annotations[index].type = .arrow(updated)
    annotations[index].bounds = updated.bounds()
    hasUnsavedChanges = true
  }

  func updateArrowBendDirection(id: UUID, bendDirection: ArrowBendDirection) {
    guard let index = annotations.firstIndex(where: { $0.id == id }),
          case .arrow(let geometry) = annotations[index].type,
          geometry.style.supportsBendDirection else { return }

    let updated = geometry.withBendDirection(bendDirection)
    guard updated != geometry else { return }

    annotations[index].type = .arrow(updated)
    annotations[index].bounds = updated.bounds()
    hasUnsavedChanges = true
  }

  func updateArrowStartHead(id: UUID, head: ArrowEndpointStyle) {
    guard let index = annotations.firstIndex(where: { $0.id == id }),
          case .arrow(let geometry) = annotations[index].type else { return }

    let updated = geometry.withStartHead(head)
    guard updated != geometry else { return }

    annotations[index].type = .arrow(updated)
    annotations[index].bounds = updated.bounds()
    hasUnsavedChanges = true
  }

  func updateArrowEndHead(id: UUID, head: ArrowEndpointStyle) {
    guard let index = annotations.firstIndex(where: { $0.id == id }),
          case .arrow(let geometry) = annotations[index].type else { return }

    let updated = geometry.withEndHead(head)
    guard updated != geometry else { return }

    annotations[index].type = .arrow(updated)
    annotations[index].bounds = updated.bounds()
    hasUnsavedChanges = true
  }

  func updateBlurType(id: UUID, blurType: BlurType) {
    guard let index = annotations.firstIndex(where: { $0.id == id }),
          case .blur = annotations[index].type else { return }

    annotations[index].type = .blur(blurType)
  }

  /// Update annotation properties (strokeWidth, fontSize, colors)
  func updateAnnotationProperties(
    id: UUID,
    strokeWidth: CGFloat? = nil,
    fontSize: CGFloat? = nil,
    strokeColor: Color? = nil,
    fillColor: Color? = nil,
    cornerRadius: CGFloat? = nil,
    opacity: CGFloat? = nil,
    rotationDegrees: CGFloat? = nil,
    watermarkStyle: WatermarkStyle? = nil,
    spotlightOpacity: CGFloat? = nil,
    recordsUndo: Bool = false
  ) {
    guard let index = annotations.firstIndex(where: { $0.id == id }) else { return }
    let colorUpdate = normalizedColorUpdate(
      for: annotations[index],
      strokeColor: strokeColor,
      fillColor: fillColor
    )

    guard annotationPropertiesWillChange(
      annotations[index],
      strokeWidth: strokeWidth,
      fontSize: fontSize,
      strokeColor: colorUpdate.strokeColor,
      fillColor: colorUpdate.fillColor,
      cornerRadius: cornerRadius,
      opacity: opacity,
      rotationDegrees: rotationDegrees,
      watermarkStyle: watermarkStyle,
      spotlightOpacity: spotlightOpacity
    ) else { return }

    if recordsUndo {
      saveState()
    }

    if let strokeWidth = strokeWidth {
      let clampedWidth = AnnotationProperties.clampedControlValue(strokeWidth)
      annotations[index].properties.strokeWidth = clampedWidth
      if case .counter = annotations[index].type {
        let center = CGPoint(x: annotations[index].bounds.midX, y: annotations[index].bounds.midY)
        annotations[index].bounds = counterBounds(center: center, controlValue: clampedWidth)
      }
    }
    if let fontSize = fontSize {
      annotations[index].properties.fontSize = fontSize
      // Recalculate bounds for new font size
      if case .text(let content) = annotations[index].type {
        let currentBounds = annotations[index].bounds
        let properties = annotations[index].properties
        annotations[index].bounds = resizedTextBounds(
          id: id,
          text: content,
          properties: properties,
          currentBounds: currentBounds
        )
      }
    }
    if let strokeColor = colorUpdate.strokeColor {
      annotations[index].properties.strokeColor = strokeColor
    }
    if let fillColor = colorUpdate.fillColor {
      annotations[index].properties.fillColor = fillColor
    }
    if let cornerRadius = cornerRadius {
      annotations[index].properties.cornerRadius = max(0, cornerRadius)
    }
    if let opacity = opacity {
      annotations[index].properties.opacity = AnnotationProperties.clampedOpacity(opacity)
    }
    if let rotationDegrees = rotationDegrees {
      annotations[index].properties.rotationDegrees = AnnotationProperties.clampedRotationDegrees(rotationDegrees)
    }
    if let watermarkStyle = watermarkStyle {
      annotations[index].properties.watermarkStyle = watermarkStyle
    }
    if let spotlightOpacity = spotlightOpacity {
      annotations[index].properties.spotlightOpacity = AnnotationProperties.clampedSpotlightOpacity(spotlightOpacity)
    }
    hasUnsavedChanges = true
  }

  func updateAnnotationPrimaryColor(
    id: UUID,
    color: Color,
    recordsUndo: Bool = false
  ) {
    updateAnnotationProperties(
      id: id,
      strokeColor: color,
      recordsUndo: recordsUndo
    )
    if isQuickPropertiesSyncEnabled {
      rememberSharedAnnotationColor(color)
    }
  }

  private func normalizedColorUpdate(
    for annotation: AnnotationItem,
    strokeColor: Color?,
    fillColor: Color?
  ) -> (strokeColor: Color?, fillColor: Color?) {
    if case .filledRectangle = annotation.type,
       let color = strokeColor ?? fillColor {
      return (color, color)
    }

    return (strokeColor, fillColor)
  }

  private func annotationPropertiesWillChange(
    _ annotation: AnnotationItem,
    strokeWidth: CGFloat? = nil,
    fontSize: CGFloat? = nil,
    strokeColor: Color? = nil,
    fillColor: Color? = nil,
    cornerRadius: CGFloat? = nil,
    opacity: CGFloat? = nil,
    rotationDegrees: CGFloat? = nil,
    watermarkStyle: WatermarkStyle? = nil,
    spotlightOpacity: CGFloat? = nil
  ) -> Bool {
    let properties = annotation.properties
    let colorUpdate = normalizedColorUpdate(
      for: annotation,
      strokeColor: strokeColor,
      fillColor: fillColor
    )

    if let strokeWidth,
       properties.strokeWidth != AnnotationProperties.clampedControlValue(strokeWidth) {
      return true
    }
    if let fontSize,
       properties.fontSize != fontSize {
      return true
    }
    if let strokeColor = colorUpdate.strokeColor,
       properties.strokeColor != strokeColor {
      return true
    }
    if let fillColor = colorUpdate.fillColor,
       properties.fillColor != fillColor {
      return true
    }
    if let cornerRadius,
       properties.cornerRadius != max(0, cornerRadius) {
      return true
    }
    if let opacity,
       properties.opacity != AnnotationProperties.clampedOpacity(opacity) {
      return true
    }
    if let rotationDegrees,
       properties.rotationDegrees != AnnotationProperties.clampedRotationDegrees(rotationDegrees) {
      return true
    }
    if let watermarkStyle,
       properties.watermarkStyle != watermarkStyle {
      return true
    }
    if let spotlightOpacity,
       properties.spotlightOpacity != AnnotationProperties.clampedSpotlightOpacity(spotlightOpacity) {
      return true
    }
    return false
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
    fontName: String? = nil,
    constrainedWidth: CGFloat? = nil,
    maximumHeight: CGFloat = AnnotateTextLayout.maxHeight,
    presentation: TextPresentation = .plain
  ) -> CGRect {
    AnnotateTextLayout.bounds(
      text: text,
      font: AnnotateTextLayout.font(size: fontSize, fontName: fontName),
      origin: origin,
      constrainedWidth: constrainedWidth,
      maximumHeight: maximumHeight,
      presentation: presentation
    )
  }

  private func resizedTextBounds(
    id: UUID,
    text: String,
    properties: AnnotationProperties,
    currentBounds: CGRect
  ) -> CGRect {
    let font = AnnotateTextLayout.font(size: properties.fontSize, fontName: properties.fontName)
    let annotationBounds = activeAnnotationBounds.standardized
    let topY = currentBounds.maxY
    let availableWidth = max(annotationBounds.maxX - currentBounds.minX, AnnotateTextLayout.minWidth)
    let availableHeight = max(topY - annotationBounds.minY, AnnotateTextLayout.minimumHeight(for: font, presentation: properties.textPresentation))
    let targetWidth: CGFloat
    if autoSizingTextAnnotationIDs.contains(id) {
      targetWidth = AnnotateTextLayout.preferredAutoWidth(
        text: text,
        font: font,
        minimumWidth: AnnotateTextLayout.minWidth,
        maximumWidth: availableWidth,
        presentation: properties.textPresentation
      )
    } else {
      targetWidth = AnnotateTextLayout.clampedWidth(
        currentBounds.width,
        maximumWidth: availableWidth
      )
    }

    var bounds = calculateTextBounds(
      text: text,
      fontSize: properties.fontSize,
      origin: currentBounds.origin,
      fontName: properties.fontName,
      constrainedWidth: targetWidth,
      maximumHeight: availableHeight,
      presentation: properties.textPresentation
    )
    bounds.origin.y = topY - bounds.height
    return bounds
  }

  /// Get selected annotation if it's a text type
  var selectedTextAnnotation: AnnotationItem? {
    guard let annotation = selectedAnnotation,
          case .text = annotation.type else {
      return nil
    }
    return annotation
  }

  /// Get selected annotation (any type)
  var selectedAnnotation: AnnotationItem? {
    guard selectedAnnotationIds.count == 1,
          let id = selectedAnnotationIds.first else { return nil }
    return annotations.first { $0.id == id }
  }

  var selectedArrowAnnotation: AnnotationItem? {
    guard let annotation = selectedAnnotation,
          case .arrow = annotation.type else {
      return nil
    }
    return annotation
  }

  private var selectedArrowAnnotations: [AnnotationItem] {
    selectedAnnotations.filter { annotation in
      if case .arrow = annotation.type { return true }
      return false
    }
  }

  private var selectedBlurAnnotations: [AnnotationItem] {
    selectedAnnotations.filter { annotation in
      if case .blur = annotation.type { return true }
      return false
    }
  }

  private var selectedWatermarkAnnotations: [AnnotationItem] {
    selectedAnnotations.filter { annotation in
      if case .watermark = annotation.type { return true }
      return false
    }
  }

  var activeArrowStyle: ArrowStyle {
    if let annotation = selectedArrowAnnotations.first,
       case .arrow(let geometry) = annotation.type {
      return geometry.style
    }
    return arrowStyle
  }

  func setActiveArrowStyle(_ style: ArrowStyle) {
    arrowStyle = style
    sharedAnnotationParameterDefaults.arrowStyle = style.rawValue
    persistSharedAnnotationParameterDefaults()

    let arrowAnnotations = selectedArrowAnnotations
    if !arrowAnnotations.isEmpty {
      if arrowAnnotations.contains(where: {
        guard case .arrow(let geometry) = $0.type else { return false }
        return geometry.style != style
      }) {
        saveState()
      }
      arrowAnnotations.forEach { updateArrowStyle(id: $0.id, style: style) }
    } else {
      arrowStyle = style
    }
  }

  var activeArrowType: ArrowType {
    if let annotation = selectedArrowAnnotations.first,
       case .arrow(let geometry) = annotation.type {
      return geometry.arrowType
    }
    return arrowType
  }

  func setActiveArrowType(_ type: ArrowType) {
    arrowType = type
    sharedAnnotationParameterDefaults.arrowType = type.rawValue
    persistSharedAnnotationParameterDefaults()

    let arrowAnnotations = selectedArrowAnnotations
    if !arrowAnnotations.isEmpty {
      if arrowAnnotations.contains(where: {
        guard case .arrow(let geometry) = $0.type else { return false }
        return geometry.arrowType != type
      }) {
        saveState()
      }
      arrowAnnotations.forEach { updateArrowType(id: $0.id, arrowType: type) }
    } else {
      arrowType = type
    }
  }

  var activeArrowBendDirection: ArrowBendDirection {
    if let annotation = selectedArrowAnnotations.first,
       case .arrow(let geometry) = annotation.type {
      return geometry.bendDirection
    }
    return arrowBendDirection
  }

  func setActiveArrowBendDirection(_ bendDirection: ArrowBendDirection) {
    arrowBendDirection = bendDirection
    sharedAnnotationParameterDefaults.arrowBendDirection = bendDirection.rawValue
    persistSharedAnnotationParameterDefaults()

    let arrowAnnotations = selectedArrowAnnotations
    if !arrowAnnotations.isEmpty {
      if arrowAnnotations.contains(where: {
        guard case .arrow(let geometry) = $0.type else { return false }
        return geometry.style.supportsBendDirection && geometry.bendDirection != bendDirection
      }) {
        saveState()
      }
      arrowAnnotations.forEach {
        updateArrowBendDirection(id: $0.id, bendDirection: bendDirection)
      }
    } else {
      arrowBendDirection = bendDirection
    }
  }

  var activeArrowStartHead: ArrowEndpointStyle {
    if let annotation = selectedArrowAnnotations.first,
       case .arrow(let geometry) = annotation.type {
      return geometry.startHead
    }
    return arrowStartHead
  }

  func setActiveArrowStartHead(_ head: ArrowEndpointStyle) {
    arrowStartHead = head
    sharedAnnotationParameterDefaults.arrowStartHead = head.rawValue
    persistSharedAnnotationParameterDefaults()

    let arrowAnnotations = selectedArrowAnnotations
    if !arrowAnnotations.isEmpty {
      if arrowAnnotations.contains(where: {
        guard case .arrow(let geometry) = $0.type else { return false }
        return geometry.startHead != head
      }) {
        saveState()
      }
      arrowAnnotations.forEach { updateArrowStartHead(id: $0.id, head: head) }
    }
  }

  var activeArrowEndHead: ArrowEndpointStyle {
    if let annotation = selectedArrowAnnotations.first,
       case .arrow(let geometry) = annotation.type {
      return geometry.endHead
    }
    return arrowEndHead
  }

  func setActiveArrowEndHead(_ head: ArrowEndpointStyle) {
    arrowEndHead = head
    sharedAnnotationParameterDefaults.arrowEndHead = head.rawValue
    persistSharedAnnotationParameterDefaults()

    let arrowAnnotations = selectedArrowAnnotations
    if !arrowAnnotations.isEmpty {
      if arrowAnnotations.contains(where: {
        guard case .arrow(let geometry) = $0.type else { return false }
        return geometry.endHead != head
      }) {
        saveState()
      }
      arrowAnnotations.forEach { updateArrowEndHead(id: $0.id, head: head) }
    }
  }

  var activeBlurType: BlurType {
    if let annotation = selectedBlurAnnotations.first,
       case .blur(let type) = annotation.type {
      return type
    }
    return blurType
  }

  func setActiveBlurType(_ type: BlurType) {
    let blurAnnotations = selectedBlurAnnotations
    if !blurAnnotations.isEmpty {
      blurAnnotations.forEach { updateBlurType(id: $0.id, blurType: type) }
    } else {
      blurType = type
    }
  }

  var activeWatermarkStyle: WatermarkStyle {
    selectedWatermarkAnnotations.first?.properties.watermarkStyle
      ?? defaultAnnotationProperties(for: .watermark).watermarkStyle
  }

  func setActiveWatermarkStyle(_ style: WatermarkStyle) {
    let rotationDegrees = style.defaultRotationDegrees
    let watermarkAnnotations = selectedWatermarkAnnotations
    if !watermarkAnnotations.isEmpty {
      watermarkAnnotations.forEach {
        updateAnnotationProperties(
          id: $0.id,
          rotationDegrees: rotationDegrees,
          watermarkStyle: style
        )
      }
    } else {
      updateDefaultAnnotationProperties(
        for: .watermark,
        rotationDegrees: rotationDegrees,
        watermarkStyle: style
      )
    }
  }

  private func loadSharedAnnotationColor() {
    guard let data = defaults.data(forKey: PreferencesKeys.annotatePrimaryColor),
          let rgba = try? JSONDecoder().decode(RGBAColor.self, from: data) else {
      return
    }
    sharedAnnotationColor = rgba.color
    strokeColor = rgba.color
  }

  private func rememberSharedAnnotationColor(_ color: Color) {
    guard let rgba = RGBAColor(color: color),
          let data = try? JSONEncoder().encode(rgba) else {
      return
    }

    sharedAnnotationColor = color
    defaults.set(data, forKey: PreferencesKeys.annotatePrimaryColor)
    applySharedAnnotationColorToToolDefaults(color)
  }

  private func loadSharedAnnotationParameterDefaults() {
    guard let data = defaults.data(forKey: PreferencesKeys.annotateParameterDefaults),
          let decoded = try? JSONDecoder().decode(SharedAnnotationParameterDefaults.self, from: data)
    else { return }

    sharedAnnotationParameterDefaults = sanitizedSharedAnnotationParameterDefaults(decoded)

    if let savedStyleRaw = sharedAnnotationParameterDefaults.arrowStyle,
       let savedStyle = ArrowStyle(rawValue: savedStyleRaw) {
      arrowStyle = savedStyle
    }
    if let savedTypeRaw = sharedAnnotationParameterDefaults.arrowType,
       let savedType = ArrowType(rawValue: savedTypeRaw) {
      arrowType = savedType
    }
    if let savedBendRaw = sharedAnnotationParameterDefaults.arrowBendDirection,
       let savedBend = ArrowBendDirection(rawValue: savedBendRaw) {
      arrowBendDirection = savedBend
    }
    if let savedStartHeadRaw = sharedAnnotationParameterDefaults.arrowStartHead,
       let savedStartHead = ArrowEndpointStyle(rawValue: savedStartHeadRaw) {
      arrowStartHead = savedStartHead
    }
    if let savedEndHeadRaw = sharedAnnotationParameterDefaults.arrowEndHead,
       let savedEndHead = ArrowEndpointStyle(rawValue: savedEndHeadRaw) {
      arrowEndHead = savedEndHead
    }
  }

  private func persistSharedAnnotationParameterDefaults() {
    guard let data = try? JSONEncoder().encode(sharedAnnotationParameterDefaults) else { return }
    defaults.set(data, forKey: PreferencesKeys.annotateParameterDefaults)
  }

  private func sanitizedSharedAnnotationParameterDefaults(
    _ defaults: SharedAnnotationParameterDefaults
  ) -> SharedAnnotationParameterDefaults {
    SharedAnnotationParameterDefaults(
      strokeWidth: defaults.strokeWidth.map(AnnotationProperties.clampedControlValue(_:)),
      cornerRadius: defaults.cornerRadius.map { max(0, $0) },
      fontSize: defaults.fontSize.map { min(max($0, 12), 72) },
      watermarkOpacity: defaults.watermarkOpacity.map(AnnotationProperties.clampedOpacity(_:)),
      watermarkRotationDegrees: defaults.watermarkRotationDegrees.map(AnnotationProperties.clampedRotationDegrees(_:)),
      spotlightCornerRadius: defaults.spotlightCornerRadius.map { max(0, $0) },
      arrowStyle: defaults.arrowStyle,
      arrowType: defaults.arrowType,
      arrowBendDirection: defaults.arrowBendDirection,
      arrowStartHead: defaults.arrowStartHead,
      arrowEndHead: defaults.arrowEndHead
    )
  }

  private func loadAnnotationToolProperties() {
    guard let data = defaults.data(forKey: PreferencesKeys.annotateToolParameterDefaults),
          let decoded = try? JSONDecoder().decode([String: PersistedAnnotationProperties].self, from: data)
    else { return }

    annotationToolProperties = decoded.reduce(into: [:]) { result, entry in
      guard let tool = AnnotationToolType(rawValue: entry.key) else { return }
      result[tool] = sanitizedAnnotationProperties(entry.value.annotationProperties, for: tool)
    }
  }

  private func persistAnnotationToolProperties() {
    let payload = annotationToolProperties.reduce(into: [String: PersistedAnnotationProperties]()) { result, entry in
      guard let persisted = PersistedAnnotationProperties(entry.value) else { return }
      result[entry.key.rawValue] = persisted
    }

    guard let data = try? JSONEncoder().encode(payload) else { return }
    defaults.set(data, forKey: PreferencesKeys.annotateToolParameterDefaults)
  }

  private func sanitizedAnnotationProperties(
    _ properties: AnnotationProperties,
    for tool: AnnotationToolType
  ) -> AnnotationProperties {
    var sanitized = properties
    sanitized.strokeWidth = AnnotationProperties.clampedControlValue(properties.strokeWidth)
    sanitized.cornerRadius = max(0, properties.cornerRadius)
    sanitized.fontSize = min(max(properties.fontSize, 12), 72)
    sanitized.opacity = AnnotationProperties.clampedOpacity(properties.opacity)
    sanitized.rotationDegrees = AnnotationProperties.clampedRotationDegrees(properties.rotationDegrees)
    sanitized.spotlightOpacity = AnnotationProperties.clampedSpotlightOpacity(properties.spotlightOpacity)
    if tool == .filledRectangle {
      sanitized.fillColor = sanitized.strokeColor
    }
    return sanitized
  }

  private func rememberSharedAnnotationStrokeWidth(_ strokeWidth: CGFloat) {
    let clampedWidth = AnnotationProperties.clampedControlValue(strokeWidth)
    sharedAnnotationParameterDefaults.strokeWidth = clampedWidth
    persistSharedAnnotationParameterDefaults()

    for tool in AnnotationToolType.allCases where tool.supportsQuickStrokeWidth {
      updateDefaultAnnotationProperties(for: tool, strokeWidth: clampedWidth)
    }

    if !selectedTool.supportsQuickPropertiesBar {
      self.strokeWidth = clampedWidth
    }
  }

  private func rememberSharedAnnotationCornerRadius(_ cornerRadius: CGFloat) {
    let clampedRadius = max(0, cornerRadius)
    sharedAnnotationParameterDefaults.cornerRadius = clampedRadius
    persistSharedAnnotationParameterDefaults()

    for tool in AnnotationToolType.allCases where tool.supportsQuickCornerRadius && tool != .spotlight {
      updateDefaultAnnotationProperties(for: tool, cornerRadius: clampedRadius)
    }

    if !selectedTool.supportsQuickPropertiesBar {
      rectangleCornerRadius = clampedRadius
    }
  }

  private func rememberSharedSpotlightCornerRadius(_ cornerRadius: CGFloat) {
    let clampedRadius = max(0, cornerRadius)
    sharedAnnotationParameterDefaults.spotlightCornerRadius = clampedRadius
    persistSharedAnnotationParameterDefaults()
    updateDefaultAnnotationProperties(for: .spotlight, cornerRadius: clampedRadius)
  }

  private func rememberSharedAnnotationFontSize(_ fontSize: CGFloat) {
    let clampedSize = min(max(fontSize, 12), 72)
    sharedAnnotationParameterDefaults.fontSize = clampedSize
    persistSharedAnnotationParameterDefaults()

    updateDefaultAnnotationProperties(for: .text, fontSize: clampedSize)
    updateDefaultAnnotationProperties(for: .watermark, fontSize: clampedSize)
  }

  private func rememberSharedWatermarkOpacity(_ opacity: CGFloat) {
    let clampedOpacity = AnnotationProperties.clampedOpacity(opacity)
    sharedAnnotationParameterDefaults.watermarkOpacity = clampedOpacity
    persistSharedAnnotationParameterDefaults()
    updateDefaultAnnotationProperties(for: .watermark, opacity: clampedOpacity)
  }

  private func rememberSharedWatermarkRotation(_ rotationDegrees: CGFloat) {
    let clampedRotation = AnnotationProperties.clampedRotationDegrees(rotationDegrees)
    sharedAnnotationParameterDefaults.watermarkRotationDegrees = clampedRotation
    persistSharedAnnotationParameterDefaults()
    updateDefaultAnnotationProperties(for: .watermark, rotationDegrees: clampedRotation)
  }

  private func rememberAnnotationPrimaryColor(_ color: Color, for tool: AnnotationToolType?) {
    guard !isQuickPropertiesSyncEnabled else {
      rememberSharedAnnotationColor(color)
      return
    }

    if let tool, tool.supportsQuickStrokeColor {
      updateDefaultAnnotationProperties(for: tool, strokeColor: color)
    } else {
      strokeColor = color
    }
  }

  private func rememberAnnotationStrokeWidth(_ strokeWidth: CGFloat, for tool: AnnotationToolType?) {
    guard !isQuickPropertiesSyncEnabled else {
      rememberSharedAnnotationStrokeWidth(strokeWidth)
      return
    }

    let clampedWidth = AnnotationProperties.clampedControlValue(strokeWidth)
    if let tool, tool.supportsQuickStrokeWidth {
      updateDefaultAnnotationProperties(for: tool, strokeWidth: clampedWidth)
    } else {
      self.strokeWidth = clampedWidth
    }
  }

  private func rememberAnnotationCornerRadius(_ cornerRadius: CGFloat, for tool: AnnotationToolType?) {
    guard !isQuickPropertiesSyncEnabled else {
      if tool == .spotlight {
        rememberSharedSpotlightCornerRadius(cornerRadius)
      } else {
        rememberSharedAnnotationCornerRadius(cornerRadius)
      }
      return
    }

    let clampedRadius = max(0, cornerRadius)
    if let tool, tool.supportsQuickCornerRadius {
      updateDefaultAnnotationProperties(for: tool, cornerRadius: clampedRadius)
    } else {
      rectangleCornerRadius = clampedRadius
    }
  }

  private func rememberAnnotationFontSize(_ fontSize: CGFloat, for tool: AnnotationToolType?) {
    guard !isQuickPropertiesSyncEnabled else {
      rememberSharedAnnotationFontSize(fontSize)
      return
    }

    let clampedSize = min(max(fontSize, 12), 72)
    if let tool, tool == .text || tool == .watermark {
      updateDefaultAnnotationProperties(for: tool, fontSize: clampedSize)
    }
  }

  private func rememberWatermarkOpacity(_ opacity: CGFloat) {
    guard !isQuickPropertiesSyncEnabled else {
      rememberSharedWatermarkOpacity(opacity)
      return
    }

    updateDefaultAnnotationProperties(
      for: .watermark,
      opacity: AnnotationProperties.clampedOpacity(opacity)
    )
  }

  private func rememberWatermarkRotation(_ rotationDegrees: CGFloat) {
    guard !isQuickPropertiesSyncEnabled else {
      rememberSharedWatermarkRotation(rotationDegrees)
      return
    }

    updateDefaultAnnotationProperties(
      for: .watermark,
      rotationDegrees: AnnotationProperties.clampedRotationDegrees(rotationDegrees)
    )
  }

  private func applySharedAnnotationColorToToolDefaults(_ color: Color) {
    for tool in AnnotationToolType.allCases where tool.supportsQuickStrokeColor {
      var properties = defaultAnnotationProperties(for: tool)
      properties.strokeColor = color
      if tool == .filledRectangle {
        properties.fillColor = color
      }
      annotationToolProperties[tool] = properties
    }
    persistAnnotationToolProperties()

    if selectedTool.supportsQuickPropertiesBar {
      applyToolPropertiesToLegacyState(defaultAnnotationProperties(for: selectedTool), for: selectedTool)
    } else {
      strokeColor = color
    }
  }

  private func defaultAnnotationProperties(for tool: AnnotationToolType?) -> AnnotationProperties {
    guard let tool else {
      var properties = AnnotationProperties(strokeColor: sharedAnnotationColor ?? .red)
      applySharedParameterDefaults(to: &properties, for: nil)
      return properties
    }
    var properties = annotationToolProperties[tool] ?? baseAnnotationProperties(for: tool)
    if isQuickPropertiesSyncEnabled {
      applySynchronizedQuickProperties(to: &properties, for: tool)
    }

    return properties
  }

  private func baseAnnotationProperties(for tool: AnnotationToolType) -> AnnotationProperties {
    if tool == .spotlight {
      var properties = AnnotationProperties(
        strokeColor: sharedAnnotationColor ?? .red,
        fillColor: .clear,
        strokeWidth: 3,
        cornerRadius: 14,
        opacity: 1.0,
        spotlightOpacity: spotlightOpacity
      )
      applySharedParameterDefaults(to: &properties, for: tool)
      return properties
    }
    if tool != .watermark {
      var properties = AnnotationProperties(strokeColor: sharedAnnotationColor ?? .red)
      if tool == .blur {
        properties.strokeWidth = AnnotationProperties.controlValueRange.lowerBound
      }
      applySharedParameterDefaults(to: &properties, for: tool)
      if tool == .filledRectangle {
        properties.fillColor = properties.strokeColor
      }
      return properties
    }

    let strokeColor = sharedAnnotationColor ?? Color.white
    var properties = AnnotationProperties(
      strokeColor: strokeColor,
      fillColor: .clear,
      strokeWidth: 3,
      cornerRadius: 0,
      fontSize: 36,
      fontName: "SF Pro",
      opacity: 0.22,
      rotationDegrees: WatermarkStyle.diagonal.defaultRotationDegrees,
      watermarkStyle: .diagonal
    )
    applySharedParameterDefaults(to: &properties, for: tool)
    return properties
  }

  private func applySynchronizedQuickProperties(
    to properties: inout AnnotationProperties,
    for tool: AnnotationToolType
  ) {
    let sharedProperties = baseAnnotationProperties(for: tool)

    if tool.supportsQuickStrokeColor {
      properties.strokeColor = sharedProperties.strokeColor
      if tool == .filledRectangle {
        properties.fillColor = sharedProperties.strokeColor
      }
    }

    if tool.supportsQuickStrokeWidth {
      properties.strokeWidth = sharedProperties.strokeWidth
    }

    if tool.supportsQuickCornerRadius {
      properties.cornerRadius = sharedProperties.cornerRadius
    }

    if tool == .text || tool == .watermark {
      properties.fontSize = sharedProperties.fontSize
    }

    if tool == .watermark {
      if sharedAnnotationParameterDefaults.watermarkOpacity != nil {
        properties.opacity = sharedProperties.opacity
      }
      if sharedAnnotationParameterDefaults.watermarkRotationDegrees != nil {
        properties.rotationDegrees = sharedProperties.rotationDegrees
      }
    }
  }

  private func applySharedParameterDefaults(
    to properties: inout AnnotationProperties,
    for tool: AnnotationToolType?
  ) {
    let defaults = sharedAnnotationParameterDefaults

    if tool == nil || tool?.supportsQuickStrokeWidth == true,
       let strokeWidth = defaults.strokeWidth {
      properties.strokeWidth = strokeWidth
    }

    if tool == .spotlight {
      if let cornerRadius = defaults.spotlightCornerRadius {
        properties.cornerRadius = cornerRadius
      } else {
        properties.cornerRadius = 14
      }
    } else if tool == nil || tool?.supportsQuickCornerRadius == true {
      if let cornerRadius = defaults.cornerRadius {
        properties.cornerRadius = cornerRadius
      }
    }

    if tool == nil || tool == .text || tool == .watermark,
       let fontSize = defaults.fontSize {
      properties.fontSize = fontSize
    }

    if tool == nil || tool == .watermark {
      if let watermarkOpacity = defaults.watermarkOpacity {
        properties.opacity = watermarkOpacity
      }
      if let watermarkRotationDegrees = defaults.watermarkRotationDegrees {
        properties.rotationDegrees = watermarkRotationDegrees
      }
    }
  }

  func annotationCreationProperties(for tool: AnnotationToolType) -> AnnotationProperties {
    var properties = defaultAnnotationProperties(for: tool)
    if tool == .text, shouldUseRecommendedTextFontSize {
      properties.fontSize = recommendedTextFontSize()
    }
    if tool == .filledRectangle {
      properties.fillColor = properties.strokeColor
    }
    return properties
  }

  /// Starts new text at a readable size relative to the current image or combined canvas.
  /// A manually chosen text size is always preserved for subsequent annotations.
  func recommendedTextFontSize() -> CGFloat {
    let canvasSize = effectiveContentBounds.size
    let shortSide = max(min(canvasSize.width, canvasSize.height), 1)
    let suggested = shortSide * 0.026
    let stepped = (suggested / 2).rounded() * 2
    return min(max(stepped, 16), 36)
  }

  private var shouldUseRecommendedTextFontSize: Bool {
    sharedAnnotationParameterDefaults.fontSize == nil && annotationToolProperties[.text] == nil
  }

  private func updateDefaultAnnotationProperties(
    for tool: AnnotationToolType,
    strokeWidth: CGFloat? = nil,
    strokeColor: Color? = nil,
    fillColor: Color? = nil,
    cornerRadius: CGFloat? = nil,
    fontSize: CGFloat? = nil,
    fontName: String? = nil,
    opacity: CGFloat? = nil,
    rotationDegrees: CGFloat? = nil,
    watermarkStyle: WatermarkStyle? = nil,
    spotlightOpacity: CGFloat? = nil
  ) {
    var properties = defaultAnnotationProperties(for: tool)

    if let strokeWidth = strokeWidth {
      properties.strokeWidth = AnnotationProperties.clampedControlValue(strokeWidth)
    }
    if tool == .filledRectangle,
       let color = strokeColor ?? fillColor {
      properties.strokeColor = color
      properties.fillColor = color
    } else {
      if let strokeColor = strokeColor {
        properties.strokeColor = strokeColor
      }
      if let fillColor = fillColor {
        properties.fillColor = fillColor
      }
    }
    if let cornerRadius = cornerRadius {
      properties.cornerRadius = max(0, cornerRadius)
    }
    if let fontSize = fontSize {
      properties.fontSize = min(max(fontSize, 12), 72)
    }
    if let fontName = fontName {
      properties.fontName = fontName
    }
    if let opacity = opacity {
      properties.opacity = AnnotationProperties.clampedOpacity(opacity)
    }
    if let rotationDegrees = rotationDegrees {
      properties.rotationDegrees = AnnotationProperties.clampedRotationDegrees(rotationDegrees)
    }
    if let watermarkStyle = watermarkStyle {
      properties.watermarkStyle = watermarkStyle
    }
    if let spotlightOpacity = spotlightOpacity {
      properties.spotlightOpacity = AnnotationProperties.clampedSpotlightOpacity(spotlightOpacity)
    }

    let sanitized = sanitizedAnnotationProperties(properties, for: tool)
    annotationToolProperties[tool] = sanitized
    persistAnnotationToolProperties()
    if selectedTool == tool {
      applyToolPropertiesToLegacyState(sanitized, for: tool)
    }
  }

  private func counterBounds(center: CGPoint, controlValue: CGFloat) -> CGRect {
    let diameter = AnnotationProperties.counterDiameter(for: controlValue)
    return CGRect(
      x: center.x - diameter / 2,
      y: center.y - diameter / 2,
      width: diameter,
      height: diameter
    )
  }

  private func syncActiveToolProperties() {
    guard selectedTool.supportsQuickPropertiesBar else { return }
    applyToolPropertiesToLegacyState(defaultAnnotationProperties(for: selectedTool), for: selectedTool)
  }

  private func applyToolPropertiesToLegacyState(
    _ properties: AnnotationProperties,
    for tool: AnnotationToolType
  ) {
    strokeColor = properties.strokeColor
    fillColor = properties.fillColor
    strokeWidth = properties.strokeWidth
    if tool.supportsQuickCornerRadius {
      rectangleCornerRadius = properties.cornerRadius
    }
    if tool == .spotlight {
      spotlightOpacity = properties.spotlightOpacity
    }
  }

  private var quickPropertiesSelectionAnnotations: [AnnotationItem] {
    guard editorMode == .annotate,
          selectedTool != .crop else { return [] }
    return selectedAnnotations
  }

  private var quickPropertiesSelectionTargets: [AnnotationItem] {
    let selected = quickPropertiesSelectionAnnotations
    guard !selected.isEmpty else { return [] }
    if selected.count == 1 {
      guard selected[0].type.supportsQuickPropertiesBar else { return [] }
    }
    return selected
  }

  private var quickPropertiesCommonSelectedTool: AnnotationToolType? {
    let selected = quickPropertiesSelectionAnnotations
    guard !selected.isEmpty else { return nil }
    let tools = Set(selected.map { $0.type.toolType })
    guard tools.count == 1 else { return nil }
    return tools.first
  }

  private func quickSelectionAnySupport(_ predicate: (AnnotationType) -> Bool) -> Bool {
    let selected = quickPropertiesSelectionTargets
    guard !selected.isEmpty else { return false }
    return selected.contains { predicate($0.type) }
  }

  private func quickSelectionTargets(matching predicate: (AnnotationType) -> Bool) -> [AnnotationItem] {
    quickPropertiesSelectionTargets.filter { predicate($0.type) }
  }

  func setQuickPropertiesControlEditing(_ isEditing: Bool) {
    if isEditing {
      beginQuickPropertiesGestureUndoIfNeeded()
    } else {
      isQuickPropertiesGestureEditing = false
      quickPropertiesGestureUndoSnapshot = nil
    }
  }

  private func beginQuickPropertiesGestureUndoIfNeeded() {
    guard !isQuickPropertiesGestureEditing,
          !quickPropertiesSelectionTargets.isEmpty else { return }
    isQuickPropertiesGestureEditing = true
    quickPropertiesGestureUndoSnapshot = currentSnapshot()
  }

  private func updateQuickSelectionProperties(
    strokeWidth: CGFloat? = nil,
    strokeColor: Color? = nil,
    fillColor: Color? = nil,
    cornerRadius: CGFloat? = nil,
    fontSize: CGFloat? = nil,
    opacity: CGFloat? = nil,
    rotationDegrees: CGFloat? = nil,
    watermarkStyle: WatermarkStyle? = nil,
    spotlightOpacity: CGFloat? = nil,
    recordsUndo: Bool = false,
    matching predicate: ((AnnotationType) -> Bool)? = nil
  ) -> Bool {
    let selected = quickPropertiesSelectionTargets.filter { annotation in
      predicate?(annotation.type) ?? true
    }
    guard !selected.isEmpty else { return false }

    let shouldRecordUndo = recordsUndo && selected.contains(where: {
      annotationPropertiesWillChange(
        $0,
        strokeWidth: strokeWidth,
        fontSize: fontSize,
        strokeColor: strokeColor,
        fillColor: fillColor,
        cornerRadius: cornerRadius,
        opacity: opacity,
        rotationDegrees: rotationDegrees,
        watermarkStyle: watermarkStyle,
        spotlightOpacity: spotlightOpacity
      )
    })

    if shouldRecordUndo {
      if let snapshot = quickPropertiesGestureUndoSnapshot {
        pushUndoSnapshot(snapshot, annotationCount: snapshot.annotations.count)
        quickPropertiesGestureUndoSnapshot = nil
      } else if !isQuickPropertiesGestureEditing {
        saveState()
      }
    }

    for annotation in selected {
      updateAnnotationProperties(
        id: annotation.id,
        strokeWidth: strokeWidth,
        fontSize: fontSize,
        strokeColor: strokeColor,
        fillColor: fillColor,
        cornerRadius: cornerRadius,
        opacity: opacity,
        rotationDegrees: rotationDegrees,
        watermarkStyle: watermarkStyle,
        spotlightOpacity: spotlightOpacity
      )
    }
    return true
  }

  var quickPropertiesSupportsArrowStyle: Bool {
    guard editorMode == .annotate,
          selectedTool != .crop else {
      return false
    }

    let selected = quickPropertiesSelectionAnnotations
    if !selected.isEmpty {
      return selected.contains {
        if case .arrow = $0.type { return true }
        return false
      }
    }

    return quickPropertiesTool == .arrow
  }

  var quickPropertiesSupportsArrowBendDirection: Bool {
    guard quickPropertiesSupportsArrowStyle else {
      return false
    }

    let selected = quickPropertiesSelectionAnnotations
    if !selected.isEmpty {
      return selected.contains {
        guard case .arrow(let geometry) = $0.type else { return false }
        return geometry.style.supportsBendDirection
      }
    }

    return quickPropertiesTool == .arrow && activeArrowStyle.supportsBendDirection
  }

  /// Per-endpoint head styles apply to the classic (stroked line) display type.
  var quickPropertiesSupportsArrowEndpoints: Bool {
    guard quickPropertiesSupportsArrowStyle else {
      return false
    }

    let selected = quickPropertiesSelectionAnnotations
    if !selected.isEmpty {
      return selected.contains {
        guard case .arrow(let geometry) = $0.type else { return false }
        return geometry.arrowType == .classic
      }
    }

    return quickPropertiesTool == .arrow && activeArrowType == .classic
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

  var quickArrowTypeBinding: Binding<ArrowType> {
    Binding(
      get: { [weak self] in
        self?.activeArrowType ?? .tapered
      },
      set: { [weak self] newType in
        self?.setActiveArrowType(newType)
      }
    )
  }

  var quickArrowBendDirectionBinding: Binding<ArrowBendDirection> {
    Binding(
      get: { [weak self] in
        self?.activeArrowBendDirection ?? .primary
      },
      set: { [weak self] newDirection in
        self?.setActiveArrowBendDirection(newDirection)
      }
    )
  }

  var quickArrowStartHeadBinding: Binding<ArrowEndpointStyle> {
    Binding(
      get: { [weak self] in
        self?.activeArrowStartHead ?? .none
      },
      set: { [weak self] newHead in
        self?.setActiveArrowStartHead(newHead)
      }
    )
  }

  var quickArrowEndHeadBinding: Binding<ArrowEndpointStyle> {
    Binding(
      get: { [weak self] in
        self?.activeArrowEndHead ?? .arrow
      },
      set: { [weak self] newHead in
        self?.setActiveArrowEndHead(newHead)
      }
    )
  }

  var quickPropertiesSupportsTextFontSize: Bool {
    guard editorMode == .annotate,
          selectedTool != .crop else {
      return false
    }

    let selected = quickPropertiesSelectionAnnotations
    if !selected.isEmpty {
      return selected.contains {
        switch $0.type {
        case .text, .watermark:
          return true
        default:
          return false
        }
      }
    }

    return quickPropertiesTool == .text || quickPropertiesTool == .watermark
  }

  var quickPropertiesSupportsTextBackground: Bool {
    guard editorMode == .annotate,
          selectedTool != .crop else {
      return false
    }

    let selected = quickPropertiesSelectionAnnotations
    if !selected.isEmpty {
      return selected.contains {
        if case .text = $0.type { return true }
        return false
      }
    }

    return quickPropertiesTool == .text
  }

  var quickPropertiesSupportsTextPresentation: Bool {
    quickPropertiesSupportsTextBackground
  }

  var quickTextPresentation: TextPresentation {
    quickSelectionTargets(matching: {
      if case .text = $0 { return true }
      return false
    }).first?.properties.textPresentation
      ?? defaultAnnotationProperties(for: quickPropertiesTool).textPresentation
  }

  func setTextPresentation(_ presentation: TextPresentation) {
    let selected = quickSelectionTargets(matching: {
      if case .text = $0 { return true }
      return false
    })

    guard !selected.isEmpty else {
      guard quickPropertiesTool == .text else { return }
      var properties = defaultAnnotationProperties(for: .text)
      properties.textPresentation = presentation
      properties.calloutTailTarget = nil
      if presentation != .plain, properties.fillColor == .clear {
        properties.fillColor = .black
      }
      annotationToolProperties[.text] = properties
      return
    }

    saveState()
    for annotation in selected {
      guard let index = annotations.firstIndex(where: { $0.id == annotation.id }) else { continue }
      annotations[index].properties.textPresentation = presentation
      if presentation == .plain {
        annotations[index].properties.calloutTailTarget = nil
      } else if presentation == .callout {
        annotations[index].properties.calloutTailTarget = annotations[index].properties.calloutTailTarget
          ?? defaultCalloutTailTarget(for: annotations[index].bounds, fontSize: annotations[index].properties.fontSize)
      } else {
        annotations[index].properties.calloutTailTarget = nil
      }
      if presentation != .plain, annotations[index].properties.fillColor == .clear {
        annotations[index].properties.fillColor = .black
      }
    }
    hasUnsavedChanges = true
  }

  func prepareTextCalloutTail(for id: UUID) {
    guard let index = annotations.firstIndex(where: { $0.id == id }),
          case .text = annotations[index].type,
          annotations[index].properties.textPresentation == .callout,
          annotations[index].properties.calloutTailTarget == nil else { return }
    annotations[index].properties.calloutTailTarget = defaultCalloutTailTarget(for: annotations[index].bounds, fontSize: annotations[index].properties.fontSize)
  }

  func updateTextCalloutTail(id: UUID, target: CGPoint) {
    guard let index = annotations.firstIndex(where: { $0.id == id }),
          case .text = annotations[index].type,
          annotations[index].properties.textPresentation == .callout else { return }
    annotations[index].properties.calloutTailTarget = TextBubbleGeometry.resolvedTailTarget(
      in: annotations[index].bounds,
      requestedTarget: target,
      fontSize: annotations[index].properties.fontSize
    )
    hasUnsavedChanges = true
  }

  private func defaultCalloutTailTarget(for bounds: CGRect, fontSize: CGFloat) -> CGPoint {
    TextBubbleGeometry.defaultTailTarget(for: bounds, fontSize: fontSize)
  }

  var quickTextFontSizeBinding: Binding<CGFloat> {
    Binding(
      get: { [weak self] in
        guard let self else { return 16 }
        return self.quickSelectionTargets(matching: {
          switch $0 {
          case .text, .watermark:
            return true
          default:
            return false
          }
        }).first?.properties.fontSize
          ?? self.defaultAnnotationProperties(for: self.quickPropertiesTool).fontSize
      },
      set: { [weak self] newSize in
        guard let self else { return }
        let clampedSize = min(max(newSize, 12), 72)
        if !self.updateQuickSelectionProperties(
          fontSize: clampedSize,
          recordsUndo: true,
          matching: {
            switch $0 {
            case .text, .watermark:
              return true
            default:
              return false
            }
          }
        ) {
          self.rememberAnnotationFontSize(clampedSize, for: self.quickPropertiesTool)
        }
      }
    )
  }

  var quickTextBackgroundBinding: Binding<Color> {
    Binding(
      get: { [weak self] in
        guard let self else { return .clear }
        return self.quickSelectionTargets(matching: {
          if case .text = $0 { return true }
          return false
        }).first?.properties.fillColor
          ?? self.defaultAnnotationProperties(for: self.quickPropertiesTool).fillColor
      },
      set: { [weak self] newColor in
        guard let self else { return }
        if !self.updateQuickSelectionProperties(
          fillColor: newColor,
          recordsUndo: true,
          matching: {
            if case .text = $0 { return true }
            return false
          }
        ) {
          if let tool = self.quickPropertiesTool {
            self.updateDefaultAnnotationProperties(for: tool, fillColor: newColor)
          }
        }
      }
    )
  }

  var quickPropertiesSupportsBlurType: Bool {
    guard editorMode == .annotate,
          selectedTool != .crop else {
      return false
    }

    let selected = quickPropertiesSelectionAnnotations
    if !selected.isEmpty {
      return selected.contains {
        if case .blur = $0.type { return true }
        return false
      }
    }

    return quickPropertiesTool == .blur
  }

  var quickBlurTypeBinding: Binding<BlurType> {
    Binding(
      get: { [weak self] in
        self?.activeBlurType ?? .pixelated
      },
      set: { [weak self] newType in
        self?.setActiveBlurType(newType)
      }
    )
  }

  var quickPropertiesSupportsWatermark: Bool {
    guard editorMode == .annotate,
          selectedTool != .crop else {
      return false
    }

    let selected = quickPropertiesSelectionAnnotations
    if !selected.isEmpty {
      return selected.contains {
        if case .watermark = $0.type { return true }
        return false
      }
    }

    return quickPropertiesTool == .watermark
  }

  var quickWatermarkTextBinding: Binding<String> {
    Binding(
      get: { [weak self] in
        guard let self else { return "Snapzy" }
        if let annotation = self.quickSelectionTargets(matching: {
          if case .watermark = $0 { return true }
          return false
        }).first,
           case .watermark(let text) = annotation.type {
          return text
        }
        return self.watermarkText
      },
      set: { [weak self] newText in
        guard let self else { return }
        let selected = self.quickSelectionTargets(matching: {
          if case .watermark = $0 { return true }
          return false
        })
        if selected.isEmpty {
          self.watermarkText = newText
        } else {
          selected.forEach { self.updateWatermarkText(id: $0.id, text: newText) }
        }
      }
    )
  }

  var quickWatermarkStyleBinding: Binding<WatermarkStyle> {
    Binding(
      get: { [weak self] in
        self?.activeWatermarkStyle ?? .diagonal
      },
      set: { [weak self] newStyle in
        self?.setActiveWatermarkStyle(newStyle)
      }
    )
  }

  var quickWatermarkOpacityBinding: Binding<CGFloat> {
    Binding(
      get: { [weak self] in
        guard let self else { return 0.22 }
        return self.quickSelectionTargets(matching: {
          if case .watermark = $0 { return true }
          return false
        }).first?.properties.opacity
          ?? self.defaultAnnotationProperties(for: self.quickPropertiesTool).opacity
      },
      set: { [weak self] newOpacity in
        guard let self else { return }
        let clampedOpacity = AnnotationProperties.clampedOpacity(newOpacity)
        if !self.updateQuickSelectionProperties(
          opacity: clampedOpacity,
          recordsUndo: true,
          matching: {
            if case .watermark = $0 { return true }
            return false
          }
        ) {
          self.rememberWatermarkOpacity(clampedOpacity)
        }
      }
    )
  }

  var quickWatermarkRotationBinding: Binding<CGFloat> {
    Binding(
      get: { [weak self] in
        guard let self else { return -24 }
        return self.quickSelectionTargets(matching: {
          if case .watermark = $0 { return true }
          return false
        }).first?.properties.rotationDegrees
          ?? self.defaultAnnotationProperties(for: self.quickPropertiesTool).rotationDegrees
      },
      set: { [weak self] newRotation in
        guard let self else { return }
        let clampedRotation = AnnotationProperties.clampedRotationDegrees(newRotation)
        if !self.updateQuickSelectionProperties(
          rotationDegrees: clampedRotation,
          recordsUndo: true,
          matching: {
            if case .watermark = $0 { return true }
            return false
          }
        ) {
          self.rememberWatermarkRotation(clampedRotation)
        }
      }
    )
  }

  var quickPropertiesAnnotation: AnnotationItem? {
    guard let annotation = quickPropertiesSelectionAnnotations.first,
          quickPropertiesSelectionAnnotations.count == 1,
          annotation.type.supportsQuickPropertiesBar else {
      return nil
    }
    return annotation
  }

  var quickPropertiesMode: QuickPropertiesMode {
    if !quickPropertiesSelectionAnnotations.isEmpty {
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

    if quickPropertiesSelectionAnnotations.count == 1 {
      return quickPropertiesSelectionAnnotations[0].type.toolType
    }

    if quickPropertiesSelectionAnnotations.count > 1 {
      return quickPropertiesCommonSelectedTool ?? .selection
    }

    guard editorMode == .annotate,
          selectedTool != .crop,
          selectedTool.supportsQuickPropertiesBar else {
      return nil
    }
    return selectedTool
  }

  var quickPropertiesSelectedAnnotationCount: Int {
    quickPropertiesSelectionAnnotations.count
  }

  var quickPropertiesShowsSelectionStyle: Bool {
    guard editorMode == .annotate,
          selectedTool != .crop else {
      return false
    }

    if quickPropertiesSelectionAnnotations.isEmpty {
      return selectedTool == .selection
    }

    return quickPropertiesSelectionAnnotations.allSatisfy { annotation in
      annotation.type.toolType == .selection || !annotation.type.supportsQuickPropertiesBar
    }
  }

  var showsQuickPropertiesBar: Bool {
    quickPropertiesMode != .hidden
  }

  var quickPropertiesContextTitle: String {
    switch quickPropertiesMode {
    case .selectedItem:
      if quickPropertiesSelectionAnnotations.count > 1 {
        return L10n.AnnotateContext.selected("\(quickPropertiesSelectionAnnotations.count)")
      }
      let tool = quickPropertiesCommonSelectedTool ?? quickPropertiesTool
      guard let tool, tool != .selection else {
        return L10n.AnnotateContext.selected(L10n.AnnotateUI.annotation)
      }
      return L10n.AnnotateContext.selected(tool.displayName)
    case .toolDefaults:
      guard let tool = quickPropertiesTool else { return "" }
      return L10n.AnnotateContext.defaults(tool.displayName)
    case .hidden:
      return ""
    }
  }

  var quickPropertiesSupportsStrokeColor: Bool {
    if !quickPropertiesSelectionAnnotations.isEmpty {
      return quickSelectionAnySupport { $0.supportsQuickStrokeColor }
    }
    return quickPropertiesTool?.supportsQuickStrokeColor ?? false
  }

  var quickPropertiesSupportsFill: Bool {
    if !quickPropertiesSelectionAnnotations.isEmpty {
      return quickSelectionAnySupport { $0.supportsQuickFillColor }
    }
    return quickPropertiesTool?.supportsQuickFillColor ?? false
  }

  var quickPropertiesSupportsStrokeWidth: Bool {
    if !quickPropertiesSelectionAnnotations.isEmpty {
      return quickSelectionAnySupport { $0.supportsQuickStrokeWidth }
    }
    return quickPropertiesTool?.supportsQuickStrokeWidth ?? false
  }

  var quickStrokeWidthLabel: String {
    quickStrokeWidthUsesSizeLabel ? L10n.Common.size : L10n.Common.stroke
  }

  var quickStrokeWidthIcon: String {
    quickStrokeWidthUsesSizeLabel ? "arrow.up.left.and.arrow.down.right" : "line.diagonal"
  }

  var quickStrokeWidthDisplayText: String {
    let controlValue = quickStrokeWidthValue

    switch quickStrokeWidthSemanticTool {
    case .counter:
      return "\(Int(AnnotationProperties.counterDiameter(for: controlValue).rounded()))"
    case .blur:
      let value: CGFloat
      switch activeBlurType {
      case .pixelated:
        value = AnnotationProperties.pixelatedBlurSize(for: controlValue)
      case .gaussian:
        value = AnnotationProperties.gaussianBlurRadius(for: controlValue)
      case .hexagonal:
        value = AnnotationProperties.hexagonalScale(for: controlValue)
      case .crystallized:
        value = AnnotationProperties.crystallizeRadius(for: controlValue)
      case .pointillism:
        value = AnnotationProperties.pointillismRadius(for: controlValue)
      case .halftone:
        value = AnnotationProperties.halftoneWidth(for: controlValue)
      case .tape:
        value = AnnotationProperties.tapePatternSpacing(for: controlValue)
      case .washi:
        value = AnnotationProperties.washiPatternSpacing(for: controlValue)
      }
      return "\(Int(value.rounded()))"
    default:
      return "\(Int(controlValue.rounded()))"
    }
  }

  private var quickStrokeWidthUsesSizeLabel: Bool {
    switch quickStrokeWidthSemanticTool {
    case .blur, .counter:
      return true
    default:
      return false
    }
  }

  private var quickStrokeWidthSemanticTool: AnnotationToolType? {
    let selectedStrokeTargets = quickSelectionTargets(matching: { $0.supportsQuickStrokeWidth })
    if !selectedStrokeTargets.isEmpty {
      let tools = Set(selectedStrokeTargets.map { $0.type.toolType })
      guard tools.count == 1 else { return nil }
      return tools.first
    }
    return quickPropertiesTool
  }

  private var quickStrokeWidthValue: CGFloat {
    quickSelectionTargets(matching: { $0.supportsQuickStrokeWidth }).first?.properties.strokeWidth
      ?? defaultAnnotationProperties(for: quickPropertiesTool).strokeWidth
  }

  var quickPropertiesSupportsCornerRadius: Bool {
    if !quickPropertiesSelectionAnnotations.isEmpty {
      return quickSelectionAnySupport { $0.toolType.supportsQuickCornerRadius }
    }
    return quickPropertiesTool?.supportsQuickCornerRadius ?? false
  }

  var quickPropertiesSupportsSpotlightOpacity: Bool {
    if !quickPropertiesSelectionAnnotations.isEmpty {
      return quickSelectionAnySupport { if case .spotlight = $0 { return true }; return false }
    }
    return quickPropertiesTool == .spotlight
  }

  var quickStrokeColorBinding: Binding<Color> {
    Binding(
      get: { [weak self] in
        guard let self else { return .red }
        return self.quickSelectionTargets(matching: { $0.supportsQuickStrokeColor }).first?.properties.strokeColor
          ?? self.defaultAnnotationProperties(for: self.quickPropertiesTool).strokeColor
      },
      set: { [weak self] newColor in
        guard let self else { return }
        let didUpdateSelection = self.updateQuickSelectionProperties(
          strokeColor: newColor,
          recordsUndo: true,
          matching: { $0.supportsQuickStrokeColor }
        )
        if didUpdateSelection {
          if self.isQuickPropertiesSyncEnabled {
            self.rememberSharedAnnotationColor(newColor)
          }
        } else {
          self.rememberAnnotationPrimaryColor(newColor, for: self.quickPropertiesTool)
        }
        if !didUpdateSelection, self.quickPropertiesTool == nil {
          self.strokeColor = newColor
        }
      }
    )
  }

  var quickFillColorBinding: Binding<Color> {
    Binding(
      get: { [weak self] in
        guard let self else { return .clear }
        return self.quickSelectionTargets(matching: { $0.supportsQuickFillColor }).first?.properties.fillColor
          ?? self.defaultAnnotationProperties(for: self.quickPropertiesTool).fillColor
      },
      set: { [weak self] newColor in
        guard let self else { return }
        if !self.updateQuickSelectionProperties(
          fillColor: newColor,
          recordsUndo: true,
          matching: { $0.supportsQuickFillColor }
        ) {
          if let tool = self.quickPropertiesTool {
            self.updateDefaultAnnotationProperties(for: tool, fillColor: newColor)
          } else {
            self.fillColor = newColor
          }
        }
      }
    )
  }

  var quickStrokeWidthBinding: Binding<CGFloat> {
    Binding(
      get: { [weak self] in
        guard let self else { return 3 }
        return self.quickSelectionTargets(matching: { $0.supportsQuickStrokeWidth }).first?.properties.strokeWidth
          ?? self.defaultAnnotationProperties(for: self.quickPropertiesTool).strokeWidth
      },
      set: { [weak self] newWidth in
        guard let self else { return }
        if !self.updateQuickSelectionProperties(
          strokeWidth: newWidth,
          recordsUndo: true,
          matching: { $0.supportsQuickStrokeWidth }
        ) {
          self.rememberAnnotationStrokeWidth(newWidth, for: self.quickPropertiesTool)
        }
      }
    )
  }

  var quickCornerRadiusBinding: Binding<CGFloat> {
    Binding(
      get: { [weak self] in
        guard let self else { return 0 }
        return self.quickSelectionTargets(matching: { $0.toolType.supportsQuickCornerRadius }).first?.properties.cornerRadius
          ?? self.defaultAnnotationProperties(for: self.quickPropertiesTool).cornerRadius
      },
      set: { [weak self] newRadius in
        guard let self else { return }
        let clampedRadius = max(0, newRadius)
        if !self.updateQuickSelectionProperties(
          cornerRadius: clampedRadius,
          recordsUndo: true,
          matching: { $0.toolType.supportsQuickCornerRadius }
        ) {
          self.rememberAnnotationCornerRadius(clampedRadius, for: self.quickPropertiesTool)
        }
      }
    )
  }

  var quickSpotlightOpacityBinding: Binding<CGFloat> {
    Binding(
      get: { [weak self] in
        guard let self else { return 0.5 }
        return self.quickSelectionTargets(matching: { if case .spotlight = $0 { return true }; return false }).first?.properties.spotlightOpacity
          ?? self.defaultAnnotationProperties(for: self.quickPropertiesTool).spotlightOpacity
      },
      set: { [weak self] newOpacity in
        guard let self else { return }
        if !self.updateQuickSelectionProperties(
          spotlightOpacity: newOpacity,
          recordsUndo: true,
          matching: { if case .spotlight = $0 { return true }; return false }
        ) {
          self.rememberAnnotationSpotlightOpacity(newOpacity, for: self.quickPropertiesTool)
        }
      }
    )
  }

  private func rememberAnnotationSpotlightOpacity(_ opacity: CGFloat, for tool: AnnotationToolType?) {
    let clampedOpacity = AnnotationProperties.clampedSpotlightOpacity(opacity)
    // Always sync the global published value so annotationCreationProperties picks it up for new regions.
    self.spotlightOpacity = clampedOpacity
    if let tool, tool == .spotlight {
      updateDefaultAnnotationProperties(for: tool, spotlightOpacity: clampedOpacity)
    }
  }

  func activateTool(_ tool: AnnotationToolType) {
    if editingTextAnnotationId != nil {
      commitTextEditing()
    }
    if tool != .selection {
      // A selected combined-image layer must not keep its handles or consume
      // clicks after the user switches back to drawing annotations.
      deselectAnnotation()
    }
    selectedTool = tool
  }

  func deleteSelectedAnnotation() {
    let selectedIds = selectedAnnotationIds
    guard !selectedIds.isEmpty else { return }
    DiagnosticLogger.shared.log(.debug, .annotate, "Delete annotation", context: [
      "count": "\(selectedIds.count)"
    ])
    saveState()
    annotations.removeAll { selectedIds.contains($0.id) }
    autoSizingTextAnnotationIDs.subtract(selectedIds)
    selectedIds.forEach { freeCombineBoundsByAnnotationID.removeValue(forKey: $0) }
    pruneUnusedEmbeddedAssets()
    updateImportWarningIfNeeded()
    refreshCombineLayout()
    deselectAnnotation()
  }

  /// Commit the current text editing and exit edit mode
  func commitTextEditing() {
    guard let editingId = editingTextAnnotationId else { return }

    if let annotation = annotations.first(where: { $0.id == editingId }),
       case .text(let text) = annotation.type {
      let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
      if trimmed.isEmpty {
        recordTextEditingUndoIfNeeded(id: editingId, newText: trimmed)
        annotations.removeAll { $0.id == editingId }
        selectedAnnotationId = nil
        hasUnsavedChanges = true
      } else {
        updateAnnotationText(id: editingId, text: trimmed)
      }
    }
    finishTextEditing()
  }

  /// Deselect current annotation
  func deselectAnnotation() {
    setSelectedAnnotationIds([])
    finishTextEditing()
  }

  /// Nudge selected annotation by delta
  func nudgeSelectedAnnotation(dx: CGFloat, dy: CGFloat) {
    let selectedIds = selectedAnnotationIds
    guard !selectedIds.isEmpty else { return }

    saveState()
    for index in annotations.indices where selectedIds.contains(annotations[index].id) {
      translateAnnotation(at: index, dx: dx, dy: dy)
    }
  }

  private func translateAnnotations(dx: CGFloat, dy: CGFloat) {
    guard dx != 0 || dy != 0 else { return }
    for index in annotations.indices {
      translateAnnotation(at: index, dx: dx, dy: dy)
    }
  }

  private func translateAnnotation(at index: Int, dx: CGFloat, dy: CGFloat) {
    annotations[index].bounds.origin.x += dx
    annotations[index].bounds.origin.y += dy

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

  static func displayFont(size: CGFloat, fontName: String? = nil, scale: CGFloat) -> NSFont {
    let baseFont = font(size: size, fontName: fontName)
    let displaySize = max(baseFont.pointSize * scale, 1)

    if let scaledFont = NSFont(descriptor: baseFont.fontDescriptor, size: displaySize) {
      return scaledFont
    }

    return NSFont.systemFont(ofSize: displaySize)
  }

  static func bounds(
    text: String,
    font: NSFont,
    origin: CGPoint,
    constrainedWidth: CGFloat? = nil,
    maximumHeight: CGFloat = maxHeight,
    presentation: TextPresentation = .plain
  ) -> CGRect {
    let finalWidth: CGFloat

    if let constrainedWidth = constrainedWidth {
      finalWidth = clampedWidth(constrainedWidth)
    } else {
      finalWidth = preferredAutoWidth(text: text, font: font, presentation: presentation)
    }

    let insets = TextBubbleGeometry.contentInsets(for: presentation, fontSize: font.pointSize)
    let contentWidth = max(finalWidth - insets.width * 2, minContentWidth)
    let contentHeight = ceil(contentSize(for: text, font: font, constrainedWidth: contentWidth).height)
    let resolvedMaximumHeight = max(minimumHeight(for: font), min(maximumHeight, maxHeight))
    let finalHeight = min(max(contentHeight + insets.height * 2, minimumHeight(for: font, presentation: presentation)), resolvedMaximumHeight)

    return CGRect(
      x: origin.x,
      y: origin.y,
      width: finalWidth,
      height: finalHeight
    )
  }

  static func textRect(for text: String, font: NSFont, in bounds: CGRect, presentation: TextPresentation = .plain) -> CGRect {
    let insets = TextBubbleGeometry.contentInsets(for: presentation, fontSize: font.pointSize)
    let contentWidth = max(bounds.width - insets.width * 2, minContentWidth)
    let contentHeight = ceil(contentSize(for: text, font: font, constrainedWidth: contentWidth).height)
    let drawHeight = min(contentHeight, max(bounds.height, 0))
    let verticalInset = max((bounds.height - drawHeight) / 2, 0)

    return CGRect(
      x: bounds.minX + insets.width,
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

  static func textEditorInset(scale: CGFloat, presentation: TextPresentation = .plain, fontSize: CGFloat = 16) -> NSSize {
    let resolvedScale = max(scale, 0.0001)
    let insets = TextBubbleGeometry.contentInsets(for: presentation, fontSize: fontSize)
    return NSSize(
      width: insets.width * resolvedScale,
      height: insets.height * resolvedScale
    )
  }

  static func clampedWidth(_ width: CGFloat, maximumWidth: CGFloat = maxWidth) -> CGFloat {
    let resolvedMaximumWidth = max(minWidth, min(maximumWidth, maxWidth))
    return min(max(width, minWidth), resolvedMaximumWidth)
  }

  static func preferredAutoWidth(
    text: String,
    font: NSFont,
    minimumWidth: CGFloat = defaultInitialWidth,
    maximumWidth: CGFloat = maxWidth,
    presentation: TextPresentation = .plain
  ) -> CGFloat {
    let insets = TextBubbleGeometry.contentInsets(for: presentation, fontSize: font.pointSize)
    let measuredWidth = ceil(singleLineSize(for: text, font: font).width) + insets.width * 2
    let resolvedMaximumWidth = max(minWidth, min(maximumWidth, maxWidth))
    let resolvedMinimumWidth = min(max(minimumWidth, minWidth), resolvedMaximumWidth)
    return min(max(measuredWidth, resolvedMinimumWidth), resolvedMaximumWidth)
  }

  static func minimumHeight(for font: NSFont, presentation: TextPresentation = .plain) -> CGFloat {
    let insets = TextBubbleGeometry.contentInsets(for: presentation, fontSize: font.pointSize)
    return ceil(font.ascender - font.descender + font.leading) + insets.height * 2
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
