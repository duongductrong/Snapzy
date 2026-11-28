//
//  VideoEditorState+AudioClips.swift
//  Snapzy
//
//  Independent multi-track audio clip management on VideoEditorState:
//  importing external audio files onto non-overlapping track lanes (`A1`, `A2`, ...),
//  manual lane creation/muting, moving across time and tracks, trimming, splitting,
//  detaching embedded audio from video clips, closing video gaps, and per-clip fades.
//

import AppKit
import AVFoundation
import Foundation
import QuartzCore
import UniformTypeIdentifiers

extension VideoEditorState {
  /// Number of audio lanes currently displayed on the timeline.
  var audioLaneCount: Int {
    AudioTimelineLaneLayout.laneCount(for: audioClips, minimumLanes: minimumAudioLanes)
  }

  /// Add an empty audio track lane (up to `AudioTimelineClip.maxTrackCount`) so the user
  /// can drag clips onto it or organize voiceover, music, and SFX visually.
  func addEmptyAudioTrack() {
    guard !isGIF else { return }
    let next = min(audioLaneCount + 1, AudioTimelineClip.maxTrackCount)
    if minimumAudioLanes < next {
      minimumAudioLanes = next
    }
  }

  /// Remove the bottom-most audio track lane if it has no clips and more than 1 lane is shown.
  func removeEmptyTrailingAudioTrack() {
    let lanes = audioLaneCount
    guard lanes > 1 else { return }
    let trailingLane = lanes - 1
    guard !audioClips.contains(where: { $0.trackIndex == trailingLane }) else { return }
    minimumAudioLanes = max(1, trailingLane)
    if mutedAudioLanes.remove(trailingLane) != nil {
      syncPlayerAudioWithExportSettings()
      updateHasUnsavedChanges()
    }
  }

  func toggleAudioLaneMute(_ lane: Int) {
    guard lane >= 0, lane < AudioTimelineClip.maxTrackCount else { return }
    let before = mutedAudioLanes
    if mutedAudioLanes.contains(lane) {
      mutedAudioLanes.remove(lane)
    } else {
      mutedAudioLanes.insert(lane)
    }
    recordAction(.updateMutedAudioLanes(old: before, new: mutedAudioLanes))
    syncPlayerAudioWithExportSettings()
    updateHasUnsavedChanges()
  }

  func isAudioClipEffectivelyMuted(_ clip: AudioTimelineClip) -> Bool {
    isMuted
      || (clip.isPrimary && exportSettings.audioMode == .mute)
      || clip.isMuted
      || mutedAudioLanes.contains(clip.trackIndex)
  }

  /// Seed the primary recording's audio clip once metadata is loaded so the
  /// Audio timeline lane displays immediately on open.
  func seedPrimaryAudioClipIfNeeded(duration primaryDuration: TimeInterval) {
    guard !isGIF, primaryDuration > 0 else { return }
    let primaryURL = Self.editorAssetURL(for: sourceURL, metadata: recordingMetadata)
    audioWaveformCache.ensureLoaded(for: primaryURL)

    guard audioClips.isEmpty, !audioTrackRoles.isEmpty else { return }
    let primaryClip = AudioTimelineClip(
      source: .primary,
      name: sourceURL.deletingPathExtension().lastPathComponent,
      timelineStart: 0,
      sourceDuration: primaryDuration,
      sourceStart: 0,
      sourceEnd: primaryDuration,
      volume: exportSettings.audioVolume,
      isMuted: exportSettings.audioMode == .mute,
      fadeIn: exportSettings.clampedAudioFadeIn,
      fadeOut: exportSettings.clampedAudioFadeOut,
      trackIndex: 0
    )
    audioClips = [primaryClip]
    syncAddedAudioPlayer()
  }

  /// Open a native file picker to import an external audio file (MP3/M4A/WAV/AAC/FLAC/AIFF)
  /// onto the Audio timeline lanes at the current playhead.
  func promptAddAudioClip(preferredTrack: Int? = nil) {
    let panel = NSOpenPanel()
    panel.allowedContentTypes = [.audio, .mp3, .wav, .aiff, .mpeg4Audio]
    panel.allowsMultipleSelection = false
    panel.canChooseDirectories = false
    panel.title = L10n.VideoEditor.addAudioTrack
    panel.prompt = L10n.VideoEditor.addAudioPrompt

    guard panel.runModal() == .OK, let url = panel.url else { return }
    let insertTime = max(0, CMTimeGetSeconds(currentTime))
    Task { @MainActor [weak self] in
      await self?.addAudioClip(url: url, at: insertTime, preferredTrack: preferredTrack)
    }
  }

