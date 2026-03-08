//
//  VideoEditorState.swift
//  Snapzy
//
//  Central state management for video editor
//

import AVFoundation
import AppKit
import Combine

// MARK: - Editor Action (Undo/Redo Support)

/// Represents an undoable editor action
enum EditorAction: Equatable {
  case trimStart(old: CMTime, new: CMTime)
  case trimEnd(old: CMTime, new: CMTime)
  case addZoom(segment: ZoomSegment)
  case removeZoom(segment: ZoomSegment)
  case updateZoom(old: ZoomSegment, new: ZoomSegment)
  case toggleMute(old: Bool, new: Bool)
  case updateBackground(
    oldStyle: BackgroundStyle, newStyle: BackgroundStyle,
    oldPadding: CGFloat, newPadding: CGFloat,
    oldShadow: CGFloat, newShadow: CGFloat,
    oldCorner: CGFloat, newCorner: CGFloat
  )
}

/// Observable state for video editor window
@MainActor
final class VideoEditorState: ObservableObject {

  private struct AutoFocusPathInput: Equatable {
    let zoomType: ZoomType
    let zoomLevel: CGFloat
    let followSpeed: Double
    let focusMargin: CGFloat

    init(segment: ZoomSegment) {
      zoomType = segment.zoomType
      zoomLevel = segment.zoomLevel
      followSpeed = segment.followSpeed
      focusMargin = segment.focusMargin
    }
  }

  // MARK: - Video Source

  private(set) var sourceURL: URL
  /// Original file URL to replace (used for "Replace Original" functionality)
  private(set) var originalURL: URL
  let asset: AVAsset
  let player: AVPlayer

  // MARK: - Metadata

  @Published private(set) var duration: CMTime = .zero
  @Published private(set) var naturalSize: CGSize = .zero
  @Published private(set) var currentTime: CMTime = .zero
  @Published private(set) var isPlaying: Bool = false

  // MARK: - Trim Range

  @Published var trimStart: CMTime = .zero
  @Published var trimEnd: CMTime = .zero
  @Published private(set) var isScrubbing: Bool = false

  // MARK: - Audio Control

  @Published var isMuted: Bool = false {
    didSet {
      player.isMuted = isMuted
    }
  }
  private var initialIsMuted: Bool = false

  /// Sync player preview mute with export audio mode
  func syncPlayerMuteWithExportSettings() {
    player.isMuted = exportSettings.audioMode == .mute
    isMuted = exportSettings.audioMode == .mute
  }

  // MARK: - Frame Thumbnails

  @Published private(set) var frameThumbnails: [NSImage] = []
  @Published private(set) var isExtractingFrames: Bool = false

  // MARK: - Zoom Segments

  @Published var zoomSegments: [ZoomSegment] = []
  @Published var selectedZoomId: UUID? = nil
  @Published var isZoomTrackVisible: Bool = true
  @Published var isVideoInfoSidebarVisible: Bool = false
  @Published var isRightSidebarVisible: Bool = false

  // MARK: - Auto Focus

  @Published private(set) var recordingMetadata: RecordingMetadata?
  @Published private(set) var autoFocusPaths: [UUID: [AutoFocusCameraSample]] = [:]

  // MARK: - GIF Metadata

  @Published private(set) var gifFrameCount: Int = 0
  @Published private(set) var gifDuration: Double = 0

  // MARK: - Background Settings

  @Published var backgroundStyle: BackgroundStyle = .none {
    didSet {
      handleBackgroundStyleChange()
    }
  }
  @Published var backgroundPadding: CGFloat = 0

  // MARK: - Cached Background Images (Performance Optimization)

  /// Cached background image for performance (avoids disk reads during render)
  @Published private(set) var cachedBackgroundImage: NSImage?

  /// Cached pre-computed blurred image (avoids real-time blur)
  @Published private(set) var cachedBlurredImage: NSImage?

  /// Track URL being loaded to prevent race conditions
  private var loadingBackgroundURL: URL?
  @Published var backgroundShadowIntensity: CGFloat = 0
  @Published var backgroundCornerRadius: CGFloat = 0
  @Published var backgroundAlignment: ImageAlignment = .center
  @Published var backgroundAspectRatio: AspectRatioOption = .auto
  @Published var isBackgroundSidebarVisible: Bool = false

  // MARK: - Export State

  @Published var isExporting: Bool = false
  @Published var exportProgress: Float = 0
  @Published var exportStatusMessage: String = "Preparing..."

  // MARK: - Export Settings

  @Published var exportSettings: ExportSettings = ExportSettings()
  @Published private(set) var estimatedFileSize: Int64 = 0

