//
//  VideoEditorAudioTimelineTrack.swift
//  Snapzy
//
//  Multi-track Audio timeline lanes with independent draggable (horizontal time +
//  vertical lane switching), trimmable, splittable, and deletable audio clips
//  (primary recording audio, imported music/voiceover, and detached video audio),
//  per-lane mute & "+ Track" badges, visible-range culling, crisp Canvas waveforms,
//  and interactive Fade In / Fade Out Bezier curves directly on each clip.
//

import AppKit
import AVFoundation
import SwiftUI

struct VideoEditorAudioTimelineTrack: View, Equatable {
  static func == (lhs: Self, rhs: Self) -> Bool {
    lhs.state === rhs.state
      && lhs.waveformCache === rhs.waveformCache
      && lhs.timelineWidth == rhs.timelineWidth
      && lhs.visibleRange == rhs.visibleRange
      && abs(lhs.stickyLeadingX - rhs.stickyLeadingX) < 0.5
  }

  let state: VideoEditorState
  @StateObject private var observation: VideoEditorTimelineObservation
  @ObservedObject var waveformCache: VideoEditorAudioWaveformCache
  let timelineWidth: CGFloat
  let visibleRange: ClosedRange<CGFloat>?
  let stickyLeadingX: CGFloat

  static let trackHeight: CGFloat = 44
  static let laneHeight: CGFloat = 40
  static let laneSpacing: CGFloat = 3
  static let maxVisibleLanes: Int = 4
  private static let blockHeight: CGFloat = 34
  private static let clipGap: CGFloat = 2
  private static let barPitch: CGFloat = 3.0
  private static let coordinateSpace = "VideoEditorAudioTrack"
  private static let maxInteractiveFade: TimeInterval = 3.0

  static func totalHeight(forLaneCount count: Int) -> CGFloat {
    let lanes = max(1, count)
    if lanes == 1 {
      return trackHeight
    }
    let visible = min(lanes, maxVisibleLanes)
    return CGFloat(visible) * laneHeight + CGFloat(visible - 1) * laneSpacing
  }

  private static func fullContentHeight(forLaneCount count: Int) -> CGFloat {
    let lanes = max(1, count)
    if lanes == 1 {
      return trackHeight
    }
    return CGFloat(lanes) * laneHeight + CGFloat(lanes - 1) * laneSpacing
  }

  @State private var hoveredClipId: UUID?
  @State private var activeDrag: AudioDragSession?
  @State private var draggedTargetLane: Int?
  @State private var preloadedClipSignature: Int = 0

  private enum DragKind: Equatable {
    case move
    case trimLeading
    case trimTrailing
    case fadeIn
    case fadeOut
  }

  private struct AudioDragSession: Equatable {
    let clipId: UUID
    let kind: DragKind
    let anchorX: CGFloat
    let anchorY: CGFloat
    let anchorTrackIndex: Int
    let anchorTimelineStart: TimeInterval
    let anchorSourceStart: TimeInterval
    let anchorSourceEnd: TimeInterval
    let anchorFade: TimeInterval
    let anchorClips: [AudioTimelineClip]
    var anchorExportSettings: ExportSettings?
  }

  init(
    state: VideoEditorState,
    waveformCache: VideoEditorAudioWaveformCache,
    timelineWidth: CGFloat,
    visibleRange: ClosedRange<CGFloat>? = nil,
    stickyLeadingX: CGFloat = 0
  ) {
    self.state = state
    _observation = StateObject(wrappedValue: VideoEditorTimelineObservation(state: state, surface: .audio))
    _waveformCache = ObservedObject(wrappedValue: waveformCache)
    self.timelineWidth = timelineWidth
    self.visibleRange = visibleRange
    self.stickyLeadingX = stickyLeadingX
  }

  private var axisDuration: TimeInterval {
    max(0.0001, CMTimeGetSeconds(state.timelineDuration))
  }

  private var pixelsPerSecond: CGFloat {
    timelineWidth / CGFloat(axisDuration)
  }

  private func x(for time: TimeInterval) -> CGFloat {
    CGFloat(time / axisDuration) * timelineWidth
  }

  private var isMasterMuted: Bool {
    state.isMuted || state.exportSettings.audioMode == .mute
  }

  private var laneCount: Int {
    state.audioLaneCount
  }

  private var singleLaneHeight: CGFloat {
    laneCount == 1 ? Self.trackHeight : Self.laneHeight
  }

  private func laneTopY(for lane: Int) -> CGFloat {
    CGFloat(max(0, lane)) * (singleLaneHeight + Self.laneSpacing)
  }

  private var renderedAudioClips: [AudioTimelineClip] {
    guard let visibleRange else { return state.audioClips }
    return state.audioClips.filter { clip in
      clip.id == activeDrag?.clipId
        || clip.id == state.selectedAudioClipId
        || state.selectedAudioClipIds.contains(clip.id)
        || (x(for: clip.timelineEnd) >= visibleRange.lowerBound
          && x(for: clip.timelineStart) <= visibleRange.upperBound)
    }
  }