  /// Import an external audio file at `timelineStart`, automatically placing it onto the
  /// lowest non-overlapping track lane (or `preferredTrack` if unobstructed) so parallel
  /// tracks (e.g. voiceover + background music) never cover each other visually.
  @discardableResult
  func addAudioClip(
    url: URL,
    at timelineStart: TimeInterval = 0,
    preferredTrack: Int? = nil
  ) async -> AudioTimelineClip? {
    guard !isGIF else { return nil }
    let asset = AVURLAsset(url: url)
    guard let loadedDuration = try? await asset.load(.duration) else { return nil }
    let seconds = CMTimeGetSeconds(loadedDuration)
    guard seconds.isFinite, seconds >= AudioTimelineClip.minDuration else { return nil }

    let clampedStart = max(0, timelineStart)
    let placement = AudioTimelineLaneLayout.nonOverlappingPlacement(
      requestedStart: clampedStart,
      duration: seconds,
      in: audioClips,
      preferredTrack: preferredTrack
    )

    let clip = AudioTimelineClip(
      source: .file(url: url),
      name: url.deletingPathExtension().lastPathComponent,
      timelineStart: placement.timelineStart,
      sourceDuration: seconds,
      sourceStart: 0,
      sourceEnd: seconds,
      trackIndex: placement.trackIndex
    )
    let before = audioClips
    audioClips.append(clip)
    selectedAudioClipId = clip.id
    selectClip(id: nil)
    selectedTextOverlayId = nil
    audioWaveformCache.ensureLoaded(for: url)
    recordAudioClipsUndo(previousClips: before, previousSelected: nil)
    syncPlayerAudioWithExportSettings()
    updateClipActionAvailability()
    updateHasUnsavedChanges()
    return clip
  }

