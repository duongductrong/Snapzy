//
//  VideoEditorClipStripView.swift
//  Snapzy
//
//  The timeline's content lane: one rounded block per clip in the sequence.
//  Clips can be selected, dragged freely along the timeline (creating or closing
//  black-screen gaps), dragged past neighbours to reorder, trimmed non-destructively
//  from either yellow edge handle, and deleted.
//

import AppKit
import AVFoundation
import SwiftUI

struct VideoEditorClipStripView: View, Equatable {
  static func == (lhs: Self, rhs: Self) -> Bool {
    lhs.state === rhs.state && lhs.thumbnailCache === rhs.thumbnailCache
      && lhs.timelineWidth == rhs.timelineWidth && lhs.trackHeight == rhs.trackHeight
      && lhs.visibleRange == rhs.visibleRange
      && abs(lhs.stickyLeadingX - rhs.stickyLeadingX) < 0.5
  }

  let state: VideoEditorState
  @StateObject private var observation: VideoEditorTimelineObservation
  @ObservedObject var thumbnailCache: VideoEditorClipThumbnailCache

  let timelineWidth: CGFloat
  let trackHeight: CGFloat
  let visibleRange: ClosedRange<CGFloat>?
  let stickyLeadingX: CGFloat

  private static let selectionGold = Color(red: 1.0, green: 0.78, blue: 0.16)

  init(
    state: VideoEditorState,
    thumbnailCache: VideoEditorClipThumbnailCache,
    timelineWidth: CGFloat,
    trackHeight: CGFloat,
    visibleRange: ClosedRange<CGFloat>? = nil,
    stickyLeadingX: CGFloat = 0
  ) {
    self.state = state
    _observation = StateObject(wrappedValue: VideoEditorTimelineObservation(state: state, surface: .clips))
    _thumbnailCache = ObservedObject(wrappedValue: thumbnailCache)
    self.timelineWidth = timelineWidth
    self.trackHeight = trackHeight
    self.visibleRange = visibleRange
    self.stickyLeadingX = stickyLeadingX
  }

  /// Visual separation between neighbouring clips. Purely cosmetic — the blocks still
  /// occupy their exact time spans, the gap is taken out of each block's width.
  private static let clipGap: CGFloat = 3
  private static let handleWidth: CGFloat = 12
  /// Small extra trim-handle reach extending inward into the clip. Never extends
  /// outward past the edge, and stays narrow enough not to steal clip-body drags.
  private static let handleReach: CGFloat = 4
  /// Pointer travel before a press turns from "select & seek" into "move / reorder".
  private static let dragThreshold: CGFloat = 5
  private static let coordinateSpace = "VideoEditorClipStrip"

  @State private var drag: DragSession?
  @State private var isHoveringHandle = false
  @State private var hoveredBodyClipId: UUID?
  @State private var hoveredGapClipIndex: Int?
  @State private var transitionPopoverClipId: UUID?

  /// One in-flight pointer gesture on a clip body or trim handle.
  private struct DragSession: Equatable {
    let clipId: UUID
    let fromIndex: Int
    var visualOffsetX: CGFloat = 0
    /// Stays false until the pointer passes `dragThreshold`, keeping a plain click
    /// behaving as select-and-seek rather than a zero-distance move.
    var isMoving = false
    /// True when the clip has been dragged past a neighbour's midpoint to swap order.
    var isReordering = false
    /// Set by an edge-handle trim drag so body gestures leave the session alone.
    var isTrimming = false
    var didBeginTrimMutation = false
    var targetIndex: Int
    /// Anchored active start / duration / scale when the drag began (keeps math jitter-free).
    var anchorActiveStart: TimeInterval = 0
    var anchorActiveEnd: TimeInterval = 0
    var anchorDuration: TimeInterval = 0
    var anchorPixelsPerSecond: CGFloat = 1
    var anchorPlacements: [TimelineSequence.Placement] = []
    /// Target timeline start where the clip will land on drop when not reordering.
    var resolvedStart: TimeInterval = 0
    /// In/out points as they stood when a trim drag began.
    var anchorStart: TimeInterval = 0
    var anchorEnd: TimeInterval = 0
    /// Allowed non-destructive source bounds for the active trim gesture.
    var minAllowedSourceStart: TimeInterval = 0
    var maxAllowedSourceEnd: TimeInterval = 0
    /// Pointer x in the strip's stable coordinate space when the gesture began.
    var anchorX: CGFloat = 0
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

  // MARK: - Body