  // MARK: - Unsaved Changes

  @Published var hasUnsavedChanges: Bool = false
  private var initialTrimStart: CMTime = .zero
  private var initialTrimEnd: CMTime = .zero
  private var initialZoomSegments: [ZoomSegment] = []
  private var initialBackgroundStyle: BackgroundStyle = .none
  private var initialBackgroundPadding: CGFloat = 0
  private var initialBackgroundShadowIntensity: CGFloat = 0
  private var initialBackgroundCornerRadius: CGFloat = 0
  private var initialDimensionPreset: ExportDimensionPreset = .original

  // MARK: - Undo/Redo

  @Published private(set) var canUndo: Bool = false
  @Published private(set) var canRedo: Bool = false
  private var undoStack: [EditorAction] = []
  private var redoStack: [EditorAction] = []
  private let maxUndoStackSize = 50
  private var isUndoingOrRedoing: Bool = false

  // MARK: - Rename State

  @Published var isRenamingFile: Bool = false

  // MARK: - Private

  private var timeObserver: Any?
  private var endObserver: NSObjectProtocol?
  private var cancellables = Set<AnyCancellable>()
  private var autoFocusPathInputs: [UUID: AutoFocusPathInput] = [:]

  // MARK: - Computed Properties

  var trimmedDuration: CMTime {
    CMTimeSubtract(trimEnd, trimStart)
  }

  var hasMouseTrackingData: Bool {
    !(recordingMetadata?.mouseSamples.isEmpty ?? true)
  }

  var autoZoomSegmentCount: Int {
    zoomSegments.filter(\.isAutoMode).count
  }

  var hasAutoZoomSegments: Bool {
    autoZoomSegmentCount > 0
  }

  var isAutoZoomActiveAtCurrentTime: Bool {
    activeZoomSegment(at: CMTimeGetSeconds(currentTime))?.isAutoMode == true
  }

  var filename: String {
    sourceURL.lastPathComponent
  }

  var fileExtension: String {
    sourceURL.pathExtension.lowercased()
  }

  /// Whether the source file is an animated GIF
  var isGIF: Bool {
    fileExtension == "gif"
  }

  var formattedDuration: String {
    formatTime(duration)
  }

  var formattedCurrentTime: String {
    formatTime(currentTime)
  }

  var formattedTrimmedDuration: String {
    formatTime(trimmedDuration)
  }

  var resolutionString: String {
    guard naturalSize.width > 0 && naturalSize.height > 0 else { return "—" }
    return "\(Int(naturalSize.width)) × \(Int(naturalSize.height))"
  }

  var aspectRatioString: String {
    guard naturalSize.width > 0 && naturalSize.height > 0 else { return "—" }
    let gcdValue = gcd(Int(naturalSize.width), Int(naturalSize.height))
    let w = Int(naturalSize.width) / gcdValue
    let h = Int(naturalSize.height) / gcdValue
    return "\(w):\(h)"
  }

  var fileSizeString: String {
    let size: Int64? = SandboxFileAccessManager.shared.withScopedAccess(to: sourceURL) {
      guard let attrs = try? FileManager.default.attributesOfItem(atPath: sourceURL.path),
            let size = attrs[.size] as? Int64
      else { return nil }
      return size
    }
    guard let size else { return "—" }
    return ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
  }

  var fileCreationDate: Date? {
    SandboxFileAccessManager.shared.withScopedAccess(to: sourceURL) {
      guard let attrs = try? FileManager.default.attributesOfItem(atPath: sourceURL.path) else {
        return nil
      }
      return attrs[.creationDate] as? Date
    }
  }

  var fileModificationDate: Date? {
    SandboxFileAccessManager.shared.withScopedAccess(to: sourceURL) {
      guard let attrs = try? FileManager.default.attributesOfItem(atPath: sourceURL.path) else {
        return nil
      }
      return attrs[.modificationDate] as? Date
    }
  }

  private func gcd(_ a: Int, _ b: Int) -> Int {
    b == 0 ? a : gcd(b, a % b)
  }

  // MARK: - Initialization

  init(url: URL, originalURL: URL? = nil) {
    self.sourceURL = url
    self.originalURL = originalURL ?? url
    self.asset = AVAsset(url: url)
    self.player = AVPlayer(playerItem: AVPlayerItem(asset: asset))

    setupTimeObserver()
    setupEndObserver()
    setupChangeTracking()
  }

  deinit {
    if let observer = timeObserver {
      player.removeTimeObserver(observer)
    }
    if let observer = endObserver {
      NotificationCenter.default.removeObserver(observer)
    }
    cancellables.removeAll()
  }

  // MARK: - Metadata Loading

