//
//  VideoEditorCameraTimelineTrack.swift
//  Snapzy
//
//  "Camera" timeline track for Studio recordings with a camera: each block is a stretch
//  where the camera is hidden. Double-click the lane to hide the camera there, drag a
//  block (or its edges) to re-time it, right-click to show the camera again.
//

import AVFoundation
import SwiftUI

struct VideoEditorCameraTimelineTrack: View, Equatable {
  static func == (lhs: Self, rhs: Self) -> Bool {
    lhs.state === rhs.state && lhs.timelineWidth == rhs.timelineWidth
  }

  let state: VideoEditorState
  let timelineWidth: CGFloat
  @StateObject private var observation: VideoEditorTimelineObservation
  @State private var drag: DragState?

  private let trackHeight: CGFloat = 40
  private let blockHeight: CGFloat = 28
  private let edgeWidth: CGFloat = 6

  private struct DragState {
    enum Mode { case move, start, end }
    let id: UUID
    let mode: Mode
    let original: VideoEditorCameraSettings
  }

  init(state: VideoEditorState, timelineWidth: CGFloat) {
    self.state = state
    self.timelineWidth = timelineWidth
    _observation = StateObject(wrappedValue: VideoEditorTimelineObservation(state: state, surface: .camera))
  }

  var body: some View {
    let _ = observation.revision
    ZStack(alignment: .topLeading) {
      TimelineTrackLaneWell()
        .frame(height: trackHeight)
        .contentShape(Rectangle())
        .gesture(SpatialTapGesture(count: 2).onEnded { value in
          guard duration > 0 else { return }
          state.hideCamera(atSequence: value.location.x / timelineWidth * duration)
        })
        .help(L10n.VideoEditor.cameraTrackHint)
      HStack(spacing: 4) {
        Image(systemName: "person.crop.square").font(.system(size: 9))
        Text(L10n.VideoEditor.cameraSection).font(.system(size: 9, weight: .medium))
      }
      .foregroundColor(.secondary)
      .padding(.leading, 6)
      .frame(height: trackHeight)
      .allowsHitTesting(false)

      ForEach(pieces) { piece in
        block(piece)
      }
    }
    .frame(width: timelineWidth, height: trackHeight, alignment: .leading)
  }

  private var duration: TimeInterval { CMTimeGetSeconds(state.timelineDuration) }

  private var pieces: [VideoEditorSourceTrackLayout.Piece] {
    VideoEditorSourceTrackLayout.pieces(
      state.cameraSettings.hiddenRanges.map { ($0.id, $0.start, $0.end) },
      placements: state.placements,
      duration: duration,
      width: timelineWidth
    )
  }

  private func block(_ piece: VideoEditorSourceTrackLayout.Piece) -> some View {
    ZStack {
      TimelineSegmentChrome(
        height: blockHeight,
        baseColor: Color.gray.opacity(0.6),
        isDragging: drag?.id == piece.rangeID,
        cornerRadius: Radius.tile
      )
      Label(L10n.VideoEditor.cameraHidden, systemImage: "eye.slash")
        .font(.system(size: 10, weight: .medium))
        .foregroundColor(.white)
        .lineLimit(1)
        .padding(.horizontal, 6)
    }
    .frame(width: piece.width, height: blockHeight)
    .clipped()
    .contentShape(Rectangle())
    .offset(x: piece.x, y: (trackHeight - blockHeight) / 2)
    .gesture(dragGesture(piece))
    .contextMenu {
      Button(L10n.VideoEditor.cameraShowHere) { state.removeCameraHiddenRange(id: piece.rangeID) }
    }
  }

  private func dragGesture(_ piece: VideoEditorSourceTrackLayout.Piece) -> some Gesture {
    DragGesture(minimumDistance: 3)
      .onChanged { value in
        if drag == nil {
          let local = value.startLocation.x
          let mode: DragState.Mode = local < edgeWidth ? .start : (local > piece.width - edgeWidth ? .end : .move)
          drag = DragState(id: piece.rangeID, mode: mode, original: state.cameraSettings)
        }
        guard let drag, let original = drag.original.hiddenRanges.first(where: { $0.id == drag.id }) else { return }
        let delta = value.translation.width / timelineWidth * duration
        let minimum = VideoEditorCameraHiddenRange.minimumDuration
        switch drag.mode {
        case .move:
          let start = max(0, original.start + delta)
          state.updateCameraHiddenRange(id: drag.id, start: start, end: start + original.end - original.start, recordUndo: false)
        case .start:
          state.updateCameraHiddenRange(id: drag.id, start: min(original.start + delta, original.end - minimum), end: original.end, recordUndo: false)
        case .end:
          state.updateCameraHiddenRange(id: drag.id, start: original.start, end: max(original.end + delta, original.start + minimum), recordUndo: false)
        }
      }
      .onEnded { _ in
        if let drag { state.commitCameraSettings(from: drag.original) }
        drag = nil
      }
  }
}
