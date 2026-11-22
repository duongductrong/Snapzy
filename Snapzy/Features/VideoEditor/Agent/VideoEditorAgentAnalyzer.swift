//
//  VideoEditorAgentAnalyzer.swift
//  Snapzy
//
//  What happens in the recording, for the agent's `get_activity` and the one-step
//  tools (`remove_silences`, `speed_up_idle`, `auto_zoom_activity`):
//
//  - silence / speech: RMS of the audio in 50 ms windows (microphone tracks when the
//    recording has them, else every track mixed), against a threshold set from the
//    recording's own noise floor.
//  - idle / motion: the cursor samples Snapzy records with each screen recording.
//
//  Results are in SOURCE time of the primary recording and cached per editor window;
//  `timelineSpans` maps them onto the structural timeline through the current clips,
//  so cuts, trims and reorders never need a new analysis. Inserted videos are not
//  analyzed.
//

import AVFoundation
import CoreGraphics
import Foundation

// MARK: - Results

nonisolated struct VideoEditorActivity: Equatable {
  /// One stretch of cursor movement, with the area the cursor covered (top-left normalized).
  struct Motion: Equatable {
    let range: ClosedRange<TimeInterval>
    let bounds: CGRect
  }

  enum AudioSource: String, Equatable {
    case none
    case microphone
    case all
  }

  var audio: AudioSource = .none
  var silences: [ClosedRange<TimeInterval>] = []
  var hasMouseData = false
  /// The cursor stays put (and no one speaks into the microphone, when there is one).
  var idle: [ClosedRange<TimeInterval>] = []
  var motion: [Motion] = []
  /// Length of the analyzed source.
  var duration: TimeInterval = 0
}

// MARK: - Analyzer

@MainActor
final class VideoEditorAgentAnalyzer {
  /// Explicit and nonisolated: the synthesized main-actor deinit hops through the
  /// back-deployed swift_task_deinitOnExecutor, which aborts on macOS 13-15 (#668).
  nonisolated deinit {}

  /// Audio window. Short enough to cut between words, long enough to be cheap.
  nonisolated static let window: TimeInterval = 0.05
  /// Shortest silence or idle stretch worth reporting at all; tools filter further.
  nonisolated static let minimumSpan: TimeInterval = 0.3

  private struct Key: Equatable {
    let url: URL
    let modified: Date?
    let mouseSampleCount: Int
    let audioTrackCount: Int
  }

  private var cached: (key: Key, activity: VideoEditorActivity)?
  private var inFlight: (key: Key, task: Task<VideoEditorActivity, Error>)?

  /// On-screen text and frames (`get_frame`, `find_on_screen`). Lives with the analysis so
  /// its OCR cache outlasts one conversation.
  let vision: VideoEditorAgentVision
  /// Speech (`get_transcript`), on-device.
  let transcriber: VideoEditorAgentTranscriber

  init(vision: VideoEditorAgentVision? = nil, transcriber: VideoEditorAgentTranscriber? = nil) {
    self.vision = vision ?? VideoEditorAgentVision()
    self.transcriber = transcriber ?? VideoEditorAgentTranscriber()
  }

  /// The analysis for the open video, from cache when the source hasn't changed.
  func activity(
    for state: VideoEditorState,
    priority: TaskPriority = .userInitiated
  ) async throws -> VideoEditorActivity {
    let key = Self.key(for: state)
    if let cached, cached.key == key { return cached.activity }
    if let inFlight, inFlight.key == key { return try await inFlight.task.value }

    let asset = state.asset
    let roles = state.audioTrackRoles
    let samples = state.recordingMetadata?.mouseSamples ?? []
    let space = state.recordingMetadata?.coordinateSpace ?? .topLeftNormalized
    let duration = CMTimeGetSeconds(state.duration)
    // A prewarm runs at utility so its audio decode doesn't compete with playback; a tool
    // that later awaits the same in-flight task escalates it to its own priority.
    let task = Task.detached(priority: priority) {
      try await Self.analyze(asset: asset, roles: roles, samples: samples, coordinateSpace: space, duration: duration)
    }
    inFlight = (key, task)
    defer { if inFlight?.key == key { inFlight = nil } }
    let activity = try await task.value
    cached = (key, activity)
    return activity
  }