  func loadMetadata() async {
    loadRecordingMetadata()

    // GIF files can't be loaded by AVAsset — use GIFResizer metadata
    if isGIF {
      if let metadata = GIFResizer.metadata(for: sourceURL) {
        naturalSize = metadata.size
        gifFrameCount = metadata.frameCount
        gifDuration = metadata.duration
      } else if let image = SandboxFileAccessManager.shared.withScopedAccess(to: sourceURL, {
        NSImage(contentsOf: sourceURL)
      }) {
        naturalSize = CGSize(
          width: image.representations.first?.pixelsWide ?? Int(image.size.width),
          height: image.representations.first?.pixelsHigh ?? Int(image.size.height)
        )
      }
      return
    }

    do {
      let loadedDuration = try await asset.load(.duration)
      duration = loadedDuration
      trimStart = .zero
      trimEnd = loadedDuration
      initialTrimStart = .zero
      initialTrimEnd = loadedDuration

      if let track = try await asset.loadTracks(withMediaType: .video).first {
        let size = try await track.load(.naturalSize)
        let transform = try await track.load(.preferredTransform)
        // Apply transform to get correct orientation
        let transformedSize = size.applying(transform)
        naturalSize = CGSize(
          width: abs(transformedSize.width),
          height: abs(transformedSize.height)
        )
      }
      // Calculate initial file size estimate after metadata loads
      recalculateEstimatedFileSize()
    } catch {
      print("Failed to load video metadata: \(error)")
    }
  }

  // MARK: - Playback Control

  func play() {
    player.play()
    isPlaying = true
  }

  func pause() {
    player.pause()
    isPlaying = false
  }

  func togglePlayback() {
    if isPlaying {
      pause()
    } else {
      play()
    }
  }

  func toggleMute() {
    let oldValue = isMuted
    isMuted.toggle()
    recordAction(.toggleMute(old: oldValue, new: isMuted))
  }

  func seek(to time: CMTime) {
    let clampedTime = clampTime(time)
    player.seek(to: clampedTime, toleranceBefore: .zero, toleranceAfter: .zero)
  }

  // MARK: - Scrubbing

  func startScrubbing() {
    isScrubbing = true
    pause()
  }

  func scrub(to time: CMTime) {
    let clampedTime = clampTime(time)
    currentTime = clampedTime
    player.seek(to: clampedTime, toleranceBefore: .zero, toleranceAfter: .zero)
  }

  func endScrubbing() {
    isScrubbing = false
  }

  // MARK: - Trim Control

  func setTrimStart(_ time: CMTime, recordUndo: Bool = true) {
    let oldValue = trimStart
    let minDuration = CMTime(seconds: 1.0, preferredTimescale: 600)
    let maxStart = CMTimeSubtract(trimEnd, minDuration)
    let clampedStart = CMTimeClampToRange(time, range: CMTimeRange(start: .zero, end: maxStart))
    trimStart = clampedStart

    // If current time is before new start, seek to start
    if CMTimeCompare(currentTime, trimStart) < 0 {
      seek(to: trimStart)
    }

    if recordUndo && CMTimeCompare(oldValue, clampedStart) != 0 {
      recordAction(.trimStart(old: oldValue, new: clampedStart))
    }
  }

  func setTrimEnd(_ time: CMTime, recordUndo: Bool = true) {
    let oldValue = trimEnd
    let minDuration = CMTime(seconds: 1.0, preferredTimescale: 600)
    let minEnd = CMTimeAdd(trimStart, minDuration)
    let clampedEnd = CMTimeClampToRange(time, range: CMTimeRange(start: minEnd, end: duration))
    trimEnd = clampedEnd

    // If current time is after new end, seek to end
    if CMTimeCompare(currentTime, trimEnd) > 0 {
      seek(to: trimEnd)
    }

    if recordUndo && CMTimeCompare(oldValue, clampedEnd) != 0 {
      recordAction(.trimEnd(old: oldValue, new: clampedEnd))
    }
  }

  func resetTrim() {
    trimStart = .zero
    trimEnd = duration
  }

  // MARK: - Frame Extraction

  func extractFrames() async {
    // GIF files don't use AVAsset — skip frame extraction
    guard !isGIF else { return }
    guard CMTimeGetSeconds(duration) > 0 else { return }

    isExtractingFrames = true
    defer { isExtractingFrames = false }

    let generator = AVAssetImageGenerator(asset: asset)
    generator.appliesPreferredTrackTransform = true
    generator.maximumSize = CGSize(width: 120, height: 68)
    generator.requestedTimeToleranceBefore = .zero
    generator.requestedTimeToleranceAfter = .zero

    let count = 25
    let totalSeconds = CMTimeGetSeconds(duration)
    let interval = totalSeconds / Double(count)

    var images: [NSImage] = []
    for i in 0..<count {
      let time = CMTime(seconds: Double(i) * interval, preferredTimescale: 600)
      if let cgImage = try? generator.copyCGImage(at: time, actualTime: nil) {
        let image = NSImage(cgImage: cgImage, size: NSSize(width: 120, height: 68))
        images.append(image)
      }
    }
    frameThumbnails = images
  }

