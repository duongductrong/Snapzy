//
//  VideoEditorState+TextOverlays.swift
//  Snapzy
//
//  Timeline Text / Title Overlay (`Aa`) management on VideoEditorState, including
//  studio presets, motion preview, and atomic Undo-safe bidirectional integration
//  with Captions.
//

import AppKit
import AVFoundation
import Foundation

extension VideoEditorState {
  var selectedTextOverlay: VideoEditorTextOverlay? {
    guard let id = selectedTextOverlayId else { return nil }
    return textOverlays.first { $0.id == id }
  }

  /// Active text overlays visible at `timelineTime` in bottom-to-top track z-order.
  func activeTextOverlays(at timelineTime: TimeInterval) -> [VideoEditorTextOverlay] {
    textOverlays
      .filter { $0.contains(time: timelineTime) }
      .sorted { lhs, rhs in
        if lhs.trackIndex != rhs.trackIndex {
          return lhs.trackIndex < rhs.trackIndex
        }
        return lhs.startTime < rhs.startTime
      }
  }

  func addTextTrackLane() {
    guard !isGIF, textLaneCount < TextTimelineLaneLayout.maxLanes else { return }
    minimumTextLanes = min(TextTimelineLaneLayout.maxLanes, textLaneCount + 1)
  }

  @discardableResult
  func addTextOverlay(
    text: String = L10n.VideoEditor.defaultTitleText,
    at startTime: TimeInterval? = nil,
    duration requestedDuration: TimeInterval = VideoEditorTextOverlay.defaultDuration,
    preset: VideoEditorCaptionSettings.EditorialPreset? = nil,
    preferredTrack: Int? = nil
  ) -> VideoEditorTextOverlay? {
    guard !isGIF else { return nil }
    let axisDuration = max(0.2, CMTimeGetSeconds(timelineDuration))
    let rawStart = startTime ?? CMTimeGetSeconds(currentTime)
    let clampedStart = max(0, min(rawStart, max(0, axisDuration - VideoEditorTextOverlay.minDuration)))
    let clampedDuration = max(
      VideoEditorTextOverlay.minDuration,
      min(requestedDuration, max(VideoEditorTextOverlay.minDuration, axisDuration - clampedStart))
    )

    guard let resolvedPlacement = TextTimelineLaneLayout.nonOverlappingPlacement(
      requestedStart: clampedStart,
      duration: clampedDuration,
      axisDuration: axisDuration,
      existing: textOverlays,
      preferredTrack: preferredTrack ?? selectedTextOverlay?.trackIndex ?? 0
    ) else {
      NSSound.beep()
      return nil
    }

    var overlay = VideoEditorTextOverlay(
      text: text,
      startTime: resolvedPlacement.start,
      duration: resolvedPlacement.duration,
      trackIndex: resolvedPlacement.trackIndex
    )
    if let preset {
      overlay.applyPreset(preset)
    }

    let before = textOverlays
    textOverlays.append(overlay)
    selectTextOverlay(id: overlay.id)
    recordAction(.replaceTextOverlays(old: before, new: textOverlays))
    updateClipActionAvailability()
    updateHasUnsavedChanges()
    return overlay
  }

  /// Triggered by the `T` shortcut or `+ Add Text` UI button: creates a title
  /// `cyberCyan` title at the current playhead and opens the Text Studio inspector.
  func addTextOverlayAtPlayheadAndOpenPanel(
    preset: VideoEditorCaptionSettings.EditorialPreset = .cyberCyan
  ) {
    guard !isGIF else { return }
    guard addTextOverlay(
      at: CMTimeGetSeconds(currentTime),
      preset: preset
    ) != nil else {
      return
    }
    leftSidebarPanel = .text
    isLeftSidebarVisible = true
  }

  /// Apply a studio preset to `id` (or create a new overlay with `preset` if none selected).
  func applyTextPreset(_ preset: VideoEditorCaptionSettings.EditorialPreset, to id: UUID? = nil) {
    guard !isGIF else { return }
    if let targetId = id ?? selectedTextOverlayId ?? textOverlays.last?.id,
       textOverlays.contains(where: { $0.id == targetId }) {
      selectTextOverlay(id: targetId)
      updateTextOverlay(id: targetId) { item in
        item.applyPreset(preset)
      }
    } else {
      addTextOverlayAtPlayheadAndOpenPanel(preset: preset)
    }
  }

