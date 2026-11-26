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
  case text
  case cursor
  case camera
  case captions
}

/// AVPlayer callbacks and schedule access are serialized on `queue`. Observer
/// registration and removal happen on the owning editor actor.
private final nonisolated class VideoEditorPreviewRateController: @unchecked Sendable {
  struct Span: Sendable {
    let start: TimeInterval
    let end: TimeInterval
    let rate: Float
  }

  private let player: AVPlayer
  private let queue = DispatchQueue(label: "com.snapzy.video-editor.preview-rate", qos: .userInitiated)
  private var spans: [Span] = []
  private var item: AVPlayerItem?
  private var enabled = false
  private var wantsPlayback = false
  private var generation = 0
  private var boundaryObserver: Any?
  private var periodicObserver: Any?
  private var seekLandingTimer: DispatchSourceTimer?
  private var pendingSeekTarget: TimeInterval?
  private var seekLandingReady = false
  private var seekLandingDeadline: TimeInterval = 0
  /// A seek whose completion never fires (a zero-tolerance request AVPlayer cannot
  /// satisfy, e.g. the exact media start of a recording with non-zero first-frame
  /// PTS) must not block the Play intent forever. The gate force-opens after this.
  private static let seekLandingTimeout: TimeInterval = 2.0

  init(player: AVPlayer) {
    self.player = player
  }

  @discardableResult
  func configure(spans: [Span], item: AVPlayerItem?, enabled: Bool, wantsPlayback: Bool) -> Int {
    let currentGeneration = queue.sync {
      generation += 1
      self.spans = spans
      self.item = item
      self.enabled = enabled
      self.wantsPlayback = wantsPlayback
      self.seekLandingTimer?.cancel()
      self.seekLandingTimer = nil
      self.pendingSeekTarget = nil
      self.seekLandingReady = false
      self.seekLandingDeadline = 0
      return generation
    }
    removeObservers()

    if item != nil, spans.contains(where: { abs($0.rate - 1) > 0.001 }) {
      let boundaries = zip(spans, spans.dropFirst()).compactMap { previous, next -> NSValue? in
        guard abs(previous.rate - next.rate) > 0.001 else { return nil }
        return NSValue(time: CMTime(seconds: next.start, preferredTimescale: 600))
      }
      if !boundaries.isEmpty {
        boundaryObserver = player.addBoundaryTimeObserver(
          forTimes: boundaries,
          queue: queue
        ) { [weak self] in
          self?.reconcile(expectedGeneration: currentGeneration)
        }
      }

      // AVPlayer may omit an individual boundary callback. The separate
      // periodic observer reads the current item position as a fallback.
      periodicObserver = player.addPeriodicTimeObserver(
        forInterval: CMTime(seconds: 0.1, preferredTimescale: 600),
        queue: queue
      ) { [weak self] _ in
        self?.reconcile(expectedGeneration: currentGeneration)
      }
    }

    queue.async { [weak self] in
      self?.reconcile(expectedGeneration: currentGeneration)
    }
    return currentGeneration
  }

  func setEnabled(_ enabled: Bool) {
    let currentGeneration = queue.sync {
      self.enabled = enabled
      return generation
    }
    if enabled {
      queue.async { [weak self] in
        self?.reconcile(expectedGeneration: currentGeneration)
      }
    }
  }

  func setPlaybackIntent(_ wantsPlayback: Bool) {
    let currentGeneration = queue.sync {
      self.wantsPlayback = wantsPlayback
      if !wantsPlayback {
        enabled = false
      }
      return generation
    }
    if wantsPlayback {
      queue.async { [weak self] in
        guard let self, generation == currentGeneration, seekLandingReady else { return }
        startPlaybackAtCurrentTime()
      }
    }
  }

  /// Keep the old item parked while a seek is in flight. AVPlayer can land a seek
  /// before its completion is delivered on the busy main queue, so check the
  /// actual item position on our own serial queue as well.
  func awaitSeekLanding(at sourceTime: TimeInterval, ifGeneration expectedGeneration: Int) {
    queue.sync {
      guard generation == expectedGeneration else { return }
      pendingSeekTarget = sourceTime
      seekLandingReady = false
      seekLandingDeadline = ProcessInfo.processInfo.systemUptime + Self.seekLandingTimeout
      seekLandingTimer?.cancel()
      let timer = DispatchSource.makeTimerSource(queue: queue)
      timer.schedule(deadline: .now() + .milliseconds(5), repeating: .milliseconds(5))
      timer.setEventHandler { [weak self] in
        self?.checkSeekLanding(expectedGeneration: expectedGeneration)
      }
      seekLandingTimer = timer
      timer.resume()
    }
  }

  /// A newer seek changes the generation; Pause clears intent.
  func resumeAfterSeek(ifGeneration expectedGeneration: Int) {
    queue.async { [weak self] in
      guard let self, generation == expectedGeneration else { return }
      finishSeekLanding()
    }
  }

  func invalidate() {
    queue.sync {
      generation += 1
      enabled = false
      wantsPlayback = false
      seekLandingTimer?.cancel()
      seekLandingTimer = nil
      pendingSeekTarget = nil
      seekLandingReady = false
      seekLandingDeadline = 0
    }
    removeObservers()
  }

  private func removeObservers() {
    if let boundaryObserver {
      player.removeTimeObserver(boundaryObserver)
      self.boundaryObserver = nil
    }
    if let periodicObserver {
      player.removeTimeObserver(periodicObserver)
      self.periodicObserver = nil
    }
  }

  private func checkSeekLanding(expectedGeneration: Int) {
    guard generation == expectedGeneration,
          let pendingSeekTarget,
          let item,
          player.currentItem === item
    else { return }
    let time = player.currentTime()
    guard time.isNumeric else { return }
    // The seek completion may never fire for an unsatisfiable request; open the
    // gate after the timeout so the Play intent cannot hang.
    if ProcessInfo.processInfo.systemUptime >= seekLandingDeadline {
      finishSeekLanding()
      return
    }
    guard abs(CMTimeGetSeconds(time) - pendingSeekTarget) <= 0.05
    else { return }
    finishSeekLanding()
  }

  private func finishSeekLanding() {
    seekLandingTimer?.cancel()
    seekLandingTimer = nil
    pendingSeekTarget = nil
    seekLandingReady = true
    if wantsPlayback {
      startPlaybackAtCurrentTime()
    }
  }

  private func startPlaybackAtCurrentTime() {
    guard let item, player.currentItem === item else { return }
    let time = player.currentTime()
    guard time.isNumeric else { return }
    enabled = true
    let sourceTime = CMTimeGetSeconds(time)
    let targetRate = spans.first(where: {
      sourceTime >= $0.start && sourceTime < $0.end
    })?.rate ?? 1
    player.defaultRate = targetRate
    if player.rate == 0 {
      player.play()
    } else if abs(player.rate - targetRate) > 0.001 {
      player.rate = targetRate
    }
  }

  private func reconcile(expectedGeneration: Int) {
    guard generation == expectedGeneration,
          enabled,
          let item,
          player.currentItem === item
    else { return }
    let time = player.currentTime()
    guard time.isNumeric else { return }
    let sourceTime = CMTimeGetSeconds(time)
    let targetRate = spans.first(where: { sourceTime >= $0.start && sourceTime < $0.end })?.rate ?? 1
    if abs(player.defaultRate - targetRate) > 0.001 {
      player.defaultRate = targetRate
    }
    // A zero rate may be a user pause or AVPlayer waiting for media. This
    // observer changes speed only while the transport is already moving.
    if player.rate > 0, abs(player.rate - targetRate) > 0.001 {
      player.rate = targetRate
    }
  }
}

// MARK: - Editor Action (Undo/Redo Support)

/// Represents an undoable editor action
enum EditorAction: Equatable {
  case trimStart(old: CMTime, new: CMTime)
  case trimEnd(old: CMTime, new: CMTime)
  case addZoom(segment: ZoomSegment)
  case removeZoom(segment: ZoomSegment)
  case updateZoom(old: ZoomSegment, new: ZoomSegment)
  case replaceZooms(
    old: [ZoomSegment],
    new: [ZoomSegment],
    oldMotionBlur: VideoEditorMotionBlurSettings? = nil,
    newMotionBlur: VideoEditorMotionBlurSettings? = nil
  )
  case updateMotionBlur(old: VideoEditorMotionBlurSettings, new: VideoEditorMotionBlurSettings)
  case updateZoomTransitionDuration(old: TimeInterval, new: TimeInterval)
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
  case replaceAudioClips(old: [AudioTimelineClip], new: [AudioTimelineClip])
  case updateMutedAudioLanes(old: Set<Int>, new: Set<Int>)
  case replaceTextOverlays(old: [VideoEditorTextOverlay], new: [VideoEditorTextOverlay])
  case replaceSpeeds(old: [SpeedSegment], new: [SpeedSegment])
  case replaceTimelineBookmarks(old: [TimeInterval], new: [TimeInterval])
  case moveClip(id: UUID, fromIndex: Int, toIndex: Int)
  case splitClip(original: TimelineClip, index: Int, first: TimelineClip, second: TimelineClip)
  /// Whole-sequence swap, for edits that reshape several clips at once (agent `cut_range`).
  case replaceClips(old: [TimelineClip], new: [TimelineClip])
  case updateFrame(old: VideoEditorFrameSettings, new: VideoEditorFrameSettings)
  case updateExportSettings(old: ExportSettings, new: ExportSettings)
  case updateCursor(old: VideoEditorCursorSettings, new: VideoEditorCursorSettings)
  case updateCamera(old: VideoEditorCameraSettings, new: VideoEditorCameraSettings)
  case updateCaptions(old: VideoEditorCaptions, new: VideoEditorCaptions)
  /// Several actions that undo and redo as one step (one AI prompt).
  case group([EditorAction])
}

/// Everything the background/frame panel changes, as one undoable value.
struct VideoEditorFrameSettings: Equatable {
  var style: BackgroundStyle
  var padding: CGFloat
  var shadowIntensity: CGFloat
  var cornerRadius: CGFloat
  var alignment: ImageAlignment
  var aspectRatio: AspectRatioOption
}

/// Playback state changes frequently, so it stays isolated from the broader editor model.
@MainActor
final class VideoEditorPlaybackState: ObservableObject {
  /// Explicit and nonisolated: the synthesized main-actor deinit hops through the
  /// back-deployed swift_task_deinitOnExecutor, which aborts on macOS 13-15 (#668).
  nonisolated deinit {}

  @Published private(set) var currentTime: CMTime = .zero
  @Published private(set) var isPlaying: Bool = false
  @Published private(set) var isScrubbing: Bool = false
  /// Active J/K/L shuttle rate (`-4, -2, -1, 0, 1, 2, 4`). Isolated here so HUD pills
  /// update without re-rendering the entire editor.
  @Published private(set) var shuttleRate: Float = 0

  var formattedCurrentTime: String {
    Self.formatTime(currentTime)
  }

  func setCurrentTime(_ time: CMTime) {
    guard CMTimeCompare(currentTime, time) != 0 else { return }
    currentTime = time
  }

  func setPlaying(_ value: Bool) {
    if !value, abs(shuttleRate) > 0.001 {
      shuttleRate = 0
    }
    guard isPlaying != value else { return }
    isPlaying = value
  }

  func setScrubbing(_ value: Bool) {
    guard isScrubbing != value else { return }
    isScrubbing = value
  }

  func setShuttleRate(_ value: Float) {
    guard abs(shuttleRate - value) > 0.001 else { return }
    shuttleRate = value
  }

  nonisolated static func formatTime(_ time: CMTime) -> String {
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
    let smartKeyframes: [AutoFocusCameraSample]?

    init(segment: ZoomSegment) {
      zoomType = segment.zoomType
      zoomLevel = segment.zoomLevel
      followSpeed = segment.followSpeed
      focusMargin = segment.focusMargin
      smartKeyframes = segment.smartKeyframes
    }
  }

  private struct FrameExtractionProfile {
    let frameCount: Int
    let tolerance: CMTime
    let strategyLabel: String
  }

  // MARK: - Video Source

  private(set) var sourceURL: URL {
    didSet {
      guard sourceURL != oldValue else { return }
      sourceSizeTask?.cancel()
      sourceSizeTask = nil
      cachedSourceFileSize = nil
      recalculateEstimatedFileSize()
    }
  }

  /// Original file URL to replace (used for "Replace Original" functionality)
  private(set) var originalURL: URL
  private(set) var assetURL: URL
  /// The source used to render the current authoring recipe. For a restored
  /// session this is the private master snapshot, not the already-rendered file.
  var editingSourceURL: URL {
    assetURL
  }