  // MARK: - Save State

  func markAsSaved() {
    hasUnsavedChanges = false
    initialTrimStart = trimStart
    initialTrimEnd = trimEnd
    initialIsMuted = isMuted
    initialZoomSegments = zoomSegments
    initialBackgroundStyle = backgroundStyle
    initialBackgroundPadding = backgroundPadding
    initialBackgroundShadowIntensity = backgroundShadowIntensity
    initialBackgroundCornerRadius = backgroundCornerRadius
    clearUndoHistory()
  }

  // MARK: - Undo/Redo Actions

  /// Record an action for undo support
  private func recordAction(_ action: EditorAction) {
    guard !isUndoingOrRedoing else { return }
    undoStack.append(action)
    if undoStack.count > maxUndoStackSize {
      undoStack.removeFirst()
    }
    redoStack.removeAll()
    updateUndoRedoState()
  }

  /// Undo the last action
  func undo() {
    guard let action = undoStack.popLast() else { return }
    isUndoingOrRedoing = true
    defer {
      isUndoingOrRedoing = false
      updateUndoRedoState()
    }

    switch action {
    case .trimStart(let old, let new):
      trimStart = old
      redoStack.append(.trimStart(old: new, new: old))

    case .trimEnd(let old, let new):
      trimEnd = old
      redoStack.append(.trimEnd(old: new, new: old))

    case .addZoom(let segment):
      zoomSegments.removeAll { $0.id == segment.id }
      if selectedZoomId == segment.id { selectedZoomId = nil }
      redoStack.append(.removeZoom(segment: segment))

    case .removeZoom(let segment):
      zoomSegments.append(segment)
      redoStack.append(.addZoom(segment: segment))

    case .updateZoom(let old, let new):
      if let index = zoomSegments.firstIndex(where: { $0.id == new.id }) {
        zoomSegments[index] = old
      }
      redoStack.append(.updateZoom(old: new, new: old))

    case .toggleMute(let old, _):
      isMuted = old
      redoStack.append(.toggleMute(old: !old, new: old))

    case .updateBackground(let oldStyle, let newStyle, let oldPadding, let newPadding, let oldShadow, let newShadow, let oldCorner, let newCorner):
      backgroundStyle = oldStyle
      backgroundPadding = oldPadding
      backgroundShadowIntensity = oldShadow
      backgroundCornerRadius = oldCorner
      redoStack.append(.updateBackground(oldStyle: newStyle, newStyle: oldStyle, oldPadding: newPadding, newPadding: oldPadding, oldShadow: newShadow, newShadow: oldShadow, oldCorner: newCorner, newCorner: oldCorner))
    }
  }

  /// Redo the last undone action
  func redo() {
    guard let action = redoStack.popLast() else { return }
    isUndoingOrRedoing = true
    defer {
      isUndoingOrRedoing = false
      updateUndoRedoState()
    }

    switch action {
    case .trimStart(let old, let new):
      trimStart = old
      undoStack.append(.trimStart(old: new, new: old))

    case .trimEnd(let old, let new):
      trimEnd = old
      undoStack.append(.trimEnd(old: new, new: old))

    case .addZoom(let segment):
      zoomSegments.removeAll { $0.id == segment.id }
      if selectedZoomId == segment.id { selectedZoomId = nil }
      undoStack.append(.removeZoom(segment: segment))

    case .removeZoom(let segment):
      zoomSegments.append(segment)
      undoStack.append(.addZoom(segment: segment))

    case .updateZoom(let old, let new):
      if let index = zoomSegments.firstIndex(where: { $0.id == new.id }) {
        zoomSegments[index] = old
      }
      undoStack.append(.updateZoom(old: new, new: old))

    case .toggleMute(let old, _):
      isMuted = old
      undoStack.append(.toggleMute(old: !old, new: old))

    case .updateBackground(let oldStyle, let newStyle, let oldPadding, let newPadding, let oldShadow, let newShadow, let oldCorner, let newCorner):
      backgroundStyle = oldStyle
      backgroundPadding = oldPadding
      backgroundShadowIntensity = oldShadow
      backgroundCornerRadius = oldCorner
      undoStack.append(.updateBackground(oldStyle: newStyle, newStyle: oldStyle, oldPadding: newPadding, newPadding: oldPadding, oldShadow: newShadow, newShadow: oldShadow, oldCorner: newCorner, newCorner: oldCorner))
    }
  }

