//
//  VideoEditorState.swift
//  Snapzy
//
//  Central state management for video editor
//

import AppKit
import AVFoundation
import Combine
import SwiftUI

// MARK: - Left Sidebar Panel

/// Entries of the collapsed left rail: the canvas/background configuration and
/// the zoom item configuration (moved from the former right sidebar).
enum VideoEditorLeftSidebarPanel: Hashable, CaseIterable {
  case background
  case zoom
}

// MARK: - Editor Action (Undo/Redo Support)

/// Represents an undoable editor action
enum EditorAction: Equatable {
  case trimStart(old: CMTime, new: CMTime)
  case trimEnd(old: CMTime, new: CMTime)
  case addZoom(segment: ZoomSegment)
  case removeZoom(segment: ZoomSegment)
  case updateZoom(old: ZoomSegment, new: ZoomSegment)
  case addSpeed(segment: SpeedSegment)
  case removeSpeed(segment: SpeedSegment)
  case updateSpeed(old: SpeedSegment, new: SpeedSegment)
  case toggleMute(old: Bool, new: Bool)
  case updateBackground(
    oldStyle: BackgroundStyle, newStyle: BackgroundStyle,
    oldPadding: CGFloat, newPadding: CGFloat,
    oldShadow: CGFloat, newShadow: CGFloat,
    oldCorner: CGFloat, newCorner: CGFloat
  )
  case addClip(clip: TimelineClip, index: Int)
  case removeClip(clip: TimelineClip, index: Int)
  case updateClip(old: TimelineClip, new: TimelineClip)
  case moveClip(id: UUID, fromIndex: Int, toIndex: Int)
  case splitClip(original: TimelineClip, index: Int, first: TimelineClip, second: TimelineClip)
}

/// Playback state changes frequently, so it stays isolated from the broader editor model.
@MainActor
final class VideoEditorPlaybackState: ObservableObject {
  @Published private(set) var currentTime: CMTime = .zero
  @Published private(set) var isPlaying: Bool = false
  @Published private(set) var isScrubbing: Bool = false

  var formattedCurrentTime: String {
    Self.formatTime(currentTime)
  }

  func setCurrentTime(_ time: CMTime) {
    guard CMTimeCompare(currentTime, time) != 0 else { return }
    currentTime = time
  }

  func setPlaying(_ value: Bool) {
    guard isPlaying != value else { return }
    isPlaying = value
  }

  func setScrubbing(_ value: Bool) {
    guard isScrubbing != value else { return }
    isScrubbing = value
  }

  private static func formatTime(_ time: CMTime) -> String {
    let totalSeconds = Int(CMTimeGetSeconds(time))
    let hours = totalSeconds / 3600
    let minutes = (totalSeconds % 3600) / 60
    let seconds = totalSeconds % 60

    if hours > 0 {
      return String(format: "%d:%02d:%02d", hours, minutes, seconds)
    }

    return String(format: "%02d:%02d", minutes, seconds)
  }
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

  private struct FrameExtractionProfile {
    let frameCount: Int
    let tolerance: CMTime
    let strategyLabel: String
  }

  // MARK: - Video Source

  private(set) var sourceURL: URL
  /// Original file URL to replace (used for "Replace Original" functionality)
  private(set) var originalURL: URL
  private(set) var assetURL: URL
  /// The source used to render the current authoring recipe. For a restored
  /// session this is the private master snapshot, not the already-rendered file.
  var editingSourceURL: URL {
    assetURL
  }
  let asset: AVAsset
  let player: AVPlayer
  let playbackState = VideoEditorPlaybackState()
  /// Timeline zoom/scroll window (UI-only, not undoable).
  let timelineViewport = VideoEditorTimelineViewport()

  // MARK: - Metadata

  @Published private(set) var duration: CMTime = .zero
  @Published private(set) var naturalSize: CGSize = .zero
  @Published private(set) var audioTrackRoles: [VideoEditorAudioTrackRole] = []

  // MARK: - Trim Range

  /// Trim window on the PRIMARY asset.
  ///
  /// For video the clip sequence is the source of truth, so this is derived: the
  /// earliest primary in-point and the latest primary out-point. GIF has no clip
  /// sequence (no `AVAsset`), so it keeps its own storage.
  var trimStart: CMTime {
    get {
      if isGIF { return gifTrimStart }
      let starts = clips.filter(\.isPrimary).map(\.sourceStart)
      return CMTime(seconds: starts.min() ?? 0, preferredTimescale: 600)
    }
    set {
      guard !isGIF else {
        gifTrimStart = newValue
        return
      }
      guard let first = clips.first(where: \.isPrimary) else { return }
      updateClip(id: first.id, sourceStart: CMTimeGetSeconds(newValue))
    }
  }

  var trimEnd: CMTime {
    get {
      if isGIF { return gifTrimEnd }
      let ends = clips.filter(\.isPrimary).map(\.sourceEnd)
      return CMTime(seconds: ends.max() ?? CMTimeGetSeconds(duration), preferredTimescale: 600)
    }
    set {
      guard !isGIF else {
        gifTrimEnd = newValue
        return
      }
      guard let last = clips.last(where: \.isPrimary) else { return }
      updateClip(id: last.id, sourceEnd: CMTimeGetSeconds(newValue))
    }
  }

  private var gifTrimStart: CMTime = .zero
  private var gifTrimEnd: CMTime = .zero

  // MARK: - Speed Segments (Timelapse)

  @Published var speedSegments: [SpeedSegment] = [] {
    didSet { cachedSequenceMap = nil }
  }

  @Published var selectedSpeedId: UUID? = nil

  // MARK: - Timeline Clips (the sequence)

  /// The ordered sequence of clips — the single source of truth for the timeline.
  ///
  /// Seeded with one primary clip spanning the whole asset. Splitting divides a clip,
  /// deleting ripples the rest left, and an inserted video is just another element.
  @Published private(set) var clips: [TimelineClip] = [] {
    didSet { invalidateTimelineCaches() }
  }

  @Published private(set) var selectedClipId: UUID? = nil
  @Published private(set) var canSplitAtPlayhead: Bool = false
  @Published private(set) var canDeleteSelectedClip: Bool = false

  /// Frame strips for inserted clips. The primary recording's strip lives in
  /// `frameThumbnails`; this covers every other asset on the timeline.
  let clipThumbnailCache = VideoEditorClipThumbnailCache()

  private var cachedPlacements: [TimelineSequence.Placement]?
  private var cachedSequenceMap: TimelineSequenceMap?
  /// Assets backing `.file` clips, keyed by URL so duplicated clips share one asset.
  private var clipAssets: [URL: AVAsset] = [:]

  private func invalidateTimelineCaches() {
    cachedPlacements = nil
    cachedSequenceMap = nil
    recalculateEstimatedFileSize()
  }

  /// Clips laid out on the structural timeline axis. Trimmed-out footage remains
  /// inside its owning placement and is marked inactive by the clip strip.
  var placements: [TimelineSequence.Placement] {
    if let cached = cachedPlacements { return cached }
    let laid = TimelineSequence.layout(clips)
    cachedPlacements = laid
    return laid
  }

  /// Clips laid out on the playable/export axis, with inactive trim slots collapsed.
  var playbackPlacements: [TimelineSequence.Placement] {
    TimelineSequence.playableLayout(clips)
  }

  /// Length of the playable/export sequence.
  var sequenceDuration: TimeInterval {
    TimelineSequence.playableDuration(clips)
  }

  /// Sequence → output map (speed applied). Cached.
  var sequenceMap: TimelineSequenceMap {
    if let cached = cachedSequenceMap { return cached }
    let map = TimelineSequenceMap(clips: clips, speedSegments: speedSegments)
    cachedSequenceMap = map
    return map
  }

  /// Structural timeline axis length. GIF has no clip sequence, so it falls back to
  /// its duration. Inactive trim slots stay on this axis for stable visual placement.
  var timelineDuration: CMTime {
    if isGIF { return duration }
    return CMTime(seconds: TimelineSequence.duration(clips), preferredTimescale: 600)
  }

  var formattedTimelineDuration: String {
    formatTime(timelineDuration)
  }

  /// True once the user has split, deleted, reordered, or inserted anything — i.e. the
  /// sequence is no longer a single primary clip and needs the composition export path.
  var hasSequenceEdits: Bool {
    clips.count > 1 || clips.contains { !$0.isPrimary }
  }

  /// True when any clip comes from a file the user added.
  var hasInsertedClips: Bool {
    clips.contains { !$0.isPrimary }
  }

  var selectedClip: TimelineClip? {
    guard let id = selectedClipId else { return nil }
    return clips.first { $0.id == id }
  }

  // MARK: - Sequence Lookups

  /// Placement covering a sequence time.
  func placement(atSequence t: TimeInterval) -> TimelineSequence.Placement? {
    TimelineSequence.placement(at: t, in: placements)
  }

  /// Active placement holding the playhead. A structural placement can exist
  /// without an active placement while the playhead is over trimmed-out footage.
  var activePlacement: TimelineSequence.Placement? {
    TimelineSequence.activePlacement(at: CMTimeGetSeconds(currentTime), in: placements)
  }

  /// Sequence start of a clip.
  func sequenceStart(ofClip id: UUID) -> TimeInterval? {
    placements.first { $0.clip.id == id }?.start
  }

  /// Which clip plays at a sequence time, and where in its source asset.
  func sourceContext(atSequence t: TimeInterval) -> (clip: TimelineClip, sourceTime: TimeInterval)? {
    guard let placement = TimelineSequence.activePlacement(at: t, in: placements) else { return nil }
    return (placement.clip, placement.sourceTime(at: t))
  }