  /// The cached analysis when it is still current; nil means `activity(for:)` must run first.
  func cachedActivity(for state: VideoEditorState) -> VideoEditorActivity? {
    guard let cached, cached.key == Self.key(for: state) else { return nil }
    return cached.activity
  }

  /// Starts the analysis early (the prompt opened) so the first tool doesn't wait.
  func prewarm(_ state: VideoEditorState) {
    guard !state.isGIF, !state.clips.isEmpty, cachedActivity(for: state) == nil else { return }
    // Utility on the awaiting task too: a main-actor (user-initiated) awaiter would
    // escalate the analysis right back.
    Task(priority: .utility) { [weak self, weak state] in
      guard let self, let state else { return }
      _ = try? await self.activity(for: state, priority: .utility)
    }
  }

  private static func key(for state: VideoEditorState) -> Key {
    let url = state.editingSourceURL
    let modified = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
    return Key(
      url: url,
      modified: modified,
      mouseSampleCount: state.recordingMetadata?.mouseSamples.count ?? 0,
      audioTrackCount: state.audioTrackRoles.count
    )
  }

  // MARK: Analysis (off the main actor)

  nonisolated static func analyze(
    asset: AVAsset,
    roles: [VideoEditorAudioTrackRole],
    samples: [RecordedMouseSample],
    coordinateSpace: RecordingCoordinateSpace,
    duration: TimeInterval
  ) async throws -> VideoEditorActivity {
    var activity = VideoEditorActivity(duration: duration)

    let tracks = try await asset.loadTracks(withMediaType: .audio)
    if !tracks.isEmpty {
      // Silence means nobody talks: prefer the microphone over system sound.
      let microphone = zip(tracks, roles).filter { $0.1 == .microphone }.map(\.0)
      let chosen = microphone.isEmpty ? tracks : microphone
      let levels = try await readLevels(asset: asset, tracks: chosen)
      activity.audio = microphone.isEmpty ? .all : .microphone
      activity.silences = silences(levels: levels, window: window)
    }

    let points = canonical(samples, coordinateSpace)
    if points.count >= 2 {
      activity.hasMouseData = true
      let still = stillSpans(points, end: duration)
      // With a microphone, someone talking over a still cursor isn't idle. System sound alone
      // (music, a notification) says nothing about whether the user is waiting.
      activity.idle = activity.audio == .microphone ? intersect(still, activity.silences) : still
      activity.motion = motionSpans(points)
    }
    return activity
  }

  /// RMS level (dBFS) of each window, the chosen tracks mixed to mono.
  nonisolated static func readLevels(asset: AVAsset, tracks: [AVAssetTrack]) async throws -> [Float] {
    let sampleRate = 16_000.0
    let reader = try AVAssetReader(asset: asset)
    let output = AVAssetReaderAudioMixOutput(audioTracks: tracks, audioSettings: [
      AVFormatIDKey: kAudioFormatLinearPCM,
      AVSampleRateKey: sampleRate,
      AVNumberOfChannelsKey: 1,
      AVLinearPCMBitDepthKey: 32,
      AVLinearPCMIsFloatKey: true,
      AVLinearPCMIsBigEndianKey: false,
      AVLinearPCMIsNonInterleaved: false,
    ])
    output.alwaysCopiesSampleData = false
    guard reader.canAdd(output) else { return [] }
    reader.add(output)
    guard reader.startReading() else { throw reader.error ?? CancellationError() }

    let perWindow = Int(sampleRate * window)
    var levels: [Float] = []
    var sum: Double = 0
    var count = 0
    while let buffer = output.copyNextSampleBuffer() {
      try Task.checkCancellation()
      guard let block = CMSampleBufferGetDataBuffer(buffer) else { continue }
      var length = 0
      var pointer: UnsafeMutablePointer<CChar>?
      guard CMBlockBufferGetDataPointer(block, atOffset: 0, lengthAtOffsetOut: nil, totalLengthOut: &length, dataPointerOut: &pointer) == kCMBlockBufferNoErr,
            let pointer else { continue }
      let frames = length / MemoryLayout<Float>.size
      pointer.withMemoryRebound(to: Float.self, capacity: frames) { samples in
        for index in 0 ..< frames {
          let value = Double(samples[index])
          sum += value * value
          count += 1
          if count == perWindow {
            levels.append(decibels(sum / Double(count)))
            sum = 0
            count = 0
          }
        }
      }
    }
    if reader.status == .failed { throw reader.error ?? CancellationError() }
    if count > perWindow / 2 { levels.append(decibels(sum / Double(count))) }
    return levels
  }