  private func updateUndoRedoState() {
    canUndo = !undoStack.isEmpty
    canRedo = !redoStack.isEmpty
  }

  private func clearUndoHistory() {
    undoStack.removeAll()
    redoStack.removeAll()
    updateUndoRedoState()
  }

  // MARK: - File Operations

  /// Open the source file location in Finder
  func openInFinder() {
    let sourceAccess = SandboxFileAccessManager.shared.beginAccessingURL(sourceURL)
    defer { sourceAccess.stop() }
    NSWorkspace.shared.activateFileViewerSelecting([sourceURL])
  }

  /// Rename the source file
  func renameFile(to newName: String) throws {
    let oldSourceURL = sourceURL
    let directory = sourceURL.deletingLastPathComponent()
    let sourceAccess = SandboxFileAccessManager.shared.beginAccessingURL(oldSourceURL)
    let directoryAccess = SandboxFileAccessManager.shared.beginAccessingURL(directory)
    defer {
      sourceAccess.stop()
      directoryAccess.stop()
    }

    let ext = sourceURL.pathExtension
    let sanitizedName = newName.trimmingCharacters(in: .whitespacesAndNewlines)

    guard !sanitizedName.isEmpty else {
      throw NSError(domain: "VideoEditor", code: 1, userInfo: [NSLocalizedDescriptionKey: "Filename cannot be empty"])
    }

    let newURL = directoryAccess.url.appendingPathComponent(sanitizedName).appendingPathExtension(ext)

    guard newURL != sourceURL else { return }

    guard !FileManager.default.fileExists(atPath: newURL.path) else {
      throw NSError(domain: "VideoEditor", code: 2, userInfo: [NSLocalizedDescriptionKey: "A file with this name already exists"])
    }

    try FileManager.default.moveItem(at: sourceAccess.url, to: newURL)

    let oldSidecarURL = RecordingMetadataStore.sidecarURL(for: oldSourceURL)
    let newSidecarURL = RecordingMetadataStore.sidecarURL(for: newURL)
    if FileManager.default.fileExists(atPath: oldSidecarURL.path) {
      try FileManager.default.moveItem(at: oldSidecarURL, to: newSidecarURL)
    }

    sourceURL = newURL
    if originalURL == oldSourceURL {
      originalURL = newURL
    }
  }

  // MARK: - Zoom Management

  /// Add a new zoom segment at the specified time
  @discardableResult
  func addZoom(at time: TimeInterval) -> UUID {
    let videoDuration = CMTimeGetSeconds(duration)
    let defaultZoomType: ZoomType = hasMouseTrackingData ? .auto : .manual
    let segment = ZoomSegment(
      startTime: max(0, time - ZoomSegment.defaultDuration / 2),
      duration: ZoomSegment.defaultDuration,
      zoomLevel: ZoomSegment.defaultZoomLevel,
      zoomCenter: CGPoint(x: 0.5, y: 0.5),
      zoomType: defaultZoomType
    ).clamped(to: videoDuration)

    zoomSegments.append(segment)
    selectedZoomId = segment.id
    recordAction(.addZoom(segment: segment))
    return segment.id
  }

  /// Remove a zoom segment by ID
  func removeZoom(id: UUID) {
    guard let segment = zoomSegments.first(where: { $0.id == id }) else { return }
    zoomSegments.removeAll { $0.id == id }
    if selectedZoomId == id {
      selectedZoomId = nil
    }
    recordAction(.removeZoom(segment: segment))
  }

  /// Update zoom segment properties
  func updateZoom(
    id: UUID,
    startTime: TimeInterval? = nil,
    duration: TimeInterval? = nil,
    zoomLevel: CGFloat? = nil,
    zoomCenter: CGPoint? = nil,
    zoomType: ZoomType? = nil,
    followSpeed: Double? = nil,
    focusMargin: CGFloat? = nil,
    isEnabled: Bool? = nil
  ) {
    guard let index = zoomSegments.firstIndex(where: { $0.id == id }) else { return }

    var segment = zoomSegments[index]
    let videoDuration = CMTimeGetSeconds(self.duration)

    if let startTime = startTime {
      segment.startTime = max(0, min(startTime, videoDuration - ZoomSegment.minDuration))
    }
    if let duration = duration {
      segment.duration = max(ZoomSegment.minDuration, min(duration, videoDuration - segment.startTime))
    }
    if let zoomLevel = zoomLevel {
      segment.zoomLevel = max(ZoomSegment.minZoomLevel, min(zoomLevel, ZoomSegment.maxZoomLevel))
    }
    if let zoomCenter = zoomCenter {
      segment.zoomCenter = CGPoint(
        x: max(0, min(zoomCenter.x, 1)),
        y: max(0, min(zoomCenter.y, 1))
      )
    }
    if let zoomType = zoomType {
      segment.zoomType = zoomType
    }
    if let followSpeed = followSpeed {
      segment.followSpeed = AutoFocusSettings.clampFollowSpeed(followSpeed)
    }
    if let focusMargin = focusMargin {
      segment.focusMargin = AutoFocusSettings.clampFocusMargin(focusMargin)
    }
    if let isEnabled = isEnabled {
      segment.isEnabled = isEnabled
    }

    zoomSegments[index] = segment
  }

