//
//  VideoEditorAudioClip.swift
//  Snapzy
//
//  Independent multi-track audio clip model for the audio timeline lanes.
//  Supports both the recording's primary audio and user-imported audio files
//  (MP3, M4A, WAV, AAC, FLAC, AIFF) with free timeline placement, multi-lane
//  stacking (`trackIndex`), independent non-destructive trimming, splitting,
//  volume, mute, and fade in/out.
//

import Foundation

nonisolated struct AudioTimelineClip: Identifiable, Equatable, Hashable, Codable, Sendable {
  enum Source: Equatable, Hashable, Codable, Sendable {
    /// Original audio track from the recording being edited.
    case primary
    /// External audio file imported by the user (music, voiceover, SFX) or detached clip audio.
    case file(url: URL)
  }

  static let minDuration: TimeInterval = 0.15
  static let maxTrackCount: Int = 8
  static let maxVolume: Float = 2.0
  static let maxTimelineSeconds: TimeInterval = 864_000

  let id: UUID
  let source: Source
  var name: String
  /// Position on the timeline sequence axis where this clip starts playing.
  var timelineStart: TimeInterval
  /// Full duration of the underlying audio asset.
  let sourceDuration: TimeInterval
  /// In-point within the underlying audio asset.
  var sourceStart: TimeInterval
  /// Out-point within the underlying audio asset.
  var sourceEnd: TimeInterval
  /// Per-clip linear gain (`0.0 ... 2.0`).
  var volume: Float
  var isMuted: Bool
  var fadeIn: TimeInterval
  var fadeOut: TimeInterval
  /// Zero-based audio track lane index (`0 = A1`, `1 = A2`, ...).
  var trackIndex: Int

  init(
    id: UUID = UUID(),
    source: Source,
    name: String,
    timelineStart: TimeInterval = 0,
    sourceDuration: TimeInterval,
    sourceStart: TimeInterval = 0,
    sourceEnd: TimeInterval? = nil,
    volume: Float = 1.0,
    isMuted: Bool = false,
    fadeIn: TimeInterval = 0,
    fadeOut: TimeInterval = 0,
    trackIndex: Int = 0
  ) {
    self.id = id
    self.source = source
    self.name = String(name.prefix(256))
    self.timelineStart = timelineStart.isFinite ? min(max(0, timelineStart), Self.maxTimelineSeconds) : 0
    self.sourceDuration = sourceDuration.isFinite ? min(max(0, sourceDuration), Self.maxTimelineSeconds) : 0

    let clampedStart = max(0, min(sourceStart.isFinite ? sourceStart : 0, self.sourceDuration))
    let requestedEnd = (sourceEnd?.isFinite == true ? sourceEnd : nil) ?? self.sourceDuration
    var clampedEnd = max(clampedStart, min(requestedEnd, self.sourceDuration))
    if clampedEnd - clampedStart < Self.minDuration, clampedStart + Self.minDuration <= self.sourceDuration {
      clampedEnd = clampedStart + Self.minDuration
    }
    self.sourceStart = clampedStart
    self.sourceEnd = clampedEnd
    let safeVol = volume.isFinite ? volume : 1.0
    self.volume = min(max(safeVol, 0), 2.0)
    self.isMuted = isMuted
    self.fadeIn = ExportSettings.clampedAudioFade(fadeIn)
    self.fadeOut = ExportSettings.clampedAudioFade(fadeOut)
    self.trackIndex = max(0, min(trackIndex, Self.maxTrackCount - 1))
  }

  init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    let decodedId = try c.decode(UUID.self, forKey: .id)
    let decodedSource = try c.decode(Source.self, forKey: .source)
    let decodedName = try c.decode(String.self, forKey: .name)
    let rawStart = (try? c.decode(TimeInterval.self, forKey: .timelineStart)) ?? 0
    let rawDur = (try? c.decode(TimeInterval.self, forKey: .sourceDuration)) ?? 0
    let rawSourceStart = (try? c.decode(TimeInterval.self, forKey: .sourceStart)) ?? 0
    let rawSourceEnd = try? c.decode(TimeInterval.self, forKey: .sourceEnd)
    let rawVolume = (try? c.decode(Float.self, forKey: .volume)) ?? 1.0
    let rawMuted = (try? c.decode(Bool.self, forKey: .isMuted)) ?? false
    let rawFadeIn = (try? c.decode(TimeInterval.self, forKey: .fadeIn)) ?? 0
    let rawFadeOut = (try? c.decode(TimeInterval.self, forKey: .fadeOut)) ?? 0
    let rawTrack = (try? c.decodeIfPresent(Int.self, forKey: .trackIndex)) ?? 0
    self.init(
      id: decodedId,
      source: decodedSource,
      name: decodedName,
      timelineStart: rawStart,
      sourceDuration: rawDur,
      sourceStart: rawSourceStart,
      sourceEnd: rawSourceEnd,
      volume: rawVolume,
      isMuted: rawMuted,
      fadeIn: rawFadeIn,
      fadeOut: rawFadeOut,
      trackIndex: rawTrack
    )
  }

  var isPrimary: Bool {
    if case .primary = source {
      return true
    }
    return false
  }

  var fileURL: URL? {
    if case .file(let url) = source {
      return url
    }
    return nil
  }

  var duration: TimeInterval {
    max(0, sourceEnd - sourceStart)
  }

  var timelineEnd: TimeInterval {
    timelineStart + duration
  }

  func contains(timelineTime: TimeInterval) -> Bool {
    timelineTime >= timelineStart && timelineTime < timelineEnd
  }

  /// Move this clip along the timeline (and optionally to a different track lane)
  /// without changing its source window.
  func moved(to newStart: TimeInterval, trackIndex: Int? = nil) -> AudioTimelineClip {
    var copy = self
    copy.timelineStart = newStart.isFinite ? max(0, newStart) : copy.timelineStart
    if let trackIndex {
      copy.trackIndex = max(0, min(trackIndex, Self.maxTrackCount - 1))
    }
    return copy
  }

  /// Trim the leading edge on the timeline (adjusting both `timelineStart` and `sourceStart`).
  func trimmedLeading(by deltaSeconds: TimeInterval) -> AudioTimelineClip {
    var copy = self
    let minDelta = max(-sourceStart, -timelineStart)
    let maxDelta = duration - Self.minDuration
    let clampedDelta = min(max(deltaSeconds, minDelta), max(minDelta, maxDelta))
    copy.timelineStart = max(0, timelineStart + clampedDelta)
    copy.sourceStart = max(0, sourceStart + clampedDelta)
    return copy
  }

  /// Trim the trailing edge on the timeline (adjusting `sourceEnd`).
  func trimmedTrailing(by deltaSeconds: TimeInterval) -> AudioTimelineClip {
    var copy = self
    let minEnd = sourceStart + Self.minDuration
    let clampedEnd = min(max(sourceEnd + deltaSeconds, minEnd), sourceDuration)
    copy.sourceEnd = clampedEnd
    return copy
  }

  /// Split this audio clip at `timelineTime`, returning `(left, right)` on the same lane
  /// if the cut leaves both halves >= `minDuration`.
  func split(at timelineTime: TimeInterval) -> (left: AudioTimelineClip, right: AudioTimelineClip)? {
    let offset = timelineTime - timelineStart
    guard offset >= Self.minDuration, duration - offset >= Self.minDuration else { return nil }
    let splitSourceTime = sourceStart + offset

    let left = AudioTimelineClip(
      id: UUID(),
      source: source,
      name: name,
      timelineStart: timelineStart,
      sourceDuration: sourceDuration,
      sourceStart: sourceStart,
      sourceEnd: splitSourceTime,
      volume: volume,
      isMuted: isMuted,
      fadeIn: min(fadeIn, offset),
      fadeOut: 0,
      trackIndex: trackIndex
    )
    let right = AudioTimelineClip(
      id: UUID(),
      source: source,
      name: name,
      timelineStart: timelineTime,
      sourceDuration: sourceDuration,
      sourceStart: splitSourceTime,
      sourceEnd: sourceEnd,
      volume: volume,
      isMuted: isMuted,
      fadeIn: 0,
      fadeOut: min(fadeOut, duration - offset),
      trackIndex: trackIndex
    )
    return (left, right)
  }
}