  /// Convert a structural timeline time into the compact playable sequence used
  /// by speed scaling and export. Returns nil while the structural playhead is
  /// over trimmed-out footage.
  func playbackSequenceTime(atTimeline t: TimeInterval) -> TimeInterval? {
    guard let context = sourceContext(atSequence: t),
          let playbackPlacement = playbackPlacements.first(where: { $0.clip.id == context.clip.id })
    else { return nil }
    return playbackPlacement.sequenceTime(atSource: context.sourceTime)
  }

  /// Project an effect range from the stable structural timeline onto the compact
  /// playable/export sequence. Trimmed slots disappear here; clip identity remains
  /// the only mapping key, so a reorder cannot move the effect block itself.
  func projectToPlaybackSequence(timelineRange: ClosedRange<TimeInterval>) -> [ClosedRange<TimeInterval>] {
    TimelineSequence.project(
      timelineRange: timelineRange,
      from: placements,
      to: playbackPlacements
    )
  }

  /// True when a structural sequence time sits over any active video material.
  /// Effect tracks are independent from clip identity, so inserted clips are valid
  /// hosts too; trimmed-out slot edges remain unavailable for direct add gestures.
  func isPlayableMaterial(atSequence t: TimeInterval) -> Bool {
    sourceContext(atSequence: t) != nil
  }

  /// True when at least one enabled speed segment changes playback rate.
  var hasSpeedSegments: Bool {
    speedSegments.contains { $0.isEnabled && $0.rate != 1.0 }
  }

  /// Final exported length: the sequence with speed scaling applied.
  var effectiveOutputDuration: CMTime {
    if isGIF { return trimmedDuration }
    return CMTime(seconds: sequenceMap.outputDuration, preferredTimescale: 600)
  }

  // MARK: - Audio Control

  @Published var isMuted: Bool = false {
    didSet {
      player.isMuted = isMuted
    }
  }

  private var initialIsMuted: Bool = false

  /// Sync player preview audio with export audio mode and custom volume settings.
  func syncPlayerAudioWithExportSettings() {
    let shouldMute = exportSettings.audioMode == .mute
    if isMuted != shouldMute {
      isMuted = shouldMute
    } else {
      player.isMuted = shouldMute
    }

    guard exportSettings.audioMode == .custom else {
      player.volume = 1.0
      player.currentItem?.audioMix = nil
      return
    }

    player.volume = 1.0
    let settingsSnapshot = exportSettings
    let audioTrackRolesSnapshot = audioTrackRoles
    let assetSnapshot = asset
    Task { @MainActor [weak self] in
      do {
        let audioTracks = try await assetSnapshot.loadTracks(withMediaType: .audio)
        guard let self,
              exportSettings == settingsSnapshot,
              exportSettings.audioMode == .custom
        else { return }

        player.currentItem?.audioMix = VideoEditorAudioMixFactory.makeAudioMix(
          for: audioTracks,
          settings: settingsSnapshot,
          roles: audioTrackRolesSnapshot
        )
      } catch {
        DiagnosticLogger.shared.logError(.editor, error, "Preview audio mix failed")
      }
    }
  }

  // MARK: - Frame Thumbnails

  @Published private(set) var frameThumbnails: [NSImage] = []
  @Published private(set) var isExtractingFrames: Bool = false

  // MARK: - Zoom Segments

  @Published var zoomSegments: [ZoomSegment] = []
  @Published var selectedZoomId: UUID? = nil
  @Published var isZoomTrackVisible: Bool = true
  @Published var isSpeedTrackVisible: Bool = true
  @Published var isVideoInfoSidebarVisible: Bool = false
  @Published var isLeftSidebarVisible: Bool = false
  /// Which configuration the collapsed left rail currently expands.
  @Published var leftSidebarPanel: VideoEditorLeftSidebarPanel = .background
  @Published var zoomTransitionDuration: TimeInterval = ZoomCalculator.defaultTransitionDuration {
    didSet {
      let clamped = ZoomCalculator.clampTransitionDuration(zoomTransitionDuration)
      if abs(clamped - zoomTransitionDuration) > 0.0001 {
        zoomTransitionDuration = clamped
        return
      }

      UserDefaults.standard.set(clamped, forKey: PreferencesKeys.videoEditorZoomTransitionDuration)
    }
  }

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

  // MARK: - Export State

  @Published var isExporting: Bool = false
  @Published var exportProgress: Float = 0
  @Published var exportStatusMessage: String = "Preparing..."
  @Published var progressOperation: VideoEditorProgressOperation = .exportVideo

  // MARK: - Export Settings

  @Published var exportSettings: ExportSettings = .init()
  @Published private(set) var estimatedFileSize: Int64 = 0

  // MARK: - Unsaved Changes

  @Published var hasUnsavedChanges: Bool = false
  private var initialZoomSegments: [ZoomSegment] = []
  private var initialSpeedSegments: [SpeedSegment] = []
  private var initialClips: [TimelineClip] = []
  private var initialBackgroundStyle: BackgroundStyle = .none
  private var initialBackgroundPadding: CGFloat = 0
  private var initialBackgroundShadowIntensity: CGFloat = 0
  private var initialBackgroundCornerRadius: CGFloat = 0
  private var initialExportSettings: ExportSettings = .init()

  // MARK: - Cloud State

  @Published var cloudURL: URL?
  @Published var cloudKey: String?
  @Published var quickAccessItemId: UUID?

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
  private let restoredSessionData: VideoEditorSessionData?
  private var didRestoreSession = false

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

  var currentTime: CMTime {
    playbackState.currentTime
  }

  var isPlaying: Bool {
    playbackState.isPlaying
  }

  var isScrubbing: Bool {
    playbackState.isScrubbing
  }