  /// Seek to the leading edge of the selected (or first) Text Overlay and play so the user
  /// can inspect its entrance, specular sheen, and exit motion in real time.
  func previewTextOverlayMotion(id: UUID? = nil) {
    guard !isGIF else { return }
    let target = (id.flatMap { tid in textOverlays.first { $0.id == tid } })
      ?? selectedTextOverlay
      ?? textOverlays.first
    guard let overlay = target else { return }
    selectTextOverlay(id: overlay.id)
    seek(to: CMTime(seconds: max(0, overlay.startTime), preferredTimescale: 600))
    if !playbackState.isPlaying {
      play()
    }
  }

  func selectTextOverlay(id: UUID?) {
    selectedTextOverlayId = id
    selectedTextOverlayIds = id.map { [$0] } ?? []
    if id != nil {
      selectClip(id: nil)
      selectedAudioClipId = nil
      selectedAudioClipIds = []
      selectedCaptionId = nil
      selectedCaptionIds = []
      selectedZoomId = nil
      selectedSpeedId = nil
    }
    updateClipActionAvailability()
  }

  func selectCaption(id: UUID?) {
    selectedCaptionId = id
    selectedCaptionIds = id.map { [$0] } ?? []
    if id != nil {
      selectClip(id: nil)
      selectedTextOverlayId = nil
      selectedTextOverlayIds = []
      selectedAudioClipId = nil
      selectedAudioClipIds = []
      selectedZoomId = nil
      selectedSpeedId = nil
    }
    updateClipActionAvailability()
  }

  /// `⌘A` track-wide Select All across Captions, Text Overlays, and Audio Clips.
  @discardableResult
  func selectAllInActiveTrack() -> Bool {
    guard !isGIF else { return false }

    // 1. Captions track active or selected
    if selectedCaptionId != nil || !selectedCaptionIds.isEmpty
      || (isLeftSidebarVisible && leftSidebarPanel == .captions && !captions.segments.isEmpty) {
      let allIds = Set(captions.segments.map(\.id))
      guard !allIds.isEmpty else { return false }
      selectedCaptionIds = allIds
      selectedCaptionId = selectedCaptionId ?? captions.segments.first?.id
      selectedTextOverlayId = nil
      selectedTextOverlayIds = []
      selectedAudioClipId = nil
      selectedAudioClipIds = []
      selectClip(id: nil)
      selectedZoomId = nil
      selectedSpeedId = nil
      updateClipActionAvailability()
      return true
    }

    // 2. Text track active or selected
    if selectedTextOverlayId != nil || !selectedTextOverlayIds.isEmpty
      || (isLeftSidebarVisible && leftSidebarPanel == .text && !textOverlays.isEmpty) {
      let allIds = Set(textOverlays.map(\.id))
      guard !allIds.isEmpty else { return false }
      selectedTextOverlayIds = allIds
      selectedTextOverlayId = selectedTextOverlayId ?? textOverlays.first?.id
      selectedCaptionId = nil
      selectedCaptionIds = []
      selectedAudioClipId = nil
      selectedAudioClipIds = []
      selectClip(id: nil)
      selectedZoomId = nil
      selectedSpeedId = nil
      updateClipActionAvailability()
      return true
    }

    // 3. Audio track selected
    if selectedAudioClipId != nil || !selectedAudioClipIds.isEmpty {
      let allIds = Set(audioClips.map(\.id))
      guard !allIds.isEmpty else { return false }
      selectedAudioClipIds = allIds
      selectedAudioClipId = selectedAudioClipId ?? audioClips.first?.id
      selectedCaptionId = nil
      selectedCaptionIds = []
      selectedTextOverlayId = nil
      selectedTextOverlayIds = []
      selectClip(id: nil)
      selectedZoomId = nil
      selectedSpeedId = nil
      updateClipActionAvailability()
      return true
    }

    return false
  }