  var body: some View {
    let _ = observation.revision
    let lanes = laneCount
    let containerHeight = Self.totalHeight(forLaneCount: lanes)
    let contentHeight = Self.fullContentHeight(forLaneCount: lanes)
    let currentSignature = waveformClipSignature

    Group {
      if lanes > Self.maxVisibleLanes {
        ScrollView(.vertical, showsIndicators: true) {
          multiLaneCanvas(lanes: lanes, contentHeight: contentHeight)
        }
        .frame(width: timelineWidth, height: containerHeight, alignment: .topLeading)
      } else {
        multiLaneCanvas(lanes: lanes, contentHeight: containerHeight)
      }
    }
    .onAppear {
      preloadedClipSignature = currentSignature
      preloadWaveforms()
    }
    .onChange(of: currentSignature) { nextSignature in
      preloadedClipSignature = nextSignature
      preloadWaveforms()
    }
    .onDisappear {
      if activeDrag != nil {
        activeDrag = nil
        draggedTargetLane = nil
        state.timelineSnapGuide.clear()
      }
    }
  }

  private var waveformClipSignature: Int {
    var hasher = Hasher()
    hasher.combine(state.audioClips.count)
    for clip in state.audioClips {
      hasher.combine(clip.id)
      hasher.combine(state.waveformSourceURL(for: clip))
    }
    hasher.combine(state.clips.count)
    for role in state.audioTrackRoles {
      hasher.combine(role.id)
    }
    return hasher.finalize()
  }

  private func multiLaneCanvas(lanes: Int, contentHeight: CGFloat) -> some View {
    ZStack(alignment: .topLeading) {
      // Background lane wells (A1, A2, ...)
      VStack(spacing: Self.laneSpacing) {
        ForEach(0 ..< lanes, id: \.self) { lane in
          let isDropTarget = draggedTargetLane == lane && activeDrag?.kind == .move
          ZStack(alignment: .leading) {
            TimelineTrackLaneWell()
              .frame(height: singleLaneHeight)
              .overlay(
                Radius.rect(Radius.tile)
                  .strokeBorder(
                    isDropTarget ? Color.cyan.opacity(0.85) : Color.clear,
                    lineWidth: 1.5
                  )
              )
              .contentShape(Rectangle())
              .gesture(emptyLaneScrubGesture)
              .contextMenu { laneContextMenu(lane: lane, totalLanes: lanes) }

            if state.audioClips.isEmpty, lane == 0 {
              HStack(spacing: 6) {
                Image(systemName: "waveform")
                  .font(.system(size: 10))
                  .foregroundColor(.secondary)
                Text(L10n.VideoEditor.audioEmptyHint)
                  .font(.system(size: 10, weight: .medium))
                  .foregroundColor(.secondary)
                Spacer()
              }
              .padding(.leading, 68)
              .allowsHitTesting(false)
            } else if !state.audioClips.contains(where: { $0.trackIndex == lane }) {
              Text(L10n.VideoEditor.audioLaneDropHint(L10n.VideoEditor.additionalAudioTrackShort(lane + 1)))
                .font(.system(size: 9.5, weight: .medium))
                .foregroundColor(.secondary.opacity(0.65))
                .padding(.leading, 68)
                .allowsHitTesting(false)
            }
          }
        }
      }

      // Culled audio clips positioned at their lane's Y + timelineStart X
      ForEach(renderedAudioClips) { clip in
        audioClipBlock(clip)
      }

      // Sticky lane badges (A1 / A2 + per-lane mute + "+ Track" button on trailing lane)
      ForEach(0 ..< lanes, id: \.self) { lane in
        laneBadgeOverlay(lane: lane, totalLanes: lanes)
          .offset(
            x: max(4, min(stickyLeadingX + 4, max(4, timelineWidth - 74))),
            y: laneTopY(for: lane) + (singleLaneHeight - 20) / 2
          )
          .zIndex(10)
      }
    }
    .frame(width: timelineWidth, height: contentHeight, alignment: .topLeading)
    .coordinateSpace(name: Self.coordinateSpace)
  }

