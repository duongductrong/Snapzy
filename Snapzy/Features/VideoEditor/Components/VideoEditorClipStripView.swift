//
//  VideoEditorClipStripView.swift
//  Snapzy
//
//  The timeline's content lane: one rounded block per clip in the sequence, laid
//  shoulder to shoulder. Replaces the old continuous filmstrip with hatched cut
//  regions punched into it — clips are now real objects you can select, drag to
//  reorder, trim from either edge, and delete.
//

import AppKit
import AVFoundation
import SwiftUI

struct VideoEditorClipStripView: View {
  @ObservedObject var state: VideoEditorState
  @ObservedObject var thumbnailCache: VideoEditorClipThumbnailCache
  @ObservedObject private var playbackState: VideoEditorPlaybackState

  let timelineWidth: CGFloat
  let trackHeight: CGFloat

  init(
    state: VideoEditorState,
    thumbnailCache: VideoEditorClipThumbnailCache,
    timelineWidth: CGFloat,
    trackHeight: CGFloat
  ) {
    _state = ObservedObject(wrappedValue: state)
    _thumbnailCache = ObservedObject(wrappedValue: thumbnailCache)
    _playbackState = ObservedObject(wrappedValue: state.playbackState)
    self.timelineWidth = timelineWidth
    self.trackHeight = trackHeight
  }

  /// Visual separation between neighbouring clips. Purely cosmetic — the blocks still
  /// occupy their exact time spans, the gap is taken out of each block's width.
  private static let clipGap: CGFloat = 3
  private static let handleWidth: CGFloat = 12
  /// Extra trim-handle reach, extending inward into the clip. Never extends
  /// outward past the edge, where it would swallow clicks meant for the
  /// neighbouring clip across a cut.
  private static let handleReach: CGFloat = 10
  /// Pointer travel before a press turns from "select" into "reorder".
  private static let reorderThreshold: CGFloat = 6
  private static let coordinateSpace = "VideoEditorClipStrip"

  @State private var drag: DragSession?

  /// One in-flight pointer gesture on a clip body.
  private struct DragSession {
    let clipId: UUID
    let fromIndex: Int
    var translation: CGFloat = 0
    /// Stays false until the pointer passes `reorderThreshold`, which keeps a plain
    /// click behaving as select-and-seek rather than a zero-distance reorder.
    var isReordering = false
    /// A drag on a single-clip sequence scrubs the playhead — there is nothing
    /// to reorder yet, so horizontal travel means "move the playhead with me".
    var isScrubbing = false
    /// Set by an edge-handle trim drag so body gestures leave the session alone.
    var isTrimming = false
    var targetIndex: Int
    /// In/out points as they stood when a trim drag began. Translation is cumulative,
    /// so it must be applied to a fixed anchor rather than to the live clip — which
    /// SwiftUI may have already re-rendered mid-gesture.
    var anchorStart: TimeInterval = 0
    var anchorEnd: TimeInterval = 0
    /// Pointer x in the strip's stable coordinate space when the trim drag began.
    /// Measured here rather than in the handle's own space: the handle repositions
    /// on every tick, so a local measurement would feed back into itself and jitter.
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
    ZStack(alignment: .leading) {
      Color.black.opacity(0.2)

      if state.isExtractingFrames, state.frameThumbnails.isEmpty {
        loadingRow
      } else {
        ForEach(state.placements) { placement in
          clipBlock(placement)
        }
      }
    }
    .frame(width: timelineWidth, height: trackHeight, alignment: .leading)
    .coordinateSpace(name: Self.coordinateSpace)
    .onAppear { preloadInsertedThumbnails() }
    .onChange(of: state.clips) { _ in preloadInsertedThumbnails() }
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

  // MARK: - Clip Block