  /// Detach embedded audio from a video clip (primary or inserted `.file` clip) onto an
  /// independent Multi-Track Audio lane, marking the video clip `isAudioDetached = true`
  /// so export never doubles its audio. Records one atomic Undo group.
  @discardableResult
  func detachAudio(fromClipId clipId: UUID) async -> AudioTimelineClip? {
    guard !isGIF,
          let idx = clips.firstIndex(where: { $0.id == clipId }),
          placements.contains(where: { $0.clip.id == clipId })
    else { return nil }

    let videoClip = clips[idx]
    guard !videoClip.isAudioDetached, videoClip.duration >= AudioTimelineClip.minDuration else {
      return nil
    }

    let audioSource: AudioTimelineClip.Source
    let audioName: String
    let waveformURL: URL

    switch videoClip.source {
    case .primary:
      guard !audioTrackRoles.isEmpty else { return nil }
      audioSource = .primary
      audioName = L10n.VideoEditor.detachedAudioName(sourceURL.deletingPathExtension().lastPathComponent)
      waveformURL = Self.editorAssetURL(for: sourceURL, metadata: recordingMetadata)

    case .file(let url):
      let asset = clipAsset(for: videoClip)
      let tracks = await (try? asset.loadTracks(withMediaType: .audio)) ?? []
      guard !tracks.isEmpty else { return nil }
      audioSource = .file(url: url)
      audioName = L10n.VideoEditor.detachedAudioName(url.deletingPathExtension().lastPathComponent)
      waveformURL = url
    }

    // Re-resolve clip index in case the timeline mutated while awaiting track metadata.
    guard let liveIdx = clips.firstIndex(where: { $0.id == clipId }),
          let livePlacement = placements.first(where: { $0.clip.id == clipId }),
          !clips[liveIdx].isAudioDetached
    else { return nil }

    let liveClip = clips[liveIdx]
    let timelineStart = livePlacement.activeStart
    let timelineEnd = livePlacement.activeEnd
    let resolvedLane = AudioTimelineLaneLayout.resolvedTrackIndex(
      timelineStart: timelineStart,
      timelineEnd: timelineEnd,
      in: audioClips
    )

    let detached = AudioTimelineClip(
      source: audioSource,
      name: audioName,
      timelineStart: timelineStart,
      sourceDuration: liveClip.sourceDuration,
      sourceStart: liveClip.sourceStart,
      sourceEnd: liveClip.sourceEnd,
      volume: 1.0,
      isMuted: false,
      fadeIn: 0,
      fadeOut: 0,
      trackIndex: resolvedLane
    )

    let beforeAudio = audioClips
    var updatedVideoClips = clips
    updatedVideoClips[liveIdx].isAudioDetached = true

    beginUndoGroup()
    defer { endUndoGroup() }

    applyClipsReplacing(updatedVideoClips, recordUndo: true)

    // For a primary clip, avoid duplicating an identical auto-seeded primary audio clip
    // covering the exact same span; instead ensure the detached span exists cleanly.
    let alreadyCoveredByPrimary = audioSource == .primary && audioClips.contains { existing in
      existing.isPrimary
        && abs(existing.timelineStart - timelineStart) < 0.05
        && abs(existing.sourceStart - liveClip.sourceStart) < 0.05
        && abs(existing.sourceEnd - liveClip.sourceEnd) < 0.05
    }

    let resultClip: AudioTimelineClip
    if alreadyCoveredByPrimary,
       let existing = audioClips.first(where: {
         $0.isPrimary
           && abs($0.timelineStart - timelineStart) < 0.05
           && abs($0.sourceStart - liveClip.sourceStart) < 0.05
           && abs($0.sourceEnd - liveClip.sourceEnd) < 0.05
       }) {
      resultClip = existing
      selectedAudioClipId = existing.id
      selectClip(id: nil)
    } else {
      // If detaching a split `.primary` clip while a broader auto-seeded `.primary` audio clip
      // already spans this range, carve out the overlapping span so primary audio is never
      // mixed twice in preview or export.
      if audioSource == .primary {
        let detachStart = detached.timelineStart
        let detachEnd = detached.timelineEnd
        var carved: [AudioTimelineClip] = []
        for existing in audioClips {
          guard existing.isPrimary,
                existing.timelineStart < detachEnd - 0.02,
                existing.timelineEnd > detachStart + 0.02
          else {
            carved.append(existing)
            continue
          }
          // Left remainder before detached span
          if existing.timelineStart < detachStart - AudioTimelineClip.minDuration {
            let leftDur = detachStart - existing.timelineStart
            carved.append(AudioTimelineClip(
              id: UUID(),
              source: existing.source,
              name: existing.name,
              timelineStart: existing.timelineStart,
              sourceDuration: existing.sourceDuration,
              sourceStart: existing.sourceStart,
              sourceEnd: min(existing.sourceEnd, existing.sourceStart + leftDur),
              volume: existing.volume,
              isMuted: existing.isMuted,
              fadeIn: min(existing.fadeIn, leftDur * 0.5),
              fadeOut: 0,
              trackIndex: existing.trackIndex
            ))
          }
          // Right remainder after detached span
          if existing.timelineEnd > detachEnd + AudioTimelineClip.minDuration {
            let rightOffset = detachEnd - existing.timelineStart
            let rightDur = existing.timelineEnd - detachEnd
            carved.append(AudioTimelineClip(
              id: UUID(),
              source: existing.source,
              name: existing.name,
              timelineStart: detachEnd,
              sourceDuration: existing.sourceDuration,
              sourceStart: min(existing.sourceEnd, existing.sourceStart + rightOffset),
              sourceEnd: existing.sourceEnd,
              volume: existing.volume,
              isMuted: existing.isMuted,
              fadeIn: 0,
              fadeOut: min(existing.fadeOut, rightDur * 0.5),
              trackIndex: existing.trackIndex
            ))
          }
        }
        audioClips = carved
      }
      audioClips.append(detached)
      recordAudioClipsUndo(previousClips: beforeAudio, previousSelected: selectedAudioClipId)
      selectedAudioClipId = detached.id
      selectClip(id: nil)
      resultClip = detached
    }

    audioWaveformCache.ensureLoaded(for: waveformURL)
    syncPlayerAudioWithExportSettings()
    updateClipActionAvailability()
    updateHasUnsavedChanges()
    return resultClip
  }

  /// True when a video clip can still have its embedded audio detached.
  func canDetachAudio(forClipId clipId: UUID) -> Bool {
    guard !isGIF, let clip = clips.first(where: { $0.id == clipId }), !clip.isAudioDetached else {
      return false
    }
    switch clip.source {
    case .primary:
      return !audioTrackRoles.isEmpty
    case .file:
      return true
    }
  }

  func selectAudioClip(id: UUID?) {
    selectedAudioClipId = id
    if id != nil {
      selectClip(id: nil)
      selectedTextOverlayId = nil
    }
    updateClipActionAvailability()
  }

  func commitAudioClipEdit(previousClips: [AudioTimelineClip]) {
    guard previousClips != audioClips else { return }
    recordAudioClipsUndo(previousClips: previousClips, previousSelected: selectedAudioClipId)
    syncPlayerAudioWithExportSettings()
    updateClipActionAvailability()
    updateHasUnsavedChanges()
  }

  func recordAudioClipsUndo(previousClips: [AudioTimelineClip], previousSelected _: UUID?) {
    guard previousClips != audioClips else { return }
    recordAction(.replaceAudioClips(old: previousClips, new: audioClips))
  }