  /// Bulk delete all selected items on the active track (Captions, Text, Audio) or single
  /// selected Zoom / Speed / Video clip — always in 1 atomic Undo step.
  @discardableResult
  func deleteSelectedTrackItems() -> Bool {
    if !selectedCaptionIds.isEmpty || selectedCaptionId != nil {
      return deleteSelectedCaptions()
    }
    if selectedTextOverlayIds.count > 1 {
      return removeSelectedTextOverlays()
    }
    if let textId = selectedTextOverlayId {
      removeTextOverlay(id: textId)
      return true
    }
    if selectedAudioClipIds.count > 1 {
      return deleteSelectedAudioClips()
    }
    if let audioId = selectedAudioClipId {
      deleteAudioClip(id: audioId)
      return true
    }
    if let zoomId = selectedZoomId {
      removeZoom(id: zoomId)
      return true
    }
    if let speedId = selectedSpeedId {
      removeSpeed(id: speedId)
      return true
    }
    if canDeleteSelectedClip {
      deleteSelectedClip()
      return true
    }
    return false
  }

  @discardableResult
  func deleteSelectedCaptions() -> Bool {
    var idsToRemove = selectedCaptionIds
    if let single = selectedCaptionId {
      idsToRemove.insert(single)
    }
    guard !idsToRemove.isEmpty else { return false }
    let oldCaptions = captions
    var nextCaptions = captions
    nextCaptions.segments.removeAll { idsToRemove.contains($0.id) }
    guard nextCaptions != oldCaptions else { return false }
    applyCaptions(nextCaptions)
    selectedCaptionId = nil
    selectedCaptionIds = []
    recordAction(.updateCaptions(old: oldCaptions, new: nextCaptions))
    updateClipActionAvailability()
    updateHasUnsavedChanges()
    return true
  }

  @discardableResult
  func removeSelectedTextOverlays() -> Bool {
    var idsToRemove = selectedTextOverlayIds
    if let single = selectedTextOverlayId {
      idsToRemove.insert(single)
    }
    guard !idsToRemove.isEmpty else { return false }
    let before = textOverlays
    textOverlays.removeAll { idsToRemove.contains($0.id) }
    guard textOverlays != before else { return false }
    selectedTextOverlayId = nil
    selectedTextOverlayIds = []
    recordAction(.replaceTextOverlays(old: before, new: textOverlays))
    updateClipActionAvailability()
    updateHasUnsavedChanges()
    return true
  }

  @discardableResult
  func deleteSelectedAudioClips() -> Bool {
    var idsToRemove = selectedAudioClipIds
    if let single = selectedAudioClipId {
      idsToRemove.insert(single)
    }
    guard !idsToRemove.isEmpty else { return false }
    let before = audioClips
    let beforeSel = selectedAudioClipId
    let removedPrimary = audioClips.contains { idsToRemove.contains($0.id) && $0.isPrimary }
    let remaining = audioClips.filter { !idsToRemove.contains($0.id) }
    guard remaining != before else { return false }

    beginUndoGroup()
    defer { endUndoGroup() }

    audioClips = remaining
    selectedAudioClipId = nil
    selectedAudioClipIds = []
    recordAudioClipsUndo(previousClips: before, previousSelected: beforeSel)
    if removedPrimary, !audioClips.contains(where: \.isPrimary) {
      var settings = exportSettings
      settings.audioMode = .mute
      updateExportSettingsRecordingUndo(settings)
    }
    syncPlayerAudioWithExportSettings()
    updateClipActionAvailability()
    updateHasUnsavedChanges()
    return true
  }

  /// Apply the selected Text Overlay's style (and optionally motion) to ALL text overlays
  /// on the same track or across all text tracks in 1 atomic Undo step.
  @discardableResult
  func applySelectedTextStyleToAll(includeMotion: Bool, trackOnly: Bool = false) -> Int {
    guard let source = selectedTextOverlay ?? textOverlays.last else { return 0 }
    let before = textOverlays
    var updatedCount = 0
    for idx in textOverlays.indices {
      if textOverlays[idx].id == source.id {
        continue
      }
      if trackOnly, textOverlays[idx].trackIndex != source.trackIndex {
        continue
      }
      var nextStyle = source.style
      if !includeMotion {
        let existing = textOverlays[idx].style
        nextStyle.animationIn = existing.animationIn
        nextStyle.animationOut = existing.animationOut
        nextStyle.animationDuration = existing.animationDuration
        nextStyle.wordMode = existing.wordMode
        nextStyle.wordAnimation = existing.wordAnimation
        nextStyle.shimmerSweep = existing.shimmerSweep
      }
      textOverlays[idx].style = nextStyle
      textOverlays[idx].syncLegacyMirrorFromStyle()
      textOverlays[idx].style.fontSize = nextStyle.fontSize
      updatedCount += 1
    }
    guard updatedCount > 0 else { return 0 }
    recordAction(.replaceTextOverlays(old: before, new: textOverlays))
    updateHasUnsavedChanges()
    return updatedCount
  }