  func setZoomMode(id: UUID, zoomType: ZoomType) {
    guard zoomType != .auto || hasMouseTrackingData else { return }
    updateZoom(id: id, zoomType: zoomType)
  }

  func cameraState(
    at time: TimeInterval,
    transitionDuration: TimeInterval = 0.3
  ) -> VideoEditorCameraState {
    VideoEditorAutoFocusEngine.resolvedCameraState(
      at: time,
      segments: zoomSegments,
      autoFocusPaths: autoFocusPaths,
      transitionDuration: transitionDuration
    )
  }

  func autoFocusPath(for segment: ZoomSegment) -> [AutoFocusCameraSample] {
    autoFocusPaths[segment.id] ?? []
  }

  /// Select a zoom segment
  func selectZoom(id: UUID?) {
    selectedZoomId = id
  }

  /// Toggle zoom enabled state
  func toggleZoomEnabled(id: UUID) {
    guard let index = zoomSegments.firstIndex(where: { $0.id == id }) else { return }
    zoomSegments[index].isEnabled.toggle()
  }

  /// Get the active zoom segment at a given time (enabled segments only - for playback)
  func activeZoomSegment(at time: TimeInterval) -> ZoomSegment? {
    ZoomCalculator.activeSegment(at: time, in: zoomSegments)
  }

  /// Get any zoom segment at a given time (including disabled - for UI interaction)
  func zoomSegment(at time: TimeInterval) -> ZoomSegment? {
    zoomSegments.filter { $0.contains(time: time) }.last
  }

  /// Get the currently selected zoom segment
  var selectedZoomSegment: ZoomSegment? {
    guard let id = selectedZoomId else { return nil }
    return zoomSegments.first { $0.id == id }
  }

  /// Toggle zoom track visibility
  func toggleZoomTrackVisibility() {
    isZoomTrackVisible.toggle()
  }

  /// Toggle video info sidebar visibility
  func toggleVideoInfoSidebar() {
    isVideoInfoSidebarVisible.toggle()
  }

  /// Toggle right sidebar visibility
  func toggleRightSidebar() {
    isRightSidebarVisible.toggle()
  }

  /// Toggle background sidebar visibility
  func toggleBackgroundSidebar() {
    isBackgroundSidebarVisible.toggle()
  }

  // MARK: - Export Settings Methods

  /// Update export settings and recalculate file size
  func updateExportSettings(_ settings: ExportSettings) {
    exportSettings = settings
    syncPlayerMuteWithExportSettings()
    recalculateEstimatedFileSize()
  }

  /// Recalculate estimated file size based on current settings
  func recalculateEstimatedFileSize() {
    Task { @MainActor in
      estimatedFileSize = await calculateEstimatedFileSize()
    }
  }