  var isAutoZoomActiveAtCurrentTime: Bool {
    activeZoomSegment(atTimeline: CMTimeGetSeconds(currentTime))?.isAutoMode == true
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

  /// Final output length after trim + speed scaling. Differs from trimmed duration only when
  /// speed segments are active.
  var formattedOutputDuration: String {
    formatTime(effectiveOutputDuration)
  }

  var resolutionString: String {
    guard naturalSize.width > 0, naturalSize.height > 0 else { return "—" }
    return "\(Int(naturalSize.width)) × \(Int(naturalSize.height))"
  }

  var aspectRatioString: String {
    guard naturalSize.width > 0, naturalSize.height > 0 else { return "—" }
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

  init(
    url: URL,
    originalURL: URL? = nil,
    sessionData: VideoEditorSessionData? = nil
  ) {
    let initialMetadata = sessionData?.recordingMetadata
      ?? Self.loadRecordingMetadata(for: url, originalURL: originalURL)
    let editorAssetURL = sessionData?.sourceSnapshotURL
      ?? Self.editorAssetURL(for: url, metadata: initialMetadata)

    sourceURL = url
    self.originalURL = originalURL ?? url
    assetURL = editorAssetURL
    restoredSessionData = sessionData
    asset = AVAsset(url: editorAssetURL)
    let item = AVPlayerItem(asset: asset)
    primaryPlayerItem = item
    player = AVPlayer(playerItem: item)
    zoomTransitionDuration = Self.loadZoomTransitionDuration()
    recordingMetadata = initialMetadata

    setupTimeObserver()
    setupEndObserver()
    setupChangeTracking()
  }

  private static func loadRecordingMetadata(for url: URL, originalURL: URL?) -> RecordingMetadata? {
    let candidateURLs = [url, originalURL].compactMap { $0 }
      .reduce(into: [URL]()) { urls, url in
        guard !urls.contains(url) else { return }
        urls.append(url)
      }

    return candidateURLs.lazy.compactMap { RecordingMetadataStore.load(for: $0) }.first
  }

  static func editorAssetURL(for url: URL, metadata: RecordingMetadata?) -> URL {
    guard
      let audioSourceURL = metadata?.audioSourceURL,
      FileManager.default.fileExists(atPath: audioSourceURL.path)
    else {
      return url
    }

    return audioSourceURL
  }

  static func audioTrackRoles(for audioTracks: [AVAssetTrack],
                              metadata: RecordingMetadata?) -> [VideoEditorAudioTrackRole] {
    let count = audioTracks.count
    guard count > 0 else { return [] }

    if let metadata,
       metadata.audioSourceURL != nil,
       !metadata.audioSourceTracks.isEmpty {
      let rolesByTrackID = Dictionary(
        uniqueKeysWithValues: metadata.audioSourceTracks.map { ($0.trackID, $0.role) }
      )
      let resolvedRoles = audioTracks.compactMap { track in
        rolesByTrackID[Int(track.trackID)].map(Self.videoEditorAudioTrackRole)
      }
      if resolvedRoles.count == count {
        return resolvedRoles
      }
    }

    if let metadata,
       metadata.audioSourceURL != nil,
       metadata.audioSourceTrackRoles.count == count {
      return metadata.audioSourceTrackRoles.map(Self.videoEditorAudioTrackRole)
    }

    return VideoEditorAudioTrackRole.roles(forAudioTrackCount: count)
  }

  static func audioTrackRoles(forAudioTrackCount count: Int,
                              metadata: RecordingMetadata?) -> [VideoEditorAudioTrackRole] {
    if let metadata,
       metadata.audioSourceURL != nil,
       metadata.audioSourceTrackRoles.count == count {
      return metadata.audioSourceTrackRoles.map(videoEditorAudioTrackRole)
    }

    return VideoEditorAudioTrackRole.roles(forAudioTrackCount: count)
  }

  private static func videoEditorAudioTrackRole(_ role: RecordingAudioSourceTrackRole) -> VideoEditorAudioTrackRole {
    switch role {
    case .systemAudio:
      .systemAudio
    case .microphone:
      .microphone
    }
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
      if let metadata = GIFResizer.metadata(for: editingSourceURL) {
        naturalSize = metadata.size
        gifFrameCount = metadata.frameCount
        gifDuration = metadata.duration
        DiagnosticLogger.shared.log(
          .info,
          .editor,
          "GIF metadata loaded",
          context: [
            "size": "\(Int(metadata.size.width))x\(Int(metadata.size.height))",
            "frames": "\(metadata.frameCount)",
          ]
        )
      } else if let image = SandboxFileAccessManager.shared.withScopedAccess(to: editingSourceURL, {
        NSImage(contentsOf: editingSourceURL)
      }) {
        naturalSize = CGSize(
          width: image.representations.first?.pixelsWide ?? Int(image.size.width),
          height: image.representations.first?.pixelsHigh ?? Int(image.size.height)
        )
      }
      _ = restoreSessionIfNeeded()
      return
    }

    do {
      let loadedDuration = try await asset.load(.duration)
      duration = loadedDuration

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
      let audioTracks = try await asset.loadTracks(withMediaType: .audio)
      let audioTrackCount = audioTracks.count
      audioTrackRoles = Self.audioTrackRoles(for: audioTracks, metadata: recordingMetadata)
      if !restoreSessionIfNeeded(primaryDuration: CMTimeGetSeconds(loadedDuration)) {
        // Seed the sequence with one clip spanning the whole recording.
        let seed = TimelineClip(source: .primary, sourceDuration: CMTimeGetSeconds(loadedDuration))
        clips = [seed]
        initialClips = clips
        selectedClipId = seed.id
        activeClipId = seed.id
        activeItemSource = .primary
      }
      DiagnosticLogger.shared.log(.info, .editor, "Video metadata loaded", context: [
        "duration": String(format: "%.1fs", CMTimeGetSeconds(loadedDuration)),
        "size": "\(Int(naturalSize.width))x\(Int(naturalSize.height))",
        "audioTracks": "\(audioTrackCount)",
        "audioTrackRoles": audioTrackRoles.map(\.id).joined(separator: ","),
      ])
      // Calculate initial file size estimate after metadata loads
      recalculateEstimatedFileSize()
    } catch {
      DiagnosticLogger.shared.logError(.editor, error, "Failed to load video metadata")
      print("Failed to load video metadata: \(error)")
    }
  }

  /// Restore the non-destructive recipe after the master asset has loaded its
  /// duration. The current `sourceURL` remains the visible/replacement target;
  /// `asset` is already backed by the session's private source snapshot.
  @discardableResult
  private func restoreSessionIfNeeded(primaryDuration: TimeInterval? = nil) -> Bool {
    guard !didRestoreSession else {
      return restoredSessionData != nil && (!clips.isEmpty || isGIF)
    }
    didRestoreSession = true

    guard let sessionData = restoredSessionData else { return false }

    if !isGIF {
      guard let primaryDuration,
            primaryDuration.isFinite,
            primaryDuration > 0,
            !sessionData.clips.isEmpty,
            sessionData.clips.allSatisfy({ isRestorableClip($0, primaryDuration: primaryDuration) })
      else {
        DiagnosticLogger.shared.log(
          .warning,
          .editor,
          "Video Editor session ignored; timeline source validation failed"
        )
        return false
      }

      clips = sessionData.clips
      let structuralDuration = TimelineSequence.duration(clips)
      zoomSegments = sessionData.zoomSegments.compactMap { segment in
        guard segment.startTime.isFinite,
              segment.duration.isFinite,
              segment.startTime < structuralDuration
        else {
          return nil
        }
        return segment.clamped(to: structuralDuration)
      }
      speedSegments = sessionData.speedSegments.compactMap { segment in
        guard segment.startTime.isFinite,
              segment.duration.isFinite,
              segment.startTime < structuralDuration
        else {
          return nil
        }
        return segment.clamped(to: structuralDuration)
      }
      selectedClipId = clips.first?.id
      activeClipId = clips.first?.id
      activeItemSource = clips.first?.source
    } else {
      zoomSegments = []
      speedSegments = []
    }

    backgroundStyle = sessionData.backgroundStyle
    backgroundPadding = sessionData.backgroundPadding
    backgroundShadowIntensity = sessionData.backgroundShadowIntensity
    backgroundCornerRadius = sessionData.backgroundCornerRadius
    backgroundAlignment = sessionData.backgroundAlignment
    backgroundAspectRatio = sessionData.backgroundAspectRatio
    exportSettings = sessionData.exportSettings
    isMuted = sessionData.isMuted
    rebuildAutoFocusPaths(for: zoomSegments)

    // Restored values are the new clean baseline. A later user change should
    // produce the normal unsaved-document state and a new session snapshot.
    markAsSaved()
    updateClipActionAvailability()
    syncPlayerAudioWithExportSettings()
    recalculateEstimatedFileSize()

    DiagnosticLogger.shared.log(.info, .editor, "Video Editor session restored", context: [
      "clips": "\(clips.count)",
      "zooms": "\(zoomSegments.count)",
      "speeds": "\(speedSegments.count)",
    ])
    return true
  }

  private func isRestorableClip(
    _ clip: TimelineClip,
    primaryDuration: TimeInterval
  ) -> Bool {
    let values = [
      clip.sourceDuration,
      clip.sourceStart,
      clip.sourceEnd,
      clip.slotStart,
      clip.slotEnd,
    ]
    guard values.allSatisfy(\.isFinite),
          clip.sourceDuration > 0,
          clip.sourceStart >= 0,
          clip.sourceStart < clip.sourceEnd,
          clip.slotStart >= 0,
          clip.slotStart < clip.slotEnd,
          clip.sourceStart >= clip.slotStart - 0.05,
          clip.sourceEnd <= clip.slotEnd + 0.05,
          clip.sourceEnd <= clip.sourceDuration + 0.05,
          clip.slotEnd <= clip.sourceDuration + 0.05,
          clip.duration >= TimelineClip.minDuration - 0.0001,
          clip.slotDuration >= TimelineClip.minDuration - 0.0001
    else {
      return false
    }

    switch clip.source {
    case .primary:
      return abs(clip.sourceDuration - primaryDuration) <= 0.05
    case .file(let url):
      return FileManager.default.fileExists(atPath: url.path)
    }
  }

  // MARK: - Playback Control

  /// Source asset currently loaded into the player, so clips cut from the same
  /// asset do not force a reload at every boundary.
  private var activeItemSource: TimelineClip.Source?
  /// Clip currently feeding the player, so a tick knows which placement it is in.
  private var activeClipId: UUID?
  /// True while a handoff seek into the next clip is still completing. Ticks and
  /// item-end notifications delivered in that window still reflect the previous
  /// clip's position, so they must be dropped instead of acted on.
  private var handoffSeekInFlight = false
  /// Pre-drag snapshot for clip trim gestures (one undo entry per gesture).
  private var clipTrimOriginal: TimelineClip?
  private let primaryPlayerItem: AVPlayerItem

  func play() {
    let playableTime = normalizedTimelineTime(currentTime)
    if CMTimeCompare(playableTime, currentTime) != 0 {
      playbackState.setCurrentTime(playableTime)
      seekPlayerInternally(to: CMTimeGetSeconds(playableTime))
    }
    // Preserve pitch when playing speed-scaled regions (matches export's .spectral choice).
    player.currentItem?.audioTimePitchAlgorithm = .spectral
    // Persist the requested rate as AVPlayer's resume/default rate and explicitly start
    // playback. Assigning only `rate` is transient: a later `play()`/item handoff can
    // restore AVPlayer's default 1x rate and silently lose the speed effect.
    applyPreviewRate(currentPreviewRate(at: currentTime), startPlayback: true)
    playbackState.setPlaying(true)
  }

  /// Playback rate for the speed segment under a SEQUENCE time.
  ///
  /// The effect is authored on the structural timeline and is projected to the
  /// compact playable axis only for rate lookup. This keeps inserted clips and
  /// reordered clips under the same independent speed track as the preview/export.
  func currentPreviewRate(at time: CMTime) -> Float {
    guard hasSpeedSegments else { return 1.0 }
    let t = CMTimeGetSeconds(time)
    guard let playbackTime = playbackSequenceTime(atTimeline: t) else { return 1.0 }
    return Float(sequenceMap.rate(atSequence: playbackTime))
  }

  func pause() {
    player.pause()
    playbackState.setPlaying(false)
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

  /// Seek to a STRUCTURAL timeline time. Inactive trim slots remain addressable for
  /// stable layout, but the time is normalized to the nearest active frame.
  func seek(to time: CMTime) {
    let clampedTime = normalizedTimelineTime(time)
    playbackState.setCurrentTime(clampedTime)
    seekPlayerInternally(to: CMTimeGetSeconds(clampedTime))
    updateClipActionAvailability()
  }

  func stepTimeline(by seconds: Double) {
    let step = CMTime(seconds: seconds, preferredTimescale: 600)
    let steppedTime = CMTimeAdd(currentTime, step)
    let clampedTime = normalizedTimelineTime(steppedTime)
    playbackState.setCurrentTime(clampedTime)
    seekPlayerInternally(to: CMTimeGetSeconds(clampedTime))
    updateClipActionAvailability()
  }

  // MARK: - Scrubbing

  func startScrubbing() {
    playbackState.setScrubbing(true)
    pause()
  }

  /// Scrubbing follows the structural timeline but snaps over inactive trim slots,
  /// keeping the playhead on playable material.
  func scrub(to time: CMTime) {
    let clampedTime = normalizedTimelineTime(time)
    playbackState.setCurrentTime(clampedTime)
    seekPlayerInternally(to: CMTimeGetSeconds(clampedTime))
    updateClipActionAvailability()
  }

  func endScrubbing() {
    playbackState.setScrubbing(false)
  }

  // MARK: - Player Item Management (clip sequence)

  /// Point the player at whichever clip covers a sequence time, seeking to that
  /// clip's own source time.
  private func seekPlayerInternally(to sequenceSeconds: TimeInterval) {
    guard let context = sourceContext(atSequence: sequenceSeconds) else { return }
    activeClipId = context.clip.id
    activateItemIfNeeded(for: context.clip, previewTime: sequenceSeconds)
    player.seek(
      to: CMTime(seconds: context.sourceTime, preferredTimescale: 600),
      toleranceBefore: .zero,
      toleranceAfter: .zero
    )
  }

  /// Swap the player item when the sequence crosses into a different source asset.
  ///
  /// Keyed on `source`, not clip id: consecutive clips cut from the same asset share
  /// one item, so an ordinary split costs a seek rather than a reload.
  private func activateItemIfNeeded(for clip: TimelineClip, previewTime: TimeInterval? = nil) {
    guard activeItemSource != clip.source else { return }
    let wasPlaying = isPlaying
    let previousRate = player.rate

    let item = clip.isPrimary ? primaryPlayerItem : AVPlayerItem(asset: clipAsset(for: clip))
    player.replaceCurrentItem(with: item)
    activeItemSource = clip.source

    if wasPlaying {
      player.currentItem?.audioTimePitchAlgorithm = .spectral
      let resumedRate = if let previewTime {
        currentPreviewRate(at: CMTime(seconds: previewTime, preferredTimescale: 600))
      } else {
        max(previousRate, 1.0)
      }
      applyPreviewRate(resumedRate, startPlayback: true)
    }
  }

  /// Clamp to the sequence axis.
  private func clampTimelineTime(_ time: CMTime) -> CMTime {
    CMTimeClampToRange(time, range: CMTimeRange(start: .zero, end: timelineDuration))
  }

  /// Snap a structural timeline time to the nearest active clip material. Trimmed
  /// slots remain visible for alignment, but they are not playable or exportable.
  private func normalizedTimelineTime(_ time: CMTime) -> CMTime {
    let clamped = CMTimeGetSeconds(clampTimelineTime(time))
    guard sourceContext(atSequence: clamped) == nil else {
      return CMTime(seconds: clamped, preferredTimescale: 600)
    }

    var before: TimeInterval?
    var after: TimeInterval?
    for placement in placements where placement.activeEnd > placement.activeStart {
      if placement.activeEnd <= clamped {
        before = max(before ?? 0, placement.activeEnd - 0.0001)
      } else if placement.activeStart >= clamped {
        after = min(after ?? TimeInterval.greatestFiniteMagnitude, placement.activeStart)
      }
    }

    let resolved: TimeInterval = switch (before, after) {
    case let (before?, after?):
      clamped - before <= after - clamped ? before : after
    case let (before?, nil):
      before
    case let (nil, after?):
      after
    case (nil, nil):
      clamped
    }
    return CMTime(seconds: resolved, preferredTimescale: 600)
  }

  // MARK: - Trim Control

  /// Trim the sequence's first primary clip. GIF keeps its own stored window.
  func setTrimStart(_ time: CMTime, recordUndo: Bool = true) {
    guard isGIF else {
      guard let first = clips.first(where: \.isPrimary) else { return }
      updateClip(id: first.id, sourceStart: CMTimeGetSeconds(time))
      return
    }

    let oldValue = gifTrimStart
    let minDuration = CMTime(seconds: 1.0, preferredTimescale: 600)
    let maxStart = CMTimeSubtract(gifTrimEnd, minDuration)
    let clampedStart = CMTimeClampToRange(time, range: CMTimeRange(start: .zero, end: maxStart))
    gifTrimStart = clampedStart
    if CMTimeCompare(currentTime, clampedStart) < 0 {
      seek(to: clampedStart)
    }
    if recordUndo, CMTimeCompare(oldValue, clampedStart) != 0 {
      recordAction(.trimStart(old: oldValue, new: clampedStart))
    }
  }

  /// Trim the sequence's last primary clip. GIF keeps its own stored window.
  func setTrimEnd(_ time: CMTime, recordUndo: Bool = true) {
    guard isGIF else {
      guard let last = clips.last(where: \.isPrimary) else { return }
      updateClip(id: last.id, sourceEnd: CMTimeGetSeconds(time))
      return
    }

    let oldValue = gifTrimEnd
    let minDuration = CMTime(seconds: 1.0, preferredTimescale: 600)
    let minEnd = CMTimeAdd(gifTrimStart, minDuration)
    let clampedEnd = CMTimeClampToRange(time, range: CMTimeRange(start: minEnd, end: duration))
    gifTrimEnd = clampedEnd
    if CMTimeCompare(currentTime, clampedEnd) > 0 {
      seek(to: clampedEnd)
    }
    if recordUndo, CMTimeCompare(oldValue, clampedEnd) != 0 {
      recordAction(.trimEnd(old: oldValue, new: clampedEnd))
    }
  }

  /// Collapse the sequence back to one full-length primary clip.
  func resetTrim() {
    guard !isGIF else {
      gifTrimStart = .zero
      gifTrimEnd = duration
      return
    }
    clips = [TimelineClip(source: .primary, sourceDuration: CMTimeGetSeconds(duration))]
    selectedClipId = clips.first?.id
  }

  // MARK: - Frame Extraction

  func extractFrames() async {
    // GIF files don't use AVAsset — skip frame extraction
    guard !isGIF else { return }
    guard CMTimeGetSeconds(duration) > 0 else { return }

    isExtractingFrames = true
    defer { isExtractingFrames = false }

    let startedAt = Date()
    let profile = await determineFrameExtractionProfile()
    let totalSeconds = CMTimeGetSeconds(duration)
    let cgImages = await generateFrameThumbnails(
      frameCount: profile.frameCount,
      totalSeconds: totalSeconds,
      tolerance: profile.tolerance
    )

    frameThumbnails = cgImages.map { image in
      NSImage(cgImage: image, size: NSSize(width: 120, height: 68))
    }

    DiagnosticLogger.shared.log(.info, .editor, "Frame strip extracted", context: [
      "strategy": profile.strategyLabel,
      "requestedFrames": "\(profile.frameCount)",
      "generatedFrames": "\(frameThumbnails.count)",
      "elapsedMs": "\(Int(Date().timeIntervalSince(startedAt) * 1000))",
    ])
  }

  private func determineFrameExtractionProfile() async -> FrameExtractionProfile {
    guard let track = try? await asset.loadTracks(withMediaType: .video).first else {
      return FrameExtractionProfile(frameCount: 25, tolerance: .zero, strategyLabel: "default-no-track")
    }

    let estimatedDataRate = await (try? track.load(.estimatedDataRate)) ?? 0
    let pixelCount = naturalSize.width * naturalSize.height

    // Guardrail: heavier files (high resolution / high bitrate) get lighter extraction to keep UI responsive.
    if pixelCount >= 7_000_000 || estimatedDataRate >= 80_000_000 {
      return FrameExtractionProfile(
        frameCount: 12,
        tolerance: CMTime(value: 1, timescale: 20),
        strategyLabel: "very-heavy"
      )
    }

    if pixelCount >= 3_700_000 || estimatedDataRate >= 45_000_000 {
      return FrameExtractionProfile(
        frameCount: 16,
        tolerance: CMTime(value: 1, timescale: 30),
        strategyLabel: "heavy"
      )
    }

    return FrameExtractionProfile(frameCount: 25, tolerance: .zero, strategyLabel: "default")
  }

  private func generateFrameThumbnails(
    frameCount: Int,
    totalSeconds: Double,
    tolerance: CMTime
  ) async -> [CGImage] {
    let safeCount = max(frameCount, 1)
    let targetSize = CGSize(width: 120, height: 68)
    let inputURL = editingSourceURL

    return await withCheckedContinuation { continuation in
      DispatchQueue.global(qos: .userInitiated).async {
        autoreleasepool {
          let generator = AVAssetImageGenerator(asset: AVAsset(url: inputURL))
          generator.appliesPreferredTrackTransform = true
          generator.maximumSize = targetSize
          generator.requestedTimeToleranceBefore = tolerance
          generator.requestedTimeToleranceAfter = tolerance

          // Sample each cell's center so thumbnail i represents the time window
          // [i/count, (i+1)/count) of the duration — the same window the strip
          // lays out (VideoTimelineFrameStrip tiles cells of width
          // contentWidth/count). Endpoint sampling (i/(count-1)) instead drew
          // each frame off-center by up to half a cell, a drift that grows
          // with the zoom level.
          var slots: [CGImage?] = Array(repeating: nil, count: safeCount)
          for i in 0 ..< safeCount {
            let progress = (Double(i) + 0.5) / Double(safeCount)
            let time = CMTime(seconds: totalSeconds * progress, preferredTimescale: 600)
            if let cgImage = try? generator.copyCGImage(at: time, actualTime: nil) {
              slots[i] = cgImage
            }
          }

          // Fill decode holes from the neighboring slot so the slot count — and
          // therefore the time mapping — stays exact even when a frame fails.
          // Forward pass covers interior/trailing holes; the backward pass
          // covers any leading holes with the first decodable frame.
          var lastGood: CGImage?
          for i in 0 ..< safeCount {
            if let image = slots[i] {
              lastGood = image
            } else {
              slots[i] = lastGood
            }
          }
          var nextGood: CGImage?
          for i in stride(from: safeCount - 1, through: 0, by: -1) {
            if let image = slots[i] {
              nextGood = image
            } else {
              slots[i] = nextGood
            }
          }

          continuation.resume(returning: slots.compactMap { $0 })
        }
      }
    }
  }

  // MARK: - Save State

  func markAsSaved() {
    hasUnsavedChanges = false
    initialIsMuted = isMuted
    initialZoomSegments = zoomSegments
    initialSpeedSegments = speedSegments
    initialClips = clips
    initialBackgroundStyle = backgroundStyle
    initialBackgroundPadding = backgroundPadding
    initialBackgroundShadowIntensity = backgroundShadowIntensity
    initialBackgroundCornerRadius = backgroundCornerRadius
    initialExportSettings = exportSettings
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
    DiagnosticLogger.shared.log(.debug, .editor, "Undo", context: ["stackDepth": "\(undoStack.count)"])
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

    case .addSpeed(let segment):
      speedSegments.removeAll { $0.id == segment.id }
      if selectedSpeedId == segment.id { selectedSpeedId = nil }
      redoStack.append(.removeSpeed(segment: segment))

    case .removeSpeed(let segment):
      speedSegments.append(segment)
      redoStack.append(.addSpeed(segment: segment))

    case .updateSpeed(let old, let new):
      if let index = speedSegments.firstIndex(where: { $0.id == new.id }) {
        speedSegments[index] = old
      }
      redoStack.append(.updateSpeed(old: new, new: old))

    case .toggleMute(let old, _):
      isMuted = old
      redoStack.append(.toggleMute(old: !old, new: old))

    case .updateBackground(
      let oldStyle,
      let newStyle,
      let oldPadding,
      let newPadding,
      let oldShadow,
      let newShadow,
      let oldCorner,
      let newCorner
    ):
      backgroundStyle = oldStyle
      backgroundPadding = oldPadding
      backgroundShadowIntensity = oldShadow
      backgroundCornerRadius = oldCorner
      redoStack.append(.updateBackground(
        oldStyle: newStyle,
        newStyle: oldStyle,
        oldPadding: newPadding,
        newPadding: oldPadding,
        oldShadow: newShadow,
        newShadow: oldShadow,
        oldCorner: newCorner,
        newCorner: oldCorner
      ))

    case .addClip(let clip, let index):
      removeClipSilently(id: clip.id)
      redoStack.append(.removeClip(clip: clip, index: index))

    case .removeClip(let clip, let index):
      insertClipSilently(clip, at: index)
      redoStack.append(.addClip(clip: clip, index: index))

    case .updateClip(let old, let new):
      replaceClipSilently(id: new.id, with: old)
      redoStack.append(.updateClip(old: new, new: old))

    case .moveClip(let id, let fromIndex, let toIndex):
      moveClipSilently(id: id, to: fromIndex)
      redoStack.append(.moveClip(id: id, fromIndex: toIndex, toIndex: fromIndex))

    case .splitClip(let original, let index, let first, let second):
      // Rejoin: drop both halves and restore the clip they came from.
      removeClipSilently(id: first.id)
      removeClipSilently(id: second.id)
      insertClipSilently(original, at: index)
      redoStack.append(.splitClip(original: original, index: index, first: first, second: second))
    }
  }

  /// Redo the last undone action
  func redo() {
    guard let action = redoStack.popLast() else { return }
    DiagnosticLogger.shared.log(.debug, .editor, "Redo", context: ["stackDepth": "\(redoStack.count)"])
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

    case .addSpeed(let segment):
      speedSegments.removeAll { $0.id == segment.id }
      if selectedSpeedId == segment.id { selectedSpeedId = nil }
      undoStack.append(.removeSpeed(segment: segment))

    case .removeSpeed(let segment):
      speedSegments.append(segment)
      undoStack.append(.addSpeed(segment: segment))

    case .updateSpeed(let old, let new):
      if let index = speedSegments.firstIndex(where: { $0.id == new.id }) {
        speedSegments[index] = old
      }
      undoStack.append(.updateSpeed(old: new, new: old))

    case .toggleMute(let old, _):
      isMuted = old
      undoStack.append(.toggleMute(old: !old, new: old))

    case .updateBackground(
      let oldStyle,
      let newStyle,
      let oldPadding,
      let newPadding,
      let oldShadow,
      let newShadow,
      let oldCorner,
      let newCorner
    ):
      backgroundStyle = oldStyle
      backgroundPadding = oldPadding
      backgroundShadowIntensity = oldShadow
      backgroundCornerRadius = oldCorner
      undoStack.append(.updateBackground(
        oldStyle: newStyle,
        newStyle: oldStyle,
        oldPadding: newPadding,
        newPadding: oldPadding,
        oldShadow: newShadow,
        newShadow: oldShadow,
        oldCorner: newCorner,
        newCorner: oldCorner
      ))

    case .addClip(let clip, let index):
      removeClipSilently(id: clip.id)
      undoStack.append(.removeClip(clip: clip, index: index))

    case .removeClip(let clip, let index):
      insertClipSilently(clip, at: index)
      undoStack.append(.addClip(clip: clip, index: index))

    case .updateClip(let old, let new):
      replaceClipSilently(id: new.id, with: old)
      undoStack.append(.updateClip(old: new, new: old))

    case .moveClip(let id, let fromIndex, let toIndex):
      moveClipSilently(id: id, to: fromIndex)
      undoStack.append(.moveClip(id: id, fromIndex: toIndex, toIndex: fromIndex))

    case .splitClip(let original, let index, let first, let second):
      // Re-split: the undo handler rejoined the halves, so redo has to divide again.
      removeClipSilently(id: original.id)
      insertClipSilently(first, at: index)
      insertClipSilently(second, at: index + 1)
      undoStack.append(.splitClip(original: original, index: index, first: first, second: second))
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
    DiagnosticLogger.shared.log(
      .info,
      .editor,
      "Renaming file",
      context: ["from": sourceURL.lastPathComponent, "to": newName]
    )
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
      throw NSError(
        domain: "VideoEditor",
        code: 2,
        userInfo: [NSLocalizedDescriptionKey: "A file with this name already exists"]
      )
    }

    try FileManager.default.moveItem(at: sourceAccess.url, to: newURL)

    do {
      try RecordingMetadataStore.moveAssociation(from: oldSourceURL, to: newURL)
    } catch {
      DiagnosticLogger.shared.logError(.editor, error, "Metadata association move failed during rename")
      print("[RecordingMetadata] Failed to move metadata association during rename: \(error.localizedDescription)")
    }

    sourceURL = newURL
    if originalURL == oldSourceURL {
      originalURL = newURL
    }
  }