  /// Apply ONLY the selected Text Overlay's motion (`In`/`Out`, `wordMode`, `wordAnimation`,
  /// `specularSheen`, `animationDuration`) to ALL text overlays in 1 atomic Undo step.
  @discardableResult
  func applySelectedTextMotionToAll(trackOnly: Bool = false) -> Int {
    guard let source = selectedTextOverlay ?? textOverlays.last else { return 0 }
    let before = textOverlays
    var updatedCount = 0
    for idx in textOverlays.indices {
      if textOverlays[idx].id == source.id {
        continue
      }
      if trackOnly, textOverlays[idx].trackIndex != source.trackIndex {
        continue
      }
      textOverlays[idx].style.animationIn = source.style.animationIn
      textOverlays[idx].style.animationOut = source.style.animationOut
      textOverlays[idx].style.animationDuration = source.style.animationDuration
      textOverlays[idx].style.wordMode = source.style.wordMode
      textOverlays[idx].style.wordAnimation = source.style.wordAnimation
      textOverlays[idx].style.shimmerSweep = source.style.shimmerSweep
      updatedCount += 1
    }
    guard updatedCount > 0 else { return 0 }
    recordAction(.replaceTextOverlays(old: before, new: textOverlays))
    updateHasUnsavedChanges()
    return updatedCount
  }

  func updateTextOverlay(
    id: UUID,
    recordUndo: Bool = true,
    mutate: (inout VideoEditorTextOverlay) -> Void
  ) {
    guard let idx = textOverlays.firstIndex(where: { $0.id == id }) else { return }
    let before = textOverlays
    var edited = textOverlays[idx]
    mutate(&edited)
    let axisDuration = max(0.2, CMTimeGetSeconds(timelineDuration))
    edited.startTime = max(0, min(edited.startTime, max(0, axisDuration - VideoEditorTextOverlay.minDuration)))
    edited.duration = max(
      VideoEditorTextOverlay.minDuration,
      min(edited.duration, max(VideoEditorTextOverlay.minDuration, axisDuration - edited.startTime))
    )
    edited.normalizedX = VideoEditorTextOverlay.clampNormalizedX(edited.normalizedX)
    edited.normalizedY = VideoEditorTextOverlay.clampNormalizedY(edited.normalizedY)
    edited.style.maxWidthFraction = VideoEditorCaptionSettings.clampMaxWidthFraction(
      edited.style.maxWidthFraction
    )
    let originalStyleFontSize = before[idx].style.fontSize
    if abs(edited.style.fontSize - originalStyleFontSize) > 0.00001 {
      let clampedStyleFontSize = min(
        VideoEditorCaptionSettings.fontSizeRange.upperBound,
        max(VideoEditorCaptionSettings.fontSizeRange.lowerBound, edited.style.fontSize)
      )
      edited.fontSize = VideoEditorTextOverlay.clampFontSize(clampedStyleFontSize * 720.0)
      edited.style.fontSize = clampedStyleFontSize
    } else {
      edited.fontSize = VideoEditorTextOverlay.clampFontSize(edited.fontSize)
    }
    guard edited != textOverlays[idx] else { return }
    textOverlays[idx] = edited
    if recordUndo {
      recordAction(.replaceTextOverlays(old: before, new: textOverlays))
    }
    updateHasUnsavedChanges()
  }

  func commitTextOverlayEdit(previous: [VideoEditorTextOverlay]) {
    guard previous != textOverlays else { return }
    recordAction(.replaceTextOverlays(old: previous, new: textOverlays))
    updateHasUnsavedChanges()
  }