  var body: some View {
    let _ = observation.revision
    return ZStack(alignment: .leading) {
      TimelineTrackLaneWell()
        .contentShape(Rectangle())
        .gesture(emptyLaneScrubGesture)
        .contextMenu {
          if state.hasRemovableVideoGaps {
            Button {
              state.closeAllGaps()
            } label: {
              Label(L10n.VideoEditor.closeAllGaps, systemImage: "arrow.left.and.right")
            }
          }
        }

      if state.isExtractingFrames, state.frameThumbnails.isEmpty {
        loadingRow
      } else {
        ForEach(state.removableVideoGaps) { gap in
          videoGapOverlay(gap)
        }

        ForEach(renderedPlacements) { placement in
          clipBlock(placement)
        }

        ForEach(state.abuttingClipSeams) { seam in
          transitionSeamButton(seam)
        }

        if let session = drag, session.isReordering, session.targetIndex != session.fromIndex {
          reorderDropIndicator(for: session)
        }
      }

      // Sticky V1 NLE track badge
      videoTrackBadge
        .offset(x: max(4, min(stickyLeadingX + 4, max(4, timelineWidth - 40))), y: -trackHeight / 2 + 14)
        .zIndex(6)
        .allowsHitTesting(false)
    }
    .frame(width: timelineWidth, height: trackHeight, alignment: .leading)
    .coordinateSpace(name: Self.coordinateSpace)
    .onAppear { preloadInsertedThumbnails() }
    .onChange(of: state.clips) { _ in preloadInsertedThumbnails() }
    // A trim holds speed-preview rebuilds until it ends; if the strip goes away
    // mid-gesture, `onEnded` never fires, so clean up here.
    .onDisappear {
      if drag?.didBeginTrimMutation == true {
        state.endClipTrim()
      }
      if drag != nil {
        state.timelineSnapGuide.clear()
        drag = nil
      }
      isHoveringHandle = false
      hoveredBodyClipId = nil
      NSCursor.arrow.set()
    }
  }

  private var renderedPlacements: [TimelineSequence.Placement] {
    guard let visibleRange else { return state.placements }
    return state.placements.filter { placement in
      placement.clip.id == drag?.clipId || placement.clip.id == state.selectedClipId
        || (x(for: placement.activeEnd) >= visibleRange.lowerBound
          && x(for: placement.activeStart) <= visibleRange.upperBound)
    }
  }