  func moveAudioClip(id: UUID, to newStart: TimeInterval, trackIndex: Int? = nil) {
    guard let idx = audioClips.firstIndex(where: { $0.id == id }) else { return }
    audioClips[idx] = audioClips[idx].moved(to: newStart, trackIndex: trackIndex)
    syncAddedAudioPlayer()
    updateHasUnsavedChanges()
  }

  /// Move an audio clip up (`delta < 0`) or down (`delta > 0`) to the nearest non-overlapping
  /// audio track lane in that direction (with Undo). Does nothing if every lane in that direction
  /// already contains an overlapping clip.
  func moveAudioClipToAdjacentTrack(id: UUID, delta: Int) {
    guard delta != 0, let idx = audioClips.firstIndex(where: { $0.id == id }) else { return }
    let clip = audioClips[idx]
    let step = delta < 0 ? -1 : 1
    let bound = step < 0 ? 0 : (AudioTimelineClip.maxTrackCount - 1)
    guard (step < 0 && clip.trackIndex > 0) || (step > 0 && clip.trackIndex < bound) else { return }

    var resolvedLane: Int?
    for candidateLane in stride(from: clip.trackIndex + step, through: bound, by: step) {
      if AudioTimelineLaneLayout.isLaneFree(
        candidateLane,
        timelineStart: clip.timelineStart,
        timelineEnd: clip.timelineEnd,
        excludingClipId: clip.id,
        in: audioClips
      ) {
        resolvedLane = candidateLane
        break
      }
    }
    guard let targetLane = resolvedLane else {
      NSSound.beep()
      return
    }
    let before = audioClips
    audioClips[idx].trackIndex = targetLane
    commitAudioClipEdit(previousClips: before)
  }

  func trimAudioClipLeading(id: UUID, by deltaSeconds: TimeInterval) {
    guard let idx = audioClips.firstIndex(where: { $0.id == id }) else { return }
    audioClips[idx] = audioClips[idx].trimmedLeading(by: deltaSeconds)
    syncAddedAudioPlayer()
    updateHasUnsavedChanges()
  }

  func trimAudioClipTrailing(id: UUID, by deltaSeconds: TimeInterval) {
    guard let idx = audioClips.firstIndex(where: { $0.id == id }) else { return }
    audioClips[idx] = audioClips[idx].trimmedTrailing(by: deltaSeconds)
    syncAddedAudioPlayer()
    updateHasUnsavedChanges()
  }

  var selectedAudioClip: AudioTimelineClip? {
    guard let id = selectedAudioClipId else { return nil }
    return audioClips.first { $0.id == id }
  }

  func setAudioClipVolume(id: UUID, volume: Float) {
    guard let idx = audioClips.firstIndex(where: { $0.id == id }) else { return }
    let clamped = min(max(volume, 0), 2.0)
    guard abs(audioClips[idx].volume - clamped) > 0.001 else { return }
    let before = audioClips
    audioClips[idx].volume = clamped
    recordAudioClipsUndo(previousClips: before, previousSelected: selectedAudioClipId)
    syncAddedAudioPlayer()
    updateHasUnsavedChanges()
  }

  func setAudioClipFade(id: UUID, fadeIn: TimeInterval? = nil, fadeOut: TimeInterval? = nil) {
    guard let idx = audioClips.firstIndex(where: { $0.id == id }) else { return }
    if let fadeIn {
      audioClips[idx].fadeIn = ExportSettings.clampedAudioFade(fadeIn)
    }
    if let fadeOut {
      audioClips[idx].fadeOut = ExportSettings.clampedAudioFade(fadeOut)
    }
    if audioClips[idx].isPrimary, !usesIndependentAudioPlayback {
      var settings = exportSettings
      if let fadeIn {
        settings.setAudioFadeIn(fadeIn)
      }
      if let fadeOut {
        settings.setAudioFadeOut(fadeOut)
      }
      updateExportSettings(settings)
    } else {
      syncAddedAudioPlayer()
      updateHasUnsavedChanges()
    }
  }

  /// Commit an interactive audio fade drag or Reset Fades as 1 atomic Undo transaction
  /// capturing both `audioClips` and `exportSettings` (when primary fades mirror exportSettings).
  func commitAudioFadeEdit(
    previousClips: [AudioTimelineClip],
    previousExportSettings: ExportSettings
  ) {
    let clipsChanged = previousClips != audioClips
    let settingsChanged = previousExportSettings != exportSettings
    guard clipsChanged || settingsChanged else { return }

    beginUndoGroup()
    defer { endUndoGroup() }

    if clipsChanged {
      recordAudioClipsUndo(previousClips: previousClips, previousSelected: selectedAudioClipId)
    }
    if settingsChanged {
      recordAction(.updateExportSettings(old: previousExportSettings, new: exportSettings))
    }
    syncPlayerAudioWithExportSettings()
    updateClipActionAvailability()
    updateHasUnsavedChanges()
  }