  nonisolated private static func decibels(_ meanSquare: Double) -> Float {
    Float(10 * log10(max(meanSquare, 1e-10)))
  }

  // MARK: Silence

  /// Threshold between silence and sound, from the recording's own spread of levels.
  nonisolated static func silenceThreshold(levels: [Float]) -> Float {
    let sorted = levels.sorted()
    guard !sorted.isEmpty else { return -50 }
    func percentile(_ p: Double) -> Float { sorted[min(sorted.count - 1, Int(Double(sorted.count - 1) * p))] }
    let floor = percentile(0.1), loud = percentile(0.9)
    // Nothing above a whisper anywhere: all of it is silence.
    if loud < -50 { return loud + 1 }
    // No clear quiet parts (constant music, room noise): only real silence counts.
    if loud - floor < 8 { return -50 }
    return min(max(floor + max(6, (loud - floor) * 0.3), -60), -28)
  }

  /// Silent stretches (seconds from the start). Sound blips under 0.15 s don't break a silence.
  nonisolated static func silences(
    levels: [Float],
    window: TimeInterval,
    minDuration: TimeInterval = minimumSpan
  ) -> [ClosedRange<TimeInterval>] {
    guard !levels.isEmpty else { return [] }
    let threshold = silenceThreshold(levels: levels)
    var runs: [ClosedRange<Int>] = []
    var start: Int?
    for (index, level) in levels.enumerated() {
      if level < threshold {
        if start == nil { start = index }
      } else if let open = start {
        runs.append(open ... index - 1)
        start = nil
      }
    }
    if let start { runs.append(start ... levels.count - 1) }

    let maxBlip = Int((0.15 / window).rounded())
    var merged: [ClosedRange<Int>] = []
    for run in runs {
      if let last = merged.last, run.lowerBound - last.upperBound - 1 <= maxBlip {
        merged[merged.count - 1] = last.lowerBound ... run.upperBound
      } else {
        merged.append(run)
      }
    }
    return merged
      .map { Double($0.lowerBound) * window ... Double($0.upperBound + 1) * window }
      .filter { $0.upperBound - $0.lowerBound >= minDuration - 1e-9 }
  }

  // MARK: Cursor

  nonisolated struct Point: Equatable {
    let time: TimeInterval
    let point: CGPoint
  }

  nonisolated static func canonical(_ samples: [RecordedMouseSample], _ space: RecordingCoordinateSpace) -> [Point] {
    samples
      .filter(\.isInsideCapture)
      .sorted { $0.time < $1.time }
      .map { sample in
        let y = space == .bottomLeftNormalized ? 1 - sample.normalizedY : sample.normalizedY
        return Point(time: sample.time, point: CGPoint(x: sample.normalizedX, y: y))
      }
  }

  /// Movement under this (normalized, per sample step) is a still hand.
  nonisolated static let stillTolerance: CGFloat = 0.004
  /// How far the cursor may wander from where it came to rest and still be resting.
  nonisolated static let restTolerance: CGFloat = 0.01

  /// Stretches where the cursor doesn't move. A recording's tail after the last sample counts
  /// as still. Outside-the-capture samples were dropped, so a cursor away from the recorded
  /// area reads as still too.
  nonisolated static func stillSpans(
    _ points: [Point],
    end: TimeInterval,
    minDuration: TimeInterval = minimumSpan
  ) -> [ClosedRange<TimeInterval>] {
    guard let first = points.first else { return [] }
    var spans: [ClosedRange<TimeInterval>] = []
    // Distance is measured from where the rest began, so a slow drift still ends it.
    var rest = first
    var previous = first
    for point in points.dropFirst() {
      let moved = hypot(point.point.x - rest.point.x, point.point.y - rest.point.y)
      if moved > restTolerance {
        // Still until the last sample before this one moved.
        if previous.time - rest.time >= minDuration { spans.append(rest.time ... previous.time) }
        rest = point
      }
      previous = point
    }
    let stillStart = rest.time
    if end - stillStart >= minDuration { spans.append(stillStart ... end) }
    return spans
  }