  func removeTextOverlay(id: UUID) {
    guard let idx = textOverlays.firstIndex(where: { $0.id == id }) else { return }
    let before = textOverlays
    textOverlays.remove(at: idx)
    if selectedTextOverlayId == id || selectedTextOverlayIds.contains(id) {
      let nextId = textOverlays.indices.contains(idx) ? textOverlays[idx].id : textOverlays.last?.id
      selectedTextOverlayId = nextId
      selectedTextOverlayIds = nextId.map { [$0] } ?? []
    }
    recordAction(.replaceTextOverlays(old: before, new: textOverlays))
    updateClipActionAvailability()
    updateHasUnsavedChanges()
  }

  func duplicateTextOverlay(id: UUID) {
    guard let source = textOverlays.first(where: { $0.id == id }) else { return }
    let axisDuration = max(0.2, CMTimeGetSeconds(timelineDuration))
    let proposedStart = source.endTime < axisDuration - VideoEditorTextOverlay.minDuration
      ? source.endTime
      : max(0, min(source.startTime + 0.5, axisDuration - VideoEditorTextOverlay.minDuration))
    let clampedDuration = max(
      VideoEditorTextOverlay.minDuration,
      min(source.duration, max(VideoEditorTextOverlay.minDuration, axisDuration - proposedStart))
    )
    guard let resolvedPlacement = TextTimelineLaneLayout.nonOverlappingPlacement(
      requestedStart: proposedStart,
      duration: clampedDuration,
      axisDuration: axisDuration,
      existing: textOverlays,
      preferredTrack: source.trackIndex
    ) else {
      return
    }
    let copy = VideoEditorTextOverlay(
      id: UUID(),
      text: source.text,
      startTime: resolvedPlacement.start,
      duration: resolvedPlacement.duration,
      normalizedX: source.normalizedX,
      normalizedY: source.normalizedY,
      fontSize: source.fontSize,
      textColorHex: source.textColorHex,
      backgroundColorHex: source.backgroundColorHex,
      hasBackground: source.hasBackground,
      isBold: source.isBold,
      isEnabled: source.isEnabled,
      animation: source.animation,
      style: source.style,
      trackIndex: resolvedPlacement.trackIndex
    )
    let before = textOverlays
    textOverlays.append(copy)
    selectTextOverlay(id: copy.id)
    recordAction(.replaceTextOverlays(old: before, new: textOverlays))
    updateClipActionAvailability()
    updateHasUnsavedChanges()
  }

  // MARK: - Bidirectional Text (`Aa`) and Captions Bridge

  /// Copy the selected Text Overlay's typography, surface format, colors, glow,
  /// and In/Out motion directly onto the global `Captions` track (1 Undo step).
  func syncSelectedTextStyleToCaptions() {
    guard let sourceOverlay = selectedTextOverlay ?? textOverlays.last else { return }
    var nextSettings = sourceOverlay.style
    nextSettings.languageIdentifier = captions.settings.languageIdentifier
    nextSettings.wordMode = captions.settings.wordMode
    nextSettings.hideDuringFastSpeed = captions.settings.hideDuringFastSpeed
    nextSettings.isEnabled = true
    if sourceOverlay.normalizedY < 0.30 {
      nextSettings.position = .top
    } else if sourceOverlay.normalizedY < 0.65 {
      nextSettings.position = .center
    } else {
      nextSettings.position = .bottom
    }
    setCaptionSettings(nextSettings)
  }

  /// Copy the `Captions` track's style onto the selected Text Overlay (1 Undo step).
  func syncCaptionsStyleToSelectedText() {
    guard let targetId = selectedTextOverlayId ?? textOverlays.last?.id else { return }
    let capStyle = captions.settings
    updateTextOverlay(id: targetId) { item in
      var s = capStyle
      s.isEnabled = true
      item.style = s
      item.syncLegacyMirrorFromStyle()
    }
  }