  /// Calculate estimated file size based on export settings
  private func calculateEstimatedFileSize() async -> Int64 {
    // Get source file size
    let sourceSize: Int64? = SandboxFileAccessManager.shared.withScopedAccess(to: sourceURL) {
      guard let attrs = try? FileManager.default.attributesOfItem(atPath: sourceURL.path),
            let sourceSize = attrs[.size] as? Int64
      else { return nil }
      return sourceSize
    }
    guard let sourceSize else { return 0 }

    // GIF mode: estimate based on pixel ratio
    if isGIF {
      let exportSize = exportSettings.exportSize(from: naturalSize)
      let originalPixels = naturalSize.width * naturalSize.height
      let newPixels = exportSize.width * exportSize.height
      let pixelRatio = originalPixels > 0 ? newPixels / originalPixels : 1.0
      let estimated = Double(sourceSize) * pixelRatio
      return Int64(max(estimated, 1024))
    }

    let sourceDuration = CMTimeGetSeconds(duration)
    guard sourceDuration > 0 else { return 0 }

    // Calculate trim ratio
    let trimmedDurationSec = CMTimeGetSeconds(trimmedDuration)
    let trimRatio = trimmedDurationSec / sourceDuration

    // Calculate dimension ratio (including background padding)
    let exportSize = exportSettings.exportSize(from: naturalSize)
    let originalPixels = naturalSize.width * naturalSize.height

    // Include background padding in canvas size calculation
    let canvasWidth: CGFloat
    let canvasHeight: CGFloat
    if backgroundStyle != .none && backgroundPadding > 0 {
      canvasWidth = exportSize.width + (backgroundPadding * 2)
      canvasHeight = exportSize.height + (backgroundPadding * 2)
    } else {
      canvasWidth = exportSize.width
      canvasHeight = exportSize.height
    }
    let canvasPixels = canvasWidth * canvasHeight
    let dimensionRatio = originalPixels > 0 ? canvasPixels / originalPixels : 1.0

    // Apply quality multiplier
    let qualityMultiplier = Double(exportSettings.quality.bitrateMultiplier)

    // Audio adjustment (rough estimate: audio is ~10% of file)
    let audioMultiplier: Double = {
      switch exportSettings.audioMode {
      case .mute: return 0.9 // Remove audio portion
      case .keep, .custom: return 1.0
      }
    }()

    // Calculate estimated size
    let estimated = Double(sourceSize) * trimRatio * dimensionRatio * qualityMultiplier * audioMultiplier
    return Int64(max(estimated, 1024)) // Minimum 1KB
  }

  // MARK: - Private Methods

  private func setupTimeObserver() {
    let interval = CMTime(seconds: 1.0 / 30.0, preferredTimescale: 600)
    timeObserver = player.addPeriodicTimeObserver(
      forInterval: interval,
      queue: .main
    ) { [weak self] time in
      Task { @MainActor in
        guard let self = self, !self.isScrubbing else { return }
        self.currentTime = time

        // Stop at trim end
        if CMTimeCompare(time, self.trimEnd) >= 0 {
          self.pause()
          self.seek(to: self.trimStart)
        }
      }
    }
  }

  private func setupEndObserver() {
    endObserver = NotificationCenter.default.addObserver(
      forName: .AVPlayerItemDidPlayToEndTime,
      object: player.currentItem,
      queue: .main
    ) { [weak self] _ in
      Task { @MainActor in
        self?.pause()
        self?.seek(to: self?.trimStart ?? .zero)
      }
    }
  }

  private func setupChangeTracking() {
    // Track trim and mute changes
    Publishers.CombineLatest3($trimStart, $trimEnd, $isMuted)
      .dropFirst(3)
      .sink { [weak self] _, _, _ in
        self?.updateHasUnsavedChanges()
        self?.recalculateEstimatedFileSize()
      }
      .store(in: &cancellables)

    // Track zoom changes - pass segments directly to avoid stale state reads
    $zoomSegments
      .removeDuplicates()
      .sink { [weak self] segments in
        guard let self = self else { return }
        self.rebuildAutoFocusPaths(for: segments)
        // Pass segments directly from publisher to avoid timing issues
        self.updateHasUnsavedChanges(currentZoomSegments: segments)
      }
      .store(in: &cancellables)

    // Track background changes
    Publishers.CombineLatest4($backgroundStyle, $backgroundPadding, $backgroundShadowIntensity, $backgroundCornerRadius)
      .dropFirst(4)
      .sink { [weak self] _, _, _, _ in
        self?.updateHasUnsavedChanges()
        self?.recalculateEstimatedFileSize()
      }
      .store(in: &cancellables)

    // Track export settings changes for file size estimation
    $exportSettings
      .dropFirst()
      .sink { [weak self] _ in
        self?.recalculateEstimatedFileSize()
      }
      .store(in: &cancellables)
  }

  private func updateHasUnsavedChanges(currentZoomSegments: [ZoomSegment]? = nil) {
    // GIF mode: only track dimension changes
    if isGIF {
      let dimensionChanged = exportSettings.dimensionPreset != initialDimensionPreset
      hasUnsavedChanges = dimensionChanged
      return
    }

    let startChanged = CMTimeCompare(trimStart, initialTrimStart) != 0
    let endChanged = CMTimeCompare(trimEnd, initialTrimEnd) != 0
    let muteChanged = isMuted != initialIsMuted
    // Use passed segments if available, otherwise read from self
    let segments = currentZoomSegments ?? zoomSegments
    let zoomsChanged = segments != initialZoomSegments
    // Background changes
    let bgStyleChanged = backgroundStyle != initialBackgroundStyle
    let bgPaddingChanged = backgroundPadding != initialBackgroundPadding
    let bgShadowChanged = backgroundShadowIntensity != initialBackgroundShadowIntensity
    let bgCornerChanged = backgroundCornerRadius != initialBackgroundCornerRadius
    let backgroundChanged = bgStyleChanged || bgPaddingChanged || bgShadowChanged || bgCornerChanged

    hasUnsavedChanges = startChanged || endChanged || muteChanged || zoomsChanged || backgroundChanged
  }