  func toggleAudioClipMute(id: UUID) {
    guard let idx = audioClips.firstIndex(where: { $0.id == id }) else { return }
    let before = audioClips
    beginUndoGroup()
    defer { endUndoGroup() }

    audioClips[idx].isMuted.toggle()
    recordAudioClipsUndo(previousClips: before, previousSelected: selectedAudioClipId)

    if audioClips[idx].isPrimary, audioClips.filter(\.isPrimary).allSatisfy(\.isMuted) {
      var settings = exportSettings
      settings.audioMode = .mute
      updateExportSettingsRecordingUndo(settings)
    } else if audioClips[idx].isPrimary, exportSettings.audioMode == .mute {
      var settings = exportSettings
      settings.audioMode = .keep
      updateExportSettingsRecordingUndo(settings)
    } else {
      syncAddedAudioPlayer()
      updateHasUnsavedChanges()
    }
  }

  @discardableResult
  func splitAudioClip(id: UUID, at timelineTime: TimeInterval) -> (UUID, UUID)? {
    guard let idx = audioClips.firstIndex(where: { $0.id == id }) else { return nil }
    guard let (left, right) = audioClips[idx].split(at: timelineTime) else { return nil }
    let before = audioClips
    let beforeSel = selectedAudioClipId
    audioClips.replaceSubrange(idx ... idx, with: [left, right])
    selectedAudioClipId = right.id
    recordAudioClipsUndo(previousClips: before, previousSelected: beforeSel)
    syncPlayerAudioWithExportSettings()
    updateClipActionAvailability()
    updateHasUnsavedChanges()
    return (left.id, right.id)
  }

  /// Split every audio clip currently crossing `timelineTime` (used when cutting video so audio cuts too).
  @discardableResult
  func splitOverlappingAudioClips(at timelineTime: TimeInterval) -> Bool {
    var updated: [AudioTimelineClip] = []
    var didSplit = false
    for clip in audioClips {
      if let (left, right) = clip.split(at: timelineTime) {
        updated.append(left)
        updated.append(right)
        didSplit = true
      } else {
        updated.append(clip)
      }
    }
    if didSplit {
      audioClips = updated
      syncAddedAudioPlayer()
      updateHasUnsavedChanges()
    }
    return didSplit
  }

  func deleteAudioClip(id: UUID) {
    guard let idx = audioClips.firstIndex(where: { $0.id == id }) else { return }
    let before = audioClips
    let beforeSel = selectedAudioClipId
    beginUndoGroup()
    defer { endUndoGroup() }

    let removed = audioClips.remove(at: idx)
    if selectedAudioClipId == id {
      selectedAudioClipId = nil
    }
    recordAudioClipsUndo(previousClips: before, previousSelected: beforeSel)
    // If the user deleted the last primary audio clip, mute the underlying recording track
    // inside the same Undo group so one Cmd+Z restores both the clip and active audio mode.
    if removed.isPrimary, !audioClips.contains(where: \.isPrimary) {
      var settings = exportSettings
      settings.audioMode = .mute
      updateExportSettingsRecordingUndo(settings)
    }
    syncPlayerAudioWithExportSettings()
    updateClipActionAvailability()
    updateHasUnsavedChanges()
  }

  /// Audio-bearing URL backing an `AudioTimelineClip`.
  func waveformSourceURL(for audioClip: AudioTimelineClip) -> URL {
    switch audioClip.source {
    case .primary:
      Self.editorAssetURL(for: sourceURL, metadata: recordingMetadata)
    case .file(let url):
      url
    }
  }

  /// True when the primary recording's audio has been edited independently of the video
  /// (moved, trimmed differently from video, split, duplicated, deleted, detached, muted per-lane,
  /// or when video clips have black-screen gaps so audio plays linearly across them).
  var usesIndependentAudioPlayback: Bool {
    guard !isGIF else { return false }
    if hasDetachedAudioClips || !mutedAudioLanes.isEmpty {
      return true
    }
    let primaryAudio = audioClips.filter(\.isPrimary)
    if primaryAudio.count != 1 {
      return !audioTrackRoles.isEmpty
    }
    if hasVideoGaps {
      return true
    }
    guard let onlyPrimary = primaryAudio.first,
          clips.count == 1,
          let videoClip = clips.first,
          let videoPlacement = placements.first
    else {
      return true
    }
    return abs(onlyPrimary.timelineStart - videoPlacement.activeStart) > 0.02
      || abs(onlyPrimary.sourceStart - videoClip.sourceStart) > 0.02
      || abs(onlyPrimary.sourceEnd - videoClip.sourceEnd) > 0.02
  }