// MARK: - Multi-Track Lane Layout

/// Pure multi-track audio lane layout helpers so overlapping audio clips (e.g. voiceover +
/// background music) automatically stack on separate lanes without visually covering each other.
nonisolated enum AudioTimelineLaneLayout {
  static func overlaps(
    startA: TimeInterval,
    endA: TimeInterval,
    startB: TimeInterval,
    endB: TimeInterval,
    tolerance: TimeInterval = 0.01
  ) -> Bool {
    startA < endB - tolerance && endA > startB + tolerance
  }

  static func overlaps(_ a: AudioTimelineClip, _ b: AudioTimelineClip, tolerance: TimeInterval = 0.01) -> Bool {
    overlaps(
      startA: a.timelineStart,
      endA: a.timelineEnd,
      startB: b.timelineStart,
      endB: b.timelineEnd,
      tolerance: tolerance
    )
  }

  static func isLaneFree(
    _ lane: Int,
    timelineStart: TimeInterval,
    timelineEnd: TimeInterval,
    excludingClipId: UUID? = nil,
    in existing: [AudioTimelineClip]
  ) -> Bool {
    guard lane >= 0, lane < AudioTimelineClip.maxTrackCount else { return false }
    return !existing.contains { other in
      other.id != excludingClipId
        && other.trackIndex == lane
        && overlaps(
          startA: timelineStart,
          endA: timelineEnd,
          startB: other.timelineStart,
          endB: other.timelineEnd
        )
    }
  }

  /// Find a non-overlapping `(timelineStart, trackIndex)` placement across `A1...A8`.
  /// If all 8 lanes are occupied at `requestedStart`, shifts `timelineStart` forward to the
  /// earliest slot `>= requestedStart` where a lane is free so clips never silently overlap.
  static func nonOverlappingPlacement(
    requestedStart: TimeInterval,
    duration: TimeInterval,
    excludingClipId: UUID? = nil,
    in existing: [AudioTimelineClip],
    preferredTrack: Int? = nil
  ) -> (timelineStart: TimeInterval, trackIndex: Int) {
    let safeDuration = max(AudioTimelineClip.minDuration, duration)
    var candidateStart = max(0, requestedStart)
    let others = existing.filter { $0.id != excludingClipId }

    for _ in 0 ... others.count {
      let candidateEnd = candidateStart + safeDuration
      if let preferredTrack {
        let clamped = max(0, min(preferredTrack, AudioTimelineClip.maxTrackCount - 1))
        if isLaneFree(clamped, timelineStart: candidateStart, timelineEnd: candidateEnd, in: others) {
          return (candidateStart, clamped)
        }
      }
      for lane in 0 ..< AudioTimelineClip.maxTrackCount {
        if isLaneFree(lane, timelineStart: candidateStart, timelineEnd: candidateEnd, in: others) {
          return (candidateStart, lane)
        }
      }
      // Every lane overlaps `[candidateStart, candidateEnd]` — advance past the earliest blocker end.
      let earliestEnd = others
        .filter { overlaps(startA: candidateStart, endA: candidateEnd, startB: $0.timelineStart, endB: $0.timelineEnd) }
        .map(\.timelineEnd)
        .min()
      guard let nextStart = earliestEnd, nextStart > candidateStart + 0.0001 else {
        break
      }
      candidateStart = nextStart
    }

    let fallbackLane = preferredTrack.map { max(0, min($0, AudioTimelineClip.maxTrackCount - 1)) }
      ?? (AudioTimelineClip.maxTrackCount - 1)
    return (candidateStart, fallbackLane)
  }

  /// Pick a non-overlapping track lane for a clip spanning `[start, end]`.
  /// Prefers `preferredTrack` when clear; otherwise picks the lowest non-overlapping lane.
  static func resolvedTrackIndex(
    timelineStart: TimeInterval,
    timelineEnd: TimeInterval,
    excludingClipId: UUID? = nil,
    in existing: [AudioTimelineClip],
    preferredTrack: Int? = nil
  ) -> Int {
    if let preferredTrack {
      let clamped = max(0, min(preferredTrack, AudioTimelineClip.maxTrackCount - 1))
      if isLaneFree(
        clamped,
        timelineStart: timelineStart,
        timelineEnd: timelineEnd,
        excludingClipId: excludingClipId,
        in: existing
      ) {
        return clamped
      }
    }

    for lane in 0 ..< AudioTimelineClip.maxTrackCount where isLaneFree(
      lane,
      timelineStart: timelineStart,
      timelineEnd: timelineEnd,
      excludingClipId: excludingClipId,
      in: existing
    ) {
      return lane
    }

    return preferredTrack.map { max(0, min($0, AudioTimelineClip.maxTrackCount - 1)) }
      ?? (AudioTimelineClip.maxTrackCount - 1)
  }

  /// Convenience overload accepting a candidate `AudioTimelineClip`.
  static func resolvedTrackIndex(
    for candidate: AudioTimelineClip,
    in existing: [AudioTimelineClip],
    preferredTrack: Int? = nil
  ) -> Int {
    resolvedTrackIndex(
      timelineStart: candidate.timelineStart,
      timelineEnd: candidate.timelineEnd,
      excludingClipId: candidate.id,
      in: existing,
      preferredTrack: preferredTrack
    )
  }

  /// Total number of audio lanes to display on the timeline.
  static func laneCount(for clips: [AudioTimelineClip], minimumLanes: Int = 1) -> Int {
    let highestUsed = (clips.map(\.trackIndex).max() ?? -1) + 1
    return max(1, min(AudioTimelineClip.maxTrackCount, max(minimumLanes, highestUsed)))
  }

  /// Resolve any collisions among loaded/legacy clips (for example clips saved before
  /// multi-track support that all had `trackIndex == 0` at overlapping timestamps).
  static func deduplicatingOverlaps(_ clips: [AudioTimelineClip]) -> [AudioTimelineClip] {
    var placed: [AudioTimelineClip] = []
    placed.reserveCapacity(clips.count)
    for var clip in clips {
      clip.trackIndex = resolvedTrackIndex(
        for: clip,
        in: placed,
        preferredTrack: clip.trackIndex
      )
      placed.append(clip)
    }
    return placed
  }
}