  @ViewBuilder
  private func laneBadgeOverlay(lane: Int, totalLanes: Int) -> some View {
    let isLaneMuted = state.mutedAudioLanes.contains(lane)
    let laneLabel = L10n.VideoEditor.additionalAudioTrackShort(lane + 1)
    let nextLaneLabel = L10n.VideoEditor.additionalAudioTrackShort(totalLanes + 1)
    HStack(spacing: 3) {
      Text(laneLabel)
        .font(.system(size: 8.5, weight: .bold, design: .rounded).monospacedDigit())
        .foregroundColor(isLaneMuted ? .secondary : .white.opacity(0.9))

      Button {
        state.toggleAudioLaneMute(lane)
      } label: {
        Image(systemName: isLaneMuted ? "speaker.slash" : "speaker.wave.2")
          .font(.system(size: 8.5, weight: .semibold))
          .foregroundColor(isLaneMuted ? .orange : .white.opacity(0.75))
          .frame(width: 14, height: 14)
          .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .accessibilityLabel(
        isLaneMuted
          ? L10n.VideoEditor.unmuteAudioTrack(laneLabel)
          : L10n.VideoEditor.muteAudioTrack(laneLabel)
      )
      .help(
        isLaneMuted
          ? L10n.VideoEditor.unmuteTrack(laneLabel)
          : L10n.VideoEditor.muteTrack(laneLabel)
      )

      if lane == totalLanes - 1, totalLanes < AudioTimelineClip.maxTrackCount {
        Button {
          state.addEmptyAudioTrack()
        } label: {
          Image(systemName: "plus")
            .font(.system(size: 8.5, weight: .bold))
            .foregroundColor(.white.opacity(0.82))
            .frame(width: 14, height: 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L10n.VideoEditor.addAudioTrack)
        .accessibilityIdentifier("video-editor.add-audio-track-button")
        .help(L10n.VideoEditor.addAudioTrackLaneHint(nextLaneLabel))
      }
    }
    .padding(.horizontal, 5)
    .padding(.vertical, 3)
    .background(Color.black.opacity(0.62), in: Capsule(style: .continuous))
    .overlay(
      Capsule(style: .continuous)
        .strokeBorder(Color.white.opacity(0.16), lineWidth: 0.5)
    )
    .accessibilityIdentifier("video-editor.audio-lane-badge.\(lane)")
  }

  @ViewBuilder
  private func laneContextMenu(lane: Int, totalLanes: Int) -> some View {
    let laneLabel = L10n.VideoEditor.additionalAudioTrackShort(lane + 1)
    let nextLaneLabel = L10n.VideoEditor.additionalAudioTrackShort(totalLanes + 1)
    Button {
      state.promptAddAudioClip(preferredTrack: lane)
    } label: {
      Label(L10n.VideoEditor.importAudioToTrack(laneLabel), systemImage: "waveform")
    }

    if totalLanes < AudioTimelineClip.maxTrackCount {
      Button {
        state.addEmptyAudioTrack()
      } label: {
        Label(L10n.VideoEditor.addAudioTrackNumbered(nextLaneLabel), systemImage: "plus")
      }
    }

    Button {
      state.toggleAudioLaneMute(lane)
    } label: {
      let muted = state.mutedAudioLanes.contains(lane)
      Label(
        muted ? L10n.VideoEditor.unmuteTrack(laneLabel) : L10n.VideoEditor.muteTrack(laneLabel),
        systemImage: muted ? "speaker.wave.2" : "speaker.slash"
      )
    }

    if lane == totalLanes - 1,
       totalLanes > 1,
       !state.audioClips.contains(where: { $0.trackIndex == lane }) {
      Divider()
      Button(role: .destructive) {
        state.removeEmptyTrailingAudioTrack()
      } label: {
        Label(L10n.VideoEditor.removeEmptyTrack(laneLabel), systemImage: "trash")
      }
    }
  }

  // MARK: - Audio Clip Block

  private func laneAccentColor(for clip: AudioTimelineClip) -> (fill: Color, topWave: Color, bottomWave: Color) {
    if clip.isPrimary {
      return (
        Color(red: 0.16, green: 0.68, blue: 0.88),
        Color(red: 0.52, green: 0.92, blue: 1.0),
        Color(red: 0.22, green: 0.68, blue: 0.96)
      )
    }
    switch clip.trackIndex % 3 {
    case 0:
      return (
        Color(red: 0.34, green: 0.56, blue: 0.96),
        Color(red: 0.66, green: 0.80, blue: 1.0),
        Color(red: 0.36, green: 0.56, blue: 0.98)
      )
    case 1:
      return (
        Color(red: 0.22, green: 0.74, blue: 0.58),
        Color(red: 0.54, green: 0.96, blue: 0.80),
        Color(red: 0.18, green: 0.68, blue: 0.52)
      )
    default:
      return (
        Color(red: 0.62, green: 0.44, blue: 0.94),
        Color(red: 0.82, green: 0.70, blue: 1.0),
        Color(red: 0.56, green: 0.38, blue: 0.92)
      )
    }
  }

  @ViewBuilder
  private func audioClipBlock(_ clip: AudioTimelineClip) -> some View {
    let isSelected = state.selectedAudioClipId == clip.id || state.selectedAudioClipIds.contains(clip.id)
    let isHovered = hoveredClipId == clip.id
    let isMuted = state.isAudioClipEffectivelyMuted(clip)

    let rawWidth = x(for: clip.timelineEnd) - x(for: clip.timelineStart)
    let width = max(14, rawWidth - Self.clipGap)
    let offsetX = x(for: clip.timelineStart) + Self.clipGap / 2
    let offsetY = laneTopY(for: clip.trackIndex) + (singleLaneHeight - Self.blockHeight) / 2

    let usesSinglePrimaryFade = clip.isPrimary && !state.usesIndependentAudioPlayback
    let effectiveFadeIn = usesSinglePrimaryFade ? state.exportSettings.clampedAudioFadeIn : clip.fadeIn
    let effectiveFadeOut = usesSinglePrimaryFade ? state.exportSettings.clampedAudioFadeOut : clip.fadeOut
    let fades = isMuted
      ? (fadeIn: 0.0, fadeOut: 0.0)
      : VideoEditorAudioMixFactory.resolvedFadeDurations(
        fadeIn: effectiveFadeIn,
        fadeOut: effectiveFadeOut,
        totalDuration: clip.duration
      )
    let fadeInWidth = min(width, CGFloat(fades.fadeIn) * pixelsPerSecond)
    let fadeOutWidth = min(width, CGFloat(fades.fadeOut) * pixelsPerSecond)

    let palette = laneAccentColor(for: clip)
    let localVisStart: CGFloat = if let visibleRange {
      max(0, min(width, visibleRange.lowerBound - offsetX - 48))
    } else {
      0
    }
    let localVisEnd: CGFloat = if let visibleRange {
      max(localVisStart, min(width, visibleRange.upperBound - offsetX + 48))
    } else {
      min(width, 4096)
    }

    ZStack(alignment: .leading) {
      Radius.rect(Radius.tile)
        .fill(isMuted ? Color.primary.opacity(0.06) : palette.fill.opacity(0.22))

      if let waveform = waveformCache.waveform(for: state.waveformSourceURL(for: clip)),
         !waveform.isEmpty,
         clip.duration > 0,
         localVisEnd > localVisStart {
        let barCount = VideoEditorAudioWaveform.barCount(forWidth: width, barPitch: Self.barPitch)
        let bars = waveform.slice(from: clip.sourceStart, to: clip.sourceEnd, barCount: barCount)
        waveformCanvas(
          bars: bars,
          totalWidth: width,
          visibleSlice: localVisStart ... localVisEnd,
          clipDuration: clip.duration,
          fades: fades,
          isMuted: isMuted,
          topWave: palette.topWave,
          bottomWave: palette.bottomWave
        )
        .transition(.opacity)
      }

      if !isMuted, fadeInWidth > 1 || fadeOutWidth > 1, localVisEnd > localVisStart {
        fadeCurveOverlay(
          totalWidth: width,
          visibleSlice: localVisStart ... localVisEnd,
          fadeInWidth: fadeInWidth,
          fadeOutWidth: fadeOutWidth
        )
      }

      // Shift title right when the clip starts near the sticky A1/A2 badge so text never collides.
      let showsFadeInDot = !isMuted && width > 32 &&
        (isSelected || isHovered || fades.fadeIn > 0.01 || activeDrag?.clipId == clip.id)
      let collidesWithBadge = offsetX < stickyLeadingX + 72
      let leadingTitleInset: CGFloat = collidesWithBadge ? 70 : (showsFadeInDot ? 18 : 6)
      if width > (collidesWithBadge ? 104 : 56) {
        VStack {
          HStack(spacing: 4) {
            Image(systemName: isMuted ? "speaker.slash" : (clip.isPrimary ? "waveform" : "music.note"))
              .font(.system(size: 8.5, weight: .semibold))
            Text(clip.name)
              .font(.system(size: 9, weight: .semibold))
              .lineLimit(1)
              .truncationMode(.middle)
            Spacer(minLength: 0)
          }
          .foregroundColor(.white.opacity(isMuted ? 0.55 : 0.88))
          .padding(.leading, leadingTitleInset)
          .padding(.trailing, isSelected ? 18 : 6)
          .padding(.top, 3)
          Spacer(minLength: 0)
        }
        .allowsHitTesting(false)
      }

      if width > (isSelected ? 82 : 64) {
        VStack {
          Spacer(minLength: 0)
          HStack {
            Spacer(minLength: 0)
            Text(formatAudioDuration(clip.duration))
              .font(.system(size: 8.5, weight: .semibold).monospacedDigit())
              .foregroundColor(.white.opacity(0.85))
              .padding(.horizontal, 4)
              .padding(.vertical, 1)
              .background(Color.black.opacity(0.45), in: Capsule())
              .padding(.trailing, isSelected ? 14 : 4)
              .padding(.bottom, 2)
          }
        }
        .allowsHitTesting(false)
      }

      Radius.rect(Radius.tile)
        .strokeBorder(
          isSelected
            ? Color.white.opacity(0.95)
            : (isMuted ? Color.primary.opacity(0.14) : palette.fill.opacity(0.48)),
          lineWidth: isSelected ? 1.8 : 1.0
        )
        .allowsHitTesting(false)
    }
    .frame(width: width, height: Self.blockHeight)
    .clipShape(Radius.rect(Radius.tile))
    .contentShape(Rectangle())
    .overlay(alignment: .leading) {
      if isSelected || isHovered {
        audioTrimHandle(clip: clip, isLeading: true)
      }
    }
    .overlay(alignment: .trailing) {
      if isSelected || isHovered {
        audioTrimHandle(clip: clip, isLeading: false)
      }
    }
    .overlay(alignment: .topLeading) {
      if !isMuted, width > 32, isSelected || isHovered || fades.fadeIn > 0.01 || activeDrag?.clipId == clip.id {
        let handleX = max(10, min(width - 14, fadeInWidth + 4))
        audioFadeHandle(
          clip: clip,
          kind: .fadeIn,
          seconds: fades.fadeIn,
          isActive: activeDrag?.clipId == clip.id && activeDrag?.kind == .fadeIn
        )
        .offset(x: handleX - 10, y: -2)
      }
    }
    .overlay(alignment: .topTrailing) {
      if !isMuted, width > 32, isSelected || isHovered || fades.fadeOut > 0.01 || activeDrag?.clipId == clip.id {
        let handleOffsetFromRight = max(10, min(width - 14, fadeOutWidth + 4))
        audioFadeHandle(
          clip: clip,
          kind: .fadeOut,
          seconds: fades.fadeOut,
          isActive: activeDrag?.clipId == clip.id && activeDrag?.kind == .fadeOut
        )
        .offset(x: -(handleOffsetFromRight - 10), y: -2)
      }
    }
    .opacity(isMuted ? 0.55 : 1.0)
    .animation(.easeOut(duration: 0.16), value: isMuted)
    .offset(x: offsetX, y: offsetY)
    .zIndex(isSelected ? 4 : (isHovered ? 2 : 1))
    .onHover { hovering in
      if hovering {
        hoveredClipId = clip.id
      } else if hoveredClipId == clip.id {
        hoveredClipId = nil
      }
    }
    .gesture(moveClipGesture(clip: clip))
    .contextMenu {
      Button {
        state.selectAudioClip(id: clip.id)
        _ = state.splitAudioClip(id: clip.id, at: CMTimeGetSeconds(state.currentTime))
      } label: {
        Label(L10n.VideoEditor.splitAudioAtPlayhead, systemImage: "scissors")
      }
      .disabled(clip.split(at: CMTimeGetSeconds(state.currentTime)) == nil)

      Divider()

      Button {
        state.moveAudioClipToAdjacentTrack(id: clip.id, delta: -1)
      } label: {
        Label(
          L10n.VideoEditor.moveAudioTrackAbove(
            L10n.VideoEditor.additionalAudioTrackShort(max(1, clip.trackIndex))
          ),
          systemImage: "arrow.up"
        )
      }
      .disabled(clip.trackIndex == 0)

      Button {
        state.moveAudioClipToAdjacentTrack(id: clip.id, delta: 1)
      } label: {
        Label(
          L10n.VideoEditor.moveAudioTrackBelow(
            L10n.VideoEditor.additionalAudioTrackShort(min(AudioTimelineClip.maxTrackCount, clip.trackIndex + 2))
          ),
          systemImage: "arrow.down"
        )
      }
      .disabled(clip.trackIndex >= AudioTimelineClip.maxTrackCount - 1)

      Divider()

      Button {
        state.toggleAudioClipMute(id: clip.id)
      } label: {
        Label(
          clip.isMuted ? L10n.VideoEditor.unmuteAudioClip : L10n.VideoEditor.muteAudioClip,
          systemImage: clip.isMuted ? "speaker.wave.2" : "speaker.slash"
        )
      }

      if fades.fadeIn > 0 || fades.fadeOut > 0 {
        Button {
          let beforeClips = state.audioClips
          let beforeSettings = state.exportSettings
          state.setAudioClipFade(id: clip.id, fadeIn: 0, fadeOut: 0)
          state.commitAudioFadeEdit(previousClips: beforeClips, previousExportSettings: beforeSettings)
        } label: {
          Label(L10n.VideoEditor.resetFades, systemImage: "arrow.counterclockwise")
        }
      }

      Divider()

      Button(role: .destructive) {
        state.deleteAudioClip(id: clip.id)
      } label: {
        Label(L10n.VideoEditor.deleteAudioClip, systemImage: "trash")
      }
    }
    .accessibilityLabel(clip.name)
    .accessibilityIdentifier("video-editor.audio-clip-item.\(clip.id.uuidString)")
  }

  // MARK: - Waveform & Fade Curve Drawing

  private func waveformCanvas(
    bars: [Float],
    totalWidth: CGFloat,
    visibleSlice: ClosedRange<CGFloat>,
    clipDuration: TimeInterval,
    fades: (fadeIn: TimeInterval, fadeOut: TimeInterval),
    isMuted: Bool,
    topWave: Color,
    bottomWave: Color
  ) -> some View {
    let sliceWidth = min(max(1, visibleSlice.upperBound - visibleSlice.lowerBound), 4096)
    let sliceOriginX = visibleSlice.lowerBound
    return Canvas { context, size in
      guard !bars.isEmpty, totalWidth > 0, size.width > 0, size.height > 0 else { return }
      let count = bars.count
      let step = totalWidth / CGFloat(count)
      guard step > 0 else { return }
      let barWidth = max(1.3, min(2.2, step * 0.62))
      let maxBarHeight = max(3, size.height - 10)
      let centerY = size.height / 2 + 2

      let topColor = isMuted ? Color.secondary.opacity(0.42) : topWave.opacity(0.92)
      let bottomColor = isMuted ? Color.secondary.opacity(0.22) : bottomWave.opacity(0.76)
      let shading = GraphicsContext.Shading.linearGradient(
        Gradient(colors: [topColor, bottomColor]),
        startPoint: CGPoint(x: 0, y: 4),
        endPoint: CGPoint(x: 0, y: size.height - 2)
      )

      let startIdx = max(0, Int(floor((sliceOriginX - barWidth) / step)))
      let endIdx = min(count - 1, Int(ceil((sliceOriginX + size.width + barWidth) / step)))
      guard startIdx <= endIdx else { return }

      for idx in startIdx ... endIdx {
        let barX = (CGFloat(idx) + 0.5) * step - barWidth / 2 - sliceOriginX
        let localTime = ((Double(idx) + 0.5) / Double(count)) * clipDuration

        var envelope: CGFloat = 1.0
        if fades.fadeIn > 0.001, localTime < fades.fadeIn {
          envelope *= max(0.08, CGFloat(localTime / fades.fadeIn))
        }
        if fades.fadeOut > 0.001, localTime > clipDuration - fades.fadeOut {
          envelope *= max(0.08, CGFloat((clipDuration - localTime) / fades.fadeOut))
        }

        let height = max(2.0, CGFloat(bars[idx]) * envelope * maxBarHeight)
        let rect = CGRect(x: barX, y: centerY - height / 2, width: barWidth, height: height)
        context.fill(Path(roundedRect: rect, cornerRadius: barWidth / 2), with: shading)
      }
    }
    .frame(width: sliceWidth, height: Self.blockHeight)
    .offset(x: sliceOriginX)
    .allowsHitTesting(false)
  }

  private func fadeCurveOverlay(
    totalWidth: CGFloat,
    visibleSlice: ClosedRange<CGFloat>,
    fadeInWidth: CGFloat,
    fadeOutWidth: CGFloat
  ) -> some View {
    let sliceWidth = min(max(1, visibleSlice.upperBound - visibleSlice.lowerBound), 4096)
    let sliceOriginX = visibleSlice.lowerBound
    return Canvas { context, size in
      context.translateBy(x: -sliceOriginX, y: 0)
      if fadeInWidth > 1, sliceOriginX < fadeInWidth {
        let w = min(fadeInWidth, totalWidth)
        var wedge = Path()
        wedge.move(to: CGPoint(x: 0, y: 0))
        wedge.addLine(to: CGPoint(x: w, y: 0))
        wedge.addQuadCurve(to: CGPoint(x: 0, y: size.height), control: CGPoint(x: w * 0.35, y: size.height * 0.16))
        wedge.closeSubpath()
        context.fill(wedge, with: .color(Color.black.opacity(0.32)))

        var curve = Path()
        curve.move(to: CGPoint(x: 0, y: size.height))
        curve.addQuadCurve(to: CGPoint(x: w, y: 0), control: CGPoint(x: w * 0.35, y: size.height * 0.16))
        context.stroke(
          curve,
          with: .color(Color(red: 0.65, green: 0.96, blue: 1.0).opacity(0.95)),
          style: StrokeStyle(lineWidth: 1.6, lineCap: .round)
        )
      }

      let fadeOutStart = totalWidth - min(fadeOutWidth, totalWidth)
      if fadeOutWidth > 1, sliceOriginX + size.width > fadeOutStart {
        let w = min(fadeOutWidth, totalWidth)
        let startX = totalWidth - w
        var wedge = Path()
        wedge.move(to: CGPoint(x: totalWidth, y: 0))
        wedge.addLine(to: CGPoint(x: startX, y: 0))
        wedge.addQuadCurve(
          to: CGPoint(x: totalWidth, y: size.height),
          control: CGPoint(x: totalWidth - w * 0.35, y: size.height * 0.16)
        )
        wedge.closeSubpath()
        context.fill(wedge, with: .color(Color.black.opacity(0.32)))

        var curve = Path()
        curve.move(to: CGPoint(x: startX, y: 0))
        curve.addQuadCurve(
          to: CGPoint(x: totalWidth, y: size.height),
          control: CGPoint(x: totalWidth - w * 0.35, y: size.height * 0.16)
        )
        context.stroke(
          curve,
          with: .color(Color(red: 0.65, green: 0.96, blue: 1.0).opacity(0.95)),
          style: StrokeStyle(lineWidth: 1.6, lineCap: .round)
        )
      }
    }
    .frame(width: sliceWidth, height: Self.blockHeight)
    .offset(x: sliceOriginX)
    .allowsHitTesting(false)
  }

  // MARK: - Handles & Gestures

  private func audioTrimHandle(clip: AudioTimelineClip, isLeading: Bool) -> some View {
    Rectangle()
      .fill(Color.white.opacity(0.9))
      .frame(width: 5, height: Self.blockHeight)
      .clipShape(Radius.rect(Radius.ornament))
      .frame(width: 12, height: Self.blockHeight, alignment: isLeading ? .leading : .trailing)
      .contentShape(Rectangle())
      .onHover { hovering in
        if hovering {
          NSCursor.resizeLeftRight.set()
        } else if activeDrag == nil {
          NSCursor.arrow.set()
        }
      }
      .highPriorityGesture(
        DragGesture(minimumDistance: 2, coordinateSpace: .named(Self.coordinateSpace))
          .onChanged { value in
            if activeDrag == nil {
              state.selectAudioClip(id: clip.id)
              activeDrag = AudioDragSession(
                clipId: clip.id,
                kind: isLeading ? .trimLeading : .trimTrailing,
                anchorX: value.location.x,
                anchorY: value.location.y,
                anchorTrackIndex: clip.trackIndex,
                anchorTimelineStart: clip.timelineStart,
                anchorSourceStart: clip.sourceStart,
                anchorSourceEnd: clip.sourceEnd,
                anchorFade: 0,
                anchorClips: state.audioClips
              )
            }
            guard let session = activeDrag, session.clipId == clip.id, pixelsPerSecond > 0 else { return }
            let delta = TimeInterval((value.location.x - session.anchorX) / pixelsPerSecond)
            let bypassSnap = !state.isSnappingEnabled || VideoEditorTimelineSnapGuideState.isBypassKeyPressed
            let candidates = state.timelineSnapCandidates(excludingClipId: clip.id)

            if isLeading {
              let rawTimelineStart = max(0, session.anchorTimelineStart + delta)
              let snapped = VideoEditorTimelineSnapper.snap(
                time: rawTimelineStart,
                candidates: candidates,
                pixelsPerSecond: pixelsPerSecond,
                isDisabled: bypassSnap
              )
              state.timelineSnapGuide.update(snapped.target)
              let effectiveDelta = snapped.time - session.anchorTimelineStart
              let base = AudioTimelineClip(
                id: clip.id,
                source: clip.source,
                name: clip.name,
                timelineStart: session.anchorTimelineStart,
                sourceDuration: clip.sourceDuration,
                sourceStart: session.anchorSourceStart,
                sourceEnd: session.anchorSourceEnd,
                volume: clip.volume,
                isMuted: clip.isMuted,
                fadeIn: clip.fadeIn,
                fadeOut: clip.fadeOut,
                trackIndex: clip.trackIndex
              )
              if let idx = state.audioClips.firstIndex(where: { $0.id == clip.id }) {
                state.audioClips[idx] = base.trimmedLeading(by: effectiveDelta)
              }
            } else {
              let anchorEnd = session.anchorTimelineStart + (session.anchorSourceEnd - session.anchorSourceStart)
              let rawTimelineEnd = anchorEnd + delta
              let snapped = VideoEditorTimelineSnapper.snap(
                time: rawTimelineEnd,
                candidates: candidates,
                pixelsPerSecond: pixelsPerSecond,
                isDisabled: bypassSnap
              )
              state.timelineSnapGuide.update(snapped.target)
              let effectiveDelta = snapped.time - anchorEnd
              let base = AudioTimelineClip(
                id: clip.id,
                source: clip.source,
                name: clip.name,
                timelineStart: session.anchorTimelineStart,
                sourceDuration: clip.sourceDuration,
                sourceStart: session.anchorSourceStart,
                sourceEnd: session.anchorSourceEnd,
                volume: clip.volume,
                isMuted: clip.isMuted,
                fadeIn: clip.fadeIn,
                fadeOut: clip.fadeOut,
                trackIndex: clip.trackIndex
              )
              if let idx = state.audioClips.firstIndex(where: { $0.id == clip.id }) {
                state.audioClips[idx] = base.trimmedTrailing(by: effectiveDelta)
              }
            }
          }
          .onEnded { _ in
            if let prior = activeDrag?.anchorClips {
              state.commitAudioClipEdit(previousClips: prior)
            }
            activeDrag = nil
            state.timelineSnapGuide.clear()
            NSCursor.arrow.set()
          }
      )
      .accessibilityLabel(isLeading ? L10n.VideoEditor.clipTrimStartHint : L10n.VideoEditor.clipTrimEndHint)
  }

  private func audioFadeHandle(
    clip: AudioTimelineClip,
    kind: DragKind,
    seconds: TimeInterval,
    isActive: Bool
  ) -> some View {
    ZStack(alignment: kind == .fadeIn ? .leading : .trailing) {
      Circle()
        .fill(isActive ? Color(red: 0.52, green: 0.92, blue: 1.0) : Color.white)
        .frame(width: isActive ? 10 : 8, height: isActive ? 10 : 8)
        .overlay(Circle().strokeBorder(Color.black.opacity(0.45), lineWidth: 1))
        .shadow(color: Color.black.opacity(0.35), radius: 2, y: 1)

      if isActive {
        Text(seconds <= 0.05 ? L10n.Common.off : String(format: "%.1fs", seconds))
          .font(.system(size: 9, weight: .semibold).monospacedDigit())
          .foregroundColor(.white)
          .padding(.horizontal, 5)
          .padding(.vertical, 2)
          .background(Color.black.opacity(0.78), in: Capsule())
          .offset(x: kind == .fadeIn ? 14 : -14)
          .fixedSize()
      }
    }
    .frame(width: 20, height: 18)
    .contentShape(Rectangle())
    .onHover { hovering in
      if hovering {
        NSCursor.resizeLeftRight.set()
      } else if activeDrag == nil {
        NSCursor.arrow.set()
      }
    }
    .highPriorityGesture(
      DragGesture(minimumDistance: 1, coordinateSpace: .named(Self.coordinateSpace))
        .onChanged { value in
          if activeDrag == nil {
            state.selectAudioClip(id: clip.id)
            let initialFade: TimeInterval = if clip.isPrimary, !state.usesIndependentAudioPlayback {
              kind == .fadeIn ? state.exportSettings.clampedAudioFadeIn : state.exportSettings.clampedAudioFadeOut
            } else {
              kind == .fadeIn ? clip.fadeIn : clip.fadeOut
            }
            activeDrag = AudioDragSession(
              clipId: clip.id,
              kind: kind,
              anchorX: value.location.x,
              anchorY: value.location.y,
              anchorTrackIndex: clip.trackIndex,
              anchorTimelineStart: clip.timelineStart,
              anchorSourceStart: clip.sourceStart,
              anchorSourceEnd: clip.sourceEnd,
              anchorFade: initialFade,
              anchorClips: state.audioClips,
              anchorExportSettings: state.exportSettings
            )
          }
          guard let session = activeDrag, session.clipId == clip.id, pixelsPerSecond > 0 else { return }
          let deltaSeconds = TimeInterval((value.location.x - session.anchorX) / pixelsPerSecond)
          let rawDuration = kind == .fadeIn
            ? session.anchorFade + deltaSeconds
            : session.anchorFade - deltaSeconds
          let stepped = (rawDuration * 10).rounded() / 10
          let clamped = min(max(stepped, 0), min(Self.maxInteractiveFade, clip.duration))
          if kind == .fadeIn {
            state.setAudioClipFade(id: clip.id, fadeIn: clamped)
          } else {
            state.setAudioClipFade(id: clip.id, fadeOut: clamped)
          }
        }
        .onEnded { _ in
          if let session = activeDrag {
            if let priorSettings = session.anchorExportSettings {
              state.commitAudioFadeEdit(
                previousClips: session.anchorClips,
                previousExportSettings: priorSettings
              )
            } else {
              state.commitAudioClipEdit(previousClips: session.anchorClips)
            }
          }
          activeDrag = nil
          NSCursor.arrow.set()
        }
    )
    .accessibilityLabel(kind == .fadeIn ? L10n.VideoEditor.fadeIn : L10n.VideoEditor.fadeOut)
    .help(kind == .fadeIn ? L10n.VideoEditor.dragAudioFadeInHint : L10n.VideoEditor.dragAudioFadeOutHint)
  }

  private func moveClipGesture(clip: AudioTimelineClip) -> some Gesture {
    DragGesture(minimumDistance: 0, coordinateSpace: .named(Self.coordinateSpace))
      .onChanged { value in
        if activeDrag == nil {
          state.selectAudioClip(id: clip.id)
          activeDrag = AudioDragSession(
            clipId: clip.id,
            kind: .move,
            anchorX: value.location.x,
            anchorY: value.location.y,
            anchorTrackIndex: clip.trackIndex,
            anchorTimelineStart: clip.timelineStart,
            anchorSourceStart: clip.sourceStart,
            anchorSourceEnd: clip.sourceEnd,
            anchorFade: 0,
            anchorClips: state.audioClips
          )
        }
        guard let session = activeDrag,
              session.clipId == clip.id,
              session.kind == .move,
              pixelsPerSecond > 0,
              abs(value.location.x - session.anchorX) > 3 || abs(value.location.y - session.anchorY) > 6
        else { return }

        let deltaX = TimeInterval((value.location.x - session.anchorX) / pixelsPerSecond)
        let rawStart = max(0, session.anchorTimelineStart + deltaX)
        let bypassSnap = !state.isSnappingEnabled || VideoEditorTimelineSnapGuideState.isBypassKeyPressed
        let snapped = VideoEditorTimelineSnapper.snapRange(
          start: rawStart,
          duration: clip.duration,
          candidates: state.timelineSnapCandidates(excludingClipId: clip.id),
          pixelsPerSecond: pixelsPerSecond,
          isDisabled: bypassSnap
        )
        state.timelineSnapGuide.update(snapped.target)

        let lanePitch = max(1, singleLaneHeight + Self.laneSpacing)
        let laneDelta = Int(round((value.location.y - session.anchorY) / lanePitch))
        let maxDropLane = min(
          max(state.audioLaneCount, session.anchorTrackIndex + 1),
          AudioTimelineClip.maxTrackCount - 1
        )
        let targetLane = max(0, min(session.anchorTrackIndex + laneDelta, maxDropLane))
        draggedTargetLane = targetLane

        state.moveAudioClip(id: clip.id, to: max(0, snapped.start), trackIndex: targetLane)
      }
      .onEnded { value in
        let prior = activeDrag?.anchorClips
        let wasTap = activeDrag.map {
          abs(value.location.x - $0.anchorX) <= 3 && abs(value.location.y - $0.anchorY) <= 6
        } ?? true
        activeDrag = nil
        draggedTargetLane = nil
        state.timelineSnapGuide.clear()
        if wasTap, pixelsPerSecond > 0 {
          let seconds = max(0, TimeInterval(value.location.x / pixelsPerSecond))
          state.seek(to: CMTime(seconds: seconds, preferredTimescale: 600))
        } else if let prior {
          state.commitAudioClipEdit(previousClips: prior)
        }
      }
  }

  private func formatAudioDuration(_ seconds: TimeInterval) -> String {
    let clamped = max(0, seconds)
    let mins = Int(clamped) / 60
    let secs = clamped - Double(mins * 60)
    return String(format: "%d:%04.1f", mins, secs)
  }

  private var emptyLaneScrubGesture: some Gesture {
    DragGesture(minimumDistance: 0, coordinateSpace: .named(Self.coordinateSpace))
      .onChanged { value in
        guard pixelsPerSecond > 0 else { return }
        if !state.playbackState.isScrubbing {
          state.selectAudioClip(id: nil)
          state.startScrubbing()
        }
        let seconds = max(0, TimeInterval(value.location.x / pixelsPerSecond))
        state.scrub(to: CMTime(seconds: seconds, preferredTimescale: 600))
      }
      .onEnded { value in
        guard pixelsPerSecond > 0 else { return }
        let seconds = max(0, TimeInterval(value.location.x / pixelsPerSecond))
        state.scrub(to: CMTime(seconds: seconds, preferredTimescale: 600))
        state.endScrubbing()
      }
  }

  private func preloadWaveforms() {
    for clip in state.audioClips {
      waveformCache.ensureLoaded(for: state.waveformSourceURL(for: clip))
    }
    for clip in state.clips {
      waveformCache.ensureLoaded(for: state.waveformSourceURL(for: clip))
    }
  }
}