  private func clampTime(_ time: CMTime) -> CMTime {
    CMTimeClampToRange(time, range: CMTimeRange(start: trimStart, end: trimEnd))
  }

  private func formatTime(_ time: CMTime) -> String {
    let totalSeconds = Int(CMTimeGetSeconds(time))
    let hours = totalSeconds / 3600
    let minutes = (totalSeconds % 3600) / 60
    let seconds = totalSeconds % 60

    if hours > 0 {
      return String(format: "%d:%02d:%02d", hours, minutes, seconds)
    } else {
      return String(format: "%02d:%02d", minutes, seconds)
    }
  }

  // MARK: - Background Image Caching (Performance)

  /// Handle background style changes - load and cache images
  private func handleBackgroundStyleChange() {
    switch backgroundStyle {
    case .wallpaper(let url), .blurred(let url):
      loadBackgroundImage(from: url)
    default:
      cachedBackgroundImage = nil
      cachedBlurredImage = nil
      loadingBackgroundURL = nil
    }
  }

  /// Load and cache background image using SystemWallpaperManager
  private func loadBackgroundImage(from url: URL) {
    loadingBackgroundURL = url

    SystemWallpaperManager.shared.loadPreviewImage(for: url) { [weak self] image in
      Task { @MainActor in
        guard let self = self else { return }
        // Race condition guard: only apply if still loading this URL
        guard self.loadingBackgroundURL == url else { return }

        self.cachedBackgroundImage = image
        self.loadingBackgroundURL = nil

        // Pre-compute blur if needed
        if case .blurred = self.backgroundStyle {
          self.cachedBlurredImage = self.applyGaussianBlur(
            to: image,
            radius: WallpaperQualityConfig.blurRadius
          )
        } else {
          self.cachedBlurredImage = nil
        }
      }
    }
  }

  private func loadRecordingMetadata() {
    guard !isGIF else {
      recordingMetadata = nil
      autoFocusPaths = [:]
      autoFocusPathInputs = [:]
      return
    }

    let candidateURLs = [sourceURL, originalURL]
      .reduce(into: [URL]()) { urls, url in
        guard !urls.contains(url) else { return }
        urls.append(url)
      }

    recordingMetadata = candidateURLs.lazy.compactMap { RecordingMetadataStore.load(for: $0) }.first

    rebuildAutoFocusPaths(for: zoomSegments)
  }

  private func rebuildAutoFocusPaths(for segments: [ZoomSegment]) {
    guard let recordingMetadata, hasMouseTrackingData else {
      autoFocusPaths = [:]
      autoFocusPathInputs = [:]
      return
    }

    var rebuiltPaths: [UUID: [AutoFocusCameraSample]] = [:]
    var rebuiltInputs: [UUID: AutoFocusPathInput] = [:]

    for segment in segments where segment.isAutoMode {
      let input = AutoFocusPathInput(segment: segment)
      rebuiltInputs[segment.id] = input

      if autoFocusPathInputs[segment.id] == input,
         let cachedPath = autoFocusPaths[segment.id] {
        rebuiltPaths[segment.id] = cachedPath
        continue
      }

      rebuiltPaths[segment.id] = VideoEditorAutoFocusEngine.buildPath(
        from: recordingMetadata,
        segment: segment
      )
    }

    autoFocusPathInputs = rebuiltInputs
    autoFocusPaths = rebuiltPaths
  }

  /// Apply Gaussian blur to image (computed once, reused during render)
  private func applyGaussianBlur(to image: NSImage?, radius: CGFloat) -> NSImage? {
    guard let image = image,
          let tiffData = image.tiffRepresentation,
          let ciImage = CIImage(data: tiffData) else { return nil }

    let filter = CIFilter(name: "CIGaussianBlur")
    filter?.setValue(ciImage, forKey: kCIInputImageKey)
    filter?.setValue(radius, forKey: kCIInputRadiusKey)

    guard let output = filter?.outputImage else { return nil }
    let croppedOutput = output.cropped(to: ciImage.extent)

    let rep = NSCIImageRep(ciImage: croppedOutput)
    let blurred = NSImage(size: rep.size)
    blurred.addRepresentation(rep)
    return blurred
  }
}