  /// Stretches of cursor movement (pauses under 0.6 s joined), with the area covered.
  nonisolated static func motionSpans(_ points: [Point], joinGap: TimeInterval = 0.6) -> [VideoEditorActivity.Motion] {
    var spans: [VideoEditorActivity.Motion] = []
    var current: (start: TimeInterval, end: TimeInterval, bounds: CGRect)?
    for (previous, point) in zip(points, points.dropFirst()) {
      let moved = hypot(point.point.x - previous.point.x, point.point.y - previous.point.y)
      guard moved > stillTolerance else { continue }
      let segment = CGRect(origin: previous.point, size: .zero).union(CGRect(origin: point.point, size: .zero))
      if var open = current, previous.time - open.end <= joinGap {
        open.end = point.time
        open.bounds = open.bounds.union(segment)
        current = open
      } else {
        if let open = current { spans.append(.init(range: open.start ... open.end, bounds: open.bounds)) }
        current = (previous.time, point.time, segment)
      }
    }
    if let open = current { spans.append(.init(range: open.start ... open.end, bounds: open.bounds)) }
    return spans
  }

  // MARK: Range math

  nonisolated static func intersect(
    _ a: [ClosedRange<TimeInterval>],
    _ b: [ClosedRange<TimeInterval>],
    minDuration: TimeInterval = minimumSpan
  ) -> [ClosedRange<TimeInterval>] {
    var result: [ClosedRange<TimeInterval>] = []
    for x in a {
      for y in b where y.lowerBound < x.upperBound && y.upperBound > x.lowerBound {
        let range = max(x.lowerBound, y.lowerBound) ... min(x.upperBound, y.upperBound)
        if range.upperBound - range.lowerBound >= minDuration - 1e-9 { result.append(range) }
      }
    }
    return result.sorted { $0.lowerBound < $1.lowerBound }
  }

  /// `ranges` minus `holes`.
  nonisolated static func subtract(
    _ ranges: [ClosedRange<TimeInterval>],
    _ holes: [ClosedRange<TimeInterval>]
  ) -> [ClosedRange<TimeInterval>] {
    var result = ranges
    for hole in holes {
      result = result.flatMap { range -> [ClosedRange<TimeInterval>] in
        guard hole.lowerBound < range.upperBound, hole.upperBound > range.lowerBound else { return [range] }
        var pieces: [ClosedRange<TimeInterval>] = []
        if hole.lowerBound > range.lowerBound { pieces.append(range.lowerBound ... hole.lowerBound) }
        if hole.upperBound < range.upperBound { pieces.append(hole.upperBound ... range.upperBound) }
        return pieces
      }
    }
    return result
  }

  /// Source ranges of the primary recording → structural timeline ranges, through the
  /// footage that plays. Touching pieces (a split) are joined.
  nonisolated static func timelineSpans(
    _ ranges: [ClosedRange<TimeInterval>],
    placements: [TimelineSequence.Placement]
  ) -> [ClosedRange<TimeInterval>] {
    var mapped: [ClosedRange<TimeInterval>] = []
    for placement in placements where placement.clip.isPrimary {
      let active = placement.clip.sourceRange
      for range in ranges where range.lowerBound < active.upperBound && range.upperBound > active.lowerBound {
        let start = placement.sequenceTime(atSource: max(range.lowerBound, active.lowerBound))
        let end = placement.sequenceTime(atSource: min(range.upperBound, active.upperBound))
        if end > start { mapped.append(start ... end) }
      }
    }
    mapped.sort { $0.lowerBound < $1.lowerBound }
    var joined: [ClosedRange<TimeInterval>] = []
    for range in mapped {
      if let last = joined.last, range.lowerBound <= last.upperBound + 0.001 {
        joined[joined.count - 1] = last.lowerBound ... max(last.upperBound, range.upperBound)
      } else {
        joined.append(range)
      }
    }
    return joined
  }

  /// Timeline ranges where primary footage plays.
  nonisolated static func playingSpans(_ placements: [TimelineSequence.Placement]) -> [ClosedRange<TimeInterval>] {
    placements
      .filter { $0.clip.isPrimary && $0.activeEnd > $0.activeStart }
      .map { $0.activeStart ... $0.activeEnd }
  }
}