  /// Effective preview playback rate for companion `addedAudioPlayer` (`segmentRate * shuttle`).
  func effectiveAddedAudioPreviewRate() -> Float {
    let shuttle = playbackState.shuttleRate
    if shuttle < 0 {
      return 0
    }
    let transportMultiplier: Float = shuttle > 1.05 ? shuttle : 1.0
    let segmentRate = isGIF ? Float(1.0) : currentPreviewRate(at: playbackState.currentTime)
    return segmentRate * transportMultiplier
  }

  /// Sync the companion live-preview audio player with external `.file` audio clips
  /// (and `.primary` clips whenever primary audio is edited independently or runs past video).
  func syncAddedAudioPlayer() {
    let includePrimary = usesIndependentAudioPlayback || isPlayheadInVideoGap
    let configuredClips: [AudioTimelineClip] = exportSettings.audioMode == .mute
      ? audioClips.map { clip in
        guard clip.isPrimary else { return clip }
        var mutedCopy = clip
        mutedCopy.isMuted = true
        return mutedCopy
      }
      : audioClips
    addedAudioPlayer.configure(
      clips: configuredClips,
      includePrimary: includePrimary,
      urlProvider: { [weak self] clip in
        guard let self else { return clip.fileURL ?? URL(fileURLWithPath: "/") }
        return waveformSourceURL(for: clip)
      },
      isMasterMuted: isMuted,
      mutedLanes: mutedAudioLanes,
      playbackRateProvider: { [weak self] in
        guard let self else { return 1.0 }
        return effectiveAddedAudioPreviewRate()
      },
      timelineTimeProvider: { [weak self] in
        guard let self else { return 0 }
        return CMTimeGetSeconds(playbackState.currentTime)
      }
    )
    player.isMuted = shouldMutePreviewPlayer
  }

  // MARK: - Close Gap (Video Timeline)

  struct VideoTimelineGap: Identifiable, Equatable {
    let clipIndex: Int
    let start: TimeInterval
    let end: TimeInterval

    var id: Int {
      clipIndex
    }

    var duration: TimeInterval {
      max(0, end - start)
    }
  }

  /// Every empty black-screen gap preceding or between video clips on the structural timeline.
  var removableVideoGaps: [VideoTimelineGap] {
    guard !isGIF else { return [] }
    let laid = placements
    guard !laid.isEmpty else { return [] }

    var gaps: [VideoTimelineGap] = []
    var cursor: TimeInterval = 0
    for placement in laid {
      if placement.activeStart - cursor > 0.02 {
        gaps.append(VideoTimelineGap(clipIndex: placement.index, start: cursor, end: placement.activeStart))
      }
      cursor = placement.activeEnd
    }
    return gaps
  }

  var hasRemovableVideoGaps: Bool {
    !removableVideoGaps.isEmpty
  }

  /// Close the empty gap immediately preceding the clip at `clipIndex` (with single-step Undo).
  func closeGap(beforeClipIndex clipIndex: Int) {
    guard !isGIF, clips.indices.contains(clipIndex) else { return }
    var updated = clips
    let clip = updated[clipIndex]
    updated[clipIndex] = TimelineClip(
      id: clip.id,
      source: clip.source,
      sourceDuration: clip.sourceDuration,
      sourceStart: clip.sourceStart,
      sourceEnd: clip.sourceEnd,
      slotStart: clip.sourceStart,
      slotEnd: clip.slotEnd,
      leadingGap: 0,
      isAudioDetached: clip.isAudioDetached,
      leadingTransition: clip.leadingTransition
    )
    if clipIndex > 0 {
      let prev = updated[clipIndex - 1]
      updated[clipIndex - 1] = TimelineClip(
        id: prev.id,
        source: prev.source,
        sourceDuration: prev.sourceDuration,
        sourceStart: prev.sourceStart,
        sourceEnd: prev.sourceEnd,
        slotStart: prev.slotStart,
        slotEnd: prev.sourceEnd,
        leadingGap: prev.leadingGap,
        isAudioDetached: prev.isAudioDetached,
        leadingTransition: prev.leadingTransition
      )
    }
    applyClipsReplacing(updated, recordUndo: true)
  }