  // MARK: - Zoom Management

  /// Add a new zoom segment at the specified structural timeline time.
  @discardableResult
  func addZoom(at time: TimeInterval) -> UUID {
    let canUseAutoFocus = sourceContext(atSequence: time)?.clip.isPrimary == true
    DiagnosticLogger.shared.log(
      .debug,
      .editor,
      "Adding zoom segment",
      context: [
        "time": String(format: "%.2f", time),
        "type": hasMouseTrackingData && canUseAutoFocus ? "auto" : "manual",
      ]
    )
    let videoDuration = CMTimeGetSeconds(timelineDuration)
    guard videoDuration > 0 else { return UUID() }
    let defaultZoomType: ZoomType = hasMouseTrackingData && canUseAutoFocus ? .auto : .manual
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
    DiagnosticLogger.shared.log(.debug, .editor, "Removing zoom segment", context: ["id": id.uuidString])
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
    let videoDuration = CMTimeGetSeconds(timelineDuration)

    if let startTime {
      segment.startTime = max(0, min(startTime, videoDuration - ZoomSegment.minDuration))
    }
    if let duration {
      segment.duration = max(ZoomSegment.minDuration, min(duration, videoDuration - segment.startTime))
    }
    if let zoomLevel {
      segment.zoomLevel = max(ZoomSegment.minZoomLevel, min(zoomLevel, ZoomSegment.maxZoomLevel))
    }
    if let zoomCenter {
      segment.zoomCenter = CGPoint(
        x: max(0, min(zoomCenter.x, 1)),
        y: max(0, min(zoomCenter.y, 1))
      )
    }
    if let zoomType {
      segment.zoomType = zoomType
    }
    if let followSpeed {
      segment.followSpeed = AutoFocusSettings.clampFollowSpeed(followSpeed)
    }
    if let focusMargin {
      segment.focusMargin = AutoFocusSettings.clampFocusMargin(focusMargin)
    }
    if let isEnabled {
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
    transitionDuration: TimeInterval? = nil
  ) -> VideoEditorCameraState {
    let effectiveDuration = ZoomCalculator.clampTransitionDuration(
      transitionDuration ?? zoomTransitionDuration
    )
    // Zoom segments are authored directly on the structural timeline. Auto-focus
    // samples are the one source-bound input; map them to the current clip sequence.
    // The mapper holds the last center across inserted clips instead of interpolating
    // through missing source data.
    let activeSegment = ZoomCalculator.activeSegment(at: time, in: zoomSegments)
    var resolvedPaths = autoFocusPaths
    if let activeSegment, activeSegment.isAutoMode {
      resolvedPaths[activeSegment.id] = VideoEditorAutoFocusEngine.timelinePath(
        autoFocusPath(for: activeSegment),
        placements: placements
      )
    }
    return VideoEditorAutoFocusEngine.resolvedCameraState(
      at: time,
      segments: zoomSegments,
      autoFocusPaths: resolvedPaths,
      transitionDuration: effectiveDuration
    )
  }

  func autoFocusPath(for segment: ZoomSegment) -> [AutoFocusCameraSample] {
    autoFocusPaths[segment.id] ?? []
  }

  /// Select a zoom segment
  func selectZoom(id: UUID?) {
    selectedZoomId = id
  }

  /// Select a zoom segment and open its configuration in the left sidebar rail.
  func openZoomConfiguration(id: UUID) {
    guard zoomSegments.contains(where: { $0.id == id }) else { return }
    selectedZoomId = id
    leftSidebarPanel = .zoom
    isLeftSidebarVisible = true
  }

  /// Toggle zoom enabled state
  func toggleZoomEnabled(id: UUID) {
    guard let index = zoomSegments.firstIndex(where: { $0.id == id }) else { return }
    zoomSegments[index].isEnabled.toggle()
  }

  // MARK: - Speed Segment Mutators (Timelapse)

  /// Clamp a desired absolute range to the structural timeline and to gaps between
  /// other enabled speed segments (no overlap). Returns nil when the remaining room
  /// is smaller than the minimum segment duration.
  private func clampedSpeedRange(
    _ range: ClosedRange<TimeInterval>,
    excluding id: UUID?
  ) -> (start: TimeInterval, duration: TimeInterval)? {
    let lowerBound = 0.0
    let upperBound = CMTimeGetSeconds(timelineDuration)
    guard upperBound - lowerBound >= SpeedSegment.minDuration else { return nil }

    var start = max(lowerBound, range.lowerBound)
    var end = min(upperBound, range.upperBound)

    // Shrink against the nearest neighbouring segments so the result never overlaps.
    let neighbours = speedSegments.filter { $0.id != id && $0.isEnabled }
    let desiredMid = (start + end) / 2
    for other in neighbours {
      let oStart = max(lowerBound, other.startTime)
      let oEnd = min(upperBound, other.endTime)
      guard oEnd > oStart else { continue }
      // Neighbour fully precedes the desired midpoint → push our start past it.
      if oEnd <= desiredMid {
        start = max(start, oEnd)
      } else if oStart >= desiredMid {
        // Neighbour follows the midpoint → pull our end before it.
        end = min(end, oStart)
      } else {
        // Neighbour straddles the midpoint → no room.
        return nil
      }
    }

    guard end - start >= SpeedSegment.minDuration else { return nil }
    return (start, end - start)
  }

  /// Add a speed segment centered at a structural timeline time, using the default
  /// duration and rate.
  @discardableResult
  func addSpeed(at time: TimeInterval) -> UUID? {
    guard !isGIF else { return nil }
    let half = SpeedSegment.defaultDuration / 2
    return addSpeed(range: (time - half) ... (time + half), rate: SpeedSegment.defaultRate)
  }

  /// Add a speed segment for an explicit structural timeline range + rate. Clamps to
  /// the timeline and neighbouring speed segments.
  @discardableResult
  func addSpeed(range: ClosedRange<TimeInterval>, rate: Double) -> UUID? {
    guard let (start, duration) = clampedSpeedRange(range, excluding: nil) else {
      DiagnosticLogger.shared.log(.debug, .editor, "Speed segment add rejected (no room)")
      return nil
    }
    let segment = SpeedSegment(startTime: start, duration: duration, rate: SpeedSegment.clampRate(rate))
    DiagnosticLogger.shared.log(
      .debug,
      .editor,
      "Adding speed segment",
      context: ["start": String(format: "%.2f", start), "rate": String(format: "%.2f", segment.rate)]
    )
    speedSegments.append(segment)
    selectedSpeedId = segment.id
    recordAction(.addSpeed(segment: segment))
    return segment.id
  }

  /// Remove a speed segment by ID.
  func removeSpeed(id: UUID) {
    guard let segment = speedSegments.first(where: { $0.id == id }) else { return }
    DiagnosticLogger.shared.log(.debug, .editor, "Removing speed segment", context: ["id": id.uuidString])
    speedSegments.removeAll { $0.id == id }
    if selectedSpeedId == id { selectedSpeedId = nil }
    recordAction(.removeSpeed(segment: segment))
  }

  /// Update a speed segment's rate and/or range. Range changes are clamped against the
  /// structural timeline bounds and neighbouring segments; an update that loses all room
  /// is ignored.
  func updateSpeed(
    id: UUID,
    rate: Double? = nil,
    startTime: TimeInterval? = nil,
    duration: TimeInterval? = nil
  ) {
    guard let index = speedSegments.firstIndex(where: { $0.id == id }) else { return }
    let old = speedSegments[index]
    var new = old

    if let rate { new.rate = SpeedSegment.clampRate(rate) }

    if startTime != nil || duration != nil {
      let desiredStart = startTime ?? old.startTime
      let desiredDuration = duration ?? old.duration
      guard let (clampedStart, clampedDuration) = clampedSpeedRange(
        desiredStart ... (desiredStart + desiredDuration),
        excluding: id
      ) else { return }
      new.startTime = clampedStart
      new.duration = clampedDuration
    }

    guard new != old else { return }
    speedSegments[index] = new
    recordAction(.updateSpeed(old: old, new: new))
  }

  /// Select a speed segment (nil clears selection).
  func selectSpeed(id: UUID?) {
    selectedSpeedId = id
  }

  /// Toggle a speed segment's enabled state (undoable — affects output duration).
  func toggleSpeedEnabled(id: UUID) {
    guard let index = speedSegments.firstIndex(where: { $0.id == id }) else { return }
    let old = speedSegments[index]
    var new = old
    new.isEnabled.toggle()
    speedSegments[index] = new
    recordAction(.updateSpeed(old: old, new: new))
  }

  /// Remove every speed segment (undoable — records one removal per segment).
  func removeAllSpeeds() {
    let ids = speedSegments.map(\.id)
    for id in ids {
      removeSpeed(id: id)
    }
  }

  // MARK: - Clip Management (split, delete, move, trim, insert)

  /// Mutators that do not touch the undo stack. Undo/redo replays through these;
  /// the public operations below wrap them with `recordAction`.
  private func insertClipSilently(_ clip: TimelineClip, at index: Int) {
    clips.insert(clip, at: max(0, min(index, clips.count)))
  }

  private func removeClipSilently(id: UUID) {
    clips.removeAll { $0.id == id }
    if selectedClipId == id { selectedClipId = nil }
  }

  private func replaceClipSilently(id: UUID, with clip: TimelineClip) {
    guard let index = clips.firstIndex(where: { $0.id == id }) else { return }
    clips[index] = clip
  }

  private func moveClipSilently(id: UUID, to index: Int) {
    guard let from = clips.firstIndex(where: { $0.id == id }) else { return }
    let target = max(0, min(index, clips.count - 1))
    guard target != from else { return }
    let clip = clips.remove(at: from)
    clips.insert(clip, at: target)
  }

  func selectClip(id: UUID?) {
    selectedClipId = id
    updateClipActionAvailability()
  }

  /// The clip a delete/split acts on: the explicit selection, else the one under
  /// the playhead.
  var targetClip: TimelineClip? {
    selectedClip ?? activePlacement?.clip
  }

  /// Backing asset for a clip. `.file` assets are cached per URL so duplicated
  /// clips share one decoder.
  func clipAsset(for clip: TimelineClip) -> AVAsset {
    switch clip.source {
    case .primary:
      return asset
    case .file(let url):
      if let cached = clipAssets[url] { return cached }
      let loaded = AVAsset(url: url)
      clipAssets[url] = loaded
      return loaded
    }
  }

  // MARK: Split

  /// Split the clip under the playhead into two clips at that frame.
  ///
  /// Both halves must clear `TimelineClip.minDuration`, so splitting right at a clip
  /// edge is a no-op rather than creating a sliver.
  func splitAtPlayhead() {
    guard !isGIF else { return }
    let t = CMTimeGetSeconds(currentTime)
    guard let placement = TimelineSequence.activePlacement(at: t, in: placements) else { return }

    let original = placement.clip
    let cutPoint = placement.sourceTime(at: t)
    guard cutPoint - original.sourceStart >= TimelineClip.minDuration,
          original.sourceEnd - cutPoint >= TimelineClip.minDuration
    else { return }

    let first = TimelineClip(
      source: original.source,
      sourceDuration: original.sourceDuration,
      sourceStart: original.sourceStart,
      sourceEnd: cutPoint,
      slotStart: original.slotStart,
      slotEnd: cutPoint
    )
    let second = TimelineClip(
      source: original.source,
      sourceDuration: original.sourceDuration,
      sourceStart: cutPoint,
      sourceEnd: original.sourceEnd,
      slotStart: cutPoint,
      slotEnd: original.slotEnd
    )

    DiagnosticLogger.shared.log(.debug, .editor, "Split clip", context: [
      "at": String(format: "%.2f", t),
      "source": String(format: "%.2f", cutPoint),
    ])

    clips.replaceSubrange(placement.index ... placement.index, with: [first, second])
    recordAction(.splitClip(original: original, index: placement.index, first: first, second: second))
    // The playhead sits on the new boundary, which belongs to the second half.
    selectedClipId = second.id
    updateClipActionAvailability()
  }

  // MARK: Delete (ripple)

  /// Remove a clip; everything after it slides left to close the gap.
  func removeClip(id: UUID) {
    guard !isGIF else { return }
    guard clips.count > 1 else { return } // never leave an empty timeline
    guard let index = clips.firstIndex(where: { $0.id == id }) else { return }

    let clip = clips[index]
    let gapStart = sequenceStart(ofClip: id) ?? 0
    clips.remove(at: index)
    recordAction(.removeClip(clip: clip, index: index))

    DiagnosticLogger.shared.log(.debug, .editor, "Removed clip", context: [
      "index": "\(index)",
      "duration": String(format: "%.2fs", clip.duration),
    ])

    // Select the clip that slid into the gap and park the playhead on it.
    selectedClipId = clips.indices.contains(index) ? clips[index].id : clips.last?.id
    let structuralDuration = CMTimeGetSeconds(timelineDuration)
    seek(to: CMTime(seconds: min(gapStart, structuralDuration), preferredTimescale: 600))
    updateClipActionAvailability()
  }

  /// Delete the selected clip, falling back to the one under the playhead.
  func deleteSelectedClip() {
    guard let clip = targetClip else { return }
    removeClip(id: clip.id)
  }

  // MARK: Move (reorder)

  /// Reorder a clip to an absolute index. Neighbours shift to close the gap, so the
  /// sequence stays gapless.
  func moveClip(id: UUID, toIndex: Int) {
    guard !isGIF else { return }
    guard let from = clips.firstIndex(where: { $0.id == id }) else { return }
    let target = max(0, min(toIndex, clips.count - 1))
    guard target != from else { return }

    let clip = clips.remove(at: from)
    clips.insert(clip, at: target)
    recordAction(.moveClip(id: id, fromIndex: from, toIndex: target))
    updateClipActionAvailability()
  }

  /// Nudge a clip one slot left or right.
  func moveClip(id: UUID, by delta: Int) {
    guard let from = clips.firstIndex(where: { $0.id == id }) else { return }
    moveClip(id: id, toIndex: from + delta)
  }

  // MARK: Trim (non-destructive)

  /// Adjust a clip's in/out points within its own source asset.
  ///
  /// Bounded by the clip's fixed structural slot, so dragging an edge outward restores
  /// frames trimmed away earlier without crossing a neighboring clip's slot.
  func updateClip(id: UUID, sourceStart: TimeInterval? = nil, sourceEnd: TimeInterval? = nil) {
    guard let index = clips.firstIndex(where: { $0.id == id }) else { return }
    let old = clips[index]
    guard sourceStart != nil || sourceEnd != nil else { return }

    var newStart = sourceStart ?? old.sourceStart
    var newEnd = sourceEnd ?? old.sourceEnd

    if sourceStart != nil {
      newStart = max(old.slotStart, min(newStart, newEnd - TimelineClip.minDuration))
    }
    if sourceEnd != nil {
      newEnd = min(old.slotEnd, max(newEnd, newStart + TimelineClip.minDuration))
    }

    let new = TimelineClip(
      id: old.id,
      source: old.source,
      sourceDuration: old.sourceDuration,
      sourceStart: newStart,
      sourceEnd: newEnd,
      slotStart: old.slotStart,
      slotEnd: old.slotEnd
    )
    guard new != old else { return }
    clips[index] = new

    // A drag records one entry when it ends, not one per gesture tick.
    if clipTrimOriginal == nil {
      recordAction(.updateClip(old: old, new: new))
    }
    updateClipActionAvailability()
  }

  /// Start a trim drag. Captures the pre-drag clip so the gesture collapses into a
  /// single undo entry.
  func beginClipTrim(id: UUID) {
    clipTrimOriginal = clips.first { $0.id == id }
  }

  func endClipTrim() {
    defer { clipTrimOriginal = nil }
    guard let old = clipTrimOriginal,
          let new = clips.first(where: { $0.id == old.id }),
          new != old
    else { return }
    recordAction(.updateClip(old: old, new: new))
  }

  // MARK: Insert

  /// Where a new video lands: on a clip boundary the playhead sits on, otherwise
  /// right after the clip currently on screen.
  var insertionIndexAtPlayhead: Int {
    let t = CMTimeGetSeconds(currentTime)
    guard let placement = placement(atSequence: t) else { return clips.count }
    return abs(t - placement.start) < 0.01 ? placement.index : placement.index + 1
  }

  /// Insert a video file into the sequence. Defaults to the playhead position, which
  /// is what makes "add a clip between the cuts" work.
  @discardableResult
  func insertClip(url: URL, at index: Int? = nil) async -> UUID? {
    guard !isGIF else { return nil }
    let loaded = AVAsset(url: url)
    do {
      let assetDuration = try await loaded.load(.duration)
      let seconds = CMTimeGetSeconds(assetDuration)
      guard seconds > TimelineClip.minDuration else {
        DiagnosticLogger.shared.log(.warning, .editor, "Inserted clip rejected (too short)", context: [
          "file": url.lastPathComponent,
        ])
        return nil
      }

      clipAssets[url] = loaded
      let clip = TimelineClip(source: .file(url: url), sourceDuration: seconds)
      let target = max(0, min(index ?? insertionIndexAtPlayhead, clips.count))
      clips.insert(clip, at: target)
      recordAction(.addClip(clip: clip, index: target))
      selectedClipId = clip.id

      DiagnosticLogger.shared.log(.info, .editor, "Inserted clip", context: [
        "file": url.lastPathComponent,
        "index": "\(target)",
        "duration": String(format: "%.1fs", seconds),
      ])
      updateClipActionAvailability()
      return clip.id
    } catch {
      DiagnosticLogger.shared.logError(.editor, error, "Failed to load inserted clip duration")
      return nil
    }
  }

  // MARK: Availability

  private func updateClipActionAvailability() {
    guard !isGIF else {
      canSplitAtPlayhead = false
      canDeleteSelectedClip = false
      return
    }

    if let placement = activePlacement {
      let cutPoint = placement.sourceTime(at: CMTimeGetSeconds(currentTime))
      canSplitAtPlayhead = cutPoint - placement.clip.sourceStart >= TimelineClip.minDuration
        && placement.clip.sourceEnd - cutPoint >= TimelineClip.minDuration
    } else {
      canSplitAtPlayhead = false
    }

    canDeleteSelectedClip = clips.count > 1 && targetClip != nil
  }

  /// Currently selected speed segment, if any.
  var selectedSpeedSegment: SpeedSegment? {
    guard let id = selectedSpeedId else { return nil }
    return speedSegments.first { $0.id == id }
  }

  /// Get the active zoom segment at a structural timeline time (enabled segments only).
  func activeZoomSegment(at time: TimeInterval) -> ZoomSegment? {
    ZoomCalculator.activeSegment(at: time, in: zoomSegments)
  }

  /// Get the active zoom segment under a structural timeline time.
  func activeZoomSegment(atTimeline time: TimeInterval) -> ZoomSegment? {
    activeZoomSegment(at: time)
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

  /// Toggle the left background sidebar visibility.
  func toggleLeftSidebar() {
    isLeftSidebarVisible.toggle()
  }

  /// Activate a left rail entry. Tapping the visible panel's icon collapses the
  /// sidebar; tapping another entry expands it with that panel.
  func selectLeftSidebarPanel(_ panel: VideoEditorLeftSidebarPanel) {
    if isLeftSidebarVisible && leftSidebarPanel == panel {
      isLeftSidebarVisible = false
    } else {
      leftSidebarPanel = panel
      isLeftSidebarVisible = true
    }
  }

  // MARK: - Export Settings Methods

  /// Update export settings and recalculate file size
  func updateExportSettings(_ settings: ExportSettings) {
    exportSettings = settings
    syncPlayerAudioWithExportSettings()
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

    // Whole sequence after trim, deletions, and speed scaling.
    let outputSeconds = sequenceMap.outputDuration
    let trimRatio = outputSeconds / sourceDuration

    // Calculate dimension ratio (including background padding)
    let exportSize = exportSettings.exportSize(from: naturalSize)
    let originalPixels = naturalSize.width * naturalSize.height

    // Include background padding in canvas size calculation
    let canvasWidth: CGFloat
    let canvasHeight: CGFloat
    if backgroundStyle != .none, backgroundPadding > 0 {
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
    let audioMultiplier = switch exportSettings.audioMode {
    case .mute: 0.9 // Remove audio portion
    case .keep, .custom: 1.0
    }

    // Primary estimate
    let estimated = Double(sourceSize) * trimRatio * dimensionRatio * qualityMultiplier * audioMultiplier

    return Int64(max(estimated, 1024)) // Minimum 1KB
  }

  // MARK: - Private Methods

  /// Apply a preview rate consistently to AVPlayer's persistent resume rate and its
  /// current transport. `defaultRate` matters whenever AVPlayer starts or resumes
  /// playback through `play()` (including after an item handoff).
  private func applyPreviewRate(_ rate: Float, startPlayback: Bool) {
    let targetRate = rate.isFinite && rate > 0 ? rate : 1.0
    player.defaultRate = targetRate

    if startPlayback || player.rate == 0 {
      player.play()
    } else if abs(player.rate - targetRate) > 0.001 {
      player.rate = targetRate
    }
  }

  private func setupTimeObserver() {
    let interval = CMTime(seconds: 1.0 / 30.0, preferredTimescale: 600)
    timeObserver = player.addPeriodicTimeObserver(
      forInterval: interval,
      queue: .main
    ) { [weak self] time in
      MainActor.assumeIsolated {
        guard let self, !self.playbackState.isScrubbing else { return }
        // A handoff seek is landing; the reported time is still the outgoing
        // clip's coordinates.
        guard !self.handoffSeekInFlight else { return }
        self.handlePlaybackTick(itemTime: CMTimeGetSeconds(time))
      }
    }
  }

  /// Periodic playback tick. `itemTime` is in the ACTIVE source asset's coordinates,
  /// so it has to be folded back onto the sequence axis before it reaches the playhead.
  private func handlePlaybackTick(itemTime: Double) {
    guard let placement = placements.first(where: { $0.clip.id == activeClipId }) else {
      // The sequence changed under us (clip deleted or reordered mid-playback).
      seekPlayerInternally(to: CMTimeGetSeconds(currentTime))
      return
    }

    let clip = placement.clip

    // While a handoff seek is in flight the observer still reports the previous
    // clip's item time, which belongs to the old coordinate range. Acting on it
    // would evaluate the old position against the new clip and could end the
    // sequence prematurely (e.g. after reordering so a clip whose range reaches
    // the asset end plays first).
    guard itemTime >= clip.sourceStart - 0.05, itemTime <= clip.sourceEnd + 0.05 else { return }

    // Reached this clip's out-point — hand off to the next one.
    if itemTime >= clip.sourceEnd - 0.01 {
      advanceToClip(after: placement)
      return
    }

    let sequenceTime = placement.sequenceTime(atSource: itemTime)
    playbackState.setCurrentTime(CMTime(seconds: sequenceTime, preferredTimescale: 600))
    updateClipActionAvailability()

    // Live timelapse preview: keep both the current transport and AVPlayer's resume
    // rate aligned with the speed segment under the playhead.
    if isPlaying {
      let desiredRate = currentPreviewRate(at: CMTime(seconds: sequenceTime, preferredTimescale: 600))
      applyPreviewRate(desiredRate, startPlayback: false)
    }
  }

  /// Continue into the clip after `placement`, or stop and rewind at the end of the
  /// sequence.
  private func advanceToClip(after placement: TimelineSequence.Placement) {
    let nextIndex = placement.index + 1
    guard nextIndex < clips.count else {
      pause()
      seek(to: .zero)
      return
    }

    let next = clips[nextIndex]
    let nextId = next.id
    let nextTime = placements.first(where: { $0.clip.id == nextId })?.activeStart
      ?? CMTimeGetSeconds(currentTime)
    activeClipId = nextId
    activateItemIfNeeded(for: next, previewTime: nextTime)
    // The seek completes asynchronously; until it lands, ticks and end
    // notifications still report the outgoing clip's coordinates.
    handoffSeekInFlight = true
    player.seek(
      to: CMTime(seconds: next.sourceStart, preferredTimescale: 600),
      toleranceBefore: .zero,
      toleranceAfter: .zero
    ) { [weak self] _ in
      Task { @MainActor [weak self] in
        // A newer handoff owns the transport if the active clip moved on again.
        guard let self, activeClipId == nextId else { return }
        handoffSeekInFlight = false
        guard isPlaying else { return }

        // The seek can leave the new item paused even when the old item was playing.
        // Resolve the rate at the next clip's structural start so a speed block that
        // begins at a clip seam is applied before the first frame of that clip.
        applyPreviewRate(
          currentPreviewRate(at: CMTime(seconds: nextTime, preferredTimescale: 600)),
          startPlayback: true
        )
      }
    }
  }

  private static func loadZoomTransitionDuration() -> TimeInterval {
    guard let stored = UserDefaults.standard.object(
      forKey: PreferencesKeys.videoEditorZoomTransitionDuration
    ) as? Double else {
      return ZoomCalculator.defaultTransitionDuration
    }

    return ZoomCalculator.clampTransitionDuration(stored)
  }

  private func setupEndObserver() {
    // Observe every item, not just the one loaded at setup: the player swaps items
    // whenever the sequence crosses into a different source asset.
    endObserver = NotificationCenter.default.addObserver(
      forName: .AVPlayerItemDidPlayToEndTime,
      object: nil,
      queue: .main
    ) { [weak self] notification in
      MainActor.assumeIsolated {
        guard let self else { return }
        // A handoff seek is already repositioning playback — any end notification
        // in this window belongs to the previous clip's play-through.
        guard !self.handoffSeekInFlight else { return }
        guard let item = notification.object as? AVPlayerItem, item === self.player.currentItem else { return }
        // Consecutive clips from one asset share an item, so an end notification
        // can arrive after the playhead already moved into a later clip. Only
        // honor it while the item is genuinely still parked at its end AND the
        // clip on screen is the one whose material reaches that end; otherwise
        // the periodic tick owns the handoff and this notification is stale.
        let itemTime = CMTimeGetSeconds(self.player.currentTime())
        let itemDuration = CMTimeGetSeconds(item.duration)
        guard let placement = self.placements.first(where: { $0.clip.id == self.activeClipId }),
              itemTime >= itemDuration - 0.1,
              placement.clip.sourceEnd >= placement.clip.sourceDuration - 0.05
        else { return }
        self.advanceToClip(after: placement)
      }
    }
  }

  private func setupChangeTracking() {
    // Track trim and mute changes
    $isMuted
      .dropFirst()
      .sink { [weak self] _ in
        self?.updateHasUnsavedChanges()
        self?.recalculateEstimatedFileSize()
      }
      .store(in: &cancellables)

    // Clip sequence changes cover trim, split, delete, reorder, and insert.
    $clips
      .removeDuplicates()
      .dropFirst()
      .sink { [weak self] _ in
        self?.updateHasUnsavedChanges()
        self?.recalculateEstimatedFileSize()
        self?.updateClipActionAvailability()
      }
      .store(in: &cancellables)

    // Track zoom changes - pass segments directly to avoid stale state reads
    $zoomSegments
      .removeDuplicates()
      .sink { [weak self] segments in
        guard let self else { return }
        rebuildAutoFocusPaths(for: segments)
        // Pass segments directly from publisher to avoid timing issues
        updateHasUnsavedChanges(currentZoomSegments: segments)
      }
      .store(in: &cancellables)

    // Track speed (timelapse) segment changes
    $speedSegments
      .removeDuplicates()
      .dropFirst()
      .sink { [weak self] _ in
        self?.updateHasUnsavedChanges()
        self?.recalculateEstimatedFileSize()
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
        self?.updateHasUnsavedChanges()
        self?.recalculateEstimatedFileSize()
      }
      .store(in: &cancellables)
  }

  private func updateHasUnsavedChanges(currentZoomSegments: [ZoomSegment]? = nil) {
    // GIF mode: only track dimension changes
    if isGIF {
      let dimensionChanged = exportSettings.dimensionPreset != initialExportSettings.dimensionPreset
        || exportSettings.customWidth != initialExportSettings.customWidth
        || exportSettings.customHeight != initialExportSettings.customHeight
      hasUnsavedChanges = dimensionChanged
      return
    }

    // Trim now lives inside the clip sequence, so `clipsChanged` covers it.
    let clipsChanged = clips != initialClips
    let muteChanged = isMuted != initialIsMuted
    // Use passed segments if available, otherwise read from self
    let segments = currentZoomSegments ?? zoomSegments
    let zoomsChanged = segments != initialZoomSegments
    let speedsChanged = speedSegments != initialSpeedSegments
    // Background changes
    let bgStyleChanged = backgroundStyle != initialBackgroundStyle
    let bgPaddingChanged = backgroundPadding != initialBackgroundPadding
    let bgShadowChanged = backgroundShadowIntensity != initialBackgroundShadowIntensity
    let bgCornerChanged = backgroundCornerRadius != initialBackgroundCornerRadius
    let backgroundChanged = bgStyleChanged || bgPaddingChanged || bgShadowChanged || bgCornerChanged
    let exportSettingsChanged = exportSettings != initialExportSettings
    hasUnsavedChanges = clipsChanged || muteChanged || zoomsChanged || speedsChanged
      || backgroundChanged || exportSettingsChanged
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
    DiagnosticLogger.shared.log(.debug, .editor, "Background style changed", context: ["style": "\(backgroundStyle)"])
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
        guard let self else { return }
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

    if let restoredSessionData {
      recordingMetadata = restoredSessionData.recordingMetadata
    } else {
      recordingMetadata = Self.loadRecordingMetadata(for: sourceURL, originalURL: originalURL)
    }

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

      let builtPath = VideoEditorAutoFocusEngine.buildPath(
        from: recordingMetadata,
        segment: segment
      )
      rebuiltPaths[segment.id] = builtPath

      let metrics = VideoEditorAutoFocusEngine.evaluatePathQuality(
        metadata: recordingMetadata,
        segment: segment,
        path: builtPath
      )
      DiagnosticLogger.shared.log(.debug, .editor, "Auto-focus path rebuilt", context: [
        "segmentId": segment.id.uuidString,
        "sampleCount": "\(metrics.sampleCount)",
        "lockAccuracy": String(format: "%.3f", metrics.lockAccuracy),
        "visibilityRate": String(format: "%.3f", metrics.visibilityRate),
        "meanError": String(format: "%.4f", metrics.meanError),
      ])
    }

    autoFocusPathInputs = rebuiltInputs
    autoFocusPaths = rebuiltPaths
  }

  /// Apply Gaussian blur to image (computed once, reused during render)
  private func applyGaussianBlur(to image: NSImage?, radius: CGFloat) -> NSImage? {
    guard let image,
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
