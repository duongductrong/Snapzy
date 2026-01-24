//
//  VideoEditorState.swift
//  ClaudeShot
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
}

/// Observable state for video editor window
@MainActor
final class VideoEditorState: ObservableObject {

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

  // MARK: - Frame Thumbnails

  @Published private(set) var frameThumbnails: [NSImage] = []
  @Published private(set) var isExtractingFrames: Bool = false

  // MARK: - Zoom Segments

  @Published var zoomSegments: [ZoomSegment] = []
  @Published var selectedZoomId: UUID? = nil
  @Published var isZoomTrackVisible: Bool = true

  // MARK: - Export State

  @Published var isExporting: Bool = false
  @Published var exportProgress: Float = 0
  @Published var exportStatusMessage: String = "Preparing..."

  // MARK: - Unsaved Changes

  @Published var hasUnsavedChanges: Bool = false
  private var initialTrimStart: CMTime = .zero
  private var initialTrimEnd: CMTime = .zero
  private var initialZoomSegments: [ZoomSegment] = []

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

  // MARK: - Computed Properties

  var trimmedDuration: CMTime {
    CMTimeSubtract(trimEnd, trimStart)
  }

  var filename: String {
    sourceURL.lastPathComponent
  }

  var fileExtension: String {
    sourceURL.pathExtension.lowercased()
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
    NSWorkspace.shared.activateFileViewerSelecting([sourceURL])
  }

  /// Rename the source file
  func renameFile(to newName: String) throws {
    let directory = sourceURL.deletingLastPathComponent()
    let ext = sourceURL.pathExtension
    let sanitizedName = newName.trimmingCharacters(in: .whitespacesAndNewlines)

    guard !sanitizedName.isEmpty else {
      throw NSError(domain: "VideoEditor", code: 1, userInfo: [NSLocalizedDescriptionKey: "Filename cannot be empty"])
    }

    let newURL = directory.appendingPathComponent(sanitizedName).appendingPathExtension(ext)

    guard newURL != sourceURL else { return }

    guard !FileManager.default.fileExists(atPath: newURL.path) else {
      throw NSError(domain: "VideoEditor", code: 2, userInfo: [NSLocalizedDescriptionKey: "A file with this name already exists"])
    }

    try FileManager.default.moveItem(at: sourceURL, to: newURL)
    sourceURL = newURL
    originalURL = newURL
  }

  // MARK: - Zoom Management

  /// Add a new zoom segment at the specified time
  @discardableResult
  func addZoom(at time: TimeInterval) -> UUID {
    let videoDuration = CMTimeGetSeconds(duration)
    let segment = ZoomSegment(
      startTime: max(0, time - ZoomSegment.defaultDuration / 2),
      duration: ZoomSegment.defaultDuration,
      zoomLevel: ZoomSegment.defaultZoomLevel,
      zoomCenter: CGPoint(x: 0.5, y: 0.5),
      zoomType: .manual
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
    if let isEnabled = isEnabled {
      segment.isEnabled = isEnabled
    }

    zoomSegments[index] = segment
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
      }
      .store(in: &cancellables)

    // Track zoom changes - pass segments directly to avoid stale state reads
    $zoomSegments
      .removeDuplicates()
      .sink { [weak self] segments in
        guard let self = self else { return }
        // Pass segments directly from publisher to avoid timing issues
        self.updateHasUnsavedChanges(currentZoomSegments: segments)
      }
      .store(in: &cancellables)
  }

  private func updateHasUnsavedChanges(currentZoomSegments: [ZoomSegment]? = nil) {
    let startChanged = CMTimeCompare(trimStart, initialTrimStart) != 0
    let endChanged = CMTimeCompare(trimEnd, initialTrimEnd) != 0
    let muteChanged = isMuted != initialIsMuted
    // Use passed segments if available, otherwise read from self
    let segments = currentZoomSegments ?? zoomSegments
    let zoomsChanged = segments != initialZoomSegments

    hasUnsavedChanges = startChanged || endChanged || muteChanged || zoomsChanged
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
}