  /// Close every empty black-screen gap across the video clip sequence so clips abut cleanly from `0.0s`.
  func closeAllGaps() {
    guard !isGIF, !clips.isEmpty else { return }
    let updated = clips.map { clip in
      TimelineClip(
        id: clip.id,
        source: clip.source,
        sourceDuration: clip.sourceDuration,
        sourceStart: clip.sourceStart,
        sourceEnd: clip.sourceEnd,
        slotStart: clip.sourceStart,
        slotEnd: clip.sourceEnd,
        leadingGap: 0,
        isAudioDetached: clip.isAudioDetached,
        leadingTransition: clip.leadingTransition
      )
    }
    applyClipsReplacing(updated, recordUndo: true)
  }

  /// True if the currently selected video or audio clip can be split at the playhead.
  var canSplitAnyAtPlayhead: Bool {
    if let audioId = selectedAudioClipId,
       let clip = audioClips.first(where: { $0.id == audioId }) {
      return clip.split(at: CMTimeGetSeconds(currentTime)) != nil
    }
    return canSplitAtPlayhead
  }

  /// True if a selected text overlay, audio clip, or video clip (when >1 clips) can be deleted.
  var canDeleteAnySelected: Bool {
    selectedTextOverlayId != nil || selectedAudioClipId != nil || canDeleteSelectedClip
  }

  /// Unified Delete action for the timeline toolbar.
  func deleteSelectedTimelineItem() {
    if let textId = selectedTextOverlayId {
      removeTextOverlay(id: textId)
    } else if let audioId = selectedAudioClipId {
      deleteAudioClip(id: audioId)
    } else if let clipId = selectedClipId, clips.count > 1 {
      removeClip(id: clipId)
    }
  }

  // MARK: - Timeline Editing Actions

  /// Trim the leading edge of the selected video or audio clip right up to the playhead.
  func trimSelectedLeftToPlayhead() {
    let t = CMTimeGetSeconds(currentTime)
    if let audioId = selectedAudioClipId,
       let clip = audioClips.first(where: { $0.id == audioId }) {
      let delta = t - clip.timelineStart
      guard delta > 0.01, t < clip.timelineEnd - AudioTimelineClip.minDuration else { return }
      let before = audioClips
      trimAudioClipLeading(id: audioId, by: delta)
      commitAudioClipEdit(previousClips: before)
      return
    }
    if let clipId = selectedClipId,
       let placement = placements.first(where: { $0.clip.id == clipId }),
       t > placement.activeStart + 0.01,
       t < placement.activeEnd - TimelineClip.minDuration {
      let newSourceStart = placement.sourceTime(at: t)
      beginClipTrim(id: clipId)
      updateClip(id: clipId, sourceStart: newSourceStart)
      endClipTrim()
    }
  }

  /// Trim the trailing edge of the selected video or audio clip right back to the playhead.
  func trimSelectedRightToPlayhead() {
    let t = CMTimeGetSeconds(currentTime)
    if let audioId = selectedAudioClipId,
       let clip = audioClips.first(where: { $0.id == audioId }) {
      let delta = t - clip.timelineEnd
      guard delta < -0.01, t > clip.timelineStart + AudioTimelineClip.minDuration else { return }
      let before = audioClips
      trimAudioClipTrailing(id: audioId, by: delta)
      commitAudioClipEdit(previousClips: before)
      return
    }
    if let clipId = selectedClipId,
       let placement = placements.first(where: { $0.clip.id == clipId }),
       t > placement.activeStart + TimelineClip.minDuration,
       t < placement.activeEnd - 0.01 {
      let newSourceEnd = placement.sourceTime(at: t)
      beginClipTrim(id: clipId)
      updateClip(id: clipId, sourceEnd: newSourceEnd)
      endClipTrim()
    }
  }

  /// Duplicate the selected text overlay, audio clip, or video clip immediately after itself.
  func duplicateSelectedTimelineItem() {
    if let textId = selectedTextOverlayId {
      duplicateTextOverlay(id: textId)
      return
    }
    if let audioId = selectedAudioClipId,
       let clip = audioClips.first(where: { $0.id == audioId }) {
      let before = audioClips
      let placement = AudioTimelineLaneLayout.nonOverlappingPlacement(
        requestedStart: clip.timelineEnd,
        duration: clip.duration,
        in: audioClips,
        preferredTrack: clip.trackIndex
      )
      let copy = AudioTimelineClip(
        id: UUID(),
        source: clip.source,
        name: clip.name,
        timelineStart: placement.timelineStart,
        sourceDuration: clip.sourceDuration,
        sourceStart: clip.sourceStart,
        sourceEnd: clip.sourceEnd,
        volume: clip.volume,
        isMuted: clip.isMuted,
        fadeIn: clip.fadeIn,
        fadeOut: clip.fadeOut,
        trackIndex: placement.trackIndex
      )
      audioClips.append(copy)
      selectedAudioClipId = copy.id
      commitAudioClipEdit(previousClips: before)
      return
    }

    if let clipId = selectedClipId {
      duplicateClip(id: clipId)
    }
  }