  /// Promote a single Caption segment into an independent, freely-draggable `Text` (`Aa`)
  /// overlay at its exact timeline timestamp and open it in the Text Studio (atomic 1-step Undo).
  @discardableResult
  func promoteCaptionToTextOverlay(
    captionId: UUID,
    removeCaption: Bool = true
  ) -> VideoEditorTextOverlay? {
    guard !isGIF,
          let segIdx = captions.segments.firstIndex(where: { $0.id == captionId })
    else { return nil }
    let segment = captions.segments[segIdx]

    guard let mapped = timelineSpan(forCaption: segment) else { return nil }
    let oldOverlays = textOverlays
    let oldCaptions = captions

    var inheritedStyle = captions.settings
    inheritedStyle.isEnabled = true
    if inheritedStyle == .default {
      inheritedStyle.apply(preset: .cyberCyan)
    }

    let targetY: CGFloat = switch captions.settings.position {
    case .top: max(0.12, captions.settings.margin + 0.08)
    case .center: 0.50
    case .bottom: min(0.88, 1.0 - max(0.12, captions.settings.margin + 0.08))
    }

    guard let targetTrack = (0 ..< TextTimelineLaneLayout.maxLanes).first(where: { lane in
      TextTimelineLaneLayout.isLaneFree(
        lane,
        start: mapped.start,
        duration: mapped.duration,
        existing: textOverlays
      )
    }) else {
      NSSound.beep()
      return nil
    }

    let created = VideoEditorTextOverlay(
      text: segment.text,
      startTime: mapped.start,
      duration: mapped.duration,
      normalizedX: 0.5,
      normalizedY: targetY,
      style: inheritedStyle,
      trackIndex: targetTrack
    )

    textOverlays.append(created)
    textOverlays.sort { $0.startTime < $1.startTime }

    var actions: [EditorAction] = [.replaceTextOverlays(old: oldOverlays, new: textOverlays)]
    if removeCaption {
      var nextCaptions = captions
      nextCaptions.segments.remove(at: segIdx)
      applyCaptions(nextCaptions)
      actions.append(.updateCaptions(old: oldCaptions, new: nextCaptions))
    }

    recordAction(actions.count == 1 ? actions[0] : .group(actions))
    selectTextOverlay(id: created.id)
    seek(to: CMTime(seconds: created.startTime + min(0.15, created.duration * 0.25), preferredTimescale: 600))
    leftSidebarPanel = .text
    isLeftSidebarVisible = true
    updateClipActionAvailability()
    updateHasUnsavedChanges()
    return created
  }

  /// Convert all visible Captions into independent `Text` (`Aa`) overlays and **delete all
  /// converted captions** so only Text overlays remain (zero duplicate rendering, zero leftover
  /// caption clips). Wrapped in 1 atomic Undo step so `⌘Z` restores the original captions cleanly.
  @discardableResult
  func convertAllCaptionsToTextOverlays() -> Int {
    guard !isGIF, !captions.segments.isEmpty else { return 0 }
    let oldOverlays = textOverlays
    let oldCaptions = captions

    var baseStyle = captions.settings
    baseStyle.isEnabled = true
    if baseStyle == .default {
      baseStyle.apply(preset: .cyberCyan)
    }
    let targetY: CGFloat = switch captions.settings.position {
    case .top: max(0.12, captions.settings.margin + 0.08)
    case .center: 0.50
    case .bottom: min(0.88, 1.0 - max(0.12, captions.settings.margin + 0.08))
    }

    var built: [VideoEditorTextOverlay] = []
    var workingOverlays = textOverlays
    for seg in captions.segments {
      let trimmed = seg.text.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !trimmed.isEmpty, let span = timelineSpan(forCaption: seg) else { continue }
      // Avoid creating an exact duplicate if an identical text overlay already exists at the same timestamp.
      let alreadyExists = workingOverlays.contains { existing in
        existing.text.trimmingCharacters(in: .whitespacesAndNewlines) == trimmed
          && abs(existing.startTime - span.start) < 0.05
          && abs(existing.duration - span.duration) < 0.05
      }
      if alreadyExists {
        continue
      }
      let lane = TextTimelineLaneLayout.firstAvailableTrackIndex(
        start: span.start,
        duration: span.duration,
        existing: workingOverlays,
        preferredTrack: 0
      )
      let overlay = VideoEditorTextOverlay(
        text: trimmed,
        startTime: span.start,
        duration: span.duration,
        normalizedX: 0.5,
        normalizedY: targetY,
        style: baseStyle,
        trackIndex: lane
      )
      built.append(overlay)
      workingOverlays.append(overlay)
    }
    guard !built.isEmpty else {
      // Even if all segments were duplicates, still clear captions so no duplicate captions remain.
      var clearedCaptions = captions
      clearedCaptions.segments = []
      clearedCaptions.settings.isEnabled = false
      applyCaptions(clearedCaptions)
      selectedCaptionId = nil
      selectedCaptionIds = []
      recordAction(.updateCaptions(old: oldCaptions, new: clearedCaptions))
      updateClipActionAvailability()
      updateHasUnsavedChanges()
      return 0
    }

    textOverlays.append(contentsOf: built)
    textOverlays.sort { lhs, rhs in
      if lhs.trackIndex != rhs.trackIndex {
        return lhs.trackIndex < rhs.trackIndex
      }
      return lhs.startTime < rhs.startTime
    }

    // Delete all captions cleanly so only Text overlays remain (zero duplicates).
    var nextCaptions = captions
    nextCaptions.segments = []
    nextCaptions.settings.isEnabled = false
    applyCaptions(nextCaptions)
    selectedCaptionId = nil
    selectedCaptionIds = []

    recordAction(.group([
      .replaceTextOverlays(old: oldOverlays, new: textOverlays),
      .updateCaptions(old: oldCaptions, new: nextCaptions),
    ]))

    if let firstId = built.first?.id {
      selectTextOverlay(id: firstId)
      seek(to: CMTime(seconds: built[0].startTime + min(0.15, built[0].duration * 0.25), preferredTimescale: 600))
    }
    leftSidebarPanel = .text
    isLeftSidebarVisible = true
    updateClipActionAvailability()
    updateHasUnsavedChanges()
    return built.count
  }