  private var loadingRow: some View {
    HStack {
      Spacer()
      ProgressView().scaleEffect(0.8)
      Text(L10n.VideoEditorTimeline.extractingFrames)
        .font(.caption)
        .foregroundColor(.secondary)
      Spacer()
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  private var videoTrackBadge: some View {
    HStack(spacing: 3) {
      Image(systemName: "film")
        .font(.system(size: 8, weight: .bold))
        .foregroundColor(.white.opacity(0.82))
      Text("V1")
        .font(.system(size: 8.5, weight: .bold, design: .rounded).monospacedDigit())
        .lineLimit(1)
        .foregroundColor(.white.opacity(0.92))
    }
    .padding(.horizontal, 6)
    .padding(.vertical, 3)
    .background(Color.black.opacity(0.62), in: Capsule(style: .continuous))
    .overlay(
      Capsule(style: .continuous)
        .strokeBorder(Color.white.opacity(0.18), lineWidth: 0.5)
    )
  }

  /// Bright insertion bar shown only when dragging past another clip's midpoint to reorder.
  private func reorderDropIndicator(for session: DragSession) -> some View {
    let indicatorTime: TimeInterval = {
      let placements = session.anchorPlacements
      guard !placements.isEmpty else { return 0 }
      let clampedTarget = min(max(0, session.targetIndex), placements.count - 1)
      if clampedTarget == 0, session.targetIndex <= session.fromIndex {
        return placements[0].activeStart
      }
      if session.targetIndex > session.fromIndex {
        return placements[clampedTarget].activeEnd
      }
      return placements[clampedTarget].activeStart
    }()
    let indicatorX = max(1.5, min(timelineWidth - 1.5, x(for: indicatorTime)))
    return Capsule(style: .continuous)
      .fill(Self.selectionGold)
      .frame(width: 3, height: trackHeight)
      .shadow(color: Self.selectionGold.opacity(0.65), radius: 4)
      .offset(x: indicatorX - 1.5)
      .zIndex(5)
      .allowsHitTesting(false)
  }

  // MARK: - Clip Block

  @ViewBuilder
  private func clipBlock(_ placement: TimelineSequence.Placement) -> some View {
    let clip = placement.clip
    let isSelected = state.selectedClipId == clip.id
    let isMoving = drag?.clipId == clip.id && drag?.isMoving == true

    // Render only the active trimmed span so trimming removes frames cleanly
    // without leaving a dimmed ghost tail behind.
    let rawWidth = x(for: placement.activeEnd) - x(for: placement.activeStart)
    let width = max(12, rawWidth - Self.clipGap)
    let offsetX = x(for: placement.activeStart) + Self.clipGap / 2

    ZStack(alignment: .leading) {
      thumbnails(for: clip, blockWidth: width)
        .accessibilityHidden(true)

      if !clip.isPrimary {
        insertedClipChrome(clip, width: width)
      }

      if clip.isAudioDetached, width > 44 {
        VStack {
          HStack {
            Spacer(minLength: 0)
            Image(systemName: "speaker.slash")
              .font(.system(size: 8.5, weight: .bold))
              .foregroundColor(.white.opacity(0.92))
              .padding(.horizontal, 4)
              .padding(.vertical, 2)
              .background(Color.black.opacity(0.62), in: Capsule())
              .padding(.trailing, isSelected ? Self.handleWidth + 4 : 6)
              .padding(.top, 4)
          }
          Spacer(minLength: 0)
        }
        .allowsHitTesting(false)
      }

      if width > (isSelected ? 82 : 60) {
        let isTrimmingThis = drag?.clipId == clip.id && drag?.isTrimming == true
        VStack {
          Spacer(minLength: 0)
          HStack {
            Spacer(minLength: 0)
            Text(formatClipDuration(clip.duration))
              .font(.system(size: 9, weight: .semibold).monospacedDigit())
              .lineLimit(1)
              .foregroundColor(isTrimmingThis ? .black : .white.opacity(0.92))
              .padding(.horizontal, 6)
              .padding(.vertical, 2)
              .background(
                isTrimmingThis ? Self.selectionGold : Color.black.opacity(0.58),
                in: Capsule()
              )
              .padding(.trailing, isSelected ? Self.handleWidth + 4 : 6)
              .padding(.bottom, 4)
          }
        }
        .allowsHitTesting(false)
      }

      Radius.rect(Radius.tile)
        .strokeBorder(
          isSelected ? Self.selectionGold : Color.white.opacity(0.20),
          lineWidth: isSelected ? 2.5 : 1.0
        )
        .allowsHitTesting(false)
    }
    .frame(width: width, height: trackHeight)
    .clipShape(Radius.rect(Radius.tile))
    .contentShape(Rectangle())
    .onHover { hovering in
      if hovering {
        hoveredBodyClipId = clip.id
        if drag == nil, !isHoveringHandle {
          NSCursor.openHand.set()
        }
      } else {
        if hoveredBodyClipId == clip.id {
          hoveredBodyClipId = nil
        }
        if drag == nil, !isHoveringHandle {
          NSCursor.arrow.set()
        }
      }
    }
    .overlay(alignment: .leading) {
      if isSelected {
        trimHandle(placement: placement, isLeading: true)
      }
    }
    .overlay(alignment: .trailing) {
      if isSelected {
        trimHandle(placement: placement, isLeading: false)
      }
    }
    .shadow(color: .black.opacity(isMoving ? 0.5 : 0), radius: isMoving ? 8 : 0)
    .opacity(isMoving ? 0.88 : 1)
    .offset(x: offsetX + (isMoving ? (drag?.visualOffsetX ?? 0) : 0))
    .zIndex(isMoving ? 3 : (isSelected ? 1 : 0))
    .gesture(bodyGesture(placement))
    .contextMenu { contextMenu(placement) }
    .accessibilityLabel(tooltip(for: clip))
    .accessibilityIdentifier("video-editor.clip-item.\(clip.id.uuidString)")
    .help(tooltip(for: clip))
  }

  private func formatClipDuration(_ seconds: TimeInterval) -> String {
    let clamped = max(0, seconds)
    let mins = Int(clamped) / 60
    let secs = clamped - Double(mins * 60)
    return String(format: "%d:%04.1f", mins, secs)
  }

  /// Tint + filename so an inserted video reads differently from the recording.
  private func insertedClipChrome(_ clip: TimelineClip, width: CGFloat) -> some View {
    ZStack(alignment: .bottomLeading) {
      Color(red: 0.35, green: 0.65, blue: 0.95).opacity(0.18)

      if width > 54 {
        Text(clip.url?.lastPathComponent ?? "")
          .font(.system(size: 9, weight: .medium))
          .foregroundColor(.white.opacity(0.9))
          .lineLimit(1)
          .truncationMode(.middle)
          .padding(.horizontal, 4)
          .padding(.vertical, 2)
          .background(.black.opacity(0.45), in: Radius.rect(Radius.ornament))
          .padding(.leading, 16)
          .padding(.bottom, 4)
      }
    }
    .allowsHitTesting(false)
  }

  // MARK: - Thumbnails

  /// Frames for a clip's active source window.
  ///
  /// Scales using `clip.duration` so trimming crops away individual frames cleanly
  /// instead of squishing the thumbnail strip horizontally.
  @ViewBuilder
  private func thumbnails(for clip: TimelineClip, blockWidth: CGFloat) -> some View {
    let images = images(for: clip)

    if images.isEmpty {
      LinearGradient(
        colors: [Color.white.opacity(0.10), Color.white.opacity(0.04)],
        startPoint: .top,
        endPoint: .bottom
      )
    } else {
      let scale = clip.duration > 0 ? blockWidth / CGFloat(clip.duration) : 0
      let fullWidth = max(blockWidth, scale * CGFloat(clip.sourceDuration))
      let cellWidth = fullWidth / CGFloat(images.count)

      let sourceOffset = scale * CGFloat(clip.sourceStart)
      let placementStart = state.placements.first(where: { $0.clip.id == clip.id })
        .map { x(for: $0.activeStart) + Self.clipGap / 2 } ?? 0
      let localLower = max(0, (visibleRange?.lowerBound ?? placementStart) - placementStart)
      let localUpper = min(blockWidth, (visibleRange?.upperBound ?? (placementStart + blockWidth)) - placementStart)
      let first = max(
        0,
        min(images.count, Int(floor((sourceOffset + localLower) / max(CGFloat.leastNonzeroMagnitude, cellWidth))))
      )
      let last = max(
        first,
        min(
          images.count,
          Int(ceil((sourceOffset + max(localLower, localUpper)) / max(CGFloat.leastNonzeroMagnitude, cellWidth)))
        )
      )
      HStack(spacing: 0) {
        Color.clear.frame(width: CGFloat(first) * cellWidth)
        ForEach(first ..< last, id: \.self) { index in
          Image(nsImage: images[index])
            .resizable()
            .interpolation(.high)
            .antialiased(true)
            .aspectRatio(contentMode: .fill)
            .frame(width: cellWidth, height: trackHeight)
            .clipped()
            .overlay(alignment: .trailing) {
              if index < images.count - 1 {
                Rectangle()
                  .fill(Color.black.opacity(0.26))
                  .frame(width: 0.5, height: trackHeight)
              }
            }
        }
      }
      .frame(width: fullWidth, alignment: .leading)
      .offset(x: -sourceOffset)
      .frame(width: blockWidth, alignment: .leading)
      .clipped()
    }
  }

  private func images(for clip: TimelineClip) -> [NSImage] {
    switch clip.source {
    case .primary:
      state.frameThumbnails
    case .file(let url):
      thumbnailCache.strip(for: url)
    }
  }

  private func preloadInsertedThumbnails() {
    for clip in state.clips {
      if case .file(let url) = clip.source {
        thumbnailCache.ensureLoaded(for: url)
      }
    }
  }

  // MARK: - Trim Handles

  /// Yellow chevron handles matching the editor's trim affordance. Dragging one moves
  /// the clip's in/out point within its backing asset so trimmed frames can be restored
  /// non-destructively into any available gap space.
  private func trimHandle(placement: TimelineSequence.Placement, isLeading: Bool) -> some View {
    let visual = Radius.rect(Radius.ornament)
      .fill(Self.selectionGold)
      .frame(width: Self.handleWidth, height: trackHeight)
      .overlay(
        Image(systemName: isLeading ? "chevron.compact.left" : "chevron.compact.right")
          .font(.system(size: 14, weight: .bold))
          .foregroundColor(.black.opacity(0.65))
      )

    return HStack(spacing: 0) {
      if isLeading {
        visual
        Color.clear.frame(width: Self.handleReach)
      } else {
        Color.clear.frame(width: Self.handleReach)
        visual
      }
    }
    .frame(height: trackHeight)
    .contentShape(Rectangle())
    .highPriorityGesture(trimGesture(placement: placement, isLeading: isLeading))
    .onHover { hovering in
      isHoveringHandle = hovering
      if hovering {
        NSCursor.resizeLeftRight.set()
      } else if drag == nil {
        if hoveredBodyClipId != nil {
          NSCursor.openHand.set()
        } else {
          NSCursor.arrow.set()
        }
      }
    }
    .accessibilityLabel(isLeading ? L10n.VideoEditor.clipTrimStartHint : L10n.VideoEditor.clipTrimEndHint)
    .help(isLeading ? L10n.VideoEditor.clipTrimStartHint : L10n.VideoEditor.clipTrimEndHint)
  }

  private func trimGesture(placement: TimelineSequence.Placement, isLeading: Bool) -> some Gesture {
    // Use minimumDistance: 0 so pressing a trim handle never falls through to the
    // clip body gesture and jumps the playhead; mutation begins once travel >= 2 pt.
    DragGesture(minimumDistance: 0, coordinateSpace: .named(Self.coordinateSpace))
      .onChanged { value in
        let clip = placement.clip
        if drag == nil {
          let extraRightRoom: TimeInterval = (placement.index + 1 < state.clips.count)
            ? max(0, state.clips[placement.index + 1].leadingGap)
            : max(0, clip.sourceDuration - clip.slotEnd)
          drag = DragSession(
            clipId: clip.id,
            fromIndex: placement.index,
            isTrimming: true,
            targetIndex: placement.index,
            anchorActiveStart: placement.activeStart,
            anchorActiveEnd: placement.activeEnd,
            anchorDuration: clip.duration,
            anchorPixelsPerSecond: max(pixelsPerSecond, 0.0001),
            anchorStart: clip.sourceStart,
            anchorEnd: clip.sourceEnd,
            minAllowedSourceStart: max(0, clip.slotStart - clip.leadingGap),
            maxAllowedSourceEnd: min(clip.sourceDuration, clip.slotEnd + extraRightRoom),
            anchorX: value.location.x
          )
          NSCursor.resizeLeftRight.set()
        }
        guard var session = drag,
              session.clipId == clip.id,
              session.isTrimming,
              abs(value.location.x - session.anchorX) >= 2
        else { return }

        if !session.didBeginTrimMutation {
          state.beginClipTrim(id: clip.id)
          session.didBeginTrimMutation = true
          drag = session
        }

        let pps = session.anchorPixelsPerSecond
        let delta = TimeInterval((value.location.x - session.anchorX) / pps)
        let bypassSnap = !state.isSnappingEnabled || VideoEditorTimelineSnapGuideState.isBypassKeyPressed

        if isLeading {
          let maxStart = max(session.minAllowedSourceStart, session.anchorEnd - TimelineClip.minDuration)
          let rawSourceStart = min(max(session.anchorStart + delta, session.minAllowedSourceStart), maxStart)
          let allowedMinTimeline = session.anchorActiveStart - (session.anchorStart - session.minAllowedSourceStart)
          let allowedMaxTimeline = session.anchorActiveEnd - TimelineClip.minDuration
          let candidates = state
            .timelineSnapCandidates(excludingClipId: clip.id)
            .filter { $0.time >= allowedMinTimeline - 0.001 && $0.time <= allowedMaxTimeline + 0.001 }

          let sequenceEdge = session.anchorActiveStart + (rawSourceStart - session.anchorStart)
          let snapped = VideoEditorTimelineSnapper.snap(
            time: sequenceEdge,
            candidates: candidates,
            pixelsPerSecond: pps,
            isDisabled: bypassSnap
          )
          state.timelineSnapGuide.update(snapped.target)
          let snappedSourceStart = min(
            max(session.anchorStart + (snapped.time - session.anchorActiveStart), session.minAllowedSourceStart),
            maxStart
          )
          state.updateClip(id: clip.id, sourceStart: snappedSourceStart)
        } else {
          let minEnd = min(session.maxAllowedSourceEnd, session.anchorStart + TimelineClip.minDuration)
          let rawSourceEnd = min(max(session.anchorEnd + delta, minEnd), session.maxAllowedSourceEnd)
          let allowedMinTimeline = session.anchorActiveStart + TimelineClip.minDuration
          let allowedMaxTimeline = session.anchorActiveEnd + (session.maxAllowedSourceEnd - session.anchorEnd)
          let candidates = state
            .timelineSnapCandidates(excludingClipId: clip.id)
            .filter { $0.time >= allowedMinTimeline - 0.001 && $0.time <= allowedMaxTimeline + 0.001 }

          let sequenceEdge = session.anchorActiveEnd + (rawSourceEnd - session.anchorEnd)
          let snapped = VideoEditorTimelineSnapper.snap(
            time: sequenceEdge,
            candidates: candidates,
            pixelsPerSecond: pps,
            isDisabled: bypassSnap
          )
          state.timelineSnapGuide.update(snapped.target)
          let snappedSourceEnd = min(
            max(session.anchorEnd + (snapped.time - session.anchorActiveEnd), minEnd),
            session.maxAllowedSourceEnd
          )
          state.updateClip(id: clip.id, sourceEnd: snappedSourceEnd)
        }
      }
      .onEnded { _ in
        if drag?.didBeginTrimMutation == true {
          state.endClipTrim()
        }
        state.timelineSnapGuide.clear()
        drag = nil
        if isHoveringHandle {
          NSCursor.resizeLeftRight.set()
        } else if hoveredBodyClipId != nil {
          NSCursor.openHand.set()
        } else {
          NSCursor.arrow.set()
        }
      }
  }

  // MARK: - Select / Move / Reorder / Empty-Lane Scrub

  private func scrubTo(_ contentX: CGFloat) {
    let seconds = TimeInterval(contentX / max(pixelsPerSecond, 0.0001))
    state.scrub(to: CMTime(seconds: seconds, preferredTimescale: 600))
  }

  /// Clicking or dragging on empty video lane space (gaps between clips or above a
  /// longer audio track) scrubs the playhead smoothly instead of being dead space.
  private var emptyLaneScrubGesture: some Gesture {
    DragGesture(minimumDistance: 0, coordinateSpace: .named(Self.coordinateSpace))
      .onChanged { value in
        if !state.playbackState.isScrubbing {
          state.startScrubbing()
        }
        scrubTo(value.location.x)
      }
      .onEnded { value in
        scrubTo(value.location.x)
        state.endScrubbing()
      }
  }

  private func bodyGesture(_ placement: TimelineSequence.Placement) -> some Gesture {
    DragGesture(minimumDistance: 0, coordinateSpace: .named(Self.coordinateSpace))
      .onChanged { value in
        if drag == nil {
          drag = DragSession(
            clipId: placement.clip.id,
            fromIndex: placement.index,
            targetIndex: placement.index,
            anchorActiveStart: placement.activeStart,
            anchorActiveEnd: placement.activeEnd,
            anchorDuration: placement.clip.duration,
            anchorPixelsPerSecond: max(pixelsPerSecond, 0.0001),
            anchorPlacements: state.placements,
            resolvedStart: placement.activeStart,
            anchorX: value.location.x
          )
          // Select on press, not on release, so activation is deterministic.
          state.selectedAudioClipId = nil
          state.selectClip(id: placement.clip.id)
        }
        guard var session = drag, session.clipId == placement.clip.id, !session.isTrimming else { return }

        if !session.isMoving {
          guard abs(value.location.x - session.anchorX) > Self.dragThreshold else { return }
          session.isMoving = true
          NSCursor.closedHand.set()
        }

        let pps = session.anchorPixelsPerSecond
        let deltaSeconds = TimeInterval((value.location.x - session.anchorX) / pps)
        let rawStart = max(0, session.anchorActiveStart + deltaSeconds)
        let rawCenter = rawStart + session.anchorDuration / 2

        let candidateIndex = reorderTargetIndex(
          forCenter: rawCenter,
          fromIndex: session.fromIndex,
          in: session.anchorPlacements
        )

        if candidateIndex != session.fromIndex {
          // Crossing another clip's midpoint switches into reorder mode.
          session.isReordering = true
          session.targetIndex = candidateIndex
          session.resolvedStart = rawStart
          session.visualOffsetX = CGFloat(rawStart - session.anchorActiveStart) * pps
          state.timelineSnapGuide.clear()
        } else {
          // Moving freely in open timeline space without overlapping neighbours.
          session.isReordering = false
          session.targetIndex = session.fromIndex

          let bypassSnap = !state.isSnappingEnabled || VideoEditorTimelineSnapGuideState.isBypassKeyPressed
          let snapped = VideoEditorTimelineSnapper.snapRange(
            start: rawStart,
            duration: session.anchorDuration,
            candidates: state.timelineSnapCandidates(excludingClipId: placement.clip.id),
            pixelsPerSecond: pps,
            isDisabled: bypassSnap
          )

          let minStart = session.fromIndex > 0
            ? session.anchorPlacements[session.fromIndex - 1].activeEnd
            : 0
          let nextStart: TimeInterval? = (session.fromIndex + 1 < session.anchorPlacements.count)
            ? session.anchorPlacements[session.fromIndex + 1].activeStart
            : nil

          var clampedStart = max(minStart, snapped.start)
          if let nextStart {
            clampedStart = min(clampedStart, max(minStart, nextStart - session.anchorDuration))
          }

          if abs(clampedStart - snapped.start) < 0.001 {
            state.timelineSnapGuide.update(snapped.target)
          } else {
            state.timelineSnapGuide.clear()
          }

          session.resolvedStart = clampedStart
          session.visualOffsetX = CGFloat(clampedStart - session.anchorActiveStart) * pps
        }

        if drag != session {
          drag = session
        }
      }
      .onEnded { value in
        let endedSession = drag
        drag = nil
        state.timelineSnapGuide.clear()
        if isHoveringHandle {
          NSCursor.resizeLeftRight.set()
        } else if hoveredBodyClipId != nil {
          NSCursor.openHand.set()
        } else {
          NSCursor.arrow.set()
        }

        // A click on macOS can finish a zero-distance drag without `onChanged`.
        state.selectedAudioClipId = nil
        state.selectClip(id: placement.clip.id)

        guard let session = endedSession, session.clipId == placement.clip.id, !session.isTrimming else {
          guard endedSession == nil else { return }
          let seconds = TimeInterval(value.location.x / max(pixelsPerSecond, 0.0001))
          state.seek(to: CMTime(seconds: seconds, preferredTimescale: 600))
          return
        }

        if session.isReordering, session.targetIndex != session.fromIndex {
          state.moveClip(id: placement.clip.id, toIndex: session.targetIndex)
        } else if session.isMoving {
          state.moveClipOnTimeline(id: placement.clip.id, toActiveStart: session.resolvedStart)
        } else {
          // A plain click parks the playhead where you clicked.
          let seconds = TimeInterval(value.location.x / max(pixelsPerSecond, 0.0001))
          state.seek(to: CMTime(seconds: seconds, preferredTimescale: 600))
        }
      }
  }

  /// Target reorder index when the dragged clip's center crosses another clip's midpoint.
  /// Returns `fromIndex` while moving within open space so the clip repositions freely.
  private func reorderTargetIndex(
    forCenter centerTime: TimeInterval,
    fromIndex: Int,
    in placements: [TimelineSequence.Placement]
  ) -> Int {
    guard placements.count > 1, placements.indices.contains(fromIndex) else {
      return min(max(0, fromIndex), max(0, placements.count - 1))
    }
    var target = fromIndex
    for idx in stride(from: fromIndex - 1, through: 0, by: -1) {
      let mid = (placements[idx].activeStart + placements[idx].activeEnd) / 2
      if centerTime < mid {
        target = idx
      } else {
        break
      }
    }
    if target != fromIndex {
      return target
    }
    for idx in (fromIndex + 1) ..< placements.count {
      let mid = (placements[idx].activeStart + placements[idx].activeEnd) / 2
      if centerTime > mid {
        target = idx
      } else {
        break
      }
    }
    return target
  }

  // MARK: - Gap Overlays & Transition Seam Controls

  @ViewBuilder
  private func videoGapOverlay(_ gap: VideoEditorState.VideoTimelineGap) -> some View {
    let startX = x(for: gap.start)
    let endX = x(for: gap.end)
    let width = max(0, endX - startX)
    if width >= 14 {
      let isHovered = hoveredGapClipIndex == gap.clipIndex
      ZStack {
        Radius.rect(Radius.tile)
          .fill(Color.white.opacity(isHovered ? 0.08 : 0.03))
          .overlay(
            Radius.rect(Radius.tile)
              .strokeBorder(
                style: StrokeStyle(lineWidth: 1, dash: [4, 3])
              )
              .foregroundColor(Color.white.opacity(isHovered ? 0.35 : 0.14))
          )

        if width >= 30 {
          Button {
            state.closeGap(beforeClipIndex: gap.clipIndex)
          } label: {
            HStack(spacing: 3) {
              Image(systemName: "arrow.left.and.right")
                .font(.system(size: 8.5, weight: .bold))
              if width >= 84 {
                Text(L10n.VideoEditor.closeGap)
                  .font(.system(size: 9, weight: .semibold))
              }
            }
            .foregroundColor(.white.opacity(isHovered ? 0.96 : 0.72))
            .padding(.horizontal, width >= 84 ? 7 : 5)
            .padding(.vertical, 3)
            .background(
              Color.black.opacity(isHovered ? 0.75 : 0.48),
              in: Capsule(style: .continuous)
            )
            .overlay(
              Capsule(style: .continuous)
                .strokeBorder(Color.white.opacity(isHovered ? 0.35 : 0.14), lineWidth: 0.5)
            )
          }
          .buttonStyle(.plain)
          .opacity(isHovered || width >= 92 ? 1.0 : 0.65)
          .accessibilityLabel(L10n.VideoEditor.closeGap)
          .accessibilityIdentifier("video-editor.close-gap.\(gap.clipIndex)")
          .help(L10n.VideoEditor.closeGapHint(String(format: "%.1fs", gap.duration)))
        }
      }
      .frame(width: max(14, width - 2), height: trackHeight - 6)
      .offset(x: startX + 1)
      .onHover { hovering in
        if hovering {
          hoveredGapClipIndex = gap.clipIndex
        } else if hoveredGapClipIndex == gap.clipIndex {
          hoveredGapClipIndex = nil
        }
      }
      .contextMenu {
        Button {
          state.closeGap(beforeClipIndex: gap.clipIndex)
        } label: {
          Label(L10n.VideoEditor.closeThisGap, systemImage: "arrow.left.and.right")
        }

        if state.removableVideoGaps.count > 1 {
          Button {
            state.closeAllGaps()
          } label: {
            Label(L10n.VideoEditor.closeAllGaps, systemImage: "arrow.left.and.right")
          }
        }
      }
      .zIndex(0.5)
    }
  }

  @ViewBuilder
  private func transitionSeamButton(_ seam: VideoEditorState.AbuttingClipSeam) -> some View {
    let seamX = x(for: seam.cutTime)
    let isActive = seam.transition?.isActive == true
    let activeStyle = seam.transition?.style ?? .none
    let isPresented = Binding<Bool>(
      get: { transitionPopoverClipId == seam.incomingClipId },
      set: { showing in
        transitionPopoverClipId = showing ? seam.incomingClipId : nil
      }
    )

    return Button {
      transitionPopoverClipId = seam.incomingClipId
    } label: {
      Image(systemName: isActive ? activeStyle.systemImage : "diamond")
        .font(.system(size: isActive ? 9 : 8, weight: .bold))
        .foregroundColor(isActive ? .white : .white.opacity(0.78))
        .frame(width: 18, height: 18)
        .background(
          Circle()
            .fill(
              isActive
                ? (activeStyle == .crossfade ? Color.cyan.opacity(0.92) : Color.indigo.opacity(0.92))
                : Color.black.opacity(0.68)
            )
        )
        .overlay(
          Circle()
            .strokeBorder(Color.white.opacity(isActive ? 0.85 : 0.3), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.45), radius: 2, y: 1)
    }
    .buttonStyle(.plain)
    .background {
      if isActive, seam.effectiveDuration > 0.01 {
        let spanW = max(18, CGFloat(seam.effectiveDuration) * pixelsPerSecond)
        Radius.rect(Radius.ornament)
          .fill(
            (activeStyle == .crossfade ? Color.cyan : Color.indigo).opacity(0.28)
          )
          .overlay(
            Radius.rect(Radius.ornament)
              .strokeBorder(
                (activeStyle == .crossfade ? Color.cyan : Color.indigo).opacity(0.75),
                lineWidth: 1
              )
          )
          .frame(width: spanW, height: trackHeight - 10)
          .allowsHitTesting(false)
      }
    }
    .frame(width: 18, height: trackHeight)
    .accessibilityLabel(
      isActive
        ? L10n.VideoEditor.namedTransition(activeStyle.displayName)
        : L10n.VideoEditor.addTransition
    )
    .accessibilityIdentifier("video-editor.transition-seam.\(seam.incomingClipIndex)")
    .help(
      isActive
        ? L10n.VideoEditor.transitionActiveHint(
          activeStyle.displayName,
          String(format: "%.1fs", seam.effectiveDuration)
        )
        : L10n.VideoEditor.addTransitionHint
    )
    .popover(isPresented: isPresented, arrowEdge: .top) {
      transitionPopoverContent(for: seam)
    }
    .offset(x: seamX - 9)
    .zIndex(4)
  }

  private func transitionPopoverContent(for seam: VideoEditorState.AbuttingClipSeam) -> some View {
    let liveTransition = state.clips
      .first(where: { $0.id == seam.incomingClipId })?
      .leadingTransition
    let currentStyle = liveTransition?.style ?? .none
    let currentDuration = liveTransition?.duration ?? TimelineClipTransition.defaultDuration

    return VStack(alignment: .leading, spacing: 10) {
      HStack {
        Text(L10n.VideoEditor.clipTransition)
          .font(.system(size: 12, weight: .semibold))
          .foregroundColor(.primary)
        Spacer()
        Button {
          transitionPopoverClipId = nil
        } label: {
          Image(systemName: "xmark")
            .font(.system(size: 9.5, weight: .bold))
            .foregroundColor(.secondary)
            .frame(width: 20, height: 20)
            .background(Color.primary.opacity(0.08), in: Circle())
        }
        .buttonStyle(.plain)
        .keyboardShortcut(.cancelAction)
        .accessibilityLabel(L10n.VideoEditor.closeTransitionPopover)
        .help(L10n.Common.close)
      }

      HStack(spacing: 6) {
        ForEach(TimelineClipTransition.Style.allCases, id: \.self) { style in
          let selected = currentStyle == style
          Button {
            state.setClipTransition(
              clipId: seam.incomingClipId,
              style: style,
              duration: currentDuration
            )
          } label: {
            VStack(spacing: 4) {
              Image(systemName: style.systemImage)
                .font(.system(size: 13, weight: .semibold))
              Text(style.displayName)
                .font(.system(size: 10, weight: .medium))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            }
            .foregroundColor(selected ? .white : .primary)
            .frame(width: 72, height: 44)
            .background(
              Radius.rect(Radius.tile)
                .fill(selected ? Color.accentColor : Color.primary.opacity(0.08))
            )
          }
          .buttonStyle(.plain)
          .accessibilityLabel(L10n.VideoEditor.transitionOptionAccessibility(style.displayName))
        }
      }

      if currentStyle != .none {
        VStack(alignment: .leading, spacing: 5) {
          Text(L10n.Common.duration)
            .font(.system(size: 10.5, weight: .medium))
            .foregroundColor(.secondary)

          HStack(spacing: 5) {
            ForEach(TimelineClipTransition.presetDurations, id: \.self) { preset in
              let isPicked = abs(currentDuration - preset) < 0.05
              Button {
                state.setClipTransition(
                  clipId: seam.incomingClipId,
                  style: currentStyle,
                  duration: preset
                )
              } label: {
                Text(String(format: "%.1fs", preset))
                  .font(.system(size: 10.5, weight: .semibold).monospacedDigit())
                  .foregroundColor(isPicked ? .white : .primary)
                  .padding(.horizontal, 9)
                  .padding(.vertical, 4)
                  .background(
                    Capsule(style: .continuous)
                      .fill(isPicked ? Color.accentColor : Color.primary.opacity(0.08))
                  )
              }
              .buttonStyle(.plain)
            }
          }
        }
      }
    }
    .padding(12)
    .onExitCommand {
      transitionPopoverClipId = nil
    }
  }

  // MARK: - Context Menu

  @ViewBuilder
  private func contextMenu(_ placement: TimelineSequence.Placement) -> some View {
    Button {
      state.selectClip(id: placement.clip.id)
      state.splitAtPlayhead()
    } label: {
      Label(L10n.VideoEditor.splitAtPlayhead, systemImage: "scissors")
    }
    .disabled(!state.canSplitAtPlayhead)

    Button {
      let clipId = placement.clip.id
      Task { @MainActor in
        _ = await state.detachAudio(fromClipId: clipId)
      }
    } label: {
      Label(
        placement.clip.isAudioDetached ? L10n.VideoEditor.audioDetached : L10n.VideoEditor.detachAudio,
        systemImage: "waveform"
      )
    }
    .disabled(!state.canDetachAudio(forClipId: placement.clip.id))

    if placement.index > 0,
       let seam = state.abuttingClipSeams.first(where: { $0.incomingClipId == placement.clip.id }) {
      Menu {
        ForEach(TimelineClipTransition.Style.allCases, id: \.self) { style in
          Button {
            state.setClipTransition(
              clipId: seam.incomingClipId,
              style: style,
              duration: seam.transition?.duration ?? TimelineClipTransition.defaultDuration
            )
          } label: {
            Label(style.displayName, systemImage: style.systemImage)
          }
        }
      } label: {
        Label(L10n.VideoEditor.leadingTransition, systemImage: "square.split.2x1")
      }
    }

    if state.hasRemovableVideoGaps {
      Divider()

      if let gapBefore = state.removableVideoGaps.first(where: { $0.clipIndex == placement.index }) {
        Button {
          state.closeGap(beforeClipIndex: gapBefore.clipIndex)
        } label: {
          Label(L10n.VideoEditor.closeGapBeforeClip, systemImage: "arrow.left.and.right")
        }
      }

      Button {
        state.closeAllGaps()
      } label: {
        Label(L10n.VideoEditor.closeAllGaps, systemImage: "arrow.left.and.right")
      }
    }

    Divider()

    Button {
      state.moveClip(id: placement.clip.id, by: -1)
    } label: {
      Label(L10n.VideoEditor.moveClipLeft, systemImage: "arrow.left")
    }
    .disabled(placement.index == 0)

    Button {
      state.moveClip(id: placement.clip.id, by: 1)
    } label: {
      Label(L10n.VideoEditor.moveClipRight, systemImage: "arrow.right")
    }
    .disabled(placement.index >= state.clips.count - 1)

    Divider()

    Button(role: .destructive) {
      state.removeClip(id: placement.clip.id)
    } label: {
      Label(L10n.VideoEditor.removeClip, systemImage: "trash")
    }
    .disabled(state.clips.count <= 1)
  }

  private func tooltip(for clip: TimelineClip) -> String {
    clip.url?.lastPathComponent ?? L10n.VideoEditor.clipPrimaryLabel
  }
}