  /// Toggle a timeline bookmark marker at the current playhead.
  func toggleBookmarkAtPlayhead() {
    let before = timelineBookmarks
    let t = max(0, CMTimeGetSeconds(currentTime))
    if let existingIdx = timelineBookmarks.firstIndex(where: { abs($0 - t) < 0.15 }) {
      timelineBookmarks.remove(at: existingIdx)
    } else {
      timelineBookmarks.append(t)
      timelineBookmarks.sort()
    }
    recordAction(.replaceTimelineBookmarks(old: before, new: timelineBookmarks))
    updateClipActionAvailability()
    updateHasUnsavedChanges()
  }

  func removeBookmark(at timestamp: TimeInterval) {
    let before = timelineBookmarks
    timelineBookmarks.removeAll { abs($0 - timestamp) < 0.01 }
    guard timelineBookmarks != before else { return }
    recordAction(.replaceTimelineBookmarks(old: before, new: timelineBookmarks))
    updateClipActionAvailability()
    updateHasUnsavedChanges()
  }

  var hasBookmarkNearPlayhead: Bool {
    let t = CMTimeGetSeconds(currentTime)
    return timelineBookmarks.contains { abs($0 - t) < 0.15 }
  }

  var canDuplicateSelected: Bool {
    selectedTextOverlayId != nil || selectedAudioClipId != nil || selectedClipId != nil
  }

  // MARK: - Black-Screen Gap Playback (Leading, Middle, or Audio-Only Tail)

  func startGapPlayback(
    until targetEnd: TimeInterval,
    resumePlacement: TimelineSequence.Placement?,
    forceSeek: Bool = true
  ) {
    stopReverseShuttleTimer()
    stopAudioTailPlayback()
    player.pause()
    playbackState.setPlaying(true)
    if playbackState.shuttleRate <= 0 {
      playbackState.setShuttleRate(1)
    }
    syncAddedAudioPlayer()
    let startTimelineTime = CMTimeGetSeconds(playbackState.currentTime)
    let rate = max(1.0, Double(playbackState.shuttleRate))
    if rate <= 1.05 {
      addedAudioPlayer.play(at: startTimelineTime, forceSeek: forceSeek)
    } else {
      addedAudioPlayer.pause()
    }

    var lastTickHostTime = CACurrentMediaTime()
    var currentGapTime = startTimelineTime
    let step: TimeInterval = 1.0 / 60.0
    audioTailPlaybackTimer = Timer.scheduledTimer(withTimeInterval: step, repeats: true) { [weak self] timer in
      guard self != nil else {
        timer.invalidate()
        return
      }
      Task { @MainActor [weak self] in
        guard let self, playbackState.isPlaying else { return }
        let nowHost = CACurrentMediaTime()
        let dt = min(0.1, max(0, nowHost - lastTickHostTime))
        lastTickHostTime = nowHost
        let liveRate = max(1.0, Double(playbackState.shuttleRate))
        currentGapTime += dt * liveRate
        let nextTime = currentGapTime
        if nextTime >= targetEnd {
          stopAudioTailPlayback()
          if let resumePlacement,
             let liveClip = clips.first(where: { $0.id == resumePlacement.clip.id }) {
            let liveStart = placements.first(where: { $0.clip.id == liveClip.id })?.activeStart
              ?? resumePlacement.activeStart
            playbackState.setCurrentTime(CMTime(seconds: liveStart, preferredTimescale: 600))
            updateClipActionAvailability()
            resumeVideoPlayback(for: liveClip)
            if playbackState.shuttleRate > 1.05 {
              player.defaultRate = playbackState.shuttleRate
              player.rate = playbackState.shuttleRate
              addedAudioPlayer.pause()
            }
          } else {
            addedAudioPlayer.pause()
            playbackState.setShuttleRate(0)
            playbackState.setPlaying(false)
            playbackState.setCurrentTime(CMTime(seconds: targetEnd, preferredTimescale: 600))
            updateClipActionAvailability()
          }
        } else {
          playbackState.setCurrentTime(CMTime(seconds: nextTime, preferredTimescale: 600))
          updateClipActionAvailability()
        }
      }
    }
  }

  func stopAudioTailPlayback() {
    audioTailPlaybackTimer?.invalidate()
    audioTailPlaybackTimer = nil
  }
}