  /// Convert a `Text` (`Aa`) overlay back into a `CaptionSegment` on the Captions track
  /// mapped to the primary recording's source timeline (atomic 1-step Undo).
  @discardableResult
  func convertTextOverlayToCaption(
    id: UUID,
    removeOverlay: Bool = true
  ) -> CaptionSegment? {
    guard !isGIF,
          let idx = textOverlays.firstIndex(where: { $0.id == id })
    else { return nil }
    let overlay = textOverlays[idx]
    let totalSource = max(0.5, CMTimeGetSeconds(duration))

    let srcStart = cursorSourceTime(atSequence: overlay.startTime)
      ?? placements.first(where: { $0.clip.isPrimary })?.clip.sourceStart
      ?? 0
    let rawSrcEnd = cursorSourceTime(atSequence: max(overlay.startTime + 0.1, overlay.endTime - 0.01))
      ?? (srcStart + overlay.duration)
    let clampedStart = max(0, min(srcStart, totalSource - 0.25))
    let clampedEnd = max(clampedStart + 0.25, min(totalSource, rawSrcEnd))

    let newSegment = CaptionSegment(
      sourceRange: clampedStart ... clampedEnd,
      text: overlay.text
    )

    let oldCaptions = captions
    let oldOverlays = textOverlays

    var nextCaptions = captions
    if nextCaptions.segments.isEmpty {
      nextCaptions.settings = overlay.style
    }
    nextCaptions.settings.isEnabled = true
    nextCaptions.segments.append(newSegment)
    applyCaptions(nextCaptions)

    var actions: [EditorAction] = [.updateCaptions(old: oldCaptions, new: nextCaptions)]
    if removeOverlay {
      textOverlays.remove(at: idx)
      if selectedTextOverlayId == id {
        selectedTextOverlayId = textOverlays.last?.id
      }
      actions.append(.replaceTextOverlays(old: oldOverlays, new: textOverlays))
    }

    recordAction(actions.count == 1 ? actions[0] : .group(actions))
    leftSidebarPanel = .captions
    isLeftSidebarVisible = true
    updateClipActionAvailability()
    updateHasUnsavedChanges()
    return newSegment
  }