  private(set) var asset: AVAsset
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
      if isGIF {
        return gifTrimStart
      }
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
      if isGIF {
        return gifTrimEnd
      }
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
    didSet {
      guard speedSegments != oldValue else { return }
      cachedSequenceMap = nil
      scheduleSpeedPreviewRebuild()
      updateHasUnsavedChanges()
      recalculateEstimatedFileSize()
    }
  }

  @Published var selectedSpeedId: UUID? = nil

  // MARK: - Timeline Clips (the sequence)

  /// The ordered sequence of clips — the single source of truth for the timeline.
  ///
  /// Seeded with one primary clip spanning the whole asset. Splitting divides a clip,
  /// deleting ripples the rest left, and an inserted video is just another element.
  @Published private(set) var clips: [TimelineClip] = [] {
    didSet {
      guard clips != oldValue else { return }
      invalidateTimelineCaches()
      scheduleSpeedPreviewRebuild()
      updateHasUnsavedChanges()
      updateClipActionAvailability()
    }
  }

  @Published private(set) var selectedClipId: UUID? = nil
  @Published private(set) var canSplitAtPlayhead: Bool = false
  @Published private(set) var canDeleteSelectedClip: Bool = false
  @Published private(set) var canTrimLeftAtPlayhead: Bool = false
  @Published private(set) var canTrimRightAtPlayhead: Bool = false
  @Published private(set) var hasBookmarkAtPlayhead: Bool = false

  /// Frame strips for inserted clips. The primary recording's strip lives in
  /// `frameThumbnails`; this covers every other asset on the timeline.
  let clipThumbnailCache = VideoEditorClipThumbnailCache()

  /// Downsampled audio peak waveforms for primary and inserted clips on the timeline.
  let audioWaveformCache = VideoEditorAudioWaveformCache()

  /// Independent audio clips on the Multi-Track Audio timeline lanes (primary recording + imported/detached audio).
  @Published var audioClips: [AudioTimelineClip] = [] {
    didSet {
      cachedTimelineDuration = nil
    }
  }

  @Published var selectedAudioClipId: UUID? = nil
  /// Multi-select set for Audio clips (populated by `⌘A` on Audio track).
  @Published var selectedAudioClipIds: Set<UUID> = []
  /// Minimum visible audio track lanes (starts at 1; grows automatically when overlapping
  /// audio clips are placed or when the user adds a new audio lane).
  @Published var minimumAudioLanes: Int = 1
  /// Per-lane mute switches (zero-based lane indices: `0 = A1`, `1 = A2`, ...).
  @Published var mutedAudioLanes: Set<Int> = []

  /// Timeline text / title overlays rendered in live preview and composited into export.
  @Published var textOverlays: [VideoEditorTextOverlay] = [] {
    didSet {
      guard textOverlays != oldValue else { return }
      updateHasUnsavedChanges()
    }
  }

  @Published var selectedTextOverlayId: UUID? = nil
  /// Multi-select set for Text overlays (populated by `⌘A` on Text track).
  @Published var selectedTextOverlayIds: Set<UUID> = []
  /// Minimum visible text track lanes (`1 = T1`, grows with `+` or overlapping text overlays).
  @Published var minimumTextLanes: Int = 1
  /// Active caption selection on the Captions track (synced with `⌘A` + `Delete`).
  @Published var selectedCaptionId: UUID? = nil
  @Published var selectedCaptionIds: Set<UUID> = []
  /// True while any text/caption field has keyboard focus, suppressing plain-key
  /// timeline shortcuts (`S`, `J/K/L`, `T`, `M`, `N`, `,`, `.`, `Delete`).
  /// Backed by `activeTextEditorTokens` so direct focus transitions between two
  /// text fields never race and clear the flag prematurely.
  @Published var isEditingTextOverlayField: Bool = false
  private var activeTextEditorTokens: Set<String> = []

  func beginTextFieldEditing(token: String) {
    activeTextEditorTokens.insert(token)
    if !isEditingTextOverlayField {
      isEditingTextOverlayField = true
    }
  }

  func endTextFieldEditing(token: String) {
    activeTextEditorTokens.remove(token)
    let shouldBeEditing = !activeTextEditorTokens.isEmpty
    if isEditingTextOverlayField != shouldBeEditing {
      isEditingTextOverlayField = shouldBeEditing
    }
  }

  var textLaneCount: Int {
    TextTimelineLaneLayout.laneCount(for: textOverlays, minimumLanes: minimumTextLanes)
  }

  /// Nominal video frame rate used for `,` / `.` single-frame stepping.
  private(set) var nominalFrameRate: Double = 30.0

  /// timeline bookmarks / markers along the ruler.
  @Published var timelineBookmarks: [TimeInterval] = []

  /// User-togglable magnetic snapping preference (Option key still bypasses temporarily).
  @Published var isSnappingEnabled: Bool = true

  /// Companion live-preview player for imported external `.file` audio clips.
  let addedAudioPlayer = VideoEditorAddedAudioPlayer()
  var audioTailPlaybackTimer: Timer?
  var reverseShuttleTimer: Timer?
  var reverseShuttleLastTick: TimeInterval = 0

  /// Audio-bearing URL backing `clip` for waveform extraction.
  func waveformSourceURL(for clip: TimelineClip) -> URL {
    switch clip.source {
    case .primary:
      Self.editorAssetURL(for: sourceURL, metadata: recordingMetadata)
    case .file(let url):
      url
    }
  }

  /// Dedicated snap-guide state updated during timeline drag gestures without triggering
  /// `VideoEditorState.objectWillChange`.
  let timelineSnapGuide = VideoEditorTimelineSnapGuideState()

  /// Collect magnetic snap targets along the structural timeline axis.
  func timelineSnapCandidates(
    excludingZoomId: UUID? = nil,
    excludingSpeedId: UUID? = nil,
    excludingClipId: UUID? = nil,
    excludingTextOverlayId: UUID? = nil
  ) -> [VideoEditorTimelineSnapper.SnapTarget] {
    var targets: [VideoEditorTimelineSnapper.SnapTarget] = []
    let totalDuration = CMTimeGetSeconds(timelineDuration)
    guard totalDuration > 0 else { return targets }

    targets.append(.init(time: 0, kind: .timelineBoundary))
    targets.append(.init(time: totalDuration, kind: .timelineBoundary))

    let playheadSeconds = CMTimeGetSeconds(currentTime)
    if playheadSeconds.isFinite, playheadSeconds >= 0, playheadSeconds <= totalDuration {
      targets.append(.init(time: playheadSeconds, kind: .playhead))
    }

    for placement in placements where placement.clip.id != excludingClipId {
      targets.append(.init(time: placement.activeStart, kind: .clipBoundary))
      targets.append(.init(time: placement.activeEnd, kind: .clipBoundary))
    }

    for segment in zoomSegments where segment.id != excludingZoomId {
      targets.append(.init(time: segment.startTime, kind: .zoomEdge))
      targets.append(.init(time: segment.endTime, kind: .zoomEdge))
    }

    for segment in speedSegments where segment.id != excludingSpeedId {
      targets.append(.init(time: segment.startTime, kind: .speedEdge))
      targets.append(.init(time: segment.endTime, kind: .speedEdge))
    }

    for caption in captions.segments {
      targets.append(.init(time: caption.start, kind: .captionEdge))
      targets.append(.init(time: caption.end, kind: .captionEdge))
    }

    for hidden in cameraSettings.hiddenRanges {
      targets.append(.init(time: hidden.start, kind: .cameraEdge))
      targets.append(.init(time: hidden.end, kind: .cameraEdge))
    }

    for audioClip in audioClips where audioClip.id != excludingClipId {
      targets.append(.init(time: audioClip.timelineStart, kind: .clipBoundary))
      targets.append(.init(time: audioClip.timelineEnd, kind: .clipBoundary))
    }

    for overlay in textOverlays where overlay.id != excludingTextOverlayId {
      targets.append(.init(time: overlay.startTime, kind: .textEdge))
      targets.append(.init(time: overlay.endTime, kind: .textEdge))
    }

    for bookmark in timelineBookmarks {
      targets.append(.init(time: bookmark, kind: .playhead))
    }

    return targets
  }

  private var cachedPlacements: [TimelineSequence.Placement]?
  private var cachedPlacementLookup: [UUID: TimelineSequence.Placement]?
  private var cachedSequenceMap: TimelineSequenceMap?
  private var cachedPlaybackPlacements: [TimelineSequence.Placement]?
  private var cachedSequenceDuration: TimeInterval?
  private var cachedTimelineDuration: CMTime?
  private var mappedAutoFocusPaths: [UUID: [AutoFocusCameraSample]] = [:]
  private var timelineLayoutRevision: UInt64 = 0
  private var mappedAutoFocusBuildTask: Task<Void, Never>?
  @Published private(set) var autoFocusPathRevision: UInt64 = 0
  /// Assets backing `.file` clips, keyed by URL so duplicated clips share one asset.
  private var clipAssets: [URL: AVAsset] = [:]

  private func invalidateTimelineCaches() {
    cachedPlacements = nil
    cachedPlacementLookup = nil
    cachedPlaybackPlacements = nil
    cachedSequenceDuration = nil
    cachedTimelineDuration = nil
    cachedSequenceMap = nil
    timelineLayoutRevision &+= 1
    scheduleMappedAutoFocusPaths()
    recalculateEstimatedFileSize()
  }

  /// Clips laid out on the structural timeline axis. Trimmed-out footage remains
  /// inside its owning placement and is marked inactive by the clip strip.
  var placements: [TimelineSequence.Placement] {
    if let cached = cachedPlacements {
      return cached
    }
    let laid = TimelineSequence.layout(clips)
    cachedPlacements = laid
    return laid
  }

  private func placementForClip(_ id: UUID?) -> TimelineSequence.Placement? {
    guard let id else { return nil }
    if cachedPlacementLookup == nil {
      cachedPlacementLookup = Dictionary(
        placements.map { ($0.clip.id, $0) },
        uniquingKeysWith: { first, _ in first }
      )
    }
    return cachedPlacementLookup?[id]
  }

  /// Clips laid out on the playable/export axis, with inactive trim slots collapsed.
  var playbackPlacements: [TimelineSequence.Placement] {
    if let cachedPlaybackPlacements {
      return cachedPlaybackPlacements
    }
    let result = TimelineSequence.playableLayout(clips)
    cachedPlaybackPlacements = result
    return result
  }

  /// Length of the playable/export sequence.
  var sequenceDuration: TimeInterval {
    if let cachedSequenceDuration {
      return cachedSequenceDuration
    }
    let result = TimelineSequence.playableDuration(clips)
    cachedSequenceDuration = result
    return result
  }

  /// Sequence → output map (speed applied). Cached.
  var sequenceMap: TimelineSequenceMap {
    if let cached = cachedSequenceMap {
      return cached
    }
    let map = TimelineSequenceMap(clips: clips, speedSegments: speedSegments)
    cachedSequenceMap = map
    return map
  }

  /// Latest end timestamp across all independent audio clips.
  var maxAudioTimelineEnd: TimeInterval {
    audioClips.map(\.timelineEnd).max() ?? 0
  }

  /// True when any video clip has an explicit leading black-screen gap before it.
  var hasVideoGaps: Bool {
    clips.contains { $0.leadingGap > 0.01 }
  }

  /// Latest active video timestamp on the structural timeline axis.
  var lastActiveVideoEnd: TimeInterval {
    placements.last(where: { $0.activeEnd > $0.activeStart })?.activeEnd ?? 0
  }

  /// Effective end of playable content across active video clips and independent audio clips.
  var effectiveTimelinePlaybackEnd: TimeInterval {
    max(lastActiveVideoEnd, maxAudioTimelineEnd)
  }

  /// True when a timeline time outside active video clips is a genuine black-screen gap
  /// (explicit clip gap, trailing audio past video, or independent audio playing over that gap).
  /// Classic single-clip trim with no audio and no gaps continues to snap to active in/out points.
  func allowsGapPlayhead(at seconds: TimeInterval) -> Bool {
    guard !isGIF, seconds.isFinite, seconds >= 0 else { return false }
    let limit = effectiveTimelinePlaybackEnd
    guard seconds <= limit + 0.0001 else { return false }
    if hasVideoGaps {
      return true
    }
    if maxAudioTimelineEnd > lastActiveVideoEnd + 0.05, seconds > lastActiveVideoEnd {
      return true
    }
    return audioClips.contains { !$0.isMuted && $0.contains(timelineTime: seconds) }
  }

  /// True when the playhead sits in a black-screen gap (before/between clips or audio continuing past video).
  var isPlayheadInVideoGap: Bool {
    isInVideoGap(at: CMTimeGetSeconds(playbackState.currentTime))
  }

  /// Evaluates black-screen gap state at an explicit timestamp (safe inside `@Published` `willSet` callbacks).
  func isInVideoGap(at seconds: TimeInterval) -> Bool {
    guard !isGIF, !placements.isEmpty, seconds.isFinite else { return false }
    return TimelineSequence.activePlacement(at: seconds, in: placements) == nil
  }

  /// Structural timeline axis length. Extends automatically when audio clips run past video.
  var timelineDuration: CMTime {
    if isGIF {
      return duration
    }
    if let cachedTimelineDuration {
      return cachedTimelineDuration
    }
    let totalSeconds = max(TimelineSequence.duration(clips), maxAudioTimelineEnd)
    let result = CMTime(seconds: totalSeconds, preferredTimescale: 600)
    cachedTimelineDuration = result
    return result
  }

  var formattedTimelineDuration: String {
    formatTime(timelineDuration)
  }

  /// True when any clip seam has an active transition (Crossfade / Dip to Black).
  var hasActiveTransitions: Bool {
    clips.dropFirst().contains { $0.leadingTransition?.isActive == true }
  }

  /// True when any clip has its embedded audio detached onto an independent lane.
  var hasDetachedAudioClips: Bool {
    clips.contains(where: \.isAudioDetached)
  }

  /// True once the user has split, deleted, reordered, repositioned with gaps, detached audio,
  /// added transitions, or inserted anything — i.e. the sequence needs composition export.
  var hasSequenceEdits: Bool {
    clips.count > 1 || clips.contains { !$0.isPrimary } || hasVideoGaps || hasActiveTransitions || hasDetachedAudioClips
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
    placementForClip(id)?.start
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
    if isGIF {
      return trimmedDuration
    }
    return CMTime(seconds: sequenceMap.outputDuration, preferredTimescale: 600)
  }

  // MARK: - Audio Control

  private var isSyncingAudioMute: Bool = false

  @Published var isMuted: Bool = false {
    didSet {
      guard !isSyncingAudioMute else { return }
      player.isMuted = shouldMutePreviewPlayer
      syncAddedAudioPlayer()
    }
  }

  private var initialIsMuted: Bool = false

  /// Whether `AVPlayer` itself should be muted at the current active clip/playhead.
  /// Non-detached external `.file` clips play their embedded audio through `AVPlayer`
  /// even when primary or other clips use independent audio lanes.
  var shouldMutePreviewPlayer: Bool {
    if isMuted || exportSettings.audioMode == .mute || playbackState.shuttleRate < 0 {
      return true
    }
    let playheadSeconds = CMTimeGetSeconds(playbackState.currentTime)
    let activeClip: TimelineClip? = TimelineSequence.activePlacement(
      at: playheadSeconds,
      in: placements
    )?.clip ?? placementForClip(activeClipId)?.clip
    if let activeClip {
      if activeClip.isAudioDetached {
        return true
      }
      if !activeClip.isPrimary {
        return false
      }
    }
    return usesIndependentAudioPlayback || isPlayheadInVideoGap
  }

  /// Sync player preview audio with export audio mode and custom volume settings.
  func syncPlayerAudioWithExportSettings() {
    syncAddedAudioPlayer()
    let hasExternalAudio = audioClips.contains { !$0.isPrimary }
    let hasAttachedInsertedClips = clips.contains { !$0.isPrimary && !$0.isAudioDetached }
    if !usesIndependentAudioPlayback,
       !hasExternalAudio,
       !hasAttachedInsertedClips,
       exportSettings.audioMode == .mute,
       !isMuted {
      isSyncingAudioMute = true
      isMuted = true
      isSyncingAudioMute = false
    }
    player.isMuted = shouldMutePreviewPlayer

    guard exportSettings.requiresAudioMix else {
      player.volume = 1.0
      player.currentItem?.audioMix = nil
      return
    }

    player.volume = 1.0
    let settingsSnapshot = exportSettings
    let rolesSnapshot: [VideoEditorAudioTrackRole] = activeItemSource == .primary ? audioTrackRoles : []
    let itemSnapshot = player.currentItem
    let assetSnapshot = itemSnapshot?.asset ?? asset
    Task { @MainActor [weak self] in
      do {
        let audioTracks = try await assetSnapshot.loadTracks(withMediaType: .audio)
        let assetDuration = try await assetSnapshot.load(.duration)
        guard let self,
              player.currentItem === itemSnapshot,
              exportSettings == settingsSnapshot,
              exportSettings.requiresAudioMix
        else { return }

        let audioRange = CMTimeRange(start: .zero, duration: assetDuration)
        player.currentItem?.audioMix = VideoEditorAudioMixFactory.makeAudioMix(
          for: audioTracks,
          settings: settingsSnapshot,
          roles: rolesSnapshot,
          audioTimeRange: audioRange
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

  @Published var zoomSegments: [ZoomSegment] = [] {
    didSet {
      guard zoomSegments != oldValue else { return }
      rebuildAutoFocusPaths(for: zoomSegments)
      updateHasUnsavedChanges()
    }
  }

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
      updateHasUnsavedChanges()
    }
  }
  private var initialZoomTransitionDuration: TimeInterval = ZoomCalculator.defaultTransitionDuration
  private var pendingFrameEditStart: VideoEditorFrameSettings?

  // MARK: - Auto Focus

  @Published private(set) var recordingMetadata: RecordingMetadata? {
    didSet { reloadCursorLayer() }
  }

  /// Studio cursor layer settings (only meaningful when `hasEditableCursor`).
  @Published private(set) var cursorSettings = VideoEditorCursorSettings.default
  private(set) var initialCursorSettings = VideoEditorCursorSettings.default
  /// Camera + cursor motion blur settings (opt-in inside the video editor preview/export).
  @Published private(set) var motionBlurSettings = VideoEditorMotionBlurSettings.disabled
  private(set) var initialMotionBlurSettings = VideoEditorMotionBlurSettings.disabled
  /// Smart Auto-Zoom generation style, confirmation state, notice & in-flight task.
  @Published var smartAutoZoomStyle: SmartAutoZoomStyle = .balanced
  @Published private(set) var isGeneratingSmartAutoZoom: Bool = false
  @Published var showSmartAutoZoomConfirmation: Bool = false
  @Published private(set) var smartAutoZoomNotice: String?
  private(set) var pendingSmartAutoZoomStyle: SmartAutoZoomStyle?
  private var smartAutoZoomTask: Task<Void, Never>?
  private var smartAutoZoomNoticeTask: Task<Void, Never>?

  /// True when the timeline contains any user-authored zoom (manual or regular auto zoom).
  var hasUserZoomSegments: Bool {
    zoomSegments.contains { !$0.isSmartAutoZoom }
  }

  /// Captured cursor images, loaded once per metadata.
  private(set) var cursorSprites = VideoEditorCursorSpriteStore.empty
  /// Resolver for the current metadata + settings; `nil` without an editable cursor.
  private(set) var cursorResolver: VideoEditorCursorResolver?
  /// Studio camera layer settings (only meaningful when `hasEditableCamera`).
  @Published private(set) var cameraSettings = VideoEditorCameraSettings.default
  private(set) var initialCameraSettings = VideoEditorCameraSettings.default
  private var didSeedCameraSettings = false
  /// Camera sidecar movie of a Studio recording, when present on disk.
  private(set) var cameraSourceURL: URL?
  /// Second, muted player on the camera sidecar for the preview.
  private(set) var cameraPreview: VideoEditorCameraPreviewController?
  /// Captions (segments in source time + style); see `VideoEditorState+Captions`.
  @Published internal(set) var captions = VideoEditorCaptions.empty {
    didSet { cachedCaptionResolver = nil }
  }

  /// Preview caption lookup, rebuilt only when `captions` changes (not per tick).
  var cachedCaptionResolver: VideoEditorCaptionResolver?
  internal(set) var initialCaptions = VideoEditorCaptions.empty
  /// Caption generation in flight (transcription), cancellable from the progress overlay.
  internal(set) var captionTask: Task<Void, Never>?
  /// Last caption generation problem or partial result, shown in the captions panel.
  @Published internal(set) var captionNotice: String?
  /// Live Studio click sound for the preview (engine starts only when used).
  let clickSoundPlayer = VideoEditorClickSoundPlayer()
  @Published private(set) var autoFocusPaths: [UUID: [AutoFocusCameraSample]] = [:]

  // MARK: - GIF Metadata

  @Published private(set) var gifFrameCount: Int = 0
  @Published private(set) var gifDuration: Double = 0

  // MARK: - Background Settings

  @Published var backgroundStyle: BackgroundStyle = .none {
    didSet {
      // Re-picking the current wallpaper reloaded and re-blurred it. Still retry when the
      // last load produced nothing.
      if backgroundStyle == oldValue, loadingBackgroundURL != nil || hasCachedBackgroundForStyle {
        return
      }
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

  /// Runs caption translations for the agent (`VideoEditorCaptionTranslationHost` in the window).
  let captionTranslator = VideoEditorCaptionTranslator()

  /// The AI prompt of this editor window, created on first use.
  private(set) var agentIfLoaded: VideoEditorAgentController?
  var agent: VideoEditorAgentController {
    if let agentIfLoaded {
      return agentIfLoaded
    }
    let agent = VideoEditorAgentController(state: self)
    agentIfLoaded = agent
    return agent
  }

  private var initialZoomSegments: [ZoomSegment] = []
  private var initialSpeedSegments: [SpeedSegment] = []
  private var initialClips: [TimelineClip] = []
  private var initialAudioClips: [AudioTimelineClip] = []
  private var initialMutedAudioLanes: Set<Int> = []
  private var initialTimelineBookmarks: [TimeInterval] = []
  private var initialTextOverlays: [VideoEditorTextOverlay] = []
  private var initialBackgroundStyle: BackgroundStyle = .none
  private var initialBackgroundPadding: CGFloat = 0
  private var initialBackgroundShadowIntensity: CGFloat = 0
  private var initialBackgroundCornerRadius: CGFloat = 0
  private var initialBackgroundAlignment: ImageAlignment = .center
  private var initialBackgroundAspectRatio: AspectRatioOption = .auto
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
  /// Open `beginUndoGroup` calls; while > 0 recorded actions collect in the buffer.
  private var undoGroupDepth = 0
  private var undoGroupBuffer: [EditorAction] = []

  // MARK: - Rename State

  @Published var isRenamingFile: Bool = false

  // MARK: - Private

  private var timeObserver: Any?
  private var timeObserverGeneration = 0
  private var lastTimeObserverUpdate: TimeInterval = 0
  private var previewRateController: VideoEditorPreviewRateController?
  private var endObserver: NSObjectProtocol?
  private var cancellables = Set<AnyCancellable>()
  private var autoFocusPathInputs: [UUID: AutoFocusPathInput] = [:]
  private let autoFocusWorker = VideoEditorAutoFocusWorker()
  private var autoFocusBuildTask: Task<Void, Never>?
  private var autoFocusRequestRevision: UInt64 = 0
  private var metadataRevision = UUID()
  private var zoomEditOriginals: [UUID: ZoomSegment] = [:]
  private var speedEditOriginals: [UUID: SpeedSegment] = [:]
  /// Undo can finish a model transaction while SwiftUI still owns its gesture.
  /// Ignore that gesture's remaining ticks until its real end callback arrives.
  private var interruptedZoomEdits = Set<UUID>()
  private var interruptedSpeedEdits = Set<UUID>()
  private var estimateTask: Task<Void, Never>?
  private var sourceSizeTask: Task<Int64?, Never>?
  private var cachedSourceFileSize: Int64?
  private var estimateRevision: UInt64 = 0
  private var isPerformanceWorkClosed = false
  private let restoredSessionData: VideoEditorSessionData?
  private var didRestoreSession = false

  // MARK: - Computed Properties

  var trimmedDuration: CMTime {
    if isGIF {
      return CMTimeSubtract(trimEnd, trimStart)
    }
    return CMTime(seconds: sequenceDuration, preferredTimescale: 600)
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
    previewRateController = VideoEditorPreviewRateController(player: player)
    let loadedTransitionDuration = Self.loadZoomTransitionDuration()
    initialZoomTransitionDuration = loadedTransitionDuration
    zoomTransitionDuration = loadedTransitionDuration
    recordingMetadata = initialMetadata
    reloadCursorLayer()

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

  /// The file the editor actually edits: the multi-track audio source when present,
  /// else a flattened Studio recording's cursor-less original, else `url` itself.
  static func editorAssetURL(for url: URL, metadata: RecordingMetadata?) -> URL {
    if let audioSourceURL = metadata?.audioSourceURL,
       FileManager.default.fileExists(atPath: audioSourceURL.path) {
      return audioSourceURL
    }
    if let name = metadata?.studioSourceFileName,
       let studioSourceURL = try? RecordingMetadataStore.sidecarURL(named: name, kind: .studioSource),
       FileManager.default.fileExists(atPath: studioSourceURL.path) {
      return studioSourceURL
    }
    return url
  }

  static func audioTrackRoles(for audioTracks: [AVAssetTrack],
                              metadata: RecordingMetadata?) -> [VideoEditorAudioTrackRole] {
    let count = audioTracks.count
    guard count > 0 else { return [] }

    if let metadata,
       metadata.audioSourceURL != nil,
       !metadata.audioSourceTracks.isEmpty {
      let rolesByTrackID = Dictionary(
        metadata.audioSourceTracks.map { ($0.trackID, $0.role) },
        uniquingKeysWith: { first, _ in first }
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
    audioTailPlaybackTimer?.invalidate()
    reverseShuttleTimer?.invalidate()
    speedPreviewBuildTask?.cancel()
    autoFocusBuildTask?.cancel()
    mappedAutoFocusBuildTask?.cancel()
    smartAutoZoomTask?.cancel()
    smartAutoZoomNoticeTask?.cancel()
    estimateTask?.cancel()
    sourceSizeTask?.cancel()
    previewRateController?.invalidate()
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
        let loadedFPS = await (try? track.load(.nominalFrameRate)) ?? 30
        if loadedFPS.isFinite, loadedFPS >= 5, loadedFPS <= 240 {
          nominalFrameRate = Double(loadedFPS)
        }
      }
      let audioTracks = try await asset.loadTracks(withMediaType: .audio)
      let audioTrackCount = audioTracks.count
      audioTrackRoles = Self.audioTrackRoles(for: audioTracks, metadata: recordingMetadata)
      seedPrimaryAudioClipIfNeeded(duration: CMTimeGetSeconds(loadedDuration))
      if !restoreSessionIfNeeded(primaryDuration: CMTimeGetSeconds(loadedDuration)) {
        // Seed the sequence with one clip spanning the whole recording.
        let primaryDuration = CMTimeGetSeconds(loadedDuration)
        let seed = TimelineClip(source: .primary, sourceDuration: primaryDuration)
        clips = [seed]
        initialClips = clips
        initialAudioClips = audioClips
        initialMutedAudioLanes = mutedAudioLanes
        initialTimelineBookmarks = timelineBookmarks
        initialTextOverlays = textOverlays
        selectedClipId = seed.id
        activeClipId = seed.id
        activeItemSource = .primary
        // Re-evaluate dirty state after baselines are seeded so a freshly opened
        // untouched video never starts with `hasUnsavedChanges == true`.
        updateHasUnsavedChanges()
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
      if let savedAudioClips = sessionData.audioClips {
        let existingClips = savedAudioClips.filter { clip in
          switch clip.source {
          case .primary:
            true
          case .file(let url):
            FileManager.default.fileExists(atPath: url.path)
          }
        }
        audioClips = AudioTimelineLaneLayout.deduplicatingOverlaps(existingClips)
        for clip in audioClips {
          audioWaveformCache.ensureLoaded(for: waveformSourceURL(for: clip))
        }
      }
      if let savedMutedLanes = sessionData.mutedAudioLanes {
        mutedAudioLanes = savedMutedLanes
      }
      if let savedBookmarks = sessionData.timelineBookmarks {
        timelineBookmarks = savedBookmarks.filter { $0.isFinite && $0 >= 0 }.sorted()
      }
      if let savedTextOverlays = sessionData.textOverlays {
        textOverlays = savedTextOverlays.map { $0.clamped(to: max(structuralDuration, 0.2)) }
      }
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
    restoreStudioLayers(from: sessionData)
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
  /// Token for the latest user/internal seek, used to ignore stale item-time ticks.
  private var internalSeekToken: UUID?
  /// True while a handoff seek into the next clip is still completing. Ticks and
  /// item-end notifications delivered in that window still reflect the previous
  /// clip's position, so they must be dropped instead of acted on.
  private var handoffSeekInFlight = false
  /// Identifies the active handoff so a newer user seek can supersede it safely.
  private var handoffSeekToken: UUID?
  /// Speed preview uses the same scaled media timeline as export, played at 1x.
  /// This avoids AVPlayer's delayed rate change skipping frames after a fast span.
  private var speedPreviewItem: AVPlayerItem?
  private var speedPreviewIsPreparing = false
  private var speedPreviewBuildFailed = false
  private var speedPreviewRevision = 0
  private var speedPreviewBuildTask: Task<Void, Never>?
  private var speedTrackDragInProgress = false
  private var speedTrackDragDidChange = false
  /// Pre-drag snapshot for clip trim gestures (one undo entry per gesture).
  private var clipTrimOriginalClips: [TimelineClip]?
  /// Latest scrub position waiting for the in-flight seek to land (chase seek).
  private var pendingScrubSeekSeconds: TimeInterval?
  private let primaryPlayerItem: AVPlayerItem

  /// True when `AVPlayer` is settled on its current item with no speed-preview build or
  /// asynchronous seek/handoff in flight (safe to assign `player.rate` immediately).
  var isPreviewTransportReadyForImmediateRateChange: Bool {
    !speedPreviewIsPreparing
      && !speedPreviewBuildFailed
      && internalSeekToken == nil
      && !handoffSeekInFlight
  }

  func play() {
    stopReverseShuttleTimer()
    if playbackState.shuttleRate <= 0 {
      playbackState.setShuttleRate(1)
    }
    let playheadNow = CMTimeGetSeconds(playbackState.currentTime)
    if !isGIF, isPlayheadInVideoGap, allowsGapPlayhead(at: playheadNow) {
      let nextPlacement = placements.first(where: { $0.activeStart > playheadNow + 0.0001 })
      let targetEnd = nextPlacement?.activeStart ?? effectiveTimelinePlaybackEnd
      if playheadNow < targetEnd - 0.02 {
        startGapPlayback(until: targetEnd, resumePlacement: nextPlacement, forceSeek: true)
        return
      } else if let nextPlacement {
        playbackState.setCurrentTime(CMTime(seconds: nextPlacement.activeStart, preferredTimescale: 600))
        seekPlayerInternally(to: nextPlacement.activeStart)
      } else {
        seek(to: .zero)
        let rewound = CMTimeGetSeconds(playbackState.currentTime)
        if isPlayheadInVideoGap, allowsGapPlayhead(at: rewound) {
          let firstNext = placements.first(where: { $0.activeStart > rewound + 0.0001 })
          let endTarget = firstNext?.activeStart ?? effectiveTimelinePlaybackEnd
          if rewound < endTarget - 0.02 {
            startGapPlayback(until: endTarget, resumePlacement: firstNext, forceSeek: true)
            return
          }
        }
      }
    }
    if speedPreviewBuildFailed {
      // A transient source/read error should not leave Play disabled forever.
      playbackState.setPlaying(true)
      addedAudioPlayer.play(at: CMTimeGetSeconds(playbackState.currentTime))
      scheduleSpeedPreviewRebuild()
      return
    }
    var waitingForSeek = speedPreviewIsPreparing || internalSeekToken != nil || handoffSeekInFlight
    if !speedPreviewIsPreparing,
       internalSeekToken == nil,
       !handoffSeekInFlight,
       !isGIF {
      // A rewind whose zero-tolerance seek did not land leaves the transport
      // parked at the item end (or past the last active out-point) while the
      // playhead claims 0. Playing from there would immediately hit the end and
      // rewind again — the reported "stuck at start" loop. Re-anchor the
      // transport to the playhead's claimed position instead of trusting the
      // item's parked position.
      let playableEnd = placements.last(where: { $0.activeEnd > $0.activeStart })?
        .activeEnd ?? CMTimeGetSeconds(timelineDuration)
      if let playerTime = currentPlayerTimelineTime() {
        let parkedAtSequenceEnd = playerTime.seconds.isFinite
          && abs(playerTime.seconds - playableEnd) <= 0.1
          && abs(playerTime.seconds - CMTimeGetSeconds(playbackState.currentTime)) > 0.05
        if parkedAtSequenceEnd {
          waitingForSeek = true
          let claimedTime = normalizedTimelineTime(playbackState.currentTime)
          playbackState.setCurrentTime(claimedTime)
          seekPlayerInternally(to: CMTimeGetSeconds(claimedTime))
        } else {
          playbackState.setCurrentTime(playerTime)
        }
      } else {
        waitingForSeek = true
        let claimedTime = normalizedTimelineTime(playbackState.currentTime)
        playbackState.setCurrentTime(claimedTime)
        seekPlayerInternally(to: CMTimeGetSeconds(claimedTime))
      }
    }
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
    playbackState.setPlaying(true)
    addedAudioPlayer.play(at: CMTimeGetSeconds(playbackState.currentTime))
    if waitingForSeek {
      if !speedPreviewIsPreparing {
        previewRateController?.setPlaybackIntent(true)
      }
      return
    }
    applyPreviewRate(speedPreviewItem == nil ? currentPreviewRate(at: currentTime) : 1,
                     startPlayback: true)
    refreshPreviewRateSchedule()
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

  private func currentPlayerTimelineTime() -> CMTime? {
    if speedPreviewItem === player.currentItem {
      let time = player.currentTime()
      guard time.isNumeric else { return nil }
      return timelineTime(atPreviewOutput: CMTimeGetSeconds(time))
    }
    guard let placement = placementForClip(activeClipId) else { return nil }
    let time = player.currentTime()
    guard time.isNumeric else { return nil }
    let sourceTime = CMTimeGetSeconds(time)
    guard sourceTime >= placement.clip.sourceStart - 0.05,
          sourceTime <= placement.clip.sourceEnd + 0.01
    else { return nil }
    return CMTime(
      seconds: placement.sequenceTime(atSource: sourceTime),
      preferredTimescale: 600
    )
  }

  /// Pause without republishing the parked position to the playhead. Rewinds call
  /// this because the player is still parked at the item end — publishing that
  /// position would flash the playhead at the end right before the rewind lands.
  private func pauseAtPendingPosition() {
    stopReverseShuttleTimer()
    stopAudioTailPlayback()
    addedAudioPlayer.pause()
    previewRateController?.setPlaybackIntent(false)
    player.pause()
    playbackState.setShuttleRate(0)
    playbackState.setPlaying(false)
  }

  func pause() {
    let wasReversing = reverseShuttleTimer != nil || playbackState.shuttleRate < 0
    stopReverseShuttleTimer()
    let wasInGapPlayback = audioTailPlaybackTimer != nil
    stopAudioTailPlayback()
    addedAudioPlayer.pause()
    previewRateController?.setPlaybackIntent(false)
    player.pause()
    if !wasInGapPlayback,
       !isPlayheadInVideoGap,
       !speedPreviewIsPreparing,
       internalSeekToken == nil,
       !handoffSeekInFlight,
       let playerTime = currentPlayerTimelineTime() {
      playbackState.setCurrentTime(playerTime)
    }
    playbackState.setShuttleRate(0)
    playbackState.setPlaying(false)
    if wasReversing {
      syncPlayerAudioWithExportSettings()
    }
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

  /// Seek to a STRUCTURAL timeline time. Allows landing in any genuine black-screen gap
  /// (explicit clip gap, middle gap with audio, or audio tail past video).
  func seek(to time: CMTime) {
    if reverseShuttleTimer != nil || playbackState.shuttleRate < 0 {
      pauseAtPendingPosition()
      syncPlayerAudioWithExportSettings()
    } else {
      stopReverseShuttleTimer()
    }
    stopAudioTailPlayback()
    let seconds = CMTimeGetSeconds(time)
    if !isGIF, seconds.isFinite {
      let clamped = max(0, min(seconds, CMTimeGetSeconds(timelineDuration)))
      if TimelineSequence.activePlacement(at: clamped, in: placements) == nil,
         allowsGapPlayhead(at: clamped) {
        let gapTime = CMTime(seconds: clamped, preferredTimescale: 600)
        player.pause()
        player.isMuted = true
        playbackState.setCurrentTime(gapTime)
        addedAudioPlayer.seek(to: clamped)
        updateClipActionAvailability()
        return
      }
    }
    let clampedTime = normalizedTimelineTime(time)
    playbackState.setCurrentTime(clampedTime)
    seekPlayerInternally(to: CMTimeGetSeconds(clampedTime))
    player.isMuted = shouldMutePreviewPlayer
    addedAudioPlayer.seek(to: CMTimeGetSeconds(clampedTime))
    updateClipActionAvailability()
  }

  func stepTimeline(by seconds: Double) {
    let step = CMTime(seconds: seconds, preferredTimescale: 600)
    let steppedTime = CMTimeAdd(currentTime, step)
    seek(to: steppedTime)
  }

  // MARK: - Scrubbing

  func startScrubbing() {
    playbackState.setScrubbing(true)
    pause()
  }

  /// Scrubbing follows the structural timeline. Lands freely in black-screen gaps
  /// when clip gaps or independent audio cover them; snaps to active material otherwise.
  ///
  /// Chase seek: the playhead follows every event, but only one frame-exact player seek
  /// is in flight at a time. A newer target waits and is issued when that seek lands;
  /// otherwise each mouse event cancelled the previous decode and the frame rarely
  /// landed during a fast drag. `endScrubbing` flushes the last target, so the final
  /// frame is exactly the one the playhead shows.
  func scrub(to time: CMTime) {
    let seconds = CMTimeGetSeconds(time)
    if !isGIF, seconds.isFinite {
      let clamped = max(0, min(seconds, CMTimeGetSeconds(timelineDuration)))
      if TimelineSequence.activePlacement(at: clamped, in: placements) == nil,
         allowsGapPlayhead(at: clamped) {
        pendingScrubSeekSeconds = nil
        playbackState.setCurrentTime(CMTime(seconds: clamped, preferredTimescale: 600))
        addedAudioPlayer.seek(to: clamped)
        updateClipActionAvailability()
        return
      }
    }
    let clampedTime = normalizedTimelineTime(time)
    playbackState.setCurrentTime(clampedTime)
    let clampedSeconds = CMTimeGetSeconds(clampedTime)
    if playbackState.isScrubbing, internalSeekToken != nil {
      pendingScrubSeekSeconds = clampedSeconds
    } else {
      seekPlayerInternally(to: clampedSeconds)
    }
    addedAudioPlayer.seek(to: clampedSeconds)
    updateClipActionAvailability()
  }

  func endScrubbing() {
    playbackState.setScrubbing(false)
    // With a seek still decoding, its completion chases the pending target; issuing it
    // here would only cancel that decode.
    if let pending = pendingScrubSeekSeconds, internalSeekToken == nil {
      seekPlayerInternally(to: pending)
    }
  }

  /// Enable or disable the speed-segment preview rate controller (disabled during
  /// fast J/K/L shuttle so user shuttle speed is never overwritten by 1× speed spans).
  func setPreviewRateControllerEnabled(_ enabled: Bool) {
    if !enabled {
      previewRateController?.setPlaybackIntent(false)
    }
    previewRateController?.setEnabled(enabled)
  }

  /// Coalesced seek for reverse J-shuttle so a new tick never cancels an in-flight
  /// video decode, keeping reverse preview smooth and CPU usage low.
  func seekPlayerForReverseShuttle(to timelineSeconds: TimeInterval) {
    guard TimelineSequence.activePlacement(at: timelineSeconds, in: placements) != nil else { return }
    if internalSeekToken != nil {
      pendingScrubSeekSeconds = timelineSeconds
    } else {
      seekPlayerInternally(to: timelineSeconds)
    }
  }

  // MARK: - Player Item Management (clip sequence)

  /// Rebuild the preview media timeline when clips or speed blocks change. The
  /// player stays parked until the current revision is ready; a superseded build
  /// cannot install an old speed map over a newer edit.
  private func scheduleSpeedPreviewRebuild(immediate: Bool = false) {
    guard !isPerformanceWorkClosed else { return }
    if defersPreviewRebuild, speedTrackDragDidChange {
      return
    }
    let debounceBuild = !immediate && (speedPreviewIsPreparing || speedPreviewItem != nil)
    speedPreviewRevision += 1
    let revision = speedPreviewRevision
    speedPreviewBuildTask?.cancel()
    speedPreviewBuildTask = nil
    speedPreviewBuildFailed = false

    guard !isGIF, hasSpeedSegments, !clips.isEmpty else {
      speedPreviewIsPreparing = false
      if speedPreviewItem != nil {
        speedPreviewItem = nil
        activeItemSource = nil
        seekPlayerInternally(to: CMTimeGetSeconds(currentTime))
      } else {
        refreshPreviewRateSchedule()
      }
      return
    }

    speedPreviewIsPreparing = true
    previewRateController?.setPlaybackIntent(false)
    previewRateController?.setEnabled(false)
    player.pause()
    internalSeekToken = nil
    handoffSeekToken = nil
    handoffSeekInFlight = false
    if defersPreviewRebuild {
      speedTrackDragDidChange = true
      return
    }
    let clipsSnapshot = clips
    let mapSnapshot = sequenceMap
    speedPreviewBuildTask = Task { @MainActor [weak self] in
      guard let self else { return }
      do {
        // Speed handles publish updates during a drag. Coalesce those revisions
        // into one composition so the UI does not rebuild media every frame.
        if debounceBuild {
          try await Task.sleep(nanoseconds: 120_000_000)
        }
        let item = try await makeSpeedPreviewItem(clips: clipsSnapshot, map: mapSnapshot)
        guard !Task.isCancelled, speedPreviewRevision == revision else { return }
        speedPreviewItem = item
        speedPreviewIsPreparing = false
        activeItemSource = nil
        player.replaceCurrentItem(with: item)
        item.audioTimePitchAlgorithm = .spectral
        syncPlayerAudioWithExportSettings()
        seekPlayerInternally(to: CMTimeGetSeconds(currentTime))
      } catch {
        guard speedPreviewRevision == revision else { return }
        speedPreviewIsPreparing = false
        speedPreviewBuildFailed = true
        playbackState.setPlaying(false)
        DiagnosticLogger.shared.logError(.editor, error, "Speed preview composition failed")
        speedPreviewItem = nil
        activeItemSource = nil
        seekPlayerInternally(to: CMTimeGetSeconds(currentTime))
      }
    }
  }

  func beginSpeedTrackDrag() {
    guard !isPerformanceWorkClosed else { return }
    // A rebuild an open undo group is already holding must survive the drag.
    if !defersPreviewRebuild {
      speedTrackDragDidChange = false
    }
    speedTrackDragInProgress = true
  }

  func endSpeedTrackDrag() {
    guard !isPerformanceWorkClosed else { return }
    guard speedTrackDragInProgress else { return }
    speedTrackDragInProgress = false
    flushDeferredPreviewRebuild()
  }

  /// A speed drag or an undo group holds preview rebuilds until it ends.
  private var defersPreviewRebuild: Bool {
    speedTrackDragInProgress || undoGroupDepth > 0
  }

  private func flushDeferredPreviewRebuild() {
    guard !isPerformanceWorkClosed, !defersPreviewRebuild, speedTrackDragDidChange else { return }
    speedTrackDragDidChange = false
    scheduleSpeedPreviewRebuild(immediate: true)
  }

  private func makeSpeedPreviewItem(
    clips clipsSnapshot: [TimelineClip],
    map: TimelineSequenceMap
  ) async throws -> AVPlayerItem {
    let composition = AVMutableComposition()
    guard let videoTrack = composition.addMutableTrack(
      withMediaType: .video,
      preferredTrackID: kCMPersistentTrackID_Invalid
    ) else {
      throw NSError(domain: "VideoEditorSpeedPreview", code: 1)
    }

    let primaryVideo = try await asset.loadTracks(withMediaType: .video).first
    if let primaryVideo {
      videoTrack.preferredTransform = try await primaryVideo.load(.preferredTransform)
    }
    var cursor = CMTime.zero
    for clip in clipsSnapshot {
      try Task.checkCancellation()
      let range = CMTimeRange(
        start: CMTime(seconds: clip.sourceStart, preferredTimescale: 600),
        duration: CMTime(seconds: clip.duration, preferredTimescale: 600)
      )
      let sourceTrack = if clip.isPrimary {
        primaryVideo
      } else {
        try await clipAsset(for: clip).loadTracks(withMediaType: .video).first
      }
      if let sourceTrack {
        try videoTrack.insertTimeRange(range, of: sourceTrack, at: cursor)
      } else {
        videoTrack.insertEmptyTimeRange(CMTimeRange(start: cursor, duration: range.duration))
      }
      cursor = CMTimeAdd(cursor, range.duration)
    }
    Self.scalePreviewTrack(videoTrack, with: map)

    let primaryAudioTracks = try await asset.loadTracks(withMediaType: .audio)
    for lane in 0 ..< max(1, primaryAudioTracks.count) {
      try Task.checkCancellation()
      guard let audioTrack = composition.addMutableTrack(
        withMediaType: .audio,
        preferredTrackID: kCMPersistentTrackID_Invalid
      ) else { continue }
      cursor = .zero
      for clip in clipsSnapshot {
        let range = CMTimeRange(
          start: CMTime(seconds: clip.sourceStart, preferredTimescale: 600),
          duration: CMTime(seconds: clip.duration, preferredTimescale: 600)
        )
        let sourceTrack: AVAssetTrack? = if clip.isPrimary {
          lane < primaryAudioTracks.count ? primaryAudioTracks[lane] : nil
        } else if lane == 0 {
          try await clipAsset(for: clip).loadTracks(withMediaType: .audio).first
        } else {
          nil
        }
        if let sourceTrack {
          try audioTrack.insertTimeRange(range, of: sourceTrack, at: cursor)
        } else {
          audioTrack.insertEmptyTimeRange(CMTimeRange(start: cursor, duration: range.duration))
        }
        cursor = CMTimeAdd(cursor, range.duration)
      }
      Self.scalePreviewTrack(audioTrack, with: map)
    }
    return AVPlayerItem(asset: composition)
  }

  private static func scalePreviewTrack(
    _ track: AVMutableCompositionTrack,
    with map: TimelineSequenceMap
  ) {
    for span in map.spans.reversed() where span.rate != 1 {
      track.scaleTimeRange(
        CMTimeRange(
          start: CMTime(seconds: span.seqStart, preferredTimescale: 600),
          duration: CMTime(seconds: span.seqDuration, preferredTimescale: 600)
        ),
        toDuration: CMTime(seconds: span.scaledDuration, preferredTimescale: 600)
      )
    }
  }

  private func timelineTime(atPreviewOutput output: TimeInterval) -> CMTime? {
    guard output.isFinite,
          let playable = TimelineSequence.placement(
            at: sequenceMap.toSequence(output), in: playbackPlacements
          ),
          let structural = placements.first(where: { $0.clip.id == playable.clip.id })
    else { return nil }
    let sourceTime = playable.sourceTime(at: sequenceMap.toSequence(output))
    return CMTime(
      seconds: structural.sequenceTime(atSource: sourceTime),
      preferredTimescale: 600
    )
  }

  private func previewOutputTime(atTimeline timeline: TimeInterval) -> TimeInterval? {
    guard let sequenceTime = playbackSequenceTime(atTimeline: timeline) else { return nil }
    return sequenceMap.toOutput(sequenceTime)
  }

  /// Zero tolerance at the exact media start is unreliable: recordings whose first
  /// frame PTS is not exactly 0 (common for ScreenCaptureKit captures) can reject
  /// the request silently, leaving the transport parked and the Play intent hung.
  /// The start of playback tolerates one frame; every other target stays frame-exact.
  static func seekToleranceBefore(for targetItemTime: TimeInterval) -> CMTime {
    abs(targetItemTime) <= 1.0 / 30.0
      ? CMTime(seconds: 1.0 / 30.0, preferredTimescale: 600)
      : .zero
  }

  /// Point the player at whichever clip covers a sequence time, seeking to that
  /// clip's own source time.
  private func seekPlayerInternally(to sequenceSeconds: TimeInterval) {
    // Any seek supersedes a scrub target still waiting for the previous seek.
    pendingScrubSeekSeconds = nil
    previewRateController?.setEnabled(false)
    player.pause()
    // A seek supersedes any pending clip handoff, even when it lands inside that
    // handoff's destination clip. Invalidate both the completion and its observer
    // gate before issuing the new seek so stale completion results cannot pause or
    // restart playback at the old clip boundary.
    handoffSeekToken = nil
    handoffSeekInFlight = false
    if speedPreviewIsPreparing {
      internalSeekToken = nil
      return
    }
    let token = UUID()
    internalSeekToken = token
    let targetItemTime: TimeInterval
    if speedPreviewItem === player.currentItem {
      guard let outputTime = previewOutputTime(atTimeline: sequenceSeconds) else {
        internalSeekToken = nil
        return
      }
      targetItemTime = outputTime
    } else if let context = sourceContext(atSequence: sequenceSeconds) {
      activeClipId = context.clip.id
      activateItemIfNeeded(for: context.clip)
      player.isMuted = shouldMutePreviewPlayer
      targetItemTime = context.sourceTime
    } else {
      internalSeekToken = nil
      setupTimeObserver()
      if playbackState.shuttleRate >= 0 {
        refreshPreviewRateSchedule()
      }
      return
    }
    let isReverseShuttle = playbackState.shuttleRate < 0
    let rateGeneration = isReverseShuttle ? nil : refreshPreviewRateSchedule()
    let rateController = previewRateController
    if let rateGeneration {
      rateController?.awaitSeekLanding(at: targetItemTime, ifGeneration: rateGeneration)
    }
    player.seek(
      to: CMTime(seconds: targetItemTime, preferredTimescale: 600),
      toleranceBefore: Self.seekToleranceBefore(for: targetItemTime),
      toleranceAfter: .zero
    ) { [weak self, weak rateController] finished in
      if finished, let rateGeneration {
        rateController?.resumeAfterSeek(ifGeneration: rateGeneration)
      }
      Task { @MainActor [weak self] in
        guard let self, internalSeekToken == token else { return }
        internalSeekToken = nil
        // The scrub moved on while this seek was decoding: chase the latest target.
        if let pending = pendingScrubSeekSeconds {
          seekPlayerInternally(to: pending)
          return
        }
        setupTimeObserver()
        if playbackState.shuttleRate < 0 {
          return
        }
        refreshPreviewRateSchedule()
        guard finished else {
          pause()
          return
        }
        if isPlaying, playbackState.shuttleRate >= 0, player.rate == 0 {
          let requestedRate: Float = if playbackState.shuttleRate > 1.05 {
            playbackState.shuttleRate
          } else {
            speedPreviewItem == nil ? currentPreviewRate(at: currentTime) : 1
          }
          applyPreviewRate(requestedRate, startPlayback: true)
        }
      }
    }
  }

  /// Swap the player item when the sequence crosses into a different source asset.
  ///
  /// Keyed on `source`, not clip id: consecutive clips cut from the same asset share
  /// one item, so an ordinary split costs a seek rather than a reload.
  private func activateItemIfNeeded(for clip: TimelineClip) {
    guard activeItemSource != clip.source else { return }

    let item = clip.isPrimary ? primaryPlayerItem : AVPlayerItem(asset: clipAsset(for: clip))
    if player.currentItem !== item {
      player.replaceCurrentItem(with: item)
    }
    activeItemSource = clip.source
    player.currentItem?.audioTimePitchAlgorithm = .spectral
    player.isMuted = shouldMutePreviewPlayer
    syncPlayerAudioWithExportSettings()
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
      return activeTimelineTime(clamped)
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
    return activeTimelineTime(resolved)
  }

  /// Quantize an active timeline time to the 600 timescale without leaving active
  /// material. Trim points are arbitrary doubles: rounding an off-grid in-point to
  /// the nearest tick can land just before it, where the time reads as trimmed-out
  /// footage and `seekPlayerInternally` has no clip to seek — the transport stays
  /// parked at the item end while the playhead claims the trimmed start.
  private func activeTimelineTime(_ seconds: TimeInterval) -> CMTime {
    let ticks = seconds * 600
    for candidate in [ticks.rounded(), ticks.rounded(.up), ticks.rounded(.down)] {
      let time = CMTime(value: CMTimeValue(candidate), timescale: 600)
      if sourceContext(atSequence: CMTimeGetSeconds(time)) != nil {
        return time
      }
    }
    return CMTime(seconds: seconds, preferredTimescale: 600)
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
      let pointSize = NSSize(
        width: max(1, CGFloat(image.width) / 2.0),
        height: max(1, CGFloat(image.height) / 2.0)
      )
      let rep = NSBitmapImageRep(cgImage: image)
      rep.size = pointSize
      let nsImage = NSImage(size: pointSize)
      nsImage.addRepresentation(rep)
      return nsImage
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
      return FrameExtractionProfile(frameCount: 32, tolerance: .zero, strategyLabel: "default-no-track")
    }

    let estimatedDataRate = await (try? track.load(.estimatedDataRate)) ?? 0
    let pixelCount = naturalSize.width * naturalSize.height

    // Guardrail: heavier 4K/5K files still get dense Retina filmstrip cells while
    // allowing modest keyframe tolerance to keep hardware extraction snappy.
    if pixelCount >= 7_000_000 || estimatedDataRate >= 80_000_000 {
      return FrameExtractionProfile(
        frameCount: 20,
        tolerance: CMTime(value: 1, timescale: 20),
        strategyLabel: "very-heavy"
      )
    }

    if pixelCount >= 3_700_000 || estimatedDataRate >= 45_000_000 {
      return FrameExtractionProfile(
        frameCount: 24,
        tolerance: CMTime(value: 1, timescale: 30),
        strategyLabel: "heavy"
      )
    }

    return FrameExtractionProfile(frameCount: 32, tolerance: .zero, strategyLabel: "default")
  }

  private func generateFrameThumbnails(
    frameCount: Int,
    totalSeconds: Double,
    tolerance: CMTime
  ) async -> [CGImage] {
    let safeCount = max(frameCount, 1)
    // 480×270 (@2x = 240×135pt) delivers crisp Retina sharpness across the 64pt-tall
    // timeline filmstrip (even when zoomed in) and hover scrub previews (~16 MB max).
    let targetSize = CGSize(width: 480, height: 270)
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
    initialAudioClips = audioClips
    initialMutedAudioLanes = mutedAudioLanes
    initialTimelineBookmarks = timelineBookmarks
    initialTextOverlays = textOverlays
    initialBackgroundStyle = backgroundStyle
    initialBackgroundPadding = backgroundPadding
    initialBackgroundShadowIntensity = backgroundShadowIntensity
    initialBackgroundCornerRadius = backgroundCornerRadius
    initialBackgroundAlignment = backgroundAlignment
    initialBackgroundAspectRatio = backgroundAspectRatio
    initialExportSettings = exportSettings
    initialMotionBlurSettings = motionBlurSettings
    initialZoomTransitionDuration = zoomTransitionDuration
    initialCaptions = captions
    clearUndoHistory()
  }

  // MARK: - Undo/Redo Actions

  /// Record an action for undo support
  func recordAction(_ action: EditorAction) {
    guard !isUndoingOrRedoing else { return }
    if undoGroupDepth > 0 {
      undoGroupBuffer.append(action)
      redoStack.removeAll()
      updateUndoRedoState()
      return
    }
    pushUndoEntry(action)
  }

  private func pushUndoEntry(_ action: EditorAction) {
    undoStack.append(action)
    if undoStack.count > maxUndoStackSize {
      undoStack.removeFirst()
    }
    redoStack.removeAll()
    updateUndoRedoState()
  }

  private func finishSegmentEdits() {
    let zoomIDs = Array(zoomEditOriginals.keys)
    let speedIDs = Array(speedEditOriginals.keys)
    for id in zoomIDs {
      endZoomEdit(id: id)
    }
    for id in speedIDs {
      endSpeedEdit(id: id)
    }
    interruptedZoomEdits.formUnion(zoomIDs)
    interruptedSpeedEdits.formUnion(speedIDs)
  }

  /// Undo the last action. Ignored while an undo group is open (an AI run is
  /// mid-flight): its changes are not on the stack yet.
  func undo() {
    guard undoGroupDepth == 0 else { return }
    finishSegmentEdits()
    guard let action = undoStack.popLast() else { return }
    DiagnosticLogger.shared.log(.debug, .editor, "Undo", context: ["stackDepth": "\(undoStack.count)"])
    isUndoingOrRedoing = true
    defer {
      isUndoingOrRedoing = false
      updateUndoRedoState()
    }
    redoStack.append(revert(action, isRedo: false))
  }

  /// Redo the last undone action
  func redo() {
    guard undoGroupDepth == 0 else { return }
    finishSegmentEdits()
    guard let action = redoStack.popLast() else { return }
    DiagnosticLogger.shared.log(.debug, .editor, "Redo", context: ["stackDepth": "\(redoStack.count)"])
    isUndoingOrRedoing = true
    defer {
      isUndoingOrRedoing = false
      updateUndoRedoState()
    }
    undoStack.append(revert(action, isRedo: true))
  }

  /// Apply the inverse of `action` and return the entry for the opposite stack.
  /// The stacks hold inverses, so the same code serves undo and redo; only a
  /// split differs (undo rejoins the halves, redo divides again).
  private func revert(_ action: EditorAction, isRedo: Bool) -> EditorAction {
    switch action {
    case .trimStart(let old, let new):
      trimStart = old
      return .trimStart(old: new, new: old)

    case .trimEnd(let old, let new):
      trimEnd = old
      return .trimEnd(old: new, new: old)

    case .addZoom(let segment):
      zoomSegments.removeAll { $0.id == segment.id }
      if selectedZoomId == segment.id {
        selectedZoomId = nil
      }
      return .removeZoom(segment: segment)

    case .removeZoom(let segment):
      zoomSegments.append(segment)
      return .addZoom(segment: segment)

    case .updateZoom(let old, let new):
      if let index = zoomSegments.firstIndex(where: { $0.id == new.id }) {
        zoomSegments[index] = old
      }
      return .updateZoom(old: new, new: old)

    case .replaceZooms(let old, let new, let oldMotionBlur, let newMotionBlur):
      zoomSegments = old
      if let selectedZoomId, !old.contains(where: { $0.id == selectedZoomId }) {
        self.selectedZoomId = old.first?.id
      }
      if let oldMotionBlur {
        motionBlurSettings = oldMotionBlur
      }
      return .replaceZooms(
        old: new,
        new: old,
        oldMotionBlur: newMotionBlur,
        newMotionBlur: oldMotionBlur
      )

    case .updateMotionBlur(let old, let new):
      applyMotionBlurSettings(old)
      return .updateMotionBlur(old: new, new: old)

    case .addSpeed(let segment):
      speedSegments.removeAll { $0.id == segment.id }
      if selectedSpeedId == segment.id {
        selectedSpeedId = nil
      }
      return .removeSpeed(segment: segment)

    case .removeSpeed(let segment):
      speedSegments.append(segment)
      return .addSpeed(segment: segment)

    case .updateSpeed(let old, let new):
      if let index = speedSegments.firstIndex(where: { $0.id == new.id }) {
        speedSegments[index] = old
      }
      return .updateSpeed(old: new, new: old)

    case .toggleMute(let old, _):
      isMuted = old
      return .toggleMute(old: !old, new: old)

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
      return .updateBackground(
        oldStyle: newStyle,
        newStyle: oldStyle,
        oldPadding: newPadding,
        newPadding: oldPadding,
        oldShadow: newShadow,
        newShadow: oldShadow,
        oldCorner: newCorner,
        newCorner: oldCorner
      )

    case .addClip(let clip, let index):
      removeClipSilently(id: clip.id)
      syncPlayerAudioWithExportSettings()
      refreshPlayerFrameAtPlayhead()
      return .removeClip(clip: clip, index: index)

    case .removeClip(let clip, let index):
      insertClipSilently(clip, at: index)
      syncPlayerAudioWithExportSettings()
      refreshPlayerFrameAtPlayhead()
      return .addClip(clip: clip, index: index)

    case .updateClip(let old, let new):
      replaceClipSilently(id: new.id, with: old)
      syncPlayerAudioWithExportSettings()
      refreshPlayerFrameAtPlayhead()
      return .updateClip(old: new, new: old)

    case .moveClip(let id, let fromIndex, let toIndex):
      moveClipSilently(id: id, to: fromIndex)
      syncPlayerAudioWithExportSettings()
      refreshPlayerFrameAtPlayhead()
      return .moveClip(id: id, fromIndex: toIndex, toIndex: fromIndex)

    case .splitClip(let original, let index, let first, let second):
      if isRedo {
        // The undo handler rejoined the halves, so redo has to divide again.
        removeClipSilently(id: original.id)
        insertClipSilently(first, at: index)
        insertClipSilently(second, at: index + 1)
      } else {
        // Rejoin: drop both halves and restore the clip they came from.
        removeClipSilently(id: first.id)
        removeClipSilently(id: second.id)
        insertClipSilently(original, at: index)
      }
      syncPlayerAudioWithExportSettings()
      refreshPlayerFrameAtPlayhead()
      return .splitClip(original: original, index: index, first: first, second: second)

    case .replaceClips(let old, let new):
      clips = old
      if let selectedClipId, !old.contains(where: { $0.id == selectedClipId }) {
        self.selectedClipId = nil
      }
      syncPlayerAudioWithExportSettings()
      refreshPlayerFrameAtPlayhead()
      updateClipActionAvailability()
      return .replaceClips(old: new, new: old)

    case .updateFrame(let old, let new):
      applyFrameSettings(old)
      return .updateFrame(old: new, new: old)

    case .updateZoomTransitionDuration(let old, let new):
      zoomTransitionDuration = old
      return .updateZoomTransitionDuration(old: new, new: old)

    case .updateExportSettings(let old, let new):
      updateExportSettings(old)
      return .updateExportSettings(old: new, new: old)

    case .updateCursor(let old, let new):
      applyCursorSettings(old)
      return .updateCursor(old: new, new: old)

    case .updateCamera(let old, let new):
      applyCameraSettings(old)
      return .updateCamera(old: new, new: old)

    case .updateCaptions(let old, let new):
      applyCaptions(old)
      return .updateCaptions(old: new, new: old)

    case .replaceAudioClips(let old, let new):
      audioClips = old
      if let sel = selectedAudioClipId, !audioClips.contains(where: { $0.id == sel }) {
        selectedAudioClipId = nil
      }
      syncPlayerAudioWithExportSettings()
      updateClipActionAvailability()
      updateHasUnsavedChanges()
      return .replaceAudioClips(old: new, new: old)

    case .updateMutedAudioLanes(let old, let new):
      mutedAudioLanes = old
      syncPlayerAudioWithExportSettings()
      updateHasUnsavedChanges()
      return .updateMutedAudioLanes(old: new, new: old)

    case .replaceTextOverlays(let old, let new):
      textOverlays = old
      if let sel = selectedTextOverlayId, !textOverlays.contains(where: { $0.id == sel }) {
        selectedTextOverlayId = nil
      }
      updateClipActionAvailability()
      updateHasUnsavedChanges()
      return .replaceTextOverlays(old: new, new: old)

    case .replaceSpeeds(let old, let new):
      speedSegments = old
      if let selectedSpeedId, !old.contains(where: { $0.id == selectedSpeedId }) {
        self.selectedSpeedId = nil
      }
      scheduleSpeedPreviewRebuild()
      updateHasUnsavedChanges()
      return .replaceSpeeds(old: new, new: old)

    case .replaceTimelineBookmarks(let old, let new):
      timelineBookmarks = old
      updateClipActionAvailability()
      updateHasUnsavedChanges()
      return .replaceTimelineBookmarks(old: new, new: old)

    case .group(let actions):
      // Undo the members newest first; the returned group replays them oldest first.
      return .group(actions.reversed().map { revert($0, isRedo: isRedo) })
    }
  }

  private func updateUndoRedoState() {
    let undoAvailable = !undoStack.isEmpty
    let redoAvailable = !redoStack.isEmpty
    if canUndo != undoAvailable {
      canUndo = undoAvailable
    }
    if canRedo != redoAvailable {
      canRedo = redoAvailable
    }
  }

  private func clearUndoHistory() {
    undoStack.removeAll()
    redoStack.removeAll()
    updateUndoRedoState()
  }

  // MARK: - Undo Groups

  /// Collect every action recorded until the matching `endUndoGroup` into one undo
  /// step. Calls nest; only the outermost end pushes. Preview media rebuilds are
  /// held until then too, so a burst of edits rebuilds the composition once.
  func beginUndoGroup() {
    if undoGroupDepth == 0 {
      finishSegmentEdits()
      undoGroupBuffer = []
    }
    undoGroupDepth += 1
  }

  /// Close a group. An empty group leaves no entry; a single action is pushed as is.
  /// Returns the entry the outermost end pushed, if any.
  @discardableResult
  func endUndoGroup() -> EditorAction? {
    guard undoGroupDepth > 0 else { return nil }
    undoGroupDepth -= 1
    guard undoGroupDepth == 0 else { return nil }
    let actions = undoGroupBuffer
    undoGroupBuffer = []
    let entry: EditorAction? = switch actions.count {
    case 0: nil
    case 1: actions[0]
    default: .group(actions)
    }
    if let entry {
      pushUndoEntry(entry)
    }
    flushDeferredPreviewRebuild()
    return entry
  }

  var isUndoGroupOpen: Bool {
    undoGroupDepth > 0
  }

  /// The top undo entry, for callers that check whether their step is still the latest.
  var lastUndoEntry: EditorAction? {
    undoStack.last
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
  func beginZoomEdit(id: UUID) {
    guard !isPerformanceWorkClosed else { return }
    interruptedZoomEdits.remove(id)
    guard zoomEditOriginals[id] == nil,
          let segment = zoomSegments.first(where: { $0.id == id }) else { return }
    zoomEditOriginals[id] = segment
  }

  func endZoomEdit(id: UUID) {
    if interruptedZoomEdits.remove(id) != nil {
      return
    }
    guard !isPerformanceWorkClosed else {
      zoomEditOriginals.removeValue(forKey: id)
      return
    }
    guard let old = zoomEditOriginals.removeValue(forKey: id),
          let new = zoomSegments.first(where: { $0.id == id }), old != new else { return }
    recordAction(.updateZoom(old: old, new: new))
  }

  func beginSpeedEdit(id: UUID) {
    guard !isPerformanceWorkClosed else { return }
    interruptedSpeedEdits.remove(id)
    guard speedEditOriginals[id] == nil,
          let segment = speedSegments.first(where: { $0.id == id }) else { return }
    speedEditOriginals[id] = segment
    beginSpeedTrackDrag()
  }

  func endSpeedEdit(id: UUID) {
    if interruptedSpeedEdits.remove(id) != nil {
      return
    }
    guard !isPerformanceWorkClosed else {
      speedEditOriginals.removeValue(forKey: id)
      return
    }
    if let old = speedEditOriginals.removeValue(forKey: id),
       let new = speedSegments.first(where: { $0.id == id }), old != new {
      recordAction(.updateSpeed(old: old, new: new))
    }
    endSpeedTrackDrag()
    recalculateEstimatedFileSize(immediate: true)
  }

  func resolvedZoomSegment(id: UUID, startTime: TimeInterval, duration: TimeInterval) -> ZoomSegment? {
    guard var segment = zoomSegments.first(where: { $0.id == id }) else { return nil }
    let upper = CMTimeGetSeconds(timelineDuration)
    segment.startTime = max(0, min(startTime, upper - ZoomSegment.minDuration))
    segment.duration = max(ZoomSegment.minDuration, min(duration, upper - segment.startTime))
    return segment
  }

  func resolvedSpeedSegment(id: UUID, startTime: TimeInterval, duration: TimeInterval) -> SpeedSegment? {
    guard var segment = speedSegments.first(where: { $0.id == id }),
          let range = clampedSpeedRange(startTime ... (startTime + max(0, duration)), excluding: id) else { return nil }
    segment.startTime = range.start
    segment.duration = range.duration
    return segment
  }

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
    guard !interruptedZoomEdits.contains(id) else { return }
    let interval = PerfSignpost.VideoEditor.beginInterval("ZoomMutation")
    defer { PerfSignpost.VideoEditor.endInterval(interval) }
    guard let index = zoomSegments.firstIndex(where: { $0.id == id }) else { return }

    var segment = zoomSegments[index]
    let oldStartTime = segment.startTime
    let oldDuration = segment.duration
    if startTime != nil || duration != nil,
       let resolved = resolvedZoomSegment(
         id: id, startTime: startTime ?? segment.startTime,
         duration: duration ?? segment.duration
       ) {
      let newStartTime = resolved.startTime
      let newDuration = duration != nil ? resolved.duration : segment.duration
      if let keyframes = segment.smartKeyframes,
         !keyframes.isEmpty,
         abs(newStartTime - oldStartTime) > 0.0001 || abs(newDuration - oldDuration) > 0.0001 {
        segment.smartKeyframes = Self.remapSmartKeyframes(
          keyframes,
          fromOldRange: oldStartTime ... (oldStartTime + oldDuration),
          toNewRange: newStartTime ... (newStartTime + newDuration),
          placements: placements
        )
      }
      segment.startTime = newStartTime
      if duration != nil {
        segment.duration = resolved.duration
      }
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
      segment.smartKeyframes = nil
    }
    if let focusMargin {
      segment.focusMargin = AutoFocusSettings.clampFocusMargin(focusMargin)
      segment.smartKeyframes = nil
    }
    if let isEnabled {
      segment.isEnabled = isEnabled
    }

    let old = zoomSegments[index]
    guard segment != old else { return }
    zoomSegments[index] = segment
    if zoomEditOriginals[id] == nil {
      recordAction(.updateZoom(old: old, new: segment))
    }
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
    return VideoEditorAutoFocusEngine.resolvedCameraState(
      at: time,
      segments: zoomSegments,
      autoFocusPaths: mappedAutoFocusPaths,
      transitionDuration: effectiveDuration
    )
  }

  /// Full-resolution physical shutter-angle motion blur plan for Retina Metal live preview.
  func previewShutterPlan(at time: TimeInterval) -> VideoEditorMotionBlurEngine.ShutterPlan {
    let sourceSize = naturalSize.width > 1 && naturalSize.height > 1
      ? naturalSize
      : CGSize(width: 1920, height: 1080)
    return VideoEditorMotionBlurEngine.shutterPlan(
      at: time,
      frameDuration: 1.0 / 30.0,
      frameSize: sourceSize,
      segments: zoomSegments,
      autoFocusPaths: mappedAutoFocusPaths,
      transitionDuration: ZoomCalculator.clampTransitionDuration(zoomTransitionDuration),
      settings: motionBlurSettings
    )
  }

  /// Analytical, zero-flicker directional + radial motion blur parameters for diagnostics.
  func previewMotionBlurParams(
    at time: TimeInterval,
    viewSize: CGSize
  ) -> VideoEditorMotionBlurEngine.PreviewFilterParams {
    VideoEditorMotionBlurEngine.previewFilterParams(
      at: time,
      viewSize: viewSize,
      segments: zoomSegments,
      autoFocusPaths: mappedAutoFocusPaths,
      transitionDuration: ZoomCalculator.clampTransitionDuration(zoomTransitionDuration),
      settings: motionBlurSettings
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
    endSpeedEdit(id: id)
    guard let segment = speedSegments.first(where: { $0.id == id }) else { return }
    DiagnosticLogger.shared.log(.debug, .editor, "Removing speed segment", context: ["id": id.uuidString])
    speedSegments.removeAll { $0.id == id }
    if selectedSpeedId == id {
      selectedSpeedId = nil
    }
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
    guard !interruptedSpeedEdits.contains(id) else { return }
    let interval = PerfSignpost.VideoEditor.beginInterval("SpeedMutation")
    defer { PerfSignpost.VideoEditor.endInterval(interval) }
    guard let index = speedSegments.firstIndex(where: { $0.id == id }) else { return }
    let old = speedSegments[index]
    var new = old

    if let rate {
      new.rate = SpeedSegment.clampRate(rate)
    }

    if startTime != nil || duration != nil {
      guard let resolved = resolvedSpeedSegment(
        id: id, startTime: startTime ?? old.startTime, duration: duration ?? old.duration
      ) else { return }
      new.startTime = resolved.startTime
      new.duration = resolved.duration
    }

    guard new != old else { return }
    speedSegments[index] = new
    if speedEditOriginals[id] == nil {
      recordAction(.updateSpeed(old: old, new: new))
    }
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
    if selectedClipId == id {
      selectedClipId = nil
    }
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

  /// Re-anchor the preview decoder to the current playhead after an undo/redo clip mutation
  /// so the visible video frame never stays frozen on a superseded clip timestamp.
  private func refreshPlayerFrameAtPlayhead() {
    guard !isGIF, !isPlaying else { return }
    let t = CMTimeGetSeconds(playbackState.currentTime)
    guard t.isFinite else { return }
    if sourceContext(atSequence: t) != nil {
      seekPlayerInternally(to: t)
    }
  }

  func selectClip(id: UUID?) {
    selectedClipId = id
    if id != nil {
      selectedAudioClipId = nil
      selectedTextOverlayId = nil
    }
    updateClipActionAvailability()
  }

  /// Ripple-shift independent audio, text overlays, zoom segments, speed segments, and
  /// timeline bookmarks across `removedSpans` on the structural timeline, returning the
  /// undoable `EditorAction` entries to group with the owning clip mutation.
  private func applyTimelineRipple(
    removing removedSpans: [ClosedRange<TimeInterval>],
    includeZoomAndSpeed: Bool = true
  ) -> [EditorAction] {
    let spans = VideoEditorTimelineCut.merged(removedSpans)
    guard !spans.isEmpty else { return [] }

    var actions: [EditorAction] = []

    if !audioClips.isEmpty {
      let oldAudio = audioClips
      let newAudio = VideoEditorTimelineCut.cutAudioClips(oldAudio, removing: spans)
      if newAudio != oldAudio {
        audioClips = newAudio
        if let sel = selectedAudioClipId, !audioClips.contains(where: { $0.id == sel }) {
          selectedAudioClipId = nil
        }
        selectedAudioClipIds = selectedAudioClipIds.intersection(Set(audioClips.map(\.id)))
        actions.append(.replaceAudioClips(old: oldAudio, new: newAudio))
      }
    }

    let newDuration = max(
      VideoEditorTextOverlay.minDuration,
      max(TimelineSequence.duration(clips), maxAudioTimelineEnd)
    )

    if !textOverlays.isEmpty {
      let oldText = textOverlays
      let newText = VideoEditorTimelineTextCut.cutTextOverlays(oldText, removing: spans)
        .map { $0.clamped(to: newDuration) }
      if newText != oldText {
        textOverlays = newText
        if let sel = selectedTextOverlayId, !textOverlays.contains(where: { $0.id == sel }) {
          selectedTextOverlayId = nil
        }
        selectedTextOverlayIds = selectedTextOverlayIds.intersection(Set(textOverlays.map(\.id)))
        actions.append(.replaceTextOverlays(old: oldText, new: newText))
      }
    }

    if includeZoomAndSpeed, !zoomSegments.isEmpty {
      let oldZooms = zoomSegments
      let newZooms = oldZooms.compactMap { seg -> ZoomSegment? in
        guard let range = VideoEditorTimelineCut.shifted(
          start: seg.startTime,
          end: seg.endTime,
          removing: spans,
          minDuration: ZoomSegment.minDuration
        ) else {
          return nil
        }
        var shifted = seg
        shifted.startTime = max(0, range.lowerBound)
        shifted.duration = max(ZoomSegment.minDuration, range.upperBound - range.lowerBound)
        return shifted
      }
      if newZooms != oldZooms {
        zoomSegments = newZooms
        if let selectedZoomId, !newZooms.contains(where: { $0.id == selectedZoomId }) {
          self.selectedZoomId = nil
        }
        actions.append(.replaceZooms(old: oldZooms, new: newZooms))
      }
    }

    if includeZoomAndSpeed, !speedSegments.isEmpty {
      let oldSpeeds = speedSegments
      let newSpeeds = oldSpeeds.compactMap { seg -> SpeedSegment? in
        guard let range = VideoEditorTimelineCut.shifted(
          start: seg.startTime,
          end: seg.endTime,
          removing: spans,
          minDuration: SpeedSegment.minDuration
        ) else {
          return nil
        }
        var shifted = seg
        shifted.startTime = max(0, range.lowerBound)
        shifted.duration = max(SpeedSegment.minDuration, range.upperBound - range.lowerBound)
        return shifted
      }
      if newSpeeds != oldSpeeds {
        speedSegments = newSpeeds
        if let selectedSpeedId, !newSpeeds.contains(where: { $0.id == selectedSpeedId }) {
          self.selectedSpeedId = nil
        }
        scheduleSpeedPreviewRebuild()
        actions.append(.replaceSpeeds(old: oldSpeeds, new: newSpeeds))
      }
    }

    if !timelineBookmarks.isEmpty {
      let oldBookmarks = timelineBookmarks
      let timelineCeiling = max(TimelineSequence.duration(clips), maxAudioTimelineEnd)
      var shiftedBookmarks: [TimeInterval] = []
      for mark in oldBookmarks {
        let insideRemoved = spans.contains { span in
          mark > span.lowerBound + 0.0001 && mark < span.upperBound - 0.0001
        }
        guard !insideRemoved else { continue }
        let landed = min(max(0, VideoEditorTimelineCut.shifted(mark, removing: spans)), timelineCeiling)
        if let prev = shiftedBookmarks.last, abs(landed - prev) < 0.01 {
          continue
        }
        shiftedBookmarks.append(landed)
      }
      shiftedBookmarks.sort()
      if shiftedBookmarks != oldBookmarks {
        timelineBookmarks = shiftedBookmarks
        actions.append(.replaceTimelineBookmarks(old: oldBookmarks, new: shiftedBookmarks))
      }
    }

    return actions
  }

  /// Replace `clips` from feature extensions (Detach Audio, Close Gap, Transitions) while
  /// keeping `clips` `private(set)` and guaranteeing Undo + audio/preview synchronization.
  func applyClipsReplacing(_ updated: [TimelineClip], recordUndo: Bool = true) {
    guard updated != clips else { return }
    let oldClips = clips
    let closedSpans = VideoEditorTimelineTextCut.collapsedGapSpans(from: oldClips, to: updated)
    clips = updated
    var actions: [EditorAction] = [.replaceClips(old: oldClips, new: updated)]
    if !closedSpans.isEmpty {
      actions.append(contentsOf: applyTimelineRipple(removing: closedSpans, includeZoomAndSpeed: true))
    }
    if recordUndo {
      recordAction(actions.count == 1 ? actions[0] : .group(actions))
    }
    syncPlayerAudioWithExportSettings()
    refreshPlayerFrameAtPlayhead()
    updateClipActionAvailability()
    updateHasUnsavedChanges()
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
      if let cached = clipAssets[url] {
        return cached
      }
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
    let playheadTime = CMTimeGetSeconds(currentTime)
    if let audioId = selectedAudioClipId {
      _ = splitAudioClip(id: audioId, at: playheadTime)
      return
    }
    let beforeAudio = audioClips
    guard let (_, second) = splitClip(atTimeline: playheadTime) else { return }
    // Cutting a video clip also slices overlapping audio clips at the playhead,
    // grouped into one Undo step so Cmd+Z rejoins both tracks cleanly.
    if splitOverlappingAudioClips(at: playheadTime), let splitVideoAction = undoStack.popLast() {
      undoStack.append(.group([splitVideoAction, .replaceAudioClips(old: beforeAudio, new: audioClips)]))
      updateUndoRedoState()
      syncPlayerAudioWithExportSettings()
    }
    // The playhead sits on the new boundary, which belongs to the second half.
    selectedTextOverlayId = nil
    selectedClipId = second
    updateClipActionAvailability()
  }

  /// Duplicate a video clip immediately after itself on the sequence (with Undo support).
  func duplicateClip(id: UUID) {
    guard !isGIF, let idx = clips.firstIndex(where: { $0.id == id }) else { return }
    let oldClips = clips
    let original = clips[idx]
    let copy = TimelineClip(
      id: UUID(),
      source: original.source,
      sourceDuration: original.sourceDuration,
      sourceStart: original.sourceStart,
      sourceEnd: original.sourceEnd,
      slotStart: original.sourceStart,
      slotEnd: original.sourceEnd,
      leadingGap: 0
    )
    var updated = clips
    // Compact trailing unused slot on the original so the copy lands flush after its visible edge.
    if original.slotEnd > original.sourceEnd + 0.0001 {
      updated[idx] = TimelineClip(
        id: original.id,
        source: original.source,
        sourceDuration: original.sourceDuration,
        sourceStart: original.sourceStart,
        sourceEnd: original.sourceEnd,
        slotStart: original.slotStart,
        slotEnd: original.sourceEnd,
        leadingGap: original.leadingGap,
        isAudioDetached: original.isAudioDetached,
        leadingTransition: original.leadingTransition
      )
    }
    updated.insert(copy, at: idx + 1)
    clips = updated
    selectedClipId = copy.id
    recordAction(.replaceClips(old: oldClips, new: updated))
    syncPlayerAudioWithExportSettings()
    updateClipActionAvailability()
    updateHasUnsavedChanges()
  }

  /// Split the clip playing at a structural timeline time. Returns the ids of the
  /// two halves, or nil when the time is not over active material or a half would
  /// be shorter than `TimelineClip.minDuration`.
  @discardableResult
  func splitClip(atTimeline t: TimeInterval) -> (first: UUID, second: UUID)? {
    guard !isGIF else { return nil }
    guard let placement = TimelineSequence.activePlacement(at: t, in: placements) else { return nil }

    let original = placement.clip
    let cutPoint = placement.sourceTime(at: t)
    guard cutPoint - original.sourceStart >= TimelineClip.minDuration,
          original.sourceEnd - cutPoint >= TimelineClip.minDuration
    else { return nil }

    let first = TimelineClip(
      source: original.source,
      sourceDuration: original.sourceDuration,
      sourceStart: original.sourceStart,
      sourceEnd: cutPoint,
      slotStart: original.slotStart,
      slotEnd: cutPoint,
      leadingGap: original.leadingGap,
      isAudioDetached: original.isAudioDetached,
      leadingTransition: original.leadingTransition
    )
    let second = TimelineClip(
      source: original.source,
      sourceDuration: original.sourceDuration,
      sourceStart: cutPoint,
      sourceEnd: original.sourceEnd,
      slotStart: cutPoint,
      slotEnd: original.slotEnd,
      leadingGap: 0,
      isAudioDetached: original.isAudioDetached,
      leadingTransition: nil
    )

    DiagnosticLogger.shared.log(.debug, .editor, "Split clip", context: [
      "at": String(format: "%.2f", t),
      "source": String(format: "%.2f", cutPoint),
    ])

    clips.replaceSubrange(placement.index ... placement.index, with: [first, second])
    recordAction(.splitClip(original: original, index: placement.index, first: first, second: second))
    if selectedClipId == original.id {
      selectedClipId = second.id
    }
    syncPlayerAudioWithExportSettings()
    updateClipActionAvailability()
    return (first.id, second.id)
  }

  // MARK: Cut range (ripple)

  /// Remove a structural timeline range from the sequence in one step; everything
  /// after it slides left. Returns the structural spans that were removed (the
  /// range, plus slivers too short to keep), or nil when nothing would be left.
  /// Zoom and speed blocks are not moved here: callers decide whether to shift them.
  @discardableResult
  func cutTimeline(range: ClosedRange<TimeInterval>) -> [ClosedRange<TimeInterval>]? {
    guard !isGIF, let result = VideoEditorTimelineCut.cut(clips, range: range),
          !result.removed.isEmpty else { return nil }
    let old = clips
    clips = result.clips
    var actions: [EditorAction] = [.replaceClips(old: old, new: result.clips)]
    actions.append(contentsOf: applyTimelineRipple(removing: result.removed, includeZoomAndSpeed: false))
    recordAction(actions.count == 1 ? actions[0] : .group(actions))
    if let selectedClipId, !clips.contains(where: { $0.id == selectedClipId }) {
      self.selectedClipId = nil
    }
    let landing = min(range.lowerBound, CMTimeGetSeconds(timelineDuration))
    seek(to: CMTime(seconds: max(0, landing), preferredTimescale: 600))
    syncPlayerAudioWithExportSettings()
    updateClipActionAvailability()
    return result.removed
  }

  // MARK: Delete (ripple)

  /// Remove a clip; everything after it slides left to close the gap.
  func removeClip(id: UUID) {
    guard !isGIF else { return }
    guard clips.count > 1 else { return } // never leave an empty timeline
    guard let index = clips.firstIndex(where: { $0.id == id }) else { return }

    let clip = clips[index]
    let oldPlacements = placements
    let gapStart = sequenceStart(ofClip: id) ?? 0
    clips.remove(at: index)
    var actions: [EditorAction] = [.removeClip(clip: clip, index: index)]
    if let removedPlacement = oldPlacements.first(where: { $0.clip.id == id }) {
      let spanStart = max(0, removedPlacement.start - max(0, removedPlacement.clip.leadingGap))
      let removedSpan = spanStart ... removedPlacement.end
      actions.append(contentsOf: applyTimelineRipple(removing: [removedSpan], includeZoomAndSpeed: true))
    }
    recordAction(actions.count == 1 ? actions[0] : .group(actions))

    DiagnosticLogger.shared.log(.debug, .editor, "Removed clip", context: [
      "index": "\(index)",
      "duration": String(format: "%.2fs", clip.duration),
    ])

    // Select the clip that slid into the gap (clearing any audio selection) and park
    // the playhead inside active video material so deleting the trailing clip never
    // strands the preview on a black frame at the exact exclusive end edge.
    selectedAudioClipId = nil
    selectedClipId = clips.indices.contains(index) ? clips[index].id : clips.last?.id
    let landing: TimeInterval = if clips.indices.contains(index),
                                   let placement = placementForClip(clips[index].id) {
      placement.activeStart
    } else if let lastPlacement = placements.last(where: { $0.activeEnd > $0.activeStart }) {
      max(lastPlacement.activeStart, lastPlacement.activeEnd - 0.02)
    } else {
      min(gapStart, CMTimeGetSeconds(timelineDuration))
    }
    seek(to: CMTime(seconds: max(0, landing), preferredTimescale: 600))
    syncPlayerAudioWithExportSettings()
    updateClipActionAvailability()
  }

  /// Delete the selected clip, falling back to the one under the playhead.
  func deleteSelectedClip() {
    guard let clip = targetClip else { return }
    removeClip(id: clip.id)
  }

  // MARK: Move (reorder & free timeline positioning)

  /// Reorder a clip to an absolute index. Neighbours shift to close the gap, so the
  /// sequence stays gapless.
  func moveClip(id: UUID, toIndex: Int) {
    guard !isGIF else { return }
    guard let from = clips.firstIndex(where: { $0.id == id }) else { return }
    let target = max(0, min(toIndex, clips.count - 1))
    guard target != from else { return }

    if hasVideoGaps {
      let oldClips = clips
      var updated = clips
      var clip = updated.remove(at: from)
      clip.leadingGap = 0
      updated.insert(clip, at: target)
      clips = updated
      recordAction(.replaceClips(old: oldClips, new: updated))
    } else {
      let clip = clips.remove(at: from)
      clips.insert(clip, at: target)
      recordAction(.moveClip(id: id, fromIndex: from, toIndex: target))
    }
    syncPlayerAudioWithExportSettings()
    updateClipActionAvailability()
  }

  /// Nudge a clip one slot left or right.
  func moveClip(id: UUID, by delta: Int) {
    guard let from = clips.firstIndex(where: { $0.id == id }) else { return }
    moveClip(id: id, toIndex: from + delta)
  }

  /// Move a clip horizontally on the timeline axis to `targetStart` (active visual start)
  /// without overlapping neighbours or shifting subsequent clips.
  func moveClipOnTimeline(id: UUID, toActiveStart targetStart: TimeInterval) {
    guard !isGIF, targetStart.isFinite else { return }
    let oldPlacements = placements
    guard let idx = oldPlacements.firstIndex(where: { $0.clip.id == id }) else { return }

    let clip = clips[idx]
    let clipDuration = clip.duration
    let prevActiveEnd = idx > 0 ? oldPlacements[idx - 1].activeEnd : 0
    let nextActiveStart = (idx + 1 < oldPlacements.count) ? oldPlacements[idx + 1].activeStart : nil

    var clampedStart = max(prevActiveEnd, targetStart)
    if let nextActiveStart {
      let maxStart = max(prevActiveEnd, nextActiveStart - clipDuration)
      clampedStart = min(clampedStart, maxStart)
    }

    var updated = clips
    var prevStructuralEnd: TimeInterval = 0
    if idx > 0 {
      let prevPlacement = oldPlacements[idx - 1]
      if prevPlacement.end > clampedStart + 0.0001 {
        let prevClip = updated[idx - 1]
        updated[idx - 1] = TimelineClip(
          id: prevClip.id,
          source: prevClip.source,
          sourceDuration: prevClip.sourceDuration,
          sourceStart: prevClip.sourceStart,
          sourceEnd: prevClip.sourceEnd,
          slotStart: prevClip.slotStart,
          slotEnd: prevClip.sourceEnd,
          leadingGap: prevClip.leadingGap,
          isAudioDetached: prevClip.isAudioDetached,
          leadingTransition: prevClip.leadingTransition
        )
        prevStructuralEnd = prevActiveEnd
      } else {
        prevStructuralEnd = prevPlacement.end
      }
    }

    let newLeadingGap = max(0, clampedStart - prevStructuralEnd)
    updated[idx] = TimelineClip(
      id: clip.id,
      source: clip.source,
      sourceDuration: clip.sourceDuration,
      sourceStart: clip.sourceStart,
      sourceEnd: clip.sourceEnd,
      slotStart: clip.sourceStart,
      slotEnd: clip.sourceEnd,
      leadingGap: newLeadingGap,
      isAudioDetached: clip.isAudioDetached,
      leadingTransition: newLeadingGap > 0.05 ? nil : clip.leadingTransition
    )

    if let nextActiveStart, idx + 1 < updated.count {
      let newStructuralEnd = clampedStart + clipDuration
      let nextClip = updated[idx + 1]
      let nextLeadingSlot = max(0, nextClip.sourceStart - nextClip.slotStart)
      if newStructuralEnd + nextLeadingSlot > nextActiveStart + 0.0001 {
        let nextGap = max(0, nextActiveStart - newStructuralEnd)
        updated[idx + 1] = TimelineClip(
          id: nextClip.id,
          source: nextClip.source,
          sourceDuration: nextClip.sourceDuration,
          sourceStart: nextClip.sourceStart,
          sourceEnd: nextClip.sourceEnd,
          slotStart: nextClip.sourceStart,
          slotEnd: nextClip.slotEnd,
          leadingGap: nextGap,
          isAudioDetached: nextClip.isAudioDetached,
          leadingTransition: nextGap > 0.05 ? nil : nextClip.leadingTransition
        )
      } else {
        var adjustedNext = nextClip
        adjustedNext.leadingGap = max(0, nextActiveStart - newStructuralEnd - nextLeadingSlot)
        if adjustedNext.leadingGap > 0.05 {
          adjustedNext.leadingTransition = nil
        }
        updated[idx + 1] = adjustedNext
      }
    }

    guard updated != clips else { return }
    let oldClips = clips
    clips = updated
    recordAction(.replaceClips(old: oldClips, new: updated))
    syncPlayerAudioWithExportSettings()
    updateClipActionAvailability()
    updateHasUnsavedChanges()
  }

  // MARK: Trim (non-destructive)

  /// Adjust a clip's in/out points within its own source asset.
  ///
  /// Preserves the clip's `leadingGap` and allows non-destructive re-extension into
  /// adjacent empty timeline gaps (or past the end of the last clip up to `sourceDuration`).
  func updateClip(id: UUID, sourceStart: TimeInterval? = nil, sourceEnd: TimeInterval? = nil) {
    guard let index = clips.firstIndex(where: { $0.id == id }) else { return }
    let oldClips = clips
    let old = clips[index]
    guard sourceStart != nil || sourceEnd != nil else { return }

    var newStart = sourceStart ?? old.sourceStart
    var newEnd = sourceEnd ?? old.sourceEnd
    var newSlotStart = old.slotStart
    var newSlotEnd = old.slotEnd
    var newLeadingGap = old.leadingGap
    var updated = clips

    if sourceStart != nil {
      let minAllowedStart = max(0, old.slotStart - old.leadingGap)
      newStart = max(minAllowedStart, min(newStart, newEnd - TimelineClip.minDuration))
      if newStart < old.slotStart {
        let extended = old.slotStart - newStart
        newSlotStart = newStart
        newLeadingGap = max(0, old.leadingGap - extended)
      }
    }
    if sourceEnd != nil {
      let extraRightRoom: TimeInterval = (index + 1 < clips.count)
        ? max(0, clips[index + 1].leadingGap)
        : max(0, old.sourceDuration - old.slotEnd)
      let maxAllowedEnd = min(old.sourceDuration, old.slotEnd + extraRightRoom)
      newEnd = min(maxAllowedEnd, max(newEnd, newStart + TimelineClip.minDuration))
      if newEnd > old.slotEnd {
        let extended = newEnd - old.slotEnd
        newSlotEnd = newEnd
        if index + 1 < updated.count {
          var nextClip = updated[index + 1]
          nextClip.leadingGap = max(0, nextClip.leadingGap - extended)
          updated[index + 1] = nextClip
        }
      }
    }

    let new = TimelineClip(
      id: old.id,
      source: old.source,
      sourceDuration: old.sourceDuration,
      sourceStart: newStart,
      sourceEnd: newEnd,
      slotStart: newSlotStart,
      slotEnd: newSlotEnd,
      leadingGap: newLeadingGap,
      isAudioDetached: old.isAudioDetached,
      leadingTransition: old.leadingTransition
    )
    updated[index] = new
    guard updated != oldClips else { return }
    clips = updated

    // A drag records one entry when it ends, not one per gesture tick.
    if clipTrimOriginalClips == nil {
      if updated.count == oldClips.count,
         (0 ..< updated.count).filter({ updated[$0] != oldClips[$0] }).count == 1 {
        recordAction(.updateClip(old: old, new: new))
      } else {
        recordAction(.replaceClips(old: oldClips, new: updated))
      }
      syncPlayerAudioWithExportSettings()
    }
    updateClipActionAvailability()
  }

  /// Start a trim drag. Captures the pre-drag sequence so the gesture collapses into a
  /// single undo entry.
  ///
  /// Like a speed drag, a trim holds the speed preview rebuild until release: otherwise
  /// every mouse event cancels and restarts the composition build and reparks the player.
  func beginClipTrim(id _: UUID) {
    clipTrimOriginalClips = clips
    beginSpeedTrackDrag()
  }

  func endClipTrim() {
    defer {
      clipTrimOriginalClips = nil
      endSpeedTrackDrag()
    }
    guard let oldClips = clipTrimOriginalClips, clips != oldClips else { return }
    let changedIndices = (0 ..< min(oldClips.count, clips.count)).filter { oldClips[$0] != clips[$0] }
    if oldClips.count == clips.count, changedIndices.count == 1, let idx = changedIndices.first {
      recordAction(.updateClip(old: oldClips[idx], new: clips[idx]))
    } else {
      recordAction(.replaceClips(old: oldClips, new: clips))
    }
    syncPlayerAudioWithExportSettings()
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

  /// Runs on every playback tick and scrub event. `@Published` notifies on every
  /// assignment, equal or not, so write only real changes: an unconditional write here
  /// re-renders every view observing the whole editor state ~30×/s while playing.
  func updateClipActionAvailability() {
    let t = CMTimeGetSeconds(currentTime)
    let canSplit: Bool
    let canDelete: Bool
    let canTrimLeft: Bool
    let canTrimRight: Bool
    let hasBookmark: Bool

    if isGIF {
      canSplit = false
      canDelete = false
      canTrimLeft = false
      canTrimRight = false
      hasBookmark = false
    } else {
      if let textId = selectedTextOverlayId,
         textOverlays.contains(where: { $0.id == textId }) {
        // Keep video Split available at the playhead even while a Text Overlay is selected
        // so scrubbing elsewhere and pressing S splits the video clip immediately.
        if let placement = activePlacement {
          let cutPoint = placement.sourceTime(at: t)
          canSplit = cutPoint - placement.clip.sourceStart >= TimelineClip.minDuration
            && placement.clip.sourceEnd - cutPoint >= TimelineClip.minDuration
        } else {
          canSplit = false
        }
        canDelete = true
        canTrimLeft = false
        canTrimRight = false
      } else if let audioId = selectedAudioClipId,
                let audioClip = audioClips.first(where: { $0.id == audioId }) {
        canSplit = audioClip.split(at: t) != nil
        canDelete = true
        canTrimLeft = t > audioClip.timelineStart + 0.02 && t < audioClip.timelineEnd - AudioTimelineClip.minDuration
        canTrimRight = t > audioClip.timelineStart + AudioTimelineClip.minDuration && t < audioClip.timelineEnd - 0.02
      } else {
        if let placement = activePlacement {
          let cutPoint = placement.sourceTime(at: t)
          canSplit = cutPoint - placement.clip.sourceStart >= TimelineClip.minDuration
            && placement.clip.sourceEnd - cutPoint >= TimelineClip.minDuration
        } else {
          canSplit = false
        }
        canDelete = clips.count > 1 && targetClip != nil
        if let clipId = selectedClipId,
           let placement = placements.first(where: { $0.clip.id == clipId }) {
          canTrimLeft = t > placement.activeStart + 0.02 && t < placement.activeEnd - TimelineClip.minDuration
          canTrimRight = t > placement.activeStart + TimelineClip.minDuration && t < placement.activeEnd - 0.02
        } else {
          canTrimLeft = false
          canTrimRight = false
        }
      }
      hasBookmark = timelineBookmarks.contains { abs($0 - t) < 0.15 }
    }

    if canSplitAtPlayhead != canSplit {
      canSplitAtPlayhead = canSplit
    }
    if canDeleteSelectedClip != canDelete {
      canDeleteSelectedClip = canDelete
    }
    if canTrimLeftAtPlayhead != canTrimLeft {
      canTrimLeftAtPlayhead = canTrimLeft
    }
    if canTrimRightAtPlayhead != canTrimRight {
      canTrimRightAtPlayhead = canTrimRight
    }
    if hasBookmarkAtPlayhead != hasBookmark {
      hasBookmarkAtPlayhead = hasBookmark
    }
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
    if isLeftSidebarVisible, leftSidebarPanel == panel {
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

  /// `updateExportSettings` with an undo entry (agent edits; the panels stay as they were).
  func updateExportSettingsRecordingUndo(_ settings: ExportSettings) {
    let old = exportSettings
    guard settings != old else { return }
    updateExportSettings(settings)
    recordAction(.updateExportSettings(old: old, new: settings))
  }

  // MARK: - Frame (background) settings

  var frameSettings: VideoEditorFrameSettings {
    VideoEditorFrameSettings(
      style: backgroundStyle,
      padding: backgroundPadding,
      shadowIntensity: backgroundShadowIntensity,
      cornerRadius: backgroundCornerRadius,
      alignment: backgroundAlignment,
      aspectRatio: backgroundAspectRatio
    )
  }

  // MARK: - Cursor settings

  /// Apply cursor settings. `recordUndo: false` for live slider drags; commit the drag
  /// with `commitCursorSettings(from:)` so it lands as one undo step.
  func setCursorSettings(_ settings: VideoEditorCursorSettings, recordUndo: Bool = true) {
    let old = cursorSettings
    guard settings != old else { return }
    applyCursorSettings(settings)
    if recordUndo {
      recordAction(.updateCursor(old: old, new: settings))
    }
  }

  func commitCursorSettings(from old: VideoEditorCursorSettings) {
    guard old != cursorSettings else { return }
    recordAction(.updateCursor(old: old, new: cursorSettings))
  }

  private func applyCursorSettings(_ settings: VideoEditorCursorSettings) {
    cursorSettings = settings
    // Same recording, new settings: reuse the resolver's smoothed path and activity
    // times when possible (slider ticks land here).
    if let resolver = cursorResolver {
      cursorResolver = resolver.updating(settings: settings)
    } else {
      rebuildCursorResolver()
    }
    updateHasUnsavedChanges()
  }

  func setCameraSettings(_ settings: VideoEditorCameraSettings, recordUndo: Bool = true) {
    let old = cameraSettings
    guard settings != old else { return }
    applyCameraSettings(settings)
    if recordUndo {
      recordAction(.updateCamera(old: old, new: settings))
    }
  }

  func commitCameraSettings(from old: VideoEditorCameraSettings) {
    guard old != cameraSettings else { return }
    recordAction(.updateCamera(old: old, new: cameraSettings))
  }

  private func applyCameraSettings(_ settings: VideoEditorCameraSettings) {
    cameraSettings = settings
    updateHasUnsavedChanges()
  }

  /// Cursor, camera and captions saved with the session become the clean baseline.
  private func restoreStudioLayers(from sessionData: VideoEditorSessionData) {
    if let cursor = sessionData.cursorSettings {
      cursorSettings = cursor
      initialCursorSettings = cursor
      rebuildCursorResolver()
    }
    if let camera = sessionData.cameraSettings {
      cameraSettings = camera
      initialCameraSettings = camera
      didSeedCameraSettings = true
    }
    if let captions = sessionData.captions, !isGIF {
      self.captions = captions
    }
    if let motionBlur = sessionData.motionBlurSettings {
      motionBlurSettings = motionBlur
      initialMotionBlurSettings = motionBlur
    }
  }

  // MARK: - Motion Blur & Smart Auto-Zoom

  func setMotionBlurSettings(_ settings: VideoEditorMotionBlurSettings, recordUndo: Bool = true) {
    let old = motionBlurSettings
    guard settings != old else { return }
    applyMotionBlurSettings(settings)
    if recordUndo {
      recordAction(.updateMotionBlur(old: old, new: settings))
    }
  }

  func commitMotionBlurSettings(from old: VideoEditorMotionBlurSettings) {
    guard old != motionBlurSettings else { return }
    recordAction(.updateMotionBlur(old: old, new: motionBlurSettings))
  }

  private func applyMotionBlurSettings(_ settings: VideoEditorMotionBlurSettings) {
    motionBlurSettings = settings
    updateHasUnsavedChanges()
  }

  /// How Smart Auto-Zoom results are combined with existing timeline zoom segments.
  enum SmartAutoZoomMergePolicy: Equatable, Sendable {
    /// Keep all manual and regular auto zooms, replace only prior Smart Auto-Zooms,
    /// and drop generated segments that overlap kept user zooms.
    case fillGaps
    /// Replace every existing zoom segment when the generated plan is non-empty.
    case replaceAll
  }

  /// Shifts or linearly rescales source-time `smartKeyframes` when a Smart Auto-Zoom segment
  /// is dragged or resized on the structural timeline, preventing the camera from clamping to
  /// stale keyframe bounds. Returns `nil` (falling back to cursor-follow) if the new position
  /// does not land on a primary recording clip.
  static func remapSmartKeyframes(
    _ keyframes: [AutoFocusCameraSample],
    fromOldRange oldRange: ClosedRange<TimeInterval>,
    toNewRange newRange: ClosedRange<TimeInterval>,
    placements: [TimelineSequence.Placement]
  ) -> [AutoFocusCameraSample]? {
    guard !keyframes.isEmpty else { return nil }

    func primarySourceTime(at sequenceTime: TimeInterval) -> TimeInterval? {
      if let exact = placements.first(where: {
        $0.clip.isPrimary && sequenceTime >= $0.start && sequenceTime <= $0.end
      }) {
        return exact.sourceTime(at: sequenceTime)
      }
      return nil
    }

    guard let oldSourceStart = primarySourceTime(at: oldRange.lowerBound),
          let newSourceStart = primarySourceTime(at: newRange.lowerBound)
    else {
      return nil
    }

    let oldDuration = oldRange.upperBound - oldRange.lowerBound
    let newDuration = newRange.upperBound - newRange.lowerBound

    if abs(newDuration - oldDuration) < 0.001 {
      let sourceDelta = newSourceStart - oldSourceStart
      return keyframes.map { sample in
        AutoFocusCameraSample(
          time: max(0, sample.time + sourceDelta),
          center: sample.center,
          zoomMultiplier: sample.zoomMultiplier
        )
      }
    }

    guard let oldSourceEnd = primarySourceTime(at: oldRange.upperBound),
          let newSourceEnd = primarySourceTime(at: newRange.upperBound)
    else {
      return nil
    }
    let oldSourceSpan = oldSourceEnd - oldSourceStart
    let newSourceSpan = newSourceEnd - newSourceStart
    guard oldSourceSpan > 0.001, newSourceSpan > 0.001 else { return nil }

    return keyframes.map { sample in
      let u = (sample.time - oldSourceStart) / oldSourceSpan
      let remappedTime = max(0, newSourceStart + u * newSourceSpan)
      return AutoFocusCameraSample(
        time: remappedTime,
        center: sample.center,
        zoomMultiplier: sample.zoomMultiplier
      )
    }
  }

  /// Filters recording metadata so clicks inside trimmed-out or deleted primary clip ranges
  /// never trigger phantom Smart Auto-Zooms.
  static func activeTimelineMetadata(
    from metadata: RecordingMetadata,
    placements: [TimelineSequence.Placement]
  ) -> RecordingMetadata {
    let activeRanges = placements
      .filter { $0.clip.isPrimary && $0.clip.sourceEnd > $0.clip.sourceStart }
      .map { $0.clip.sourceStart ... $0.clip.sourceEnd }
    guard !activeRanges.isEmpty, var capture = metadata.cursorCapture else {
      return metadata
    }
    capture.clicks = capture.clicks.filter { click in
      activeRanges.contains { $0.contains(click.time) }
    }
    var filtered = metadata
    filtered.cursorCapture = capture
    return filtered
  }

  /// Projects source-time Smart Auto-Zoom segments onto the current primary clip placements.
  /// Consecutive primary clips (such as a clip split with `S` or trimmed at a cut) coalesce into
  /// a single continuous `ZoomSegment` so the camera never double-zooms across a split seam, while
  /// segments spanning across an inserted external clip split cleanly around it.
  static func mapSmartSegments(
    _ sourceSegments: [ZoomSegment],
    onto placements: [TimelineSequence.Placement],
    timelineDuration: TimeInterval
  ) -> [ZoomSegment] {
    guard timelineDuration > 0 else { return [] }
    let primaryPlacements = placements.filter(\.clip.isPrimary)
    guard !primaryPlacements.isEmpty else { return [] }

    var mappedSegments: [ZoomSegment] = []
    for segment in sourceSegments {
      let overlapping = primaryPlacements.filter {
        segment.startTime < $0.clip.sourceEnd && segment.endTime > $0.clip.sourceStart
      }
      guard !overlapping.isEmpty else { continue }

      // Group overlapping primary placements into contiguous primary runs (no inserted
      // non-primary `.file` clip in between and no large > 2.5s deleted source jump).
      var runs: [[TimelineSequence.Placement]] = []
      for placement in overlapping {
        if var currentRun = runs.last,
           let previous = currentRun.last,
           placement.index == previous.index + 1,
           abs(placement.clip.sourceStart - previous.clip.sourceEnd) <= 2.5 {
          currentRun.append(placement)
          runs[runs.count - 1] = currentRun
        } else {
          runs.append([placement])
        }
      }

      for run in runs {
        guard let firstPlacement = run.first, let lastPlacement = run.last else { continue }
        let clippedStart = max(segment.startTime, firstPlacement.clip.sourceStart)
        let clippedEnd = min(segment.endTime, lastPlacement.clip.sourceEnd)
        guard clippedEnd > clippedStart else { continue }

        let mappedStart = firstPlacement.sequenceTime(atSource: clippedStart)
        let mappedEnd = lastPlacement.sequenceTime(atSource: clippedEnd)
        let mappedDuration = mappedEnd - mappedStart
        guard mappedDuration >= ZoomSegment.minDuration else { continue }

        let clippedKeyframes = segment.smartKeyframes.map {
          clipSmartKeyframes($0, to: clippedStart ... clippedEnd)
        }
        let mapped = ZoomSegment(
          id: UUID(),
          startTime: mappedStart,
          duration: mappedDuration,
          zoomLevel: segment.zoomLevel,
          zoomCenter: segment.zoomCenter,
          zoomType: segment.zoomType,
          followSpeed: segment.followSpeed,
          focusMargin: segment.focusMargin,
          isEnabled: segment.isEnabled,
          smartKeyframes: clippedKeyframes
        )
        mappedSegments.append(mapped.clamped(to: timelineDuration))
      }
    }

    return mappedSegments.sorted { $0.startTime < $1.startTime }
  }

  /// Merges generated Smart Auto-Zoom segments with existing timeline zooms according to `policy`.
  /// An empty generated plan is always a no-op so existing user zooms are never wiped.
  static func mergeSmartAutoZoomSegments(
    existing: [ZoomSegment],
    generated: [ZoomSegment],
    policy: SmartAutoZoomMergePolicy
  ) -> [ZoomSegment] {
    guard !generated.isEmpty else { return existing }

    switch policy {
    case .replaceAll:
      return generated.sorted { $0.startTime < $1.startTime }
    case .fillGaps:
      let preservedUserZooms = existing.filter { !$0.isSmartAutoZoom }
      let nonOverlappingGenerated = generated.filter { candidate in
        !preservedUserZooms.contains { userZoom in
          candidate.startTime < userZoom.endTime && candidate.endTime > userZoom.startTime
        }
      }
      // Nothing fits in the open gaps: keep the timeline as-is (prior smart zooms included)
      // so the caller reports "No actions detected" instead of silently dropping zooms.
      guard !nonOverlappingGenerated.isEmpty else { return existing }
      return (preservedUserZooms + nonOverlappingGenerated).sorted { $0.startTime < $1.startTime }
    }
  }

  private static func clipSmartKeyframes(
    _ keyframes: [AutoFocusCameraSample],
    to sourceRange: ClosedRange<TimeInterval>
  ) -> [AutoFocusCameraSample] {
    let sorted = keyframes.sorted { $0.time < $1.time }
    guard !sorted.isEmpty else { return [] }
    guard let first = sorted.first, let last = sorted.last else { return [] }
    if first.time >= sourceRange.lowerBound, last.time <= sourceRange.upperBound {
      return sorted
    }

    func interpolatedSample(at time: TimeInterval) -> AutoFocusCameraSample {
      if time <= first.time {
        return AutoFocusCameraSample(time: time, center: first.center, zoomMultiplier: first.zoomMultiplier)
      }
      if time >= last.time {
        return AutoFocusCameraSample(time: time, center: last.center, zoomMultiplier: last.zoomMultiplier)
      }
      var low = 0
      var high = sorted.count - 1
      while low + 1 < high {
        let mid = (low + high) / 2
        if sorted[mid].time <= time {
          low = mid
        } else {
          high = mid
        }
      }
      let a = sorted[low]
      let b = sorted[high]
      let span = max(b.time - a.time, 0.0001)
      let t = CGFloat(min(max((time - a.time) / span, 0), 1))
      return AutoFocusCameraSample(
        time: time,
        center: CGPoint(
          x: a.center.x + (b.center.x - a.center.x) * t,
          y: a.center.y + (b.center.y - a.center.y) * t
        ),
        zoomMultiplier: a.zoomMultiplier + (b.zoomMultiplier - a.zoomMultiplier) * t
      )
    }

    var clipped: [AutoFocusCameraSample] = [interpolatedSample(at: sourceRange.lowerBound)]
    for sample in sorted
      where sample.time > sourceRange.lowerBound + 0.0005 && sample.time < sourceRange.upperBound - 0.0005 {
      clipped.append(sample)
    }
    clipped.append(interpolatedSample(at: sourceRange.upperBound))
    return clipped
  }

  /// Entry point for UI actions (sidebar button and timeline context menu).
  /// Prompts for confirmation when user-authored zooms already exist; otherwise runs directly.
  func requestSmartAutoZoom(style: SmartAutoZoomStyle? = nil) {
    guard !isGIF, !isPerformanceWorkClosed, recordingMetadata != nil else { return }
    let chosenStyle = style ?? smartAutoZoomStyle
    smartAutoZoomStyle = chosenStyle
    smartAutoZoomNotice = nil

    if hasUserZoomSegments {
      pendingSmartAutoZoomStyle = chosenStyle
      showSmartAutoZoomConfirmation = true
    } else {
      generateSmartAutoZoom(style: chosenStyle, policy: .fillGaps)
    }
  }

  /// Confirms a pending Smart Auto-Zoom prompt with the user's chosen merge policy.
  func confirmSmartAutoZoom(policy: SmartAutoZoomMergePolicy) {
    let style = pendingSmartAutoZoomStyle ?? smartAutoZoomStyle
    pendingSmartAutoZoomStyle = nil
    showSmartAutoZoomConfirmation = false
    generateSmartAutoZoom(style: style, policy: policy)
  }

  /// Cancels a pending Smart Auto-Zoom confirmation prompt.
  func cancelSmartAutoZoomConfirmation() {
    pendingSmartAutoZoomStyle = nil
    showSmartAutoZoomConfirmation = false
  }

  /// Generates intelligent action- and outcome-aware Smart Auto-Zoom segments from
  /// recorded cursor/click telemetry and lightweight video-frame outcome analysis.
  func generateSmartAutoZoom(
    style: SmartAutoZoomStyle? = nil,
    policy: SmartAutoZoomMergePolicy = .fillGaps
  ) {
    guard !isGIF, !isPerformanceWorkClosed, let metadata = recordingMetadata else { return }
    let chosenStyle = style ?? smartAutoZoomStyle
    smartAutoZoomStyle = chosenStyle
    smartAutoZoomTask?.cancel()
    smartAutoZoomNoticeTask?.cancel()
    smartAutoZoomNotice = nil
    isGeneratingSmartAutoZoom = true

    let primaryAsset = asset
    let transition = zoomTransitionDuration
    let startingLayoutRevision = timelineLayoutRevision
    let activeMetadata = Self.activeTimelineMetadata(from: metadata, placements: placements)

    smartAutoZoomTask = Task { [weak self] in
      let analysisTask = Task.detached(priority: .userInitiated) {
        await VideoEditorSmartAutoZoomEngine.generatePlan(
          from: activeMetadata,
          asset: primaryAsset,
          style: chosenStyle,
          transitionDuration: transition
        )
      }
      let plan = await withTaskCancellationHandler {
        await analysisTask.value
      } onCancel: {
        analysisTask.cancel()
      }

      guard !Task.isCancelled, let self, !self.isPerformanceWorkClosed else { return }
      isGeneratingSmartAutoZoom = false

      // Always map against the LIVE timeline placements at apply time (never a stale snapshot
      // captured before async analysis), splitting cleanly across any primary clip cuts.
      let livePlacements = placements
      let liveDuration = CMTimeGetSeconds(timelineDuration)
      let layoutChangedDuringAnalysis = timelineLayoutRevision != startingLayoutRevision

      let mappedSegments = Self.mapSmartSegments(
        plan.segments,
        onto: livePlacements,
        timelineDuration: liveDuration
      )

      // Empty plan must never wipe existing zooms.
      guard !mappedSegments.isEmpty else {
        presentSmartAutoZoomNotice(L10n.VideoEditor.smartAutoZoomNoActionsDetected)
        DiagnosticLogger.shared.log(.info, .editor, "Smart Auto-Zoom found no actions", context: [
          "style": chosenStyle.rawValue,
          "layoutChangedDuringAnalysis": "\(layoutChangedDuringAnalysis)",
        ])
        return
      }

      let oldZooms = zoomSegments
      let mergedZooms = Self.mergeSmartAutoZoomSegments(
        existing: oldZooms,
        generated: mappedSegments,
        policy: policy
      )
      guard mergedZooms != oldZooms else {
        presentSmartAutoZoomNotice(L10n.VideoEditor.smartAutoZoomNoActionsDetected)
        return
      }

      zoomSegments = mergedZooms
      let newlyAddedSmart = mergedZooms.first { $0.isSmartAutoZoom }
      selectedZoomId = newlyAddedSmart?.id ?? mergedZooms.first?.id
      let autoEnabledBlur = oldZooms.isEmpty
        && !mergedZooms.isEmpty
        && !motionBlurSettings.isEnabled
        && motionBlurSettings == initialMotionBlurSettings
      let previousBlur: VideoEditorMotionBlurSettings? = autoEnabledBlur ? motionBlurSettings : nil
      let updatedBlur: VideoEditorMotionBlurSettings? = autoEnabledBlur ? .default : nil
      if let updatedBlur {
        motionBlurSettings = updatedBlur
      }
      recordAction(
        .replaceZooms(
          old: oldZooms,
          new: mergedZooms,
          oldMotionBlur: previousBlur,
          newMotionBlur: updatedBlur
        )
      )

      DiagnosticLogger.shared.log(.info, .editor, "Smart Auto-Zoom generated", context: [
        "style": chosenStyle.rawValue,
        "policy": policy == .fillGaps ? "fillGaps" : "replaceAll",
        "layoutChangedDuringAnalysis": "\(layoutChangedDuringAnalysis)",
        "actions": "\(plan.actionCount)",
        "visualOutcomes": "\(plan.analyzedVisualOutcomes)",
        "segments": "\(mergedZooms.count)",
      ])
    }
  }

  private func presentSmartAutoZoomNotice(_ message: String) {
    smartAutoZoomNoticeTask?.cancel()
    smartAutoZoomNotice = message
    smartAutoZoomNoticeTask = Task { [weak self] in
      try? await Task.sleep(nanoseconds: 4_000_000_000)
      guard !Task.isCancelled, let self, smartAutoZoomNotice == message else { return }
      smartAutoZoomNotice = nil
    }
  }

  private func reloadCameraLayer() {
    guard let source = recordingMetadata?.cameraSource,
          let url = try? RecordingMetadataStore.sidecarURL(named: source.fileName, kind: .camera),
          FileManager.default.fileExists(atPath: url.path)
    else {
      cameraSourceURL = nil
      cameraPreview?.stop()
      cameraPreview = nil
      return
    }
    if cameraSourceURL != url {
      cameraPreview?.stop()
      cameraPreview = VideoEditorCameraPreviewController(url: url)
    }
    cameraSourceURL = url
    // A fresh editor starts from the placement used while recording (once: a later
    // metadata reload or a restored session keeps the user's layout).
    if !didSeedCameraSettings {
      didSeedCameraSettings = true
      let recorded = VideoEditorCameraSettings.recorded(source)
      cameraSettings = recorded
      initialCameraSettings = recorded
    }
  }

  private func reloadCursorLayer() {
    reloadCameraLayer()
    cursorSprites = hasEditableCursor ? VideoEditorCursorSpriteStore
      .load(capture: recordingMetadata?.cursorCapture) : .empty
    rebuildCursorResolver()
  }

  private func rebuildCursorResolver() {
    guard hasEditableCursor, let metadata = recordingMetadata, let capture = metadata.cursorCapture else {
      cursorResolver = nil
      return
    }
    cursorResolver = VideoEditorCursorResolver(
      samples: metadata.mouseSamples,
      capture: capture,
      settings: cursorSettings
    )
  }

  /// Apply background/frame settings as one undoable step.
  func setFrameSettings(_ settings: VideoEditorFrameSettings) {
    let old = frameSettings
    guard settings != old else { return }
    applyFrameSettings(settings)
    recordAction(.updateFrame(old: old, new: settings))
  }

  /// Start a continuous background/frame slider drag so all live ticks collapse into one undo step.
  func beginFrameEdit() {
    guard pendingFrameEditStart == nil else { return }
    pendingFrameEditStart = frameSettings
  }

  /// Commit a continuous background/frame slider drag as a single undoable step.
  func endFrameEdit() {
    guard let start = pendingFrameEditStart else { return }
    pendingFrameEditStart = nil
    let end = frameSettings
    guard end != start else { return }
    recordAction(.updateFrame(old: start, new: end))
  }

  /// Update zoom transition duration as an undoable edit.
  func setZoomTransitionDuration(_ duration: TimeInterval) {
    let old = zoomTransitionDuration
    let clamped = ZoomCalculator.clampTransitionDuration(duration)
    guard abs(clamped - old) > 0.0001 else { return }
    zoomTransitionDuration = clamped
    recordAction(.updateZoomTransitionDuration(old: old, new: clamped))
  }

  private func applyFrameSettings(_ settings: VideoEditorFrameSettings) {
    if backgroundStyle != settings.style {
      backgroundStyle = settings.style
    }
    if backgroundPadding != settings.padding {
      backgroundPadding = settings.padding
    }
    if backgroundShadowIntensity != settings.shadowIntensity {
      backgroundShadowIntensity = settings.shadowIntensity
    }
    if backgroundCornerRadius != settings.cornerRadius {
      backgroundCornerRadius = settings.cornerRadius
    }
    if backgroundAlignment != settings.alignment {
      backgroundAlignment = settings.alignment
    }
    if backgroundAspectRatio != settings.aspectRatio {
      backgroundAspectRatio = settings.aspectRatio
    }
  }

  /// Recalculate estimated file size based on current settings
  func recalculateEstimatedFileSize(immediate: Bool = false) {
    guard !isPerformanceWorkClosed else { return }
    estimateRevision &+= 1
    let revision = estimateRevision
    estimateTask?.cancel()
    estimateTask = Task { [weak self] in
      if !immediate {
        do { try await Task.sleep(nanoseconds: 100_000_000) } catch { return }
      }
      guard !Task.isCancelled, let self else { return }
      if cachedSourceFileSize == nil {
        if sourceSizeTask == nil {
          let access = SandboxFileAccessManager.shared.beginAccessingURL(sourceURL)
          sourceSizeTask = Task.detached {
            defer { access.stop() }
            let attrs = try? FileManager.default.attributesOfItem(atPath: access.url.path)
            return (attrs?[.size] as? NSNumber)?.int64Value
          }
        }
        let sourceSnapshot = sourceURL
        let size = await sourceSizeTask?.value
        guard !Task.isCancelled, estimateRevision == revision, sourceURL == sourceSnapshot else { return }
        cachedSourceFileSize = size
        if size == nil {
          sourceSizeTask = nil
        }
      }
      guard !Task.isCancelled, estimateRevision == revision else { return }
      let size = calculateEstimatedFileSize(sourceSize: cachedSourceFileSize ?? 0)
      if estimatedFileSize != size {
        estimatedFileSize = size
      }
    }
  }

  /// Formula runs against the fully stored latest recipe; filesystem I/O is cached.
  private func calculateEstimatedFileSize(sourceSize: Int64) -> Int64 {
    let interval = PerfSignpost.VideoEditor.beginInterval("Estimate")
    defer { PerfSignpost.VideoEditor.endInterval(interval) }
    guard sourceSize > 0 else { return 0 }

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

  /// Prepare source-item ranges once on the main actor. Rate changes are then
  /// driven by AVPlayer callbacks on a separate serial queue, so a busy SwiftUI
  /// render cannot leave the outgoing speed active past its authored end.
  @discardableResult
  private func refreshPreviewRateSchedule() -> Int? {
    guard let previewRateController else { return nil }

    var sourceSpans: [VideoEditorPreviewRateController.Span] = []
    if speedPreviewItem !== player.currentItem,
       let activeClipId,
       let placement = playbackPlacements.first(where: { $0.clip.id == activeClipId }) {
      sourceSpans = sequenceMap.spans.compactMap { span in
        let start = max(span.seqStart, placement.start)
        let end = min(span.seqEnd, placement.end)
        guard end - start > 0.000_001 else { return nil }
        return VideoEditorPreviewRateController.Span(
          start: placement.sourceTime(at: start),
          end: placement.sourceTime(at: end),
          rate: Float(span.rate)
        )
      }
    }

    let forwardPlaying = isPlaying && playbackState.shuttleRate >= 0
    let allowSegmentController = forwardPlaying && playbackState.shuttleRate <= 1.05
    return previewRateController.configure(
      spans: sourceSpans,
      item: player.currentItem,
      enabled: allowSegmentController && internalSeekToken == nil && !handoffSeekInFlight,
      wantsPlayback: forwardPlaying
    )
  }

  private func setupTimeObserver() {
    if let timeObserver {
      player.removeTimeObserver(timeObserver)
    }
    timeObserverGeneration += 1
    let generation = timeObserverGeneration
    lastTimeObserverUpdate = 0

    let interval = CMTime(seconds: 1.0 / 30.0, preferredTimescale: 600)
    timeObserver = player.addPeriodicTimeObserver(
      forInterval: interval,
      queue: .main
    ) { [weak self] _ in
      MainActor.assumeIsolated {
        guard let self,
              self.timeObserverGeneration == generation,
              !self.playbackState.isScrubbing,
              !self.speedPreviewIsPreparing,
              self.playbackState.shuttleRate >= 0
        else { return }
        // A handoff seek is landing; the reported time is still the outgoing
        // clip's coordinates.
        guard !self.handoffSeekInFlight,
              self.internalSeekToken == nil
        else { return }
        // A time callback may have waited behind other main-queue work. Use the
        // player's latest position so stale callbacks can't move the playhead or
        // speed rate backward after the transport has already crossed a boundary.
        let latestItemTime = self.player.currentTime()
        guard latestItemTime.isNumeric else { return }
        // AVPlayer's interval is measured in source time. At 8x, a 30 fps
        // interval can publish the whole editor over 200 times per wall second.
        // Gate below the 1/30 s period: callbacks jitter early by a few ms, and a gate
        // equal to the period dropped about half of them at 1x (overlays at 15–30 Hz).
        let now = ProcessInfo.processInfo.systemUptime
        guard now - self.lastTimeObserverUpdate >= 0.8 / 30.0 else { return }
        self.lastTimeObserverUpdate = now
        self.handlePlaybackTick(itemTime: CMTimeGetSeconds(latestItemTime))
      }
    }
  }

  /// Periodic playback tick. `itemTime` is in the ACTIVE source asset's coordinates,
  /// so it has to be folded back onto the sequence axis before it reaches the playhead.
  func handlePlaybackTick(itemTime: Double) {
    guard !speedPreviewIsPreparing, playbackState.shuttleRate >= 0 else { return }
    if speedPreviewItem === player.currentItem {
      if itemTime >= sequenceMap.outputDuration - 0.01 {
        pauseAtPendingPosition()
        seek(to: .zero)
        return
      }
      if let time = timelineTime(atPreviewOutput: itemTime) {
        playbackState.setCurrentTime(time)
        let desiredMute = shouldMutePreviewPlayer
        if player.isMuted != desiredMute {
          player.isMuted = desiredMute
        }
        if playbackState.isPlaying {
          if playbackState.shuttleRate <= 1.05 {
            addedAudioPlayer.play(at: CMTimeGetSeconds(time))
          } else {
            addedAudioPlayer.pause()
          }
        }
        updateClipActionAvailability()
      }
      return
    }
    guard let placement = placementForClip(activeClipId) else {
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
    guard itemTime >= clip.sourceStart - 0.05 else { return }

    let sequenceTime = placement.sequenceTime(atSource: itemTime)

    // Reached this clip's out-point — hand off to the next one.
    if itemTime >= clip.sourceEnd - 0.01 {
      advanceToClip(after: placement)
      return
    }

    playbackState.setCurrentTime(CMTime(seconds: sequenceTime, preferredTimescale: 600))
    updateClipActionAvailability()
  }

  /// Continue into the clip after `placement` (playing any black-screen gap in between),
  /// or continue across an audio tail, or stop and rewind at the end of the sequence.
  private func advanceToClip(after placement: TimelineSequence.Placement) {
    previewRateController?.setEnabled(false)
    player.pause()
    let nextIndex = placement.index + 1
    guard nextIndex < clips.count else {
      if maxAudioTimelineEnd > placement.activeEnd + 0.05 {
        playbackState.setCurrentTime(CMTime(seconds: placement.activeEnd, preferredTimescale: 600))
        startGapPlayback(until: maxAudioTimelineEnd, resumePlacement: nil, forceSeek: false)
        return
      }
      pauseAtPendingPosition()
      seek(to: .zero)
      return
    }

    let next = clips[nextIndex]
    if let nextPlacement = placementForClip(next.id),
       nextPlacement.activeStart > placement.activeEnd + 0.04,
       allowsGapPlayhead(at: placement.activeEnd + 0.02) {
      playbackState.setCurrentTime(CMTime(seconds: placement.activeEnd, preferredTimescale: 600))
      startGapPlayback(until: nextPlacement.activeStart, resumePlacement: nextPlacement, forceSeek: false)
      return
    }

    resumeVideoPlayback(for: next)
  }

  /// Seamlessly hand AVPlayer playback onto `next` (used both for direct clip handoffs
  /// and when emerging out of a black-screen gap into the next video clip).
  func resumeVideoPlayback(for next: TimelineClip) {
    let nextId = next.id
    let nextTime = placementForClip(nextId)?.activeStart
      ?? CMTimeGetSeconds(currentTime)
    activeClipId = nextId
    activateItemIfNeeded(for: next)
    // The seek completes asynchronously; until it lands, ticks and end
    // notifications still report the outgoing clip's coordinates.
    let handoffToken = UUID()
    handoffSeekToken = handoffToken
    handoffSeekInFlight = true
    let rateGeneration = refreshPreviewRateSchedule()
    let rateController = previewRateController
    if let rateGeneration {
      rateController?.awaitSeekLanding(at: next.sourceStart, ifGeneration: rateGeneration)
    }
    player.seek(
      to: CMTime(seconds: next.sourceStart, preferredTimescale: 600),
      toleranceBefore: Self.seekToleranceBefore(for: next.sourceStart),
      toleranceAfter: .zero
    ) { [weak self, weak rateController] finished in
      if finished, let rateGeneration {
        rateController?.resumeAfterSeek(ifGeneration: rateGeneration)
      }
      Task { @MainActor [weak self] in
        // A user seek or a newer handoff can supersede this completion. Only the
        // owner of the current token may release the handoff gate or restart playback.
        guard let self, handoffSeekToken == handoffToken else { return }
        handoffSeekToken = nil
        setupTimeObserver()
        handoffSeekInFlight = false
        refreshPreviewRateSchedule()
        guard activeClipId == nextId else { return }
        guard finished else {
          pause()
          return
        }
        guard isPlaying, playbackState.shuttleRate >= 0 else { return }
        player.isMuted = shouldMutePreviewPlayer

        // The independent completion normally resumed playback already. If
        // AVPlayer stayed paused, preserve the user's Play intent here as well.
        if player.rate == 0 {
          let requestedRate: Float = if playbackState.shuttleRate > 1.05 {
            playbackState.shuttleRate
          } else {
            currentPreviewRate(at: CMTime(seconds: nextTime, preferredTimescale: 600))
          }
          applyPreviewRate(
            requestedRate,
            startPlayback: true
          )
        }
      }
    }
  }

  private static func loadZoomTransitionDuration() -> TimeInterval {
    guard let stored = UserDefaults.standard.object(
      forKey: PreferencesKeys.videoEditorZoomTransitionDuration
    ) as? Double else {
      return ZoomCalculator.defaultTransitionDuration
    }

    return ZoomCalculator.migrateLegacyTransitionDuration(stored)
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
        // A transport seek is already repositioning playback — end notifications
        // delivered in this window belong to the previous position or clip.
        guard !self.handoffSeekInFlight,
              self.internalSeekToken == nil
        else { return }
        guard let item = notification.object as? AVPlayerItem, item === self.player.currentItem else { return }
        if self.speedPreviewItem === item {
          // This notification is delivered on the main queue and may be stale by
          // the time it runs. The periodic observer can already have rewound the
          // preview, or the user may have resumed playback from the beginning.
          // Only rewind while this item is still parked at the end of its output.
          let itemTime = CMTimeGetSeconds(self.player.currentTime())
          let previewDuration = self.sequenceMap.outputDuration
          guard itemTime.isFinite,
                previewDuration.isFinite,
                previewDuration > 0,
                itemTime >= previewDuration - 0.1
          else { return }
          let playableVideoEnd = self.placements.last(where: { $0.activeEnd > $0.activeStart })?.activeEnd ?? 0
          if self.maxAudioTimelineEnd > playableVideoEnd + 0.05 {
            self.playbackState.setCurrentTime(CMTime(seconds: playableVideoEnd, preferredTimescale: 600))
            self.startGapPlayback(until: self.maxAudioTimelineEnd, resumePlacement: nil, forceSeek: false)
            return
          }
          self.pauseAtPendingPosition()
          self.seek(to: .zero)
          return
        }
        // Consecutive clips from one asset share an item, so an end notification
        // can arrive after the playhead already moved into a later clip. Only
        // honor it while the item is genuinely still parked at its end AND the
        // clip on screen is the one whose material reaches that end; otherwise
        // the periodic tick owns the handoff and this notification is stale.
        let itemTime = CMTimeGetSeconds(self.player.currentTime())
        let itemDuration = CMTimeGetSeconds(item.duration)
        guard let placement = self.placementForClip(self.activeClipId),
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
      .receive(on: DispatchQueue.main)
      .sink { [weak self] _ in
        self?.updateHasUnsavedChanges()
        self?.recalculateEstimatedFileSize()
      }
      .store(in: &cancellables)

    // Segment and clip downstream work runs in didSet, after storage and cache
    // invalidation. @Published sinks run in willSet and would see the old recipe.

    // Track background changes
    Publishers.CombineLatest4($backgroundStyle, $backgroundPadding, $backgroundShadowIntensity, $backgroundCornerRadius)
      .dropFirst(4)
      .receive(on: DispatchQueue.main)
      .sink { [weak self] _, _, _, _ in
        self?.updateHasUnsavedChanges()
        self?.recalculateEstimatedFileSize()
      }
      .store(in: &cancellables)

    // Alignment and aspect ratio change the exported frame too.
    Publishers.CombineLatest($backgroundAlignment, $backgroundAspectRatio)
      .dropFirst()
      .receive(on: DispatchQueue.main)
      .sink { [weak self] _, _ in
        self?.updateHasUnsavedChanges()
      }
      .store(in: &cancellables)

    // Track export settings changes for file size estimation
    $exportSettings
      .dropFirst()
      .receive(on: DispatchQueue.main)
      .sink { [weak self] _ in
        self?.updateHasUnsavedChanges()
        self?.recalculateEstimatedFileSize()
      }
      .store(in: &cancellables)
  }

  func updateHasUnsavedChanges(currentZoomSegments: [ZoomSegment]? = nil) {
    // GIF mode: only track dimension changes
    if isGIF {
      let dimensionChanged = exportSettings.dimensionPreset != initialExportSettings.dimensionPreset
        || exportSettings.customWidth != initialExportSettings.customWidth
        || exportSettings.customHeight != initialExportSettings.customHeight
      if hasUnsavedChanges != dimensionChanged {
        hasUnsavedChanges = dimensionChanged
      }
      return
    }

    // Runs on every edit tick. Short-circuit from the cheap scalar checks to the arrays
    // (clips, segments, captions with their words), stopping at the first difference.
    // Trim lives inside the clip sequence, so the clips comparison covers it.
    let segments = currentZoomSegments ?? zoomSegments
    let changed = isMuted != initialIsMuted
      || backgroundStyle != initialBackgroundStyle
      || backgroundPadding != initialBackgroundPadding
      || backgroundShadowIntensity != initialBackgroundShadowIntensity
      || backgroundCornerRadius != initialBackgroundCornerRadius
      || backgroundAlignment != initialBackgroundAlignment
      || backgroundAspectRatio != initialBackgroundAspectRatio
      || exportSettings != initialExportSettings
      || cursorSettings != initialCursorSettings
      || cameraSettings != initialCameraSettings
      || motionBlurSettings != initialMotionBlurSettings
      || abs(zoomTransitionDuration - initialZoomTransitionDuration) > 0.0001
      || clips != initialClips
      || audioClips != initialAudioClips
      || mutedAudioLanes != initialMutedAudioLanes
      || timelineBookmarks != initialTimelineBookmarks
      || textOverlays != initialTextOverlays
      || segments != initialZoomSegments
      || speedSegments != initialSpeedSegments
      || captions != initialCaptions
    if hasUnsavedChanges != changed {
      hasUnsavedChanges = changed
    }
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

        // Pre-compute blur if needed, off the main thread. The preview shows the sharp
        // wallpaper until it lands (the background view's existing fallback).
        self.cachedBlurredImage = nil
        if case .blurred = self.backgroundStyle,
           let source = image?.cgImage(forProposedRect: nil, context: nil, hints: nil) {
          let radius = WallpaperQualityConfig.blurRadius
          Task.detached(priority: .userInitiated) {
            let blurred = Self.renderGaussianBlur(of: source, radius: radius)
            await MainActor.run { [weak self] in
              guard let self, case .blurred(let current) = backgroundStyle, current == url,
                    loadingBackgroundURL == nil
              else { return }
              cachedBlurredImage = blurred.map { NSImage(cgImage: $0, size: .zero) }
            }
          }
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

    metadataRevision = UUID()
    autoFocusPathInputs = [:]
    rebuildAutoFocusPaths(for: zoomSegments)
  }

  private func rebuildAutoFocusPaths(for segments: [ZoomSegment]) {
    guard !isPerformanceWorkClosed else { return }
    let inputs = Dictionary(
      segments.filter(\.isAutoMode).map { ($0.id, AutoFocusPathInput(segment: $0)) },
      uniquingKeysWith: { first, _ in first }
    )
    guard inputs != autoFocusPathInputs else { return }
    PerfSignpost.VideoEditor.event("AutoFocusRequested")
    autoFocusPathInputs = inputs
    autoFocusRequestRevision &+= 1
    let revision = autoFocusRequestRevision
    autoFocusBuildTask?.cancel()
    guard let metadata = recordingMetadata, !metadata.mouseSamples.isEmpty, !inputs.isEmpty else {
      if !autoFocusPaths.isEmpty {
        autoFocusPaths = [:]
        autoFocusPathRevision &+= 1
        scheduleMappedAutoFocusPaths()
      }
      return
    }
    let token = metadataRevision
    let worker = autoFocusWorker
    autoFocusBuildTask = Task { [weak self] in
      // Cancel superseded requests before they enter the worker queue.
      await Task.yield()
      guard !Task.isCancelled else { return }
      let paths = await worker.paths(for: segments, metadata: metadata, metadataRevision: token)
      guard !Task.isCancelled, let self, autoFocusRequestRevision == revision else { return }
      autoFocusPaths = paths
      autoFocusPathRevision &+= 1
      scheduleMappedAutoFocusPaths()
    }
  }

  private func scheduleMappedAutoFocusPaths() {
    guard !isPerformanceWorkClosed else { return }
    mappedAutoFocusBuildTask?.cancel()
    guard !autoFocusPaths.isEmpty else {
      if !mappedAutoFocusPaths.isEmpty {
        mappedAutoFocusPaths = [:]
        autoFocusPathRevision &+= 1
      }
      return
    }
    let sourceRevision = autoFocusPathRevision
    let layoutRevision = timelineLayoutRevision
    PerfSignpost.VideoEditor.event("AutoFocusRemapRequested")
    let paths = autoFocusPaths
    let layout = placements
    let worker = autoFocusWorker
    // A trim drag changes the layout per mouse event; let the edge settle briefly so
    // superseded remaps are cancelled before they reach the worker.
    let settleDelay: UInt64 = clipTrimOriginalClips != nil ? 100_000_000 : 0
    mappedAutoFocusBuildTask = Task { [weak self] in
      if settleDelay > 0 {
        try? await Task.sleep(nanoseconds: settleDelay)
        guard !Task.isCancelled else { return }
      }
      let mapped = await worker.timelinePaths(paths, placements: layout)
      guard !Task.isCancelled, let self,
            autoFocusPathRevision == sourceRevision,
            timelineLayoutRevision == layoutRevision else { return }
      mappedAutoFocusPaths = mapped
      PerfSignpost.VideoEditor.event("AutoFocusRemapInstalled")
      autoFocusPathRevision &+= 1
    }
  }

  /// Capture metadata alongside the recipe before awaiting. The worker returns
  /// exact source paths without installing them into the changing authoring state.
  func awaitExactAutoFocusPaths(
    for segments: [ZoomSegment], metadata: RecordingMetadata?
  ) async -> [UUID: [AutoFocusCameraSample]] {
    guard let metadata else { return [:] }
    return await autoFocusWorker.paths(
      for: segments, metadata: metadata, metadataRevision: metadataRevision
    )
  }

  func cancelPendingPerformanceWork() {
    isPerformanceWorkClosed = true
    stopReverseShuttleTimer()
    stopAudioTailPlayback()
    addedAudioPlayer.stopAll()
    clickSoundPlayer.shutdown()
    cameraPreview?.stop()
    cancelCaptionGeneration()
    speedPreviewRevision &+= 1
    estimateRevision &+= 1
    speedTrackDragInProgress = false
    speedTrackDragDidChange = false
    autoFocusBuildTask?.cancel()
    mappedAutoFocusBuildTask?.cancel()
    smartAutoZoomTask?.cancel()
    smartAutoZoomNoticeTask?.cancel()
    autoFocusRequestRevision &+= 1
    estimateTask?.cancel()
    sourceSizeTask?.cancel()
    speedPreviewBuildTask?.cancel()
  }

  /// The current style's images are in place (for `.blurred`, the blur too).
  private var hasCachedBackgroundForStyle: Bool {
    guard cachedBackgroundImage != nil else { return false }
    if case .blurred = backgroundStyle {
      return cachedBlurredImage != nil
    }
    return true
  }

  private nonisolated static let blurContext = CIContext(options: [.useSoftwareRenderer: false])

  /// Gaussian blur rendered once into a bitmap. The old path TIFF-encoded the wallpaper on
  /// the main thread and returned a lazy `NSCIImageRep`, so the full-resolution blur ran
  /// again on every redraw of the preview background (resizes, sidebar and panel changes).
  nonisolated static func renderGaussianBlur(of image: CGImage, radius: CGFloat) -> CGImage? {
    let input = CIImage(cgImage: image)
    guard let filter = CIFilter(name: "CIGaussianBlur") else { return nil }
    filter.setValue(input, forKey: kCIInputImageKey)
    filter.setValue(radius, forKey: kCIInputRadiusKey)
    guard let output = filter.outputImage?.cropped(to: input.extent) else { return nil }
    // Keep the wallpaper's own color space (a P3 wallpaper would otherwise clip to sRGB).
    if let colorSpace = image.colorSpace {
      return blurContext.createCGImage(output, from: input.extent, format: .RGBA8, colorSpace: colorSpace)
    }
    return blurContext.createCGImage(output, from: input.extent)
  }
}