  @ViewBuilder
  private func clipBlock(_ placement: TimelineSequence.Placement) -> some View {
    let clip = placement.clip
    let isSelected = state.selectedClipId == clip.id
    let isDragging = drag?.clipId == clip.id && drag?.isReordering == true

    let rawWidth = x(for: placement.end) - x(for: placement.start)
    let width = max(6, rawWidth - Self.clipGap)
    let offsetX = x(for: placement.start) + Self.clipGap / 2

    ZStack(alignment: .leading) {
      thumbnails(for: clip, blockWidth: width)

      inactiveClipChrome(clip, width: width)

      if !clip.isPrimary {
        insertedClipChrome(clip, width: width)
      }

      Radius.rect(Radius.tile)
        .strokeBorder(
          isSelected ? Color.yellow : Color.white.opacity(0.16),
          lineWidth: isSelected ? 2.5 : 1
        )
        .allowsHitTesting(false)
    }
    .frame(width: width, height: trackHeight)
    .clipShape(Radius.rect(Radius.tile))
    // The thumbnail cells are visual content only. Keep the entire clip block as
    // one reliable pointer target, including cells whose image has transparent
    // or empty areas.
    .contentShape(Rectangle())
    .overlay(alignment: .leading) {
      if isSelected {
        trimHandle(clip: clip, isLeading: true)
          .offset(x: activeLeadingOffset(for: clip, width: width))
      }
    }
    .overlay(alignment: .trailing) {
      if isSelected {
        trimHandle(clip: clip, isLeading: false)
          .offset(x: -(width - activeTrailingOffset(for: clip, width: width)))
      }
    }
    .shadow(color: .black.opacity(isDragging ? 0.5 : 0), radius: isDragging ? 8 : 0)
    .opacity(isDragging ? 0.85 : 1)
    .offset(x: offsetX + (isDragging ? (drag?.translation ?? 0) : 0))
    .zIndex(isDragging ? 2 : (isSelected ? 1 : 0))
    .gesture(bodyGesture(placement))
    .contextMenu { contextMenu(placement) }
    .help(tooltip(for: clip))
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
          .padding(4)
      }
    }
    .allowsHitTesting(false)
  }

  /// Dim the portions outside the active in/out points while preserving their
  /// original slot. This makes re-extension visible without moving neighbours.
  @ViewBuilder
  private func inactiveClipChrome(_ clip: TimelineClip, width: CGFloat) -> some View {
    if clip.slotDuration > 0 {
      let leadingWidth = width * CGFloat(max(0, clip.sourceStart - clip.slotStart) / clip.slotDuration)
      let trailingWidth = width * CGFloat(max(0, clip.slotEnd - clip.sourceEnd) / clip.slotDuration)

      ZStack(alignment: .leading) {
        if leadingWidth > 0.5 {
          LinearGradient(
            colors: [Color.black.opacity(0.66), Color.black.opacity(0.42)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
          )
          .frame(width: leadingWidth, height: trackHeight)
        }

        if trailingWidth > 0.5 {
          LinearGradient(
            colors: [Color.black.opacity(0.42), Color.black.opacity(0.66)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
          )
          .frame(width: trailingWidth, height: trackHeight)
          .offset(x: width - trailingWidth)
        }
      }
      .frame(width: width, height: trackHeight, alignment: .leading)
      .allowsHitTesting(false)
    } else {
      EmptyView()
    }
  }

  private func activeLeadingOffset(for clip: TimelineClip, width: CGFloat) -> CGFloat {
    guard clip.slotDuration > 0 else { return 0 }
    return width * CGFloat(max(0, clip.sourceStart - clip.slotStart) / clip.slotDuration)
  }

  private func activeTrailingOffset(for clip: TimelineClip, width: CGFloat) -> CGFloat {
    guard clip.slotDuration > 0 else { return width }
    return width * CGFloat(max(0, clip.sourceEnd - clip.slotStart) / clip.slotDuration)
  }

  // MARK: - Thumbnails

  /// Frames for a clip's source window.
  ///
  /// The full source strip is laid out at the clip's slot scale and then shifted left
  /// by the slot start, so each frame stays under the moment it belongs to no matter
  /// how the active range is trimmed.
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
      let scale = clip.slotDuration > 0 ? blockWidth / CGFloat(clip.slotDuration) : 0
      let fullWidth = max(blockWidth, scale * CGFloat(clip.sourceDuration))
      let cellWidth = fullWidth / CGFloat(images.count)

      HStack(spacing: 0) {
        ForEach(images.indices, id: \.self) { index in
          Image(nsImage: images[index])
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: cellWidth, height: trackHeight)
        }
      }
      .frame(width: fullWidth, alignment: .leading)
      .offset(x: -scale * CGFloat(clip.slotStart))
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

  /// Yellow chevron handles matching the editor's original trim affordance. Dragging
  /// one moves the clip's in/out point within its own source asset, so material
  /// trimmed away earlier comes back when you pull outward.
  ///
  /// The grab area extends inward into the clip. The old symmetric bleed reached
  /// 6 px outward, swallowing clicks meant for the neighbouring clip.
  private func trimHandle(clip: TimelineClip, isLeading: Bool) -> some View {
    let visual = Radius.rect(Radius.ornament)
      .fill(Color.yellow)
      .frame(width: Self.handleWidth, height: trackHeight)
      .overlay(
        Image(systemName: isLeading ? "chevron.compact.left" : "chevron.compact.right")
          .font(.system(size: 15, weight: .bold))
          .foregroundColor(.black.opacity(0.55))
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
    .highPriorityGesture(trimGesture(clip: clip, isLeading: isLeading))
    .onHover { hovering in
      if hovering { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
    }
    .help(isLeading ? L10n.VideoEditor.clipTrimStartHint : L10n.VideoEditor.clipTrimEndHint)
  }

  private func trimGesture(clip: TimelineClip, isLeading: Bool) -> some Gesture {
    // A small travel minimum keeps a jittery click from nudging the in/out point.
    // The named space is the strip itself, which never moves — the handle does
    // (its offset tracks the active edge on every tick), and measuring there
    // would make the drag's own output corrupt its input.
    DragGesture(minimumDistance: 3, coordinateSpace: .named(Self.coordinateSpace))
      .onChanged { value in
        if drag == nil {
          state.beginClipTrim(id: clip.id)
          drag = DragSession(
            clipId: clip.id,
            fromIndex: 0,
            isTrimming: true,
            targetIndex: 0,
            anchorStart: clip.sourceStart,
            anchorEnd: clip.sourceEnd,
            anchorX: value.location.x
          )
        }
        guard var session = drag, session.clipId == clip.id, session.isTrimming, pixelsPerSecond > 0 else { return }

        let delta = TimeInterval((value.location.x - session.anchorX) / pixelsPerSecond)
        if isLeading {
          state.updateClip(id: clip.id, sourceStart: session.anchorStart + delta)
        } else {
          state.updateClip(id: clip.id, sourceEnd: session.anchorEnd + delta)
        }
        drag = session
      }
      .onEnded { _ in
        state.endClipTrim()
        drag = nil
      }
  }

  // MARK: - Select / Reorder / Scrub

  /// One clip on the sequence — nothing to reorder, so drags scrub the playhead.
  private var isSingleClipSequence: Bool {
    state.placements.count <= 1
  }

  private func scrubTo(_ contentX: CGFloat) {
    let seconds = TimeInterval(contentX / max(pixelsPerSecond, 0.0001))
    state.scrub(to: CMTime(seconds: seconds, preferredTimescale: 600))
  }

  private func bodyGesture(_ placement: TimelineSequence.Placement) -> some Gesture {
    DragGesture(minimumDistance: 0, coordinateSpace: .named(Self.coordinateSpace))
      .onChanged { value in
        if drag == nil {
          drag = DragSession(
            clipId: placement.clip.id,
            fromIndex: placement.index,
            targetIndex: placement.index
          )
          // Select on press, not on release, so activation is deterministic —
          // a click the system reports only as "ended" still selects the clip.
          state.selectClip(id: placement.clip.id)
        }
        guard var session = drag, session.clipId == placement.clip.id, !session.isTrimming else { return }

        session.translation = value.translation.width
        if session.isScrubbing {
          scrubTo(value.location.x)
        } else if !session.isReordering, abs(value.translation.width) > Self.reorderThreshold {
          if isSingleClipSequence {
            // Nothing to reorder yet: the drag scrubs the playhead instead.
            session.isScrubbing = true
            state.startScrubbing()
            scrubTo(value.location.x)
          } else {
            session.isReordering = true
            session.targetIndex = dropIndex(for: placement, translation: value.translation.width)
          }
        } else if session.isReordering {
          session.targetIndex = dropIndex(for: placement, translation: value.translation.width)
        }
        drag = session
      }
      .onEnded { value in
        defer { drag = nil }
        // A click on macOS can finish a zero-distance drag without giving the
        // gesture an `onChanged` callback. Selection must therefore also happen
        // on release; otherwise the click still seeks but leaves the old clip's
        // trim handles visible.
        state.selectClip(id: placement.clip.id)

        guard let session = drag, session.clipId == placement.clip.id, !session.isTrimming else {
          // No session means this was a plain click that only produced `onEnded`.
          guard drag == nil else { return }
          let seconds = TimeInterval(value.location.x / max(pixelsPerSecond, 0.0001))
          state.seek(to: CMTime(seconds: seconds, preferredTimescale: 600))
          return
        }

        if session.isScrubbing {
          state.endScrubbing()
        } else if session.isReordering {
          state.moveClip(id: placement.clip.id, toIndex: session.targetIndex)
        } else {
          // A plain click parks the playhead where you clicked.
          let seconds = TimeInterval(value.location.x / max(pixelsPerSecond, 0.0001))
          state.seek(to: CMTime(seconds: seconds, preferredTimescale: 600))
        }
      }
  }

  /// Index the dragged clip lands on: whichever clip currently contains the dragged
  /// block's centre.
  private func dropIndex(for placement: TimelineSequence.Placement, translation: CGFloat) -> Int {
    let centre = x(for: placement.start) + (x(for: placement.end) - x(for: placement.start)) / 2
    let moved = centre + translation
    let seconds = TimeInterval(moved / max(pixelsPerSecond, 0.0001))

    guard let hit = state.placement(atSequence: seconds) else {
      return translation < 0 ? 0 : max(0, state.clips.count - 1)
    }
    return hit.index
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