  private func timelineSpan(forCaption segment: CaptionSegment) -> (start: TimeInterval, duration: TimeInterval)? {
    let axisDuration = max(0.2, CMTimeGetSeconds(timelineDuration))
    for placement in placements where placement.clip.isPrimary {
      let s = max(segment.start, placement.sourceAxisStart)
      let e = min(segment.end, placement.sourceAxisEnd)
      guard e - s > 0.05 else { continue }
      let seqStart = max(0, min(placement.sequenceTime(atSource: s), axisDuration - VideoEditorTextOverlay.minDuration))
      let seqEnd = max(
        seqStart + VideoEditorTextOverlay.minDuration,
        min(axisDuration, placement.sequenceTime(atSource: e))
      )
      return (seqStart, seqEnd - seqStart)
    }
    return nil
  }
}

// MARK: - Pure Timeline Ripple Cut & Gap-Collapse Sync for Text Overlays

nonisolated enum VideoEditorTimelineTextCut {
  /// Ripple-cut timeline text overlays along removed structural spans (matching
  /// `VideoEditorTimelineCut.cutAudioClips`), shifting later overlays left, shortening
  /// overlays that cross a removed span, and dropping overlays shorter than `minDuration`.
  static func cutTextOverlays(
    _ overlays: [VideoEditorTextOverlay],
    removing removed: [ClosedRange<TimeInterval>]
  ) -> [VideoEditorTextOverlay] {
    let spans = VideoEditorTimelineCut.merged(removed)
    guard !spans.isEmpty, !overlays.isEmpty else { return overlays }

    var output: [VideoEditorTextOverlay] = []
    output.reserveCapacity(overlays.count)

    for overlay in overlays {
      guard let shiftedRange = VideoEditorTimelineCut.shifted(
        start: overlay.startTime,
        end: overlay.endTime,
        removing: spans,
        minDuration: VideoEditorTextOverlay.minDuration
      ) else {
        continue
      }
      var copy = overlay
      copy.startTime = max(0, shiftedRange.lowerBound)
      copy.duration = max(
        VideoEditorTextOverlay.minDuration,
        shiftedRange.upperBound - shiftedRange.lowerBound
      )
      output.append(copy)
    }

    return output
  }

  /// Compute structural empty/inactive spans collapsed when replacing `oldClips` with `newClips`
  /// (such as `closeGap` and `closeAllGaps`), so timeline text overlays stay locked to footage
  /// and within the updated timeline bounds.
  static func collapsedGapSpans(
    from oldClips: [TimelineClip],
    to newClips: [TimelineClip]
  ) -> [ClosedRange<TimeInterval>] {
    guard oldClips.count == newClips.count,
          zip(oldClips, newClips).allSatisfy({ $0.0.id == $0.1.id })
    else {
      return []
    }
    let oldPlacements = TimelineSequence.layout(oldClips)
    let newPlacements = TimelineSequence.layout(newClips)
    guard oldPlacements.count == newPlacements.count else { return [] }

    var spans: [ClosedRange<TimeInterval>] = []
    for idx in oldPlacements.indices {
      let prevOldEnd = idx == 0 ? 0 : oldPlacements[idx - 1].activeEnd
      let prevNewEnd = idx == 0 ? 0 : newPlacements[idx - 1].activeEnd
      let oldGap = max(0, oldPlacements[idx].activeStart - prevOldEnd)
      let newGap = max(0, newPlacements[idx].activeStart - prevNewEnd)
      let delta = oldGap - newGap
      if delta > 0.0001 {
        let spanEnd = oldPlacements[idx].activeStart
        let spanStart = max(prevOldEnd, spanEnd - delta)
        if spanEnd - spanStart > 0.0001 {
          spans.append(spanStart ... spanEnd)
        }
      }
    }
    if let lastOld = oldPlacements.last, let lastNew = newPlacements.last {
      let oldTail = max(0, lastOld.end - lastOld.activeEnd)
      let newTail = max(0, lastNew.end - lastNew.activeEnd)
      let delta = oldTail - newTail
      if delta > 0.0001 {
        let spanEnd = lastOld.end
        let spanStart = max(lastOld.activeEnd, spanEnd - delta)
        if spanEnd - spanStart > 0.0001 {
          spans.append(spanStart ... spanEnd)
        }
      }
    }
    return VideoEditorTimelineCut.merged(spans)
  }
}
